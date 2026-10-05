import XCTest
@testable import CastCore

final class UPnPTests: XCTestCase {
    static let descriptionURL = URL(string: "http://192.168.1.20:49152/description.xml")!

    static let nestedDescription = """
    <?xml version="1.0"?>
    <root xmlns="urn:schemas-upnp-org:device-1-0">
      <specVersion><major>1</major><minor>0</minor></specVersion>
      <device>
        <deviceType>urn:schemas-upnp-org:device:Basic:1</deviceType>
        <friendlyName>Salon</friendlyName>
        <UDN>uuid:root</UDN>
        <deviceList>
          <device>
            <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
            <friendlyName>Philips TV &amp; co</friendlyName>
            <manufacturer>TP Vision</manufacturer>
            <modelName>55PUS8009</modelName>
            <UDN>uuid:renderer-1</UDN>
            <serviceList>
              <service>
                <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
                <controlURL>/RenderingControl/control</controlURL>
              </service>
              <service>
                <serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
                <controlURL>ConnectionManager/control</controlURL>
              </service>
              <service>
                <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
                <controlURL>/AVTransport/control</controlURL>
                <eventSubURL>/AVTransport/event</eventSubURL>
              </service>
            </serviceList>
          </device>
        </deviceList>
      </device>
    </root>
    """

    func testSSDPResponseParsing() {
        let text = "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nLocation: http://192.168.1.20:49152/description.xml\r\n"
            + "ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\nUSN: uuid:abc::urn:schemas-upnp-org:device:MediaRenderer:1\r\n"
            + "SERVER: Linux/4.9 UPnP/1.0 TitanOS/1\r\n\r\n"
        let response = SSDP.parseResponse(text)
        XCTAssertEqual(response?.location.absoluteString, "http://192.168.1.20:49152/description.xml")
        XCTAssertEqual(response?.st, SSDP.mediaRendererST)
        XCTAssertEqual(response?.server, "Linux/4.9 UPnP/1.0 TitanOS/1")
        XCTAssertNil(SSDP.parseResponse("garbage"))
        XCTAssertNil(SSDP.parseResponse("HTTP/1.1 200 OK\r\nST: x\r\n\r\n"))
    }

    func testSSDPSearchRequest() {
        let request = SSDP.searchRequest(host: "192.168.1.20", st: SSDP.mediaRendererST)
        XCTAssertTrue(request.hasPrefix("M-SEARCH * HTTP/1.1\r\nHOST: 192.168.1.20:1900\r\n"))
        XCTAssertTrue(request.contains("MAN: \"ssdp:discover\"\r\n"))
        XCTAssertTrue(request.hasSuffix("\r\n\r\n"))
    }

    func testNestedRendererDescription() throws {
        let renderer = try DeviceDescriptionParser.parseRenderer(xml: Data(Self.nestedDescription.utf8),
                                                                 descriptionURL: Self.descriptionURL)
        XCTAssertEqual(renderer.friendlyName, "Philips TV & co")
        XCTAssertEqual(renderer.udn, "uuid:renderer-1")
        XCTAssertEqual(renderer.manufacturer, "TP Vision")
        XCTAssertEqual(renderer.avTransport.controlURL.absoluteString, "http://192.168.1.20:49152/AVTransport/control")
        XCTAssertEqual(renderer.avTransport.eventSubURL?.absoluteString, "http://192.168.1.20:49152/AVTransport/event")
        XCTAssertEqual(renderer.connectionManager?.controlURL.absoluteString, "http://192.168.1.20:49152/ConnectionManager/control")
        XCTAssertEqual(renderer.renderingControl?.serviceType, "urn:schemas-upnp-org:service:RenderingControl:1")
        XCTAssertEqual(renderer.host, "192.168.1.20")
    }

    func testDescriptionWithoutAVTransportThrows() {
        let xml = """
        <root><device><friendlyName>Router</friendlyName><serviceList><service>
        <serviceType>urn:schemas-upnp-org:service:WANIPConnection:1</serviceType><controlURL>/x</controlURL>
        </service></serviceList></device></root>
        """
        XCTAssertThrowsError(try DeviceDescriptionParser.parseRenderer(xml: Data(xml.utf8), descriptionURL: Self.descriptionURL)) {
            XCTAssertEqual($0 as? DeviceDescriptionError, .noRenderer)
        }
        XCTAssertThrowsError(try DeviceDescriptionParser.parseRenderer(xml: Data("not xml".utf8), descriptionURL: Self.descriptionURL)) {
            XCTAssertEqual($0 as? DeviceDescriptionError, .invalidXML)
        }
    }

