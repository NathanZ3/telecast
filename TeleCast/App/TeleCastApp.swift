import SwiftUI
import CastCore

@main
struct TeleCastApp: App {
    @State private var model: AppModel

    init() {
        let logURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TeleCast", isDirectory: true)
            .appendingPathComponent("telecast.log")
        LogStore.shared.configure(fileURL: logURL)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        castLog("app", "Démarrage de TéléCast \(version) · iOS \(UIDevice.current.systemVersion)")
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { url in
                    model.handleOpenURL(url)
                }
        }
    }
}
