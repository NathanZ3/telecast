import SwiftUI
import Observation
import CastCore
import CastNet

enum AppSheet: String, Identifiable {
    case videos
    case devices
    case remote
    case settings

    var id: String { rawValue }
}

/// Root of the app state: owns the browser, the TVs, the cast engine and the UI routing.
@MainActor
@Observable
final class AppModel {
    let settings: SettingsModel
    let library: LibraryStore
    let browser: BrowserModel
    let devices: DeviceModel
    let cast: CastModel
    @ObservationIgnored let relay: RelayServer
    @ObservationIgnored let fetcher: UpstreamFetcher

    var sheet: AppSheet?
    var toast: Toast?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init() {
        let settings = SettingsModel()
        let library = LibraryStore()
        let fetcher = UpstreamFetcher()
        let relay = RelayServer(testFiles: Bundle.main.url(forResource: "TestMedia", withExtension: nil), fetcher: fetcher)
        let devices = DeviceModel(relay: relay)
        self.settings = settings
        self.library = library
        self.fetcher = fetcher
        self.relay = relay
        self.devices = devices
        self.browser = BrowserModel(settings: settings, library: library, fetcher: fetcher)
        self.cast = CastModel(relay: relay, fetcher: fetcher, settings: settings, devices: devices)
        browser.app = self
        devices.app = self
        cast.app = self
        Task { [relay] in
            do {
                try await relay.start()
            } catch {
                castLog("app", "Relais non démarré : \(error.localizedDescription)")
            }
        }
        Task { [devices] in
            await devices.restore()
        }
    }

    /// `telecast://open?url=<page>` sent by the "Caster sur la TV" shortcut from Safari.
    func handleOpenURL(_ url: URL) {
        guard url.scheme?.lowercased() == "telecast" else { return }
        guard let target = Self.sharedURL(from: url) else {
            showToast(Toast(text: "Lien reçu illisible."))
            return
        }
        sheet = nil
        browser.load(url: target, userInitiated: true)
        castLog("app", "Page reçue depuis Safari : \(target.host ?? "?")")
    }

    /// Accepts both an encoded (`url=https%3A%2F%2F…`) and a raw (`url=https://…?a=1&b=2`) page URL.
    static func sharedURL(from url: URL) -> URL? {
        let absolute = url.absoluteString
        guard let marker = absolute.range(of: "url=") ?? absolute.range(of: "u=") else { return nil }
        var value = String(absolute[marker.upperBound...])
        let lower = value.lowercased()
        if lower.hasPrefix("http%3a") || lower.contains("%2f") || lower.contains("%3a") {
            value = value.removingPercentEncoding ?? value
        }
        return URLInput.url(from: value)
    }

    func showToast(_ toast: Toast) {
        self.toast = toast
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if !Task.isCancelled {
                self?.toast = nil
            }
        }
    }

    func applySettings() {
        browser.applySettings()
    }
}
