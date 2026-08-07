import 'dart:convert';

/// Declares a single action a provider agent app exposes: its tool name,
/// JSON-schema parameters and result, risk tier, and confirmation policy.
class AgentAppActionManifest {
  final String actionId;
  final String toolName;
  final String description;
  final String displayName;
  final Map<String, String> localizedDisplayNames;
  final Map<String, String> localizedDescriptions;
  final Map<String, dynamic> parameters;
  final Map<String, dynamic> resultSchema;
  final String risk;
  final String confirmationPolicy;
  final List<String> executionModes;
  final int timeoutSeconds;

  const AgentAppActionManifest({
    required this.actionId,
    required this.toolName,
    required this.description,
    this.displayName = '',
    this.localizedDisplayNames = const <String, String>{},
    this.localizedDescriptions = const <String, String>{},
    this.parameters = const <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{},
    },
    this.resultSchema = const <String, dynamic>{'type': 'object'},
    this.risk = 'high',
    this.confirmationPolicy = 'provider_required',
    this.executionModes = const <String>[],
    this.timeoutSeconds = 600,
  });

  factory AgentAppActionManifest.fromMap(Map<dynamic, dynamic> map) {
    return AgentAppActionManifest(
      actionId: map['action_id'] as String? ?? '',
      toolName: map['tool_name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      displayName: map['display_name'] as String? ?? '',
      localizedDisplayNames: _stringMap(map['localized_display_names']),
      localizedDescriptions: _stringMap(map['localized_descriptions']),
      parameters: _mapValue(map['parameters']),
      resultSchema: _mapValue(map['result_schema']),
      risk: map['risk'] as String? ?? 'high',
      confirmationPolicy:
          map['confirmation_policy'] as String? ?? 'provider_required',
      executionModes: _stringList(map['execution_modes']),
      timeoutSeconds: (map['timeout_seconds'] as num?)?.toInt() ?? 600,
    );
  }

  Map<String, dynamic> toJson() => {
    'action_id': actionId,
    'tool_name': toolName,
    'description': description,
    if (displayName.isNotEmpty) 'display_name': displayName,
    if (localizedDisplayNames.isNotEmpty)
      'localized_display_names': localizedDisplayNames,
    if (localizedDescriptions.isNotEmpty)
      'localized_descriptions': localizedDescriptions,
    'parameters': parameters,
    'result_schema': resultSchema,
    'risk': risk,
    'confirmation_policy': confirmationPolicy,
    'execution_modes': executionModes,
    'timeout_seconds': timeoutSeconds,
  };
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return const <String, String>{};
  return Map<String, String>.unmodifiable({
    for (final entry in value.entries)
      if (entry.key is String && entry.value is String)
        entry.key as String: entry.value as String,
  });
}

/// A registered provider agent app: its identity, system prompt, the set of
/// [AgentAppActionManifest]s it offers, and an optional [AgentAppInstallBinding].
class AgentAppPackage {
  final String providerId;
  final String agentId;
  final String displayName;
  final String description;
  final String systemPrompt;
  final List<AgentAppActionManifest> actions;
  final Map<String, dynamic> handoff;
  final Map<String, dynamic> result;
  final AgentAppInstallBinding? installBinding;
  final String createdAt;
  final String updatedAt;

