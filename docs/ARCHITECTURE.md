# Architecture et protocole

← [Retour au README](../README.md)

## Vue d'ensemble

```
┌─────────────── Mac ───────────────┐                ┌──────────── TV VIDAA ────────────┐
│ SwiftUI (Views, AppModel)         │                │                                  │
│   │                               │  MQTT/TLS      │  service UI / plateforme         │
│   ├─ TVBridge ────────────────────┼── :36669 ─────►│   launchapp, auth, token         │
│   │                               │                │                                  │
│   ├─ CommandQueue                 │  HTTP          │  navigateur                      │
│   └─ HTTPServer :8090 ◄───────────┼────────────────┤   agent.html                     │
│        /agent /pending /result    │                │     HiUtils_createRequest        │
│                                   │                │       └─ websdk/Appinfo.json     │
│ TVScanner (SSDP + /24, :38400)    │                │                                  │
└───────────────────────────────────┘                └──────────────────────────────────┘
```

| Fichier | Rôle |
|---|---|
| `Sources/Core.swift` | `TVBridge` (MQTT), `CommandQueue`, serveur HTTP, chemins |
| `Sources/TV.swift` | `TVDevice`, `TVStore` (`tvs.json`), `TVScanner` (découverte) |
| `Sources/Model.swift`, `ModelTV.swift` | État de l'app, appairage, reconnexion |
| `Sources/Vidaa/` | Encodage MQTT 3.1.1, identifiants, identité client TLS |
| `Sources/*Views.swift`, `Theme.swift` | Interface |
| `web/agent.html` | Page exécutée par le TV (embarquée dans le bundle) |

## 1. Découverte

- **SSDP** (`M-SEARCH` multicast) puis **balayage du /24** du Mac.
- Chaque candidat est confirmé par `http://<ip>:38400/MediaServer/rendererdevicedesc.xml`.
- Le TV est identifié par son **adresse MAC** : après deux échecs de connexion, l'app relance un
  scan et met à jour l'IP.

## 2. Liaison MQTT

Connexion TLS sur le port **36669** avec un certificat client, identifiant client propre à
chaque Mac (tiré au premier lancement).

| Sens | Topic | Usage |
|---|---|---|
| → TV | `/remoteapp/tv/ui_service/<id>/actions/vidaa_app_connect` | Demande d'appairage (affiche le code) |
| → TV | `/remoteapp/tv/ui_service/<id>/actions/authenticationcode` | Envoi du code `{"authNum":1234}` |
| → TV | `/remoteapp/tv/ui_service/<id>/actions/authenticationcodeclose` | Ferme la fenêtre de code |
| → TV | `/remoteapp/tv/platform_service/<id>/data/gettoken` | Jeton / renouvellement via refresh token |
| → TV | `/remoteapp/tv/ui_service/<id>/actions/launchapp` | Ouvre `http://<mac>:8090/agent?t=…` |
| ← TV | `/remoteapp/mobile/<id>/authentication`, `…/authenticationcode`, `…/tokenissuance` | Réponses |

## 3. L'agent

`agent.html` est servie par le Mac et ouverte dans le navigateur du TV. Elle :

1. interroge `GET /pending?t=<jeton>` toutes les ~600 ms ;
2. exécute la commande avec `HiUtils_createRequest('fileRead' | 'fileWrite', { path: 'websdk/Appinfo.json', mode: 6 })` ;
3. renvoie `POST /result?t=<jeton>` avec `{ id, result }`.

Le jeton de session est obligatoire (sinon `403`). Une commande non récupérée au bout de **25 s**
est annulée : elle ne s'exécute jamais en différé. La page n'est relancée que si elle n'a pas
interrogé le Mac depuis 3 s.

| Action | Paramètres | Résultat |
|---|---|---|
| `list` | — | `apps`, `total` |
| `backup` | — | `backup` (fichier brut) |
| `install` | `Id`, `AppName`, `URL`, `IconURL` | `replaced`, `apps`, `backup` |
| `uninstall` | `Id` | `apps`, `backup` |
| `restore` | `data` (JSON complet) | `apps`, `backup` |

Chaque écriture renvoie **le fichier d'origine** (`backup`), archivé par le Mac avant d'afficher
le succès.

## 4. Format d'une entrée `Appinfo.json`

```json
{
  "Id": "jellyfin",
  "AppName": "Jellyfin", "Title": "Jellyfin",
  "URL": "http://192.168.1.20:8096", "StartCommand": "http://192.168.1.20:8096",
  "IconURL": "https://…/icon.png", "Icon_96": "…", "Image": "…", "Thumb": "…",
  "Type": "Browser", "StoreType": "custom", "PreInstall": false,
  "InstallTime": "2026-11-10", "RunTimes": 0,
  "configUrl": "", "configUrlDownload": 0, "mediaId": 0, "initialFrom": "",
  "appInfo": { "url": "http://192.168.1.20:8096", "name": "Jellyfin" }
}
```

Une entrée avec le même `Id` est remplacée, sinon ajoutée.

## 5. Fichiers locaux

| Chemin | Contenu |
|---|---|
| `~/Library/Application Support/VidaaInstall/tvs.json` | TV appairés, jetons, identifiant client (mode 600) |
| `~/Library/Application Support/VidaaRemote/backups/` | Copies horodatées d'`Appinfo.json` |

Au premier lancement, la configuration d'anciens outils (VidaaRemote / VidaaLauncher) est
importée si elle existe.
