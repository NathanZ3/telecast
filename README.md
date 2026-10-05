# TéléCast

Appli iPhone pour envoyer sur la TV les vidéos des sites web. Un navigateur intégré repère la vidéo de la page, puis l'appli l'envoie à la TV (DLNA : Titan OS/Philips, Samsung, LG, Sony…). Le téléphone sert de télécommande, y compris depuis l'écran verrouillé.

Ce qui la rend plus fiable que les applis du même genre :

- **Mode auto** : elle essaie d'abord le lien direct. Si la TV ne lit pas, elle passe par un relais dans le téléphone, qui se présente au site comme un navigateur. Si le format HLS pose problème, elle le convertit en flux continu. Elle retient ce qui marche pour chaque TV et chaque site.
- **Reprise automatique** : si la lecture s'arrête en plein film, l'appli relance la vidéo là où elle en était. L'appli reste active écran verrouillé.
- **Bloqueur intégré** : pubs, popups et redirections forcées.
- **« Tester ma TV »** : vérifie en une minute quels formats ta TV accepte.

Ce qui reste impossible : les vidéos protégées par DRM (Netflix, Disney+, Prime Video…). YouTube se caste mieux avec son appli officielle.

---

## Installer l'appli sur l'iPhone (depuis un PC Windows)

Apple n'autorise l'installation d'applis hors App Store qu'avec une signature liée à ton identifiant Apple. L'outil gratuit **Sideloadly** fait ça depuis Windows.

### Une seule fois

1. **iTunes et iCloud, versions du site d'Apple** : Sideloadly ne marche pas avec les versions du Microsoft Store. Si tu les as, désinstalle-les, puis installe iTunes depuis apple.com/fr/itunes et iCloud pour Windows depuis le site d'Apple.
2. **Sideloadly** : télécharge-le sur le site officiel, sideloadly.io.
3. **Mode développeur sur l'iPhone** : Réglages → Confidentialité et sécurité → Mode développeur → activer. L'iPhone redémarre ; confirme l'activation.

### Installer (ou mettre à jour) TéléCast

1. Récupère le fichier `TeleCast.ipa` : il est dans le dossier `dist/` du projet. Sinon, prends le dernier artefact **TeleCast-ipa** dans l'onglet *Actions* du dépôt GitHub.
2. Branche l'iPhone au PC en USB, déverrouille-le et accepte « Faire confiance à cet ordinateur ».
3. Ouvre Sideloadly :
   - glisse `TeleCast.ipa` dans la fenêtre ;
   - saisis ton identifiant Apple (adresse e-mail) ;
   - clique sur **Start**.
4. Sideloadly te demande ton mot de passe Apple, puis le code de double authentification. Tu les saisis toi-même : ils ne servent qu'à signer l'appli auprès d'Apple.
5. Sur l'iPhone : Réglages → Général → VPN et gestion de l'appareil → ton identifiant Apple → **Faire confiance**.
6. Lance TéléCast. Accepte l'accès au **réseau local** : sans ça, l'appli ne trouve pas la TV.

### Tous les 7 jours

Avec un identifiant Apple gratuit, l'appli expire au bout de 7 jours. Il suffit de refaire l'étape « Installer » : tes réglages et tes TV sont conservés. Sideloadly peut aussi rafraîchir l'appli automatiquement quand le PC et l'iPhone sont sur le même Wi-Fi (option *Auto refresh*).

> Avec un compte développeur Apple payant (99 €/an), l'appli reste valable un an.

---

## Caster depuis Safari (raccourci « Caster sur la TV »)

À créer une seule fois dans l'app **Raccourcis**, onglet « Raccourcis », bouton « + » :

1. Action **Encoder en URL** : touche le mot bleu et choisis « Entrée du raccourci ».
2. Action **Texte** : écris `telecast://open?url=`, puis insère juste après la variable « Texte encodé en URL ».
3. Action **Ouvrir les URL** : elle ouvre le Texte.
4. Touche ⓘ, active « Afficher dans la feuille de partage » et garde seulement *URL* et *Pages web Safari*.
5. Nomme le raccourci **Caster sur la TV**.

Ensuite, dans Safari : **Partager → Caster sur la TV**. La page s'ouvre dans TéléCast : lance la vidéo puis appuie sur **Caster**. La même marche à suivre est dans l'appli : Réglages → Caster depuis Safari.

---

## Utilisation

1. **Ma TV** (icône TV en bas) : l'appli cherche les TV sur le Wi-Fi. Si rien n'apparaît, utilise **Ajouter par adresse IP** ; l'adresse se trouve dans les réglages réseau de la TV.
2. **Tester ma TV** (conseillé la première fois) : la TV affiche de courts clips de test, et TéléCast note ce qui marche.
3. Ouvre un site, lance la vidéo : le bouton **Caster** apparaît. Choisis la vidéo (celle en cours de lecture est en tête).
4. La **télécommande** s'ouvre : pause, ±10 s / ±30 s, barre de progression, volume, qualité, « Relancer ». Les mêmes commandes sont sur l'écran verrouillé.

### En cas de problème

| Symptôme | Solution |
|----------|----------|
| Aucune TV trouvée | TV allumée (pas en veille) et sur le même Wi-Fi que le tel ; Réglages iOS → TéléCast → Réseau local activé ; sinon ajout par IP. |
| « La TV n'arrive pas à joindre le téléphone » | La box isole les appareils Wi-Fi (isolation, Wi-Fi invité) : désactive-la ou utilise le Wi-Fi principal. |
| La TV refuse la vidéo | Lance « Tester ma TV ». Dans Réglages, essaie le mode « Toujours par le téléphone » ou une qualité plus basse. |
| La lecture s'arrête souvent | L'appli relance seule jusqu'à 3 fois en 10 min. Au-delà, appuie sur « Relancer ». |
| Autre chose | Réglages → Journal → bouton Partager : le journal dit exactement ce qui a bloqué. |

---

## Développement

| Dossier | Rôle |
|---------|------|
| `TeleCast/` | Appli iOS (SwiftUI) : navigateur, TV, télécommande, réglages |
| `Packages/CastKit/` | Moteur : `CastCore` (logique pure, testée) et `CastNet` (relais HTTP, téléchargements, DLNA, découverte) |
| `WebScripts/` | `detector.js`, injecté dans chaque page pour repérer les vidéos, avec ses tests WebKit |
| `tools/` | Icône, médias de test, liste anti-pubs, **faux téléviseur DLNA** |
| `docs/superpowers/` | Conception et plan d'implémentation |

- **Compilation** : sans Mac. À chaque envoi sur GitHub, `.github/workflows/ios.yml` lance les tests (Swift sur macOS, détecteur sur Linux), génère le projet Xcode avec XcodeGen et produit `TeleCast.ipa`, non signé.
- **Tests du détecteur** en local : `cd WebScripts && npm install && npx playwright install webkit && npm test`.
- **Faux téléviseur** (tester l'appli sans la TV) : `python tools/fake-renderer/fake_renderer.py --play`. Il apparaît dans TéléCast comme une TV, affiche les commandes reçues et lit le flux avec ffplay. Options utiles : `--no-hls` (TV sans HLS) et `--stop-after 30` (coupure simulée pour tester la reprise).
- **Régénérer les ressources** : `python tools/make-icon.py`, `powershell -File tools/make-test-media.ps1`, `node tools/blocklist/build.mjs`.
