import SwiftUI

struct AddressBar: View {
    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var browser = app.browser
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: browser.currentURL?.scheme == "https" ? "lock.fill" : "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Rechercher ou saisir une adresse", text: $browser.addressText)
                    .focused($focused)
                    .keyboardType(.webSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit {
                        browser.load(browser.addressText)
                    }
                if focused && !browser.addressText.isEmpty {
                    Button {
                        browser.addressText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(.secondarySystemBackground), in: Capsule())

            if focused {
                Button("Annuler") {
                    focused = false
                }
            } else if browser.currentURL != nil && !browser.showsHome {
                Button {
                    if browser.isLoading { browser.stopLoading() } else { browser.reload() }
                } label: {
                    Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
                }
                Button {
                    browser.toggleFavorite()
                } label: {
                    Image(systemName: app.library.isFavorite(browser.currentURL) ? "star.fill" : "star")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            if browser.isLoading {
                ProgressView(value: browser.progress)
                    .progressViewStyle(.linear)
                    .frame(height: 2)
            }
        }
        .onChange(of: focused) { _, isFocused in
            browser.isEditingAddress = isFocused
            if isFocused {
                browser.addressText = browser.currentURL?.absoluteString ?? ""
            } else {
                browser.syncState()
            }
        }
    }
}
