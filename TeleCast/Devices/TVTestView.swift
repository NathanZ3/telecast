import SwiftUI
import CastCore

/// "Tester ma TV": checks which formats/modes the TV plays.
struct TVTestView: View {
    @Environment(AppModel.self) private var app
    let tvID: String

    private var tv: SavedTV? {
        app.devices.tvs.first { $0.id == tvID }
    }

    var body: some View {
        List {
            Section {
                Text("La TV va afficher quelques secondes de vidéo de test dans plusieurs formats. Garde-la allumée et attends la fin (environ 1 minute).")
                    .font(.subheadline)
            }
            Section("Résultats") {
                ForEach(TVTestCase.allCases, id: \.self) { testCase in
                    HStack {
                        Text(testCase.label)
                        Spacer()
                        status(testCase)
                    }
                }
            }
            if let sink = tv?.tests?.sink, !sink.isEmpty {
                Section("Formats annoncés par la TV") {
                    Text(sink.joined(separator: ", "))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            Section {
                Button {
                    Task { await app.devices.runTest(on: tvID) }
                } label: {
                    Label(app.devices.isTesting ? "Test en cours…" : "Lancer le test", systemImage: "play.circle")
                }
                .disabled(app.devices.isTesting || app.cast.isActive || tv == nil)
            } footer: {
                if app.cast.isActive {
                    Text("Arrête d'abord le cast en cours.")
                }
            }
        }
        .navigationTitle(tv?.name ?? "Tester ma TV")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func status(_ testCase: TVTestCase) -> some View {
        if app.devices.currentTest == testCase {
            ProgressView()
        } else if let passed = app.devices.testResults[testCase.rawValue] ?? tv?.tests?.result(testCase) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(passed ? Color.green : Color.red)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }
}
