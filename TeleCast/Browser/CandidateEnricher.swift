import Foundation
import CastCore
import CastNet

/// Reads an HLS candidate's playlists in the background to show its quality, duration and DRM status.
enum CandidateEnricher {
    static func inspect(_ candidate: MediaCandidate, cap: QualityCap, fetcher: UpstreamFetcher) async -> HLSInfo? {
        do {
            let inspected = try await HLSInspector.inspect(url: candidate.url, context: candidate.context, cap: cap,
                                                           fetcher: fetcher)
            return inspected.info
        } catch {
            castLog("detect", "Playlist illisible (\(candidate.url.host ?? "?")) : \(error.localizedDescription)")
            return nil
        }
    }
}
