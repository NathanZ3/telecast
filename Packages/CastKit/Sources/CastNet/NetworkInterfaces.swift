import Foundation
import Darwin

public struct IPv4Interface: Equatable, Sendable {
    public var name: String
    public var address: String
    public var netmask: String

    public init(name: String, address: String, netmask: String) {
        self.name = name
        self.address = address
        self.netmask = netmask
    }
}

/// Active IPv4 interfaces of the device (the TV must reach the phone through the Wi-Fi one).
public enum NetworkInterfaces {
    public static func all() -> [IPv4Interface] {
        var result: [IPv4Interface] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            cursor = current.pointee.ifa_next
            let flags = Int32(truncatingIfNeeded: current.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let address = current.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                  let mask = current.pointee.ifa_netmask,
                  let addressText = ipv4String(address), let maskText = ipv4String(mask) else {
                continue
            }
            if addressText.hasPrefix("169.254.") { continue }
            result.append(IPv4Interface(name: String(cString: current.pointee.ifa_name),
                                        address: addressText, netmask: maskText))
        }
        return result
    }

    /// Wi-Fi first (`en0` on iPhone), then any other active interface.
    public static func wifi() -> IPv4Interface? {
        let interfaces = all()
        return interfaces.first { $0.name == "en0" }
            ?? interfaces.first { $0.name.hasPrefix("en") }
            ?? interfaces.first
    }

    static func ipv4String(_ pointer: UnsafeMutablePointer<sockaddr>) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        let converted: Bool = pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { socketAddress in
            var address = socketAddress.pointee.sin_addr
            return buffer.withUnsafeMutableBufferPointer { output in
                inet_ntop(AF_INET, &address, output.baseAddress, socklen_t(INET_ADDRSTRLEN)) != nil
            }
        }
        guard converted else { return nil }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }
}
