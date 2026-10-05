import XCTest
import Darwin
@testable import CastCore
@testable import CastNet

final class SSDPScannerTests: XCTestCase {
    /// A fake TV answering unicast M-SEARCH on 127.0.0.1:1900.
    func startResponder(location: String) throws -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw XCTSkip("socket() failed") }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(1900).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else {
            close(fd)
            throw XCTSkip("port 1900 unavailable on this machine")
        }
        DispatchQueue.global().async {
            var buffer = [UInt8](repeating: 0, count: 2048)
            let capacity = buffer.count
            var sender = sockaddr_in()
            var senderLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            for _ in 0..<8 {
                let count = withUnsafeMutablePointer(to: &sender) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(fd, &buffer, capacity, 0, $0, &senderLength)
                    }
                }
                guard count > 0 else { return }
                let reply = Array("HTTP/1.1 200 OK\r\nLOCATION: \(location)\r\nST: \(SSDP.mediaRendererST)\r\nUSN: uuid:fake\r\n\r\n".utf8)
                _ = withUnsafePointer(to: &sender) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, reply, reply.count, 0, $0, senderLength)
                    }
                }
            }
        }
        return fd
    }

    func testUnicastSweepFindsResponder() async throws {
        let fd = try startResponder(location: "http://127.0.0.1:49152/description.xml")
        defer { close(fd) }
        let responses = await SSDPScanner().scan(hosts: ["127.0.0.1"], localAddress: nil, includeMulticast: false, listen: 1)
        XCTAssertEqual(responses.first?.location.absoluteString, "http://127.0.0.1:49152/description.xml")
    }

    func testInterfacesAreWellFormed() {
        for interface in NetworkInterfaces.all() {
            XCTAssertNotNil(SubnetMath.parse(interface.address), interface.address)
            XCTAssertNotNil(SubnetMath.parse(interface.netmask), interface.netmask)
        }
    }
}
