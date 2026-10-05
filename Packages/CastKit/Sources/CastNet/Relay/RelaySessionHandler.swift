import Foundation
import CastCore

/// Serves one relay session (one cast attempt) in the mode chosen by the strategy.
final class RelaySessionHandler: @unchecked Sendable {
    let config: RelaySessionConfig
    let fetcher: UpstreamFetcher
    private let lock = NSLock()
    private var resources = ResourceMap()
    private var keys: [URL: Data] = [:]
    private let cache = SegmentCache(capacity: 8)

    init(config: RelaySessionConfig, fetcher: UpstreamFetcher) {
        self.config = config
        self.fetcher = fetcher
    }

    func handle(route: RelayRoute, head: HTTPRequestHead, writer: ResponseWriter, base: URL) async {
        switch route {
        case .progressive:
            await serveProgressive(head: head, writer: writer)
        case .playlist:
            await servePlaylist(url: config.mediaPlaylistURL ?? config.sourceURL, head: head, writer: writer, base: base)
        case .resource(_, let id):
            await serveResource(id: id, head: head, writer: writer, base: base)
        case .liveTS(_, let millis), .liveFMP4(_, let millis):
            await serveContinuous(offset: Double(millis) / 1000, head: head, writer: writer)
        case .health, .testFile, .notFound:
            await writer.respond(status: 404, isHead: head.method == "HEAD")
        }
    }

    private func contentFeaturesRequested(_ head: HTTPRequestHead) -> Bool {
        head.header("getcontentfeatures.dlna.org") != nil
    }

    // MARK: Progressive passthrough

    private func serveProgressive(head: HTTPRequestHead, writer: ResponseWriter) async {
        let isHead = head.method == "HEAD"
        let requestedRange = isHead ? "bytes=0-1" : head.header("range")
        var upstream: UpstreamStream?
        do {
            let stream = try await fetcher.stream(config.sourceURL, context: config.context, range: requestedRange)
            upstream = stream
            let status = stream.response.statusCode
            guard (200..<300).contains(status) else {
                stream.cancel()
                castLog("relay", "Le site refuse la vidéo (HTTP \(status))")
                await writer.respond(status: status == 404 ? 404 : 502, isHead: isHead)
                return
            }
            var headers: [(String, String)] = [
                ("Content-Type", contentType(of: stream.response)), ("Accept-Ranges", "bytes"),
                ("Connection", "close"), DLNAHeaders.cors,
            ]
            headers += DLNAHeaders.streaming(mime: config.mime, seekable: true, requested: contentFeaturesRequested(head))
            if isHead {
                stream.cancel()
                if let total = Self.totalLength(stream.response) { headers.append(("Content-Length", String(total))) }
                try await writer.sendHead(HTTPResponseHead(status: 200, headers: headers))
                return
            }
            if let length = stream.response.value(forHTTPHeaderField: "Content-Length") {
                headers.append(("Content-Length", length))
            }
            if let range = stream.response.value(forHTTPHeaderField: "Content-Range") {
                headers.append(("Content-Range", range))
            }
            try await writer.sendHead(HTTPResponseHead(status: status == 206 ? 206 : 200, headers: headers))
            while let chunk = try await stream.next() {
                try await writer.send(chunk)
            }
        } catch {
            upstream?.cancel()
            castLog("relay", "Transfert progressif interrompu : \(error.localizedDescription)")
        }
    }

    private func contentType(of response: HTTPURLResponse) -> String {
        let upstream = response.value(forHTTPHeaderField: "Content-Type") ?? ""
        return upstream.lowercased().hasPrefix("video/") ? upstream : config.mime
    }

    static func totalLength(_ response: HTTPURLResponse) -> Int? {
        if let range = response.value(forHTTPHeaderField: "Content-Range"),
           let total = range.split(separator: "/").last.flatMap({ Int($0) }) {
            return total
        }
        if response.statusCode == 200, let length = response.value(forHTTPHeaderField: "Content-Length") {
            return Int(length)
        }
        return nil
    }

    // MARK: HLS proxy (rewritten playlists, relayed segments and keys)

    private func servePlaylist(url: URL, head: HTTPRequestHead, writer: ResponseWriter, base: URL) async {
        do {
            let (response, data) = try await fetcher.data(url, context: config.context)
            guard (200..<300).contains(response.statusCode) else {
                castLog("relay", "Playlist refusée (HTTP \(response.statusCode))")
                await writer.respond(status: 502, isHead: head.method == "HEAD")
                return
            }
            await sendRewrittenPlaylist(data, playlistURL: response.url ?? url, head: head, writer: writer, base: base)
        } catch {
            castLog("relay", "Playlist injoignable : \(error.localizedDescription)")
            await writer.respond(status: 502, isHead: head.method == "HEAD")
        }
    }

