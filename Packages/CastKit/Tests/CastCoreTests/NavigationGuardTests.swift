import XCTest
@testable import CastCore

final class NavigationGuardTests: XCTestCase {
    let ads = AdHostMatcher(domains: ["popads.net"])
    let current = URL(string: "https://streaming.site/film/42")!
    let t0 = Date(timeIntervalSince1970: 1000)

    func url(_ string: String) -> URL { URL(string: string)! }

    func testAdHostsAndBadSchemes() {
        var guardrail = NavigationGuard(adMatcher: ads)
        XCTAssertEqual(guardrail.decide(url: url("https://x.popads.net/a"), isMainFrame: true, kind: .linkActivated,
                                        currentURL: current, now: t0), .block(.adHost("x.popads.net")))
        XCTAssertEqual(guardrail.decide(url: url("itms-apps://apps.apple.com/app/1"), isMainFrame: true, kind: .other,
                                        currentURL: current, now: t0), .block(.badScheme("itms-apps")))
        XCTAssertEqual(guardrail.decide(url: url("about:blank"), isMainFrame: false, kind: .other,
                                        currentURL: current, now: t0), .allow)
    }

    func testUserNavigationIsAllowed() {
        var guardrail = NavigationGuard(adMatcher: ads)
        XCTAssertEqual(guardrail.decide(url: url("https://other.site/"), isMainFrame: true, kind: .linkActivated,
                                        currentURL: current, now: t0), .allow)
        XCTAssertEqual(guardrail.decide(url: url("https://other.site/"), isMainFrame: true, kind: .backForward,
                                        currentURL: current, now: t0), .allow)
    }

    func testScriptRedirectsToOtherSitesAreBlocked() {
        var guardrail = NavigationGuard(adMatcher: ads)
        XCTAssertEqual(guardrail.decide(url: url("https://pub.com/x"), isMainFrame: true, kind: .other,
                                        currentURL: current, now: t0), .block(.crossSiteRedirect("pub.com")))
        XCTAssertEqual(guardrail.decide(url: url("https://cdn.streaming.site/p"), isMainFrame: true, kind: .other,
                                        currentURL: current, now: t0), .allow)
        XCTAssertEqual(guardrail.decide(url: url("https://pub.com/x"), isMainFrame: false, kind: .other,
                                        currentURL: current, now: t0), .allow)
        XCTAssertEqual(guardrail.decide(url: url("https://pub.com/x"), isMainFrame: true, kind: .other,
                                        currentURL: nil, now: t0), .allow)
    }

    func testIntentWindowAllowsServerRedirectChains() {
        var guardrail = NavigationGuard(adMatcher: ads)
        guardrail.noteUserIntent(at: t0)
        XCTAssertEqual(guardrail.decide(url: url("https://mirror.site/"), isMainFrame: true, kind: .other,
                                        currentURL: current, now: t0.addingTimeInterval(1)), .allow)
        XCTAssertEqual(guardrail.decide(url: url("https://mirror.site/"), isMainFrame: true, kind: .other,
                                        currentURL: current, now: t0.addingTimeInterval(5)),
                       .block(.crossSiteRedirect("mirror.site")))
        _ = guardrail.decide(url: url("https://a.site/"), isMainFrame: true, kind: .linkActivated, currentURL: current,
                             now: t0.addingTimeInterval(10))
        XCTAssertEqual(guardrail.decide(url: url("https://b.site/"), isMainFrame: true, kind: .other,
                                        currentURL: current, now: t0.addingTimeInterval(11)), .allow)
    }

    func testRedirectBlockingCanBeDisabled() {
        var guardrail = NavigationGuard(blockRedirects: false, adMatcher: ads)
        XCTAssertEqual(guardrail.decide(url: url("https://pub.com/x"), isMainFrame: true, kind: .other,
                                        currentURL: current, now: t0), .allow)
    }

    func testPopups() {
        let guardrail = NavigationGuard(adMatcher: ads)
        XCTAssertEqual(guardrail.decidePopup(url: url("https://other.site/"), kind: .linkActivated), .openInPlace)
        XCTAssertEqual(guardrail.decidePopup(url: url("https://other.site/"), kind: .other), .block)
        XCTAssertEqual(guardrail.decidePopup(url: url("https://a.popads.net/"), kind: .linkActivated), .block)
        XCTAssertEqual(guardrail.decidePopup(url: nil, kind: .linkActivated), .block)
    }
}
