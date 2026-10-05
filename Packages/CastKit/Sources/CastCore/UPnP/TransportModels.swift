import Foundation

public enum TransportState: String, Codable, Sendable {
    case stopped = "STOPPED"
    case playing = "PLAYING"
    case paused = "PAUSED_PLAYBACK"
    case transitioning = "TRANSITIONING"
    case noMedia = "NO_MEDIA_PRESENT"
    case unknown = "UNKNOWN"

    public init(raw: String) {
        let upper = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self = TransportState(rawValue: upper) ?? .unknown
    }
}

public struct TransportInfo: Equatable, Sendable {
    public var state: TransportState
    public var status: String

    public init(state: TransportState, status: String = "OK") {
        self.state = state
        self.status = status
    }

    public var isError: Bool { status.uppercased() == "ERROR_OCCURRED" }
}

public struct PositionInfo: Equatable, Sendable {
    public var duration: Double?
    public var position: Double?
    public var trackURI: String?

    public init(duration: Double? = nil, position: Double? = nil, trackURI: String? = nil) {
        self.duration = duration
        self.position = position
        self.trackURI = trackURI
    }
}

/// `H+:MM:SS[.F+]` times used by AVTransport.
public enum UPnPTime {
    public static func parse(_ string: String) -> Double? {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.uppercased() != "NOT_IMPLEMENTED" else { return nil }
        let parts = text.split(separator: ":")
        if parts.count == 3, let hours = Double(parts[0]), let minutes = Double(parts[1]), let seconds = Double(parts[2]) {
            guard hours >= 0, minutes >= 0, seconds >= 0 else { return nil }
            return hours * 3600 + minutes * 60 + seconds
        }
        if parts.count == 1, let seconds = Double(text), seconds >= 0 { return seconds }
        return nil
    }

    public static func format(_ seconds: Double) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds.rounded(.down))) : 0
        return String(format: "%02ld:%02ld:%02ld", total / 3600, (total % 3600) / 60, total % 60)
    }
}
