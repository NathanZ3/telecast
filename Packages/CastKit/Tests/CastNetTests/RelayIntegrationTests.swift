import XCTest
@testable import CastCore
@testable import CastNet

/// End-to-end relay tests on the loopback interface: a second RelayServer plays the
/// "website" (serving fixtures under /t/), the relay under test fetches from it.
final class RelayIntegrationTests: XCTestCase {
    final class HeadRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var heads: [HTTPRequestHead] = []
        func record(_ head: HTTPRequestHead) { lock.withLock { heads.append(head) } }
        var all: [HTTPRequestHead] { lock.withLock { heads } }
    }

    let key = Data((0..<16).map { UInt8($0 + 100) })
    let movie = Data((0..<10_000).map { UInt8($0 % 251) })
    let plainSegments = [Data(repeating: 0xA1, count: 3000), Data(repeating: 0xB2, count: 2000), Data(repeating: 0xC3, count: 1000)]
    let fmp4Parts = [Data("INIT-SECTION".utf8), Data(repeating: 0x51, count: 700), Data(repeating: 0x52, count: 900)]

    var upstream: RelayServer!
    var relay: RelayServer!
    var recorder: HeadRecorder!
    var fixtures: URL!
    var session: URLSession!

    override func setUp() async throws {
        fixtures = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try writeFixtures()
        upstream = RelayServer(testFiles: fixtures)
        try await upstream.start()
        relay = RelayServer(testFiles: nil)
        try await relay.start()
        recorder = HeadRecorder()
        let recorder = self.recorder!
        upstream.onRequest = { recorder.record($0) }
        session = URLSession(configuration: .ephemeral)
    }

    override func tearDown() async throws {
        upstream?.stop()
        relay?.stop()
        session?.invalidateAndCancel()
        if let fixtures { try? FileManager.default.removeItem(at: fixtures) }
    }

    func writeFixtures() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: fixtures.appendingPathComponent("hls"), withIntermediateDirectories: true)
        try manager.createDirectory(at: fixtures.appendingPathComponent("fmp4"), withIntermediateDirectories: true)
        try movie.write(to: fixtures.appendingPathComponent("movie.mp4"))
        try key.write(to: fixtures.appendingPathComponent("hls/k.key"))
        var playlist = "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:6\n#EXT-X-MEDIA-SEQUENCE:0\n"
        playlist += "#EXT-X-KEY:METHOD=AES-128,URI=\"k.key\"\n"
        let durations = ["6.0", "6.0", "4.0"]
        for (index, plain) in plainSegments.enumerated() {
            let encrypted = try AES128.encryptCBC(plain, key: key, iv: AES128.iv(forSequence: index))
            try encrypted.write(to: fixtures.appendingPathComponent("hls/seg\(index).ts"))
            playlist += "#EXTINF:\(durations[index]),\nseg\(index).ts\n"
        }
        playlist += "#EXT-X-ENDLIST\n"
        try Data(playlist.utf8).write(to: fixtures.appendingPathComponent("hls/index.m3u8"))

        try fmp4Parts[0].write(to: fixtures.appendingPathComponent("fmp4/init.mp4"))
        try fmp4Parts[1].write(to: fixtures.appendingPathComponent("fmp4/s0.m4s"))
        try fmp4Parts[2].write(to: fixtures.appendingPathComponent("fmp4/s1.m4s"))
        let fmp4Playlist = "#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:4,\ns0.m4s\n#EXTINF:4,\ns1.m4s\n#EXT-X-ENDLIST\n"
        try Data(fmp4Playlist.utf8).write(to: fixtures.appendingPathComponent("fmp4/index.m3u8"))
    }

    func upstreamURL(_ path: String) -> URL {
        URL(string: upstream.baseURL(host: "127.0.0.1")!.absoluteString + "/t/" + path)!
    }

    func relayURL(_ route: RelayRoute) -> URL {
        URL(string: relay.baseURL(host: "127.0.0.1")!.absoluteString + route.path)!
    }

    func get(_ url: URL, range: String? = nil) async throws -> (HTTPURLResponse, Data) {
        var request = URLRequest(url: url)
        if let range { request.setValue(range, forHTTPHeaderField: "Range") }
        let (data, response) = try await session.data(for: request)
        return (response as! HTTPURLResponse, data)
    }

    func testHealth() async throws {
        let (response, data) = try await get(relayURL(.health))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "ok")
    }

    func testProgressivePassthroughForwardsRangeAndHeaders() async throws {
        let context = RequestContext(referer: "https://site.example/film", userAgent: "UA-Test", cookie: "sid=42")
        relay.register(RelaySessionConfig(id: "p1", mode: .progressive, sourceURL: upstreamURL("movie.mp4"),
                                          mediaPlaylistURL: nil, context: context, mime: "video/mp4"))
        let (response, data) = try await get(relayURL(.progressive(session: "p1", ext: "mp4")), range: "bytes=10-19")
        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(data, movie.subdata(in: 10..<20))
        XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Range"), "bytes 10-19/10000")
        let upstreamHead = try XCTUnwrap(recorder.all.last)
        XCTAssertEqual(upstreamHead.header("referer"), "https://site.example/film")
        XCTAssertEqual(upstreamHead.header("user-agent"), "UA-Test")
        XCTAssertEqual(upstreamHead.header("cookie"), "sid=42")
        XCTAssertNotNil(relay.lastContact("p1"))

        let (full, body) = try await get(relayURL(.progressive(session: "p1", ext: "mp4")))
        XCTAssertEqual(full.statusCode, 200)
        XCTAssertEqual(body, movie)
    }

    func testPlaylistIsRewrittenAndResourcesRelayed() async throws {
        relay.register(RelaySessionConfig(id: "h1", mode: .hlsProxy, sourceURL: upstreamURL("hls/index.m3u8"),
                                          mediaPlaylistURL: upstreamURL("hls/index.m3u8"), context: .none,
                                          mime: "application/vnd.apple.mpegurl"))
        let (response, data) = try await get(relayURL(.playlist(session: "h1")))
        XCTAssertEqual(response.statusCode, 200)
        let text = String(decoding: data, as: UTF8.self)
        let relayPrefix = relay.baseURL(host: "127.0.0.1")!.absoluteString + "/s/h1/r/"
        let segmentLines = text.split(separator: "\n").filter { !$0.hasPrefix("#") }
        XCTAssertEqual(segmentLines.count, 3)
        XCTAssertTrue(segmentLines.allSatisfy { $0.hasPrefix(relayPrefix) }, text)
        XCTAssertTrue(text.contains("URI=\"\(relayPrefix)"), text)

        let (segmentResponse, segment) = try await get(URL(string: String(segmentLines[1]))!)
        XCTAssertEqual(segmentResponse.statusCode, 200)
        let expected = try AES128.encryptCBC(plainSegments[1], key: key, iv: AES128.iv(forSequence: 1))
        XCTAssertEqual(segment, expected)
    }

    func testContinuousTSDecryptsAndConcatenatesFromOffset() async throws {
        relay.register(RelaySessionConfig(id: "l1", mode: .liveTS, sourceURL: upstreamURL("hls/index.m3u8"),
                                          mediaPlaylistURL: upstreamURL("hls/index.m3u8"), context: .none, mime: "video/mp2t"))
        let (response, data) = try await get(relayURL(.liveTS(session: "l1", offsetMillis: 0)))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Type"), "video/mp2t")
        XCTAssertEqual(data, plainSegments[0] + plainSegments[1] + plainSegments[2])

        let (_, fromSix) = try await get(relayURL(.liveTS(session: "l1", offsetMillis: 6000)))
        XCTAssertEqual(fromSix, plainSegments[1] + plainSegments[2])
    }

    func testContinuousFMP4StartsWithInitSection() async throws {
        relay.register(RelaySessionConfig(id: "f1", mode: .liveFMP4, sourceURL: upstreamURL("fmp4/index.m3u8"),
                                          mediaPlaylistURL: upstreamURL("fmp4/index.m3u8"), context: .none, mime: "video/mp4"))
        let (_, data) = try await get(relayURL(.liveFMP4(session: "f1", offsetMillis: 0)))
        XCTAssertEqual(data, fmp4Parts[0] + fmp4Parts[1] + fmp4Parts[2])
        let (_, fromFour) = try await get(relayURL(.liveFMP4(session: "f1", offsetMillis: 4000)))
        XCTAssertEqual(fromFour, fmp4Parts[0] + fmp4Parts[2])
    }

    func testUnknownSessionIs404AndTestFilesSupportRanges() async throws {
        let (missing, _) = try await get(relayURL(.playlist(session: "nope")))
        XCTAssertEqual(missing.statusCode, 404)
        let (partial, bytes) = try await get(upstreamURL("movie.mp4"), range: "bytes=-4")
        XCTAssertEqual(partial.statusCode, 206)
        XCTAssertEqual(bytes, movie.suffix(4))
    }

    func testMediaSourcePreparesRelayURLs() async throws {
        let source = RelayMediaSource(server: relay, sourceURL: upstreamURL("hls/index.m3u8"), kind: .hls,
                                      mediaPlaylistURL: upstreamURL("hls/index.m3u8"), context: .none,
                                      capabilities: RendererCapabilities(sinkMimes: ["video/mpeg"]))
        let direct = try await source.prepare(strategy: .direct, offset: 0)
        XCTAssertEqual(direct.url, upstreamURL("hls/index.m3u8"))
        XCTAssertEqual(direct.mime, "application/vnd.apple.mpegurl")
        let continuous = try await source.prepare(strategy: .relayTS, offset: 12.5)
        XCTAssertEqual(continuous.mime, "video/mpeg")
        XCTAssertEqual(continuous.offset, 12.5)
        XCTAssertFalse(continuous.seekable)
        XCTAssertTrue(continuous.url.path.hasSuffix("/t12500/live.ts"))
        let before = Date()
        XCTAssertFalse(source.wasFetched(after: before))
        var request = URLRequest(url: URL(string: continuous.url.absoluteString.replacingOccurrences(
            of: continuous.url.host ?? "", with: "127.0.0.1"))!)
        request.httpMethod = "HEAD"
        _ = try await session.data(for: request)
        XCTAssertTrue(source.wasFetched(after: before))
        await source.release()
        XCTAssertFalse(source.wasFetched(after: before))
    }
}