  const AgentAppPackage({
    required this.providerId,
    required this.agentId,
    required this.displayName,
    this.description = '',
    this.systemPrompt = '',
    this.actions = const <AgentAppActionManifest>[],
    this.handoff = const <String, dynamic>{},
    this.result = const <String, dynamic>{},
    this.installBinding,
    this.autoInvokeEnabled = false,
    this.lastUsedAt = '',
    this.useCount = 0,
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory AgentAppPackage.fromMap(Map<dynamic, dynamic> map) {
    return AgentAppPackage(
      providerId: map['provider_id'] as String? ?? '',
      agentId: map['agent_id'] as String? ?? '',
      displayName: map['display_name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      systemPrompt: map['system_prompt'] as String? ?? '',
      actions: (map['actions'] as List? ?? const [])
          .whereType<Map>()
          .map(AgentAppActionManifest.fromMap)
          .toList(growable: false),
      handoff: _mapValue(map['handoff']),
      result: _mapValue(map['result']),
      installBinding: map['install_binding'] is Map
          ? AgentAppInstallBinding.fromMap(map['install_binding'] as Map)
          : null,
      autoInvokeEnabled: map['auto_invoke_enabled'] as bool? ?? false,
      lastUsedAt: map['last_used_at'] as String? ?? '',
      useCount: (map['use_count'] as num?)?.toInt() ?? 0,
      createdAt: map['created_at'] as String? ?? '',
      updatedAt: map['updated_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'provider_id': providerId,
    'agent_id': agentId,
    'display_name': displayName,
    'description': description,
    'system_prompt': systemPrompt,
    'actions': actions.map((action) => action.toJson()).toList(),
    'handoff': handoff,
    'result': result,
    if (installBinding != null) 'install_binding': installBinding!.toJson(),
    'auto_invoke_enabled': autoInvokeEnabled,
    if (lastUsedAt.isNotEmpty) 'last_used_at': lastUsedAt,
    if (useCount > 0) 'use_count': useCount,
    if (createdAt.isNotEmpty) 'created_at': createdAt,
    if (updatedAt.isNotEmpty) 'updated_at': updatedAt,
  };

  /// Whether the host may expose this app's actions without an explicit @.
  final bool autoInvokeEnabled;

  /// Host-recorded timestamp of the most recent explicit or actual use.
  final String lastUsedAt;

  /// Host-recorded number of explicit selections and actual invocations.
  final int useCount;

  String toJsonString() => jsonEncode(toJson());
}

/// Binds an installed provider app to the host: platform package/bundle ids,
/// signing certificates, shared secret, and deep-link URLs used to hand off
/// actions and receive results across the app boundary.
class AgentAppInstallBinding {
  final String platform;
  final String appPackageName;
  final String activityName;
  final String signingCertSha256;
  final int appVersionCode;
  final int appLastUpdateTimeMs;
  final bool trustedRefreshSupported;
  final String installedAt;
  final String installRequestId;
  final int protocolVersion;
  final String hostPackageName;
  final String hostSigningCertSha256;
  final String hostInstanceId;
  final String hostSharedSecret;
  final String iosBundleId;
  final String iosTeamId;
  final String installUrl;
  final String actionUrl;
  final String universalLinkDomain;
  final String hostBundleId;
  final String hostTeamId;
  final String hostCallbackScheme;
  final bool backgroundTriggerSupported;
  final String hostBackgroundTriggerService;

  const AgentAppInstallBinding({
    required this.platform,
    required this.appPackageName,
    required this.activityName,
    required this.signingCertSha256,
    this.appVersionCode = 0,
    this.appLastUpdateTimeMs = 0,
    this.trustedRefreshSupported = false,
    required this.installedAt,
    required this.installRequestId,
    required this.protocolVersion,
    this.hostPackageName = '',
    this.hostSigningCertSha256 = '',
    this.hostInstanceId = '',
    this.hostSharedSecret = '',
    this.iosBundleId = '',
    this.iosTeamId = '',
    this.installUrl = '',
    this.actionUrl = '',
    this.universalLinkDomain = '',
    this.hostBundleId = '',
    this.hostTeamId = '',
    this.hostCallbackScheme = '',
    this.backgroundTriggerSupported = false,
    this.hostBackgroundTriggerService = '',
  });

  factory AgentAppInstallBinding.fromMap(Map<dynamic, dynamic> map) {
    return AgentAppInstallBinding(
      platform: map['platform'] as String? ?? '',
      appPackageName: map['app_package_name'] as String? ?? '',
      activityName: map['activity_name'] as String? ?? '',
      signingCertSha256: map['signing_cert_sha256'] as String? ?? '',
      appVersionCode: _agentAppInt(map['app_version_code']),
      appLastUpdateTimeMs: _agentAppInt(map['app_last_update_time_ms']),
      trustedRefreshSupported: _agentAppBool(map['trusted_refresh_supported']),
      installedAt: map['installed_at'] as String? ?? '',
      installRequestId: map['install_request_id'] as String? ?? '',
      protocolVersion: (map['protocol_version'] as num?)?.toInt() ?? 1,
      hostPackageName: map['host_package_name'] as String? ?? '',
      hostSigningCertSha256: map['host_signing_cert_sha256'] as String? ?? '',
      hostInstanceId: map['host_instance_id'] as String? ?? '',
      hostSharedSecret: map['host_shared_secret'] as String? ?? '',
      iosBundleId: map['ios_bundle_id'] as String? ?? '',
      iosTeamId: map['ios_team_id'] as String? ?? '',
      installUrl: map['install_url'] as String? ?? '',
      actionUrl: map['action_url'] as String? ?? '',
      universalLinkDomain: map['universal_link_domain'] as String? ?? '',
      hostBundleId: map['host_bundle_id'] as String? ?? '',
      hostTeamId: map['host_team_id'] as String? ?? '',
      hostCallbackScheme: map['host_callback_scheme'] as String? ?? '',
      backgroundTriggerSupported:
          map['background_trigger_supported'] as bool? ?? false,
      hostBackgroundTriggerService:
          map['host_background_trigger_service'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'app_package_name': appPackageName,
    'activity_name': activityName,
    'signing_cert_sha256': signingCertSha256,
    if (appVersionCode > 0) 'app_version_code': appVersionCode,
    if (appLastUpdateTimeMs > 0) 'app_last_update_time_ms': appLastUpdateTimeMs,
    if (trustedRefreshSupported)
      'trusted_refresh_supported': trustedRefreshSupported,
    'installed_at': installedAt,
    'install_request_id': installRequestId,
    'protocol_version': protocolVersion,
    if (hostPackageName.isNotEmpty) 'host_package_name': hostPackageName,
    if (hostSigningCertSha256.isNotEmpty)
      'host_signing_cert_sha256': hostSigningCertSha256,
    if (hostInstanceId.isNotEmpty) 'host_instance_id': hostInstanceId,
    if (hostSharedSecret.isNotEmpty) 'host_shared_secret': hostSharedSecret,
    if (iosBundleId.isNotEmpty) 'ios_bundle_id': iosBundleId,
    if (iosTeamId.isNotEmpty) 'ios_team_id': iosTeamId,
    if (installUrl.isNotEmpty) 'install_url': installUrl,
    if (actionUrl.isNotEmpty) 'action_url': actionUrl,
    if (universalLinkDomain.isNotEmpty)
      'universal_link_domain': universalLinkDomain,
    if (hostBundleId.isNotEmpty) 'host_bundle_id': hostBundleId,
    if (hostTeamId.isNotEmpty) 'host_team_id': hostTeamId,
    if (hostCallbackScheme.isNotEmpty)
      'host_callback_scheme': hostCallbackScheme,
    if (backgroundTriggerSupported)
      'background_trigger_supported': backgroundTriggerSupported,
    if (hostBackgroundTriggerService.isNotEmpty)
      'host_background_trigger_service': hostBackgroundTriggerService,
  };
}

int _agentAppInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _agentAppBool(Object? value) {
  if (value is bool) return value;
  return value?.toString().toLowerCase() == 'true';
}

/// A pending proposal to run a provider action, awaiting host approval.
/// Carries the arguments, an intent summary, expiry/nonce/idempotency fields,
/// and an optional signature for verifying the request's authenticity.
class AgentAppActionProposal {
  final String requestId;
  final String providerId;
  final String agentId;
  final String actionId;
  final String toolName;
  final Map<String, dynamic> arguments;
  final String userIntentSummary;
  final String createdAt;
  final String expiresAt;
  final String nonce;
  final String idempotencyKey;
  final Map<String, dynamic> callback;
  final String risk;
  final String confirmationPolicy;
  final String hostInstanceId;
  final String signatureAlgorithm;
  final String? signature;

  const AgentAppActionProposal({
    required this.requestId,
    required this.providerId,
    required this.agentId,
    required this.actionId,
    required this.toolName,
    this.arguments = const <String, dynamic>{},
    this.userIntentSummary = '',
    required this.createdAt,
    required this.expiresAt,
    required this.nonce,
    required this.idempotencyKey,
    this.callback = const <String, dynamic>{},
    this.risk = 'high',
    this.confirmationPolicy = 'provider_required',
    this.hostInstanceId = '',
    this.signatureAlgorithm = '',
    this.signature,
  });

  factory AgentAppActionProposal.fromMap(Map<dynamic, dynamic> map) {
    return AgentAppActionProposal(
      requestId: map['request_id'] as String? ?? '',
      providerId: map['provider_id'] as String? ?? '',
      agentId: map['agent_id'] as String? ?? '',
      actionId: map['action_id'] as String? ?? '',
      toolName: map['tool_name'] as String? ?? '',
      arguments: _mapValue(map['arguments']),
      userIntentSummary: map['user_intent_summary'] as String? ?? '',
      createdAt: map['created_at'] as String? ?? '',
      expiresAt: map['expires_at'] as String? ?? '',
      nonce: map['nonce'] as String? ?? '',
      idempotencyKey: map['idempotency_key'] as String? ?? '',
      callback: _mapValue(map['callback']),
      risk: map['risk'] as String? ?? 'high',
      confirmationPolicy:
          map['confirmation_policy'] as String? ?? 'provider_required',
      hostInstanceId: map['host_instance_id'] as String? ?? '',
      signatureAlgorithm: map['signature_algorithm'] as String? ?? '',
      signature: map['signature'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'request_id': requestId,
    'provider_id': providerId,
    'agent_id': agentId,
    'action_id': actionId,
    'tool_name': toolName,
    'arguments': arguments,
    'user_intent_summary': userIntentSummary,
    'created_at': createdAt,
    'expires_at': expiresAt,
    'nonce': nonce,
    'idempotency_key': idempotencyKey,
    'callback': callback,
    'risk': risk,
    'confirmation_policy': confirmationPolicy,
    if (hostInstanceId.isNotEmpty) 'host_instance_id': hostInstanceId,
    if (signatureAlgorithm.isNotEmpty)
      'signature_algorithm': signatureAlgorithm,
    if (signature != null) 'signature': signature,
  };
}

/// The outcome of an executed provider action: terminal status, result payload
/// or error, optional provider trace id, and an optional result signature.
class AgentAppActionResult {
  final String requestId;
  final String status;
  final Map<String, dynamic> result;
  final String? error;
  final String? providerTraceId;
  final String completedAt;
  final String? signature;

  const AgentAppActionResult({
    required this.requestId,
    required this.status,
    this.result = const <String, dynamic>{},
    this.error,
    this.providerTraceId,
    required this.completedAt,
    this.signature,
  });

  /// Stable provider error code when the result uses either the v3 structured
  /// error shape or the legacy `code: message` string shape.
  String? get errorCode {
    final value = error?.trim();
    if (value == null || value.isEmpty) return null;
    final separator = value.indexOf(':');
    final candidate = (separator < 0 ? value : value.substring(0, separator))
        .trim();
    if (candidate.isEmpty ||
        !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(candidate)) {
      return null;
    }
    return candidate;
  }

  /// True only for the trusted-validation failure emitted before provider
  /// business logic starts, so restoring the binding and retrying is safe.
  bool get isHostBindingMissing =>
      status == 'failed' && errorCode == 'host_not_bound';

  /// True when trusted Provider state can be safely restored and the same
  /// proposal retried. Both failures happen before business logic or replay
  /// consumption, so a single trusted refresh cannot duplicate side effects.
  bool get isTrustedBindingRejected =>
      status == 'failed' &&
      (errorCode == 'host_not_bound' || errorCode == 'signature_invalid');

  factory AgentAppActionResult.fromMap(Map<dynamic, dynamic> map) {
    return AgentAppActionResult(
      requestId: map['request_id'] as String? ?? '',
      status: map['status'] as String? ?? '',
      result: _mapValue(map['result']),
      error: _actionErrorString(map['error']),
      providerTraceId: map['provider_trace_id'] as String?,
      completedAt: map['completed_at'] as String? ?? '',
      signature: map['signature'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'request_id': requestId,
    'status': status,
    'result': result,
    if (error != null) 'error': error,
    if (providerTraceId != null) 'provider_trace_id': providerTraceId,
    'completed_at': completedAt,
    if (signature != null) 'signature': signature,
  };

  String toJsonString() => jsonEncode(toJson());
}

String? _actionErrorString(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is Map) {
    final code = value['code']?.toString().trim() ?? '';
    final message = value['message']?.toString().trim() ?? '';
    if (code.isNotEmpty && message.isNotEmpty) return '$code: $message';
    if (code.isNotEmpty) return code;
    if (message.isNotEmpty) return message;
  }
  return value.toString();
}

/// A stored ledger entry pairing an [AgentAppActionProposal] with its current
/// status and, once available, its [AgentAppActionResult].
class AgentAppActionRecord {
  final AgentAppActionProposal proposal;
  final String status;
  final AgentAppActionResult? result;
  final String createdAt;
  final String updatedAt;

  const AgentAppActionRecord({
    required this.proposal,
    required this.status,
    this.result,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AgentAppActionRecord.fromMap(Map<dynamic, dynamic> map) {
    final result = map['result'];
    return AgentAppActionRecord(
      proposal: AgentAppActionProposal.fromMap(
        Map<dynamic, dynamic>.from(map['proposal'] as Map? ?? const {}),
      ),
      status: map['status'] as String? ?? '',
      result: result is Map ? AgentAppActionResult.fromMap(result) : null,
      createdAt: map['created_at'] as String? ?? '',
      updatedAt: map['updated_at'] as String? ?? '',
    );
  }
}

/// A fully-resolved action request handed to the host executor: the
/// [AgentAppActionProposal], its matching [AgentAppActionManifest], and the
/// owning package metadata.
class AgentAppActionRequest {
  final AgentAppActionProposal proposal;
  final AgentAppActionManifest action;
  final Map<String, dynamic> package;

  const AgentAppActionRequest({
    required this.proposal,
    required this.action,
    required this.package,
  });

  factory AgentAppActionRequest.fromMap(Map<dynamic, dynamic> map) {
    return AgentAppActionRequest(
      proposal: AgentAppActionProposal.fromMap(
        Map<dynamic, dynamic>.from(map['proposal'] as Map? ?? const {}),
      ),
      action: AgentAppActionManifest.fromMap(
        Map<dynamic, dynamic>.from(map['action'] as Map? ?? const {}),
      ),
      package: _mapValue(map['package']),
    );
  }
}

List<AgentAppPackage> decodeAgentAppPackages(String jsonStr) {
  final decoded = jsonDecode(jsonStr);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map(AgentAppPackage.fromMap)
      .toList(growable: false);
}

List<AgentAppActionRecord> decodeAgentAppActionRecords(String jsonStr) {
  final decoded = jsonDecode(jsonStr);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map(AgentAppActionRecord.fromMap)
      .toList(growable: false);
}

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const <String, dynamic>{};
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value.map((item) => item.toString()).toList(growable: false);
}
