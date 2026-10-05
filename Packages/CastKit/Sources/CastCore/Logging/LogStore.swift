import Foundation

/// In-memory ring buffer of log lines, mirrored to a rotating file. Shown and shared
/// from the app's "Journal" screen — the main debugging tool without Xcode.
public final class LogStore: @unchecked Sendable {
    public struct Entry: Identifiable, Sendable {
        public let id: Int
        public let date: Date
        public let category: String
        public let message: String

        public var line: String {
            "\(LogStore.timestamp(date)) [\(category)] \(message)"
        }
    }

    public static let shared = LogStore()

    private let lock = NSLock()
    private let capacity: Int
    private var buffer: [Entry] = []
    private var nextID = 0
    private var fileURL: URL?
    private var maxFileBytes = 1_000_000
    private var appendHandler: (@Sendable () -> Void)?
    private let fileQueue = DispatchQueue(label: "telecast.log.file")

    public init(capacity: Int = 2000) {
        self.capacity = capacity
    }

    public var onAppend: (@Sendable () -> Void)? {
        get { lock.withLock { appendHandler } }
        set { lock.withLock { appendHandler = newValue } }
    }

    public func configure(fileURL: URL?, maxFileBytes: Int = 1_000_000) {
        lock.withLock {
            self.fileURL = fileURL
            self.maxFileBytes = maxFileBytes
        }
    }

    public func log(_ category: String, _ message: String) {
        lock.lock()
        nextID += 1
        let entry = Entry(id: nextID, date: Date(), category: category, message: message)
        buffer.append(entry)
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
        let callback = appendHandler
        let file = fileURL
        let maxBytes = maxFileBytes
        lock.unlock()

        if let file {
            let line = entry.line + "\n"
            fileQueue.async {
                LogStore.append(line, to: file, maxBytes: maxBytes)
            }
        }
        callback?()
    }

    public func entries() -> [Entry] {
        lock.withLock { buffer }
    }

    public func exportText() -> String {
        entries().map(\.line).joined(separator: "\n")
    }

    public func clear() {
        lock.withLock { buffer.removeAll() }
    }

    /// Waits until pending file writes are done.
    public func flush() {
        fileQueue.sync {}
    }

    static func append(_ text: String, to url: URL, maxBytes: Int) {
        let manager = FileManager.default
        if let attributes = try? manager.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber,
           size.intValue + text.utf8.count > maxBytes {
            let rotated = url.appendingPathExtension("1")
            try? manager.removeItem(at: rotated)
            try? manager.moveItem(at: url, to: rotated)
        }
        if !manager.fileExists(atPath: url.path) {
            try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            manager.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = handle.seekToEndOfFile()
        handle.write(Data(text.utf8))
    }

    static func timestamp(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let millis = (components.nanosecond ?? 0) / 1_000_000
        return String(format: "%02ld:%02ld:%02ld.%03ld", components.hour ?? 0, components.minute ?? 0,
                      components.second ?? 0, millis)
    }
}

/// Logs to the shared journal.
public func castLog(_ category: String, _ message: @autoclosure () -> String) {
    LogStore.shared.log(category, message())
}
