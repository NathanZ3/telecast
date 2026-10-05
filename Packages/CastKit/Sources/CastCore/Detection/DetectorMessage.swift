import Foundation

/// A message posted by `detector.js` through `window.webkit.messageHandlers.castDetector`.
public struct DetectorMessage: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case candidate
        case playing
        case hello
    }

    public var kind: Kind
    public var url: String?
    public var via: String?
    public var mime: String?
    public var frameURL: String?
    public var duration: Double?
    public var width: Double?
    public var height: Double?
    public var playing: Bool?
    public var userAgent: String?

    public init(kind: Kind, url: String? = nil, via: String? = nil, mime: String? = nil, frameURL: String? = nil,
                duration: Double? = nil, width: Double? = nil, height: Double? = nil, playing: Bool? = nil,
                userAgent: String? = nil) {
        self.kind = kind
        self.url = url
        self.via = via
        self.mime = mime
        self.frameURL = frameURL
        self.duration = duration
        self.width = width
        self.height = height
        self.playing = playing
        self.userAgent = userAgent
    }

    /// Decodes a `WKScriptMessage.body` (a dictionary, or a JSON string).
    public static func decode(from body: Any) -> DetectorMessage? {
        let data: Data
        if let string = body as? String {
            data = Data(string.utf8)
        } else {
            guard JSONSerialization.isValidJSONObject(body),
                  let encoded = try? JSONSerialization.data(withJSONObject: body) else { return nil }
            data = encoded
        }
        return try? JSONDecoder().decode(DetectorMessage.self, from: data)
    }
}
