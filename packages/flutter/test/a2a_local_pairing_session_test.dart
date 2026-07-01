import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/api/a2a_local_pairing_session.dart';
import 'package:napaxi_flutter/api/a2a_local_pairing_store.dart';
import 'package:napaxi_flutter/api/a2a_pairing.dart';
import 'package:napaxi_flutter/models/a2a.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  A2ALocalPeerAdvertisement peer(
    String id, {
    String publicKey = 'pub',
    String endpoint = 'lan://1.2.3.4:7000',
  }) =>
      A2ALocalPeerAdvertisement(
        peerId: id,
        agentId: 'agent.$id',
        displayName: 'Peer $id',
        publicKey: publicKey,
        endpoint: endpoint,
      );

  A2ALocalPairingSession session({List<A2APeer> savedPeers = const []}) =>
      A2ALocalPairingSession(
        store: A2ALocalPairingStore.memory(),
        loadSavedPeers: () async => savedPeers,
      );

  test('local identity & secret are generated once and persisted', () async {
    final s = session();
    final pub1 = await s.localPublicKey();
    final pub2 = await s.localPublicKey();
    expect(pub1, isNotEmpty);
    expect(pub2, pub1, reason: 'stable across calls');

    final secret1 = await s.localPairingSecret();
    final secret2 = await s.localPairingSecret();
    expect(secret1, isNotEmpty);
    expect(secret2, secret1);
    // Pairing secret is normalized hex.
    expect(secret1, A2APairing.normalizePairingSecret(secret1));
  });

  test('remote pairing secret round-trips and drives paired state', () async {
    final s = session();
    final p = peer('alpha');

    expect(await s.isPeerPaired(p), isFalse);
    expect(await s.remotePairingSecret(p), isNull);

    await s.saveRemotePairingSecret(p, '11aa 22bb');
    // Stored normalized.
    expect(await s.remotePairingSecret(p), '11AA22BB');
    expect(await s.isPeerPaired(p), isTrue);
  });

  test('a saved peer with a shared secret counts as paired', () async {
    final saved = A2APeer(
      peerId: 'beta',
      agentId: 'agent.beta',
      sharedSecret: 'tofu-hmac-v2:deadbeef',
      publicKey: 'pub',
      endpoints: const [A2APeerEndpoint(transport: 'lan_tcp_jsonl', uri: 'lan://x')],
    );
    final s = session(savedPeers: [saved]);
    expect(await s.isPeerPaired(peer('beta')), isTrue);
  });

  test('sharedSecretForPeer prefers a saved secret over deriving', () async {
    final saved = A2APeer(
      peerId: 'gamma',
      agentId: 'agent.gamma',
      sharedSecret: 'tofu-hmac-v2:saved-one',
      publicKey: 'pub',
      endpoints: const [A2APeerEndpoint(transport: 'lan_tcp_jsonl', uri: 'lan://x')],
    );
    final s = session(savedPeers: [saved]);
    final secret = await s.sharedSecretForPeer(peer('gamma'), localPeerId: 'me');
    expect(secret, 'tofu-hmac-v2:saved-one');
  });

  test('sharedSecretForPeer derives the same value as A2APairing', () async {
    final s = session();
    final p = peer('delta', publicKey: 'remote-pub');
    await s.saveRemotePairingSecret(p, 'ABCD1234');

    final derived =
        await s.sharedSecretForPeer(p, localPeerId: 'local-peer');

    // Recompute independently with the pure helper and the session's identity.
    final expected = A2APairing.deriveLocalSharedSecret(
      localPeerId: 'local-peer',
      localPublicKey: await s.localPublicKey(),
      localPairingSecret: await s.localPairingSecret(),
      remotePeerId: 'delta',
      remotePublicKey: 'remote-pub',
      remotePairingSecret: 'ABCD1234',
    );
    expect(derived, expected);
    expect(derived, startsWith('tofu-hmac-v2:'));
  });

  test('sharedSecretForPeer returns null without enough material', () async {
    final s = session();
    final p = peer('epsilon');
    // No remote secret stored.
    expect(await s.sharedSecretForPeer(p, localPeerId: 'me'), isNull);
    // Remote secret present but no local peer id.
    await s.saveRemotePairingSecret(p, 'ABCD1234');
    expect(await s.sharedSecretForPeer(p, localPeerId: ''), isNull);
  });

  group('peer resolution', () {
    test('resolveKnownPeer matches id, prefix, and agent id', () {
      final s = session()..rememberPeers([peer('abcdef'), peer('zzz')]);
      expect(s.resolveKnownPeer('abcdef')?.peerId, 'abcdef');
      expect(s.resolveKnownPeer('abc')?.peerId, 'abcdef');
      expect(s.resolveKnownPeer('agent.zzz')?.peerId, 'zzz');
      expect(s.resolveKnownPeer('nope'), isNull);
    });

    test('sortedKnownPeers is deterministic by label then id', () {
      final s = session()
        ..rememberPeers([peer('b'), peer('a'), peer('c')]);
      final ids = s.sortedKnownPeers().map((p) => p.peerId).toList();
      expect(ids, ['a', 'b', 'c']); // display names "Peer a/b/c"
    });

    test('resolvePairedPeer falls back to saved peers and requires pairing',
        () async {
      final saved = A2APeer(
        peerId: 'saved-1',
        agentId: 'agent.saved',
        sharedSecret: 'tofu-hmac-v2:s',
        publicKey: 'pub',
        endpoints: const [
          A2APeerEndpoint(transport: 'lan_tcp_jsonl', uri: 'lan://host')
        ],
      );
      final s = session(savedPeers: [saved]);
      expect((await s.resolvePairedPeer('saved-1'))?.peerId, 'saved-1');
      expect(await s.resolvePairedPeer('unknown'), isNull);
    });
  });

  test('buildInvite carries local identity and decodes back', () async {
    final s = session();
    final invite = await s.buildInvite(
      localPeerId: 'me',
      agentId: 'agent.me',
      displayName: 'My Phone',
      endpoint: 'lan://5.6.7.8:9000',
      transport: 'lan_tcp_jsonl',
    );
    expect(invite.peerId, 'me');
    expect(invite.publicKey, await s.localPublicKey());
    expect(invite.pairingSecret, await s.localPairingSecret());

    final decoded = s.decodeInvite(invite.toQrPayload());
    expect(decoded?.peerId, 'me');
    expect(decoded?.endpoint, 'lan://5.6.7.8:9000');
  });

  group('classifyInboundMessage', () {
    A2APeerMessage msg(
      String id, {
      String kind = 'task_request',
      Map<String, dynamic> payload = const {},
    }) =>
        A2APeerMessage(
          messageId: id,
          sessionId: 'sess',
          fromPeerId: 'remote',
          toPeerId: 'me',
          kind: kind,
          createdAt: '',
          expiresAt: '',
          nonce: 'n',
          idempotencyKey: 'i',
          payload: payload,
        );

    test('dedups by message id', () {
      final s = session();
      expect(
        s.classifyInboundMessage(msg('m1')),
        A2AInboundRoute.taskRequest,
      );
      expect(
        s.classifyInboundMessage(msg('m1')),
        A2AInboundRoute.duplicate,
        reason: 'second sighting of the same id is a duplicate',
      );
    });

    test('filters loopback self-test messages', () {
      final s = session();
      expect(
        s.classifyInboundMessage(
          msg('m2', payload: {'purpose': 'local_a2a_loopback'}),
        ),
        A2AInboundRoute.loopback,
      );
    });

    test('routes pairing and task kinds', () {
      final s = session();
      expect(
        s.classifyInboundMessage(msg('p1', kind: 'pairing_accept')),
        A2AInboundRoute.pairingAccept,
      );
      expect(
        s.classifyInboundMessage(msg('p2', kind: 'pairing_request')),
        A2AInboundRoute.pairingRequest,
      );
      expect(
        s.classifyInboundMessage(msg('t1', kind: 'task_request')),
        A2AInboundRoute.taskRequest,
      );
      expect(
        s.classifyInboundMessage(msg('o1', kind: 'task_progress')),
        A2AInboundRoute.other,
      );
    });
  });
}
