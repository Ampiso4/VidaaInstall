import SwiftUI

enum PairStep: Equatable { case connecting, waitingPIN, verifying, success, failed }

struct PairingSession: Equatable {
    var tv: TVDevice
    var step: PairStep
    var error: String?
}

extension AppModel {
    var activeTV: TVDevice? { tvs.first { $0.mac == activeMAC } }

    /// Actif d'abord, puis appairés, puis le reste.
    var tvRows: [TVDevice] {
        tvs.sorted { a, b in
            let ka = (a.mac == activeMAC ? 0 : a.paired ? 1 : 2), kb = (b.mac == activeMAC ? 0 : b.paired ? 1 : 2)
            return ka != kb ? ka < kb : a.ip.localizedStandardCompare(b.ip) == .orderedAscending
        }
    }

    var linkLabel: String {
        guard activeTV != nil else { return "aucun" }
        switch link {
        case .connected(true): return "connecté"
        case .connected(false): return "non appairé"
        case .connecting: return "connexion…"
        case .rejected: return "refusé"
        case .offline: return "hors ligne"
        case .idle: return "—"
        }
    }

    private func index(_ mac: String) -> Int? { tvs.firstIndex { $0.mac == mac } }

    func persist() {
        TVStore.save(TVStoreFile(clientUUID: clientUUID, activeMAC: activeMAC,
                                 tvs: tvs.filter { $0.paired || $0.mac == activeMAC }))
    }

    // MARK: Migration depuis VidaaRemote / VidaaLauncher

    func migrate(_ l: LegacyConfig) {
        Task {
            if let ip = l.tvIP, var tv = await TVScanner.probe(ip) {
                // Le jeton hérité n'est valable qu'avec l'identifiant client qui l'a obtenu.
                if !l.access.isEmpty, l.deviceUUID != nil {
                    tv.token = TVToken(access: l.access, refresh: l.refresh, issued: l.time, accessDays: 2, refreshDays: 30)
                }
                withAnimation(.spring) { tvs = [tv]; activeMAC = tv.mac; nearby = [tv.mac] }
                persist()
                connectActive()
                if !tv.paired { section = .tvs }
            } else {
                section = .tvs
                startScan()
            }
        }
    }

    // MARK: Connexion

    func connectActive() {
        guard let tv = activeTV else { bridge.disconnect(); return }
        bridge.connect(ip: tv.ip, auth: tv.auth, token: tv.token?.accessValid == true ? tv.token?.access : nil)
    }

    func linkChanged(_ s: LinkState) {
        withAnimation(.easeInOut(duration: 0.3)) { link = s }
        switch s {
        case .connected(let authorized):
            if pairing?.step == .connecting {
                bridge.requestPIN()
                withAnimation(.spring) { pairing?.step = .waitingPIN }
            } else if !authorized, pairing == nil, !refreshingToken,
                      let t = activeTV?.token, t.refreshValid {
                // Jeton d'accès expiré : on en redemande un avec le jeton de rafraîchissement.
                refreshingToken = true
                bridge.requestToken(refresh: t.refresh)
            }
        case .rejected(_, let usedToken):
            if usedToken, let m = activeMAC, let i = index(m) { tvs[i].token?.access = ""; persist() }
        case .offline(let n):
            if n >= 2 { rediscover() }
            if n >= 3, pairing?.step == .connecting {
                withAnimation(.spring) {
                    pairing?.step = .failed
                    pairing?.error = "Téléviseur injoignable. Vérifie qu'il est allumé."
                }
            }
        default: break
        }
    }

    /// Le TV ne répond plus : il a peut-être changé d'IP. Un scan le retrouve par sa MAC.
    func rediscover() {
        guard !scanning, activeTV != nil, Date().timeIntervalSince(lastRediscovery) > 45 else { return }
        lastRediscovery = Date()
        startScan(quiet: true)
    }

