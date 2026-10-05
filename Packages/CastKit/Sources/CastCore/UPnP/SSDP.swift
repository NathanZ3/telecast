import Foundation

/// Simple Service Discovery Protocol helpers (UPnP device discovery).
public enum SSDP {
    public static let multicastHost = "239.255.255.250"
    public static let port: UInt16 = 1900
    public static let mediaRendererST = "urn:schemas-upnp-org:device:MediaRenderer:1"
    public static let rootDeviceST = "upnp:rootdevice"

    /// An `M-SEARCH` request. `host` is the multicast group or, for a unicast sweep, the target IP.
    public static func searchRequest(host: String, st: String, mx: Int = 1) -> String {
        "M-SEARCH * HTTP/1.1\r\n"
            + "HOST: \(host):\(port)\r\n"
            + "MAN: \"ssdp:discover\"\r\n"
            + "MX: \(mx)\r\n"
            + "ST: \(st)\r\n"
            + "USER-AGENT: iOS/17 UPnP/1.1 TeleCast/1.0\r\n"
            + "\r\n"
    }

    public struct Response: Equatable, Sendable {
        public var location: URL
        public var usn: String?
        public var st: String?
        public var server: String?

        public init(location: URL, usn: String?, st: String?, server: String?) {
            self.location = location
            self.usn = usn
            self.st = st
            self.server = server
        }
    }

    /// Parses a search response (or a `NOTIFY`) and returns its `LOCATION`.
    public static func parseResponse(_ text: String) -> Response? {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
        guard let first = lines.first?.uppercased(), first.hasPrefix("HTTP/") || first.hasPrefix("NOTIFY") else {
            return nil
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        guard let raw = headers["LOCATION"], let location = URL(string: raw), location.host != nil else { return nil }
        return Response(location: location, usn: headers["USN"], st: headers["ST"] ?? headers["NT"], server: headers["SERVER"])
    }
}
