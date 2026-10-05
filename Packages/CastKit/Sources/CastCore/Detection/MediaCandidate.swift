import Foundation

/// Summary of an HLS stream, filled in after reading its playlists.
public struct HLSInfo: Codable, Equatable, Sendable {
    public struct Variant: Codable, Equatable, Sendable {
        public var url: URL
        public var bandwidth: Int?
        public var width: Int?
        public var height: Int?
        public var hasSeparateAudio: Bool

        public init(url: URL, bandwidth: Int?, width: Int?, height: Int?, hasSeparateAudio: Bool) {
            self.url = url
            self.bandwidth = bandwidth
            self.width = width
            self.height = height
            self.hasSeparateAudio = hasSeparateAudio
        }
    }

    public var isMaster: Bool
    public var variants: [Variant]
    public var chosenVariantURL: URL
    public var totalDuration: Double?
    public var isLive: Bool
    public var segmentFormat: SegmentFormat
    public var hasSeparateAudio: Bool
    public var drm: Bool
    public var encrypted: Bool

    public init(isMaster: Bool, variants: [Variant], chosenVariantURL: URL, totalDuration: Double?, isLive: Bool,
                segmentFormat: SegmentFormat, hasSeparateAudio: Bool, drm: Bool, encrypted: Bool) {
        self.isMaster = isMaster
        self.variants = variants
        self.chosenVariantURL = chosenVariantURL
        self.totalDuration = totalDuration
        self.isLive = isLive
        self.segmentFormat = segmentFormat
        self.hasSeparateAudio = hasSeparateAudio
        self.drm = drm
        self.encrypted = encrypted
    }
}

/// A video found in the current page.
public struct MediaCandidate: Identifiable, Equatable, Sendable {
    public let id: String
    public var url: URL
    public var kind: MediaKind
    public var context: RequestContext
    public var frameURL: URL?
    public var pageURL: URL?
    public var pageTitle: String?
    public var via: Set<String>
    public var duration: Double?
    public var width: Int?
    public var height: Int?
    public var isPlaying: Bool
    public var firstSeen: Date
    public var lastSeen: Date
    public var hls: HLSInfo?

    public init(id: String, url: URL, kind: MediaKind, context: RequestContext, frameURL: URL?, pageURL: URL?,
                pageTitle: String?, via: Set<String>, duration: Double? = nil, width: Int? = nil, height: Int? = nil,
                isPlaying: Bool = false, firstSeen: Date, lastSeen: Date, hls: HLSInfo? = nil) {
        self.id = id
        self.url = url
        self.kind = kind
        self.context = context
        self.frameURL = frameURL
        self.pageURL = pageURL
        self.pageTitle = pageTitle
        self.via = via
        self.duration = duration
        self.width = width
        self.height = height
        self.isPlaying = isPlaying
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.hls = hls
    }

    public var effectiveDuration: Double? {
        if let duration, duration.isFinite, duration > 0 { return duration }
        if let total = hls?.totalDuration, total > 0 { return total }
        return nil
    }

    public var isDRM: Bool { hls?.drm ?? false }

    public var isCastable: Bool { kind != .dash && !isDRM }

    public var score: Int {
        var total = 0
        if isPlaying { total += 50 }
        if kind == .hls {
            total += 10
            if hls?.isMaster == true { total += 10 }
        }
        if !via.isDisjoint(with: ["video-src", "source", "media-event"]) { total += 15 }
        if let seconds = effectiveDuration {
            if seconds < 60 {
                total -= 40
            } else {
                total += min(Int(seconds / 60), 30)
            }
        }
        if isDRM { total -= 100 }
        if kind == .dash { total -= 20 }
        return total
    }

    public var displayTitle: String {
        if let pageTitle, !pageTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return pageTitle }
        let name = url.lastPathComponent
        if !name.isEmpty && name != "/" { return name }
        return url.host ?? url.absoluteString
    }
}

/// What the browser knows about the page when a detector message arrives.
public struct PageContext: Sendable {
    public var pageURL: URL?
    public var pageTitle: String?
    public var userAgent: String?
    public var cookies: [CookieRecord]

    public init(pageURL: URL?, pageTitle: String?, userAgent: String?, cookies: [CookieRecord]) {
        self.pageURL = pageURL
        self.pageTitle = pageTitle
        self.userAgent = userAgent
        self.cookies = cookies
    }
}
