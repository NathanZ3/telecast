import Foundation

/// Request line + headers of an HTTP/1.1 request received by the relay.
public struct HTTPRequestHead: Equatable, Sendable {
    public var method: String
    public var target: String
    public var path: String
    /// Header names are lowercased.
    public var headers: [String: String]

    public init(method: String, target: String, headers: [String: String]) {
        self.method = method
        self.target = target
        self.headers = headers
        if target.lowercased().hasPrefix("http"), let url = URL(string: target) {
            self.path = url.path.isEmpty ? "/" : url.path
        } else {
            self.path = String(target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? "/")
        }
    }

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

public enum HTTPRequestParser {
    static let terminator = Data("\r\n\r\n".utf8)

    /// Index just after the blank line ending the header block.
    public static func headerEnd(in data: Data) -> Int? {
        guard let range = data.range(of: terminator) else { return nil }
        return range.upperBound
    }

    public static func parse(_ data: Data) -> HTTPRequestHead? {
        let end = headerEnd(in: data) ?? data.count
        let block = data.prefix(end)
        guard let text = String(data: block, encoding: .utf8) ?? String(data: block, encoding: .isoLatin1) else {
            return nil
        }
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { headers[name] = value }
        }
        return HTTPRequestHead(method: String(parts[0]).uppercased(), target: String(parts[1]), headers: headers)
    }
}

/// Status line + headers of a relay response.
public struct HTTPResponseHead: Sendable {
    public var status: Int
    public var headers: [(String, String)]

    public init(status: Int, headers: [(String, String)] = []) {
        self.status = status
        self.headers = headers
    }

    public func serialized() -> Data {
        var text = "HTTP/1.1 \(status) \(Self.reason(for: status))\r\n"
        for (name, value) in headers {
            text += "\(name): \(value)\r\n"
        }
        text += "\r\n"
        return Data(text.utf8)
    }

    public static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 206: return "Partial Content"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 416: return "Range Not Satisfiable"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default: return "Status"
        }
    }
}
