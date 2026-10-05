import Foundation
import Darwin
import CastCore

/// SSDP search over BSD sockets. Without Apple's multicast entitlement (free accounts),
/// iOS refuses multicast, so the scanner also sends a unicast M-SEARCH to every host
/// of the local subnet; most TV UPnP stacks answer those too.
public final class SSDPScanner: @unchecked Sendable {
    public init() {}

    public func scan(hosts: [String], localAddress: String?, includeMulticast: Bool,
                     listen: TimeInterval = 3) async -> [SSDP.Response] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[SSDP.Response], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let found = Self.blockingScan(hosts: hosts, localAddress: localAddress,
                                              includeMulticast: includeMulticast, listen: listen)
                continuation.resume(returning: found)
            }
        }
    }

    static func blockingScan(hosts: [String], localAddress: String?, includeMulticast: Bool,
                             listen: TimeInterval) -> [SSDP.Response] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            castLog("ssdp", "socket() impossible (errno \(errno))")
            return []
        }
        defer { close(fd) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 0, tv_usec: 200_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = 0
        local.sin_addr.s_addr = localAddress.map { inet_addr($0) } ?? INADDR_ANY
        let bound = withUnsafePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bound != 0 {
            castLog("ssdp", "bind() impossible (errno \(errno)), envoi depuis l'adresse par défaut")
        }

        var responses: [String: SSDP.Response] = [:]
        var buffer = [UInt8](repeating: 0, count: 8192)
        var sendFailures = 0

        func send(_ text: String, to host: String) {
            var destination = sockaddr_in()
            destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            destination.sin_family = sa_family_t(AF_INET)
            destination.sin_port = in_port_t(SSDP.port).bigEndian
            destination.sin_addr.s_addr = inet_addr(host)
            let bytes = Array(text.utf8)
            let sent = withUnsafePointer(to: &destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if sent < 0 { sendFailures += 1 }
        }

        let capacity = buffer.count

        func drain(until deadline: Date) {
            repeat {
                let count = recv(fd, &buffer, capacity, 0)
                if count > 0 {
                    let text = String(decoding: buffer[0..<count], as: UTF8.self)
                    if let response = SSDP.parseResponse(text) {
                        responses[response.location.absoluteString] = response
                    }
                } else if Date() >= deadline {
                    return
                }
            } while Date() < deadline
        }

        let targets = [SSDP.mediaRendererST, SSDP.rootDeviceST]
        for _ in 0..<2 {
            if includeMulticast {
                for target in targets {
                    send(SSDP.searchRequest(host: SSDP.multicastHost, st: target, mx: 1), to: SSDP.multicastHost)
                }
            }
            for (index, host) in hosts.enumerated() {
                for target in targets {
                    send(SSDP.searchRequest(host: host, st: target, mx: 1), to: host)
                }
                if index % 32 == 31 {
                    drain(until: Date().addingTimeInterval(0.02))
                }
            }
            drain(until: Date().addingTimeInterval(0.3))
        }
        drain(until: Date().addingTimeInterval(listen))
        castLog("ssdp", "Balayage de \(hosts.count) adresses : \(responses.count) réponse(s), \(sendFailures) envoi(s) refusé(s)")
        return Array(responses.values)
    }
}
