import XCTest
@testable import CastCore

final class DetectionTests: XCTestCase {
    private func url(_ string: String) -> URL { URL(string: string)! }

    private let page = PageContext(pageURL: URL(string: "https://site.com/film"), pageTitle: "Mon film",
                                   userAgent: "UA", cookies: [])

    func testClassifier() {
        XCTAssertEqual(MediaClassifier.classify(url: url("https://c.net/a/master.m3u8?t=1"), mime: nil, via: "xhr"), .media(.hls))
        XCTAssertEqual(MediaClassifier.classify(url: url("https://c.net/get?id=1"), mime: "application/vnd.apple.mpegurl; charset=utf-8", via: "xhr"), .media(.hls))
        XCTAssertEqual(MediaClassifier.classify(url: url("https://c.net/v.mpd"), mime: nil, via: "fetch"), .media(.dash))
        XCTAssertEqual(MediaClassifier.classify(url: url("https://c.net/seg-12.ts"), mime: nil, via: "xhr"), .ignored("segment"))
        XCTAssertEqual(MediaClassifier.classify(url: url("https://c.net/movie.mp4"), mime: nil, via: "video-src"), .media(.progressive))
        XCTAssertEqual(MediaClassifier.classify(url: url("https://c.net/seg-3.mp4"), mime: nil, via: "fetch"), .ignored("segment"))
        XCTAssertEqual(MediaClassifier.classify(url: url("https://rr3.googlevideo.com/videoplayback"), mime: nil, via: "xhr"), .ignored("youtube"))
        XCTAssertEqual(MediaClassifier.classify(url: url("https://pubads.g.doubleclick.net/x.mp4"), mime: nil, via: "video-src"), .ignored("ad"))
        XCTAssertEqual(MediaClassifier.classify(url: url("blob:https://c.net/123"), mime: nil, via: "video-src"), .ignored("scheme"))
        XCTAssertEqual(MediaClassifier.classify(url: url("https://c.net/app.js"), mime: nil, via: "perf"), .ignored("not-media"))
        XCTAssertEqual(MediaClassifier.classify(url: url("https://c.net/stream"), mime: "video/mp4", via: "video-src"), .media(.progressive))
    }

    func testSegmentHeuristic() {
        XCTAssertTrue(MediaClassifier.looksLikeSegment("chunk_3.m4s"))
        XCTAssertTrue(MediaClassifier.looksLikeSegment("000123.mp4"))
        XCTAssertTrue(MediaClassifier.looksLikeSegment("init.mp4"))
        XCTAssertTrue(MediaClassifier.looksLikeSegment("video_720_15.mp4"))
        XCTAssertFalse(MediaClassifier.looksLikeSegment("movie.mp4"))
        XCTAssertFalse(MediaClassifier.looksLikeSegment("le-film.mp4"))
    }

    func testDecodeFromDictionary() {
        let body: [String: Any] = ["kind": "candidate", "url": "https://c.net/a.m3u8", "via": "xhr", "duration": 12.5, "playing": true]
        let message = DetectorMessage.decode(from: body)
        XCTAssertEqual(message?.kind, .candidate)
        XCTAssertEqual(message?.url, "https://c.net/a.m3u8")
        XCTAssertEqual(message?.duration, 12.5)
        XCTAssertEqual(message?.playing, true)
        XCTAssertNil(DetectorMessage.decode(from: ["kind": "unknown"]))
        XCTAssertNil(DetectorMessage.decode(from: 42))
    }

