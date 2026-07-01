import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/api/a2a_local_pairing_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('memory store round-trips public key and local pairing secret', () async {
    final store = A2ALocalPairingStore.memory();

    expect(await store.readLocalPublicKey(), isNull);
    await store.writeLocalPublicKey('pub-1');
    expect(await store.readLocalPublicKey(), 'pub-1');

    expect(await store.readLocalPairingSecret(), isNull);
    await store.writeLocalPairingSecret('secret-1');
    expect(await store.readLocalPairingSecret(), 'secret-1');
  });

  test('remote pairing secrets are keyed and survive updates', () async {
    final store = A2ALocalPairingStore.memory();

    expect(await store.readRemotePairingSecret('peerA'), isNull);
    await store.writeRemotePairingSecret('peerA', 'sa');
    await store.writeRemotePairingSecret('peerB', 'sb');

    expect(await store.readRemotePairingSecret('peerA'), 'sa');
    expect(await store.readRemotePairingSecret('peerB'), 'sb');

    // Overwrite one key without clobbering the other.
    await store.writeRemotePairingSecret('peerA', 'sa2');
    final all = await store.loadRemotePairingSecrets();
    expect(all['peerA'], 'sa2');
    expect(all['peerB'], 'sb');
  });

  test('empty remote secrets are not retained', () async {
    final store = A2ALocalPairingStore.memory();
    await store.writeRemotePairingSecret('peerA', '');
    expect(await store.readRemotePairingSecret('peerA'), isNull);
    expect(await store.loadRemotePairingSecrets(), isEmpty);
  });

  test('legacy plaintext keys migrate once and are cleared', () async {
    SharedPreferences.setMockInitialValues({
      'napaxi_demo.a2a_local.public_identity.v1': 'legacy-pub',
      'napaxi_demo.a2a_local.pairing_secret.v1': 'legacy-secret',
      'napaxi_demo.a2a_local.paired_peer_secrets.v1':
          '{"peerA":"legacy-remote"}',
    });

    // Use the SharedPreferences-backed store so migration writes land where the
    // store reads them back.
    final store = A2ALocalPairingStore.insecureSharedPreferences();
    await store.migrateLegacyPlaintextIfPresent();

    expect(await store.readLocalPublicKey(), 'legacy-pub');
    expect(await store.readLocalPairingSecret(), 'legacy-secret');
    expect(await store.readRemotePairingSecret('peerA'), 'legacy-remote');

    // Legacy keys are gone.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('napaxi_demo.a2a_local.public_identity.v1'), isNull);
    expect(prefs.getString('napaxi_demo.a2a_local.pairing_secret.v1'), isNull);
    expect(
      prefs.getString('napaxi_demo.a2a_local.paired_peer_secrets.v1'),
      isNull,
    );
  });

  test('migration is a no-op when no legacy keys exist', () async {
    SharedPreferences.setMockInitialValues({});
    final store = A2ALocalPairingStore.insecureSharedPreferences();
    await store.migrateLegacyPlaintextIfPresent();
    expect(await store.readLocalPublicKey(), isNull);
    expect(await store.readLocalPairingSecret(), isNull);
  });

  test('malformed remote-secret JSON decodes to empty, never throws', () async {
    SharedPreferences.setMockInitialValues({
      'napaxi_demo.a2a_local.paired_peer_secrets.v1': 'not json {{{',
    });
    final store = A2ALocalPairingStore.insecureSharedPreferences();
    await store.migrateLegacyPlaintextIfPresent();
    expect(await store.loadRemotePairingSecrets(), isEmpty);
  });
}
