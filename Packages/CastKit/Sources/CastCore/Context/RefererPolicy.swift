import Foundation

/// Reproduces the browser default referrer policy (`strict-origin-when-cross-origin`).
public enum RefererPolicy {
    /// `scheme://host[:port]`, default ports omitted.
    public static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        var result = "\(scheme)://\(host)"
        if let port = url.port, !(scheme == "http" && port == 80), !(scheme == "https" && port == 443) {
            result += ":\(port)"
        }
        return result
    }

    public static func isSameOrigin(_ a: URL, _ b: URL) -> Bool {
        guard let originA = origin(of: a), let originB = origin(of: b) else { return false }
        return originA == originB
    }

    public static func referer(frameURL: URL, requestURL: URL) -> String? {
        guard let frameScheme = frameURL.scheme?.lowercased(), frameScheme == "http" || frameScheme == "https" else {
            return nil
        }
        if frameScheme == "https" && requestURL.scheme?.lowercased() == "http" { return nil }
        if isSameOrigin(frameURL, requestURL) { return stripped(frameURL) }
        guard let frameOrigin = origin(of: frameURL) else { return nil }
        return frameOrigin + "/"
    }

    static func stripped(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.string ?? url.absoluteString
    }
}
