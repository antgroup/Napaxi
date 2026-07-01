import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/agent_app.dart';
import '../models/agent_provider_trigger.dart';

/// Agent-provider trigger API: verifies HMAC-signed provider triggers and
/// tracks consumed trigger ids to prevent replay.
class AgentProviderTriggerApi {
  AgentProviderTriggerApi({
    required AgentAppPackage? Function(String agentId) getPackage,
    MethodChannel? channel,
    SharedPreferences? preferences,
  })  : _channel = channel ?? const MethodChannel(_channelName),
        _preferences = preferences,
        _getPackage = getPackage;

  static const _channelName = 'com.napaxi.flutter/background';
  static const _signatureAlgorithm = 'hmac-sha256-v1';
  static const _consumedKey = 'agent_provider.consumed_triggers.v1';

  final MethodChannel _channel;
  final SharedPreferences? _preferences;
  final AgentAppPackage? Function(String agentId) _getPackage;

  Future<AgentTriggerRequest?> consumePendingTrigger() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getPendingAgentTriggerRequest',
    );
    if (raw == null || raw.isEmpty) return null;
    final json = raw['triggerRequestJson'] as String? ?? '';
    if (json.isEmpty) return null;
    return AgentTriggerRequest.fromJsonString(json);
  }

  Future<AcceptedAgentTrigger> acceptTrigger(
    AgentTriggerRequest request,
  ) async {
    final package = await validateTrigger(request);
    final prefs = await _prefs();
    final consumed = prefs.getStringList(_consumedKey) ?? const <String>[];
    await prefs.setStringList(
      _consumedKey,
      <String>{...consumed, request.requestId}.toList(growable: false),
    );
    await _channel.invokeMethod<void>('clearPendingAgentTriggerRequest');
    return AcceptedAgentTrigger(
      request: request,
      displayName: package.displayName.trim().isEmpty
          ? package.agentId
          : package.displayName,
    );
  }

  Future<AgentAppPackage> validateTrigger(AgentTriggerRequest request) async {
    if (request.protocolVersion < 2) {
      throw StateError('Agent trigger protocol v2 is required');
    }
    if (request.requestId.isEmpty ||
        request.providerId.isEmpty ||
        request.agentId.isEmpty ||
        request.message.trim().isEmpty ||
        request.nonce.isEmpty ||
        request.idempotencyKey.isEmpty) {
      throw StateError('Agent trigger is missing required fields');
    }
    final expiresAt = DateTime.tryParse(request.expiresAt)?.toUtc();
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
      throw StateError('Agent trigger expired');
    }
    final prefs = await _prefs();
    if ((prefs.getStringList(_consumedKey) ?? const <String>[])
        .contains(request.requestId)) {
      throw StateError('Agent trigger has already been consumed');
    }
    if (request.hostInstanceId.isEmpty ||
        request.signatureAlgorithm != _signatureAlgorithm ||
        request.signature == null ||
        request.signature!.isEmpty) {
      throw StateError('Agent trigger is missing trusted signature fields');
    }

    final package = _getPackage(request.agentId);
    if (package == null) {
      throw StateError('Triggered Agent is not installed');
    }
    if (package.providerId != request.providerId) {
      throw StateError('Agent trigger provider does not match installed Agent');
    }
    final binding = package.installBinding;
    if (binding == null ||
        binding.hostInstanceId != request.hostInstanceId ||
        binding.hostSharedSecret.isEmpty) {
      throw StateError('Agent trigger is not bound to a trusted host');
    }
    final expected = _hmacSha256Base64NoPad(
      binding.hostSharedSecret,
      _triggerSignaturePayload(request),
    );
    if (expected != request.signature) {
      throw StateError('Agent trigger signature is invalid');
    }
    return package;
  }

  Future<SharedPreferences> _prefs() async {
    final preferences = _preferences;
    if (preferences != null) return preferences;
    return SharedPreferences.getInstance();
  }
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
  if (value is List) {
    return '[${value.map(_canonicalJson).join(',')}]';
  }
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
