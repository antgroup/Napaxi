import Foundation

// iOS adapter parity for the Flutter local A2A pairing surface
// (`packages/flutter/lib/api/a2a_local_pairing_session.dart` and
// `a2a_local_pairing_store.dart`). The cryptography lives in
// `NapaxiA2APairing` (A2APairing.swift); this file owns the non-UI pairing
// orchestration — local identity/secret persistence, per-peer remote-secret
// storage, shared-secret derivation, paired-state checks, invite build/decode,
// and inbound-message routing. UI concerns stay in the host. See
// `docs/sdk-adapter-parity.md`.

/// The action a host should take for an inbound A2A peer message, decided by
/// `NapaxiA2ALocalPairingSession.classifyInboundMessage`. Mirrors the Flutter
/// `A2AInboundRoute` enum so every adapter routes inbound messages identically.
public enum NapaxiA2AInboundRoute: String, Codable, Equatable, Sendable {
    /// Already seen this message id — ignore.
    case duplicate
    /// A loopback self-test message — ignore.
    case loopback
    /// A `pairing_accept` handshake message.
    case pairingAccept
    /// A `pairing_request` handshake message.
    case pairingRequest
    /// A `task_request` — record it and (if delivered) send a receipt.
    case taskRequest
    /// Any other recorded message kind (progress, result, ack, ...).
    case other
}

/// Non-secret key/value persistence seam for local A2A pairing bookkeeping
/// (the local public key). Mirrors the Flutter `NapaxiA2AKeyValueStore`.
public protocol NapaxiA2AKeyValueStore: Sendable {
    func read(_ key: String) async throws -> String?
    func write(_ key: String, value: String) async throws
    func delete(_ key: String) async throws
}

/// Secret persistence seam for local A2A pairing secrets (the local pairing
/// secret and per-peer remote secrets). Mirrors the Flutter
/// `NapaxiA2ASecretStore`; back it with Keychain on device.
public protocol NapaxiA2ASecretStore: Sendable {
    func read(_ key: String) async throws -> String?
    func write(_ key: String, value: String) async throws
    func delete(_ key: String) async throws
}

/// Persistence for local A2A pairing identity and secrets. Mirrors the Flutter
/// `A2ALocalPairingStore`: non-secret values go through a
/// `NapaxiA2AKeyValueStore`, secrets through a `NapaxiA2ASecretStore`. This
/// reuses the existing config store seam (`NapaxiConfigStore`) so a host can
/// back secrets with the Keychain.
public final class NapaxiA2ALocalPairingStore: @unchecked Sendable {
    // On-device storage keys. The `.v1`/`.v2` suffixes are the on-device
    // schema, not the cross-device wire contract — they must match the Flutter
    // and Android adapters so a single device's identity survives adapter swaps.
    public static let publicKeyKey = "napaxi.a2a_local.public_key.v1"
    public static let pairingSecretKey = "napaxi.a2a_local.pairing_secret.v1"
    public static let pairedPeerSecretsKey = "napaxi.a2a_local.paired_peer_secrets.v2"

    private let keyValueStore: NapaxiA2AKeyValueStore
    private let secretStore: NapaxiA2ASecretStore

    public init(keyValueStore: NapaxiA2AKeyValueStore, secretStore: NapaxiA2ASecretStore) {
        self.keyValueStore = keyValueStore
        self.secretStore = secretStore
    }

    /// Host-grade store: non-secret values in `UserDefaults`, secrets in the
    /// Keychain. Mirrors the Flutter `.secure()` constructor.
    public static func secure() -> NapaxiA2ALocalPairingStore {
        #if canImport(Security)
        return NapaxiA2ALocalPairingStore(
            keyValueStore: NapaxiUserDefaultsConfigKeyValueStore(),
            secretStore: NapaxiKeychainConfigSecretStore(service: "dev.napaxi.a2a_local")
        )
        #else
        let memory = NapaxiMemoryConfigStore()
        return NapaxiA2ALocalPairingStore(keyValueStore: memory, secretStore: memory)
        #endif
    }

