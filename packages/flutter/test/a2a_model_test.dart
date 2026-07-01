import 'dart:convert';

import 'package:napaxi_flutter/api/a2a_pairing.dart';
import 'package:napaxi_flutter/models/a2a.dart';
import 'package:test/test.dart';

void main() {
  test('A2A envelope and task record decode stable JSON', () {
    final envelope = A2ADeepLinkEnvelope.fromJson({
      'protocol_version': 1,
      'envelope_id': 'env-1',
      'kind': 'task_request',
      'sender': {'agent_id': 'sender.agent', 'peer_id': 'peer-1'},
      'recipient': {'agent_id': 'receiver.agent'},
      'task': {
        'task_id': 'task-1',
        'message': 'hello',
        'session_mode': 'isolated',
      },
      'callback': {'deep_link_url': 'agent-sender://a2a/result'},
      'created_at': '2026-06-03T00:00:00Z',
      'expires_at': '2026-06-03T01:00:00Z',
      'nonce': 'nonce',
      'idempotency_key': 'idem',
    });

    expect(envelope.envelopeId, 'env-1');
    expect(envelope.sender.peerId, 'peer-1');
    expect(envelope.task?.taskId, 'task-1');
    expect(envelope.toJson()['idempotencyKey'], 'idem');

    final record = A2ATaskRecord.fromJson({
      'task_id': 'task-1',
      'envelope_id': 'env-1',
      'idempotency_key': 'idem',
      'agent_id': 'receiver.agent',
      'sender': envelope.sender.toJson(),
      'request': envelope.task!.toJson(),
      'status': 'pending_user_confirmation',
      'trust': 'untrusted',
      'source': 'deep_link',
      'created_at': '2026-06-03T00:00:00Z',
      'updated_at': '2026-06-03T00:00:00Z',
      'session_id': 'peer-session-1',
      'peer_message_id': 'peer-message-1',
      'result_artifacts': [
        {
          'artifact_id': 'photo-1',
          'mime_type': 'image/jpeg',
          'name': 'photo.jpg'
        },
      ],
    });

    expect(record.idempotencyKey, 'idem');
    expect(record.status, 'pending_user_confirmation');
    expect(record.sessionId, 'peer-session-1');
    expect(record.peerMessageId, 'peer-message-1');
    expect(record.resultArtifacts.single.artifactId, 'photo-1');

    final peer = A2APeer.fromJson({
      'peer_id': 'peer-1',
      'agent_id': 'agent.peer',
      'trust_level': 'trusted',
      'shared_secret': 'secret',
      'public_key': 'public',
      'last_seen_at': '2026-06-03T00:00:00Z',
      'endpoints': [
        {'transport': 'lan_tcp', 'uri': 'tcp://192.168.1.8:38471/a2a'},
      ],
    });
    expect(peer.sharedSecret, 'secret');
    expect(peer.publicKey, 'public');
    expect(peer.endpoints.single.transport, 'lan_tcp');
    expect(peer.toJson()['sharedSecret'], 'secret');
  });

  test('A2A local peer message and delivery decode stable JSON', () {
    final session = A2APeerSession.fromJson({
      'session_id': 'session-1',
      'local_peer_id': 'phone-a',
      'remote_peer_id': 'phone-b',
      'remote_agent_id': 'agent.b',
      'status': 'active',
      'transport': 'lan_websocket',
      'endpoint': 'ws://192.168.1.2:38471/a2a',
      'created_at': '2026-06-03T00:00:00Z',
      'updated_at': '2026-06-03T00:00:01Z',
    });
    expect(session.remotePeerId, 'phone-b');
    expect(session.transport, 'lan_websocket');

    final message = A2APeerMessage.fromJson({
      'message_id': 'msg-1',
      'session_id': 'session-1',
      'from_peer_id': 'phone-a',
      'to_peer_id': 'phone-b',
      'kind': 'task_request',
      'created_at': '2026-06-03T00:00:00Z',
      'expires_at': '2026-06-03T00:30:00Z',
      'nonce': 'nonce',
      'idempotency_key': 'idem',
      'payload': {
        'task': {'task_id': 'task-1', 'message': 'hello'},
      },
    });
    expect(message.payload['task']['task_id'], 'task-1');
    expect(jsonDecode(message.toJsonString())['messageId'], 'msg-1');

    final delivery = A2ADeliveryRecord.fromJson({
      'message_id': 'msg-1',
      'session_id': 'session-1',
      'direction': 'inbound',
      'kind': 'task_request',
      'status': 'delivered',
      'created_at': '2026-06-03T00:00:01Z',
      'updated_at': '2026-06-03T00:00:01Z',
      'task_id': 'task-1',
    });
    expect(delivery.status, 'delivered');
    expect(delivery.taskId, 'task-1');
  });

  test('A2A local transport models decode stable channel payloads', () {
    final status = A2ALocalTransportStatus.fromJson({
      'supported': true,
      'running': true,
      'transport': 'lan_tcp_jsonl',
      'serviceType': '_napaxi-a2a._tcp.',
      'peerId': 'phone-a',
      'listenerPort': 38471,
      'registeredName': 'Napaxi-phone-a',
      'discoveredPeerCount': 2,
      'activeDiscoveryCount': 1,
      'sentMessageCount': 3,
      'receivedMessageCount': 4,
      'multicastLockHeld': true,
      'lastError': '',
    });
    expect(status.running, isTrue);
    expect(status.serviceType, '_napaxi-a2a._tcp.');
    expect(status.listenerPort, 38471);
    expect(status.discoveredPeerCount, 2);
    expect(status.activeDiscoveryCount, 1);
    expect(status.sentMessageCount, 3);
    expect(status.receivedMessageCount, 4);
    expect(status.multicastLockHeld, isTrue);

    final peer = A2ALocalPeerAdvertisement.fromJson({
      'peerId': 'phone-b',
      'agentId': 'agent.b',
      'displayName': 'Phone B',
      'transport': 'lan_tcp_jsonl',
      'endpoint': 'tcp://192.168.1.8:38471/a2a',
      'host': '192.168.1.8',
      'port': 38471,
    });
    expect(peer.endpoint, 'tcp://192.168.1.8:38471/a2a');
    expect(peer.toPeer().trustLevel, 'untrusted');
    expect(
      peer.toPeer(trustLevel: 'user_confirmed').trustLevel,
      'user_confirmed',
    );
    expect(
      peer
          .toPeer(trustLevel: 'user_confirmed', sharedSecret: 'secret')
          .sharedSecret,
      'secret',
    );

    final message = A2APeerMessage(
      messageId: 'msg-1',
      sessionId: 'session-1',
      fromPeerId: 'phone-a',
      toPeerId: 'phone-b',
      kind: 'task_request',
      createdAt: '2026-06-03T00:00:00Z',
      expiresAt: '2026-06-03T00:30:00Z',
      nonce: 'nonce',
      idempotencyKey: 'idem',
    );
    expect(jsonDecode(message.toJsonString())['messageId'], 'msg-1');
  });

  test('A2A local transport preserves non-peer control frames', () {
    final event = A2ALocalTransportEvent.fromEvent({
      'action': 'a2aLocalPeerMessage',
      'payload': jsonEncode({
        'messageJson': jsonEncode({
          'frameType': 'a2a_blob_manifest',
          'manifestId': 'manifest-1',
        }),
      }),
    });

    expect(event.action, 'a2aLocalPeerMessage');
    expect(event.message, isNull);
    expect(jsonDecode(event.messageJson)['frameType'], 'a2a_blob_manifest');
  });

  test('A2A local pairing helpers derive symmetric non-public secret', () {
    final peerA = A2ALocalPeerAdvertisement.fromJson({
      'peerId': 'phone-a',
      'agentId': 'agent.a',
      'displayName': 'Phone A',
      'publicKey': 'public-a',
      'transport': 'lan_tcp_jsonl',
      'endpoint': 'tcp://192.168.1.7:38471/a2a',
      'host': '192.168.1.7',
      'port': 38471,
    });
    final peerB = A2ALocalPeerAdvertisement.fromJson({
      'peerId': 'phone-b',
      'agentId': 'agent.b',
      'displayName': 'Phone B',
      'publicKey': 'public-b',
      'transport': 'lan_tcp_jsonl',
      'endpoint': 'tcp://192.168.1.8:38471/a2a',
      'host': '192.168.1.8',
      'port': 38471,
    });

    expect(
      A2APairing.pairingKey(peerId: peerA.peerId, publicKey: peerA.publicKey),
      'phone-a|public-a',
    );
    expect(
      A2APairing.pairingCodeFromIdentity('phone-a', 'public-a'),
      hasLength(9),
    );
    expect(
      A2APairing.normalizePairingSecret(' a1b2-c3d4 ef00 '),
      'A1B2C3D4EF00',
    );
    expect(
      A2APairing.formatPairingSecret('a1b2c3d4ef00'),
      'A1B2 C3D4 EF00',
    );

    const secretA = 'AAAA BBBB CCCC DDDD';
    const secretB = '1111-2222-3333-4444';
    final aToB = A2APairing.deriveLocalSharedSecret(
      localPeerId: peerA.peerId,
      localPublicKey: peerA.publicKey,
      localPairingSecret: secretA,
      remotePeerId: peerB.peerId,
      remotePublicKey: peerB.publicKey,
      remotePairingSecret: secretB,
    );
    final bToA = A2APairing.deriveLocalSharedSecret(
      localPeerId: peerB.peerId,
      localPublicKey: peerB.publicKey,
      localPairingSecret: secretB,
      remotePeerId: peerA.peerId,
      remotePublicKey: peerA.publicKey,
      remotePairingSecret: secretA,
    );
    final withoutRemoteSecret = A2APairing.deriveLocalSharedSecret(
      localPeerId: peerA.peerId,
      localPublicKey: peerA.publicKey,
      localPairingSecret: secretA,
      remotePeerId: peerB.peerId,
      remotePublicKey: peerB.publicKey,
      remotePairingSecret: '',
    );

    expect(
      aToB,
      'tofu-hmac-v2:2F4C67A6913CE598670024D0F63C64C26DE3D8B6CDED86ED376EB0A9F02979DF',
    );
    expect(aToB, bToA);
    expect(aToB, startsWith('tofu-hmac-v2:'));
    expect(aToB, hasLength('tofu-hmac-v2:'.length + 64));
    expect(aToB, isNot(withoutRemoteSecret));
    expect(aToB, isNot(contains('public-a')));
    expect(aToB, isNot(contains('public-b')));
    expect(aToB, isNot(contains('AAAA')));
    expect(aToB, isNot(contains('1111')));
  });
}
