#if DEMO
import SwiftUI

// Mode « captures » (build de test uniquement : swiftc -D DEMO, jamais dans la release).
// Données fictives : aucune IP ni MAC réelle, pas de connexion au téléviseur.
//   VIDAA_SHOTS=1            active le mode
//   VIDAA_PANE=tvs|install|apps|backups
//   VIDAA_SHOTS_STATE=success|pair|scan   état particulier
//   VIDAA_SHOTS_TOUR=1       visite automatique des écrans (pour le GIF)

extension AppModel {
    static var env: [String: String] { ProcessInfo.processInfo.environment }

    private static let salon = "02:94:be:2c:ac:c6"
    private static let chambre = "02:e7:52:77:9c:84"

    func startShots() {
        let token = TVToken(access: "demo", refresh: "demo", issued: Int(Date().timeIntervalSince1970), accessDays: 2, refreshDays: 30)
        tvs = [
            TVDevice(mac: Self.salon, name: "Salon", ip: "192.168.1.42", transport: 3290, token: token, lastSeen: Date()),
            TVDevice(mac: Self.chambre, name: "Chambre", ip: "192.168.1.57", transport: 3285, lastSeen: Date()),
        ]
        activeMAC = Self.salon
        nearby = [Self.salon, Self.chambre]
        lastScanAt = Date()
        link = .connected(authorized: true)
        absorb(["apps": Self.demoApps], action: "list")

        switch Self.env["VIDAA_SHOTS_STATE"] {
        case "pair":
            pairing = PairingSession(tv: tvs[1], step: .waitingPIN); pin = "47"
        case "scan":
            simulateScan()
        case "success":
            fillForm()
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                fakeInstall()
            }
        default: break
        }
        if Self.env["VIDAA_SHOTS_TOUR"] != nil { tour() }
    }

    private func fillForm() {
        appName = "Jellyfin"; appID = "jellyfin"
        appURL = "http://192.168.1.20:8096/web/index.html"
        iconURL = "https://avatars.githubusercontent.com/u/45698031?s=300"
    }

    private func fakeInstall() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            installState = .working; installMessage = "Écriture d'Appinfo.json…"
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                installState = .success; burstAt = Date()
                installMessage = "« Jellyfin » installé. Redémarre le TV pour voir la tuile."
            }
            show("Application installée", .success)
        }
    }

    private func simulateScan() {
        let found = nearby
        withAnimation { scanning = true; scanStartedAt = Date(); nearby = [] }
        Task {
            for mac in found {
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { _ = nearby.insert(mac) }
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation { scanning = false; lastScanAt = Date() }
        }
    }

    private func tour() {
        Task {
            @MainActor func go(_ p: Pane, _ wait: Double) async {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { section = p }
                try? await Task.sleep(nanoseconds: UInt64(wait * 1e9))
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            section = .tvs; simulateScan()
            try? await Task.sleep(nanoseconds: 4_200_000_000)
            await go(.apps, 1.6)
            withAnimation(.spring) { appFilter = .custom }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.spring) { appFilter = .all }
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await go(.install, 0.9)
            fillForm()
            try? await Task.sleep(nanoseconds: 900_000_000)
            fakeInstall()
            try? await Task.sleep(nanoseconds: 3_600_000_000)
            await go(.backups, 2.5)
        }
    }

    static func demoBackups() -> [BackupFile] {
        let now = Date()
        let base = URL(fileURLWithPath: "/tmp/vidaa-demo")
        return [
            BackupFile(url: base.appendingPathComponent("1"), date: now.addingTimeInterval(-90), size: 34_100, appCount: 12, reason: "Avant une installation"),
            BackupFile(url: base.appendingPathComponent("2"), date: now.addingTimeInterval(-3_600 * 5), size: 33_200, appCount: 11, reason: "Avant une désinstallation"),
            BackupFile(url: base.appendingPathComponent("3"), date: now.addingTimeInterval(-86_400 * 2), size: 34_000, appCount: 12, reason: "Avant une installation"),
            BackupFile(url: base.appendingPathComponent("4"), date: now.addingTimeInterval(-86_400 * 9), size: 32_800, appCount: 11, reason: "Sauvegarde manuelle"),
        ]
    }

    static let demoApps: [[String: Any]] = [
        ["Id": "2", "AppName": "Prime Video", "URL": "amazon", "StoreType": "store", "subCategory": "Movies & TV series", "InstallTime": "2025-12-26",
         "IconURL": "https://img.vidaahub.com/vidaa/2025/1/202501140748419338.png?resize=w_260,h_260"],
        ["Id": "162", "AppName": "DAZN", "URL": "https://tv.dazn.com/app/vidaa/", "StoreType": "hisense", "subCategory": "Sports", "InstallTime": "2026-8-4",
         "IconURL": "https://img.vidaahub.com/vidaa/2024/5/202405300642094995.png?resize=w_260,h_260"],
        ["Id": "244", "AppName": "UEFA.tv", "URL": "https://dice-tv.imggaming.com/vidaa/dce.uefatv/index.html", "StoreType": "hisense", "subCategory": "Sports", "InstallTime": "2026-5-12",
         "IconURL": "https://img.vidaahub.com/vidaa/2025/1/202501140801084724.png?resize=w_260,h_260"],
        ["Id": "2568", "AppName": "Stremio Lite", "URL": "https://www.stremio.com/", "StoreType": "hisense", "subCategory": "Movies & TV series", "InstallTime": "2026-7-4",
         "IconURL": "https://img.vidaahub.com/s3_bucket/9999/app/9999_80d92da5-01bf-4416-b46b-901c63b257d1/a14b838fd3d7a02375371564a0545f89?f=webp&resize=w_300,h_300"],
        ["Id": "2187", "AppName": "TVZone", "URL": "https://tvzone.app/android/", "StoreType": "hisense", "subCategory": "Internet TV", "InstallTime": "2025-9-3",
         "IconURL": "https://img.vidaahub.com/vidaa/2026/10/202610221955111099.png?resize=w_300,h_300"],
        ["Id": "1876", "AppName": "Duplecast", "URL": "http://vidaa.duplecast.com/", "StoreType": "store", "subCategory": "Internet TV", "InstallTime": "2025-9-3",
         "IconURL": "https://img.vidaahub.com/vidaa/2022/11/202211102142287972.jpg?resize=w_300,h_300"],
        ["Id": "1623", "AppName": "A to Z Movie Box", "URL": "https://vidaa-tv.vlogbox.com/", "StoreType": "hisense", "subCategory": "Movies & TV series", "InstallTime": "2026-5-7",
         "IconURL": "https://img.vidaahub.com/vidaa/2022/7/202207270112586222.png?resize=w_300,h_300"],
        ["Id": "2185", "AppName": "Hot IPTV", "URL": "http://vidaa.hotplayer.app/index.html", "StoreType": "store", "subCategory": "Internet TV", "InstallTime": "2025-9-3",
         "IconURL": "https://img.vidaahub.com/vidaa/2023/10/202310041838499485.png?resize=w_300,h_300"],
        ["Id": "jellyfin", "AppName": "Jellyfin", "URL": "http://192.168.1.20:8096/web/index.html", "StoreType": "custom", "InstallTime": "2026-11-09",
         "IconURL": "https://avatars.githubusercontent.com/u/45698031?s=300"],
        ["Id": "dashboard", "AppName": "Mon Dashboard", "URL": "http://192.168.1.20:8080/index.html", "StoreType": "custom", "InstallTime": "2026-11-10"],
    ]
}
#endif
