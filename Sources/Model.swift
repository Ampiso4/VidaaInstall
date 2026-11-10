import SwiftUI
import AppKit

enum Pane: String, CaseIterable, Identifiable {
    case tvs, install, apps, backups
    var id: String { rawValue }
    var title: String {
        switch self { case .tvs: "Téléviseurs"; case .install: "Installer"; case .apps: "Applications"; case .backups: "Sauvegardes" }
    }
    var subtitle: String {
        switch self {
        case .tvs: "Scan et appairage"
        case .install: "Nouvelle tuile"
        case .apps: "Sur le téléviseur"
        case .backups: "Appinfo.json"
        }
    }
    var icon: String {
        switch self { case .tvs: "dot.radiowaves.left.and.right"; case .install: "sparkles"; case .apps: "square.grid.2x2.fill"; case .backups: "clock.arrow.circlepath" }
    }
}

enum OrbState: Equatable { case idle, working, success, failure }

enum AppSource: String, CaseIterable, Identifiable {
    case all, custom, store, hisense
    var id: String { rawValue }
    var title: String {
        switch self { case .all: "Toutes"; case .custom: "Mes apps"; case .store: "Store"; case .hisense: "Hisense" }
    }
    var icon: String {
        switch self { case .all: "square.grid.2x2"; case .custom: "person.crop.square"; case .store: "bag"; case .hisense: "tv" }
    }
}

enum AppSort: String, CaseIterable, Identifiable {
    case name, recent
    var id: String { rawValue }
    var title: String { self == .name ? "A → Z" : "Récentes" }
}

struct TVApp: Identifiable, Hashable {
    let id: String
    let name: String
    let url: String
    let icon: String
    let source: AppSource
    let preinstalled: Bool
    let category: String?
    let installed: Date?
    let host: String

    var custom: Bool { source == .custom }

    private static let categories: [String: String] = [
        "internet tv": "TV en ligne", "movies & tv series": "Films & séries", "sports": "Sport",
        "tools": "Outils", "music": "Musique", "games": "Jeux", "news": "Actualités", "kids": "Enfants",
        "education": "Éducation", "lifestyle": "Style de vie", "entertainment": "Divertissement",
        "video": "Vidéo", "social": "Réseaux sociaux", "health & fitness": "Santé et sport",
    ]

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-M-d"
        return f
    }()

    init?(_ d: [String: Any]) {
        guard let id = d["Id"] as? String, !id.isEmpty else { return nil }
        self.id = id
        url = d["URL"] as? String ?? ""
        icon = ["IconURL", "Icon_96", "Thumb", "Image"].compactMap { d[$0] as? String }.first { !$0.isEmpty } ?? ""
        preinstalled = d["PreInstall"] as? Bool ?? false
        switch (d["StoreType"] as? String ?? "").lowercased() {
        case "custom": source = .custom
        case "store": source = .store
        default: source = .hisense
        }
        let rawCat = [d["subCategory"], d["categoryName"]].compactMap { $0 as? String }.first { !$0.isEmpty }
        category = rawCat.map { Self.categories[$0.lowercased()] ?? $0 }
        installed = (d["InstallTime"] as? String).flatMap { Self.dayFormat.date(from: $0) }
        // « amazon », « miracast » : certaines entrées système n'ont pas d'URL réelle.
        if let u = URL(string: url), let h = u.host { host = h.hasPrefix("www.") ? String(h.dropFirst(4)) : h }
        else { host = url }
        let named = [d["AppName"], d["Title"]].compactMap { $0 as? String }.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if let named { name = named }
        else if !url.isEmpty, URL(string: url)?.host == nil { name = url.prefix(1).uppercased() + url.dropFirst() }
        else { name = "App \(id)" }
    }
}

struct BackupFile: Identifiable, Hashable {
    let url: URL
    let date: Date
    let size: Int
    let appCount: Int?
    let reason: String
    var id: URL { url }
}

struct Toast: Identifiable, Equatable {
    enum Kind { case success, failure, info }
    let id = UUID()
    let text: String
    let kind: Kind
}

enum Field: Hashable { case id, name, url, icon }

@MainActor
final class AppModel: ObservableObject {
    @Published var section: Pane = .install

    // Liaisons
    @Published var link: LinkState = .idle
    @Published var serverUp = false
    @Published var agentLive = false
    @Published var fatal: String?

