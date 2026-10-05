import Foundation

/// Maximum quality sent to the TV.
public enum QualityCap: String, Codable, CaseIterable, Sendable {
    case auto
    case p1080
    case p720
    case p480

    public var maxHeight: Int? {
        switch self {
        case .auto: return nil
        case .p1080: return 1080
        case .p720: return 720
        case .p480: return 480
        }
    }

    public var label: String {
        switch self {
        case .auto: return "Auto (la meilleure)"
        case .p1080: return "1080p maximum"
        case .p720: return "720p maximum"
        case .p480: return "480p maximum"
        }
    }
}

public enum VariantSelector {
    /// Highest bandwidth video variant within the cap; the smallest one when none fits.
    public static func choose(_ variants: [HLSVariantStream], cap: QualityCap) -> HLSVariantStream? {
        let video = variants.filter { !$0.isAudioOnly }
        let pool = video.isEmpty ? variants : video
        guard !pool.isEmpty else { return nil }

        let allowed: [HLSVariantStream]
        if let maxHeight = cap.maxHeight {
            allowed = pool.filter { ($0.height ?? 0) <= maxHeight }
        } else {
            allowed = pool
        }
        if allowed.isEmpty {
            return pool.min { lhs, rhs in
                (lhs.height ?? Int.max, lhs.bandwidth ?? Int.max) < (rhs.height ?? Int.max, rhs.bandwidth ?? Int.max)
            }
        }
        return allowed.max { ($0.bandwidth ?? 0) < ($1.bandwidth ?? 0) }
    }
}
