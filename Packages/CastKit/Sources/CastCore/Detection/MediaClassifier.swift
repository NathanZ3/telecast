import Foundation

public enum MediaClassification: Equatable, Sendable {
    case media(MediaKind)
    case ignored(String)
}

/// Decides whether a URL seen in a page is a castable media (and which kind).
public enum MediaClassifier {
    static let hlsMimes: Set<String> = [
        "application/vnd.apple.mpegurl", "application/x-mpegurl", "application/mpegurl",
        "audio/mpegurl", "audio/x-mpegurl",
    ]
    static let dashMimes: Set<String> = ["application/dash+xml"]
    static let segmentExtensions: Set<String> = [
        "ts", "m4s", "aac", "ac3", "ec3", "vtt", "webvtt", "srt", "key", "m4a", "mp3", "cmfv", "cmfa", "m4f",
    ]
    static let progressiveExtensions: Set<String> = ["mp4", "m4v", "mov", "webm", "mkv"]
    static let nonMediaExtensions: Set<String> = [
        "js", "css", "json", "html", "htm", "png", "jpg", "jpeg", "gif", "webp", "svg", "ico", "woff", "woff2", "ttf",
    ]
    static let networkVias: Set<String> = ["fetch", "xhr", "perf"]

    public static func classify(url: URL, mime: String?, via: String?) -> MediaClassification {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .ignored("scheme")
        }
        guard let host = url.host?.lowercased() else { return .ignored("no-host") }
        if host.hasSuffix("googlevideo.com") || host == "youtube.com" || host.hasSuffix(".youtube.com") {
            return .ignored("youtube")
        }
        if AdHostMatcher.builtIn.matches(host: host) { return .ignored("ad") }

        let lowerURL = url.absoluteString.lowercased()
        let ext = url.pathExtension.lowercased()
        let type = mime.map(normalizedMime) ?? ""

        if hlsMimes.contains(type) || ext == "m3u8" || lowerURL.contains(".m3u8") { return .media(.hls) }
        if dashMimes.contains(type) || ext == "mpd" { return .media(.dash) }
        if type == "video/mp2t" || type == "video/iso.segment" || type.hasPrefix("audio/") || segmentExtensions.contains(ext) {
            return .ignored("segment")
        }
        if nonMediaExtensions.contains(ext) { return .ignored("not-media") }
        if progressiveExtensions.contains(ext) || type.hasPrefix("video/") {
            if let via, networkVias.contains(via), looksLikeSegment(url.lastPathComponent) {
                return .ignored("segment")
            }
            return .media(.progressive)
        }
        return .ignored("not-media")
    }

    static func normalizedMime(_ mime: String) -> String {
        guard let first = mime.split(separator: ";").first else { return "" }
        return first.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Heuristic for media-segment file names (`seg-12.mp4`, `chunk_3.m4s`, `000123.mp4`, `init.mp4`…).
    public static func looksLikeSegment(_ lastPathComponent: String) -> Bool {
        let name = lastPathComponent.lowercased()
        let stem: String
        if let dot = name.lastIndex(of: ".") {
            stem = String(name[..<dot])
        } else {
            stem = name
        }
        guard !stem.isEmpty else { return false }
        let markers = ["seg", "chunk", "frag", "init", "part", "range"]
        if markers.contains(where: { stem.contains($0) }) { return true }
        if stem.allSatisfy(\.isNumber) { return true }
        let pieces = stem.split(whereSeparator: { $0 == "-" || $0 == "_" })
        if pieces.count > 1, let last = pieces.last, last.allSatisfy(\.isNumber) { return true }
        return false
    }
}