    /// Demo-grade store: everything in plaintext `UserDefaults`. Named
    /// explicitly so a real host cannot select it by accident — do not ship.
    /// Mirrors the Flutter `.insecureSharedPreferences()` constructor.
    public static func insecureSharedPreferences() -> NapaxiA2ALocalPairingStore {
        let store = NapaxiUserDefaultsConfigKeyValueStore()
        return NapaxiA2ALocalPairingStore(
            keyValueStore: store,
            secretStore: NapaxiConfigSecretStoreFromKeyValue(store)
        )
    }

    /// In-memory store for tests. Mirrors the Flutter `.memory()` constructor.
    public static func memory() -> NapaxiA2ALocalPairingStore {
        let store = NapaxiMemoryConfigStore()
        return NapaxiA2ALocalPairingStore(keyValueStore: store, secretStore: store)
    }

    public func readLocalPublicKey() async throws -> String? {
        try await keyValueStore.read(Self.publicKeyKey)
    }

    public func writeLocalPublicKey(_ value: String) async throws {
        try await keyValueStore.write(Self.publicKeyKey, value: value)
    }

    public func readLocalPairingSecret() async throws -> String? {
        try await secretStore.read(Self.pairingSecretKey)
    }

    public func writeLocalPairingSecret(_ value: String) async throws {
        try await secretStore.write(Self.pairingSecretKey, value: value)
    }

    /// Load the `pairingKey -> remoteSecret` map. Tolerant of malformed JSON
    /// (returns empty) — never throws.
    public func loadRemotePairingSecrets() async throws -> [String: String] {
        let raw = try await secretStore.read(Self.pairedPeerSecretsKey)
        return Self.decodeSecretMap(raw)
    }

    public func readRemotePairingSecret(_ pairingKey: String) async throws -> String? {
        let secrets = try await loadRemotePairingSecrets()
        let value = secrets[pairingKey]
        return (value?.isEmpty != false) ? nil : value
    }

    public func writeRemotePairingSecret(_ pairingKey: String, secret: String) async throws {
        var secrets = try await loadRemotePairingSecrets()
        secrets[pairingKey] = secret
        let map = secrets.mapValues { NapaxiJSONValue.string($0) }
        try await secretStore.write(Self.pairedPeerSecretsKey, value: (try? map.jsonString()) ?? "{}")
    }

    /// One-time migration of legacy plaintext keys into this store. Safe to call
    /// repeatedly: it only acts when a legacy key is present and the new key is
    /// absent, and clears the legacy key after. Mirrors the Flutter
    /// `migrateLegacyPlaintextIfPresent()` (the iOS host historically had no
    /// legacy plaintext keys, so this is a no-op placeholder kept for parity).
    public func migrateLegacyPlaintextIfPresent() async throws {
        // The iOS adapter never shipped the demo's plaintext SharedPreferences
        // keys; there is nothing to migrate. Kept for cross-adapter parity so a
        // host can call the same upgrade hook on every platform.
    }

    private static func decodeSecretMap(_ raw: String?) -> [String: String] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [:]
        }
        guard let object = try? NapaxiRawJSON(jsonString: raw).value.objectValue else {
            return [:]
        }
        var result: [String: String] = [:]
        for (key, value) in object {
            // Mirror the Flutter `_decodeSecretMap`, which coerces every value
            // (`entry.value?.toString() ?? ''`) and drops only empties, so a
            // legacy/externally-written numeric or bool entry survives as text
            // rather than being silently dropped.
            let string = stringifySecretValue(value)
            if !string.isEmpty {
                result[key] = string
            }
        }
        return result
    }

    private static func stringifySecretValue(_ value: NapaxiJSONValue) -> String {
        switch value {
        case .string(let string): return string
        case .number(let number):
            return number.rounded() == number ? String(Int(number)) : String(number)
        case .bool(let bool): return String(bool)
        case .null: return ""
        case .array, .object: return (try? NapaxiRawJSON(value).jsonString()) ?? ""
        }
    }
}

/// Adapts a `NapaxiA2AKeyValueStore` as a `NapaxiA2ASecretStore` for the
/// explicitly-insecure plaintext fallback.
private struct NapaxiConfigSecretStoreFromKeyValue: NapaxiA2ASecretStore {
    let store: NapaxiA2AKeyValueStore
    init(_ store: NapaxiA2AKeyValueStore) { self.store = store }
    func read(_ key: String) async throws -> String? { try await store.read(key) }
    func write(_ key: String, value: String) async throws { try await store.write(key, value: value) }
    func delete(_ key: String) async throws { try await store.delete(key) }
}

