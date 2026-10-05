import XCTest
@testable import CastCore

final class XMLTests: XCTestCase {
    func testParsesNamespacedDocument() throws {
        let xml = """
        <s:Envelope xmlns:s="x"><s:Body><u:Resp xmlns:u="y"><A>1</A><B> two </B><C attr="v">&lt;tag&gt;</C></u:Resp></s:Body></s:Envelope>
        """
        let root = try MiniXML.parse(Data(xml.utf8))
        XCTAssertEqual(root.name, "Envelope")
        let response = try XCTUnwrap(root.descendant("Resp"))
        XCTAssertEqual(response.value("A"), "1")
        XCTAssertEqual(response.value("B"), "two")
        XCTAssertEqual(response.value("C"), "<tag>")
        XCTAssertEqual(response.child("C")?.attributes["attr"], "v")
        XCTAssertEqual(response.children(named: "A").count, 1)
        XCTAssertNil(root.descendant("Missing"))
    }

    func testInvalidXMLThrows() {
        XCTAssertThrowsError(try MiniXML.parse(Data("<a><b></a>".utf8)))
        XCTAssertThrowsError(try MiniXML.parse(Data()))
    }
}
