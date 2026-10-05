import Foundation

/// How the relay serves a session.
public enum RelayMode: String, Codable, Sendable {
    /// Byte-for-byte passthrough of a progressive file (Range forwarded).
    case progressive
    /// HLS playlist rewritten so segments and keys come through the relay.
    case hlsProxy
    /// HLS with TS segments concatenated into one continuous MPEG-TS stream.
    case liveTS
    /// HLS with fMP4 segments concatenated (init section first) into one fragmented MP4 stream.
    case liveFMP4
}

public struct RelaySessionConfig: Sendable {
    public var id: String
    public var mode: RelayMode
    public var sourceURL: URL
    /// The media playlist to use for HLS modes (a variant chosen from the master).
    public var mediaPlaylistURL: URL?
    public var context: RequestContext
    /// Content-Type announced to the TV.
    public var mime: String

    public init(id: String, mode: RelayMode, sourceURL: URL, mediaPlaylistURL: URL?, context: RequestContext, mime: String) {
        self.id = id
        self.mode = mode
        self.sourceURL = sourceURL
        self.mediaPlaylistURL = mediaPlaylistURL
        self.context = context
        self.mime = mime
    }
}

/// DLNA-specific response headers.
public enum DLNAHeaders {
    public static func streaming(mime: String, seekable: Bool, requested: Bool) -> [(String, String)] {
        var headers: [(String, String)] = [("transferMode.dlna.org", "Streaming")]
        if requested {
            headers.append(("contentFeatures.dlna.org", DLNAFlags.additionalInfo(seekable: seekable)))
        }
        return headers
    }

    public static let cors: (String, String) = ("Access-Control-Allow-Origin", "*")
}
