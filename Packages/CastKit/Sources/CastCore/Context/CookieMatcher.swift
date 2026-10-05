import Foundation

/// A cookie as stored by the in-app browser (copied from `WKHTTPCookieStore`).
public struct CookieRecord: Codable, Hashable, Sendable {
    public var name: String
    public var value: String
    public var domain: String
    public var path: String
    public var isSecure: Bool
    public var expiresAt: Date?

    public init(name: String, value: String, domain: String, path: String = "/", isSecure: Bool = false, expiresAt: Date? = nil) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.isSecure = isSecure
        self.expiresAt = expiresAt
    }
}

/// Builds the `Cookie` header a browser would send for a URL.
public enum CookieMatcher {
    public static func cookieHeader(for url: URL, cookies: [CookieRecord], now: Date = Date()) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let isSecureRequest = url.scheme?.lowercased() == "https"
        let path = url.path.isEmpty ? "/" : url.path

        let matching = cookies.enumerated().filter { _, cookie in
            if let expiry = cookie.expiresAt, expiry <= now { return false }
            if cookie.isSecure && !isSecureRequest { return false }
            return domainMatches(host: host, cookieDomain: cookie.domain)
                && pathMatches(path: path, cookiePath: cookie.path)
        }
        guard !matching.isEmpty else { return nil }

        let ordered = matching.sorted { lhs, rhs in
            if lhs.element.path.count != rhs.element.path.count {
                return lhs.element.path.count > rhs.element.path.count
            }
            return lhs.offset < rhs.offset
        }
        return ordered.map { "\($0.element.name)=\($0.element.value)" }.joined(separator: "; ")
    }

    static func domainMatches(host: String, cookieDomain: String) -> Bool {
        var domain = cookieDomain.lowercased()
        if domain.hasPrefix(".") { domain.removeFirst() }
        guard !domain.isEmpty else { return false }
        return host == domain || host.hasSuffix("." + domain)
    }

    static func pathMatches(path: String, cookiePath: String) -> Bool {
        let cookiePath = cookiePath.isEmpty ? "/" : cookiePath
        if path == cookiePath { return true }
        guard path.hasPrefix(cookiePath) else { return false }
        return cookiePath.hasSuffix("/") || path.dropFirst(cookiePath.count).first == "/"
    }
}
