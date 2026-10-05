# TéléCast — Document de conception (MVP)

- **Date** : 2026-10-05
- **Statut** : parcours utilisateur et « mode auto » validés par l'utilisateur ; il a délégué les choix techniques (« vas-y fais-moi l'app »).
- **Référence fonctionnelle** : l'appli *Web Video Cast* (navigateur intégré → détection de la vidéo → envoi à la TV), en plus fiable.

## 1. Contexte

L'utilisateur regarde des films et séries dans le navigateur de son iPhone et veut les envoyer sur sa TV. Il utilisait Web Video Cast, avec trois défauts :

1. **la TV ne lit pas** (erreur, écran noir, chargement infini) ;
2. **ça coupe / se déconnecte** (en cours de route, quand le tel est verrouillé) ;
3. **pubs et popups**.

La détection des vidéos marchait correctement.

Matériel : iPhone (iOS récent), PC Windows (pas de Mac), TV sous **Titan OS** (Philips probable, modèle inconnu). Web Video Cast arrivait à caster dessus, donc la TV accepte très probablement le **DLNA**. L'appli doit aussi pouvoir viser Samsung, LG et Android TV / Google TV.

## 2. Objectifs et non-objectifs

### Objectifs du MVP

| # | Objectif |
|---|----------|
| O1 | Navigateur intégré qui détecte les vidéos MP4 et HLS, y compris dans les lecteurs intégrés (iframes d'autres domaines). |
| O2 | Cast vers les TV **DLNA** (Titan OS, Samsung, LG, Sony…). |
| O3 | **Mode auto** : lien direct → relais par le tel → flux reconverti, avec mémorisation de ce qui marche. |
| O4 | Robustesse : appli vivante écran verrouillé, surveillance de la lecture, **reprise automatique**. |
| O5 | Blocage des pubs, popups et redirections forcées. |
| O6 | Télécommande dans l'appli et sur l'écran verrouillé. |
| O7 | Bouton « Tester ma TV ». |
| O8 | Entrée depuis Safari (raccourci iOS du menu Partager) et bouton « Coller le lien ». |
| O9 | Journal exportable (indispensable pour déboguer sans Mac). |
| O10 | Compilation sans Mac (CI GitHub) et installation depuis Windows (Sideloadly). |

### Non-objectifs (MVP)

- Contenus protégés par DRM (Netflix, Disney+, FairPlay/Widevine) : impossible par principe.
- YouTube (l'appli officielle caste déjà mieux).
- Recopie d'écran.
- Transcodage (changement de codec) : le tel ne fait que du ré-empaquetage.
- DASH vers DLNA, sous-titres, file d'attente.
- Chromecast (étape 2), AirPlay (étape 3).
- Publication sur l'App Store.

## 3. Parcours utilisateur (validé)

1. L'utilisateur ouvre l'appli : barre d'adresse, favoris, historique. Ou, depuis Safari : **Partager → « Caster sur la TV »**, ce qui ouvre la page dans l'appli.
2. La page s'affiche dans le navigateur intégré, avec bloqueur de pubs, popups et redirections.
3. Il lance la vidéo sur le site ; l'appli la repère et affiche un bouton **Caster** avec le nombre de vidéos trouvées.
4. Il choisit sa TV (trouvée sur le Wi-Fi ou ajoutée par IP) ; la vidéo part sur la TV.
5. Le tel devient la télécommande (pause, ±10 s / ±30 s, barre de progression, volume, stop), aussi depuis l'écran verrouillé.

## 4. Architecture

```
TeleCast (appli iOS, SwiftUI)
├── Browser       WKWebView + detector.js + règles anti-pubs + garde popups/redirections
├── Cast          CastController : orchestre stratégies, suivi, reprise auto, télécommande
├── Features      Accueil, Vidéos détectées, TV, Télécommande, Réglages, Test TV, Journal, Aide
└── Support       KeepAlive (audio silencieux), NowPlaying (écran verrouillé), stockage JSON

CastKit (paquet Swift local, sans dépendance tierce)
├── CastCore      logique pure et testable : modèles, classification des médias, en-têtes et cookies,
│                 SSDP, description UPnP, SOAP + DIDL-Lite, ProtocolInfo, HLS (lecture, réécriture,
│                 chronologie), HTTP (requêtes, plages), planificateur de stratégies,
│                 machine d'état de session, mémoire des stratégies
└── CastNet       réseau Apple : serveur relais (Network.framework), téléchargement amont (URLSession),
                  balayage SSDP (sockets BSD), client DLNA, déchiffrement AES-128 (CommonCrypto),
                  interfaces réseau (getifaddrs)

WebScripts        detector.js (injecté dans les pages), testé sous Windows avec Playwright WebKit
tools/            médias de test (ffmpeg), liste anti-pubs, faux téléviseur DLNA pour tests sur PC
```

Principe : tout ce qui peut être de la logique pure va dans **CastCore**, avec des tests unitaires. CastNet et l'appli restent de fines couches d'entrées/sorties. Comme il n'y a pas de Mac, chaque compilation passe par la CI : il faut que le maximum de logique soit vérifié par des tests.

## 5. Composants

### 5.1 Navigateur et détection

- `WKWebView` avec stockage persistant (les cookies et connexions aux sites sont conservés), suffixe d'agent utilisateur type Safari, calculé d'après la version d'iOS (`Version/<iOS>.0 Mobile/15E148 Safari/604.1`), lecture *inline* autorisée.
- `detector.js` est injecté **au début du document, dans toutes les frames**, dans le monde JavaScript de la page. Il repère :
  - l'affectation de `src` sur les éléments `video`/`audio` et les balises `<source>` (y compris celles ajoutées plus tard, via `MutationObserver`) ;
  - les événements média (`loadedmetadata`, `play`, `playing`, `durationchange`, en phase de capture) : `currentSrc`, durée, dimensions, lecture en cours ;
  - les requêtes `fetch` et `XMLHttpRequest` (URL et `Content-Type` de la réponse) ;
  - les ressources chargées (`PerformanceObserver` de type `resource`), en filet de sécurité.
- Les URL `blob:` et `data:` sont ignorées. Une lecture via MediaSource (`blob:`) est signalée comme « lecture en cours » pour la frame, ce qui aide à relier le bon manifeste HLS.
- Côté natif, chaque message est complété par la frame d'origine (`WKFrameInfo`), puis :
  - **classé** par CastCore : `hls`, `dash`, `progressive` (mp4/m4v/mov/webm/mkv) ou `ignorer` (segments, pubs, analytics) ;
  - **dédoublonné** (URL normalisée) et **noté** : en lecture +50 ; manifeste maître HLS +20 ; durée longue jusqu'à +30 ; durée < 60 s −40 ; domaine publicitaire = exclu ;
  - **enrichi** : lecture de la playlist HLS avec les bons en-têtes → variantes (résolution, débit), durée totale, type de segments (TS ou fMP4), chiffrement, direct ou VOD.
- `EXT-X-KEY` en `SAMPLE-AES`/`SAMPLE-AES-CTR`, ou `KEYFORMAT` FairPlay/Widevine → « Protégé (DRM) », non castable. DASH → « non supporté par la TV (DLNA) ».
- La liste des vidéos détectées est remise à zéro à chaque nouvelle page principale.

### 5.2 Pubs, popups et redirections

- **Bloqueur** : `WKContentRuleList` compilée depuis `blocklist.json` embarqué. C'est une liste maison de domaines publicitaires et de *popunders*, au format de filtre `^[htpsw]+:\/\/([a-z0-9-]+\.)?domaine\.tld[\/:&?]?`. Activable dans les réglages.
- **Popups** (`window.open`, `target=_blank`) : refusées par `WKUIDelegate`. Exception : un lien tapé par l'utilisateur vers le même site s'ouvre dans l'onglet courant. Un bandeau « Popup bloquée — Ouvrir quand même » s'affiche.
- **Redirections** : une navigation de la frame principale vers un **autre site** (domaine enregistrable différent), de type « autre » (déclenchée par script), en dehors d'une fenêtre d'intention de 3 s, est bloquée. La fenêtre d'intention s'ouvre quand l'utilisateur saisit une URL, touche un lien, un favori ou l'historique. Un bandeau « Redirection bloquée vers X — Autoriser » s'affiche. Les schémas non http(s) et les domaines de la liste sont toujours bloqués.
- Les alertes JavaScript sont fermées automatiquement.

### 5.3 Contexte de requête (ce que le site exige)

Pour chaque vidéo détectée, CastCore calcule le contexte que le navigateur aurait envoyé :

- `Referer` selon la politique `strict-origin-when-cross-origin`, à partir de l'URL de la frame ;
- `Origin` (origine de la frame) pour les requêtes `fetch`/XHR d'une autre origine (manifestes et segments HLS) ;
- `User-Agent` du `WKWebView` ;
- `Cookie` : cookies du `WKHTTPCookieStore` qui correspondent au domaine, au chemin et au mode sécurisé de l'URL demandée.

Le relais et les pré-vérifications utilisent ce contexte.

### 5.4 Découverte des TV

- Avec un compte Apple gratuit, iOS **interdit le multicast** (le droit `com.apple.developer.networking.multicast` est réservé aux comptes payants). Découverte principale : **M-SEARCH SSDP unicast** vers chaque hôte du /24 de l'interface Wi-Fi (`en0`), avec `ST: urn:schemas-upnp-org:device:MediaRenderer:1` puis `upnp:rootdevice`, en 2 passes, puis 3 s d'écoute. Un M-SEARCH multicast est aussi tenté : il échoue sans bruit, et fonctionnera avec un compte payant.
- Pour chaque `LOCATION` : lecture de la description UPnP, recherche (sous-appareils compris) des services `AVTransport` (obligatoire), `RenderingControl` et `ConnectionManager`. Les URL relatives sont résolues depuis `URLBase` ou `LOCATION`.
- Les TV connues (UDN, nom, URL de description, IP) sont **mémorisées** : au lancement, l'appli relit directement leur description, sans balayage. Si cela échoue (IP changée), elle relance un balayage.
- **Ajout manuel par IP** : M-SEARCH unicast vers cette IP, puis essai d'URL de description courantes (`:49152/description.xml` à `:49155/description.xml`, `:9197/dmr`, `:52323/dmr.xml`).
- **Appareils audio seulement** (enceintes, amplis) : si leur liste *ProtocolInfo* ne contient aucun type `video/*` ni HLS, ils sont marqués « audio » et rangés en fin de liste.
- La permission « Réseau local » (`NSLocalNetworkUsageDescription`) est demandée au premier balayage. Si elle est refusée, un écran d'aide l'explique.

### 5.5 Pilotage DLNA

- SOAP 1.1 (`POST`, `text/xml; charset="utf-8"`, en-tête `SOAPAction`), avec le type de service exact de la description (`:1` ou `:2`).
- `AVTransport` : `SetAVTransportURI`, `Play`, `Pause`, `Stop`, `Seek` (`REL_TIME`), `GetTransportInfo`, `GetPositionInfo`, `GetMediaInfo`.
- `RenderingControl` : `GetVolume`/`SetVolume`, `GetMute`/`SetMute` (canal `Master`).
- `ConnectionManager` : `GetProtocolInfo` (liste *Sink* des formats acceptés).
- Métadonnées **DIDL-Lite** systématiques (titre, `object.item.videoItem`, `res` + `protocolInfo`), avec drapeaux DLNA adaptés : `DLNA.ORG_OP=01` si la plage d'octets est possible, `00` pour un flux continu, `DLNA.ORG_FLAGS=01700000000000000000000000000000`.
- Le type MIME est choisi d'après la liste *Sink* : TS → `video/mp2t`, sinon `video/vnd.dlna.mpeg-tts`, sinon `video/mpeg` ; HLS → `application/vnd.apple.mpegurl`, sinon `application/x-mpegURL` ; progressif → type annoncé ou `video/mp4`.
- Les fautes SOAP (`UPnPError` : code et description) sont remontées et journalisées. Délai maximal de 4 s par requête ; jamais deux requêtes de suivi en même temps.

### 5.6 Relais (serveur HTTP local du tel)

- Serveur HTTP/1.1 minimal (`NWListener`, port choisi par le système), `GET` et `HEAD`, une réponse par connexion (`Connection: close`).
- **Routes** :

  | Route | Rôle |
  |-------|------|
  | `/h` | santé |
  | `/t/<fichier>` | médias de test embarqués |
  | `/s/<session>/p` | vidéo progressive (plages d'octets transmises) |
  | `/s/<session>/m.m3u8` | playlist HLS réécrite |
  | `/s/<session>/r/<id>` | ressource relayée (segment, clé, sous-playlist réécrite) |
  | `/s/<session>/live.ts?o=<s>` | flux MPEG-TS continu à partir de `o` secondes |
  | `/s/<session>/live.mp4?o=<s>` | flux fMP4 continu à partir de `o` secondes |

- Identifiants de session aléatoires (UUID) ; une session est supprimée quand le cast s'arrête.
- **Amont** : `URLSession` sans gestion automatique des cookies (le `Cookie` est posé explicitement) ; redirections suivies en gardant les en-têtes. Les playlists, clés et segments sont chargés en entier ; le progressif est transmis en flux avec contre-pression (tampon ≤ 8 Mo, tâche suspendue/reprise).
- **Réponses** : `transferMode.dlna.org: Streaming`, `contentFeatures.dlna.org` si demandé, `Access-Control-Allow-Origin: *` (utile pour Chromecast à l'étape 2), `Content-Type` corrigé si l'amont renvoie `application/octet-stream`.
- **Flux continu** (TS ou fMP4) :
  - segments de la variante choisie, à partir de l'offset, avec 3 segments préchargés ;
  - déchiffrement AES-128 (IV explicite ou dérivé du numéro de séquence) ;
  - pour le fMP4, segment d'initialisation `EXT-X-MAP` envoyé une fois en tête ;
  - playlist rechargée toutes les `TARGETDURATION` en direct ;
  - segment en échec → 3 essais (0,5 / 1 / 2 s) → rechargement de la playlist → segment sauté et journalisé ;
  - cache des 8 derniers segments, partagé entre connexions (les TV en ouvrent souvent plusieurs) ;
  - pas de `Content-Length` (la fin = fermeture) ; les en-têtes `Range` sont ignorés (réponse 200).

### 5.7 Mode auto (choix de la stratégie)

**Stratégies** :

- `direct` : la TV lit l'URL d'origine ;
- `relaisProgressif` ;
- `relaisHLS` (playlist réécrite) ;
- `relaisTS` (flux continu) ;
- `relaisFMP4` (flux continu).

**Pré-vérification** : `GET` avec `Range: bytes=0-1023`, sans aucun en-tête de navigateur (comme le ferait la TV), sur le média, et sur le premier segment pour du HLS. Une réponse 2xx signifie que le lien direct est possible.

**Ordre des essais en DLNA** :

| Contenu | La TV annonce le HLS | La TV ne l'annonce pas |
|---------|----------------------|------------------------|
| Progressif | direct (si pré-vérif OK) → relaisProgressif | idem |
| HLS, segments TS | direct (si pré-vérif OK) → relaisHLS → relaisTS | relaisTS → relaisHLS |
| HLS, segments fMP4 | direct (si pré-vérif OK) → relaisHLS → relaisFMP4 | relaisFMP4 → relaisHLS |
| HLS avec audio séparé (`EXT-X-MEDIA TYPE=AUDIO` avec URI) | direct → relaisHLS (pas de flux continu) | idem |
| DASH | refusé avec un message | refusé avec un message |

- **Mémoire** : la stratégie gagnante est retenue par couple (TV, type de contenu + hôte du média) et essayée en premier la fois suivante. Les résultats du Test TV ajustent aussi l'ordre.
- **Réglage « Mode »** : Auto (par défaut), Toujours relais, Toujours direct.
- **Un essai** = `Stop` (erreurs ignorées) → `SetAVTransportURI` → `Play` → attente de l'état `PLAYING` (12 s en direct, 20 s pour les flux continus). L'essai échoue sur faute SOAP, état `STOPPED` ou `NO_MEDIA_PRESENT` après `Play`, ou délai dépassé. En mode relais, si la TV n'a contacté le relais à aucun moment en 8 s, le message est « la TV n'arrive pas à joindre le tel (isolation Wi-Fi ?) ». La progression s'affiche (« Essai 2/3 : flux continu… »).

### 5.8 Robustesse (« ça coupe »)

- Tant qu'un cast est actif : session audio `.playback` et boucle silencieuse générée en mémoire (`UIBackgroundModes = audio`). L'appli et son relais restent vivants écran verrouillé.
- **Suivi à 1 Hz** : `GetTransportInfo` + `GetPositionInfo` ; la dernière position est mémorisée.
- **Reprise auto** : sur un arrêt non demandé (`STOPPED` ou `NO_MEDIA_PRESENT`) alors que la position est inférieure à la durée moins 30 s (ou durée inconnue et lecture depuis plus de 30 s), relance avec la même stratégie à la dernière position. En flux continu, via un nouvel offset ; sinon `SetAVTransportURI` + `Play` + `Seek`. Au maximum 3 reprises par 10 minutes, puis erreur avec un bouton « Relancer ».
- **Perte de contact** (5 échecs de suivi consécutifs) → état « TV injoignable », nouvel essai toutes les 5 s pendant 2 min, puis abandon.
- **Interruption audio** (appel) : la session est réactivée à la fin.

### 5.9 Télécommande et écran verrouillé

- Titre, état, barre de progression (position et durée), boutons −30/−10/lecture-pause/+10/+30, stop, volume, choix de la qualité (variante HLS, avec relance à la position courante), bouton « Relancer ».
- **Avance et recul** : modes natifs → `Seek REL_TIME` ; flux continus → relance à l'offset. Position affichée = offset + position de la TV ; durée = durée de la playlist.
- **Écran verrouillé et Centre de contrôle** : `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` (lecture, pause, ±10 s, déplacement dans la barre).

### 5.10 Test TV

- Médias de test embarqués, générés avec ffmpeg (≈ 8 s, H.264/AAC 720p, texte incrusté « MP4 OK », « HLS OK »…) : MP4 progressif, HLS à segments TS, flux TS continu, HLS fMP4, flux fMP4 continu.
- Chaque test passe par le relais et attend `PLAYING` (12 s), puis note ✓ ou ✗ et l'erreur éventuelle. Le résultat inclut aussi la liste *ProtocolInfo* de la TV.
- Les résultats sont enregistrés et le mode auto s'en sert.

### 5.11 Entrée depuis Safari

- Schéma d'URL `telecast://open?url=<URL encodée>`.
- Raccourci iOS « Caster sur la TV », affiché dans la feuille de partage pour les URL et pages Safari : *Encoder en URL* → *Texte* `telecast://open?url=…` → *Ouvrir les URL*. La marche à suivre est dans l'écran Aide et le README.
- Bouton « Coller le lien » (`PasteButton`, sans alerte d'accès au presse-papiers).

### 5.12 Journal, réglages et stockage

- **Journal** : 2 000 lignes en mémoire + fichier (1 Mo, rotation), écran « Journal » avec Partager.
- **Réglages** : bloqueur (oui/non), blocage des redirections (oui/non), mode (auto/relais/direct), qualité maximale (auto/1080p/720p/480p), TV par défaut, gestion des TV, aide du raccourci, version.
- **Stockage** : fichiers JSON dans *Application Support* (favoris, 50 dernières pages de l'historique, TV, capacités, mémoire des stratégies, réglages).

## 6. Construction et installation

- **Projet** : XcodeGen (`project.yml`) ; le projet Xcode est généré en CI, il n'est jamais modifié à la main.
- **Langage** : Swift en mode de langage 5, iOS 17 minimum, SwiftUI + Observation, **aucune dépendance tierce**.
- **CI** : GitHub Actions sur macOS (dernier Xcode stable) :
  1. `swift test` sur CastKit ;
  2. `xcodegen generate` ;
  3. `xcodebuild` (`iphoneos`, sans signature) ;
  4. empaquetage `Payload/TeleCast.app` → `TeleCast.ipa`, publié comme artefact téléchargeable.
- **Installation** : Sideloadly sous Windows + identifiant Apple gratuit ; l'appli est valable 7 jours (re-signature automatique possible) ; le **mode développeur** doit être activé sur l'iPhone. Alternative : compte développeur payant (99 €/an), avec validité d'un an et droit multicast à demander.
- **Identifiant** : `com.ntrichet.telecast` (Sideloadly peut le modifier s'il est refusé). Nom affiché : **TéléCast**.

## 7. Tests

- **CastKit** (XCTest, en CI) :
  - SSDP, description UPnP, SOAP/DIDL, ProtocolInfo ;
  - HLS (lecture, réécriture, chronologie, choix de variante) ;
  - en-têtes, Referer et cookies ; HTTP et plages d'octets ;
  - classification et notation ; planificateur de stratégies ;
  - machine d'état de session (horloge simulée : essais, échecs, reprise auto, avance par offset) ;
  - tests d'intégration CastNet sur macOS : relais local ↔ serveur amont de test (progressif + plages, playlist réécrite, flux TS continu, AES-128).
- **detector.js** : Playwright WebKit sous Windows, sur des pages de test locales (`<video src>`, `<source>`, iframe d'une autre origine, `fetch`/XHR de `.m3u8`, réponses avec `Content-Type` HLS sans extension).
- **Faux téléviseur DLNA** (Python, sur le PC) : répond au M-SEARCH unicast, journalise les commandes SOAP, peut lire le flux reçu avec ffplay. Il permet de tester l'appli sans la vraie TV.
- **Recette** sur iPhone + TV, avec une liste de contrôle : découverte, Test TV, cast MP4, cast HLS, 10 min tel verrouillé, avance/recul, reprise auto, popups et redirections bloquées.

## 8. Étapes

1. **Étape 1 (ce document)** : tout ce qui précède, en DLNA.
2. **Étape 2** : Chromecast (Android TV / Google TV) — protocole Cast v2 (TLS, port 8009), *Default Media Receiver*, relais avec CORS, découverte Bonjour `_googlecast._tcp`.
3. **Étape 3** (si besoin) : AirPlay, sous-titres, renouvellement automatique des liens expirés, file d'attente.

## 9. Risques et parades

| Risque | Parade |
|--------|--------|
| La TV ne répond pas au M-SEARCH unicast | Ajout par IP + URL de description courantes ; sinon compte payant (multicast). |
| La TV Titan OS est exigeante sur les formats | Test TV + cinq modes ; message clair si rien ne passe (plan B : clé Chromecast, étape 2). |
| Pas de Mac : compilation uniquement en CI | Logique isolée et testée dans CastKit ; journal exportable depuis l'appli. |
| Liens vidéo qui expirent en cours de film | Reprise auto limitée ; renouvellement automatique prévu à l'étape 3. |
| Quota de minutes macOS de GitHub en dépôt privé | Dépôt public possible (aucun secret dans le code). |
| Codec non lisible par la TV (HEVC…) | Impossible sans transcodage : message explicite. |
