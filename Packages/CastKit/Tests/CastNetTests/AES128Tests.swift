import XCTest
@testable import CastNet

final class AES128Tests: XCTestCase {
    let key = Data((0..<16).map { UInt8($0) })
    let iv = Data(repeating: 0, count: 16)

    func testRoundTrip() throws {
        let plain = Data("hello telecast!! et un peu plus de texte".utf8)
        let encrypted = try AES128.encryptCBC(plain, key: key, iv: iv)
        XCTAssertNotEqual(encrypted, plain)
        XCTAssertEqual(encrypted.count % 16, 0)
        XCTAssertEqual(try AES128.decryptCBC(encrypted, key: key, iv: iv), plain)
    }

    func testRejectsBadKey() {
        XCTAssertThrowsError(try AES128.decryptCBC(Data(count: 16), key: Data(count: 5), iv: iv)) {
            XCTAssertEqual($0 as? AES128Error, .badKeyOrIV)
        }
    }

    func testSequenceIV() {
        var expected = Data(repeating: 0, count: 16)
        expected[15] = 1
        XCTAssertEqual(AES128.iv(forSequence: 1), expected)
        let big = AES128.iv(forSequence: 0x0102)
        XCTAssertEqual(big[14], 0x01)
        XCTAssertEqual(big[15], 0x02)
    }

    func testByteRangeParsing() {
        XCTAssertEqual(RelayServer.byteRange("bytes=10-19", size: 100), 10..<20)
        XCTAssertEqual(RelayServer.byteRange("bytes=90-", size: 100), 90..<100)
        XCTAssertEqual(RelayServer.byteRange("bytes=-5", size: 100), 95..<100)
        XCTAssertEqual(RelayServer.byteRange("bytes=0-1000", size: 100), 0..<100)
        XCTAssertNil(RelayServer.byteRange("bytes=200-", size: 100))
        XCTAssertNil(RelayServer.byteRange("items=0-1", size: 100))
    }

    func testSegmentCacheEvictsLeastRecentlyUsed() {
        let cache = SegmentCache(capacity: 2)
        cache.set("a", Data([1]))
        cache.set("b", Data([2]))
        _ = cache.get("a")
        cache.set("c", Data([3]))
        XCTAssertNotNil(cache.get("a"))
        XCTAssertNil(cache.get("b"))
        XCTAssertEqual(cache.count, 2)
    }
}