    // Installation
    @Published var appID = ""
    @Published var appName = ""
    @Published var appURL = ""
    @Published var iconURL = ""
    @Published var installState: OrbState = .idle
    @Published var installMessage = "Renseigne l'application puis lance l'installation."
    @Published var failCount = 0
    @Published var burstAt: Date?
    @Published var attempted = false

    // Applications
    @Published var apps: [TVApp] = []
    @Published var appsLoading = false
    @Published var appsLoaded = false
    @Published var appsVersion = 0
    @Published var appsError: String?
    @Published var search = ""
    @Published var appFilter: AppSource = .all
    @Published var appSort: AppSort = .name
    @Published var confirmUninstall: TVApp?
    @Published var removing: Set<String> = []

    // Sauvegardes
    @Published var backups: [BackupFile] = []
    @Published var backupBusy = false
    @Published var confirmRestore: BackupFile?
    @Published var restoring: URL?

    // Téléviseurs
    @Published var tvs: [TVDevice] = []
    @Published var activeMAC: String?
    @Published var nearby: Set<String> = []
    @Published var scanning = false
    @Published var scanStartedAt: Date?
    @Published var lastScanAt: Date?
    @Published var pairing: PairingSession?
    @Published var pin = ""
    @Published var pinShake = 0
    @Published var pairBurstAt: Date?
    @Published var confirmForget: TVDevice?
    var clientUUID: String
    var scanTask: Task<Void, Never>?
    var lastRediscovery = Date.distantPast
    var refreshingToken = false

    @Published var toast: Toast?
    @Published private(set) var busy = false

    let bridge: TVBridge
    private let handler = HTTPHandler()
    private let server: HTTPServer

    init() {
        let legacy = loadLegacyConfig()
        let stored = TVStore.load()
        // Ce Mac garde l'identifiant hérité (son jeton y est lié) ; un Mac neuf en tire un unique.
        clientUUID = stored?.clientUUID ?? legacy.deviceUUID ?? randomClientUUID()
        bridge = TVBridge(clientUUID: clientUUID)
        server = HTTPServer(port: httpPort, handler: handler)
        tvs = stored?.tvs ?? []
        activeMAC = stored?.activeMAC
        // Les deux rappels arrivent sur la file principale.
        bridge.onState = { [weak self] s in MainActor.assumeIsolated { self?.linkChanged(s) } }
        bridge.onMessage = { [weak self] t, p in MainActor.assumeIsolated { self?.message(t, p) } }
        server.onStateChange = { [weak self] up in
            Task { @MainActor in
                guard let self else { return }
                self.serverUp = up
                if !up { self.fatal = "Port \(httpPort) indisponible — une autre instance tourne-t-elle déjà ?" }
            }
        }
        if stored == nil { persist() } // fige l'identifiant dès le premier lancement
        if !bridge.hasIdentity { fatal = "Certificat client introuvable — impossible de joindre le téléviseur." }
        server.start()
        loadBackups()
        if Self.shots {} // captures : données fictives, aucune connexion
        else if stored == nil { migrate(legacy) } else if activeTV == nil { section = .tvs; startScan() } else { connectActive() }
        if let p = ProcessInfo.processInfo.environment["VIDAA_PANE"], let s = Pane(rawValue: p) { section = s }
        #if DEMO
        if Self.shots { startShots() }
        #endif
        Task { [weak self] in
            while let self {
                let live = self.handler.agentAlive(within: 3)
                if live != self.agentLive { withAnimation(.easeInOut) { self.agentLive = live } }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    var tvConnected: Bool { if case .connected = link { return true } else { return false } }
    var tvAuthorized: Bool { link == .connected(authorized: true) }

    var agentURL: String {
        "http://\(localIPv4(matching: activeTV?.ip ?? "192.168.1.1")):\(httpPort)/agent?t=\(handler.token)"
    }

    // MARK: Exécution d'une commande sur le TV

    enum Outcome {
        case ok([String: Any])
        case failed(String)
        case timeout(picked: Bool)

        var message: String {
            switch self {
            case .ok(let r): return r["msg"] as? String ?? "Opération réussie"
            case .failed(let e): return e
            case .timeout(false): return "Le téléviseur n'a pas ouvert la page agent. Est-il allumé et sur le même réseau ?"
            case .timeout(true): return "Le téléviseur n'a pas confirmé. Vérifie la liste des applications avant de réessayer."
            }
        }
    }

    private func run(_ action: String, _ params: [String: Any] = [:], timeout: TimeInterval = 25,
                     onPicked: (() -> Void)? = nil) async -> Outcome {
        // Page agent déjà ouverte : le TV interroge le Mac, MQTT n'est pas nécessaire.
        if !handler.agentAlive(within: 3) {
            guard activeTV != nil else { return .failed("Aucun téléviseur sélectionné. Lance un scan dans « Téléviseurs ».") }
            guard tvConnected else { return .failed("Téléviseur injoignable. Est-il allumé ? Un scan peut retrouver sa nouvelle adresse.") }
        }
        busy = true
        defer { busy = false }
        // N'ouvre la page agent que si elle n'est pas déjà affichée : un rechargement
        // en pleine écriture ferait perdre la confirmation.
        if !handler.agentAlive(within: 3) { bridge.launch(url: agentURL, name: "VidaaInstall") }
        let id = handler.commands.add(action, params, ttl: timeout)
        let start = Date()
        var picked = false
        while Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let r = handler.commands.takeResult(id) {
                absorb(r, action: action)
                if r["ok"] as? Bool == true { return .ok(r) }
                return .failed(r["error"] as? String ?? "Échec côté téléviseur")
            }
            if !picked, handler.commands.isTaken(id) { picked = true; onPicked?() }
        }
        handler.commands.cancel(id)
        return .timeout(picked: picked)
    }

    /// Sauvegarde automatique (le TV renvoie le fichier d'avant écriture) et
    /// liste à jour des applications.
    func absorb(_ r: [String: Any], action: String) {
        if let raw = r["backup"] as? String, !raw.isEmpty {
            saveBackup(raw, reason: action)
        }
        if let list = r["apps"] as? [[String: Any]] {
            let parsed = list.compactMap(TVApp.init)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                apps = parsed.sorted { ($0.custom ? 0 : 1, $0.name.lowercased()) < ($1.custom ? 0 : 1, $1.name.lowercased()) }
                appsLoaded = true
                appsError = nil
            }
            appsVersion += 1
        }
    }

    func show(_ text: String, _ kind: Toast.Kind) {
        let t = Toast(text: text, kind: kind)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { toast = t }
        Task {
            try? await Task.sleep(nanoseconds: 3_800_000_000)
            if toast?.id == t.id { withAnimation(.easeInOut(duration: 0.3)) { toast = nil } }
        }
    }

    // MARK: Installation

    func error(for field: Field) -> String? {
        switch field {
        case .id:
            if appID.isEmpty { return attempted ? "Obligatoire" : nil }
            return appID.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) == nil
                ? "Lettres, chiffres, point, tiret ou souligné uniquement" : nil
        case .name:
            return attempted && appName.trimmingCharacters(in: .whitespaces).isEmpty ? "Obligatoire" : nil
        case .url:
            if appURL.isEmpty { return attempted ? "Obligatoire" : nil }
            return isHTTP(appURL) ? nil : "Doit commencer par http:// ou https://"
        case .icon:
            return iconURL.isEmpty || isHTTP(iconURL) ? nil : "Doit commencer par http:// ou https://"
        }
    }

