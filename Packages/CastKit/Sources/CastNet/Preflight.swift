import Foundation
import CastCore

/// Checks whether the media answers without any browser header — i.e. whether the TV
/// could load the original URL by itself.
public enum Preflight {
    public static func directReachable(url: URL, firstSegment: URL?) async -> Bool {
        let session = URLSessionTransport.makeSession()
        defer { session.finishTasksAndInvalidate() }
        guard await probe(url, session: session) else { return false }
        if let firstSegment {
            return await probe(firstSegment, session: session)
        }
        return true
    }

    static func probe(_ url: URL, session: URLSession) async -> Bool {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            bytes.task.cancel()
            guard let http = response as? HTTPURLResponse else { return false }
            let ok = (200..<300).contains(http.statusCode)
            castLog("preflight", "\(url.host ?? "?") → \(http.statusCode)")
            return ok
        } catch {
            castLog("preflight", "\(url.host ?? "?") → \(error.localizedDescription)")
            return false
        }
    }
}
