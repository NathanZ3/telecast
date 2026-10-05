import XCTest
@testable import CastCore

final class HLSTests: XCTestCase {
    static let masterURL = URL(string: "https://cdn.net/movie/master.m3u8")!
    static let mediaURL = URL(string: "https://cdn.net/movie/low/index.m3u8")!

    static let master = """
    #EXTM3U
    #EXT-X-VERSION:4
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="Français",DEFAULT=YES,URI="audio/fr.m3u8"
    #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,CODECS="avc1.4d401e,mp4a.40.2"
    low/index.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2"
    mid/index.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2",AUDIO="aud"
    https://other.cdn/high/index.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2"
    audio-only.m3u8
    """

    static let media = """
    #EXTM3U
    #EXT-X-VERSION:3
    #EXT-X-TARGETDURATION:6
    #EXT-X-MEDIA-SEQUENCE:10
    #EXT-X-KEY:METHOD=AES-128,URI="k.key",IV=0x000102030405060708090A0B0C0D0E0F
    #EXTINF:6.0,
    seg10.ts
    #EXTINF:6.0,Titre
    seg11.ts
    #EXT-X-DISCONTINUITY
    #EXTINF:4.5,
    https://cdn2.net/seg12.ts
    #EXT-X-ENDLIST
    """

    static let fmp4 = """
    #EXTM3U
    #EXT-X-TARGETDURATION:4
    #EXT-X-MAP:URI="init.mp4"
    #EXTINF:4,
    s1.m4s
    #EXTINF:4,
    s2.m4s
    """

    func parseMaster(_ text: String = master) throws -> HLSMasterPlaylist {
        guard case let .master(playlist) = try M3U8Parser.parse(text, baseURL: Self.masterURL) else {
            XCTFail("expected a master playlist")
            throw M3U8Error.notM3U8
        }
        return playlist
    }

    func parseMedia(_ text: String, base: URL = mediaURL) throws -> HLSMediaPlaylist {
        guard case let .media(playlist) = try M3U8Parser.parse(text, baseURL: base) else {
            XCTFail("expected a media playlist")
            throw M3U8Error.notM3U8
        }
        return playlist
    }

    func testMasterPlaylist() throws {
        let master = try parseMaster()
        XCTAssertEqual(master.variants.count, 4)
        XCTAssertEqual(master.variants[0].uri.absoluteString, "https://cdn.net/movie/low/index.m3u8")
        XCTAssertEqual(master.variants[0].codecs, "avc1.4d401e,mp4a.40.2")
        XCTAssertEqual(master.variants[0].height, 360)
        XCTAssertEqual(master.variants[2].uri.absoluteString, "https://other.cdn/high/index.m3u8")
        XCTAssertTrue(master.hasSeparateAudio(master.variants[2]))
        XCTAssertFalse(master.hasSeparateAudio(master.variants[0]))
        XCTAssertTrue(master.variants[3].isAudioOnly)
        XCTAssertEqual(master.renditions.first?.name, "Français")
        XCTAssertEqual(master.renditions.first?.isDefault, true)
        XCTAssertEqual(master.renditions.first?.uri?.absoluteString, "https://cdn.net/movie/audio/fr.m3u8")
    }

    func testVariantSelection() throws {
        let variants = try parseMaster().variants
        XCTAssertEqual(VariantSelector.choose(variants, cap: .p720)?.height, 720)
        XCTAssertEqual(VariantSelector.choose(variants, cap: .auto)?.height, 1080)
        XCTAssertEqual(VariantSelector.choose(variants, cap: .p480)?.height, 360)
        XCTAssertEqual(VariantSelector.choose([variants[2]], cap: .p480)?.height, 1080)
        XCTAssertNil(VariantSelector.choose([], cap: .auto))
    }

    func testMediaPlaylistWithAESKey() throws {
        let media = try parseMedia(Self.media)
        XCTAssertEqual(media.segments.count, 3)
        XCTAssertEqual(media.totalDuration, 16.5, accuracy: 0.0001)
        XCTAssertFalse(media.isLive)
        XCTAssertEqual(media.targetDuration, 6)
        XCTAssertEqual(media.segments[0].sequence, 10)
        XCTAssertEqual(media.segments[2].sequence, 12)
        XCTAssertEqual(media.segments[1].uri.absoluteString, "https://cdn.net/movie/low/seg11.ts")
        XCTAssertEqual(media.segments[2].uri.absoluteString, "https://cdn2.net/seg12.ts")
        XCTAssertTrue(media.segments[2].discontinuity)
        XCTAssertFalse(media.segments[1].discontinuity)
        XCTAssertEqual(media.segments[0].key?.uri?.absoluteString, "https://cdn.net/movie/low/k.key")
        XCTAssertEqual(media.segments[0].key?.iv, Data((0...15).map { UInt8($0) }))
        XCTAssertTrue(media.isAES128)
        XCTAssertFalse(media.hasDRM)
        XCTAssertFalse(media.usesFMP4)
        XCTAssertEqual(media.segmentIndex(at: 7), 1)
        XCTAssertEqual(media.segmentIndex(at: -3), 0)
        XCTAssertEqual(media.segmentIndex(at: 999), 2)
        XCTAssertEqual(media.startTime(ofSegmentAt: 2), 12)
    }

