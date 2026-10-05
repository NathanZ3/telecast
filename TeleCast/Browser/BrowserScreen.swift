import SwiftUI

/// Main screen: address bar, page (or home), cast button, mini player, toolbar.
struct BrowserScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            AddressBar()
            ZStack(alignment: .bottomTrailing) {
                WebViewContainer(webView: app.browser.webView)
                    .opacity(app.browser.showsHome ? 0 : 1)
                if app.browser.showsHome {
                    HomeView()
                }
                castButton
            }
            .animation(.spring(duration: 0.3), value: app.browser.castableCount)
            if app.cast.isActive || app.cast.snapshot != nil {
                MiniPlayerBar()
            }
            toolbar
        }
    }

    @ViewBuilder
    private var castButton: some View {
        let count = app.browser.castableCount
        if count > 0 && !app.browser.showsHome {
            Button {
                app.sheet = .videos
            } label: {
                Label(count == 1 ? "Caster" : "Caster (\(count))", systemImage: "tv.badge.wifi")
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            }
            .padding(16)
            .transition(.scale.combined(with: .opacity))
        }
    }

    private var toolbar: some View {
        HStack {
            Button {
                app.browser.goBack()
            } label: {
                Image(systemName: "chevron.backward")
            }
            .disabled(!app.browser.canGoBack)
            Spacer()
            Button {
                app.browser.goForward()
            } label: {
                Image(systemName: "chevron.forward")
            }
            .disabled(!app.browser.canGoForward)
            Spacer()
            Button {
                app.browser.goHome()
            } label: {
                Image(systemName: app.browser.showsHome ? "house.fill" : "house")
            }
            Spacer()
            Button {
                app.sheet = .devices
            } label: {
                Image(systemName: app.devices.selected == nil ? "tv" : "tv.fill")
            }
            Spacer()
            Button {
                app.sheet = .settings
            } label: {
                Image(systemName: "gearshape")
            }
        }
        .font(.title3)
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }
}
