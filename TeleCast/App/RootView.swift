import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var routing = app
        BrowserScreen()
            .sheet(item: $routing.sheet) { sheet in
                switch sheet {
                case .videos:
                    VideoListView()
                case .devices:
                    DevicePickerView()
                case .remote:
                    RemoteView()
                case .settings:
                    SettingsView()
                }
            }
            .overlay(alignment: .top) {
                if let toast = app.toast {
                    ToastView(toast: toast) {
                        app.toast = nil
                    }
                    .padding(.top, 52)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: app.toast)
    }
}
