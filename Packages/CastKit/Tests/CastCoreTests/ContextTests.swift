import XCTest
@testable import CastCore

final class ContextTests: XCTestCase {
    private func url(_ string: String) -> URL { URL(string: string)! }

    func testRefererSameOriginKeepsPathAndQueryWithoutFragment() {
        let referer = RefererPolicy.referer(frameURL: url("https://e.com/p?a=1#f"), requestURL: url("https://e.com/v.m3u8"))
        XCTAssertEqual(referer, "https://e.com/p?a=1")
    }

    func testRefererCrossOriginIsOriginOnly() {
        let referer = RefererPolicy.referer(frameURL: url("https://embed.io/e/42"), requestURL: url("https://cdn.net/x.m3u8"))
        XCTAssertEqual(referer, "https://embed.io/")
    }

    func testRefererDowngradeIsOmitted() {
        XCTAssertNil(RefererPolicy.referer(frameURL: url("https://e.com/"), requestURL: url("http://e.com/v.mp4")))
    }

    func testOriginKeepsNonDefaultPort() {
        XCTAssertEqual(RefererPolicy.origin(of: url("http://127.0.0.1:8080/x")), "http://127.0.0.1:8080")
        XCTAssertEqual(RefererPolicy.origin(of: url("https://E.com:443/x")), "https://e.com")
    }

    func testCookieDomainSecurePathAndExpiry() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cookies = [
            CookieRecord(name: "a", value: "1", domain: ".e.com"),
            CookieRecord(name: "s", value: "x", domain: "e.com", isSecure: true),
            CookieRecord(name: "old", value: "0", domain: "e.com", expiresAt: now.addingTimeInterval(-1)),
            CookieRecord(name: "api", value: "k", domain: "e.com", path: "/api"),
            CookieRecord(name: "b", value: "2", domain: "e.com", path: "/video"),
        ]
        XCTAssertEqual(CookieMatcher.cookieHeader(for: url("https://v.e.com/x"), cookies: cookies, now: now), "a=1; s=x")
        XCTAssertEqual(CookieMatcher.cookieHeader(for: url("http://v.e.com/x"), cookies: cookies, now: now), "a=1")
        XCTAssertEqual(CookieMatcher.cookieHeader(for: url("https://e.com/video/1"), cookies: cookies, now: now), "b=2; a=1; s=x")
        XCTAssertNil(CookieMatcher.cookieHeader(for: url("https://other.com/"), cookies: cookies, now: now))
    }

    func testContextBuilderAddsOriginOnlyForCrossOriginNetworkRequests() {
        let frame = url("https://embed.io/e/42")
        let request = url("https://cdn.net/master.m3u8")
        let xhr = ContextBuilder.make(requestURL: request, frameURL: frame, via: "xhr", userAgent: "UA", cookies: [])
        XCTAssertEqual(xhr.origin, "https://embed.io")
        XCTAssertEqual(xhr.referer, "https://embed.io/")
        XCTAssertEqual(xhr.userAgent, "UA")
        XCTAssertNil(xhr.cookie)

        let element = ContextBuilder.make(requestURL: request, frameURL: frame, via: "video-src", userAgent: "UA", cookies: [])
        XCTAssertNil(element.origin)

        let sameOrigin = ContextBuilder.make(requestURL: url("https://embed.io/v.m3u8"), frameURL: frame, via: "fetch",
                                             userAgent: nil, cookies: [])
        XCTAssertNil(sameOrigin.origin)
    }

    func testHeaderFieldsSkipEmptyValues() {
        let context = RequestContext(referer: "https://a/", origin: "", userAgent: "UA", cookie: nil)
        XCTAssertEqual(context.headerFields, ["Referer": "https://a/", "User-Agent": "UA"])
        XCTAssertEqual(RequestContext.none.headerFields, [:])
    }
}
