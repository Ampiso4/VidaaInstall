import Foundation
import CryptoKit

/// Auth algorithm variant, selected from the TV's UPnP `transport_protocol`.
enum AuthMethod {
    case legacy   // < 3000      : no XOR username, legacy suffix
    case middle   // 3000..3289  : XOR username,  legacy suffix
    case modern   // >= 3290     : XOR username,  modern suffix (default when unknown)
}

enum VidaaConstants {
    static let mqttPort: UInt16 = 36669
    static let discoveryPort: UInt16 = 36671
    static let upnpPort: UInt16 = 38400
    static let pattern = "38D65DC30F45109A369A86FCE866A85B"
    static let valueSuffixModern = "h!i@s#$v%i^d&a*a"
    static let valueSuffixLegacy = "h*i&s%e!r^v0i1c9"
    static let timeXOR: UInt64 = 0x5698_1477_2b03_a968
    static let brand = "his"
}

struct MQTTCredentials {
    let clientId: String
    let username: String
    let password: String
}

/// MD5 is mandated by the VIDAA broker's credential scheme; it is not a
/// security choice here.
func md5Upper(_ s: String) -> String {
    Insecure.MD5.hash(data: Data(s.utf8))
        .map { String(format: "%02X", $0) }
        .joined()
}

/// Reproduces `libmqttcrypt.so` credential generation.
/// - `uuid` keeps its original case: the race hash is case-sensitive.
func generateCredentials(
    uuid rawUUID: String,
    auth: AuthMethod,
    operation: String = "vidaacommon",
    timestamp: Int = Int(Date().timeIntervalSince1970)
) -> MQTTCredentials {
    var uuid = rawUUID
    let flat = uuid.replacingOccurrences(of: ":", with: "")
    if !uuid.contains(":"), !uuid.contains("-"), flat.count == 12 {
        uuid = stride(from: 0, to: 12, by: 2).map {
            let i = flat.index(flat.startIndex, offsetBy: $0)
            let j = flat.index(i, offsetBy: 2)
            return String(flat[i..<j])
        }.joined(separator: ":")
    }

    let raceMD5 = String(md5Upper("\(VidaaConstants.pattern)$\(uuid)").prefix(6))
    let clientId = "\(uuid)$\(VidaaConstants.brand)$\(raceMD5)_\(operation)_001"

    let username: String
    if auth == .legacy {
        username = "\(VidaaConstants.brand)$\(timestamp)"
    } else {
        let xorTime = UInt64(timestamp) ^ VidaaConstants.timeXOR
        username = "\(VidaaConstants.brand)$\(xorTime)"
    }

    let suffix = auth == .modern ? VidaaConstants.valueSuffixModern : VidaaConstants.valueSuffixLegacy
    let digitSum = String(abs(timestamp)).reduce(0) { $0 + ($1.wholeNumberValue ?? 0) }
    let valueMD5 = String(md5Upper("\(VidaaConstants.brand)\(digitSum % 10)\(suffix)").prefix(6))
    let password = md5Upper("\(timestamp)$\(valueMD5)")

    return MQTTCredentials(clientId: clientId, username: username, password: password)
}
