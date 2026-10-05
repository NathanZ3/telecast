import Foundation
import CastCore

/// `RendererControl` for a UPnP/DLNA TV.
public struct DLNARendererControl: RendererControl {
    public let client: DLNAClient

    public init(client: DLNAClient) {
        self.client = client
    }

    public init(renderer: RendererDescription, transport: HTTPTransport = URLSessionTransport()) {
        self.client = DLNAClient(renderer: renderer, transport: transport)
    }

    public func load(_ media: PreparedMedia, title: String) async throws {
        try? await client.stop()
        let protocolInfo = DLNAFlags.protocolInfo(mime: media.mime, seekable: media.seekable)
        let metadata = DIDL.metadata(title: title, url: media.url.absoluteString, protocolInfo: protocolInfo)
        castLog("dlna", "SetAVTransportURI \(media.url.absoluteString) [\(media.mime)]")
        try await client.setAVTransportURI(media.url.absoluteString, metadata: metadata)
    }

    public func play() async throws {
        try await client.play()
    }

    public func pause() async throws {
        try await client.pause()
    }

    public func stop() async throws {
        try await client.stop()
    }

    public func seek(to seconds: Double) async throws {
        try await client.seek(to: seconds)
    }

    public func status() async throws -> (TransportInfo, PositionInfo) {
        let info = try await client.transportInfo()
        let position = try await client.positionInfo()
        return (info, position)
    }

    public func volume() async throws -> Int {
        try await client.volume()
    }

    public func setVolume(_ value: Int) async throws {
        try await client.setVolume(value)
    }
}
