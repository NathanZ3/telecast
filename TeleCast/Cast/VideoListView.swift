import SwiftUI
import CastCore

/// Videos found on the page; tapping one casts it to the selected TV.
struct VideoListView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                tvSection
                Section {
                    ForEach(app.browser.candidates) { candidate in
                        Button {
                            Task { await app.cast.cast(candidate) }
                        } label: {
                            VideoRow(candidate: candidate)
                        }
                        .disabled(!candidate.isCastable)
                    }
                } header: {
                    Text("Vidéos trouvées sur la page")
                } footer: {
                    Text("La vidéo en cours de lecture est en tête de liste. Si la bonne n'apparaît pas, lance-la sur le site puis reviens ici.")
                }
            }
            .navigationTitle("Caster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var tvSection: some View {
        Section {
            if let tv = app.devices.selected {
                HStack {
                    Label(tv.name, systemImage: "tv")
                    Spacer()
                    Button("Changer") { app.sheet = .devices }
                }
            } else {
                Button {
                    app.sheet = .devices
                } label: {
                    Label("Choisir ma TV", systemImage: "tv")
                }
            }
        }
    }
}

struct VideoRow: View {
    let candidate: MediaCandidate

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: candidate.isPlaying ? "play.circle.fill" : "film")
                .font(.title2)
                .foregroundStyle(candidate.isCastable ? Color.accentColor : Color.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.displayTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(Formatters.candidateSubtitle(candidate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
