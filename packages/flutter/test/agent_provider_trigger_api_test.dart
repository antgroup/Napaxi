import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/api/agent_provider_trigger_api.dart';
import 'package:napaxi_flutter/models/agent_app.dart';
import 'package:napaxi_flutter/models/agent_provider_trigger.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const channel = MethodChannel('com.napaxi.flutter/background');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('consumePendingTrigger parses method channel payload', () async {
    final trigger = _signedTrigger();
    final api = AgentProviderTriggerApi(
      channel: channel,
      getPackage: (_) => _package(),
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getPendingAgentTriggerRequest') {
        return {'triggerRequestJson': trigger.toJsonString()};
      }
      fail('unexpected method ${call.method}');
    });

    final parsed = await api.consumePendingTrigger();

    expect(parsed?.requestId, 'trigger-1');
    expect(parsed?.message, 'Review today spending.');
  });

  test('acceptTrigger validates signature and rejects replay', () async {
    final trigger = _signedTrigger();
    final api = AgentProviderTriggerApi(
      channel: channel,
      getPackage: (_) => _package(),
    );

    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });

    final accepted = await api.acceptTrigger(trigger);

    expect(accepted.request.agentId, 'provider.agent');
    expect(calls, contains('clearPendingAgentTriggerRequest'));
    await expectLater(
      api.acceptTrigger(trigger),
      throwsA(isA<StateError>()),
    );
  });

  test('validateTrigger rejects tampered message', () async {
    final trigger = _signedTrigger(message: 'Tampered');
    final tampered = AgentTriggerRequest(
      requestId: trigger.requestId,
      providerId: trigger.providerId,
      agentId: trigger.agentId,
      message: 'Other message',
      source: trigger.source,
      eventType: trigger.eventType,
      payload: trigger.payload,
      createdAt: trigger.createdAt,
      expiresAt: trigger.expiresAt,
      nonce: trigger.nonce,
      idempotencyKey: trigger.idempotencyKey,
      hostInstanceId: trigger.hostInstanceId,
      signatureAlgorithm: trigger.signatureAlgorithm,
      signature: trigger.signature,
    );
    final api = AgentProviderTriggerApi(
      channel: channel,
      getPackage: (_) => _package(),
    );

    await expectLater(
      api.validateTrigger(tampered),
      throwsA(isA<StateError>()),
    );
  });
}

AgentAppPackage _package() {
  return const AgentAppPackage(
    providerId: 'provider.test',
    agentId: 'provider.agent',
    displayName: 'Provider Agent',
    installBinding: AgentAppInstallBinding(
      platform: 'android',
      appPackageName: 'provider.app',
      activityName: 'provider.ActionActivity',
      signingCertSha256: 'provider123',
      installedAt: '2026-05-27T00:00:00Z',
      installRequestId: 'install-1',
      protocolVersion: 2,
      hostInstanceId: 'host-instance-1',
      hostSharedSecret: 'secret-1',
    ),
  );
}

AgentTriggerRequest _signedTrigger(
    {String message = 'Review today spending.'}) {
  final unsigned = AgentTriggerRequest(
    requestId: 'trigger-1',
    providerId: 'provider.test',
    agentId: 'provider.agent',
    message: message,
    source: 'virtual_wallet',
    eventType: 'review_spending_requested',
    payload: const {'view': 'today_spending'},
    createdAt: '2026-05-27T00:00:00Z',
    expiresAt: '2030-01-01T00:00:00Z',
    nonce: 'nonce-trigger',
    idempotencyKey: 'trigger-1',
    hostInstanceId: 'host-instance-1',
    signatureAlgorithm: 'hmac-sha256-v1',
  );
  return AgentTriggerRequest(
    requestId: unsigned.requestId,
    providerId: unsigned.providerId,
    agentId: unsigned.agentId,
    message: unsigned.message,
    source: unsigned.source,
    eventType: unsigned.eventType,
    payload: unsigned.payload,
    createdAt: unsigned.createdAt,
    expiresAt: unsigned.expiresAt,
    nonce: unsigned.nonce,
    idempotencyKey: unsigned.idempotencyKey,
    hostInstanceId: unsigned.hostInstanceId,
    signatureAlgorithm: unsigned.signatureAlgorithm,
    signature: _hmacSha256Base64NoPad(
      'secret-1',
      _triggerSignaturePayload(unsigned),
    ),
  );
}

String _triggerSignaturePayload(AgentTriggerRequest request) {
  final payloadHash = _sha256Base64NoPad(_canonicalJson(request.payload));
  return [
    'request_id=${request.requestId}',
    'provider_id=${request.providerId}',
    'agent_id=${request.agentId}',
    'message=${request.message}',
    'source=${request.source}',
    'event_type=${request.eventType}',
    'payload_sha256=$payloadHash',
    'created_at=${request.createdAt}',
    'expires_at=${request.expiresAt}',
    'nonce=${request.nonce}',
    'idempotency_key=${request.idempotencyKey}',
    'host_instance_id=${request.hostInstanceId}',
  ].join('\n');
}

String _canonicalJson(Object? value) {
  if (value == null) return 'null';
  if (value is bool || value is num) return value.toString();
  if (value is String) return jsonEncode(value);
  if (value is List) return '[${value.map(_canonicalJson).join(',')}]';
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return '{${keys.map((key) {
      return '${jsonEncode(key)}:${_canonicalJson(value[key])}';
    }).join(',')}}';
  }
  return jsonEncode(value.toString());
}

String _sha256Base64NoPad(String value) {
  return base64Encode(sha256.convert(utf8.encode(value)).bytes)
      .replaceAll('=', '');
}

String _hmacSha256Base64NoPad(String secret, String payload) {
  final hmac = Hmac(sha256, utf8.encode(secret));
  return base64Encode(hmac.convert(utf8.encode(payload)).bytes)
      .replaceAll('=', '');
}