    func testSOAPEnvelopeEscapesArguments() {
        let envelope = SOAP.envelope(action: "SetAVTransportURI", serviceType: "urn:schemas-upnp-org:service:AVTransport:1",
                                     arguments: [("InstanceID", "0"), ("CurrentURI", "http://x/a?b=1&c=2"),
                                                 ("CurrentURIMetaData", "<DIDL-Lite/>")])
        XCTAssertTrue(envelope.contains("<u:SetAVTransportURI xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">"))
        XCTAssertTrue(envelope.contains("<CurrentURI>http://x/a?b=1&amp;c=2</CurrentURI>"))
        XCTAssertTrue(envelope.contains("<CurrentURIMetaData>&lt;DIDL-Lite/&gt;</CurrentURIMetaData>"))
        XCTAssertEqual(SOAP.actionHeader(serviceType: "urn:x:1", action: "Play"), "\"urn:x:1#Play\"")
    }

    func testSOAPResponseAndFault() throws {
        let response = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>\
        <u:GetTransportInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">\
        <CurrentTransportState>PLAYING</CurrentTransportState><CurrentTransportStatus>OK</CurrentTransportStatus>\
        <CurrentSpeed>1</CurrentSpeed></u:GetTransportInfoResponse></s:Body></s:Envelope>
        """
        let output = try SOAP.parseResponse(Data(response.utf8), action: "GetTransportInfo")
        XCTAssertEqual(output["CurrentTransportState"], "PLAYING")
        XCTAssertEqual(output["CurrentSpeed"], "1")

        let fault = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault><faultcode>s:Client</faultcode>\
        <faultstring>UPnPError</faultstring><detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0">\
        <errorCode>714</errorCode><errorDescription>Illegal MIME-type</errorDescription></UPnPError></detail>\
        </s:Fault></s:Body></s:Envelope>
        """
        XCTAssertEqual(SOAP.parseFault(Data(fault.utf8)), SOAPFault(code: 714, detail: "Illegal MIME-type"))
        XCTAssertThrowsError(try SOAP.parseResponse(Data(fault.utf8), action: "Play")) {
            XCTAssertEqual($0 as? SOAPFault, SOAPFault(code: 714, detail: "Illegal MIME-type"))
        }
        XCTAssertNil(SOAP.parseFault(Data(response.utf8)))
    }

    func testUPnPTime() {
        XCTAssertEqual(UPnPTime.parse("01:02:03.500"), 3723.5)
        XCTAssertEqual(UPnPTime.parse("0:00:00"), 0)
        XCTAssertEqual(UPnPTime.parse("42"), 42)
        XCTAssertNil(UPnPTime.parse("NOT_IMPLEMENTED"))
        XCTAssertNil(UPnPTime.parse(""))
        XCTAssertEqual(UPnPTime.format(3723.9), "01:02:03")
        XCTAssertEqual(UPnPTime.format(-5), "00:00:00")
        XCTAssertEqual(TransportState(raw: " playing "), .playing)
        XCTAssertEqual(TransportState(raw: "WHATEVER"), .unknown)
        XCTAssertTrue(TransportInfo(state: .stopped, status: "ERROR_OCCURRED").isError)
    }

    func testProtocolInfoAndCapabilities() {
        let list = ProtocolInfo.parseList("http-get:*:video/mp4:*,http-get:*:application/x-mpegURL:*, http-get:*:video/mpeg:DLNA.ORG_PN=MPEG_TS_SD_EU_ISO,bad")
        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list[2].additional, "DLNA.ORG_PN=MPEG_TS_SD_EU_ISO")
        let capabilities = RendererCapabilities(sink: list)
        XCTAssertTrue(capabilities.isKnown)
        XCTAssertTrue(capabilities.announcesHLS)
        XCTAssertTrue(capabilities.hasVideo)
        XCTAssertEqual(capabilities.mime(for: .hls), "application/x-mpegURL")
        XCTAssertEqual(capabilities.mime(for: .mpegTS), "video/mpeg")
        XCTAssertEqual(RendererCapabilities(sinkMimes: ["video/vnd.dlna.mpeg-tts", "video/mp2t"]).mime(for: .mpegTS), "video/mp2t")
        XCTAssertEqual(RendererCapabilities.unknown.mime(for: .mpegTS), "video/mpeg")
        XCTAssertEqual(RendererCapabilities.unknown.mime(for: .hls), "application/vnd.apple.mpegurl")
        XCTAssertTrue(RendererCapabilities.unknown.hasVideo)
        XCTAssertFalse(RendererCapabilities(sinkMimes: ["audio/mpeg", "audio/flac"]).hasVideo)
        XCTAssertEqual(RendererCapabilities(sinkMimes: ["video/mp4", "VIDEO/MP4"]).sinkMimes, ["video/mp4"])
    }

    func testDLNAFlagsAndDIDL() {
        XCTAssertEqual(DLNAFlags.protocolInfo(mime: "video/mp4", seekable: true),
                       "http-get:*:video/mp4:DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000")
        XCTAssertTrue(DLNAFlags.additionalInfo(seekable: false).hasPrefix("DLNA.ORG_OP=00;"))
        let didl = DIDL.metadata(title: "A & B", url: "http://x/y?a=1&b=2", protocolInfo: "http-get:*:video/mp4:*", duration: 3723)
        XCTAssertTrue(didl.contains("<dc:title>A &amp; B</dc:title>"))
        XCTAssertTrue(didl.contains(">http://x/y?a=1&amp;b=2</res>"))
        XCTAssertTrue(didl.contains("duration=\"01:02:03.000\""))
        XCTAssertTrue(didl.contains("<upnp:class>object.item.videoItem</upnp:class>"))
    }
}