    private func isHTTP(_ s: String) -> Bool {
        guard let u = URL(string: s), let scheme = u.scheme?.lowercased(), u.host != nil else { return false }
        return scheme == "http" || scheme == "https"
    }

    var formValid: Bool {
        !appID.isEmpty && !appName.trimmingCharacters(in: .whitespaces).isEmpty && !appURL.isEmpty
            && [Field.id, .name, .url, .icon].allSatisfy { error(for: $0) == nil }
    }

    /// Propose un identifiant à partir du nom tant que l'utilisateur n'en a pas saisi.
    func suggestID(from name: String, previous: String) {
        let slug = { (s: String) in
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
        }
        if appID.isEmpty || appID == slug(previous) { appID = slug(name) }
    }

    func install() {
        attempted = true
        guard formValid, !busy else {
            withAnimation(.default) { failCount += 1 }
            return
        }
        let name = appName.trimmingCharacters(in: .whitespaces)
        let params: [String: Any] = ["Id": appID, "AppName": name, "URL": appURL, "IconURL": iconURL]
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            installState = .working
            installMessage = agentLive ? "Envoi au téléviseur…" : "Ouverture de la page agent sur le téléviseur…"
        }
        Task {
            let out = await run("install", params) {
                withAnimation { self.installMessage = "Écriture d'Appinfo.json…" }
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                switch out {
                case .ok(let r):
                    installState = .success
                    burstAt = Date()
                    let replaced = r["replaced"] as? Bool == true
                    installMessage = "« \(name) » \(replaced ? "mis à jour" : "installé"). Redémarre le TV pour voir la tuile."
                    show(replaced ? "Application mise à jour" : "Application installée", .success)
                default:
                    installState = .failure
                    failCount += 1
                    installMessage = out.message
                    show("Échec de l'installation", .failure)
                }
            }
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if installState != .working { withAnimation(.easeInOut(duration: 0.6)) { installState = .idle } }
        }
    }

    func resetForm() {
        withAnimation(.spring) {
            appID = ""; appName = ""; appURL = ""; iconURL = ""
            attempted = false; installState = .idle
            installMessage = "Renseigne l'application puis lance l'installation."
        }
    }

    func edit(_ app: TVApp) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            appID = app.id; appName = app.name; appURL = app.url; iconURL = app.icon
            installState = .idle
            installMessage = "Modifie les champs puis réinstalle pour mettre à jour « \(app.name) »."
            section = .install
        }
    }

    // MARK: Applications

    func refreshApps() {
        guard !busy else { return }
        withAnimation { appsLoading = true; appsError = nil }
        Task {
            let out = await run("list")
            withAnimation(.spring) {
                appsLoading = false
                if case .ok = out {} else { appsError = out.message }
            }
        }
    }

    func uninstall(_ app: TVApp) {
        guard !busy else { return }
        withAnimation { _ = removing.insert(app.id) }
        Task {
            let out = await run("uninstall", ["Id": app.id])
            withAnimation(.spring) { _ = removing.remove(app.id) }
            if case .ok = out { show("« \(app.name) » désinstallée", .success) }
            else { show(out.message, .failure) }
        }
    }

    func count(_ f: AppSource) -> Int { f == .all ? apps.count : apps.filter { $0.source == f }.count }

    var filteredApps: [TVApp] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        var list = apps.filter { appFilter == .all || $0.source == appFilter }
        if !q.isEmpty {
            list = list.filter { [$0.name, $0.id, $0.host, $0.category ?? ""].contains { $0.lowercased().contains(q) } }
        }
        switch appSort {
        case .name: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .recent: list.sort { ($0.installed ?? .distantPast) > ($1.installed ?? .distantPast) }
        }
        return list
    }

    // MARK: Sauvegardes

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return f
    }()

    private func saveBackup(_ raw: String, reason: String) {
        try? FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        let name = "Appinfo-\(Self.stamp.string(from: Date()))-\(reason).json"
        try? raw.write(to: backupsDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        loadBackups()
    }

    #if DEMO
    static let shots = ProcessInfo.processInfo.environment["VIDAA_SHOTS"] != nil
    #else
    static let shots = false
    #endif

    func loadBackups() {
        #if DEMO
        if Self.shots { withAnimation(.spring) { backups = Self.demoBackups() }; return }
        #endif
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        let list: [BackupFile] = files.filter { $0.pathExtension == "json" }.map { u in
            let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            var count: Int?
            if let d = try? Data(contentsOf: u),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let a = o["AppInfo"] as? [Any] { count = a.count }
            let base = u.deletingPathExtension().lastPathComponent
            let reason: String
            if base.hasSuffix("-install") { reason = "Avant une installation" }
            else if base.hasSuffix("-uninstall") { reason = "Avant une désinstallation" }
            else if base.hasSuffix("-restore") { reason = "Avant une restauration" }
            else { reason = "Sauvegarde manuelle" }
            return BackupFile(url: u, date: v?.contentModificationDate ?? .distantPast,
                              size: v?.fileSize ?? 0, appCount: count, reason: reason)
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            backups = list.sorted { $0.date > $1.date }
        }
    }

    func backupNow() {
        guard !busy else { return }
        withAnimation { backupBusy = true }
        Task {
            let out = await run("backup")
            withAnimation { backupBusy = false }
            if case .ok(let r) = out {
                show("Sauvegarde enregistrée — \(r["total"] as? Int ?? 0) apps", .success)
            } else { show(out.message, .failure) }
        }
    }

    func restore(_ b: BackupFile) {
        guard !busy, let raw = try? String(contentsOf: b.url, encoding: .utf8) else { return }
        withAnimation { restoring = b.url }
        Task {
            let out = await run("restore", ["data": raw])
            withAnimation { restoring = nil }
            if case .ok = out { show("Sauvegarde restaurée. Redémarre le TV.", .success) }
            else { show(out.message, .failure) }
        }
    }

    func reveal(_ b: BackupFile) { NSWorkspace.shared.activateFileViewerSelecting([b.url]) }
    func openBackupsFolder() {
        try? FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(backupsDir)
    }
}
