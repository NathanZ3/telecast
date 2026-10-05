import XCTest
@testable import CastCore

/// Virtual clock: `sleep` advances time instantly.
final class TestClock: SessionClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 0)

    func now() -> Date { lock.withLock { current } }

    var elapsed: Double { now().timeIntervalSince1970 }

    func sleep(seconds: Double) async throws {
        try Task.checkCancellation()
        lock.withLock { current = current.addingTimeInterval(seconds) }
        await Task.yield()
        try Task.checkCancellation()
    }
}

/// A TV whose state is a function of (load index, seconds since that load).
final class FakeRenderer: RendererControl, @unchecked Sendable {
    typealias Script = @Sendable (_ loadIndex: Int, _ sinceLoad: Double) -> (TransportState, Double?)

    private let lock = NSLock()
    private let clock: TestClock
    private let script: Script
    private var loadsStorage: [PreparedMedia] = []
    private var seeksStorage: [Double] = []
    private var stopsStorage = 0
    private var pausesStorage = 0
    private var statusCallsStorage = 0
    private var lastLoadAt: Double = 0
    private var failWindowStorage: ClosedRange<Double>?

    init(clock: TestClock, failWindow: ClosedRange<Double>? = nil, script: @escaping Script) {
        self.clock = clock
        self.script = script
        self.failWindowStorage = failWindow
    }

    var loads: [PreparedMedia] { lock.withLock { loadsStorage } }
    var seeks: [Double] { lock.withLock { seeksStorage } }
    var stops: Int { lock.withLock { stopsStorage } }
    var pauses: Int { lock.withLock { pausesStorage } }
    var statusCalls: Int { lock.withLock { statusCallsStorage } }

    func load(_ media: PreparedMedia, title: String) async throws {
        let now = clock.elapsed
        lock.withLock {
            loadsStorage.append(media)
            lastLoadAt = now
        }
    }

    func play() async throws {}

    func pause() async throws {
        lock.withLock { pausesStorage += 1 }
    }

    func stop() async throws {
        lock.withLock { stopsStorage += 1 }
    }

    func seek(to seconds: Double) async throws {
        lock.withLock { seeksStorage.append(seconds) }
    }

    func status() async throws -> (TransportInfo, PositionInfo) {
        let now = clock.elapsed
        let snapshot: (Int, Double, ClosedRange<Double>?) = lock.withLock {
            statusCallsStorage += 1
            return (loadsStorage.count - 1, now - lastLoadAt, failWindowStorage)
        }
        if let window = snapshot.2, window.contains(now) { throw DLNAError.httpStatus(503) }
        guard snapshot.0 >= 0 else { return (TransportInfo(state: .noMedia), PositionInfo()) }
        let (state, position) = script(snapshot.0, snapshot.1)
        return (TransportInfo(state: state), PositionInfo(duration: nil, position: position))
    }

    func volume() async throws -> Int { 20 }

    func setVolume(_ value: Int) async throws {}
}

final class FakeMedia: MediaSource, @unchecked Sendable {
    private let lock = NSLock()
    private var preparedStorage: [(CastStrategy, Double)] = []
    private var releasedStorage = false
    private let fetched: Bool

    init(fetched: Bool = true) {
        self.fetched = fetched
    }

    var prepared: [(CastStrategy, Double)] { lock.withLock { preparedStorage } }
    var released: Bool { lock.withLock { releasedStorage } }

    func prepare(strategy: CastStrategy, offset: Double) async throws -> PreparedMedia {
        lock.withLock { preparedStorage.append((strategy, offset)) }
        return PreparedMedia(url: URL(string: "http://phone.local/\(strategy.rawValue)")!, mime: "video/mp4",
                             seekable: !strategy.isContinuous, offset: offset)
    }

    func wasFetched(after date: Date) -> Bool { fetched }

    func release() async {
        lock.withLock { releasedStorage = true }
    }
}

/// Keeps phase changes (not every position update) and the last snapshot.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var phaseHistory: [CastPhase] = []
    private var lastSnapshot: CastSnapshot?
    private var successes: [CastStrategy] = []

    func record(_ snapshot: CastSnapshot) {
        lock.withLock {
            if phaseHistory.last != snapshot.phase { phaseHistory.append(snapshot.phase) }
            lastSnapshot = snapshot
        }
    }

    func success(_ strategy: CastStrategy) {
        lock.withLock { successes.append(strategy) }
    }

    var phases: [CastPhase] { lock.withLock { phaseHistory } }
    var last: CastSnapshot? { lock.withLock { lastSnapshot } }
    var succeeded: [CastStrategy] { lock.withLock { successes } }

    var failureMessage: String? {
        if case let .failed(message)? = last?.phase { return message }
        return nil
    }
}

