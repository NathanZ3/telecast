import Foundation
import Observation
import CastCore

struct AppSettings: Codable, Equatable {
    var adBlock = true
    var blockRedirects = true
    var mode: CastModePreference = .auto
    var quality: QualityCap = .auto
}

@MainActor
@Observable
final class SettingsModel {
    private(set) var value = AppSettings()
    @ObservationIgnored private let store = JSONFileStore(
        url: JSONFileStore<AppSettings>.applicationSupportURL(named: "settings"), defaultValue: AppSettings())

    init() {
        value = store.load()
    }

    func update(_ change: (inout AppSettings) -> Void) {
        var copy = value
        change(&copy)
        guard copy != value else { return }
        value = copy
        store.save(copy)
    }
}
