import Foundation

// Téléviseurs connus, jetons d'appairage et découverte sur le réseau local.

struct TVToken: Codable, Hashable {
    var access: String
    var refresh: String
    var issued: Int
    var accessDays: Int
    var refreshDays: Int

    var accessValid: Bool { !access.isEmpty && Date().timeIntervalSince1970 < Double(issued + accessDays * 86400) - 600 }
    var refreshValid: Bool { !refresh.isEmpty && Date().timeIntervalSince1970 < Double(issued + refreshDays * 86400) }
    var refreshExpiry: Date { Date(timeIntervalSince1970: TimeInterval(issued + refreshDays * 86400)) }

    /// Charge utile `tokenissuance` du TV : les nombres arrivent parfois en chaînes.
    static func parse(_ json: String) -> TVToken? {
        guard let d = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let access = o["accesstoken"] as? String, !access.isEmpty else { return nil }
        func int(_ k: String, _ f: Int) -> Int {
            if let v = o[k] as? Int { return v }
            if let s = o[k] as? String, let v = Int(s) { return v }
            return f
        }
        return TVToken(access: access, refresh: o["refreshtoken"] as? String ?? "",
                       issued: int("accesstoken_time", Int(Date().timeIntervalSince1970)),
                       accessDays: int("accesstoken_duration_day", 2),
                       refreshDays: int("refreshtoken_duration_day", 30))
    }
}

struct TVDevice: Codable, Identifiable, Hashable {
    /// Adresse MAC du TV (Ethernet) : identifiant stable, l'IP peut changer.
    var mac: String
    var name: String
    var ip: String
    var transport: Int
    var wifiMAC: String?
    var token: TVToken?
    var lastSeen: Date?
    var id: String { mac }

    var paired: Bool { token?.accessValid == true || token?.refreshValid == true }
    var auth: AuthMethod { transport < 3000 ? .legacy : transport < 3290 ? .middle : .modern }
    var displayName: String {
        let generic = ["smart tv", "renderer", ""]
        return generic.contains(name.lowercased()) ? "Téléviseur Hisense" : name
    }
    var shortMAC: String { mac.uppercased() }
}

struct TVStoreFile: Codable {
    var clientUUID: String
    var activeMAC: String?
    var tvs: [TVDevice]
}

enum TVStore {
    static let url = installDir.appendingPathComponent("tvs.json")

