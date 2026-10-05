import Foundation

public enum CastPhase: Equatable, Sendable {
    case preparing
    case trying(strategy: CastStrategy, attempt: Int, total: Int)
    case playing
    case paused
    case buffering
    case resuming(Int)
    case unreachable
    case failed(String)
    case ended
    case stopped

    public var isActive: Bool {
        switch self {
        case .failed, .ended, .stopped: return false
        default: return true
        }
    }
}

public struct CastSnapshot: Equatable, Sendable {
    public var phase: CastPhase
    public var strategy: CastStrategy?
    public var position: Double?
    public var duration: Double?
    public var isLive: Bool
    public var volume: Int?
    public var message: String?

    public init(phase: CastPhase, strategy: CastStrategy? = nil, position: Double? = nil, duration: Double? = nil,
                isLive: Bool = false, volume: Int? = nil, message: String? = nil) {
        self.phase = phase
        self.strategy = strategy
        self.position = position
        self.duration = duration
        self.isLive = isLive
        self.volume = volume
        self.message = message
    }
}

public struct CastSessionConfig: Sendable {
    public var directTimeout: Double = 12
    public var continuousTimeout: Double = 20
    public var relayContactTimeout: Double = 8
    public var pollInterval: Double = 1
    public var maxResumes: Int = 3
    public var resumeWindow: Double = 600
    public var unreachableAfterFailures: Int = 5
    public var unreachableGiveUp: Double = 120
    /// A TV still STOPPED this long after Play (and not fetching) refused the media.
    public var minStoppedGrace: Double = 6
    /// A stop closer than this to the end is a normal end of video.
    public var endTolerance: Double = 30

    public init() {}
}