final class CastSessionTests: XCTestCase {
    func makeSession(_ strategies: [CastStrategy], duration: Double? = 3600, isLive: Bool = false, startOffset: Double = 0,
                     renderer: FakeRenderer, media: FakeMedia, clock: TestClock, recorder: Recorder) -> CastSession {
        CastSession(title: "Film", strategies: strategies, knownDuration: duration, isLive: isLive, startOffset: startOffset,
                    renderer: renderer, media: media, clock: clock,
                    onUpdate: { recorder.record($0) }, onSuccess: { recorder.success($0) })
    }

    func waitFor(_ description: String, timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("Timed out waiting for \(description)")
    }

    func testFirstStrategyPlays() async {
        let clock = TestClock()
        let renderer = FakeRenderer(clock: clock) { _, since in since < 2 ? (.transitioning, nil) : (.playing, since - 2) }
        let media = FakeMedia()
        let recorder = Recorder()
        let session = makeSession([.direct, .relayProgressive], renderer: renderer, media: media, clock: clock, recorder: recorder)
        await session.start()
        await waitFor("playing") { recorder.phases.contains(.playing) }
        XCTAssertEqual(recorder.succeeded, [.direct])
        XCTAssertEqual(media.prepared.map { $0.0 }, [.direct])
        await session.stop()
    }

    func testFallsBackToNextStrategyAfterTimeout() async {
        let clock = TestClock()
        let renderer = FakeRenderer(clock: clock) { index, since in
            index == 0 ? (.transitioning, nil) : (since < 1 ? .transitioning : .playing, max(0, since - 1))
        }
        let media = FakeMedia()
        let recorder = Recorder()
        let session = makeSession([.direct, .relayTS], renderer: renderer, media: media, clock: clock, recorder: recorder)
        await session.start()
        await waitFor("playing") { recorder.phases.contains(.playing) }
        XCTAssertEqual(recorder.succeeded, [.relayTS])
        XCTAssertEqual(media.prepared.map { $0.0 }, [.direct, .relayTS])
        XCTAssertGreaterThanOrEqual(renderer.stops, 1)
        XCTAssertTrue(recorder.phases.contains(.trying(strategy: .relayTS, attempt: 2, total: 2)))
        await session.stop()
    }

    func testRelayNeverContactedReportsWiFiProblem() async {
        let clock = TestClock()
        let renderer = FakeRenderer(clock: clock) { _, _ in (.transitioning, nil) }
        let media = FakeMedia(fetched: false)
        let recorder = Recorder()
        let session = makeSession([.relayTS], renderer: renderer, media: media, clock: clock, recorder: recorder)
        await session.start()
        await waitFor("failure") { recorder.failureMessage != nil }
        XCTAssertTrue(recorder.failureMessage?.contains("joindre") == true, recorder.failureMessage ?? "")
        XCTAssertLessThan(clock.elapsed, 15)
    }

    func testAllStrategiesFail() async {
        let clock = TestClock()
        let renderer = FakeRenderer(clock: clock) { _, _ in (.stopped, nil) }
        let media = FakeMedia()
        let recorder = Recorder()
        let session = makeSession([.direct, .relayProgressive], renderer: renderer, media: media, clock: clock, recorder: recorder)
        await session.start()
        await waitFor("failure") { recorder.failureMessage != nil }
        XCTAssertEqual(media.prepared.count, 2)
        XCTAssertTrue(recorder.failureMessage?.contains("aucun mode") == true)
        XCTAssertTrue(recorder.succeeded.isEmpty)
    }

    func testUnexpectedStopsResumeThenGiveUp() async {
        let clock = TestClock()
        let renderer = FakeRenderer(clock: clock) { _, since in since < 20 ? (.playing, since) : (.stopped, nil) }
        let media = FakeMedia()
        let recorder = Recorder()
        let session = makeSession([.relayTS], renderer: renderer, media: media, clock: clock, recorder: recorder)
        await session.start()
        await waitFor("failure after resumes") { recorder.failureMessage != nil }
        let offsets = media.prepared.map { $0.1 }
        XCTAssertEqual(offsets.count, 4)
        XCTAssertEqual(offsets.first, 0)
        XCTAssertGreaterThan(offsets[1], 15)
        XCTAssertLessThan(offsets[1], 21)
        XCTAssertGreaterThan(offsets[3], offsets[2])
        XCTAssertTrue(recorder.phases.contains(.resuming(1)))
        XCTAssertTrue(recorder.phases.contains(.resuming(3)))
        XCTAssertTrue(recorder.failureMessage?.contains("Relancer") == true)
    }

