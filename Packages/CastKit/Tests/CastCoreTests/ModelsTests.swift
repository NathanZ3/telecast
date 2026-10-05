import XCTest
@testable import CastCore

final class ModelsTests: XCTestCase {
    func testMediaKindRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode([MediaKind.hls, .dash, .progressive])
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"hls\",\"dash\",\"progressive\"]")
        let decoded = try JSONDecoder().decode([MediaKind].self, from: data)
        XCTAssertEqual(decoded, [.hls, .dash, .progressive])
    }

    func testSegmentFormatRawValues() {
        XCTAssertEqual(SegmentFormat(rawValue: "fmp4"), .fmp4)
        XCTAssertEqual(SegmentFormat.ts.rawValue, "ts")
        XCTAssertNil(SegmentFormat(rawValue: "mkv"))
    }
}
