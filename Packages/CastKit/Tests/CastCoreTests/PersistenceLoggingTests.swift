import XCTest
@testable import CastCore

final class PersistenceLoggingTests: XCTestCase {
    struct Sample: Codable, Equatable {
        var name: String
        var count: Int
    }

    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testJSONStoreRoundTrip() throws {
        let directory = try temporaryDirectory()
        let store = JSONFileStore(url: directory.appendingPathComponent("nested/sample.json"),
                                  defaultValue: Sample(name: "default", count: 0))
        XCTAssertEqual(store.load(), Sample(name: "default", count: 0))
        store.save(Sample(name: "tv", count: 3))
        XCTAssertEqual(store.load(), Sample(name: "tv", count: 3))
        let reopened = JSONFileStore(url: directory.appendingPathComponent("nested/sample.json"),
                                     defaultValue: Sample(name: "default", count: 0))
        XCTAssertEqual(reopened.load(), Sample(name: "tv", count: 3))
    }

    func testCorruptFileFallsBackToDefault() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("bad.json")
        try Data("{not json".utf8).write(to: url)
        let store = JSONFileStore(url: url, defaultValue: [String]())
        XCTAssertEqual(store.load(), [])
    }

    func testRingBufferKeepsLastEntries() {
        let log = LogStore(capacity: 3)
        for index in 1...5 {
            log.log("test", "m\(index)")
        }
        XCTAssertEqual(log.entries().map(\.message), ["m3", "m4", "m5"])
        XCTAssertTrue(log.exportText().contains("[test] m5"))
        log.clear()
        XCTAssertTrue(log.entries().isEmpty)
    }

    func testFileRotation() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("telecast.log")
        let log = LogStore(capacity: 100)
        log.configure(fileURL: file, maxFileBytes: 200)
        for index in 1...20 {
            log.log("rotation", "ligne numéro \(index)")
        }
        log.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.appendingPathExtension("1").path))
        let content = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(content.contains("ligne numéro 20"))
    }

    func testOnAppendCallbackAndSharedLogger() {
        let log = LogStore(capacity: 10)
        let expectation = expectation(description: "callback")
        log.onAppend = { expectation.fulfill() }
        log.log("cb", "hello")
        wait(for: [expectation], timeout: 1)

        castLog("shared", "bonjour")
        XCTAssertEqual(LogStore.shared.entries().last?.message, "bonjour")
    }
}
