import Foundation

/// Rewrites every URI of a playlist (segments, keys, init sections, variants, renditions)
/// so that the TV fetches them through the relay.
public enum PlaylistRewriter {
    static let uriTags = [
        "#EXT-X-KEY:", "#EXT-X-MAP:", "#EXT-X-MEDIA:", "#EXT-X-I-FRAME-STREAM-INF:", "#EXT-X-SESSION-KEY:",
        "#EXT-X-PRELOAD-HINT:", "#EXT-X-PART:", "#EXT-X-RENDITION-REPORT:",
    ]

    public static func rewrite(_ text: String, baseURL: URL, map: (URL) -> String) -> String {
        var output: [String] = []
        for line in M3U8Parser.normalizedLines(text) {
            if line.isEmpty {
                continue
            }
            if line.hasPrefix("#") {
                if uriTags.contains(where: { line.hasPrefix($0) }) {
                    output.append(rewriteURIAttribute(line, baseURL: baseURL, map: map))
                } else {
                    output.append(line)
                }
            } else if let url = M3U8Parser.resolve(line, base: baseURL) {
                output.append(map(url))
            } else {
                output.append(line)
            }
        }
        return output.joined(separator: "\n") + "\n"
    }

    static func rewriteURIAttribute(_ line: String, baseURL: URL, map: (URL) -> String) -> String {
        guard let marker = line.range(of: "URI=\"") else { return line }
        let valueStart = marker.upperBound
        guard let valueEnd = line[valueStart...].firstIndex(of: "\"") else { return line }
        let value = String(line[valueStart..<valueEnd])
        guard let url = M3U8Parser.resolve(value, base: baseURL), url.scheme == "http" || url.scheme == "https" else {
            return line
        }
        return String(line[..<valueStart]) + map(url) + String(line[valueEnd...])
    }
}
