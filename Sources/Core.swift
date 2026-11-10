import Foundation
import Network
import Security

// Moteur de VidaaInstall : pont MQTT vers le TV, file de commandes, serveur HTTP
// que la page agent (ouverte sur le TV) interroge en boucle.

let supportDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/VidaaRemote")
let backupsDir = supportDir.appendingPathComponent("backups")
let installDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/VidaaInstall")
/// Port propre à VidaaInstall : VidaaLauncher occupe déjà 8099.
let httpPort: UInt16 = 8090

/// Réglages hérités de VidaaRemote/VidaaLauncher, lus une fois pour la migration.
struct LegacyConfig {
    var tvIP: String?
    var deviceUUID: String?
    var access = ""
    var refresh = ""
    var time = 0
    /// Vrai si une config VidaaRemote/VidaaLauncher existe sur ce Mac.
    var found = false
}

/// Identifiant client propre à ce Mac, au format MAC « administrée localement ».
/// Deux Mac avec le même identifiant se déconnecteraient l'un l'autre sur le TV.
func randomClientUUID() -> String {
    var b = (0..<6).map { _ in UInt8.random(in: 0...255) }
    b[0] = (b[0] & 0xFC) | 0x02
    return b.map { String(format: "%02x", $0) }.joined(separator: ":")
}

func loadLegacyConfig() -> LegacyConfig {
    struct C: Codable { var tvIP: String?; var deviceUUID: String? }
    struct T: Codable { var access: String; var refresh: String; var time: Double }
    var l = LegacyConfig()
    if let d = try? Data(contentsOf: supportDir.appendingPathComponent("config.json")),
       let c = try? JSONDecoder().decode(C.self, from: d) {
        if let ip = c.tvIP { l.tvIP = ip }
        if let u = c.deviceUUID { l.deviceUUID = u }
        l.found = true
    }
    if let d = try? Data(contentsOf: supportDir.appendingPathComponent("token.json")),
       let t = try? JSONDecoder().decode(T.self, from: d) {
        l.access = t.access; l.refresh = t.refresh; l.time = Int(t.time)
        l.found = true
    }
    return l
}

// MARK: - Adresse IP du Mac vue par le TV

private func parseIPv4(_ s: String) -> UInt32? {
    var a = in_addr()
    guard inet_pton(AF_INET, s, &a) == 1 else { return nil }
    return UInt32(bigEndian: a.s_addr)
}

private func ipv4(_ sa: UnsafeMutablePointer<sockaddr>) -> UInt32 {
    sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
}

private func format(_ ip: UInt32) -> String {
    "\(ip >> 24 & 0xFF).\(ip >> 16 & 0xFF).\(ip >> 8 & 0xFF).\(ip & 0xFF)"
}

/// Choisit l'interface qui est sur le même sous-réseau que le TV (Wi-Fi, Ethernet
/// USB…), sinon la première interface `en*` active.
func localIPv4(matching tvIP: String) -> String {
    let tv = parseIPv4(tvIP)
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return "127.0.0.1" }
    defer { freeifaddrs(ifaddr) }
    var fallback: String?
    for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
        let f = ptr.pointee
        guard let addr = f.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
              (f.ifa_flags & UInt32(IFF_UP)) != 0, (f.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
        let ip = ipv4(addr)
        if let tv, let m = f.ifa_netmask, ip & ipv4(m) == tv & ipv4(m) { return format(ip) }
        if fallback == nil, String(cString: f.ifa_name).hasPrefix("en") { fallback = format(ip) }
    }
    return fallback ?? "127.0.0.1"
}

// MARK: - Pont MQTT

enum LinkState: Equatable {
    case idle
    case connecting
    case connected(authorized: Bool)
    case rejected(code: UInt8, usedToken: Bool)
    case offline(attempts: Int)
}

/// Une session MQTT/TLS avec un téléviseur. Une seule connexion vivante à la fois :
/// chaque `connect` invalide la précédente (compteur de génération).
final class TVBridge {
    private let identity: SecIdentity?
    private let clientUUID: String
    private let queue = DispatchQueue(label: "vidaa.install.bridge")
    private var conn: NWConnection?
    private var framer = MQTTFramer()
    private var pending: [Data] = []
    private var generation = 0
    private var failures = 0
    private var reconnectScheduled = false
    private var target: (ip: String, auth: AuthMethod, token: String?)?
    private var creds: MQTTCredentials
    private(set) var authorized = false
    private var ready = false

