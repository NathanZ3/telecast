# TéléCast

Appli iPhone pour envoyer sur la TV les vidéos des sites web : un navigateur intégré repère la vidéo de la page, puis l'appli l'envoie à la TV (DLNA). Elle passe par un relais dans le téléphone quand le site ou la TV l'exigent.

## Contenu du dépôt

| Dossier | Rôle |
|---------|------|
| `TeleCast/` | Appli iOS (SwiftUI) |
| `Packages/CastKit/` | Moteur : `CastCore` (logique testée) et `CastNet` (réseau, relais, DLNA) |
| `WebScripts/` | Script injecté dans les pages pour détecter les vidéos (+ tests) |
| `tools/` | Outils : médias de test, icône, liste anti-pubs, faux téléviseur DLNA |
| `docs/superpowers/` | Conception et plan d'implémentation |

## Compilation

Pas besoin de Mac : à chaque envoi sur GitHub, la CI (`.github/workflows/ios.yml`) lance les tests puis produit `TeleCast.ipa`, téléchargeable dans l'onglet **Actions** du dépôt (artefact `TeleCast-ipa`).

Le guide d'installation sur iPhone sera détaillé ici à la fin du développement.
