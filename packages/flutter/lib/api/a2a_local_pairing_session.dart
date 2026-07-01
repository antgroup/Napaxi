import 'dart:convert';
import 'dart:math' as math;

import '../models/a2a.dart';
import 'a2a_invite.dart';
import 'a2a_local_pairing_store.dart';
import 'a2a_pairing.dart';

/// The action a host should take for an inbound A2A peer message, decided by
/// [A2ALocalPairingSession.classifyInboundMessage]. Keeps the routing decision
/// in the SDK (shared across adapters) while the host owns the UI/side effects.
enum A2AInboundRoute {
  /// Already seen this message id — ignore.
  duplicate,

  /// A loopback self-test message — ignore.
  loopback,

  /// A `pairing_accept` handshake message.
  pairingAccept,

  /// A `pairing_request` handshake message.
  pairingRequest,

  /// A `task_request` — record it and (if delivered) send a receipt.
  taskRequest,

  /// Any other recorded message kind (progress, result, ack, ...).
  other,
}

/// Reusable local A2A pairing orchestration, lifted out of the demo so each
/// host (Flutter demo, Android, iOS) calls a thin API instead of re-deriving
/// the handshake.
///
/// This owns the parts of the local-pairing flow that are NOT UI: the local
/// identity (public key) and pairing secret, per-peer remote-secret storage,
/// shared-secret derivation timing, the paired-state check, and invite
/// build/decode. It wraps:
///   - [A2APairing] for the (pure, deterministic) cryptography,
///   - [A2ALocalPairingStore] for the secure-storage seam, and
///   - a caller-supplied lookup of already-saved peers (the durable peer list
///     the SDK persists), so the session can find an existing shared secret
///     without reaching into engine internals.
///
/// UI concerns — slash parsing, dialogs, QR rendering, chat notices — stay in
/// the host. See `docs/a2a-local-pairing-followups.md` and
/// `docs/sdk-adapter-parity.md`.
class A2ALocalPairingSession {
  A2ALocalPairingSession({
    A2ALocalPairingStore? store,
    required Future<List<A2APeer>> Function() loadSavedPeers,
  })  : _store = store ?? A2ALocalPairingStore.secure(),
        _loadSavedPeers = loadSavedPeers;

  final A2ALocalPairingStore _store;
  final Future<List<A2APeer>> Function() _loadSavedPeers;

  /// The backing store, exposed so a host can run a one-time migration
  /// (`store.migrateLegacyPlaintextIfPresent()`) on upgrade.
  A2ALocalPairingStore get store => _store;

  /// Discovered/known peers cache, keyed by peer id. Populated as the host
  /// resolves peers; used to look up a peer by id/prefix/agent id.
  final Map<String, A2ALocalPeerAdvertisement> _knownPeers = {};

  /// Inbound message-id dedup set. Inbound transport can redeliver; the host
  /// routes each message id at most once.
  final Set<String> _seenMessageIds = {};

  /// Register peers the host has discovered so later `resolve*` calls can find
  /// them. Idempotent.
  void rememberPeers(Iterable<A2ALocalPeerAdvertisement> peers) {
    for (final peer in peers) {
      if (peer.peerId.isNotEmpty) _knownPeers[peer.peerId] = peer;
    }
  }

  /// All known peers, sorted by a stable key (display name then peer id) so the
  /// host renders a deterministic order without re-implementing the sort.
  List<A2ALocalPeerAdvertisement> sortedKnownPeers() {
    final peers = _knownPeers.values.toList();
    peers.sort((a, b) {
      final byLabel = _peerSortLabel(a).compareTo(_peerSortLabel(b));
      return byLabel != 0 ? byLabel : a.peerId.compareTo(b.peerId);
    });
    return peers;
  }

  /// Resolve a known (discovered) peer by exact peer id, peer-id prefix, or
  /// agent id. Returns null if nothing matches.
  A2ALocalPeerAdvertisement? resolveKnownPeer(String target) {
    final trimmed = target.trim();
    if (trimmed.isEmpty) return null;
    final exact = _knownPeers[trimmed];
    if (exact != null) return exact;
    for (final peer in _knownPeers.values) {
      if (peer.peerId.startsWith(trimmed) || peer.agentId == trimmed) {
        return peer;
      }
    }
    return null;
  }

  // --- Local identity & secrets -------------------------------------------

  /// The local public key, generated and persisted on first use.
  Future<String> localPublicKey() async {
    final existing = await _store.readLocalPublicKey();
    if (existing != null && existing.isNotEmpty) return existing;
    final random = math.Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    final created = base64UrlEncode(bytes).replaceAll('=', '');
    await _store.writeLocalPublicKey(created);
    return created;
  }

  /// The local pairing secret (normalized hex), generated and persisted on
  /// first use.
  Future<String> localPairingSecret() async {
    final existing = A2APairing.normalizePairingSecret(
      await _store.readLocalPairingSecret() ?? '',
    );
    if (existing.isNotEmpty) return existing;
    final created = A2APairing.generateLocalPairingSecret();
    await _store.writeLocalPairingSecret(created);
    return created;
  }

  /// The stored remote pairing secret for [peer], or null if not paired.
  Future<String?> remotePairingSecret(A2ALocalPeerAdvertisement peer) async {
    final value = A2APairing.normalizePairingSecret(
      await _store.readRemotePairingSecret(_pairingKey(peer)) ?? '',
    );
    return value.isEmpty ? null : value;
  }

  /// Persist the remote pairing secret for [peer].
  Future<void> saveRemotePairingSecret(
    A2ALocalPeerAdvertisement peer,
    String secret,
  ) {
    return _store.writeRemotePairingSecret(
      _pairingKey(peer),
      A2APairing.normalizePairingSecret(secret),
    );
  }

