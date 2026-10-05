import Foundation

/// IPv4 helpers used to sweep the local network for TVs.
public enum SubnetMath {
    /// Host addresses of the subnet containing `address`, without the network address,
    /// the broadcast address and `address` itself. Subnets larger than a /24 are narrowed
    /// to the /24 around `address` so a sweep stays short.
    public static func hosts(address: String, netmask: String, limit: Int = 254) -> [String] {
        guard let ip = parse(address), let mask = parse(netmask) else { return [] }
        let effectiveMask: UInt32 = mask.nonzeroBitCount < 24 ? 0xFFFF_FF00 : mask
        let network = ip & effectiveMask
        let broadcast = network | ~effectiveMask
        guard broadcast > network + 1 else { return [] }

        var result: [String] = []
        var current = network + 1
        while current < broadcast && result.count < limit {
            if current != ip { result.append(format(current)) }
            current += 1
        }
        return result
    }

    public static func parse(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard let byte = UInt8(part) else { return nil }
            value = (value << 8) | UInt32(byte)
        }
        return value
    }

    public static func format(_ value: UInt32) -> String {
        "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }
}
