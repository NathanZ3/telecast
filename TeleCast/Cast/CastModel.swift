import Foundation
import Observation
import CastCore
import CastNet

/// Starts casts (inspection, preflight, strategy plan, session) and exposes the remote control.
@MainActor
@Observable
final class CastModel {
    @ObservationIgnored weak var app: AppModel?
    @ObservationIgnored let relay: RelayServer
    @ObservationIgnored let fetcher: UpstreamFetcher
    @ObservationIgnored let settings: SettingsModel
    @ObservationIgnored let devices: DeviceModel
    @ObservationIgnored private var session: CastSession?
    @ObservationIgnored private var memory = StrategyMemory()
    @ObservationIgnored private let memoryStore = JSONFileStore(
        url: JSONFileStore<StrategyMemory>.applicationSupportURL(named: "strategies"), defaultValue: StrategyMemory())
    @ObservationIgnored private let nowPlaying = NowPlayingController()

    private(set) var snapshot: CastSnapshot?
    private(set) var title = ""
    private(set) var tvName = ""
    private(set) var candidate: MediaCandidate?
    private(set) var variants: [HLSInfo.Variant] = []
    private(set) var currentVariantURL: URL?
    private(set) var isStarting = false

    var isActive: Bool { isStarting || (snapshot?.phase.isActive ?? false) }

    init(relay: RelayServer, fetcher: UpstreamFetcher, settings: SettingsModel, devices: DeviceModel) {
        self.relay = relay
        self.fetcher = fetcher
        self.settings = settings
        self.devices = devices
        memory = memoryStore.load()
    }

    // MARK: Start

    func cast(_ candidate: MediaCandidate, startAt: Double = 0, preferredVariant: URL? = nil) async {
        guard let tv = devices.selected else {
            app?.sheet = .devices
            app?.showToast(Toast(text: "Choisis d'abord ta TV."))
            return
        }
        if session != nil {
            await stopSession(clearUI: false)
        }
        isStarting = true
        self.candidate = candidate
        title = candidate.displayTitle
        tvName = tv.name
        snapshot = CastSnapshot(phase: .preparing, message: "Préparation…")
        app?.sheet = .remote
        KeepAlive.shared.start()
        castLog("cast", "Cast de \(candidate.url.host ?? "?") (\(candidate.kind.rawValue)) vers \(tv.name)")

        let context = await app?.browser.freshContext(for: candidate) ?? candidate.context

        var info = candidate.hls
        var mediaPlaylistURL: URL?
        var firstSegment: URL?
        if candidate.kind == .hls {
            do {
                let inspected = try await HLSInspector.inspect(url: candidate.url, context: context,
                                                               cap: settings.value.quality,
                                                               preferredVariant: preferredVariant, fetcher: fetcher)
                info = inspected.info
                mediaPlaylistURL = inspected.mediaURL
                firstSegment = inspected.media.segments.first?.uri
                variants = inspected.info.variants
                currentVariantURL = inspected.mediaURL
            } catch {
                fail("Impossible de lire la vidéo sur le site (\(error.localizedDescription)). Relance la vidéo sur la page puis réessaie.")
                return
            }
        } else {
            variants = []
            currentVariantURL = nil
        }

        let profile = ContentProfile(kind: candidate.kind, segmentFormat: info?.segmentFormat ?? .unknown,
                                     hasSeparateAudio: info?.hasSeparateAudio ?? false, drm: info?.drm ?? false,
                                     host: candidate.url.host ?? "")
        var reachable = false
        if settings.value.mode != .alwaysRelay {
            reachable = await Preflight.directReachable(url: mediaPlaylistURL ?? candidate.url, firstSegment: firstSegment)
        }

        let strategies: [CastStrategy]
        do {
            strategies = try StrategyPlanner.plan(profile: profile, capabilities: tv.capabilities,
                                                  preflight: PreflightResult(directReachable: reachable),
                                                  preference: settings.value.mode,
                                                  remembered: memory.recall(tv: tv.id, profile: profile), tests: tv.tests)
        } catch PlanError.drm {
            fail("Cette vidéo est protégée (DRM) : aucune appli ne peut la caster.")
            return
        } catch {
            fail("Les vidéos DASH ne sont pas prises en charge par les TV DLNA.")
            return
        }
        castLog("cast", "Lien direct possible : \(reachable ? "oui" : "non") · essais : \(strategies.map(\.rawValue).joined(separator: ", "))")

        let media = RelayMediaSource(server: relay, sourceURL: candidate.url, kind: candidate.kind,
                                     mediaPlaylistURL: mediaPlaylistURL, context: context, capabilities: tv.capabilities)
        let tvID = tv.id
        let newSession = CastSession(
            title: title, strategies: strategies, knownDuration: info?.totalDuration ?? candidate.effectiveDuration,
            isLive: info?.isLive ?? false, startOffset: startAt, renderer: devices.control(for: tv), media: media,
            clock: SystemClock(),
            onUpdate: { [weak self] snapshot in
                Task { @MainActor in self?.apply(snapshot) }
            },
            onSuccess: { [weak self] strategy in
                Task { @MainActor in self?.remember(strategy, tv: tvID, profile: profile) }
            })
        session = newSession
        isStarting = false
        nowPlaying.activate(cast: self)
        await newSession.start()
    }