// The config-store seams already conform structurally; bridge them to the A2A
// store protocols so a host can reuse one secure backend for both.
extension NapaxiMemoryConfigStore: NapaxiA2AKeyValueStore, NapaxiA2ASecretStore {}
extension NapaxiUserDefaultsConfigKeyValueStore: NapaxiA2AKeyValueStore {}
#if canImport(Security)
extension NapaxiKeychainConfigSecretStore: NapaxiA2ASecretStore {}
#endif

/// Reusable local A2A pairing orchestration, lifted out of the demo so each
/// host calls a thin API instead of re-deriving the handshake. Mirrors the
/// Flutter `A2ALocalPairingSession`.
public final class NapaxiA2ALocalPairingSession: @unchecked Sendable {
    private let store: NapaxiA2ALocalPairingStore
    private let loadSavedPeers: @Sendable () async throws -> [NapaxiA2APeer]
    private let lock = NSLock()
    private var knownPeers: [String: NapaxiA2ALocalPeerAdvertisement] = [:]
    // Insertion order of first-seen peer ids. The Flutter `_knownPeers` is a
    // LinkedHashMap (insertion-ordered), so its `.values` first-match scan is
    // deterministic; a Swift Dictionary is unordered, so we track order here to
    // reproduce the same first-match on peer-id-prefix / agent-id collisions.
    private var knownPeerOrder: [String] = []
    private var seenMessageIds: Set<String> = []

    public init(
        store: NapaxiA2ALocalPairingStore? = nil,
        loadSavedPeers: @escaping @Sendable () async throws -> [NapaxiA2APeer]
    ) {
        self.store = store ?? NapaxiA2ALocalPairingStore.secure()
        self.loadSavedPeers = loadSavedPeers
    }

    /// The backing store, exposed so a host can run the one-time migration on
    /// upgrade.
    public var pairingStore: NapaxiA2ALocalPairingStore { store }

    /// Register peers the host has discovered so later `resolve*` calls can find
    /// them. Idempotent.
    public func rememberPeers(_ peers: [NapaxiA2ALocalPeerAdvertisement]) {
        lock.lock()
        defer { lock.unlock() }
        for peer in peers where !peer.peerId.isEmpty {
            if knownPeers[peer.peerId] == nil { knownPeerOrder.append(peer.peerId) }
            knownPeers[peer.peerId] = peer
        }
    }

    /// All known peers, sorted by a stable key (display name then peer id).
    public func sortedKnownPeers() -> [NapaxiA2ALocalPeerAdvertisement] {
        lock.lock()
        let peers = Array(knownPeers.values)
        lock.unlock()
        return peers.sorted { lhs, rhs in
            let byLabel = peerSortLabel(lhs).compare(peerSortLabel(rhs))
            if byLabel != .orderedSame { return byLabel == .orderedAscending }
            return lhs.peerId < rhs.peerId
        }
    }

