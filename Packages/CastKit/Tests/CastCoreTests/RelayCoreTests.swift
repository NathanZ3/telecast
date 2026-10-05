import XCTest
@testable import CastCore

final class RelayCoreTests: XCTestCase {
    func testParsesRequestHead() throws {
        let raw = "GET /s/abc/t12000/live.ts HTTP/1.1\r\nHost: 192.168.1.30:4000\r\nRange: bytes=0-\r\n"
            + "getcontentFeatures.dlna.org: 1\r\n\r\nBODY"
        let data = Data(raw.utf8)
        XCTAssertEqual(HTTPRequestParser.headerEnd(in: data), raw.utf8.count - 4)
        let head = try XCTUnwrap(HTTPRequestParser.parse(data))
        XCTAssertEqual(head.method, "GET")
        XCTAssertEqual(head.path, "/s/abc/t12000/live.ts")
        XCTAssertEqual(head.header("Range"), "bytes=0-")
        XCTAssertEqual(head.header("GETCONTENTFEATURES.DLNA.ORG"), "1")
        XCTAssertNil(HTTPRequestParser.headerEnd(in: Data("GET / HTTP/1.1\r\nHost: x\r\n".utf8)))
        XCTAssertNil(HTTPRequestParser.parse(Data("garbage".utf8)))
    }

    func testPathStripsQueryAndAbsoluteForm() {
        XCTAssertEqual(HTTPRequestHead(method: "GET", target: "/h?x=1", headers: [:]).path, "/h")
        XCTAssertEqual(HTTPRequestHead(method: "GET", target: "http://1.2.3.4:5/s/a/m.m3u8", headers: [:]).path, "/s/a/m.m3u8")
    }

    func testRoutesRoundTrip() {
        let routes: [RelayRoute] = [
            .health, .testFile("hls/index.m3u8"), .progressive(session: "abc", ext: "mp4"), .playlist(session: "abc"),
            .resource(session: "abc", id: "12.ts"), .liveTS(session: "abc", offsetMillis: 12000),
            .liveFMP4(session: "abc", offsetMillis: 0),
        ]
        for route in routes {
            XCTAssertEqual(RelayRoute.parse(path: route.path), route, route.path)
        }
        XCTAssertEqual(RelayRoute.parse(path: "/s/abc/t12000/live.ts"), .liveTS(session: "abc", offsetMillis: 12000))
        XCTAssertEqual(RelayRoute.parse(path: "/nothing"), .notFound)
        XCTAssertEqual(RelayRoute.parse(path: "/t/../secret"), .notFound)
        XCTAssertEqual(RelayRoute.parse(path: "/s/abc/tX/live.ts"), .notFound)
        XCTAssertEqual(RelayRoute.liveTS(session: "abc", offsetMillis: 5).sessionID, "abc")
        XCTAssertNil(RelayRoute.health.sessionID)
    }

    func testResourceMapIsStableAndKeepsExtensions() {
        var map = ResourceMap()
        let segment = URL(string: "https://cdn.net/a/seg1.ts?token=1")!
        let first = map.id(for: segment)
        XCTAssertEqual(map.id(for: segment), first)
        XCTAssertTrue(first.hasSuffix(".ts"))
        let other = map.id(for: URL(string: "https://cdn.net/a/getkey")!)
        XCTAssertNotEqual(other, first)
        XCTAssertFalse(other.contains("."))
        XCTAssertEqual(map.entry(for: first)?.url, segment)
        XCTAssertNil(map.entry(for: "999"))
        XCTAssertEqual(map.count, 2)
    }

    func testResponseHeadSerialization() {
        let head = HTTPResponseHead(status: 206, headers: [("Content-Type", "video/mp4"), ("Content-Range", "bytes 0-9/100")])
        let text = String(data: head.serialized(), encoding: .utf8)
        XCTAssertEqual(text, "HTTP/1.1 206 Partial Content\r\nContent-Type: video/mp4\r\nContent-Range: bytes 0-9/100\r\n\r\n")
    }

    func testDLNAStreamingHeaders() {
        let requested = DLNAHeaders.streaming(mime: "video/mpeg", seekable: false, requested: true)
        XCTAssertEqual(requested.count, 2)
        XCTAssertEqual(requested[0].0, "transferMode.dlna.org")
        XCTAssertEqual(requested[1].1, "DLNA.ORG_OP=00;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000")
        XCTAssertEqual(DLNAHeaders.streaming(mime: "video/mp4", seekable: true, requested: false).count, 1)
    }
}
