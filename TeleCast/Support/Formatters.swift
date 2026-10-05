import Foundation
import CastCore

enum Formatters {
    static func time(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite else { return "--:--" }
        return CastSession.timeLabel(seconds)
    }

    /// "1 h 52" / "45 min".
    static func duration(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        let minutes = Int(seconds / 60)
        if minutes >= 60 {
            return String(format: "%ld h %02ld", minutes / 60, minutes % 60)
        }
        return "\(max(1, minutes)) min"
    }

    static func candidateSubtitle(_ candidate: MediaCandidate) -> String {
        var parts: [String] = []
        switch candidate.kind {
        case .hls:
            parts.append("HLS")
        case .dash:
            parts.append("DASH (non pris en charge)")
        case .progressive:
            let ext = candidate.url.pathExtension.uppercased()
            parts.append(ext.isEmpty ? "Vidéo" : ext)
        }
        if let height = candidate.hls?.variants.compactMap(\.height).max() ?? candidate.height {
            parts.append("\(height)p")
        }
        if let length = duration(candidate.effectiveDuration) {
            parts.append(length)
        }
        if candidate.hls?.isLive == true { parts.append("Direct") }
        if candidate.isDRM { parts.append("Protégée (DRM)") }
        if let host = candidate.url.host { parts.append(host) }
        return parts.joined(separator: " · ")
    }

    static func variantLabel(_ variant: HLSInfo.Variant) -> String {
        var text = variant.height.map { "\($0)p" } ?? "Qualité"
        if let bandwidth = variant.bandwidth {
            text += String(format: " · %.1f Mb/s", Double(bandwidth) / 1_000_000)
        }
        return text
    }
}
