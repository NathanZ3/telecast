import Foundation

public struct HLSByteRange: Equatable, Sendable {
    public var length: Int
    public var offset: Int

    public init(length: Int, offset: Int) {
        self.length = length
        self.offset = offset
    }

    /// HTTP `Range` header value covering this sub-range.
    public var rangeHeader: String { "bytes=\(offset)-\(offset + length - 1)" }
}

public struct HLSKey: Equatable, Sendable {
    public var method: String
    public var uri: URL?
    public var iv: Data?
    public var keyFormat: String?

    public init(method: String, uri: URL?, iv: Data?, keyFormat: String?) {
        self.method = method
        self.uri = uri
        self.iv = iv
        self.keyFormat = keyFormat
    }

    public var isNone: Bool { method.uppercased() == "NONE" }
    public var isAES128: Bool { method.uppercased() == "AES-128" }

    /// Sample encryption or a key system (FairPlay, Widevine…): not castable.
    public var isDRM: Bool {
        if method.uppercased().hasPrefix("SAMPLE-AES") { return true }
        if let format = keyFormat?.lowercased(), format != "identity" { return true }
        return false
    }
}

public struct HLSMap: Equatable, Sendable {
    public var uri: URL
    public var byteRange: HLSByteRange?

    public init(uri: URL, byteRange: HLSByteRange?) {
        self.uri = uri
        self.byteRange = byteRange
    }
}

public struct HLSSegment: Equatable, Sendable {
    public var uri: URL
    public var duration: Double
    public var sequence: Int
    public var key: HLSKey?
    public var map: HLSMap?
    public var byteRange: HLSByteRange?
    public var discontinuity: Bool

    public init(uri: URL, duration: Double, sequence: Int, key: HLSKey?, map: HLSMap?, byteRange: HLSByteRange?,
                discontinuity: Bool) {
        self.uri = uri
        self.duration = duration
        self.sequence = sequence
        self.key = key
        self.map = map
        self.byteRange = byteRange
        self.discontinuity = discontinuity
    }
}

public struct HLSVariantStream: Equatable, Sendable {
    public var uri: URL
    public var bandwidth: Int?
    public var width: Int?
    public var height: Int?
    public var codecs: String?
    public var audioGroup: String?

    public init(uri: URL, bandwidth: Int?, width: Int?, height: Int?, codecs: String?, audioGroup: String?) {
        self.uri = uri
        self.bandwidth = bandwidth
        self.width = width
        self.height = height
        self.codecs = codecs
        self.audioGroup = audioGroup
    }

    public var isAudioOnly: Bool {
        guard width == nil, height == nil, let codecs = codecs?.lowercased() else { return false }
        let videoMarkers = ["avc", "hvc", "hev", "vp09", "vp9", "av01", "dvh", "dva", "mp4v"]
        return !videoMarkers.contains { codecs.contains($0) }
    }
}

public struct HLSRendition: Equatable, Sendable {
    public var type: String
    public var groupID: String
    public var name: String?
    public var uri: URL?
    public var isDefault: Bool

    public init(type: String, groupID: String, name: String?, uri: URL?, isDefault: Bool) {
        self.type = type
        self.groupID = groupID
        self.name = name
        self.uri = uri
        self.isDefault = isDefault
    }
}

public struct HLSMasterPlaylist: Equatable, Sendable {
    public var variants: [HLSVariantStream]
    public var renditions: [HLSRendition]
    public var sessionKeys: [HLSKey]

    public init(variants: [HLSVariantStream], renditions: [HLSRendition], sessionKeys: [HLSKey]) {
        self.variants = variants
        self.renditions = renditions
        self.sessionKeys = sessionKeys
    }

    /// The variant's audio comes from a separate playlist (`EXT-X-MEDIA TYPE=AUDIO` with a URI).
    public func hasSeparateAudio(_ variant: HLSVariantStream) -> Bool {
        guard let group = variant.audioGroup else { return false }
        return renditions.contains { $0.type.uppercased() == "AUDIO" && $0.groupID == group && $0.uri != nil }
    }
}

public struct HLSMediaPlaylist: Equatable, Sendable {
    public var targetDuration: Double
    public var mediaSequence: Int
    public var segments: [HLSSegment]
    public var endList: Bool
    public var playlistType: String?

    public init(targetDuration: Double, mediaSequence: Int, segments: [HLSSegment], endList: Bool, playlistType: String?) {
        self.targetDuration = targetDuration
        self.mediaSequence = mediaSequence
        self.segments = segments
        self.endList = endList
        self.playlistType = playlistType
    }

    public var isLive: Bool { !endList && playlistType?.uppercased() != "VOD" }

    public var totalDuration: Double { segments.reduce(0) { $0 + $1.duration } }