    func testStopNearTheEndIsANormalEnd() async {
        let clock = TestClock()
        let renderer = FakeRenderer(clock: clock) { _, since in since < 100 ? (.playing, since) : (.stopped, nil) }
        let media = FakeMedia()
        let recorder = Recorder()
        let session = makeSession([.relayTS], startOffset: 3480, renderer: renderer, media: media, clock: clock,
                                  recorder: recorder)
        await session.start()
        await waitFor("ended") { recorder.phases.contains(.ended) }
        XCTAssertEqual(media.prepared.count, 1)
        XCTAssertEqual(media.prepared.first?.1, 3480)
    }

    func testContinuousSeekRestartsAtOffset() async {
        let clock = TestClock()
        let renderer = FakeRenderer(clock: clock) { _, since in since < 1 ? (.transitioning, nil) : (.playing, since - 1) }
        let media = FakeMedia()
        let recorder = Recorder()
        let session = makeSession([.relayTS], renderer: renderer, media: media, clock: clock, recorder: recorder)
        await session.start()
        await waitFor("playing") { recorder.phases.contains(.playing) }
        await session.seek(to: 1200)
        XCTAssertEqual(media.prepared.last?.0, .relayTS)
        XCTAssertEqual(media.prepared.last?.1, 1200)
        let position = await session.snapshot().position ?? 0
        XCTAssertGreaterThanOrEqual(position, 1200)
        XCTAssertTrue(renderer.seeks.isEmpty)
        await session.stop()
    }

    func testNativeSeekForDirectProgressive() async {
        let clock = TestClock()
        let renderer = FakeRenderer(clock: clock) { _, since in (.playing, since) }
        let media = FakeMedia()
        let recorder = Recorder()
        let session = makeSession([.direct], duration: nil, renderer: renderer, media: media, clock: clock, recorder: recorder)
        await session.start()
        await waitFor("playing") { recorder.phases.contains(.playing) }
        await session.seek(to: 1200)
        XCTAssertEqual(renderer.seeks, [1200])
        XCTAssertEqual(media.prepared.count, 1)
        await session.stop()
    }

    func testUnreachableThenRecovered() async {
        let clock = TestClock()
        let renderer = FakeRenderer(clock: clock, failWindow: 30...40) { _, since in (.playing, since) }
        let media = FakeMedia()
        let recorder = Recorder()
        let session = makeSession([.direct], renderer: renderer, media: media, clock: clock, recorder: recorder)
        await session.start()
        await waitFor("recovered") {
            let phases = recorder.phases
            guard let index = phases.lastIndex(of: .unreachable) else { return false }
            return phases[(index + 1)...].contains(.playing)
        }
        await session.stop()
    }

    func testStopReleasesEverything() async {
        let clock = TestClock()
        let renderer = FakeRenderer(clock: clock) { _, since in (.playing, since) }
        let media = FakeMedia()
        let recorder = Recorder()
        let session = makeSession([.direct], renderer: renderer, media: media, clock: clock, recorder: recorder)
        await session.start()
        await waitFor("playing") { recorder.phases.contains(.playing) }
        await session.stop()
        XCTAssertGreaterThanOrEqual(renderer.stops, 1)
        XCTAssertTrue(media.released)
        XCTAssertEqual(recorder.last?.phase, .stopped)
        let calls = renderer.statusCalls
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertLessThanOrEqual(renderer.statusCalls, calls + 1)
    }

    func testTogglePause() async {
        let clock = TestClock()
        let renderer = FakeRenderer(clock: clock) { _, since in (.playing, since) }
        let media = FakeMedia()
        let recorder = Recorder()
        let session = makeSession([.direct], renderer: renderer, media: media, clock: clock, recorder: recorder)
        await session.start()
        await waitFor("playing") { recorder.phases.contains(.playing) }
        await session.togglePause()
        XCTAssertEqual(renderer.pauses, 1)
        XCTAssertTrue(recorder.phases.contains(.paused))
        await session.stop()
    }

    func testTimeLabel() {
        XCTAssertEqual(CastSession.timeLabel(65), "1:05")
        XCTAssertEqual(CastSession.timeLabel(3725), "1:02:05")
        XCTAssertEqual(CastSession.timeLabel(-3), "0:00")
    }
}