    var onState: ((LinkState) -> Void)?
    var onMessage: ((String, String) -> Void)?

    init(clientUUID: String) {
        self.clientUUID = clientUUID
        self.identity = ClientIdentity.load()
        self.creds = generateCredentials(uuid: clientUUID, auth: .modern)
    }

    var hasIdentity: Bool { identity != nil }

    func connect(ip: String, auth: AuthMethod, token: String?) {
        queue.async {
            self.target = (ip, auth, token)
            self.failures = 0
            self.open()
        }
    }

    func disconnect() {
        queue.async {
            self.generation += 1
            self.target = nil
            self.teardown()
            self.emit(.idle)
        }
    }

    private func teardown() {
        if ready { conn?.send(content: MQTTPacket.disconnect, completion: .contentProcessed { _ in }) }
        conn?.stateUpdateHandler = nil
        conn?.cancel()
        conn = nil
        ready = false
        authorized = false
    }

    private func emit(_ s: LinkState) { DispatchQueue.main.async { self.onState?(s) } }

    private func open() {
        generation += 1
        let gen = generation
        teardown()
        framer = MQTTFramer()
        guard let target, let identity, let secIdentity = sec_identity_create(identity) else { return }
        // Identifiants recalculés à chaque tentative : ils dépendent de l'horodatage.
        creds = generateCredentials(uuid: clientUUID, auth: target.auth)
        emit(.connecting)

        let tls = NWProtocolTLS.Options()
        let sec = tls.securityProtocolOptions
        sec_protocol_options_set_local_identity(sec, secIdentity)
        // Le TV présente un certificat auto-signé.
        sec_protocol_options_set_verify_block(sec, { _, _, done in done(true) }, queue)
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 5
        let c = NWConnection(host: NWEndpoint.Host(target.ip), port: NWEndpoint.Port(rawValue: VidaaConstants.mqttPort)!,
                             using: NWParameters(tls: tls, tcp: tcp))
        conn = c
        c.stateUpdateHandler = { [weak self] st in
            guard let self, gen == self.generation else { return }
            switch st {
            case .ready:
                let pw = target.token ?? self.creds.password
                self.raw(MQTTPacket.connect(clientId: self.creds.clientId, username: self.creds.username,
                                            password: pw, keepAlive: 120))
                self.read(c, gen)
            case .failed, .waiting:
                self.retry(gen)
            default: break
            }
        }
        c.start(queue: queue)
    }

    private func retry(_ gen: Int) {
        guard gen == generation, !reconnectScheduled, target != nil else { return }
        reconnectScheduled = true
        ready = false
        authorized = false
        failures += 1
        emit(.offline(attempts: failures))
        let delay = min(15.0, 2.0 * Double(failures))
        queue.asyncAfter(deadline: .now() + delay) {
            self.reconnectScheduled = false
            guard gen == self.generation else { return }
            self.open()
        }
    }

    private func ping(_ gen: Int) {
        queue.asyncAfter(deadline: .now() + 50) {
            guard gen == self.generation, self.ready else { return }
            self.raw(MQTTPacket.pingreq)
            self.ping(gen)
        }
    }

    private func raw(_ d: Data) { conn?.send(content: d, completion: .contentProcessed { _ in }) }

