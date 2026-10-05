import XCTest
@testable import CastCore

final class StrategyTests: XCTestCase {
    let reachable = PreflightResult(directReachable: true)
    let unreachable = PreflightResult(directReachable: false)
    let hlsTV = RendererCapabilities(sinkMimes: ["video/mp4", "application/vnd.apple.mpegurl"])
    let basicTV = RendererCapabilities(sinkMimes: ["video/mp4", "video/mpeg"])

    func plan(_ profile: ContentProfile, _ capabilities: RendererCapabilities, _ preflight: PreflightResult,
              preference: CastModePreference = .auto, remembered: CastStrategy? = nil,
              tests: TVTestResults? = nil) throws -> [CastStrategy] {
        try StrategyPlanner.plan(profile: profile, capabilities: capabilities, preflight: preflight,
                                 preference: preference, remembered: remembered, tests: tests)
    }

    func testProgressive() throws {
        let profile = ContentProfile(kind: .progressive, host: "cdn.net")
        XCTAssertEqual(try plan(profile, basicTV, reachable), [.direct, .relayProgressive])
        XCTAssertEqual(try plan(profile, basicTV, unreachable), [.relayProgressive])
        XCTAssertEqual(try plan(profile, basicTV, reachable, preference: .alwaysRelay), [.relayProgressive])
        XCTAssertEqual(try plan(profile, basicTV, unreachable, preference: .alwaysDirect), [.direct])
    }

    func testHLSWithTSSegments() throws {
        let profile = ContentProfile(kind: .hls, segmentFormat: .ts, host: "cdn.net")
        XCTAssertEqual(try plan(profile, basicTV, reachable), [.relayTS, .relayHLS])
        XCTAssertEqual(try plan(profile, hlsTV, reachable), [.direct, .relayHLS, .relayTS])
        XCTAssertEqual(try plan(profile, hlsTV, unreachable), [.relayHLS, .relayTS])
        XCTAssertEqual(try plan(profile, .unknown, reachable), [.relayTS, .relayHLS])
    }

    func testHLSWithFMP4Segments() throws {
        let profile = ContentProfile(kind: .hls, segmentFormat: .fmp4, host: "cdn.net")
        XCTAssertEqual(try plan(profile, basicTV, reachable), [.relayFMP4, .relayHLS])
        XCTAssertEqual(try plan(profile, hlsTV, reachable), [.direct, .relayHLS, .relayFMP4])
    }

    func testSeparateAudioNeverUsesContinuousStreams() throws {
        let profile = ContentProfile(kind: .hls, segmentFormat: .ts, hasSeparateAudio: true, host: "cdn.net")
        XCTAssertEqual(try plan(profile, basicTV, reachable), [.direct, .relayHLS])
        XCTAssertEqual(try plan(profile, basicTV, unreachable), [.relayHLS])
    }

    func testRefusals() {
        XCTAssertThrowsError(try plan(ContentProfile(kind: .hls, drm: true, host: "x"), hlsTV, reachable)) {
            XCTAssertEqual($0 as? PlanError, .drm)
        }
        XCTAssertThrowsError(try plan(ContentProfile(kind: .dash, host: "x"), hlsTV, reachable)) {
            XCTAssertEqual($0 as? PlanError, .dashUnsupported)
        }
    }

    func testRememberedStrategyGoesFirst() throws {
        let profile = ContentProfile(kind: .hls, segmentFormat: .ts, host: "cdn.net")
        XCTAssertEqual(try plan(profile, basicTV, reachable, remembered: .relayHLS), [.relayHLS, .relayTS])
        XCTAssertEqual(try plan(profile, basicTV, reachable, remembered: .direct), [.relayTS, .relayHLS])
    }

    func testFailedTVTestsMoveStrategiesLast() throws {
        let profile = ContentProfile(kind: .hls, segmentFormat: .ts, host: "cdn.net")
        let tests = TVTestResults(results: [.liveTS: false, .hlsTS: true], date: Date(), sink: [])
        XCTAssertEqual(try plan(profile, basicTV, reachable, tests: tests), [.relayHLS, .relayTS])
        XCTAssertEqual(tests.result(.liveTS), false)
        XCTAssertNil(tests.result(.mp4))
        XCTAssertEqual(tests.passedCount, 1)
    }

    func testMemoryPrefersHostSpecificEntry() {
        var memory = StrategyMemory()
        XCTAssertTrue(memory.isEmpty)
        let siteA = ContentProfile(kind: .hls, segmentFormat: .ts, host: "a.com")
        let siteB = ContentProfile(kind: .hls, segmentFormat: .ts, host: "b.com")
        memory.remember(.relayHLS, tv: "uuid:tv", profile: siteA)
        XCTAssertEqual(memory.recall(tv: "uuid:tv", profile: siteA), .relayHLS)
        XCTAssertEqual(memory.recall(tv: "uuid:tv", profile: siteB), .relayHLS)
        memory.remember(.relayTS, tv: "uuid:tv", profile: siteB)
        XCTAssertEqual(memory.recall(tv: "uuid:tv", profile: siteA), .relayHLS)
        XCTAssertEqual(memory.recall(tv: "uuid:tv", profile: ContentProfile(kind: .hls, segmentFormat: .ts, host: "c.com")), .relayTS)
        XCTAssertNil(memory.recall(tv: "uuid:other", profile: siteA))
        XCTAssertNil(memory.recall(tv: "uuid:tv", profile: ContentProfile(kind: .progressive, host: "a.com")))
    }

    func testLabels() {
        XCTAssertEqual(CastStrategy.relayTS.label, "Flux continu (TS)")
        XCTAssertTrue(CastStrategy.relayFMP4.isContinuous)
        XCTAssertFalse(CastStrategy.direct.usesRelay)
        XCTAssertEqual(TVTestCase.allCases.count, 5)
    }
}
