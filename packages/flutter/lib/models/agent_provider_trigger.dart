import 'dart:convert';

/// A signed request from a provider app asking the host to start an agent turn,
/// carrying the triggering message, source/event type, payload, and the
/// expiry/nonce/idempotency/signature fields used to authenticate it.
class AgentTriggerRequest {
  final int protocolVersion;
  final String requestId;
  final String providerId;
  final String agentId;
  final String message;
  final String source;
  final String eventType;
  final Map<String, dynamic> payload;
  final String createdAt;
  final String expiresAt;
  final String nonce;
  final String idempotencyKey;
  final String hostInstanceId;
  final String signatureAlgorithm;
  final String? signature;

  const AgentTriggerRequest({
    this.protocolVersion = 2,
    required this.requestId,
    required this.providerId,
    required this.agentId,
    required this.message,
    this.source = '',
    this.eventType = '',
    this.payload = const <String, dynamic>{},
    required this.createdAt,
    required this.expiresAt,
    required this.nonce,
    required this.idempotencyKey,
    this.hostInstanceId = '',
    this.signatureAlgorithm = '',
    this.signature,
  });

  factory AgentTriggerRequest.fromMap(Map<dynamic, dynamic> map) {
    return AgentTriggerRequest(
      protocolVersion: (map['protocol_version'] as num?)?.toInt() ?? 2,
      requestId: map['request_id'] as String? ?? '',
      providerId: map['provider_id'] as String? ?? '',
      agentId: map['agent_id'] as String? ?? '',
      message: map['message'] as String? ?? '',
      source: map['source'] as String? ?? '',
      eventType: map['event_type'] as String? ?? '',
      payload: _mapValue(map['payload']),
      createdAt: map['created_at'] as String? ?? '',
      expiresAt: map['expires_at'] as String? ?? '',
      nonce: map['nonce'] as String? ?? '',
      idempotencyKey: map['idempotency_key'] as String? ?? '',
      hostInstanceId: map['host_instance_id'] as String? ?? '',
      signatureAlgorithm: map['signature_algorithm'] as String? ?? '',
      signature: map['signature'] as String?,
    );
  }

  factory AgentTriggerRequest.fromJsonString(String value) {
    return AgentTriggerRequest.fromMap(jsonDecode(value) as Map);
  }

  Map<String, dynamic> toJson() => {
        'protocol_version': protocolVersion,
        'request_id': requestId,
        'provider_id': providerId,
        'agent_id': agentId,
        'message': message,
        'source': source,
        'event_type': eventType,
        'payload': payload,
        'created_at': createdAt,
        'expires_at': expiresAt,
        'nonce': nonce,
        'idempotency_key': idempotencyKey,
        if (hostInstanceId.isNotEmpty) 'host_instance_id': hostInstanceId,
        if (signatureAlgorithm.isNotEmpty)
          'signature_algorithm': signatureAlgorithm,
        if (signature != null) 'signature': signature,
      };

  String toJsonString() => jsonEncode(toJson());
}

/// A validated [AgentTriggerRequest] paired with the resolved provider display
/// name, ready for the host to surface and act on.
class AcceptedAgentTrigger {
  final AgentTriggerRequest request;
  final String displayName;

  const AcceptedAgentTrigger({
    required this.request,
    required this.displayName,
  });
}

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const <String, dynamic>{};
}
