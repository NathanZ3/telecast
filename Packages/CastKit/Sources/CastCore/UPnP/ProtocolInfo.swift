import Foundation

/// One `protocol:network:contentFormat:additionalInfo` entry (UPnP ConnectionManager).
public struct ProtocolInfo: Hashable, Sendable {
    public var transport: String
    public var network: String
    public var mime: String
    public var additional: String

    public init?(_ string: String) {
        let parts = string.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
            .map(String.init)
        guard parts.count == 4, !parts[2].isEmpty else { return nil }
        transport = parts[0]
        network = parts[1]
        mime = parts[2]
        additional = parts[3]
    }

    public var string: String { "\(transport):\(network):\(mime):\(additional)" }

    public static func parseList(_ csv: String) -> [ProtocolInfo] {
        csv.split(separator: ",").compactMap { ProtocolInfo(String($0)) }
    }
}

/// Container of the stream we hand to the TV.
public enum StreamContainer: String, Codable, Sendable {
    case mp4, mpegTS, hls, fmp4, webm, mkv, mov
}

/// What a TV says it can play (ConnectionManager `GetProtocolInfo` → Sink).
public struct RendererCapabilities: Codable, Hashable, Sendable {
    /// Mime types as spelled by the TV, deduplicated case-insensitively.
    public var sinkMimes: [String]

    public init(sinkMimes: [String]) {
        var seen = Set<String>()
        var list: [String] = []
        for mime in sinkMimes {
            let trimmed = mime.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            list.append(trimmed)
        }
        self.sinkMimes = list
    }

    public init(sink: [ProtocolInfo]) {
        self.init(sinkMimes: sink.map(\.mime))
    }

    public static let unknown = RendererCapabilities(sinkMimes: [])

    static let hlsMimes: Set<String> = [
        "application/vnd.apple.mpegurl", "application/x-mpegurl", "application/mpegurl",
        "audio/mpegurl", "audio/x-mpegurl",
    ]

    public var isKnown: Bool { !sinkMimes.isEmpty }

    public var announcesHLS: Bool {
        sinkMimes.contains { Self.hlsMimes.contains($0.lowercased()) }
    }

    /// Unknown capabilities are treated as "may play video".
    public var hasVideo: Bool {
        !isKnown || announcesHLS || sinkMimes.contains { $0.lowercased().hasPrefix("video/") }
    }

    public func mime(for container: StreamContainer) -> String {
        switch container {
        case .mpegTS:
            return find(["video/mp2t", "video/mpeg", "video/vnd.dlna.mpeg-tts"]) ?? "video/mpeg"
        case .hls:
            return find(["application/vnd.apple.mpegurl", "application/x-mpegurl"]) ?? "application/vnd.apple.mpegurl"
        case .mp4, .fmp4:
            return find(["video/mp4"]) ?? "video/mp4"
        case .webm:
            return find(["video/webm"]) ?? "video/webm"
        case .mkv:
            return find(["video/x-matroska", "video/x-mkv", "video/mkv"]) ?? "video/x-matroska"
        case .mov:
            return find(["video/quicktime"]) ?? "video/quicktime"
        }
    }

    private func find(_ candidates: [String]) -> String? {
        for candidate in candidates {
            if let match = sinkMimes.first(where: { $0.lowercased() == candidate }) { return match }
        }
        return nil
    }
}

/// DLNA `additionalInfo` flags for the media we serve.
public enum DLNAFlags {
    /// Streaming transfer mode + background + connection stall + DLNA 1.5.
    public static let streamingFlags = "01700000000000000000000000000000"

    public static func additionalInfo(seekable: Bool) -> String {
        "DLNA.ORG_OP=\(seekable ? "01" : "00");DLNA.ORG_CI=0;DLNA.ORG_FLAGS=\(streamingFlags)"
    }

    public static func protocolInfo(mime: String, seekable: Bool) -> String {
        "http-get:*:\(mime):\(additionalInfo(seekable: seekable))"
    }
}
