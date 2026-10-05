import Foundation

/// Small LRU cache of decrypted segments shared by the connections of a session
/// (TVs often open several connections for the same stream).
final class SegmentCache: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var order: [String] = []
    private var storage: [String: Data] = [:]

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func get(_ key: String) -> Data? {
        lock.withLock {
            guard let value = storage[key] else { return nil }
            if let index = order.firstIndex(of: key) {
                order.remove(at: index)
                order.append(key)
            }
            return value
        }
    }

    func set(_ key: String, _ value: Data) {
        lock.withLock {
            if storage[key] == nil {
                order.append(key)
            } else if let index = order.firstIndex(of: key) {
                order.remove(at: index)
                order.append(key)
            }
            storage[key] = value
            while order.count > capacity {
                let evicted = order.removeFirst()
                storage[evicted] = nil
            }
        }
    }

    var count: Int { lock.withLock { storage.count } }
}
