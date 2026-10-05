import SwiftUI

/// Start page: paste a link, favourites, history.
struct HomeView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            headerSection
            if app.browser.currentURL != nil {
                Section {
                    Button {
                        app.browser.showPage()
                    } label: {
                        Label("Revenir à la page : \(app.browser.title.isEmpty ? (app.browser.currentURL?.host ?? "") : app.browser.title)",
                              systemImage: "arrow.uturn.backward")
                            .lineLimit(1)
                    }
                }
            }
            if !app.library.favorites.isEmpty {
                Section("Favoris") {
                    ForEach(app.library.favorites) { entry in
                        row(entry, symbol: "star.fill")
                    }
                    .onDelete { app.library.removeFavorites(at: $0) }
                }
            }
            if !app.library.history.isEmpty {
                Section("Récents") {
                    ForEach(app.library.history.prefix(15)) { entry in
                        row(entry, symbol: "clock")
                    }
                    Button("Effacer l'historique", role: .destructive) {
                        app.library.clearHistory()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("TéléCast")
                    .font(.largeTitle.bold())
                Text("Ouvre un site, lance la vidéo, puis appuie sur « Caster ».")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    PasteButton(payloadType: URL.self) { urls in
                        guard let url = urls.first else { return }
                        Task { @MainActor in
                            app.browser.load(url: url, userInitiated: true)
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.capsule)
                    Button {
                        app.sheet = .devices
                    } label: {
                        Label(app.devices.selected?.name ?? "Choisir ma TV", systemImage: "tv")
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func row(_ entry: LibraryEntry, symbol: String) -> some View {
        Button {
            app.browser.load(url: entry.url, userInitiated: true)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(entry.url.host ?? entry.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
