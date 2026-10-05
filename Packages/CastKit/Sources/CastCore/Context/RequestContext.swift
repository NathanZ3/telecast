import Foundation

/// The browser-like headers a site expects when its media is requested.
public struct RequestContext: Codable, Hashable, Sendable {
    public var referer: String?
    public var origin: String?
    public var userAgent: String?
    public var cookie: String?

    public init(referer: String? = nil, origin: String? = nil, userAgent: String? = nil, cookie: String? = nil) {
        self.referer = referer
        self.origin = origin
        self.userAgent = userAgent
        self.cookie = cookie
    }

    public static let none = RequestContext()

    /// Header fields to send upstream (only the non-empty ones).
    public var headerFields: [String: String] {
        var fields: [String: String] = [:]
        if let referer, !referer.isEmpty { fields["Referer"] = referer }
        if let origin, !origin.isEmpty { fields["Origin"] = origin }
        if let userAgent, !userAgent.isEmpty { fields["User-Agent"] = userAgent }
        if let cookie, !cookie.isEmpty { fields["Cookie"] = cookie }
        return fields
    }
}
