import 'package:napaxi_flutter/api/a2a_invite.dart';
import 'package:test/test.dart';

import 'support/contract_fixtures.dart';

/// Adapter-parity guard: the Flutter invite codec must consume the SHARED
/// wire-shape fixture in packages/api_contract/fixtures/a2a/, which is the
/// cross-adapter source of truth (pinned in Rust core's
/// local_pairing_contract). If iOS/Android adapters bind the same fixture,
/// a drift on any one adapter surfaces as a failing decode rather than a
/// silent cross-device incompatibility. See docs/sdk-adapter-parity.md.
void main() {
  test('Flutter codec decodes the shared local-pairing invite fixture', () {
    final fixture = contractFixtureObject('a2a/local_pairing_invite.json');
    final invite = Map<String, dynamic>.from(fixture['invite'] as Map);
    final qrPrefix = fixture['qrPrefix'] as String;

    // The fixture's prefix must equal the codec's compiled-in contract prefix.
    expect(qrPrefix, A2AInvite.qrPrefix);

    // Build a QR payload exactly as a sending adapter would, then decode it.
    final code = _encodeInvite(invite);
    final decoded = A2AInvite.tryDecodePayload('$qrPrefix$code');

    expect(decoded, isNotNull,
        reason: 'shared fixture must decode with the Flutter codec');
    expect(decoded!.peerId, invite['peerId']);
    expect(decoded.publicKey, invite['publicKey']);
    expect(decoded.pairingSecret, invite['pairingSecret']);
    expect(decoded.endpoint, invite['endpoint']);
    expect(decoded.transport, invite['transport']);
    expect(decoded.version, invite['v']);
  });

  test('every required identity field in the fixture is enforced by the codec',
      () {
    final fixture = contractFixtureObject('a2a/local_pairing_invite.json');
    final invite = Map<String, dynamic>.from(fixture['invite'] as Map);
    final required =
        (fixture['requiredIdentityFields'] as List).cast<String>();

    // Dropping any single required field must make the codec reject the invite,
    // matching the core contract's required-field set.
    for (final field in required) {
      final partial = Map<String, dynamic>.from(invite)..remove(field);
      expect(
        A2AInvite.tryDecodeCode(_encodeInvite(partial)),
        isNull,
        reason: 'invite missing $field must be rejected',
      );
    }
  });
}

String _encodeInvite(Map<String, dynamic> invite) {
  // Mirror A2AInvite.toCode() without depending on its private constructor:
  // base64url(jsonEncode(invite)) with padding stripped.
  return A2AInvite(
    version: (invite['v'] as num?)?.toInt() ?? A2AInvite.currentVersion,
    peerId: invite['peerId'] as String? ?? '',
    agentId: invite['agentId'] as String? ?? '',
    displayName: invite['displayName'] as String? ?? '',
    publicKey: invite['publicKey'] as String? ?? '',
    pairingSecret: invite['pairingSecret'] as String? ?? '',
    endpoint: invite['endpoint'] as String? ?? '',
    transport: invite['transport'] as String? ?? '',
    createdAt: invite['createdAt'] as String? ?? '',
  ).toCode();
}
