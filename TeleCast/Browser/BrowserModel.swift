import SwiftUI
import WebKit
import Observation
import CastCore
import CastNet

/// The in-app browser: navigation state, detected videos, blocked popups/redirects.
@MainActor
@Observable
final class BrowserModel {
    @ObservationIgnored weak var app: AppModel?
    @ObservationIgnored let settings: SettingsModel
    @ObservationIgnored let library: LibraryStore
    @ObservationIgnored let fetcher: UpstreamFetcher
    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private let coordinator: WebViewCoordinator
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var enriching = Set<String>()
    @ObservationIgnored private var popupToastShown = false
    @ObservationIgnored private var installedAdBlock: Bool?
    @ObservationIgnored private(set) var userAgent: String?
    @ObservationIgnored private(set) var cookies: [CookieRecord] = []

    var currentURL: URL?
    var title = ""
    var isLoading = false
    var progress: Double = 0
    var canGoBack = false
    var canGoForward = false
    var addressText = ""
    var isEditingAddress = false
    var showsHome = true
    private(set) var store = CandidateStore()

    var candidates: [MediaCandidate] { store.candidates }
    var castableCount: Int { store.candidates.filter(\.isCastable).count }

    init(settings: SettingsModel, library: LibraryStore, fetcher: UpstreamFetcher) {
        self.settings = settings
        self.library = library
        self.fetcher = fetcher
        let coordinator = WebViewCoordinator(adMatcher: Self.loadAdMatcher(), blockRedirects: settings.value.blockRedirects)
        self.coordinator = coordinator
        self.webView = WebViewFactory.make(coordinator: coordinator)
        coordinator.model = self
        observeWebView()
        installContentBlocker(reload: false)
    }

    static func loadAdMatcher() -> AdHostMatcher {
        guard let url = Bundle.main.url(forResource: "adhosts", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return .builtIn
        }
        return AdHostMatcher(text: text)
    }

    // MARK: Navigation

    func load(_ input: String) {
        guard let url = URLInput.url(from: input) else { return }
        load(url: url, userInitiated: true)
    }

    func load(url: URL, userInitiated: Bool) {
        if userInitiated { coordinator.noteUserIntent() }
        isEditingAddress = false
        showsHome = false
        addressText = url.host ?? url.absoluteString
        webView.load(URLRequest(url: url))
    }

    func goBack() {
        coordinator.noteUserIntent()
        showsHome = false
        webView.goBack()
    }

    func goForward() {
        coordinator.noteUserIntent()
        showsHome = false
        webView.goForward()
    }

    func reload() {
        coordinator.noteUserIntent()
        webView.reload()
    }

    func stopLoading() {
        webView.stopLoading()
    }

    func goHome() {
        showsHome = true
    }

    func showPage() {
        if currentURL != nil { showsHome = false }
    }

    func toggleFavorite() {
        guard let url = currentURL else { return }
        library.toggleFavorite(url: url, title: title)
    }

    // MARK: Web view state

    private func observeWebView() {
        observations = [
            webView.observe(\.url) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncState() } },
            webView.observe(\.title) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncState() } },
            webView.observe(\.isLoading) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncState() } },
            webView.observe(\.estimatedProgress) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncState() } },
            webView.observe(\.canGoBack) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncState() } },
            webView.observe(\.canGoForward) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncState() } },
        ]
    }

    func syncState() {
        currentURL = webView.url
        title = webView.title ?? ""
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        if !isEditingAddress {
            addressText = currentURL?.host ?? currentURL?.absoluteString ?? ""
        }
    }

    func pageDidCommit() {
        store.reset()
        enriching.removeAll()
        popupToastShown = false
        showsHome = false
        syncState()
        Task { await refreshCookies() }
    }

    func pageDidFinish() {
        syncState()
        if let url = webView.url, let scheme = url.scheme, scheme.hasPrefix("http") {
            library.addHistory(url: url, title: webView.title ?? "")
        }
        Task { await refreshCookies() }
    }

    func pageDidFail(_ error: Error) {
        syncState()
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain" && (nsError.code == 102 || nsError.code == 101) { return }
        castLog("browser", "Chargement impossible : \(nsError.localizedDescription)")
        app?.showToast(Toast(text: "Page inaccessible : \(nsError.localizedDescription)"))
    }

    func refreshCookies() async {
        let records = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        cookies = records.map {
            CookieRecord(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path, isSecure: $0.isSecure,
                         expiresAt: $0.expiresDate)
        }
    }

    /// Request context recomputed with the latest cookies, just before casting.
    func freshContext(for candidate: MediaCandidate) async -> RequestContext {
        await refreshCookies()
        let via = candidate.via.contains("xhr") || candidate.via.contains("fetch") ? "xhr" : candidate.via.first
        return ContextBuilder.make(requestURL: candidate.url, frameURL: candidate.frameURL, via: via,
                                   userAgent: userAgent ?? candidate.context.userAgent, cookies: cookies)
    }

    // MARK: Detection

    func handleDetector(_ message: DetectorMessage, frame: WKFrameInfo) {
        if message.kind == .hello {
            if frame.isMainFrame, let agent = message.userAgent { userAgent = agent }
            return
        }
        let frameURL = frame.request.url ?? message.frameURL.flatMap { URL(string: $0) }
        let page = PageContext(pageURL: currentURL, pageTitle: title.isEmpty ? nil : title, userAgent: userAgent,
                               cookies: cookies)
        if store.ingest(message, frameURL: frameURL, page: page) {
            enrichPendingCandidates()
        }
    }

    private func enrichPendingCandidates() {
        let cap = settings.value.quality
        let fetcher = self.fetcher
        for candidate in store.candidates where candidate.kind == .hls && candidate.hls == nil && !enriching.contains(candidate.id) {
            enriching.insert(candidate.id)
            Task { [weak self] in
                let info = await CandidateEnricher.inspect(candidate, cap: cap, fetcher: fetcher)
                guard let self, let info else { return }
                self.store.setHLSInfo(info, for: candidate.id)
            }
        }
    }

    // MARK: Guard callbacks

    func didBlock(_ reason: BlockReason, url: URL) {
        switch reason {
        case .adHost(let host):
            castLog("guard", "Pub bloquée : \(host)")
        case .badScheme(let scheme):
            castLog("guard", "Lien « \(scheme): » bloqué")
        case .crossSiteRedirect(let host):
            castLog("guard", "Redirection bloquée vers \(host)")
            app?.showToast(Toast(text: "Redirection bloquée vers \(host)", actionTitle: "Autoriser") { [weak self] in
                self?.load(url: url, userInitiated: true)
            })
        }
    }

    func didBlockPopup(_ url: URL?) {
        castLog("guard", "Popup bloquée \(url?.host ?? "")")
        guard !popupToastShown, let url, url.scheme?.hasPrefix("http") == true else { return }
        popupToastShown = true
        app?.showToast(Toast(text: "Popup bloquée", actionTitle: "Ouvrir") { [weak self] in
            self?.load(url: url, userInitiated: true)
        })
    }

    // MARK: Settings

    func applySettings() {
        coordinator.guardrail.blockRedirects = settings.value.blockRedirects
        installContentBlocker(reload: true)
    }

    private func installContentBlocker(reload: Bool) {
        let enabled = settings.value.adBlock
        guard installedAdBlock != enabled else { return }
        installedAdBlock = enabled
        let controller = webView.configuration.userContentController
        Task { [weak self] in
            await ContentBlocker.install(on: controller, enabled: enabled)
            if reload, let self, self.currentURL != nil {
                self.webView.reload()
            }
        }
    }
}
