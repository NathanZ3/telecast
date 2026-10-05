import Foundation

public enum DLNAError: Error, Equatable {
    case soapFault(SOAPFault)
    case httpStatus(Int)
    case missingService(String)
    case badResponse
}

/// UPnP AV control of one renderer (AVTransport, RenderingControl, ConnectionManager).
public struct DLNAClient: Sendable {
    public let renderer: RendererDescription
    let transport: HTTPTransport

    public init(renderer: RendererDescription, transport: HTTPTransport) {
        self.renderer = renderer
        self.transport = transport
    }

    public func setAVTransportURI(_ uri: String, metadata: String) async throws {
        try await invoke(renderer.avTransport, "SetAVTransportURI",
                         [("InstanceID", "0"), ("CurrentURI", uri), ("CurrentURIMetaData", metadata)])
    }

    public func play() async throws {
        try await invoke(renderer.avTransport, "Play", [("InstanceID", "0"), ("Speed", "1")])
    }

    public func pause() async throws {
        try await invoke(renderer.avTransport, "Pause", [("InstanceID", "0")])
    }

    public func stop() async throws {
        try await invoke(renderer.avTransport, "Stop", [("InstanceID", "0")])
    }

    public func seek(to seconds: Double) async throws {
        try await invoke(renderer.avTransport, "Seek",
                         [("InstanceID", "0"), ("Unit", "REL_TIME"), ("Target", UPnPTime.format(seconds))])
    }

    public func transportInfo() async throws -> TransportInfo {
        let output = try await invoke(renderer.avTransport, "GetTransportInfo", [("InstanceID", "0")], expectsOutput: true)
        return TransportInfo(state: TransportState(raw: output["CurrentTransportState"] ?? ""),
                             status: output["CurrentTransportStatus"] ?? "OK")
    }

    public func positionInfo() async throws -> PositionInfo {
        let output = try await invoke(renderer.avTransport, "GetPositionInfo", [("InstanceID", "0")], expectsOutput: true)
        return PositionInfo(duration: output["TrackDuration"].flatMap(UPnPTime.parse),
                            position: output["RelTime"].flatMap(UPnPTime.parse),
                            trackURI: output["TrackURI"])
    }

    public func protocolInfoSink() async throws -> [ProtocolInfo] {
        guard let service = renderer.connectionManager else { throw DLNAError.missingService("ConnectionManager") }
        let output = try await invoke(service, "GetProtocolInfo", [], expectsOutput: true)
        return ProtocolInfo.parseList(output["Sink"] ?? "")
    }

    public func volume() async throws -> Int {
        guard let service = renderer.renderingControl else { throw DLNAError.missingService("RenderingControl") }
        let output = try await invoke(service, "GetVolume", [("InstanceID", "0"), ("Channel", "Master")], expectsOutput: true)
        guard let value = output["CurrentVolume"].flatMap({ Int($0) }) else { throw DLNAError.badResponse }
        return value
    }

    public func setVolume(_ value: Int) async throws {
        guard let service = renderer.renderingControl else { throw DLNAError.missingService("RenderingControl") }
        let clamped = max(0, min(100, value))
        try await invoke(service, "SetVolume",
                         [("InstanceID", "0"), ("Channel", "Master"), ("DesiredVolume", String(clamped))])
    }

    @discardableResult
    func invoke(_ service: UPnPService, _ action: String, _ arguments: [(String, String)],
                expectsOutput: Bool = false) async throws -> [String: String] {
        let body = SOAP.envelope(action: action, serviceType: service.serviceType, arguments: arguments)
        let request = HTTPRequestSpec(
            url: service.controlURL,
            method: "POST",
            headers: [
                "Content-Type": "text/xml; charset=\"utf-8\"",
                "SOAPAction": SOAP.actionHeader(serviceType: service.serviceType, action: action),
            ],
            body: Data(body.utf8),
            timeout: 4)
        let response = try await transport.send(request)
        guard (200..<300).contains(response.status) else {
            if let fault = SOAP.parseFault(response.body) { throw DLNAError.soapFault(fault) }
            throw DLNAError.httpStatus(response.status)
        }
        if response.body.isEmpty {
            if expectsOutput { throw DLNAError.badResponse }
            return [:]
        }
        do {
            return try SOAP.parseResponse(response.body, action: action)
        } catch let fault as SOAPFault {
            throw DLNAError.soapFault(fault)
        } catch {
            if expectsOutput { throw DLNAError.badResponse }
            return [:]
        }
    }
}