  // --- Pairing state & shared secret --------------------------------------

  /// Is [peer] paired? True if a saved peer already carries a shared secret,
  /// or if we hold a remote pairing secret for it.
  Future<bool> isPeerPaired(A2ALocalPeerAdvertisement peer) async {
    if (await _savedSharedSecret(peer) != null) return true;
    return (await remotePairingSecret(peer)) != null;
  }

  /// The shared secret to use with [peer]: a previously saved one if present,
  /// otherwise derived now from local + remote pairing secrets. Returns null
  /// when not enough material is available (no remote secret, or no local peer
  /// id yet).
  Future<String?> sharedSecretForPeer(
    A2ALocalPeerAdvertisement peer, {
    required String localPeerId,
  }) async {
    final saved = await _savedSharedSecret(peer);
    if (saved != null) return saved;
    final remote = await remotePairingSecret(peer);
    if (remote == null || localPeerId.isEmpty) return null;
    return A2APairing.deriveLocalSharedSecret(
      localPeerId: localPeerId,
      localPublicKey: await localPublicKey(),
      localPairingSecret: await localPairingSecret(),
      remotePeerId: peer.peerId,
      remotePublicKey: peer.publicKey,
      remotePairingSecret: remote,
    );
  }

  /// Resolve a *paired* peer by id/prefix/agent id, consulting both the
  /// discovered cache and the durable saved-peer list. Returns null if no
  /// match is paired.
  Future<A2ALocalPeerAdvertisement?> resolvePairedPeer(String target) async {
    final scanned = resolveKnownPeer(target);
    if (scanned != null && await isPeerPaired(scanned)) return scanned;

    final trimmed = target.trim();
    for (final saved in await _loadSavedPeers()) {
      final peer = _advertisementFromSavedPeer(saved);
      if (peer == null) continue;
      _knownPeers[peer.peerId] = peer;
      final matches = peer.peerId == trimmed ||
          peer.peerId.startsWith(trimmed) ||
          saved.agentId == trimmed;
      if (matches && await isPeerPaired(peer)) return peer;
    }
    return null;
  }

  // --- Invite codec (delegates to the shared wire contract) ---------------

  /// Build an invite for the local peer. Returns the [A2AInvite] whose
  /// `toQrPayload()` / `toCode()` produce the shareable strings.
  Future<A2AInvite> buildInvite({
    required String localPeerId,
    required String agentId,
    required String displayName,
    required String endpoint,
    required String transport,
    String createdAt = '',
  }) async {
    return A2AInvite(
      peerId: localPeerId,
      agentId: agentId,
      displayName: displayName,
      publicKey: await localPublicKey(),
      pairingSecret: await localPairingSecret(),
      endpoint: endpoint,
      transport: transport,
      createdAt: createdAt,
    );
  }

  /// Decode any pasted/scanned invite form. See [A2AInvite.tryDecodePayload].
  A2AInvite? decodeInvite(String rawValue) =>
      A2AInvite.tryDecodePayload(rawValue);

  // --- Inbound message routing (decision only; UI stays in the host) -------

  /// Classify an inbound peer message into the action the host should take.
  ///
  /// This owns the parity-critical routing *decision* — dedup, loopback
  /// filtering, and the kind→route mapping — so every adapter routes inbound
  /// messages identically. It does NOT perform any UI or transport side effect;
  /// the host switches on the returned [A2AInboundRoute] and renders/acts.
  ///
  /// Dedup is stateful: the first call for a given message id advances the seen
  /// set; later calls for the same id return [A2AInboundRoute.duplicate].
  A2AInboundRoute classifyInboundMessage(A2APeerMessage message) {
    if (!_seenMessageIds.add(message.messageId)) {
      return A2AInboundRoute.duplicate;
    }
    final purpose = message.payload['purpose'];
    if (purpose == 'local_a2a_loopback' ||
        purpose == 'local_a2a_reachability_probe') {
      return A2AInboundRoute.loopback;
    }
    switch (message.kind) {
      case 'pairing_accept':
        return A2AInboundRoute.pairingAccept;
      case 'pairing_request':
        return A2AInboundRoute.pairingRequest;
      case 'task_request':
        return A2AInboundRoute.taskRequest;
      default:
        return A2AInboundRoute.other;
    }
  }

  // --- Internals -----------------------------------------------------------

  String _pairingKey(A2ALocalPeerAdvertisement peer) =>
      A2APairing.pairingKey(peerId: peer.peerId, publicKey: peer.publicKey);

  String _peerSortLabel(A2ALocalPeerAdvertisement peer) {
    final name = peer.displayName.trim();
    if (name.isNotEmpty) return name.toLowerCase();
    final agent = peer.agentId.trim();
    if (agent.isNotEmpty) return agent.toLowerCase();
    return peer.peerId.toLowerCase();
  }

  Future<String?> _savedSharedSecret(A2ALocalPeerAdvertisement peer) async {
    for (final saved in await _loadSavedPeers()) {
      if (saved.peerId != peer.peerId) continue;
      final secret = saved.sharedSecret.trim();
      if (secret.isNotEmpty) return secret;
    }
    return null;
  }

  A2ALocalPeerAdvertisement? _advertisementFromSavedPeer(A2APeer peer) {
    final endpoint = peer.endpoints.isEmpty ? null : peer.endpoints.first;
    if (peer.peerId.isEmpty || endpoint == null || endpoint.uri.isEmpty) {
      return null;
    }
    return A2ALocalPeerAdvertisement(
      peerId: peer.peerId,
      agentId: peer.agentId,
      displayName: peer.displayName,
      publicKey: peer.publicKey,
      transport: endpoint.transport,
      endpoint: endpoint.uri,
    );
  }
}
