import SwiftUI

/// How to add "Caster sur la TV" to Safari's share sheet, and troubleshooting tips.
struct HelpView: View {
    @State private var copied = false

    var body: some View {
        List {
            Section("Créer le raccourci (une seule fois)") {
                step(1, "Ouvre l'app Raccourcis, onglet « Raccourcis », puis touche « + ».")
                step(2, "Ajoute l'action « Encoder en URL ». Touche le mot bleu et choisis « Entrée du raccourci ».")
                step(3, "Ajoute l'action « Texte » et écris : telecast://open?url= puis, juste après, insère la variable « Texte encodé en URL ».")
                step(4, "Ajoute l'action « Ouvrir les URL » (elle ouvre le Texte).")
                step(5, "Touche ⓘ en bas : active « Afficher dans la feuille de partage » et garde seulement URL et Pages web Safari comme types acceptés.")
                step(6, "Nomme le raccourci « Caster sur la TV ».")
                Button(copied ? "Copié !" : "Copier « telecast://open?url= »") {
                    UIPasteboard.general.string = "telecast://open?url="
                    copied = true
                }
            }
            Section("Utilisation") {
                Text("Dans Safari, sur la page de la vidéo : bouton Partager → « Caster sur la TV ». La page s'ouvre dans TéléCast : lance la vidéo puis appuie sur « Caster ».")
                Text("Tu peux aussi copier le lien dans Safari et utiliser « Coller » sur l'accueil de TéléCast.")
            }
            Section("Ça ne marche pas ?") {
                tip("wifi", "Le téléphone et la TV doivent être sur le même réseau Wi-Fi (pas le Wi-Fi invité de la box).")
                tip("lock.shield", "Réglages iOS → TéléCast → active « Réseau local ». Sans ça, la TV reste invisible.")
                tip("tv", "Lance « Tester ma TV » : TéléCast saura quels formats ta TV accepte.")
                tip("doc.text", "Ouvre le Journal (Réglages → Journal) et partage-le : il dit exactement ce qui a bloqué.")
                tip("lock", "Netflix, Disney+ et les autres vidéos protégées (DRM) ne peuvent pas être castées.")
            }
        }
        .navigationTitle("Caster depuis Safari")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(text)
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
    }
}
