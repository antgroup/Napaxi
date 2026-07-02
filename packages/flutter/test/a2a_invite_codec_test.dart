import 'dart:convert';

import 'package:napaxi_flutter/api/a2a_invite.dart';
import 'package:test/test.dart';

void main() {
  A2AInvite sampleInvite() => const A2AInvite(
        peerId: 'peer-abc',
        agentId: 'agent.demo',
        displayName: 'Demo Phone',
        publicKey: 'pubkey-xyz',
        pairingSecret: 'secret-123',
        endpoint: 'lan://10.0.0.2:7000',
        transport: 'lan_tcp_jsonl',
        createdAt: '2026-06-08T00:00:00Z',
      );

  test('encode/decode round-trips every field', () {
    final invite = sampleInvite();
    final decoded = A2AInvite.tryDecodeCode(invite.toCode());

    expect(decoded, isNotNull);
    expect(decoded!.version, A2AInvite.currentVersion);
    expect(decoded.peerId, invite.peerId);
    expect(decoded.agentId, invite.agentId);
    expect(decoded.displayName, invite.displayName);
    expect(decoded.publicKey, invite.publicKey);
    expect(decoded.pairingSecret, invite.pairingSecret);
    expect(decoded.endpoint, invite.endpoint);
    expect(decoded.transport, invite.transport);
    expect(decoded.createdAt, invite.createdAt);
  });

  test('QR payload carries the contract prefix and decodes back', () {
    final invite = sampleInvite();
    final payload = invite.toQrPayload();

    expect(payload, startsWith(A2AInvite.qrPrefix));
    final decoded = A2AInvite.tryDecodePayload(payload);
    expect(decoded?.peerId, invite.peerId);
  });

  test('tryDecodePayload accepts a /a2a join command line', () {
    final code = sampleInvite().toCode();
    final decoded = A2AInvite.tryDecodePayload('  /a2a join $code  ');
    expect(decoded?.peerId, 'peer-abc');
  });

  test('tryDecodePayload accepts a bare code', () {
    final code = sampleInvite().toCode();
    expect(A2AInvite.tryDecodePayload(code)?.peerId, 'peer-abc');
  });

  group('malformed input is rejected, never throws', () {
    test('empty / whitespace', () {
      expect(A2AInvite.tryDecodeCode(''), isNull);
      expect(A2AInvite.tryDecodePayload('   '), isNull);
    });

    test('non-base64 garbage', () {
      expect(A2AInvite.tryDecodeCode('!!!not base64!!!'), isNull);
    });

    test('valid base64 of non-JSON', () {
      final notJson = base64UrlEncode(utf8.encode('hello world'))
          .replaceAll('=', '');
      expect(A2AInvite.tryDecodeCode(notJson), isNull);
    });

    test('JSON missing required identity fields', () {
      String encode(Map<String, dynamic> m) =>
          base64UrlEncode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

      // Missing peerId.
      expect(
        A2AInvite.tryDecodeCode(encode({
          'v': 1,
          'publicKey': 'k',
          'pairingSecret': 's',
        })),
        isNull,
      );
      // Missing pairingSecret.
      expect(
        A2AInvite.tryDecodeCode(encode({
          'v': 1,
          'peerId': 'p',
          'publicKey': 'k',
        })),
        isNull,
      );
      // Missing publicKey.
      expect(
        A2AInvite.tryDecodeCode(encode({
          'v': 1,
          'peerId': 'p',
          'pairingSecret': 's',
        })),
        isNull,
      );
    });
  });

  test('toPeerAdvertisement preserves transport, and the model default when empty',
      () {
    final withTransport = sampleInvite().toPeerAdvertisement();
    expect(withTransport.peerId, 'peer-abc');
    expect(withTransport.transport, 'lan_tcp_jsonl');

    const noTransport = A2AInvite(
      peerId: 'p',
      agentId: 'a',
      publicKey: 'k',
      pairingSecret: 's',
    );
    // Empty invite transport falls back to the advertisement model default
    // rather than being forced to an empty string.
    expect(noTransport.toPeerAdvertisement().transport, isNotEmpty);
  });
}
