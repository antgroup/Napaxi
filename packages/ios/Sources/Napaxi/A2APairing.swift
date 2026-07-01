import CryptoKit
import Foundation

public enum NapaxiA2APairing {
    public static func generateLocalPairingSecret(byteLength: Int = 16) -> String {
        let length = min(max(byteLength, 16), 64)
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<length).map { _ in UInt8.random(in: 0...255, using: &generator) }
        return hexString(bytes)
    }

    public static func normalizePairingSecret(_ value: String) -> String {
        value
            .unicodeScalars
            .filter { scalar in
                (48...57).contains(Int(scalar.value))
                    || (65...70).contains(Int(scalar.value))
                    || (97...102).contains(Int(scalar.value))
            }
            .map { String($0).uppercased() }
            .joined()
    }

    public static func formatPairingSecret(_ value: String) -> String {
        let normalized = normalizePairingSecret(value)
        guard !normalized.isEmpty else { return "" }
        var chunks: [String] = []
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let end = normalized.index(index, offsetBy: 4, limitedBy: normalized.endIndex) ?? normalized.endIndex
            chunks.append(String(normalized[index..<end]))
            index = end
        }
        return chunks.joined(separator: " ")
    }

    public static func pairingCodeFromIdentity(peerId: String, publicKey: String) -> String {
        let hex = sha256Hex(identityMaterial(peerId: peerId, publicKey: publicKey))
        return "\(hex.prefix(4)) \(hex.dropFirst(4).prefix(4))"
    }

    public static func pairingKey(peerId: String, publicKey: String) -> String {
        identityMaterial(peerId: peerId, publicKey: publicKey)
    }

    public static func deriveLocalSharedSecret(
        localPeerId: String,
        localPublicKey: String,
        localPairingSecret: String,
        remotePeerId: String,
        remotePublicKey: String,
        remotePairingSecret: String
    ) -> String {
        let identities = [
            identityMaterial(peerId: localPeerId, publicKey: localPublicKey),
            identityMaterial(peerId: remotePeerId, publicKey: remotePublicKey),
        ].sorted()
        let secrets = [
            normalizePairingSecret(localPairingSecret),
            normalizePairingSecret(remotePairingSecret),
        ].sorted()
        return "tofu-hmac-v2:\(sha256Hex((identities + secrets).joined(separator: "|")))"
    }

    private static func identityMaterial(peerId: String, publicKey: String) -> String {
        let material = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(peerId)|\(material.isEmpty ? peerId : material)"
    }

    private static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return hexString(digest)
    }

    private static func hexString<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02X", $0) }.joined()
    }
}

/// Decoded local A2A pairing invite — the iOS binding of the shared wire
/// contract pinned in Rust core (`napaxi_core::api::a2a::local_pairing_contract`)
/// and mirrored by the Flutter `A2AInvite` codec. Field names, the QR prefix,
/// and the required identity fields must match the cross-adapter fixture at
/// `packages/api_contract/fixtures/a2a/local_pairing_invite.json`.
public struct NapaxiA2AInvite: Equatable, Sendable {
    public static let qrPrefix = "napaxi-a2a-invite:"
    public static let currentVersion = 1

    public var version: Int
    public var peerId: String
    public var agentId: String
    public var displayName: String
    public var publicKey: String
    public var pairingSecret: String
    public var endpoint: String
    public var transport: String
    public var createdAt: String

    public init(
        version: Int = currentVersion,
        peerId: String,
        agentId: String = "",
        displayName: String = "",
        publicKey: String,
        pairingSecret: String,
        endpoint: String = "",
        transport: String = "",
        createdAt: String = ""
    ) {
        self.version = version
        self.peerId = peerId
        self.agentId = agentId
        self.displayName = displayName
        self.publicKey = publicKey
        self.pairingSecret = pairingSecret
        self.endpoint = endpoint
        self.transport = transport
        self.createdAt = createdAt
    }

    /// The flat JSON object form (the value base64url-encoded into the code).
    public func toJson() -> [String: Any] {
        [
            "v": version,
            "peerId": peerId,
            "agentId": agentId,
            "displayName": displayName,
            "publicKey": publicKey,
            "pairingSecret": pairingSecret,
            "endpoint": endpoint,
            "transport": transport,
            "createdAt": createdAt,
        ]
    }

    /// Encode to the bare invite code (base64url, no padding).
    public func toCode() -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: toJson(),
            options: [.sortedKeys]
        ) else { return "" }
        return Self.base64UrlNoPad(data)
    }

    /// Encode to the full QR / deep-link payload (with the prefix).
    public func toQrPayload() -> String { "\(Self.qrPrefix)\(toCode())" }

    /// Decode a bare invite code (base64url JSON). Returns nil on malformed
    /// input or when a required identity field is missing — never throws.
    public static func tryDecodeCode(_ code: String) -> NapaxiA2AInvite? {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              let data = base64UrlDecode(normalized),
              let object = try? JSONSerialization.jsonObject(with: data),
              let map = object as? [String: Any]
        else { return nil }

        let peerId = stringValue(map["peerId"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let pairingSecret = stringValue(map["pairingSecret"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let publicKey = stringValue(map["publicKey"]).trimmingCharacters(in: .whitespacesAndNewlines)
        // An invite without a peer id, public key, or pairing secret cannot
        // drive a handshake — reject rather than return a half-built record.
        guard !peerId.isEmpty, !pairingSecret.isEmpty, !publicKey.isEmpty else { return nil }

        let version = (map["v"] as? Int) ?? (map["v"] as? NSNumber)?.intValue ?? currentVersion
        return NapaxiA2AInvite(
            version: version,
            peerId: peerId,
            agentId: stringValue(map["agentId"]),
            displayName: stringValue(map["displayName"]),
            publicKey: publicKey,
            pairingSecret: pairingSecret,
            endpoint: stringValue(map["endpoint"]),
            transport: stringValue(map["transport"]),
            createdAt: stringValue(map["createdAt"])
        )
    }

    /// Decode a full QR payload (with prefix), a `/a2a join <code>` line, or a
    /// bare code. Returns nil when nothing decodes — never throws.
    public static func tryDecodePayload(_ rawValue: String) -> NapaxiA2AInvite? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix(qrPrefix) {
            return tryDecodeCode(String(value.dropFirst(qrPrefix.count)))
        }
        if let code = joinCommandCode(value) {
            return tryDecodeCode(code)
        }
        return tryDecodeCode(value)
    }

    private static func stringValue(_ value: Any?) -> String {
        if let string = value as? String { return string }
        return ""
    }

    private static func joinCommandCode(_ value: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "(?:^|\\s)/a2a\\s+join\\s+([A-Za-z0-9_-]+)",
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              let codeRange = Range(match.range(at: 1), in: value)
        else { return nil }
        return String(value[codeRange])
    }

    private static func base64UrlNoPad(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64UrlDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
