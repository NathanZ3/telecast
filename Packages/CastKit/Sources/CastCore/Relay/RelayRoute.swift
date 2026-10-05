import Foundation

/// URL layout of the relay. Offsets live in the path (no query string): some TVs mishandle queries.
public enum RelayRoute: Equatable, Sendable {
    case health
    case testFile(String)
    case progressive(session: String, ext: String)
    case playlist(session: String)
    case resource(session: String, id: String)
    case liveTS(session: String, offsetMillis: Int)
    case liveFMP4(session: String, offsetMillis: Int)
    case notFound

    public static func parse(path: String) -> RelayRoute {
        let parts = path.split(separator: "/").map(String.init)
        guard let first = parts.first else { return .notFound }
        switch first {
        case "h" where parts.count == 1:
            return .health
        case "t" where parts.count >= 2:
            let relative = parts.dropFirst().joined(separator: "/")
            return relative.contains("..") ? .notFound : .testFile(relative)
        case "s" where parts.count >= 3:
            let session = parts[1]
            if parts.count == 3 {
                let name = parts[2]
                if name == "m.m3u8" { return .playlist(session: session) }
                if name.hasPrefix("v."), name.count > 2 { return .progressive(session: session, ext: String(name.dropFirst(2))) }
                return .notFound
            }
            if parts.count == 4, parts[2] == "r" {
                return .resource(session: session, id: parts[3])
            }
            if parts.count == 4, parts[2].hasPrefix("t"), let millis = Int(parts[2].dropFirst()) {
                if parts[3] == "live.ts" { return .liveTS(session: session, offsetMillis: millis) }
                if parts[3] == "live.mp4" { return .liveFMP4(session: session, offsetMillis: millis) }
            }
            return .notFound
        default:
            return .notFound
        }
    }

    public var path: String {
        switch self {
        case .health:
            return "/h"
        case .testFile(let relative):
            return "/t/" + relative
        case .progressive(let session, let ext):
            return "/s/\(session)/v.\(ext)"
        case .playlist(let session):
            return "/s/\(session)/m.m3u8"
        case .resource(let session, let id):
            return "/s/\(session)/r/\(id)"
        case .liveTS(let session, let millis):
            return "/s/\(session)/t\(millis)/live.ts"
        case .liveFMP4(let session, let millis):
            return "/s/\(session)/t\(millis)/live.mp4"
        case .notFound:
            return "/404"
        }
    }

    public var sessionID: String? {
        switch self {
        case .progressive(let session, _), .playlist(let session), .resource(let session, _),
             .liveTS(let session, _), .liveFMP4(let session, _):
            return session
        case .health, .testFile, .notFound:
            return nil
        }
    }
}
