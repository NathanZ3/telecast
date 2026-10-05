import Foundation

/// Remembers which strategy worked, per TV and kind of content (and per media host).
public struct StrategyMemory: Codable, Sendable {
    var entries: [String: CastStrategy] = [:]

    public init() {}

    static func key(tv: String, profile: ContentProfile, host: String?) -> String {
        "\(tv)|\(profile.kind.rawValue)|\(profile.segmentFormat.rawValue)|\(profile.hasSeparateAudio)|\(host ?? "*")"
    }

    /// Host-specific memory first, then what worked for the same kind of content on this TV.
    public func recall(tv: String, profile: ContentProfile) -> CastStrategy? {
        entries[Self.key(tv: tv, profile: profile, host: profile.host)]
            ?? entries[Self.key(tv: tv, profile: profile, host: nil)]
    }

    public mutating func remember(_ strategy: CastStrategy, tv: String, profile: ContentProfile) {
        entries[Self.key(tv: tv, profile: profile, host: profile.host)] = strategy
        entries[Self.key(tv: tv, profile: profile, host: nil)] = strategy
    }

    public var isEmpty: Bool { entries.isEmpty }
}
