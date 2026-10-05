import XCTest
@testable import CastCore

final class UtilTests: XCTestCase {
    func testRegistrableDomain() {
        XCTAssertEqual(RegistrableDomain.of("www.example.com"), "example.com")
        XCTAssertEqual(RegistrableDomain.of("a.b.example.co.uk"), "example.co.uk")
        XCTAssertEqual(RegistrableDomain.of("192.168.1.10"), "192.168.1.10")
        XCTAssertEqual(RegistrableDomain.of("Video.Site.FR."), "site.fr")
        XCTAssertTrue(RegistrableDomain.sameSite("cdn.site.com", "site.com"))
        XCTAssertFalse(RegistrableDomain.sameSite("site.com", "other.com"))
    }

    func testAdHostMatcher() {
        let matcher = AdHostMatcher(text: "# comment\ndoubleclick.net\n\n  popads.net  \n")
        XCTAssertEqual(matcher.count, 2)
        XCTAssertTrue(matcher.matches(host: "ad.doubleclick.net"))
        XCTAssertTrue(matcher.matches(host: "POPADS.NET"))
        XCTAssertFalse(matcher.matches(host: "notdoubleclick.net"))
        XCTAssertFalse(matcher.matches(host: "example.com"))
        XCTAssertTrue(AdHostMatcher.builtIn.matches(host: "imasdk.googleapis.com"))
        XCTAssertFalse(AdHostMatcher.builtIn.matches(host: "googleapis.com"))
    }

    func testURLInput() {
        XCTAssertEqual(URLInput.url(from: "example.com")?.absoluteString, "https://example.com")
        XCTAssertEqual(URLInput.url(from: "http://x.fr/a")?.absoluteString, "http://x.fr/a")
        XCTAssertEqual(URLInput.url(from: "192.168.1.20:8080/x")?.absoluteString, "https://192.168.1.20:8080/x")
        XCTAssertEqual(URLInput.url(from: "film complet")?.host, "www.google.com")
        XCTAssertEqual(URLInput.url(from: "telecast")?.host, "www.google.com")
        XCTAssertNil(URLInput.url(from: "   "))
    }

    func testSubnetHostsForSlash24() {
        let hosts = SubnetMath.hosts(address: "192.168.1.69", netmask: "255.255.255.0")
        XCTAssertEqual(hosts.count, 253)
        XCTAssertEqual(hosts.first, "192.168.1.1")
        XCTAssertEqual(hosts.last, "192.168.1.254")
        XCTAssertFalse(hosts.contains("192.168.1.69"))
    }

    func testSubnetLargerThanSlash24IsNarrowed() {
        let hosts = SubnetMath.hosts(address: "10.0.5.7", netmask: "255.255.0.0")
        XCTAssertEqual(hosts.count, 253)
        XCTAssertEqual(hosts.first, "10.0.5.1")
    }

    func testSubnetInvalidInput() {
        XCTAssertEqual(SubnetMath.hosts(address: "nope", netmask: "255.255.255.0"), [])
        XCTAssertNil(SubnetMath.parse("1.2.3"))
        XCTAssertEqual(SubnetMath.format(0xC0A8_0101), "192.168.1.1")
    }
}
