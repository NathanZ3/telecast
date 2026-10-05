import Foundation
import CastCore

public enum RelayMediaError: Error, Equatable {
    case relayUnavailable
}

/// `MediaSource` that gives the TV either the original URL (`direct`) or a relay URL
/// registered on the phone's `RelayServer` for the requested strategy.
public final class RelayMediaSource: MediaSource, @unchecked Sendable {
    private let server: RelayServer
    private let sourceURL: URL
    private let kind: MediaKind
    private let mediaPlaylistURL: URL?
    private let context: RequestContext
    private let capabilities: RendererCapabilities
    private let lock = NSLock()
    private var sessionIDs: [String] = []

    public init(server: RelayServer, sourceURL: URL, kind: MediaKind, mediaPlaylistURL: URL?, context: RequestContext,
                capabilities: RendererCapabilities) {
        self.server = server
        self.sourceURL = sourceURL
        self.kind = kind
        self.mediaPlaylistURL = mediaPlaylistURL
        self.context = context
        self.capabilities = capabilities
    }

    public func prepare(strategy: CastStrategy, offset: Double) async throws -> PreparedMedia {
        switch strategy {
        case .direct:
            if kind == .hls {
                return PreparedMedia(url: mediaPlaylistURL ?? sourceURL, mime: capabilities.mime(for: .hls),
                                     seekable: true, offset: 0)
            }
            return PreparedMedia(url: sourceURL, mime: capabilities.mime(for: Self.container(for: sourceURL)),
                                 seekable: true, offset: 0)
        case .relayProgressive:
            let mime = capabilities.mime(for: Self.container(for: sourceURL))
            let id = try await register(.progressive, mime: mime)
            let url = try relayURL(.progressive(session: id, ext: Self.fileExtension(for: sourceURL)))
            return PreparedMedia(url: url, mime: mime, seekable: true, offset: 0)
        case .relayHLS:
            let mime = capabilities.mime(for: .hls)
            let id = try await register(.hlsProxy, mime: mime)
            return PreparedMedia(url: try relayURL(.playlist(session: id)), mime: mime, seekable: true, offset: 0)
        case .relayTS:
            let mime = capabilities.mime(for: .mpegTS)
            let id = try await register(.liveTS, mime: mime)
            let url = try relayURL(.liveTS(session: id, offsetMillis: Int(max(0, offset) * 1000)))
            return PreparedMedia(url: url, mime: mime, seekable: false, offset: max(0, offset))
        case .relayFMP4:
            let mime = capabilities.mime(for: .fmp4)
            let id = try await register(.liveFMP4, mime: mime)
            let url = try relayURL(.liveFMP4(session: id, offsetMillis: Int(max(0, offset) * 1000)))
            return PreparedMedia(url: url, mime: mime, seekable: false, offset: max(0, offset))
        }
    }

    public func wasFetched(after date: Date) -> Bool {
        let ids = lock.withLock { sessionIDs }
        return ids.contains { id in
            guard let contact = server.lastContact(id) else { return false }
            return contact >= date
        }
    }

    public func release() async {
        let ids: [String] = lock.withLock {
            let all = sessionIDs
            sessionIDs.removeAll()
            return all
        }
        for id in ids {
            server.unregister(id)
        }
    }

    private func register(_ mode: RelayMode, mime: String) async throws -> String {
        do {
            try await server.ensureRunning()
        } catch {
            throw RelayMediaError.relayUnavailable
        }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        server.register(RelaySessionConfig(id: id, mode: mode, sourceURL: sourceURL, mediaPlaylistURL: mediaPlaylistURL,
                                           context: context, mime: mime))
        let stale: [String] = lock.withLock {
            sessionIDs.append(id)
            guard sessionIDs.count > 3 else { return [] }
            let removed = Array(sessionIDs.prefix(sessionIDs.count - 3))
            sessionIDs.removeFirst(sessionIDs.count - 3)
            return removed
        }
        for oldID in stale {
            server.unregister(oldID)
        }
        return id
    }

    private func relayURL(_ route: RelayRoute) throws -> URL {
        guard let base = server.lanBaseURL(), let url = URL(string: base.absoluteString + route.path) else {
            throw RelayMediaError.relayUnavailable
        }
        return url
    }

    static func container(for url: URL) -> StreamContainer {
        switch url.pathExtension.lowercased() {
        case "mov": return .mov
        case "webm": return .webm
        case "mkv": return .mkv
        default: return .mp4
        }
    }

    static func fileExtension(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return ["mp4", "m4v", "mov", "webm", "mkv"].contains(ext) ? ext : "mp4"
    }
}
