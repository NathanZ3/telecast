import Foundation
import CastCore

/// "Tester ma TV": plays short bundled clips in every format/mode and records what works.
/// Expects the bundled test media under the relay's `/t/`: `test.mp4`, `hls/index.m3u8`
/// (TS segments) and `fmp4/index.m3u8` (fMP4 segments).
public final class TVTestRunner: @unchecked Sendable {
    let server: RelayServer
    let renderer: RendererControl
    let capabilities: RendererCapabilities
    let clock: SessionClock
    let timeout: Double

    public init(server: RelayServer, renderer: RendererControl, capabilities: RendererCapabilities,
                clock: SessionClock = SystemClock(), timeout: Double = 12) {
        self.server = server
        self.renderer = renderer
        self.capabilities = capabilities
        self.clock = clock
        self.timeout = timeout
    }

    public func run(progress: @escaping @Sendable (TVTestCase, Bool?) -> Void) async -> TVTestResults {
        var results: [TVTestCase: Bool] = [:]
        do {
            try await server.ensureRunning()
        } catch {
            castLog("test", "Relais indisponible : \(error.localizedDescription)")
        }
        for testCase in TVTestCase.allCases {
            if Task.isCancelled { break }
            progress(testCase, nil)
            let passed = await runCase(testCase)
            results[testCase] = passed
            castLog("test", "\(testCase.label) : \(passed ? "OK" : "échec")")
            progress(testCase, passed)
            try? await renderer.stop()
            try? await clock.sleep(seconds: 1)
        }
        return TVTestResults(results: results, date: Date(), sink: capabilities.sinkMimes)
    }

    func runCase(_ testCase: TVTestCase) async -> Bool {
        guard let lan = server.lanBaseURL(), let loopback = server.baseURL(host: "127.0.0.1") else { return false }
        let media: PreparedMedia
        switch testCase {
        case .mp4:
            media = PreparedMedia(url: url(lan, .testFile("test.mp4")), mime: capabilities.mime(for: .mp4),
                                  seekable: true, offset: 0)
        case .hlsTS:
            media = PreparedMedia(url: url(lan, .testFile("hls/index.m3u8")), mime: capabilities.mime(for: .hls),
                                  seekable: true, offset: 0)
        case .hlsFMP4:
            media = PreparedMedia(url: url(lan, .testFile("fmp4/index.m3u8")), mime: capabilities.mime(for: .hls),
                                  seekable: true, offset: 0)
        case .liveTS:
            let id = "testts" + UUID().uuidString.prefix(8).lowercased()
            let playlist = url(loopback, .testFile("hls/index.m3u8"))
            let mime = capabilities.mime(for: .mpegTS)
            server.register(RelaySessionConfig(id: id, mode: .liveTS, sourceURL: playlist, mediaPlaylistURL: playlist,
                                               context: .none, mime: mime))
            media = PreparedMedia(url: url(lan, .liveTS(session: id, offsetMillis: 0)), mime: mime, seekable: false, offset: 0)
        case .liveFMP4:
            let id = "testfm" + UUID().uuidString.prefix(8).lowercased()
            let playlist = url(loopback, .testFile("fmp4/index.m3u8"))
            let mime = capabilities.mime(for: .fmp4)
            server.register(RelaySessionConfig(id: id, mode: .liveFMP4, sourceURL: playlist, mediaPlaylistURL: playlist,
                                               context: .none, mime: mime))
            media = PreparedMedia(url: url(lan, .liveFMP4(session: id, offsetMillis: 0)), mime: mime, seekable: false, offset: 0)
        }
        do {
            try await renderer.load(media, title: "TéléCast — test \(testCase.label)")
            try? await renderer.play()
            let start = clock.now()
            while clock.now().timeIntervalSince(start) < timeout {
                try await clock.sleep(seconds: 1)
                if let status = try? await renderer.status() {
                    if status.0.state == .playing { return true }
                    if status.0.isError { return false }
                }
            }
            return false
        } catch {
            castLog("test", "\(testCase.label) : \(error)")
            return false
        }
    }

    private func url(_ base: URL, _ route: RelayRoute) -> URL {
        URL(string: base.absoluteString + route.path) ?? base
    }
}
