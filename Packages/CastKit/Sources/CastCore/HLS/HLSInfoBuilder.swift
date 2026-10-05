import Foundation

extension HLSInfo {
    /// Summarises an inspected stream (optional master + the chosen media playlist).
    public static func make(master: HLSMasterPlaylist?, chosen: HLSVariantStream?, mediaURL: URL,
                            media: HLSMediaPlaylist) -> HLSInfo {
        var variants: [HLSInfo.Variant] = []
        if let master {
            for stream in master.variants where !stream.isAudioOnly {
                variants.append(HLSInfo.Variant(url: stream.uri, bandwidth: stream.bandwidth, width: stream.width,
                                                height: stream.height, hasSeparateAudio: master.hasSeparateAudio(stream)))
            }
        }
        var separateAudio = false
        if let master, let chosen {
            separateAudio = master.hasSeparateAudio(chosen)
        }
        let format: SegmentFormat = media.segments.isEmpty ? .unknown : (media.usesFMP4 ? .fmp4 : .ts)
        let sessionDRM = master?.sessionKeys.contains { $0.isDRM } ?? false
        return HLSInfo(isMaster: master != nil,
                       variants: variants,
                       chosenVariantURL: mediaURL,
                       totalDuration: media.isLive ? nil : media.totalDuration,
                       isLive: media.isLive,
                       segmentFormat: format,
                       hasSeparateAudio: separateAudio,
                       drm: media.hasDRM || sessionDRM,
                       encrypted: media.isAES128)
    }
}
