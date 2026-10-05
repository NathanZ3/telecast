import SwiftUI

struct DevicePickerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var showAddByIP = false

    var body: some View {
        NavigationStack {
            List {
                tvSection
                actionsSection
                if app.devices.lastScanFoundNothing && !app.devices.isScanning {
                    helpSection
                }
            }
            .overlay {
                if app.devices.tvs.isEmpty && app.devices.isScanning {
                    ProgressView("Recherche des TV…")
                }
            }
            .navigationTitle("Ma TV")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddByIP) {
                AddByIPView()
            }
            .task {
                if app.devices.tvs.isEmpty {
                    await app.devices.refresh()
                }
            }
        }
    }

    @ViewBuilder
    private var tvSection: some View {
        if !app.devices.tvs.isEmpty {
            Section("Téléviseurs") {
                ForEach(app.devices.tvs) { tv in
                    Button {
                        app.devices.select(tv.id)
                        dismiss()
                    } label: {
                        tvRow(tv)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            app.devices.remove(tv.id)
                        } label: {
                            Label("Oublier", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func tvRow(_ tv: SavedTV) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tv.isAudioOnly ? "hifispeaker" : "tv")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(tv.name)
                    .foregroundStyle(.primary)
                Text(tv.isAudioOnly ? "Audio seulement · \(tv.subtitle)" : tv.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if tv.id == app.devices.selectedID {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task { await app.devices.refresh() }
            } label: {
                Label(app.devices.isScanning ? "Recherche en cours…" : "Rechercher les TV", systemImage: "arrow.clockwise")
            }
            .disabled(app.devices.isScanning)
            Button {
                showAddByIP = true
            } label: {
                Label("Ajouter par adresse IP", systemImage: "plus")
            }
            if let tv = app.devices.selected {
                NavigationLink {
                    TVTestView(tvID: tv.id)
                } label: {
                    Label("Tester ma TV", systemImage: "checklist")
                }
            }
        } footer: {
            Text("La TV et le téléphone doivent être sur le même Wi-Fi. Au premier lancement, autorise l'accès au réseau local.")
        }
    }

    private var helpSection: some View {
        Section("Aucune TV trouvée ?") {
            Label("Allume la TV (pas en veille) et vérifie qu'elle est sur le même Wi-Fi.", systemImage: "power")
            Label("Réglages iOS → TéléCast → active « Réseau local ».", systemImage: "lock.shield")
            Label("Sinon, ajoute-la avec son adresse IP (dans les réglages réseau de la TV).", systemImage: "number")
        }
        .font(.subheadline)
    }
}
