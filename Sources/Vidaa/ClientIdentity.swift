import Foundation
import Security

/// The shared VidaaApp client certificate (CN=VidaaAppAndroidV01, valid to 2034).
/// Every VIDAA mobile client presents this same identity; the TV's broker
/// requires it for mutual TLS.
enum ClientIdentity {
    /// P12 password, hardcoded in the vendor app's native library.
    private static let passphrase = "186e990688070325a1c4b0ce275d2388"

    private static let p12Base64 = """
        "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"
"""

    static func load() -> SecIdentity? {
        guard let data = Data(base64Encoded: p12Base64,
                              options: .ignoreUnknownCharacters) else { return nil }

        var items: CFArray?
        let options = [kSecImportExportPassphrase as String: passphrase] as CFDictionary
        guard SecPKCS12Import(data as CFData, options, &items) == errSecSuccess,
              let entries = items as? [[String: Any]],
              let identity = entries.first?[kSecImportItemIdentity as String]
        else { return nil }

        return (identity as! SecIdentity)
    }
}
