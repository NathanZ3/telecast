import Foundation

/// Matches hosts against a list of ad / tracking domains (exact match or any subdomain).
public struct AdHostMatcher: Sendable {
    private let domains: Set<String>

    public init(domains: Set<String>) {
        self.domains = Set(domains.map { $0.lowercased() }.filter { !$0.isEmpty })
    }

    /// One domain per line; blank lines and lines starting with `#` are ignored.
    public init(text: String) {
        var set = Set<String>()
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            set.insert(line.lowercased())
        }
        self.init(domains: set)
    }

    public var count: Int { domains.count }

    public func matches(host: String) -> Bool {
        var candidate = host.lowercased()
        if candidate.hasSuffix(".") { candidate.removeLast() }
        while !candidate.isEmpty {
            if domains.contains(candidate) { return true }
            guard let dot = candidate.firstIndex(of: ".") else { return false }
            candidate = String(candidate[candidate.index(after: dot)...])
        }
        return false
    }

    /// Small built-in list (ad networks, video-ad servers, analytics) used to ignore
    /// media requests that are obviously ads, even before the full blocklist is loaded.
    public static let builtIn = AdHostMatcher(domains: [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "google-analytics.com",
        "googletagmanager.com", "googletagservices.com", "imasdk.googleapis.com", "adservice.google.com",
        "amazon-adsystem.com", "adnxs.com", "criteo.com", "criteo.net", "taboola.com", "outbrain.com",
        "popads.net", "popcash.net", "propellerads.com", "adsterra.com", "exoclick.com", "juicyads.com",
        "trafficjunky.net", "onclickads.net", "hilltopads.net", "clickadu.com", "adcash.com", "a-ads.com",
        "spotxchange.com", "springserve.com", "teads.tv", "smartadserver.com", "pubmatic.com",
        "rubiconproject.com", "openx.net", "casalemedia.com", "moatads.com", "scorecardresearch.com",
        "jwpltx.com", "adskeeper.com", "mgid.com", "revcontent.com", "zedo.com", "yieldmo.com",
    ])
}
