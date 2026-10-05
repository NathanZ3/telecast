import Foundation

/// A Codable value persisted as one JSON file (atomic writes, default value when missing).
public final class JSONFileStore<Value: Codable>: @unchecked Sendable {
    private let url: URL
    private let defaultValue: Value
    private let lock = NSLock()

    public init(url: URL, defaultValue: Value) {
        self.url = url
        self.defaultValue = defaultValue
    }

    public func load() -> Value {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Value.self, from: data) else {
            return defaultValue
        }
        return value
    }

    public func save(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            castLog("store", "Écriture impossible de \(url.lastPathComponent) : \(error.localizedDescription)")
        }
    }

    /// `Application Support/TeleCast/<name>.json`
    public static func applicationSupportURL(named name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("TeleCast", isDirectory: true).appendingPathComponent("\(name).json")
    }
}
