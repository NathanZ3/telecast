import Foundation

/// Stable short ids for the upstream resources referenced by a relayed playlist.
/// The original extension is kept so TVs that sniff file names still recognise segments.
public struct ResourceMap: Sendable {
    struct Entry: Sendable {
        var url: URL
        var byteRange: HLSByteRange?
    }

    static let keptExtensions: Set<String> = [
        "ts", "m4s", "mp4", "aac", "key", "m3u8", "vtt", "webvtt", "m4a", "mp3", "cmfv", "cmfa",
    ]

    private var keyToID: [String: String] = [:]
    private var entries: [String: Entry] = [:]
    private var counter = 0

    public init() {}

    public mutating func id(for url: URL, byteRange: HLSByteRange? = nil) -> String {
        let key = url.absoluteString + (byteRange.map { "#\($0.offset)+\($0.length)" } ?? "")
        if let existing = keyToID[key] { return existing }
        counter += 1
        let ext = url.pathExtension.lowercased()
        let id = Self.keptExtensions.contains(ext) ? "\(counter).\(ext)" : "\(counter)"
        keyToID[key] = id
        entries[id] = Entry(url: url, byteRange: byteRange)
        return id
    }

    public func entry(for id: String) -> (url: URL, byteRange: HLSByteRange?)? {
        guard let entry = entries[id] else { return nil }
        return (entry.url, entry.byteRange)
    }

    public var count: Int { entries.count }
}