    func message(_ topic: String, _ payload: String) {
        if topic.hasSuffix("/authentication") {
            if pairing?.step == .connecting { withAnimation(.spring) { pairing?.step = .waitingPIN } }
        } else if topic.hasSuffix("/authenticationcode") {
            let o = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any]
            let result = (o?["result"] as? Int) ?? Int(o?["result"] as? String ?? "")
            if result == 1 {
                withAnimation(.spring) { pairing?.step = .verifying }
                bridge.requestToken()
            } else if pairing != nil {
                withAnimation(.spring) {
                    pairing?.step = .waitingPIN
                    pairing?.error = "Code incorrect, réessaie."
                    pin = ""
                    pinShake += 1
                }
            }
        } else if topic.contains("tokenissuance") {
            guard let tok = TVToken.parse(payload), let mac = pairing?.tv.mac ?? activeMAC, let i = index(mac) else { return }
            refreshingToken = false
            tvs[i].token = tok
            activeMAC = mac
            persist()
            connectActive() // le jeton n'autorise qu'une nouvelle connexion
            if pairing != nil {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { pairing?.step = .success; pairBurstAt = Date() }
                Task {
                    try? await Task.sleep(nanoseconds: 1_700_000_000)
                    withAnimation(.spring) { pairing = nil }
                    show("« \(tvs[i].displayName) » appairé", .success)
                }
            }
        }
    }

    // MARK: Scan

    func startScan(quiet: Bool = false) {
        guard !scanning else { return }
        scanTask?.cancel()
        withAnimation(.easeInOut) { scanning = true; scanStartedAt = Date(); nearby = [] }
        let priority = tvs.map(\.ip)
        scanTask = Task {
            // Deux passes au plus : la première peut tomber pendant que macOS demande
            // l'accès au réseau local (après chaque recompilation).
            for pass in 0..<2 {
                for await tv in TVScanner.scan(priority: priority) {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { upsert(tv) }
                }
                if !nearby.isEmpty || Task.isCancelled || pass == 1 { break }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
            withAnimation(.easeInOut) { scanning = false; lastScanAt = Date() }
            if nearby.isEmpty && !quiet {
                show("Aucun téléviseur VIDAA trouvé. Même réseau ? Accès au réseau local autorisé ?", .info)
            }
        }
    }

    private func upsert(_ found: TVDevice) {
        nearby.insert(found.mac)
        guard let i = index(found.mac) else { tvs.append(found); return }
        let moved = tvs[i].ip != found.ip
        tvs[i].ip = found.ip
        tvs[i].name = found.name
        tvs[i].transport = found.transport
        tvs[i].wifiMAC = found.wifiMAC
        tvs[i].lastSeen = Date()
        persist()
        if moved && found.mac == activeMAC {
            show("Téléviseur retrouvé à sa nouvelle adresse \(found.ip)", .info)
            connectActive()
        }
    }

    // MARK: Appairage

    func use(_ tv: TVDevice) {
        guard tv.paired else { startPairing(tv); return }
        withAnimation(.spring) { activeMAC = tv.mac }
        persist()
        connectActive()
        show("« \(tv.displayName) » sélectionné", .success)
    }

    func startPairing(_ tv: TVDevice) {
        pin = ""
        withAnimation(.spring) { activeMAC = tv.mac }
        persist()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { pairing = PairingSession(tv: tv, step: .connecting) }
        bridge.connect(ip: tv.ip, auth: tv.auth, token: nil)
    }

    func submitPIN() {
        guard pin.count == 4, pairing?.step == .waitingPIN else { return }
        withAnimation(.spring) { pairing?.step = .verifying; pairing?.error = nil }
        bridge.submitPIN(pin)
        let sent = pin
        Task {
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            if pairing?.step == .verifying, pin == sent {
                withAnimation(.spring) { pairing?.step = .waitingPIN; pairing?.error = "Pas de réponse du téléviseur. Réessaie ou redemande un code." }
            }
        }
    }

    func resendPIN() {
        pin = ""
        withAnimation(.spring) { pairing?.error = nil }
        if tvConnected {
            withAnimation(.spring) { pairing?.step = .waitingPIN }
            bridge.requestPIN()
        } else if let tv = pairing?.tv {
            withAnimation(.spring) { pairing?.step = .connecting }
            bridge.connect(ip: tv.ip, auth: tv.auth, token: nil)
        }
    }

    func cancelPairing() {
        if pairing?.step == .waitingPIN { bridge.closePINDialog() }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { pairing = nil }
        connectActive()
    }

    func forget(_ tv: TVDevice) {
        withAnimation(.spring) {
            if let i = index(tv.mac) {
                if nearby.contains(tv.mac) { tvs[i].token = nil } else { tvs.remove(at: i) }
            }
            if activeMAC == tv.mac { activeMAC = nil }
        }
        if activeTV == nil { bridge.disconnect() }
        persist()
        show("« \(tv.displayName) » oublié", .info)
    }
}
