import Foundation

public enum NavigationKind: Sendable {
    case linkActivated
    case formSubmitted
    case backForward
    case reload
    case formResubmitted
    case other
}

public enum BlockReason: Equatable, Sendable {
    case adHost(String)
    case crossSiteRedirect(String)
    case badScheme(String)
}

public enum NavigationDecision: Equatable, Sendable {
    case allow
    case block(BlockReason)
}

public enum PopupDecision: Equatable, Sendable {
    case openInPlace
    case block
}

/// Blocks ad navigations, forced cross-site redirects and popups in the in-app browser.
public struct NavigationGuard: Sendable {
    public var blockRedirects: Bool
    public var adMatcher: AdHostMatcher
    public var intentWindow: TimeInterval
    private var lastIntentAt: Date?

    public init(blockRedirects: Bool = true, adMatcher: AdHostMatcher, intentWindow: TimeInterval = 3) {
        self.blockRedirects = blockRedirects
        self.adMatcher = adMatcher
        self.intentWindow = intentWindow
    }

    /// The user typed an address, tapped a link, a favourite or the history.
    public mutating func noteUserIntent(at date: Date) {
        lastIntentAt = date
    }

    public mutating func decide(url: URL, isMainFrame: Bool, kind: NavigationKind, currentURL: URL?,
                                now: Date) -> NavigationDecision {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "about" || scheme == "blob" || scheme == "data" { return .allow }
        guard scheme == "http" || scheme == "https" else { return .block(.badScheme(scheme)) }
        let host = url.host?.lowercased() ?? ""
        if adMatcher.matches(host: host) { return .block(.adHost(host)) }
        guard isMainFrame else { return .allow }

        switch kind {
        case .linkActivated, .formSubmitted:
            lastIntentAt = now
            return .allow
        case .backForward, .reload, .formResubmitted:
            return .allow
        case .other:
            guard blockRedirects, let current = currentURL, let currentHost = current.host,
                  current.scheme?.lowercased().hasPrefix("http") == true else {
                return .allow
            }
            if RegistrableDomain.sameSite(currentHost, host) { return .allow }
            if let last = lastIntentAt, now.timeIntervalSince(last) <= intentWindow { return .allow }
            return .block(.crossSiteRedirect(host))
        }
    }

    public func decidePopup(url: URL?, kind: NavigationKind) -> PopupDecision {
        guard kind == .linkActivated, let url, let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return .block
        }
        if adMatcher.matches(host: url.host ?? "") { return .block }
        return .openInPlace
    }
}