    private func read(_ c: NWConnection, _ gen: Int) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 18) { [weak self] data, _, done, err in
            guard let self, gen == self.generation else { return }
            if let data, !data.isEmpty {
                self.framer.append(data)
                for p in self.framer.drain() { self.handle(p, gen) }
            }
            if err == nil && !done { self.read(c, gen); return }
            self.retry(gen)
        }
    }

    private func handle(_ p: MQTTPacket.Incoming, _ gen: Int) {
        switch p.kind {
        case 2: // CONNACK = [session-present, code retour]
            let code = p.body.count >= 2 ? p.body[1] : 0xFF
            guard code == 0 else {
                let usedToken = target?.token != nil
                // Jeton refusé : on retombe sur les identifiants dynamiques.
                if usedToken { target?.token = nil }
                emit(.rejected(code: code, usedToken: usedToken))
                retry(gen)
                return
            }
            failures = 0
            ready = true
            authorized = target?.token != nil
            subscribe()
            ping(gen)
            emit(.connected(authorized: authorized))
            pending.forEach(raw)
            pending.removeAll()
        case 3: // PUBLISH
            if (p.flags >> 1) & 0x03 == 1, p.body.count >= 4 {
                let pid0 = p.body[2], pid1 = p.body[3]
                raw(Data([0x40, 0x02, pid0, pid1])) // PUBACK
            }
            if let topic = p.topic, let payload = p.payload {
                DispatchQueue.main.async { self.onMessage?(topic, payload) }
            }
        default: break
        }
    }

    private func subscribe() {
        let base = "/remoteapp/mobile/\(creds.clientId)"
        let topics = ["authentication", "authenticationcode", "authenticationcodeclose", "tokenissuance"]
            .map { "\(base)/ui_service/data/\($0)" } + ["\(base)/platform_service/data/tokenissuance"]
        raw(MQTTPacket.subscribe(topics: topics, packetId: UInt16.random(in: 1...65535)))
    }

    func publish(_ topic: String, _ payload: String, queueIfOffline: Bool = false) {
        queue.async {
            let pkt = MQTTPacket.publish(topic: topic.replacingOccurrences(of: "{id}", with: self.creds.clientId), payload: payload)
            if self.ready { self.raw(pkt) } else if queueIfOffline { self.pending = [pkt] }
        }
    }

    /// Demande au TV d'ouvrir une URL dans son navigateur (MQTT `launchapp`).
    func launch(url: String, name: String) {
        let payload: [String: Any] = ["name": name, "urlType": 37, "storeType": 0, "url": url]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        publish("/remoteapp/tv/ui_service/{id}/actions/launchapp", json, queueIfOffline: true)
    }

    // Appairage : le TV affiche un code à 4 chiffres, on le renvoie, il émet un jeton.
    func requestPIN() {
        publish("/remoteapp/tv/ui_service/{id}/actions/vidaa_app_connect",
                #"{"app_version":2,"connect_result":0,"device_type":"Mobile App"}"#)
    }
    func submitPIN(_ pin: String) {
        // L'app officielle envoie authNum en entier JSON, pas en chaîne.
        publish("/remoteapp/tv/ui_service/{id}/actions/authenticationcode", #"{"authNum":\#(Int(pin) ?? 0)}"#)
    }
    func closePINDialog() { publish("/remoteapp/tv/ui_service/{id}/actions/authenticationcodeclose", "") }
    func requestToken(refresh: String = "") {
        let esc = refresh.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        publish("/remoteapp/tv/platform_service/{id}/data/gettoken", #"{"refreshtoken":"\#(esc)"}"#)
    }
}

// MARK: - File de commandes

final class CommandQueue {
    private struct Command { let id: Int; let action: String; let params: [String: Any]; let deadline: Date }
    private var queue: [Command] = []
    private var taken: Set<Int> = []
    private var results: [Int: [String: Any]] = [:]
    private var nextID = 1
    private let lock = NSLock()

    func add(_ action: String, _ params: [String: Any], ttl: TimeInterval) -> Int {
        lock.lock(); defer { lock.unlock() }
        let id = nextID; nextID += 1
        queue.append(Command(id: id, action: action, params: params, deadline: Date().addingTimeInterval(ttl)))
        return id
    }

    /// Le TV vient chercher la commande suivante. Les commandes expirées sont jetées :
    /// une action abandonnée côté Mac ne s'exécute jamais en différé.
    func pop() -> [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        queue.removeAll { $0.deadline < now }
        guard !queue.isEmpty else { return nil }
        let c = queue.removeFirst()
        taken.insert(c.id)
        return ["id": c.id, "action": c.action, "params": c.params]
    }

    func store(_ id: Int, _ result: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        guard taken.contains(id) else { return }
        results[id] = result
    }

    func isTaken(_ id: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return taken.contains(id)
    }

    func takeResult(_ id: Int) -> [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        guard let r = results.removeValue(forKey: id) else { return nil }
        taken.remove(id)
        return r
    }

    func cancel(_ id: Int) {
        lock.lock(); defer { lock.unlock() }
        queue.removeAll { $0.id == id }
        taken.remove(id)
        results.removeValue(forKey: id)
    }
}

// MARK: - Serveur HTTP

final class HTTPHandler {
    let commands = CommandQueue()
    let token = UUID().uuidString
    private let lock = NSLock()
    private var lastPollAt = Date.distantPast

    /// Vrai si la page agent a interrogé le Mac récemment.
    func agentAlive(within seconds: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return Date().timeIntervalSince(lastPollAt) < seconds
    }

    private func agentHTML() -> Data? {
        Bundle.main.url(forResource: "agent", withExtension: "html").flatMap { try? Data(contentsOf: $0) }
    }

    func handle(head: String, body: Data) -> Data {
        guard let first = head.split(separator: "\r\n").first else { return resp(400, "bad request") }
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { return resp(400, "bad request") }
        let method = String(parts[0])
        let comps = URLComponents(string: String(parts[1]))
        let path = comps?.path ?? "/"
        let t = comps?.queryItems?.first { $0.name == "t" }?.value

        if method == "GET", path == "/agent" || path == "/" {
            guard let html = agentHTML() else { return resp(500, "agent.html introuvable") }
            return resp(200, html, type: "text/html; charset=utf-8")
        }
        guard t == token else { return json(403, ["error": "session expirée"]) }

        switch (method, path) {
        case ("GET", "/pending"):
            lock.lock(); lastPollAt = Date(); lock.unlock()
            return json(200, commands.pop() ?? ["action": NSNull()])
        case ("POST", "/result"):
            if let o = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let id = o["id"] as? Int, let r = o["result"] as? [String: Any] {
                commands.store(id, r)
            }
            return json(200, ["ok": true])
        default:
            return resp(404, "not found")
        }
    }

    private func json(_ code: Int, _ obj: [String: Any]) -> Data {
        resp(code, (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8), type: "application/json; charset=utf-8")
    }
    private func resp(_ code: Int, _ s: String) -> Data { resp(code, Data(s.utf8), type: "text/plain; charset=utf-8") }
    private func resp(_ code: Int, _ body: Data, type: String) -> Data {
        let phrase = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 413: "Payload Too Large", 500: "Internal Server Error"][code] ?? "OK"
        var out = Data("HTTP/1.1 \(code) \(phrase)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
        out.append(body)
        return out
    }

    static func tooLarge() -> Data {
        Data("HTTP/1.1 413 Payload Too Large\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
    }
}

final class HTTPServer {
    private let port: UInt16
    private let handler: HTTPHandler
    private var listener: NWListener?
    private static let separator = Data("\r\n\r\n".utf8)
    private static let maxRequest = 16 << 20
    var onStateChange: ((Bool) -> Void)?

    init(port: UInt16, handler: HTTPHandler) { self.port = port; self.handler = handler }

    func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!) else {
            DispatchQueue.main.async { self.onStateChange?(false) }; return
        }
        listener = l
        l.newConnectionHandler = { [weak self] c in
            guard let self else { return }
            c.stateUpdateHandler = { st in if case .ready = st { self.pump(c) } }
            c.start(queue: .global())
            // Pas de connexion zombie : 30 s maximum par requête.
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) { c.cancel() }
        }
        l.stateUpdateHandler = { st in
            let up: Bool
            if case .ready = st { up = true } else if case .failed = st { up = false } else { return }
            DispatchQueue.main.async { self.onStateChange?(up) }
        }
        l.start(queue: .global())
    }

    private func pump(_ c: NWConnection) {
        var buffer = Data()
        func step() {
            c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { data, _, done, err in
                if let data { buffer.append(data) }
                if err != nil { c.cancel(); return }
                if buffer.count > HTTPServer.maxRequest {
                    c.send(content: HTTPHandler.tooLarge(), completion: .contentProcessed { _ in c.cancel() }); return
                }
                // Tout est mesuré en octets bruts : pas de décodage avant la fin des en-têtes.
                if let r = buffer.range(of: HTTPServer.separator) {
                    let head = String(decoding: buffer[buffer.startIndex..<r.lowerBound], as: UTF8.self)
                    var need = 0
                    for line in head.split(separator: "\r\n") {
                        let kv = line.split(separator: ":", maxSplits: 1)
                        if kv.count == 2, kv[0].lowercased() == "content-length" {
                            need = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
                        }
                    }
                    if buffer.count - r.upperBound >= need {
                        let body = buffer[r.upperBound..<(r.upperBound + need)]
                        let response = self.handler.handle(head: head, body: Data(body))
                        c.send(content: response, completion: .contentProcessed { _ in c.cancel() })
                        return
                    }
                }
                if done { c.cancel(); return }
                step()
            }
        }
        step()
    }
}
