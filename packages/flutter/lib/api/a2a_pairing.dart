import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;

/// Static helpers for generating, normalizing, and formatting A2A local
/// pairing secrets.
class A2APairing {
  const A2APairing._();

  static String generateLocalPairingSecret({int byteLength = 16}) {
    final length = byteLength.clamp(16, 64).toInt();
    final random = math.Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return _hexFromBytes(bytes);
  }

  static String normalizePairingSecret(String value) {
    return value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
  }

  static String formatPairingSecret(String value) {
    final normalized = normalizePairingSecret(value);
    if (normalized.isEmpty) return '';
    final chunks = <String>[];
    for (var i = 0; i < normalized.length; i += 4) {
      chunks.add(normalized.substring(i, math.min(i + 4, normalized.length)));
    }
    return chunks.join(' ');
  }

  static String pairingCodeFromIdentity(String peerId, String publicKey) {
    final hex = _sha256Hex(_identityMaterial(peerId, publicKey));
    return '${hex.substring(0, 4)} ${hex.substring(4, 8)}';
  }

  static String pairingKey({
    required String peerId,
    required String publicKey,
  }) {
    return _identityMaterial(peerId, publicKey);
  }

  static String deriveLocalSharedSecret({
    required String localPeerId,
    required String localPublicKey,
    required String localPairingSecret,
    required String remotePeerId,
    required String remotePublicKey,
    required String remotePairingSecret,
  }) {
    final identities = [
      _identityMaterial(localPeerId, localPublicKey),
      _identityMaterial(remotePeerId, remotePublicKey),
    ]..sort();
    final secrets = [
      normalizePairingSecret(localPairingSecret),
      normalizePairingSecret(remotePairingSecret),
    ]..sort();
    return 'tofu-hmac-v2:${_sha256Hex([...identities, ...secrets].join('|'))}';
  }

  static String _identityMaterial(String peerId, String publicKey) {
    final material = publicKey.trim().isEmpty ? peerId : publicKey.trim();
    return '$peerId|$material';
  }

  static String _sha256Hex(String value) {
    return _hexFromBytes(crypto.sha256.convert(utf8.encode(value)).bytes);
  }

  static String _hexFromBytes(List<int> bytes) {
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }
}
