import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistence seam for local A2A pairing identity and secrets.
///
/// Secrets (the local pairing secret and per-peer remote secrets) go through
/// [NapaxiA2ASecretStore]; non-secret bookkeeping (the local public key, the
/// paired-peer set) goes through [NapaxiA2AKeyValueStore]. This mirrors the
/// existing `NapaxiConfigStore` seam so hosts can back secrets with
/// Keychain/Keystore.
///
/// The demo previously kept all of this in plaintext `SharedPreferences`
/// (`docs/a2a-local-pairing-followups.md` flagged it). `A2ALocalPairingStore.secure()`
/// is the host-grade default; `.insecureSharedPreferences()` is an explicitly
/// named demo fallback so plaintext storage can never ship silently; `.memory()`
/// is for tests.
abstract class NapaxiA2AKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Secret persistence seam (local pairing secret, per-peer remote secrets);
/// back this with Keychain/Keystore on a real host.
abstract class NapaxiA2ASecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Routes local A2A pairing state to a [NapaxiA2AKeyValueStore] (non-secret) and
/// a [NapaxiA2ASecretStore] (secret). Use [A2ALocalPairingStore.secure] on a
/// real host; the other constructors are explicit demo/test fallbacks.
class A2ALocalPairingStore {
  A2ALocalPairingStore({
    required NapaxiA2AKeyValueStore keyValueStore,
    required NapaxiA2ASecretStore secretStore,
  })  : _keyValueStore = keyValueStore,
        _secretStore = secretStore;

  /// Host-grade store: non-secret values in SharedPreferences, secrets in
  /// platform secure storage (Keychain / Keystore).
  A2ALocalPairingStore.secure()
      : this(
          keyValueStore: _SharedPreferencesA2AStore(),
          secretStore: _FlutterSecureA2AStore(),
        );

  /// Demo-grade store: everything in plaintext SharedPreferences. Named
  /// explicitly so a real host cannot select it by accident. Do not ship.
  A2ALocalPairingStore.insecureSharedPreferences()
      : this(
          keyValueStore: _SharedPreferencesA2AStore(),
          secretStore: _SharedPreferencesA2AStore(),
        );

  /// In-memory store for tests.
  A2ALocalPairingStore.memory()
      : this(
          keyValueStore: _MemoryA2AStore(),
          secretStore: _MemoryA2AStore(),
        );

  // Storage keys. The `.v1`/`.v2` suffixes are the on-device schema, not the
  // cross-device wire contract.
  static const _publicKeyKey = 'napaxi.a2a_local.public_key.v1';
  static const _pairingSecretKey = 'napaxi.a2a_local.pairing_secret.v1';
  static const _pairedPeerSecretsKey = 'napaxi.a2a_local.paired_peer_secrets.v2';

  // Legacy plaintext SharedPreferences keys the demo used before this seam.
  // Read once, migrated into the secret store, then cleared. The public-key
  // key matches the demo's actual constant (`public_identity`, not
  // `public_key`) — getting this wrong would regenerate the local public key on
  // upgrade and break existing pairings.
  static const _legacyPairingSecretKey =
      'napaxi_demo.a2a_local.pairing_secret.v1';
  static const _legacyPairedPeerSecretsKey =
      'napaxi_demo.a2a_local.paired_peer_secrets.v1';
  static const _legacyPublicKeyKey = 'napaxi_demo.a2a_local.public_identity.v1';

  final NapaxiA2AKeyValueStore _keyValueStore;
  final NapaxiA2ASecretStore _secretStore;

  Future<String?> readLocalPublicKey() => _keyValueStore.read(_publicKeyKey);

  Future<void> writeLocalPublicKey(String value) =>
      _keyValueStore.write(_publicKeyKey, value);

  Future<String?> readLocalPairingSecret() =>
      _secretStore.read(_pairingSecretKey);

  Future<void> writeLocalPairingSecret(String value) =>
      _secretStore.write(_pairingSecretKey, value);

  /// Load the `pairingKey -> remoteSecret` map. Tolerant of malformed JSON
  /// (returns empty) — never throws.
  Future<Map<String, String>> loadRemotePairingSecrets() async {
    final raw = await _secretStore.read(_pairedPeerSecretsKey);
    return _decodeSecretMap(raw);
  }

  Future<String?> readRemotePairingSecret(String pairingKey) async {
    final secrets = await loadRemotePairingSecrets();
    final value = secrets[pairingKey];
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> writeRemotePairingSecret(
    String pairingKey,
    String secret,
  ) async {
    final secrets = await loadRemotePairingSecrets();
    secrets[pairingKey] = secret;
    await _secretStore.write(_pairedPeerSecretsKey, jsonEncode(secrets));
  }

  Future<void> deleteRemotePairingSecret(String pairingKey) async {
    final secrets = await loadRemotePairingSecrets();
    secrets.remove(pairingKey);
    await _secretStore.write(_pairedPeerSecretsKey, jsonEncode(secrets));
  }

  /// One-time migration of the demo's legacy plaintext SharedPreferences keys
  /// into this store. Safe to call repeatedly: it only acts when a legacy key
  /// is present and the new key is absent, and clears the legacy key after.
  Future<void> migrateLegacyPlaintextIfPresent() async {
    final prefs = await SharedPreferences.getInstance();

    final legacyPublic = prefs.getString(_legacyPublicKeyKey);
    if (legacyPublic != null && legacyPublic.isNotEmpty) {
      if (await readLocalPublicKey() == null) {
        await writeLocalPublicKey(legacyPublic);
      }
      await prefs.remove(_legacyPublicKeyKey);
    }

    final legacySecret = prefs.getString(_legacyPairingSecretKey);
    if (legacySecret != null && legacySecret.isNotEmpty) {
      if (await readLocalPairingSecret() == null) {
        await writeLocalPairingSecret(legacySecret);
      }
      await prefs.remove(_legacyPairingSecretKey);
    }

    final legacyMap = prefs.getString(_legacyPairedPeerSecretsKey);
    if (legacyMap != null && legacyMap.trim().isNotEmpty) {
      final existing = await loadRemotePairingSecrets();
      if (existing.isEmpty) {
        final migrated = _decodeSecretMap(legacyMap);
        if (migrated.isNotEmpty) {
          await _secretStore.write(
            _pairedPeerSecretsKey,
            jsonEncode(migrated),
          );
        }
      }
      await prefs.remove(_legacyPairedPeerSecretsKey);
    }
  }

  Map<String, String> _decodeSecretMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return {
        for (final entry in decoded.entries)
          entry.key.toString(): entry.value?.toString() ?? '',
      }..removeWhere((_, value) => value.isEmpty);
    } catch (_) {
      return <String, String>{};
    }
  }
}

class _SharedPreferencesA2AStore
    implements NapaxiA2AKeyValueStore, NapaxiA2ASecretStore {
  @override
  Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  @override
  Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  @override
  Future<void> delete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}

class _FlutterSecureA2AStore implements NapaxiA2ASecretStore {
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class _MemoryA2AStore implements NapaxiA2AKeyValueStore, NapaxiA2ASecretStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
