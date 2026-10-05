import SwiftUI
import CastCore

/// The journal: what the app did (detection, discovery, cast attempts, relay requests).
struct LogView: View {
    @State private var entries: [LogStore.Entry] = []

    var body: some View {
        List(entries.reversed()) { entry in
            Text(entry.line)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
        .listStyle(.plain)
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("Journal vide", systemImage: "doc.text")
            }
        }
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: LogStore.shared.exportText(), subject: Text("Journal TéléCast")) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Effacer", role: .destructive) {
                    LogStore.shared.clear()
                    entries = []
                }
            }
        }
        .task {
            while !Task.isCancelled {
                entries = LogStore.shared.entries()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}