    private func sendRewrittenPlaylist(_ data: Data, playlistURL: URL, head: HTTPRequestHead, writer: ResponseWriter,
                                       base: URL) async {
        let text = String(decoding: data, as: UTF8.self)
        let prefix = base.absoluteString.hasSuffix("/") ? String(base.absoluteString.dropLast()) : base.absoluteString
        let sessionID = config.id
        let rewritten = PlaylistRewriter.rewrite(text, baseURL: playlistURL) { resource in
            let id = lock.withLock { resources.id(for: resource) }
            return prefix + RelayRoute.resource(session: sessionID, id: id).path
        }
        let mime = config.mode == .hlsProxy ? config.mime : "application/vnd.apple.mpegurl"
        await writer.respond(status: 200, type: mime, body: Data(rewritten.utf8), isHead: head.method == "HEAD",
                             extraHeaders: [("Cache-Control", "no-cache")]
                                + DLNAHeaders.streaming(mime: mime, seekable: true, requested: contentFeaturesRequested(head)))
    }

    private func serveResource(id: String, head: HTTPRequestHead, writer: ResponseWriter, base: URL) async {
        let isHead = head.method == "HEAD"
        guard let entry = lock.withLock({ resources.entry(for: id) }) else {
            await writer.respond(status: 404, isHead: isHead)
            return
        }
        let range = head.header("range") ?? entry.byteRange?.rangeHeader
        do {
            let (response, data) = try await fetcher.data(entry.url, context: config.context, range: range)
            guard (200..<300).contains(response.statusCode) else {
                castLog("relay", "Ressource refusée (HTTP \(response.statusCode)) : \(entry.url.lastPathComponent)")
                await writer.respond(status: 502, isHead: isHead)
                return
            }
            let type = response.value(forHTTPHeaderField: "Content-Type") ?? ""
            if type.lowercased().contains("mpegurl") || data.starts(with: Data("#EXTM3U".utf8)) {
                await sendRewrittenPlaylist(data, playlistURL: response.url ?? entry.url, head: head, writer: writer, base: base)
                return
            }
            var headers: [(String, String)] = []
            if let contentRange = response.value(forHTTPHeaderField: "Content-Range"), head.header("range") != nil {
                headers.append(("Content-Range", contentRange))
            }
            let outputType = type.isEmpty ? RelayServer.contentType(forExtension: entry.url.pathExtension) : type
            let status = response.statusCode == 206 && head.header("range") != nil ? 206 : 200
            var allHeaders: [(String, String)] = [("Content-Type", outputType), ("Content-Length", String(data.count)),
                                                  ("Connection", "close"), DLNAHeaders.cors]
            allHeaders += headers
            try await writer.sendHead(HTTPResponseHead(status: status, headers: allHeaders))
            if !isHead { try await writer.send(data) }
        } catch {
            castLog("relay", "Ressource interrompue : \(error.localizedDescription)")
            await writer.respond(status: 502, isHead: isHead)
        }
    }

    // MARK: Continuous TS / fMP4

    private func serveContinuous(offset: Double, head: HTTPRequestHead, writer: ResponseWriter) async {
        var headers: [(String, String)] = [("Content-Type", config.mime), ("Connection", "close"),
                                           ("Cache-Control", "no-cache"), DLNAHeaders.cors]
        headers += DLNAHeaders.streaming(mime: config.mime, seekable: false, requested: contentFeaturesRequested(head))
        do {
            try await writer.sendHead(HTTPResponseHead(status: 200, headers: headers))
            if head.method == "HEAD" { return }
            let streamer = ContinuousStreamer(
                playlistURL: config.mediaPlaylistURL ?? config.sourceURL,
                context: config.context,
                fetcher: fetcher,
                cache: cache,
                keyLoader: { [weak self] url in
                    guard let self else { throw UpstreamError.cancelled }
                    return try await self.key(for: url)
                })
            try await streamer.run(from: offset, includeInit: config.mode == .liveFMP4) { chunk in
                try await writer.send(chunk)
            }
        } catch {
            castLog("relay", "Flux continu terminé : \(error.localizedDescription)")
        }
    }

    func key(for url: URL) async throws -> Data {
        if let cached = lock.withLock({ keys[url] }) { return cached }
        let (response, data) = try await fetcher.data(url, context: config.context)
        guard (200..<300).contains(response.statusCode) else { throw UpstreamError.badStatus(response.statusCode) }
        guard data.count == 16 else {
            castLog("relay", "Clé AES de \(data.count) octets ignorée")
            throw AES128Error.badKeyOrIV
        }
        lock.withLock { keys[url] = data }
        return data
    }
}