    private func fail(_ message: String) {
        isStarting = false
        snapshot = CastSnapshot(phase: .failed(message), message: message)
        KeepAlive.shared.stop()
        castLog("cast", message)
    }

    private func apply(_ snapshot: CastSnapshot) {
        guard session != nil else { return }
        self.snapshot = snapshot
        nowPlaying.update(title: title, snapshot: snapshot)
        if !snapshot.phase.isActive {
            KeepAlive.shared.stop()
        }
    }

    private func remember(_ strategy: CastStrategy, tv: String, profile: ContentProfile) {
        memory.remember(strategy, tv: tv, profile: profile)
        memoryStore.save(memory)
    }

    // MARK: Remote

    func togglePause() {
        guard let session else { return }
        Task { await session.togglePause() }
    }

    func seek(to seconds: Double) {
        guard let session else { return }
        Task { await session.seek(to: seconds) }
    }

    func skip(_ delta: Double) {
        guard let session else { return }
        Task { await session.skip(by: delta) }
    }

    func setVolume(_ value: Int) {
        guard let session else { return }
        Task { await session.setVolume(value) }
    }

    func restart() {
        guard let session else {
            if let candidate { Task { await cast(candidate) } }
            return
        }
        KeepAlive.shared.start()
        Task { await session.restart() }
    }

    func changeQuality(_ variant: HLSInfo.Variant) {
        guard let candidate else { return }
        let position = snapshot?.position ?? 0
        Task { await cast(candidate, startAt: position, preferredVariant: variant.url) }
    }

    func stop() {
        Task { await stopSession(clearUI: true) }
    }

    private func stopSession(clearUI: Bool) async {
        let current = session
        session = nil
        await current?.stop()
        KeepAlive.shared.stop()
        nowPlaying.deactivate()
        if clearUI {
            snapshot = nil
            candidate = nil
            variants = []
            currentVariantURL = nil
        }
    }

    // MARK: Display

    static func statusText(_ snapshot: CastSnapshot?) -> String {
        guard let snapshot else { return "" }
        switch snapshot.phase {
        case .preparing:
            return snapshot.message ?? "Préparation…"
        case .trying:
            return snapshot.message ?? "Connexion à la TV…"
        case .playing:
            return snapshot.strategy.map { "Lecture · \($0.label)" } ?? "Lecture"
        case .paused:
            return "En pause"
        case .buffering:
            return snapshot.message ?? "Chargement…"
        case .resuming:
            return snapshot.message ?? "Reprise automatique…"
        case .unreachable:
            return "TV injoignable, nouvelle tentative…"
        case .failed(let message):
            return message
        case .ended:
            return "Vidéo terminée"
        case .stopped:
            return "Arrêté"
        }
    }
}
