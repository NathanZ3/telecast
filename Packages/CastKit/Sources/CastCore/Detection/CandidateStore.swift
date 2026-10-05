import Foundation

/// The videos detected in the current page, deduplicated and ranked.
public struct CandidateStore: Sendable {
    public private(set) var candidates: [MediaCandidate] = []

    public init() {}

    /// Lowercased host + path: the same video requested with a fresh token keeps its identity.
    public static func candidateID(for url: URL) -> String {
        (url.host?.lowercased() ?? "") + url.path
    }

    /// Returns true when the list changed.
    @discardableResult
    public mutating func ingest(_ message: DetectorMessage, frameURL: URL?, page: PageContext, now: Date = Date()) -> Bool {
        switch message.kind {
        case .hello:
            return false
        case .playing:
            return markPlaying(frameURL: frameURL, duration: message.duration)
        case .candidate:
            guard let raw = message.url, let url = URL(string: raw) else { return false }
            guard case let .media(kind) = MediaClassifier.classify(url: url, mime: message.mime, via: message.via) else {
                return false
            }
            let id = Self.candidateID(for: url)
            let context = ContextBuilder.make(requestURL: url, frameURL: frameURL, via: message.via,
                                              userAgent: page.userAgent, cookies: page.cookies, now: now)
            if let index = candidates.firstIndex(where: { $0.id == id }) {
                var existing = candidates[index]
                existing.url = url
                existing.context = context
                existing.lastSeen = now
                if let via = message.via { existing.via.insert(via) }
                if let seconds = Self.validDuration(message.duration) { existing.duration = seconds }
                if let width = Self.positiveInt(message.width) { existing.width = width }
                if let height = Self.positiveInt(message.height) { existing.height = height }
                if message.playing == true { existing.isPlaying = true }
                if existing.pageTitle == nil { existing.pageTitle = page.pageTitle }
                candidates[index] = existing
            } else {
                var via = Set<String>()
                if let source = message.via { via.insert(source) }
                let candidate = MediaCandidate(
                    id: id, url: url, kind: kind, context: context, frameURL: frameURL,
                    pageURL: page.pageURL, pageTitle: page.pageTitle, via: via,
                    duration: Self.validDuration(message.duration),
                    width: Self.positiveInt(message.width), height: Self.positiveInt(message.height),
                    isPlaying: message.playing == true, firstSeen: now, lastSeen: now)
                candidates.append(candidate)
            }
            sortCandidates()
            return true
        }
    }

    public mutating func setHLSInfo(_ info: HLSInfo, for id: String) {
        guard let index = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[index].hls = info
        sortCandidates()
    }

    public mutating func reset() {
        candidates.removeAll()
    }

    /// A media element of `frameURL` plays a `blob:` source (MediaSource): the most recent
    /// streaming manifest seen in that frame is the one being played.
    mutating func markPlaying(frameURL: URL?, duration: Double?) -> Bool {
        let frameKey = frameURL?.absoluteString
        let streaming = candidates.indices.filter {
            candidates[$0].kind != .progressive && candidates[$0].frameURL?.absoluteString == frameKey
        }
        guard let index = streaming.max(by: { candidates[$0].lastSeen < candidates[$1].lastSeen }) else {
            return false
        }
        candidates[index].isPlaying = true
        if let seconds = Self.validDuration(duration) { candidates[index].duration = seconds }
        sortCandidates()
        return true
    }

    static func validDuration(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    static func positiveInt(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return Int(value)
    }

    mutating func sortCandidates() {
        candidates.sort { lhs, rhs in
            let left = lhs.score
            let right = rhs.score
            if left != right { return left > right }
            return lhs.lastSeen > rhs.lastSeen
        }
    }
}
