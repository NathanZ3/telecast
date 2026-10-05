import Foundation

/// Kind of media stream detected in a web page.
public enum MediaKind: String, Codable, Sendable, Hashable {
    case hls
    case dash
    case progressive
}

/// Container used by the media segments of an HLS stream.
public enum SegmentFormat: String, Codable, Sendable, Hashable {
    case ts
    case fmp4
    case unknown
}