    public var usesFMP4: Bool {
        let fragmentExtensions: Set<String> = ["m4s", "mp4", "cmfv", "m4f", "m4v"]
        return segments.contains { $0.map != nil || fragmentExtensions.contains($0.uri.pathExtension.lowercased()) }
    }

    public var hasDRM: Bool { segments.contains { $0.key?.isDRM == true } }

    public var isAES128: Bool { segments.contains { $0.key?.isAES128 == true } }

    /// Index of the segment playing at `offset` seconds (clamped to the playlist).
    public func segmentIndex(at offset: Double) -> Int {
        guard !segments.isEmpty else { return 0 }
        var start = 0.0
        for (index, segment) in segments.enumerated() {
            if offset < start + segment.duration { return index }
            start += segment.duration
        }
        return segments.count - 1
    }

    public func startTime(ofSegmentAt index: Int) -> Double {
        let count = max(0, min(index, segments.count))
        return segments.prefix(count).reduce(0) { $0 + $1.duration }
    }
}

public enum HLSPlaylist: Equatable, Sendable {
    case master(HLSMasterPlaylist)
    case media(HLSMediaPlaylist)
}

public enum M3U8Error: Error, Equatable {
    case notM3U8
    case emptyPlaylist
}

public enum M3U8Parser {
    public static func parse(_ text: String, baseURL: URL) throws -> HLSPlaylist {
        let lines = normalizedLines(text)
        guard let first = lines.first(where: { !$0.isEmpty }), first.hasPrefix("#EXTM3U") else {
            throw M3U8Error.notM3U8
        }
        if lines.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF") }) {
            return .master(try parseMaster(lines, baseURL: baseURL))
        }
        return .media(try parseMedia(lines, baseURL: baseURL))
    }

    static func normalizedLines(_ text: String) -> [String] {
        var body = text
        if body.hasPrefix("\u{FEFF}") { body.removeFirst() }
        return body.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func value(of line: String, tag: String) -> String {
        String(line.dropFirst(tag.count))
    }

    static func parseMaster(_ lines: [String], baseURL: URL) throws -> HLSMasterPlaylist {
        var variants: [HLSVariantStream] = []
        var renditions: [HLSRendition] = []
        var sessionKeys: [HLSKey] = []
        var pending: [String: String]?

        for line in lines {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                pending = attributes(value(of: line, tag: "#EXT-X-STREAM-INF:"))
            } else if line.hasPrefix("#EXT-X-MEDIA:") {
                let attrs = attributes(value(of: line, tag: "#EXT-X-MEDIA:"))
                renditions.append(HLSRendition(
                    type: attrs["TYPE"] ?? "", groupID: attrs["GROUP-ID"] ?? "", name: attrs["NAME"],
                    uri: attrs["URI"].flatMap { resolve($0, base: baseURL) },
                    isDefault: attrs["DEFAULT"]?.uppercased() == "YES"))
            } else if line.hasPrefix("#EXT-X-SESSION-KEY:") {
                sessionKeys.append(parseKey(value(of: line, tag: "#EXT-X-SESSION-KEY:"), base: baseURL))
            } else if !line.isEmpty, !line.hasPrefix("#"), let attrs = pending {
                pending = nil
                guard let uri = resolve(line, base: baseURL) else { continue }
                let size = parseResolution(attrs["RESOLUTION"])
                variants.append(HLSVariantStream(
                    uri: uri, bandwidth: attrs["BANDWIDTH"].flatMap { Int($0) }, width: size?.width,
                    height: size?.height, codecs: attrs["CODECS"], audioGroup: attrs["AUDIO"]))
            }
        }
        guard !variants.isEmpty else { throw M3U8Error.emptyPlaylist }
        return HLSMasterPlaylist(variants: variants, renditions: renditions, sessionKeys: sessionKeys)
    }

    static func parseMedia(_ lines: [String], baseURL: URL) throws -> HLSMediaPlaylist {
        var targetDuration = 0.0
        var mediaSequence = 0
        var segments: [HLSSegment] = []
        var endList = false
        var playlistType: String?
        var currentKey: HLSKey?
        var currentMap: HLSMap?
        var pendingDuration: Double?
        var pendingRange: String?
        var pendingDiscontinuity = false
        var rangeEnds: [String: Int] = [:]

        for line in lines {
            if line.hasPrefix("#EXT-X-TARGETDURATION:") {
                targetDuration = Double(value(of: line, tag: "#EXT-X-TARGETDURATION:")) ?? 0
            } else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                mediaSequence = Int(value(of: line, tag: "#EXT-X-MEDIA-SEQUENCE:")) ?? 0
            } else if line.hasPrefix("#EXT-X-PLAYLIST-TYPE:") {
                playlistType = value(of: line, tag: "#EXT-X-PLAYLIST-TYPE:")
            } else if line.hasPrefix("#EXT-X-ENDLIST") {
                endList = true
            } else if line.hasPrefix("#EXT-X-KEY:") {
                let key = parseKey(value(of: line, tag: "#EXT-X-KEY:"), base: baseURL)
                currentKey = key.isNone ? nil : key
            } else if line.hasPrefix("#EXT-X-MAP:") {
                let attrs = attributes(value(of: line, tag: "#EXT-X-MAP:"))
                if let uri = attrs["URI"].flatMap({ resolve($0, base: baseURL) }) {
                    currentMap = HLSMap(uri: uri, byteRange: attrs["BYTERANGE"].flatMap { parseByteRange($0, previousEnd: nil) })
                }
            } else if line.hasPrefix("#EXTINF:") {
                let raw = value(of: line, tag: "#EXTINF:")
                let durationText = raw.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                pendingDuration = Double(durationText.trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("#EXT-X-BYTERANGE:") {
                pendingRange = value(of: line, tag: "#EXT-X-BYTERANGE:")
            } else if line == "#EXT-X-DISCONTINUITY" {
                pendingDiscontinuity = true
            } else if !line.isEmpty, !line.hasPrefix("#") {
                defer {
                    pendingDuration = nil
                    pendingRange = nil
                    pendingDiscontinuity = false
                }
                guard let duration = pendingDuration, let uri = resolve(line, base: baseURL) else { continue }
                var range: HLSByteRange?
                if let spec = pendingRange {
                    range = parseByteRange(spec, previousEnd: rangeEnds[uri.absoluteString])
                    if let range { rangeEnds[uri.absoluteString] = range.offset + range.length }
                }
                segments.append(HLSSegment(
                    uri: uri, duration: duration, sequence: mediaSequence + segments.count, key: currentKey,
                    map: currentMap, byteRange: range, discontinuity: pendingDiscontinuity))
            }
        }
        guard !segments.isEmpty else { throw M3U8Error.emptyPlaylist }
        return HLSMediaPlaylist(targetDuration: targetDuration, mediaSequence: mediaSequence, segments: segments,
                                endList: endList, playlistType: playlistType)
    }

    /// Parses an attribute list; quoted values keep their commas, keys are uppercased.
    public static func attributes(_ list: String) -> [String: String] {
        var result: [String: String] = [:]
        var key = ""
        var value = ""
        var readingKey = true
        var inQuotes = false
        for character in list {
            if readingKey {
                if character == "=" {
                    readingKey = false
                } else if character == "," {
                    key = ""
                } else {
                    key.append(character)
                }
            } else if character == "\"" {
                inQuotes.toggle()
            } else if character == "," && !inQuotes {
                result[key.trimmingCharacters(in: .whitespaces).uppercased()] = value
                key = ""
                value = ""
                readingKey = true
            } else {
                value.append(character)
            }
        }
        if !readingKey {
            result[key.trimmingCharacters(in: .whitespaces).uppercased()] = value
        }
        return result
    }

    public static func resolve(_ uri: String, base: URL) -> URL? {
        let trimmed = uri.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed, relativeTo: base) { return url.absoluteURL }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: encoded, relativeTo: base)?.absoluteURL
    }

    static func parseKey(_ list: String, base: URL) -> HLSKey {
        let attrs = attributes(list)
        return HLSKey(method: attrs["METHOD"] ?? "NONE",
                      uri: attrs["URI"].flatMap { resolve($0, base: base) },
                      iv: attrs["IV"].flatMap(parseHex),
                      keyFormat: attrs["KEYFORMAT"])
    }

    static func parseHex(_ text: String) -> Data? {
        var hex = text.trimmingCharacters(in: .whitespaces)
        if hex.lowercased().hasPrefix("0x") { hex = String(hex.dropFirst(2)) }
        guard !hex.isEmpty, hex.count <= 32 else { return nil }
        hex = String(repeating: "0", count: 32 - hex.count) + hex
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    static func parseByteRange(_ spec: String, previousEnd: Int?) -> HLSByteRange? {
        let parts = spec.split(separator: "@", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = parts.first, let length = Int(first), length > 0 else { return nil }
        let offset = parts.count > 1 ? Int(parts[1]) ?? 0 : previousEnd ?? 0
        return HLSByteRange(length: length, offset: offset)
    }

    static func parseResolution(_ text: String?) -> (width: Int, height: Int)? {
        guard let parts = text?.lowercased().split(separator: "x"), parts.count == 2,
              let width = Int(parts[0]), let height = Int(parts[1]) else { return nil }
        return (width, height)
    }
}
