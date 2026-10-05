import Foundation
import CastCore

/// An HLS stream after reading its playlists: the media playlist we will use and its summary.
public struct InspectedHLS: Sendable {
    public var info: HLSInfo
    public var mediaURL: URL
    public var media: HLSMediaPlaylist

    public init(info: HLSInfo, mediaURL: URL, media: HLSMediaPlaylist) {
        self.info = info
        self.mediaURL = mediaURL
        self.media = media
    }
}

public enum HLSInspector {
    /// Reads the playlist at `url` (master or media). For a master, picks the variant
    /// (`preferredVariant` if given, else the best one within `cap`) and reads it.
    public static func inspect(url: URL, context: RequestContext, cap: QualityCap, preferredVariant: URL? = nil,
                               fetcher: UpstreamFetcher) async throws -> InspectedHLS {
        let (response, data) = try await fetcher.data(url, context: context)
        guard (200..<300).contains(response.statusCode) else { throw UpstreamError.badStatus(response.statusCode) }
        let base = response.url ?? url
        switch try M3U8Parser.parse(String(decoding: data, as: UTF8.self), baseURL: base) {
        case .media(let media):
            let info = HLSInfo.make(master: nil, chosen: nil, mediaURL: base, media: media)
            return InspectedHLS(info: info, mediaURL: base, media: media)
        case .master(let master):
            var chosen: HLSVariantStream?
            if let preferredVariant {
                chosen = master.variants.first { $0.uri == preferredVariant }
            }
            if chosen == nil {
                chosen = VariantSelector.choose(master.variants, cap: cap)
            }
            guard let variant = chosen else { throw M3U8Error.emptyPlaylist }
            let (mediaResponse, mediaData) = try await fetcher.data(variant.uri, context: context)
            guard (200..<300).contains(mediaResponse.statusCode) else {
                throw UpstreamError.badStatus(mediaResponse.statusCode)
            }
            let mediaBase = mediaResponse.url ?? variant.uri
            guard case .media(let media) = try M3U8Parser.parse(String(decoding: mediaData, as: UTF8.self),
                                                                  baseURL: mediaBase) else {
                throw M3U8Error.notM3U8
            }
            let info = HLSInfo.make(master: master, chosen: variant, mediaURL: mediaBase, media: media)
            return InspectedHLS(info: info, mediaURL: mediaBase, media: media)
        }
    }
}
