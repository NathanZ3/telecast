import SwiftUI
import CastCore

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                browserSection
                castSection
                tvSection
                helpSection
                Section {
                    LabeledContent("Version", value: version)
                }
            }
            .navigationTitle("Réglages")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    private var browserSection: some View {
        Section {
            Toggle("Bloquer les pubs", isOn: binding(\.adBlock))
            Toggle("Bloquer les redirections forcées", isOn: binding(\.blockRedirects))
        } header: {
            Text("Navigateur")
        } footer: {
            Text("Les popups sont toujours bloquées. Une redirection bloquée peut être autorisée depuis le bandeau qui s'affiche.")
        }
    }

    private var castSection: some View {
        Section {
            Picker("Mode de cast", selection: binding(\.mode)) {
                ForEach(CastModePreference.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            Picker("Qualité maximale", selection: binding(\.quality)) {
                ForEach(QualityCap.allCases, id: \.self) { cap in
                    Text(cap.label).tag(cap)
                }
            }
        } header: {
            Text("Cast")
        } footer: {
            Text("En automatique, TéléCast essaie le lien direct, puis passe par le téléphone si la TV n'arrive pas à lire. Il retient ce qui marche pour chaque TV et chaque site.")
        }
    }

    private var tvSection: some View {
        Section("TV") {
            Button {
                app.sheet = .devices
            } label: {
                LabeledContent("Ma TV", value: app.devices.selected?.name ?? "Aucune")
            }
            if let tv = app.devices.selected {
                NavigationLink("Tester « \(tv.name) »") {
                    TVTestView(tvID: tv.id)
                }
            }
        }
    }

    private var helpSection: some View {
        Section("Aide") {
            NavigationLink("Caster depuis Safari") { HelpView() }
            NavigationLink("Journal") { LogView() }
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { app.settings.value[keyPath: keyPath] },
            set: { newValue in
                app.settings.update { $0[keyPath: keyPath] = newValue }
                app.applySettings()
            })
    }
}
