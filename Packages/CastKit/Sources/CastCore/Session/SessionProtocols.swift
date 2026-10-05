import Foundation

/// What the TV will load for one strategy.
public struct PreparedMedia: Equatable, Sendable {
    public var url: URL
    public var mime: String
    /// Whether the TV may seek itself (byte ranges / native HLS seeking).
    public var seekable: Bool
    /// Position (seconds) of the media's first frame inside the video (continuous streams).
    public var offset: Double

    public init(url: URL, mime: String, seekable: Bool, offset: Double) {
        self.url = url
        self.mime = mime
        self.seekable = seekable
        self.offset = offset
    }
}

/// A TV that can be driven (DLNA today, Chromecast later).
public protocol RendererControl: Sendable {
    /// Stops the current media (errors ignored) and loads the new one.
    func load(_ media: PreparedMedia, title: String) async throws
    func play() async throws
    func pause() async throws
    func stop() async throws
    func seek(to seconds: Double) async throws
    func status() async throws -> (TransportInfo, PositionInfo)
    func volume() async throws -> Int
    func setVolume(_ value: Int) async throws
}

/// Produces the URL the TV should load for a strategy (direct URL or relay URL).
public protocol MediaSource: Sendable {
    func prepare(strategy: CastStrategy, offset: Double) async throws -> PreparedMedia
    /// True when the TV fetched something from the relay for this media after `date`.
    func wasFetched(after date: Date) -> Bool
    func release() async
}

public protocol SessionClock: Sendable {
    func now() -> Date
    func sleep(seconds: Double) async throws
}

public struct SystemClock: SessionClock {
    public init() {}

    public func now() -> Date { Date() }

    public func sleep(seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}
