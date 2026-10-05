import Foundation

/// One format checked by "Tester ma TV".
public enum TVTestCase: String, Codable, CaseIterable, Sendable {
    case mp4
    case hlsTS
    case liveTS
    case hlsFMP4
    case liveFMP4

    public var label: String {
        switch self {
        case .mp4: return "Vidéo MP4"
        case .hlsTS: return "HLS (segments TS)"
        case .liveTS: return "Flux continu TS"
        case .hlsFMP4: return "HLS (segments fMP4)"
        case .liveFMP4: return "Flux continu MP4"
        }
    }
}

public struct TVTestResults: Codable, Equatable, Sendable {
    /// Keyed by `TVTestCase.rawValue` (string keys keep the JSON readable).
    public var results: [String: Bool]
    public var date: Date
    /// The TV's ProtocolInfo sink list at the time of the test.
    public var sink: [String]

    public init(results: [TVTestCase: Bool], date: Date, sink: [String]) {
        var map: [String: Bool] = [:]
        for (testCase, passed) in results {
            map[testCase.rawValue] = passed
        }
        self.results = map
        self.date = date
        self.sink = sink
    }

    public func result(_ testCase: TVTestCase) -> Bool? {
        results[testCase.rawValue]
    }

    public var passedCount: Int { results.values.filter { $0 }.count }
}
