import Foundation

/// Computes the request context (Referer, Origin, User-Agent, Cookie) a browser
/// would have used for a media request seen in a given frame.
public enum ContextBuilder {
    static let networkVias: Set<String> = ["fetch", "xhr", "perf"]

    public static func make(requestURL: URL, frameURL: URL?, via: String?, userAgent: String?,
                            cookies: [CookieRecord], now: Date = Date()) -> RequestContext {
        var context = RequestContext()
        context.userAgent = userAgent
        context.cookie = CookieMatcher.cookieHeader(for: requestURL, cookies: cookies, now: now)
        if let frameURL {
            context.referer = RefererPolicy.referer(frameURL: frameURL, requestURL: requestURL)
            if let via, networkVias.contains(via), !RefererPolicy.isSameOrigin(frameURL, requestURL) {
                context.origin = RefererPolicy.origin(of: frameURL)
            }
        }
        return context
    }
}