/// Drives one cast: tries strategies in order, then watches playback, resumes after
/// unexpected stops and implements the remote control (pause, seek, volume).
public actor CastSession {
    private enum Outcome {
        case success
        case failure(String)
    }

    private let title: String
    private let strategies: [CastStrategy]
    private let knownDuration: Double?
    private let isLive: Bool
    private let startOffset: Double
    private let renderer: RendererControl
    private let media: MediaSource
    private let clock: SessionClock
    private let config: CastSessionConfig
    private let onUpdate: @Sendable (CastSnapshot) -> Void
    private let onSuccess: @Sendable (CastStrategy) -> Void

    private var state: CastSnapshot
    private var runTask: Task<Void, Never>?
    private var current: PreparedMedia?
    private var currentStrategy: CastStrategy?
    private var lastPosition: Double
    private var playStartedAt: Date?
    private var userStopped = false
    private var busy = false
    private var resumeDates: [Date] = []
    private var statusFailures = 0
    private var unreachableSince: Date?
    private var stoppedStreak = 0

    public init(title: String, strategies: [CastStrategy], knownDuration: Double?, isLive: Bool, startOffset: Double,
                renderer: RendererControl, media: MediaSource, clock: SessionClock,
                config: CastSessionConfig = CastSessionConfig(),
                onUpdate: @escaping @Sendable (CastSnapshot) -> Void,
                onSuccess: @escaping @Sendable (CastStrategy) -> Void) {
        self.title = title
        self.strategies = strategies
        self.knownDuration = knownDuration
        self.isLive = isLive
        self.startOffset = startOffset
        self.renderer = renderer
        self.media = media
        self.clock = clock
        self.config = config
        self.onUpdate = onUpdate
        self.onSuccess = onSuccess
        self.lastPosition = startOffset
        self.state = CastSnapshot(phase: .preparing, duration: knownDuration, isLive: isLive)
    }

    // MARK: - Public API

    public func start() {
        guard runTask == nil, !userStopped else { return }
        let offset = startOffset
        let list = strategies
        runTask = Task { [weak self] in
            await self?.run(from: offset, strategies: list)
        }
    }

    public func snapshot() -> CastSnapshot {
        state
    }

    public func stop() async {
        guard !userStopped else { return }
        userStopped = true
        runTask?.cancel()
        runTask = nil
        publish(phase: .stopped, message: nil)
        try? await renderer.stop()
        await media.release()
    }

    public func togglePause() async {
        guard state.phase.isActive, !busy, !userStopped else { return }
        do {
            if state.phase == .paused {
                try await renderer.play()
                publish(phase: .playing, message: nil)
            } else {
                try await renderer.pause()
                publish(phase: .paused, message: nil)
            }
        } catch {
            publish(message: "La TV a refusé : \(Self.describe(error))")
        }
    }

    public func seek(to target: Double) async {
        guard let strategy = currentStrategy, state.phase.isActive, !isLive, !busy, !userStopped else { return }
        var clamped = max(0, target)
        if let duration = effectiveDuration {
            clamped = min(clamped, max(0, duration - 5))
        }
        busy = true
        defer { busy = false }
        if strategy.isContinuous {
            publish(phase: .buffering, message: "Déplacement à \(Self.timeLabel(clamped))…")
            switch await attempt(strategy, offset: clamped) {
            case .success:
                lastPosition = clamped
                state.position = clamped
                publish(phase: .playing, message: nil)
            case .failure(let reason):
                publish(phase: .failed(reason), message: reason)
            }
        } else {
            do {
                try await renderer.seek(to: clamped)
                lastPosition = clamped
                state.position = clamped
                emit()
            } catch {
                publish(message: "La TV ne permet pas d'avancer dans cette vidéo.")
            }
        }
    }

    public func skip(by delta: Double) async {
        await seek(to: (state.position ?? lastPosition) + delta)
    }

    public func setVolume(_ value: Int) async {
        let clamped = max(0, min(100, value))
        do {
            try await renderer.setVolume(clamped)
            state.volume = clamped
            emit()
        } catch {
            publish(message: "Volume non réglable sur cette TV.")
        }
    }

    /// Manual "Relancer": tries again from the last position, current strategy first.
    public func restart() {
        guard !userStopped else { return }
        let position = lastPosition
        var ordered = strategies
        if let strategy = currentStrategy, let index = ordered.firstIndex(of: strategy) {
            ordered.remove(at: index)
            ordered.insert(strategy, at: 0)
        }
        resumeDates.removeAll()
        runTask?.cancel()
        runTask = Task { [weak self] in
            await self?.run(from: position, strategies: ordered)
        }
    }

    // MARK: - Run loop

    private func run(from offset: Double, strategies list: [CastStrategy]) async {
        publish(phase: .preparing, message: "Préparation…")
        let ok = await runTrials(from: offset, strategies: list)
        guard ok, !Task.isCancelled, !userStopped else { return }
        if let volume = try? await renderer.volume() {
            state.volume = volume
            emit()
        }
        await monitor()
    }

    private func runTrials(from offset: Double, strategies list: [CastStrategy]) async -> Bool {
        var lastReason = "La TV n'a pas pu lire la vidéo."
        for (index, strategy) in list.enumerated() {
            if Task.isCancelled || userStopped { return false }
            publish(phase: .trying(strategy: strategy, attempt: index + 1, total: list.count),
                    message: "Essai \(index + 1)/\(list.count) : \(strategy.label)…")
            switch await attempt(strategy, offset: offset) {
            case .success:
                castLog("cast", "Lecture démarrée (\(strategy.rawValue))")
                onSuccess(strategy)
                publish(phase: .playing, message: nil)
                return true
            case .failure(let reason):
                lastReason = reason
                castLog("cast", "Échec \(strategy.rawValue) : \(reason)")
                if Task.isCancelled || userStopped { return false }
                try? await renderer.stop()
            }
        }
        if Task.isCancelled || userStopped { return false }
        let message = list.count > 1
            ? "La TV n'a pu lire la vidéo dans aucun mode. Dernière erreur : \(lastReason)"
            : lastReason
        publish(phase: .failed(message), message: message)
        return false
    }

    private func attempt(_ strategy: CastStrategy, offset: Double) async -> Outcome {
        do {
            let prepared = try await media.prepare(strategy: strategy, offset: strategy.isContinuous ? offset : 0)
            current = prepared
            currentStrategy = strategy
            state.strategy = strategy
            stoppedStreak = 0
            playStartedAt = nil
            let startedAt = clock.now()
            try await renderer.load(prepared, title: title)
            do {
                try await renderer.play()
            } catch {
                castLog("cast", "Play ignoré : \(Self.describe(error))")
            }
            let timeout = strategy.isContinuous ? config.continuousTimeout : config.directTimeout
            let outcome = await waitForPlaying(timeout: timeout, since: startedAt, usesRelay: strategy.usesRelay)
            if case .success = outcome, !strategy.isContinuous, offset > 1 {
                do {
                    try await renderer.seek(to: offset)
                    lastPosition = offset
                    state.position = offset
                } catch {
                    castLog("cast", "Positionnement initial refusé : \(Self.describe(error))")
                }
            }
            return outcome
        } catch {
            return .failure(Self.describe(error))
        }
    }

    private func waitForPlaying(timeout: Double, since start: Date, usesRelay: Bool) async -> Outcome {
        var statusErrors = 0
        while true {
            if Task.isCancelled || userStopped { return .failure("Annulé.") }
            do {
                try await clock.sleep(seconds: config.pollInterval)
            } catch {
                return .failure("Annulé.")
            }
            let elapsed = clock.now().timeIntervalSince(start)
            do {
                let (info, position) = try await renderer.status()
                statusErrors = 0
                if info.isError { return .failure("La TV signale une erreur de lecture.") }
                switch info.state {
                case .playing:
                    playStartedAt = clock.now()
                    updatePosition(position)
                    return .success
                case .paused:
                    try? await renderer.play()
                    playStartedAt = clock.now()
                    return .success
                case .stopped, .noMedia:
                    let tvIsFetching = usesRelay && media.wasFetched(after: start)
                    if elapsed >= config.minStoppedGrace && !tvIsFetching {
                        return .failure("La TV a refusé la vidéo dans ce mode.")
                    }
                case .transitioning, .unknown:
                    break
                }
            } catch {
                statusErrors += 1
                if statusErrors >= 3 { return .failure("La TV ne répond plus.") }
            }
            if usesRelay, elapsed >= config.relayContactTimeout, !media.wasFetched(after: start) {
                return .failure("La TV n'arrive pas à joindre le téléphone. Vérifie que les deux sont sur le même Wi-Fi "
                                + "(et que l'isolation Wi-Fi de la box est désactivée).")
            }
            if elapsed >= timeout { return .failure("La TV n'a pas démarré la lecture à temps.") }
        }
    }

    private func monitor() async {
        while !Task.isCancelled && !userStopped {
            do {
                try await clock.sleep(seconds: config.pollInterval)
            } catch {
                return
            }
            if busy || userStopped { continue }
            let status: (TransportInfo, PositionInfo)
            do {
                status = try await renderer.status()
            } catch {
                if handleStatusFailure() { continue }
                return
            }
            if busy || userStopped { continue }
            let (info, position) = status
            statusFailures = 0
            unreachableSince = nil
            switch info.state {
            case .playing:
                stoppedStreak = 0
                updatePosition(position)
                if playStartedAt == nil { playStartedAt = clock.now() }
                setPhase(.playing)
            case .paused:
                stoppedStreak = 0
                updatePosition(position)
                setPhase(.paused)
            case .transitioning:
                stoppedStreak = 0
                setPhase(.buffering)
            case .unknown:
                break
            case .stopped, .noMedia:
                stoppedStreak += 1
                guard stoppedStreak >= 2 else { continue }
                stoppedStreak = 0
                if !isUnexpectedStop() {
                    publish(phase: .ended, message: "Lecture terminée.")
                    return
                }
                guard canResume() else {
                    let message = "La lecture s'est arrêtée plusieurs fois. Appuie sur « Relancer »."
                    publish(phase: .failed(message), message: message)
                    return
                }
                let resumed = await resume()
                if !resumed { return }
            }
        }
    }

    /// Returns false when the session should give up.
    private func handleStatusFailure() -> Bool {
        statusFailures += 1
        guard statusFailures >= config.unreachableAfterFailures else { return true }
        let now = clock.now()
        if unreachableSince == nil { unreachableSince = now }
        if let since = unreachableSince, now.timeIntervalSince(since) >= config.unreachableGiveUp {
            let message = "La TV ne répond plus."
            publish(phase: .failed(message), message: message)
            return false
        }
        setPhase(.unreachable, message: "TV injoignable, nouvelle tentative…")
        return true
    }

    private func resume() async -> Bool {
        guard let strategy = currentStrategy else { return false }
        resumeDates.append(clock.now())
        let position = lastPosition
        publish(phase: .resuming(resumeDates.count), message: "Coupure détectée : reprise à \(Self.timeLabel(position))…")
        castLog("cast", "Reprise automatique à \(Int(position)) s (\(strategy.rawValue))")
        busy = true
        defer { busy = false }
        if case .success = await attempt(strategy, offset: position) {
            publish(phase: .playing, message: nil)
            return true
        }
        let others = strategies.filter { $0 != strategy }
        guard !others.isEmpty else {
            let message = "Impossible de reprendre la lecture."
            publish(phase: .failed(message), message: message)
            return false
        }
        return await runTrials(from: position, strategies: others)
    }

    private func isUnexpectedStop() -> Bool {
        if isLive { return true }
        if let duration = effectiveDuration {
            return lastPosition < duration - config.endTolerance
        }
        guard let started = playStartedAt else { return false }
        return clock.now().timeIntervalSince(started) > 30
    }

    private func canResume() -> Bool {
        let now = clock.now()
        resumeDates = resumeDates.filter { now.timeIntervalSince($0) < config.resumeWindow }
        return resumeDates.count < config.maxResumes
    }

    // MARK: - State helpers

    private var effectiveDuration: Double? {
        knownDuration ?? state.duration
    }

    private func updatePosition(_ info: PositionInfo) {
        guard let strategy = currentStrategy else { return }
        if let tvPosition = info.position {
            let absolute = strategy.isContinuous ? (current?.offset ?? 0) + tvPosition : tvPosition
            lastPosition = absolute
            state.position = absolute
        }
        if knownDuration == nil, !strategy.isContinuous, let duration = info.duration, duration > 0 {
            state.duration = duration
        }
    }

    private func setPhase(_ phase: CastPhase, message: String? = nil) {
        if state.phase != phase {
            state.phase = phase
            state.message = message
        }
        emit()
    }

    private func publish(phase: CastPhase, message: String?) {
        state.phase = phase
        state.message = message
        emit()
    }

    private func publish(message: String?) {
        state.message = message
        emit()
    }

    private func emit() {
        onUpdate(state)
    }

    // MARK: - Formatting

    static func describe(_ error: Error) -> String {
        if let dlna = error as? DLNAError {
            switch dlna {
            case .soapFault(let fault):
                let code = fault.code.map { " (code \($0))" } ?? ""
                let detail = fault.detail.map { " : \($0)" } ?? ""
                return "La TV a refusé\(code)\(detail)."
            case .httpStatus(let status):
                return "La TV a répondu une erreur HTTP \(status)."
            case .missingService(let name):
                return "La TV ne gère pas \(name)."
            case .badResponse:
                return "Réponse illisible de la TV."
            }
        }
        if error is CancellationError { return "Annulé." }
        return error.localizedDescription
    }

    public static func timeLabel(_ seconds: Double) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds)) : 0
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%ld:%02ld:%02ld", hours, minutes, secs) }
        return String(format: "%ld:%02ld", minutes, secs)
    }
}
