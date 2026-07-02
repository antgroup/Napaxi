import 'dart:convert';

import 'agent_app.dart';

/// Describes how to reach a provider app for install/action: its platform,
/// package/bundle ids, launch activities, signing cert, and deep-link URLs.
class AgentProviderDescriptor {
  final String platform;
  final String packageName;
  final String installActivityName;
  final String activityName;
  final String label;
  final String signingCertSha256;
  final String installUrl;
  final String actionUrl;
  final String universalLinkDomain;
  final String iosBundleId;
  final String iosTeamId;

  const AgentProviderDescriptor({
    this.platform = 'android',
    required this.packageName,
    required this.installActivityName,
    required this.activityName,
    this.label = '',
    this.signingCertSha256 = '',
    this.installUrl = '',
    this.actionUrl = '',
    this.universalLinkDomain = '',
    this.iosBundleId = '',
    this.iosTeamId = '',
  });

  factory AgentProviderDescriptor.fromMap(Map<dynamic, dynamic> map) {
    return AgentProviderDescriptor(
      platform: map['platform'] as String? ?? 'android',
      packageName: map['packageName'] as String? ?? '',
      installActivityName: (map['installActivityName'] as String?) ??
          (map['activityName'] as String?) ??
          '',
      activityName: (map['activityName'] as String?) ??
          (map['installActivityName'] as String?) ??
          '',
      label: map['label'] as String? ?? '',
      signingCertSha256: map['signingCertSha256'] as String? ?? '',
      installUrl: map['installUrl'] as String? ?? '',
      actionUrl: map['actionUrl'] as String? ?? '',
      universalLinkDomain: map['universalLinkDomain'] as String? ?? '',
      iosBundleId: map['iosBundleId'] as String? ?? '',
      iosTeamId: map['iosTeamId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'packageName': packageName,
        'installActivityName': installActivityName,
        'activityName': activityName,
        'label': label,
        'signingCertSha256': signingCertSha256,
        if (installUrl.isNotEmpty) 'installUrl': installUrl,
        if (actionUrl.isNotEmpty) 'actionUrl': actionUrl,
        if (universalLinkDomain.isNotEmpty)
          'universalLinkDomain': universalLinkDomain,
        if (iosBundleId.isNotEmpty) 'iosBundleId': iosBundleId,
        if (iosTeamId.isNotEmpty) 'iosTeamId': iosTeamId,
      };
}

/// A host-signed request asking a provider app to install/register itself,
/// carrying the protocol version, request id, nonce, host identity, and expiry.
class AgentInstallRequest {
  final int protocolVersion;
  final String requestId;
  final String nonce;
  final String hostPackageName;
  final String createdAt;
  final String expiresAt;
  final String hostSigningCertSha256;
  final String hostInstanceId;
  final String hostSharedSecret;
  final String hostBundleId;
  final String hostTeamId;
  final String hostCallbackScheme;
  final String callbackUrl;
  final bool backgroundTriggerSupported;
  final String hostBackgroundTriggerService;

  const AgentInstallRequest({
    this.protocolVersion = 1,
    required this.requestId,
    required this.nonce,
    required this.hostPackageName,
    required this.createdAt,
    required this.expiresAt,
    this.hostSigningCertSha256 = '',
    this.hostInstanceId = '',
    this.hostSharedSecret = '',
    this.hostBundleId = '',
    this.hostTeamId = '',
    this.hostCallbackScheme = '',
    this.callbackUrl = '',
    this.backgroundTriggerSupported = false,
    this.hostBackgroundTriggerService = '',
  });

  factory AgentInstallRequest.fromMap(Map<dynamic, dynamic> map) {
    return AgentInstallRequest(
      protocolVersion: (map['protocol_version'] as num?)?.toInt() ?? 1,
      requestId: map['request_id'] as String? ?? '',
      nonce: map['nonce'] as String? ?? '',
      hostPackageName: map['host_package_name'] as String? ?? '',
      createdAt: map['created_at'] as String? ?? '',
      expiresAt: map['expires_at'] as String? ?? '',
      hostSigningCertSha256: map['host_signing_cert_sha256'] as String? ?? '',
      hostInstanceId: map['host_instance_id'] as String? ?? '',
      hostSharedSecret: map['host_shared_secret'] as String? ?? '',
      hostBundleId: map['host_bundle_id'] as String? ?? '',
      hostTeamId: map['host_team_id'] as String? ?? '',
      hostCallbackScheme: map['host_callback_scheme'] as String? ?? '',
      callbackUrl: map['callback_url'] as String? ?? '',
      backgroundTriggerSupported:
          map['background_trigger_supported'] as bool? ?? false,
      hostBackgroundTriggerService:
          map['host_background_trigger_service'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'protocol_version': protocolVersion,
        'request_id': requestId,
        'nonce': nonce,
        'host_package_name': hostPackageName,
        'created_at': createdAt,
        'expires_at': expiresAt,
        'host_signing_cert_sha256': hostSigningCertSha256,
        'host_instance_id': hostInstanceId,
        'host_shared_secret': hostSharedSecret,
        if (hostBundleId.isNotEmpty) 'host_bundle_id': hostBundleId,
        if (hostTeamId.isNotEmpty) 'host_team_id': hostTeamId,
        if (hostCallbackScheme.isNotEmpty)
          'host_callback_scheme': hostCallbackScheme,
        if (callbackUrl.isNotEmpty) 'callback_url': callbackUrl,
        if (backgroundTriggerSupported)
          'background_trigger_supported': backgroundTriggerSupported,
        if (hostBackgroundTriggerService.isNotEmpty)
          'host_background_trigger_service': hostBackgroundTriggerService,
      };

  String toJsonString() => jsonEncode(toJson());
}

/// The result of an [AgentInstallRequest]: terminal status, the registered
/// [AgentAppPackage] on success, or an error map on failure.
class AgentInstallResult {
  final String status;
  final String requestId;
  final String nonce;
  final AgentAppPackage? package;
  final Map<String, dynamic>? error;
  final String completedAt;

  const AgentInstallResult({
    required this.status,
    required this.requestId,
    required this.nonce,
    this.package,
    this.error,
    required this.completedAt,
  });

  factory AgentInstallResult.fromMap(Map<dynamic, dynamic> map) {
    final packageValue = map['package'];
    return AgentInstallResult(
      status: map['status'] as String? ?? '',
      requestId: map['request_id'] as String? ?? '',
      nonce: map['nonce'] as String? ?? '',
      package:
          packageValue is Map ? AgentAppPackage.fromMap(packageValue) : null,
      error: _mapValue(map['error']),
      completedAt: map['completed_at'] as String? ?? '',
    );
  }
}

Map<String, dynamic>? _mapValue(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}