    func testFMP4AndLive() throws {
        let media = try parseMedia(Self.fmp4)
        XCTAssertTrue(media.usesFMP4)
        XCTAssertTrue(media.isLive)
        XCTAssertEqual(media.segments[0].map?.uri.lastPathComponent, "init.mp4")
    }

    func testSampleAESIsDRM() throws {
        let text = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://x",KEYFORMAT="com.apple.streamingkeydelivery"
        #EXTINF:4,
        a.ts
        #EXT-X-ENDLIST
        """
        XCTAssertTrue(try parseMedia(text).hasDRM)
    }

    func testByteRanges() throws {
        let text = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXTINF:4,
        #EXT-X-BYTERANGE:1000@0
        all.ts
        #EXTINF:4,
        #EXT-X-BYTERANGE:500
        all.ts
        #EXT-X-ENDLIST
        """
        let media = try parseMedia(text)
        XCTAssertEqual(media.segments[0].byteRange, HLSByteRange(length: 1000, offset: 0))
        XCTAssertEqual(media.segments[1].byteRange, HLSByteRange(length: 500, offset: 1000))
        XCTAssertEqual(media.segments[1].byteRange?.rangeHeader, "bytes=1000-1499")
    }

    func testRejectsNonPlaylists() {
        XCTAssertThrowsError(try M3U8Parser.parse("<html></html>", baseURL: Self.masterURL)) {
            XCTAssertEqual($0 as? M3U8Error, .notM3U8)
        }
        XCTAssertThrowsError(try M3U8Parser.parse("#EXTM3U\n#EXT-X-ENDLIST\n", baseURL: Self.masterURL)) {
            XCTAssertEqual($0 as? M3U8Error, .emptyPlaylist)
        }
    }

    func testAttributeParsing() {
        let attrs = M3U8Parser.attributes("BANDWIDTH=1,CODECS=\"a,b\",NAME=\"x y\",DEFAULT=YES")
        XCTAssertEqual(attrs["BANDWIDTH"], "1")
        XCTAssertEqual(attrs["CODECS"], "a,b")
        XCTAssertEqual(attrs["NAME"], "x y")
        XCTAssertEqual(attrs["DEFAULT"], "YES")
    }

    func testRewriterMapsAllURIs() {
        let mapped = PlaylistRewriter.rewrite(Self.media, baseURL: Self.mediaURL) { "R(\($0.lastPathComponent))" }
        let lines = mapped.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines.contains("R(seg10.ts)"))
        XCTAssertTrue(lines.contains("R(seg12.ts)"))
        XCTAssertTrue(lines.contains("#EXT-X-KEY:METHOD=AES-128,URI=\"R(k.key)\",IV=0x000102030405060708090A0B0C0D0E0F"))
        XCTAssertTrue(lines.contains("#EXTINF:6.0,Titre"))
        XCTAssertTrue(lines.contains("#EXT-X-ENDLIST"))
        XCTAssertFalse(mapped.contains("seg11.ts\n#"))

        let fmp4 = PlaylistRewriter.rewrite(Self.fmp4, baseURL: Self.mediaURL) { "R(\($0.lastPathComponent))" }
        XCTAssertTrue(fmp4.contains("#EXT-X-MAP:URI=\"R(init.mp4)\""))

        let master = PlaylistRewriter.rewrite(Self.master, baseURL: Self.masterURL) { "R(\($0.host ?? ""))" }
        XCTAssertTrue(master.contains("URI=\"R(cdn.net)\""))
        XCTAssertTrue(master.contains("\nR(other.cdn)\n"))
    }

    func testInfoSummary() throws {
        let master = try parseMaster()
        let media = try parseMedia(Self.media)
        let info = HLSInfo.make(master: master, chosen: master.variants[2], mediaURL: Self.mediaURL, media: media)
        XCTAssertTrue(info.isMaster)
        XCTAssertEqual(info.variants.count, 3)
        XCTAssertTrue(info.hasSeparateAudio)
        XCTAssertEqual(info.segmentFormat, .ts)
        XCTAssertEqual(info.totalDuration ?? 0, 16.5, accuracy: 0.0001)
        XCTAssertTrue(info.encrypted)
        XCTAssertFalse(info.drm)
        XCTAssertFalse(info.isLive)

        let live = HLSInfo.make(master: nil, chosen: nil, mediaURL: Self.mediaURL, media: try parseMedia(Self.fmp4))
        XCTAssertNil(live.totalDuration)
        XCTAssertEqual(live.segmentFormat, .fmp4)
        XCTAssertFalse(live.isMaster)
    }
}
