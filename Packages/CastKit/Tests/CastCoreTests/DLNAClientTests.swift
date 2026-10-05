import XCTest
@testable import CastCore

/// Records requests and answers them with a closure.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HTTPRequestSpec] = []
    private let responder: (HTTPRequestSpec) -> HTTPResponseData

    init(responder: @escaping (HTTPRequestSpec) -> HTTPResponseData) {
        self.responder = responder
    }

    var requests: [HTTPRequestSpec] {
        lock.withLock { recorded }
    }

    func send(_ request: HTTPRequestSpec) async throws -> HTTPResponseData {
        lock.withLock { recorded.append(request) }
        return responder(request)
    }
}

final class DLNAClientTests: XCTestCase {
    static let renderer = RendererDescription(
        udn: "uuid:tv", friendlyName: "TV", manufacturer: nil, modelName: nil,
        deviceType: "urn:schemas-upnp-org:device:MediaRenderer:1",
        descriptionURL: URL(string: "http://192.168.1.20:49152/description.xml")!,
        avTransport: UPnPService(serviceType: "urn:schemas-upnp-org:service:AVTransport:1",
                                 controlURL: URL(string: "http://192.168.1.20:49152/AVTransport/control")!),
        renderingControl: nil,
        connectionManager: UPnPService(serviceType: "urn:schemas-upnp-org:service:ConnectionManager:1",
                                       controlURL: URL(string: "http://192.168.1.20:49152/CM/control")!))

    static func body(_ request: HTTPRequestSpec) -> String {
        String(data: request.body ?? Data(), encoding: .utf8) ?? ""
    }

    static func soapResponse(_ action: String, _ fields: [(String, String)]) -> HTTPResponseData {
        let inner = fields.map { "<\($0.0)>\($0.1)</\($0.0)>" }.joined()
        let xml = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body>"
            + "<u:\(action)Response xmlns:u=\"urn:x\">\(inner)</u:\(action)Response></s:Body></s:Envelope>"
        return HTTPResponseData(status: 200, body: Data(xml.utf8))
    }

    func testPlayPostsSOAPToAVTransport() async throws {
        let transport = FakeTransport { _ in HTTPResponseData(status: 200) }
        let client = DLNAClient(renderer: Self.renderer, transport: transport)
        try await client.play()
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url, Self.renderer.avTransport.controlURL)
        XCTAssertEqual(request.headers["SOAPAction"], "\"urn:schemas-upnp-org:service:AVTransport:1#Play\"")
        XCTAssertTrue(Self.body(request).contains("<Speed>1</Speed>"))
    }

    func testSeekUsesRelTime() async throws {
        let transport = FakeTransport { _ in HTTPResponseData(status: 200) }
        let client = DLNAClient(renderer: Self.renderer, transport: transport)
        try await client.seek(to: 75)
        XCTAssertTrue(Self.body(transport.requests[0]).contains("<Unit>REL_TIME</Unit><Target>00:01:15</Target>"))
    }

    func testFaultIsSurfaced() async {
        let fault = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><s:Fault><detail>"
            + "<UPnPError><errorCode>701</errorCode><errorDescription>Transition not available</errorDescription>"
            + "</UPnPError></detail></s:Fault></s:Body></s:Envelope>"
        let transport = FakeTransport { _ in HTTPResponseData(status: 500, body: Data(fault.utf8)) }
        let client = DLNAClient(renderer: Self.renderer, transport: transport)
        do {
            try await client.play()
            XCTFail("expected a fault")
        } catch {
            XCTAssertEqual(error as? DLNAError, .soapFault(SOAPFault(code: 701, detail: "Transition not available")))
        }
    }

    func testHTTPErrorWithoutFault() async {
        let transport = FakeTransport { _ in HTTPResponseData(status: 404) }
        let client = DLNAClient(renderer: Self.renderer, transport: transport)
        do {
            try await client.stop()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? DLNAError, .httpStatus(404))
        }
    }

    func testMissingRenderingControl() async {
        let client = DLNAClient(renderer: Self.renderer, transport: FakeTransport { _ in HTTPResponseData(status: 200) })
        do {
            _ = try await client.volume()
            XCTFail("expected missing service")
        } catch {
            XCTAssertEqual(error as? DLNAError, .missingService("RenderingControl"))
        }
    }

    func testPositionAndTransportInfo() async throws {
        let transport = FakeTransport { request in
            let action = request.headers["SOAPAction"] ?? ""
            if action.contains("GetPositionInfo") {
                return Self.soapResponse("GetPositionInfo", [("TrackDuration", "01:00:00"), ("RelTime", "00:10:00"),
                                                             ("TrackURI", "http://x/v.mp4")])
            }
            if action.contains("GetTransportInfo") {
                return Self.soapResponse("GetTransportInfo", [("CurrentTransportState", "PAUSED_PLAYBACK"),
                                                              ("CurrentTransportStatus", "OK")])
            }
            return Self.soapResponse("GetProtocolInfo", [("Source", ""), ("Sink", "http-get:*:video/mp4:*,http-get:*:video/mpeg:*")])
        }
        let client = DLNAClient(renderer: Self.renderer, transport: transport)
        let position = try await client.positionInfo()
        XCTAssertEqual(position.duration, 3600)
        XCTAssertEqual(position.position, 600)
        XCTAssertEqual(position.trackURI, "http://x/v.mp4")
        let info = try await client.transportInfo()
        XCTAssertEqual(info.state, .paused)
        let sink = try await client.protocolInfoSink()
        XCTAssertEqual(sink.map(\.mime), ["video/mp4", "video/mpeg"])
        XCTAssertEqual(transport.requests.last?.url.absoluteString, "http://192.168.1.20:49152/CM/control")
    }

    func testOutputActionWithEmptyBodyIsBadResponse() async {
        let client = DLNAClient(renderer: Self.renderer, transport: FakeTransport { _ in HTTPResponseData(status: 200) })
        do {
            _ = try await client.transportInfo()
            XCTFail("expected bad response")
        } catch {
            XCTAssertEqual(error as? DLNAError, .badResponse)
        }
    }
}