    /// Resolve a known (discovered) peer by exact peer id, peer-id prefix, or
    /// agent id. Returns nil if nothing matches.
    public func resolveKnownPeer(_ target: String) -> NapaxiA2ALocalPeerAdvertisement? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let exact = knownPeers[trimmed] { return exact }
        // Scan in insertion order to match Flutter's LinkedHashMap first-match.
        for key in knownPeerOrder {
            guard let peer = knownPeers[key] else { continue }
            if peer.peerId.hasPrefix(trimmed) || peer.agentId == trimmed {
                return peer
            }
        }
        return nil
    }

    // --- Local identity & secrets -------------------------------------------

    /// The local public key, generated and persisted on first use.
    public func localPublicKey() async throws -> String {
        if let existing = try await store.readLocalPublicKey(), !existing.isEmpty {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 24)
        var generator = SystemRandomNumberGenerator()
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: 0...255, using: &generator)
        }
        let created = Self.base64UrlNoPad(Data(bytes))
        try await store.writeLocalPublicKey(created)
        return created
    }

    /// The local pairing secret (normalized hex), generated and persisted on
    /// first use.
    public func localPairingSecret() async throws -> String {
        let existing = NapaxiA2APairing.normalizePairingSecret(
            try await store.readLocalPairingSecret() ?? ""
        )
        if !existing.isEmpty { return existing }
        let created = NapaxiA2APairing.generateLocalPairingSecret()
        try await store.writeLocalPairingSecret(created)
        return created
    }

    /// The stored remote pairing secret for `peer`, or nil if not paired.
    public func remotePairingSecret(_ peer: NapaxiA2ALocalPeerAdvertisement) async throws -> String? {
        let value = NapaxiA2APairing.normalizePairingSecret(
            try await store.readRemotePairingSecret(pairingKey(peer)) ?? ""
        )
        return value.isEmpty ? nil : value
    }

    /// Persist the remote pairing secret for `peer`.
    public func saveRemotePairingSecret(
        _ peer: NapaxiA2ALocalPeerAdvertisement,
        secret: String
    ) async throws {
        try await store.writeRemotePairingSecret(
            pairingKey(peer),
            secret: NapaxiA2APairing.normalizePairingSecret(secret)
        )
    }

    // --- Pairing state & shared secret --------------------------------------

    /// Is `peer` paired? True if a saved peer already carries a shared secret,
    /// or if we hold a remote pairing secret for it.
    public func isPeerPaired(_ peer: NapaxiA2ALocalPeerAdvertisement) async throws -> Bool {
        if try await savedSharedSecret(peer) != nil { return true }
        return (try await remotePairingSecret(peer)) != nil
    }

    /// The shared secret to use with `peer`: a previously saved one if present,
    /// otherwise derived now. Returns nil when not enough material is available.
    public func sharedSecretForPeer(
        _ peer: NapaxiA2ALocalPeerAdvertisement,
        localPeerId: String
    ) async throws -> String? {
        if let saved = try await savedSharedSecret(peer) { return saved }
        guard let remote = try await remotePairingSecret(peer), !localPeerId.isEmpty else {
            return nil
        }
        return NapaxiA2APairing.deriveLocalSharedSecret(
            localPeerId: localPeerId,
            localPublicKey: try await localPublicKey(),
            localPairingSecret: try await localPairingSecret(),
            remotePeerId: peer.peerId,
            remotePublicKey: peer.publicKey,
            remotePairingSecret: remote
        )
    }

    /// Resolve a *paired* peer by id/prefix/agent id, consulting both the
    /// discovered cache and the durable saved-peer list. Returns nil if no
    /// match is paired.
    public func resolvePairedPeer(_ target: String) async throws -> NapaxiA2ALocalPeerAdvertisement? {
        if let scanned = resolveKnownPeer(target), try await isPeerPaired(scanned) {
            return scanned
        }
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        for saved in try await loadSavedPeers() {
            guard let peer = advertisementFromSavedPeer(saved) else { continue }
            lock.lock()
            if knownPeers[peer.peerId] == nil { knownPeerOrder.append(peer.peerId) }
            knownPeers[peer.peerId] = peer
            lock.unlock()
            let matches = peer.peerId == trimmed
                || peer.peerId.hasPrefix(trimmed)
                || saved.agentId == trimmed
            if matches, try await isPeerPaired(peer) { return peer }
        }
        return nil
    }

    // --- Invite codec (delegates to the shared wire contract) ---------------

    /// Build an invite for the local peer.
    public func buildInvite(
        localPeerId: String,
        agentId: String,
        displayName: String,
        endpoint: String,
        transport: String,
        createdAt: String = ""
    ) async throws -> NapaxiA2AInvite {
        NapaxiA2AInvite(
            peerId: localPeerId,
            agentId: agentId,
            displayName: displayName,
            publicKey: try await localPublicKey(),
            pairingSecret: try await localPairingSecret(),
            endpoint: endpoint,
            transport: transport,
            createdAt: createdAt
        )
    }

    /// Decode any pasted/scanned invite form. See
    /// `NapaxiA2AInvite.tryDecodePayload`.
    public func decodeInvite(_ rawValue: String) -> NapaxiA2AInvite? {
        NapaxiA2AInvite.tryDecodePayload(rawValue)
    }

    // --- Inbound message routing (decision only; UI stays in the host) -------

    /// Classify an inbound peer message into the action the host should take.
    /// Dedup is stateful: the first call for a given message id advances the
    /// seen set; later calls for the same id return `.duplicate`.
    public func classifyInboundMessage(_ message: NapaxiA2APeerMessage) -> NapaxiA2AInboundRoute {
        lock.lock()
        let inserted = seenMessageIds.insert(message.messageId).inserted
        lock.unlock()
        if !inserted { return .duplicate }
        if message.payload["purpose"]?.stringValue == "local_a2a_loopback" {
            return .loopback
        }
        switch message.kind {
        case "pairing_accept": return .pairingAccept
        case "pairing_request": return .pairingRequest
        case "task_request": return .taskRequest
        default: return .other
        }
    }

    // --- Internals -----------------------------------------------------------

    private func pairingKey(_ peer: NapaxiA2ALocalPeerAdvertisement) -> String {
        NapaxiA2APairing.pairingKey(peerId: peer.peerId, publicKey: peer.publicKey)
    }

    private func peerSortLabel(_ peer: NapaxiA2ALocalPeerAdvertisement) -> String {
        let name = peer.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name.lowercased() }
        let agent = peer.agentId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !agent.isEmpty { return agent.lowercased() }
        return peer.peerId.lowercased()
    }

    private func savedSharedSecret(_ peer: NapaxiA2ALocalPeerAdvertisement) async throws -> String? {
        for saved in try await loadSavedPeers() where saved.peerId == peer.peerId {
            let secret = saved.sharedSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            if !secret.isEmpty { return secret }
        }
        return nil
    }

    private func advertisementFromSavedPeer(_ peer: NapaxiA2APeer) -> NapaxiA2ALocalPeerAdvertisement? {
        guard let endpoint = peer.endpoints.first,
              !peer.peerId.isEmpty,
              !endpoint.uri.isEmpty else {
            return nil
        }
        return NapaxiA2ALocalPeerAdvertisement(json: [
            "peerId": .string(peer.peerId),
            "agentId": .string(peer.agentId),
            "displayName": .string(peer.displayName),
            "publicKey": .string(peer.publicKey),
            "transport": .string(endpoint.transport),
            "endpoint": .string(endpoint.uri),
        ])
    }

    private static func base64UrlNoPad(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// The advertisement view of the inviting peer, for transport/discovery APIs.
/// Mirrors the Flutter `A2AInvite.toPeerAdvertisement()`.
public extension NapaxiA2AInvite {
    func toPeerAdvertisement() -> NapaxiA2ALocalPeerAdvertisement {
        var json: [String: NapaxiJSONValue] = [
            "peerId": .string(peerId),
            "agentId": .string(agentId),
            "displayName": .string(displayName),
            "publicKey": .string(publicKey),
            "endpoint": .string(endpoint),
        ]
        // Preserve the model's transport default when the invite did not carry
        // one (`NapaxiA2ALocalPeerAdvertisement` defaults transport to
        // `lan_tcp_jsonl` for an absent key).
        if !transport.isEmpty {
            json["transport"] = .string(transport)
        }
        return NapaxiA2ALocalPeerAdvertisement(json: json)
    }
}

/// The core A2A transport identifier for this advertisement's wire transport.
/// Mirrors the Flutter `A2ALocalPeerAdvertisement.coreTransport` getter and its
/// `_coreA2ATransport` mapping so adapters normalize transports identically.
public extension NapaxiA2ALocalPeerAdvertisement {
    var coreTransport: String {
        switch transport.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "lan_tcp_jsonl", "tcp_jsonl", "jsonl_tcp": return "lan_tcp"
        case "lan_websocket", "websocket", "ws": return "lan_web_socket"
        case "tcp": return "lan_tcp"
        case "bluetooth": return "ble"
        case "deeplink": return "deep_link"
        case "host": return "host_provided"
        case let value where !value.isEmpty: return value
        default: return "unknown"
        }
    }
}

// MARK: - Flutter migration aliases

public typealias A2AInboundRoute = NapaxiA2AInboundRoute
public typealias A2ALocalPairingSession = NapaxiA2ALocalPairingSession
public typealias A2ALocalPairingStore = NapaxiA2ALocalPairingStore
// Migration aliases removed: NapaxiA2A* renamed to NapaxiA2A* for consistency.
