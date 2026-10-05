import Foundation

/// How the video reaches the TV.
public enum CastStrategy: String, Codable, CaseIterable, Sendable {
    /// The TV loads the original URL.
    case direct
    /// The TV reads a progressive file through the phone (headers added, Range forwarded).
    case relayProgressive
    /// The TV reads a rewritten HLS playlist; segments come through the phone.
    case relayHLS
    /// The phone turns HLS (TS segments) into one continuous MPEG-TS stream.
    case relayTS
    /// The phone turns HLS (fMP4 segments) into one continuous fragmented MP4 stream.
    case relayFMP4

    public var usesRelay: Bool { self != .direct }

    public var isContinuous: Bool { self == .relayTS || self == .relayFMP4 }

    public var label: String {
        switch self {
        case .direct: return "Lien direct"
        case .relayProgressive: return "Relais du téléphone"
        case .relayHLS: return "Relais HLS"
        case .relayTS: return "Flux continu (TS)"
        case .relayFMP4: return "Flux continu (MP4)"
        }
    }
}

public enum CastModePreference: String, Codable, CaseIterable, Sendable {
    case auto
    case alwaysRelay
    case alwaysDirect

    public var label: String {
        switch self {
        case .auto: return "Automatique"
        case .alwaysRelay: return "Toujours par le téléphone"
        case .alwaysDirect: return "Toujours en direct"
        }
    }
}

/// The properties of a video that decide which strategies make sense.
public struct ContentProfile: Hashable, Codable, Sendable {
    public var kind: MediaKind
    public var segmentFormat: SegmentFormat
    public var hasSeparateAudio: Bool
    public var drm: Bool
    public var host: String

    public init(kind: MediaKind, segmentFormat: SegmentFormat = .unknown, hasSeparateAudio: Bool = false,
                drm: Bool = false, host: String) {
        self.kind = kind
        self.segmentFormat = segmentFormat
        self.hasSeparateAudio = hasSeparateAudio
        self.drm = drm
        self.host = host
    }
}

/// Whether the media answers without any browser header (as the TV would request it).
public struct PreflightResult: Equatable, Sendable {
    public var directReachable: Bool

    public init(directReachable: Bool) {
        self.directReachable = directReachable
    }
}

public enum PlanError: Error, Equatable {
    case drm
    case dashUnsupported
}
