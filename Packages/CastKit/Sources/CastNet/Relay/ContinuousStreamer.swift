import Foundation
import CastCore

/// Turns an HLS media playlist into one continuous stream (TS segments back to back, or
/// fMP4 init section + fragments), starting at an offset, with prefetching, decryption,
/// retries and live playlist reloading.
final class ContinuousStreamer: @unchecked Sendable {
    typealias KeyLoader = @Sendable (URL) async throws -> Data

    let playlistURL: URL
    let context: RequestContext
    let fetcher: UpstreamFetcher
    let cache: SegmentCache
    let keyLoader: KeyLoader
    let prefetchCount = 3

    init(playlistURL: URL, context: RequestContext, fetcher: UpstreamFetcher, cache: SegmentCache, keyLoader: @escaping KeyLoader) {
        self.playlistURL = playlistURL
        self.context = context
        self.fetcher = fetcher
        self.cache = cache
        self.keyLoader = keyLoader
    }

    func run(from offset: Double, includeInit: Bool, write: (Data) async throws -> Void) async throws {
        var playlist = try await loadPlaylist()
        var cursor = playlist.segments[playlist.segmentIndex(at: offset)].sequence
        var sentMapURI: URL?
        var reloadedAfterFailure = false
        var pending: [Int: Task<Data, Error>] = [:]
        defer {
            for task in pending.values { task.cancel() }
        }
        castLog("relay", "Flux continu depuis \(Int(offset)) s (segment \(cursor))")

        while true {
            try Task.checkCancellation()
            let upcoming = playlist.segments.filter { $0.sequence >= cursor }
            if upcoming.isEmpty {
                if !playlist.isLive {
                    castLog("relay", "Fin de la vidéo atteinte")
                    return
                }
                try await Task.sleep(nanoseconds: UInt64(max(1, playlist.targetDuration / 2) * 1_000_000_000))
                playlist = (try? await loadPlaylist()) ?? playlist
                if let first = playlist.segments.first, cursor < first.sequence {
                    cursor = first.sequence
                }
                continue
            }

            for segment in upcoming.prefix(prefetchCount) where pending[segment.sequence] == nil {
                pending[segment.sequence] = Task { try await self.fetchSegment(segment) }
            }
            let segment = upcoming[0]
            guard let task = pending[segment.sequence] else { continue }
            let data: Data
            do {
                data = try await task.value
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                pending[segment.sequence] = nil
                if !reloadedAfterFailure {
                    reloadedAfterFailure = true
                    castLog("relay", "Segment \(segment.sequence) en échec, relecture de la playlist")
                    if let fresh = try? await loadPlaylist() { playlist = fresh }
                    continue
                }
                castLog("relay", "Segment \(segment.sequence) sauté : \(error.localizedDescription)")
                reloadedAfterFailure = false
                cursor = segment.sequence + 1
                continue
            }
            pending[segment.sequence] = nil
            reloadedAfterFailure = false

            if includeInit, let map = segment.map, map.uri != sentMapURI {
                let initData = try await fetchInit(map, key: segment.key, sequence: segment.sequence)
                try await write(initData)
                sentMapURI = map.uri
            }
            try await write(data)
            cursor = segment.sequence + 1
        }
    }

    func loadPlaylist() async throws -> HLSMediaPlaylist {
        let (response, data) = try await fetcher.data(playlistURL, context: context)
        guard (200..<300).contains(response.statusCode) else { throw UpstreamError.badStatus(response.statusCode) }
        let base = response.url ?? playlistURL
        switch try M3U8Parser.parse(String(decoding: data, as: UTF8.self), baseURL: base) {
        case .media(let media):
            return media
        case .master(let master):
            guard let variant = VariantSelector.choose(master.variants, cap: .auto) else { throw M3U8Error.emptyPlaylist }
            let (mediaResponse, mediaData) = try await fetcher.data(variant.uri, context: context)
            guard (200..<300).contains(mediaResponse.statusCode) else {
                throw UpstreamError.badStatus(mediaResponse.statusCode)
            }
            guard case .media(let media) = try M3U8Parser.parse(String(decoding: mediaData, as: UTF8.self),
                                                                  baseURL: mediaResponse.url ?? variant.uri) else {
                throw M3U8Error.notM3U8
            }
            return media
        }
    }

    func fetchSegment(_ segment: HLSSegment) async throws -> Data {
        let cacheKey = segment.uri.absoluteString + (segment.byteRange.map { "#\($0.offset)+\($0.length)" } ?? "")
        if let cached = cache.get(cacheKey) { return cached }
        var lastError: Error = UpstreamError.badStatus(0)
        for (attempt, delay) in [0.0, 0.5, 1.0, 2.0].enumerated() {
            if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            do {
                let (response, raw) = try await fetcher.data(segment.uri, context: context, range: segment.byteRange?.rangeHeader)
                guard (200..<300).contains(response.statusCode) else { throw UpstreamError.badStatus(response.statusCode) }
                let data = try await decryptIfNeeded(raw, key: segment.key, sequence: segment.sequence)
                cache.set(cacheKey, data)
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                castLog("relay", "Segment \(segment.sequence), essai \(attempt + 1) : \(error.localizedDescription)")
            }
        }
        throw lastError
    }

    func fetchInit(_ map: HLSMap, key: HLSKey?, sequence: Int) async throws -> Data {
        let cacheKey = "init:" + map.uri.absoluteString
        if let cached = cache.get(cacheKey) { return cached }
        let (response, raw) = try await fetcher.data(map.uri, context: context, range: map.byteRange?.rangeHeader)
        guard (200..<300).contains(response.statusCode) else { throw UpstreamError.badStatus(response.statusCode) }
        let data = try await decryptIfNeeded(raw, key: key, sequence: sequence, explicitIVOnly: true)
        cache.set(cacheKey, data)
        return data
    }

    func decryptIfNeeded(_ raw: Data, key: HLSKey?, sequence: Int, explicitIVOnly: Bool = false) async throws -> Data {
        guard let key, key.isAES128, let keyURI = key.uri else { return raw }
        if explicitIVOnly && key.iv == nil { return raw }
        let keyData = try await keyLoader(keyURI)
        return try AES128.decryptCBC(raw, key: keyData, iv: key.iv ?? AES128.iv(forSequence: sequence))
    }
}
