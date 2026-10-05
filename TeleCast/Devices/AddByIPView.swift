import SwiftUI
import CastCore

struct AddByIPView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var working = false
    @State private var failed = false

    private var isValid: Bool {
        SubnetMath.parse(address.trimmingCharacters(in: .whitespaces)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("192.168.1.50", text: $address)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Adresse IP de la TV")
                } footer: {
                    Text("Elle se trouve dans les réglages réseau de la TV (Réglages → Réseau → État ou Informations du réseau).")
                }
                if failed {
                    Section {
                        Label("Aucune TV compatible trouvée à cette adresse.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Ajouter une TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView()
                    } else {
                        Button("Ajouter") { add() }
                            .disabled(!isValid)
                    }
                }
            }
        }
    }

    private func add() {
        working = true
        failed = false
        Task {
            let ok = await app.devices.add(ip: address)
            working = false
            if ok {
                dismiss()
            } else {
                failed = true
            }
        }
    }
}