    static func load() -> TVStoreFile? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TVStoreFile.self, from: d)
    }

    static func save(_ f: TVStoreFile) {
        try? FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let d = try? enc.encode(f) else { return }
        try? d.write(to: url, options: [.atomic])
        // Contient les jetons : lecture réservée à l'utilisateur.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

// MARK: - Découverte

enum TVScanner {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 1.5
        c.timeoutIntervalForResource = 2.5
        c.httpMaximumConnectionsPerHost = 2
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    /// Lit la description UPnP du TV (port 38400) ; nil si ce n'est pas un VIDAA.
    static func probe(_ ip: String) async -> TVDevice? {
        guard let u = URL(string: "http://\(ip):38400/MediaServer/rendererdevicedesc.xml"),
              let (data, resp) = try? await session.data(from: u),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let xml = String(decoding: data, as: UTF8.self)
        func tag(_ t: String) -> String? {
            guard let a = xml.range(of: "<\(t)>"), let b = xml.range(of: "</\(t)>", range: a.upperBound..<xml.endIndex) else { return nil }
            return String(xml[a.upperBound..<b.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var cap: [String: String] = [:]
        for line in (tag("modelDescription") ?? "").split(whereSeparator: \.isNewline) {
            let kv = line.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { cap[String(kv[0]).trimmingCharacters(in: .whitespaces)] = String(kv[1]).trimmingCharacters(in: .whitespaces) }
        }
        guard cap["vidaa_support"] == "1" || cap["brand"] == "his" else { return nil }
        let rawMAC = cap["macEthernet"] ?? cap["mac"] ?? cap["macWifi"] ?? ""
        guard rawMAC.count == 12 else { return nil }
        return TVDevice(mac: colonMAC(rawMAC), name: tag("friendlyName") ?? "", ip: ip,
                        transport: Int(cap["transport_protocol"] ?? "") ?? 3290,
                        wifiMAC: cap["macWifi"].map(colonMAC), token: nil, lastSeen: Date())
    }

    static func colonMAC(_ s: String) -> String {
        let flat = s.lowercased().filter(\.isHexDigit)
        guard flat.count == 12 else { return s.lowercased() }
        return stride(from: 0, to: 12, by: 2).map { i in
            let a = flat.index(flat.startIndex, offsetBy: i)
            return String(flat[a..<flat.index(a, offsetBy: 2)])
        }.joined(separator: ":")
    }

    /// Diffuse les TV trouvés au fil de l'eau : SSDP (rapide) + balayage du sous-réseau.
    static func scan(priority: [String]) -> AsyncStream<TVDevice> {
        AsyncStream { cont in
            let task = Task {
                let seen = Seen()
                func report(_ ip: String) async {
                    guard !Task.isCancelled, await seen.claimIP(ip), let tv = await probe(ip) else { return }
                    if await seen.claimMAC(tv.mac) { cont.yield(tv) }
                }
                await withTaskGroup(of: Void.self) { g in
                    g.addTask { for ip in priority { await report(ip) } }
                    g.addTask { for ip in await ssdp(timeout: 2.5) { await report(ip) } }
                    g.addTask {
                        let hosts = subnetHosts()
                        for chunk in stride(from: 0, to: hosts.count, by: 64).map({ Array(hosts[$0..<min($0 + 64, hosts.count)]) }) {
                            guard !Task.isCancelled else { return }
                            await withTaskGroup(of: Void.self) { cg in for ip in chunk { cg.addTask { await report(ip) } } }
                        }
                    }
                }
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    private actor Seen {
        var ips: Set<String> = []
        var macs: Set<String> = []
        func claimIP(_ ip: String) -> Bool { ips.insert(ip).inserted }
        func claimMAC(_ m: String) -> Bool { macs.insert(m).inserted }
    }

    /// Hôtes du /24 (au plus) de chaque interface active du Mac.
    private static func subnetHosts() -> [String] {
        var out: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let f = ptr.pointee
            guard let a = f.ifa_addr, a.pointee.sa_family == UInt8(AF_INET),
                  (f.ifa_flags & UInt32(IFF_UP)) != 0, (f.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
                  String(cString: f.ifa_name).hasPrefix("en") else { continue }
            let ip = a.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let base = ip & 0xFFFF_FF00
            for h in 1...254 where base | UInt32(h) != ip {
                let v = base | UInt32(h)
                out.append("\(v >> 24 & 0xFF).\(v >> 16 & 0xFF).\(v >> 8 & 0xFF).\(v & 0xFF)")
            }
        }
        return out
    }

    /// M-SEARCH SSDP : les TV VIDAA répondent avec une LOCATION sur le port 38400.
    private static func ssdp(timeout: TimeInterval) async -> [String] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
                guard fd >= 0 else { cont.resume(returning: []); return }
                defer { close(fd) }
                var tv = timeval(tv_sec: 0, tv_usec: 250_000)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                var dst = sockaddr_in()
                dst.sin_family = sa_family_t(AF_INET)
                dst.sin_port = in_port_t(1900).bigEndian
                inet_pton(AF_INET, "239.255.255.250", &dst.sin_addr)
                let msg = Array("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n".utf8)
                for _ in 0..<2 {
                    _ = withUnsafePointer(to: &dst) { p in
                        p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            sendto(fd, msg, msg.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
                var ips = Set<String>()
                var buf = [UInt8](repeating: 0, count: 4096)
                let end = Date().addingTimeInterval(timeout)
                while Date() < end {
                    var from = sockaddr_in()
                    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
                    let n = withUnsafeMutablePointer(to: &from) { p in
                        p.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buf, buf.count, 0, $0, &len) }
                    }
                    guard n > 0 else { continue }
                    let text = String(decoding: buf[0..<n], as: UTF8.self)
                    if text.contains(":38400/") || text.contains("His/") {
                        var a = from.sin_addr
                        var out = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        inet_ntop(AF_INET, &a, &out, socklen_t(out.count))
                        ips.insert(String(cString: out))
                    }
                }
                cont.resume(returning: Array(ips))
            }
        }
    }
}
