import 'dart:convert';

import '../models/a2a.dart';

/// Local A2A pairing invite — the decoded form of a `napaxi-a2a-invite:` QR /
/// text payload.
///
/// The wire shape (field names, QR prefix, schema version) is the cross-device
/// contract pinned in Rust core at `napaxi_core::api::a2a::local_pairing_contract`.
/// Keep this Dart codec in lockstep with that module; the parity fixtures in
/// `packages/api_contract/fixtures/a2a/` lock the two together.
class A2AInvite {
  const A2AInvite({
    required this.peerId,
    required this.agentId,
    required this.publicKey,
    required this.pairingSecret,
    this.displayName = '',
    this.endpoint = '',
    this.transport = '',
    this.createdAt = '',
    this.version = currentVersion,
  });

  /// Current invite schema version (mirrors `INVITE_VERSION` in core).
  static const int currentVersion = 1;

  /// QR / deep-link payload prefix (mirrors `INVITE_QR_PREFIX` in core).
  static const String qrPrefix = 'napaxi-a2a-invite:';

  // Wire field names (mirror `invite_fields::*` in core). Kept private; callers
  // use the typed fields below.
  static const String _fVersion = 'v';
  static const String _fPeerId = 'peerId';
  static const String _fAgentId = 'agentId';
  static const String _fDisplayName = 'displayName';
  static const String _fPublicKey = 'publicKey';
  static const String _fPairingSecret = 'pairingSecret';
  static const String _fEndpoint = 'endpoint';
  static const String _fTransport = 'transport';
  static const String _fCreatedAt = 'createdAt';

  final int version;
  final String peerId;
  final String agentId;
  final String displayName;
  final String publicKey;
  final String pairingSecret;
  final String endpoint;
  final String transport;
  final String createdAt;

  /// The flat JSON object form (the value that gets base64url-encoded).
  Map<String, dynamic> toJson() => {
        _fVersion: version,
        _fPeerId: peerId,
        _fAgentId: agentId,
        _fDisplayName: displayName,
        _fPublicKey: publicKey,
        _fPairingSecret: pairingSecret,
        _fEndpoint: endpoint,
        _fTransport: transport,
        _fCreatedAt: createdAt,
      };

  /// Encode to the bare invite code (base64url, no padding) — no QR prefix.
  String toCode() {
    final bytes = utf8.encode(jsonEncode(toJson()));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Encode to the full QR / deep-link payload, with the [qrPrefix].
  String toQrPayload() => '$qrPrefix${toCode()}';

  /// Decode a bare invite code (base64url JSON). Returns null on any malformed
  /// input or if the required identity fields are missing — never throws.
  static A2AInvite? tryDecodeCode(String code) {
    final normalized = code.trim();
    if (normalized.isEmpty) return null;
    Map<String, dynamic> map;
    try {
      final raw = utf8.decode(base64Url.decode(base64Url.normalize(normalized)));
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      map = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
    final peerId = (map[_fPeerId] as String?)?.trim() ?? '';
    final pairingSecret = (map[_fPairingSecret] as String?)?.trim() ?? '';
    final publicKey = (map[_fPublicKey] as String?)?.trim() ?? '';
    // An invite without a peer id, public key, or pairing secret cannot drive a
    // handshake — reject rather than return a half-built record.
    if (peerId.isEmpty || pairingSecret.isEmpty || publicKey.isEmpty) {
      return null;
    }
    return A2AInvite(
      version: (map[_fVersion] as num?)?.toInt() ?? currentVersion,
      peerId: peerId,
      agentId: (map[_fAgentId] as String?)?.trim() ?? '',
      displayName: (map[_fDisplayName] as String?) ?? '',
      publicKey: publicKey,
      pairingSecret: pairingSecret,
      endpoint: (map[_fEndpoint] as String?) ?? '',
      transport: (map[_fTransport] as String?) ?? '',
      createdAt: (map[_fCreatedAt] as String?) ?? '',
    );
  }

  /// Decode any of the forms a user might paste/scan:
  /// - a full `napaxi-a2a-invite:<code>` QR payload,
  /// - a `/a2a join <code>` slash command line,
  /// - or a bare invite code.
  /// Returns null when nothing decodes — never throws.
  static A2AInvite? tryDecodePayload(String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty) return null;
    if (value.startsWith(qrPrefix)) {
      return tryDecodeCode(value.substring(qrPrefix.length));
    }
    final joinMatch = RegExp(
      r'(?:^|\s)/a2a\s+join\s+([A-Za-z0-9_-]+)',
      caseSensitive: false,
    ).firstMatch(value);
    if (joinMatch != null) {
      return tryDecodeCode(joinMatch.group(1) ?? '');
    }
    return tryDecodeCode(value);
  }

  /// The advertisement view of the inviting peer, for transport/discovery APIs.
  A2ALocalPeerAdvertisement toPeerAdvertisement() {
    // Preserve the model's transport default when the invite did not carry one.
    if (transport.isEmpty) {
      return A2ALocalPeerAdvertisement(
        peerId: peerId,
        agentId: agentId,
        displayName: displayName,
        publicKey: publicKey,
        endpoint: endpoint,
      );
    }
    return A2ALocalPeerAdvertisement(
      peerId: peerId,
      agentId: agentId,
      displayName: displayName,
      publicKey: publicKey,
      endpoint: endpoint,
      transport: transport,
    );
  }
}