    func testIngestDeduplicatesByHostAndPath() {
        var store = CandidateStore()
        let frame = url("https://embed.io/e/1")
        let t0 = Date(timeIntervalSince1970: 100)
        store.ingest(DetectorMessage(kind: .candidate, url: "https://cdn.net/v/master.m3u8?token=a", via: "xhr"),
                     frameURL: frame, page: page, now: t0)
        store.ingest(DetectorMessage(kind: .candidate, url: "https://cdn.net/v/master.m3u8?token=b", via: "perf"),
                     frameURL: frame, page: page, now: t0.addingTimeInterval(5))
        XCTAssertEqual(store.candidates.count, 1)
        XCTAssertEqual(store.candidates[0].url.absoluteString, "https://cdn.net/v/master.m3u8?token=b")
        XCTAssertEqual(store.candidates[0].via, ["xhr", "perf"])
        XCTAssertEqual(store.candidates[0].context.referer, "https://embed.io/")
        XCTAssertEqual(store.candidates[0].pageTitle, "Mon film")
    }

    func testIgnoredMessagesDoNotChangeStore() {
        var store = CandidateStore()
        XCTAssertFalse(store.ingest(DetectorMessage(kind: .candidate, url: "https://cdn.net/seg-1.ts", via: "xhr"),
                                    frameURL: nil, page: page))
        XCTAssertFalse(store.ingest(DetectorMessage(kind: .hello, userAgent: "UA"), frameURL: nil, page: page))
        XCTAssertTrue(store.candidates.isEmpty)
    }

    func testPlayingMessageMarksMostRecentStreamOfFrame() {
        var store = CandidateStore()
        let frame = url("https://embed.io/e/1")
        let t0 = Date(timeIntervalSince1970: 100)
        store.ingest(DetectorMessage(kind: .candidate, url: "https://cdn.net/old.m3u8", via: "xhr"), frameURL: frame, page: page, now: t0)
        store.ingest(DetectorMessage(kind: .candidate, url: "https://cdn.net/new.m3u8", via: "xhr"), frameURL: frame,
                     page: page, now: t0.addingTimeInterval(1))
        XCTAssertTrue(store.ingest(DetectorMessage(kind: .playing, frameURL: frame.absoluteString, duration: 5400, playing: true),
                                   frameURL: frame, page: page))
        let playing = store.candidates.first { $0.isPlaying }
        XCTAssertEqual(playing?.url.lastPathComponent, "new.m3u8")
        XCTAssertEqual(playing?.duration, 5400)
        XCTAssertEqual(store.candidates.first?.url.lastPathComponent, "new.m3u8")
    }

    func testPlayingFeatureBeatsShortPreroll() {
        var store = CandidateStore()
        let frame = url("https://site.com/film")
        store.ingest(DetectorMessage(kind: .candidate, url: "https://ads.example/preroll.mp4", via: "video-src", duration: 20),
                     frameURL: frame, page: page)
        store.ingest(DetectorMessage(kind: .candidate, url: "https://cdn.net/film/index.m3u8", via: "xhr", duration: 3600, playing: true),
                     frameURL: frame, page: page)
        XCTAssertEqual(store.candidates.first?.url.lastPathComponent, "index.m3u8")
        XCTAssertLessThan(store.candidates.last!.score, 0)
    }

    func testDRMAndDashAreNotCastable() {
        let now = Date()
        var candidate = MediaCandidate(id: "x", url: url("https://c.net/a.m3u8"), kind: .hls, context: .none, frameURL: nil,
                                       pageURL: nil, pageTitle: nil, via: [], firstSeen: now, lastSeen: now)
        XCTAssertTrue(candidate.isCastable)
        candidate.hls = HLSInfo(isMaster: false, variants: [], chosenVariantURL: candidate.url, totalDuration: 100,
                                isLive: false, segmentFormat: .ts, hasSeparateAudio: false, drm: true, encrypted: true)
        XCTAssertFalse(candidate.isCastable)
        candidate.hls = nil
        candidate.kind = .dash
        XCTAssertFalse(candidate.isCastable)
        XCTAssertEqual(candidate.displayTitle, "a.m3u8")
    }

    func testReset() {
        var store = CandidateStore()
        store.ingest(DetectorMessage(kind: .candidate, url: "https://cdn.net/a.mp4", via: "video-src"), frameURL: nil, page: page)
        store.reset()
        XCTAssertTrue(store.candidates.isEmpty)
    }
}
