import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/agent_app.dart';
import '../models/agent_app_diagnostics.dart';
import '../models/agent_provider_install.dart';
import '../tool_executor.dart';

/// Agent-provider install API: discovers installable providers and drives the
/// install handshake (over the background channel), registering packages.
class AgentProviderInstallApi {
  AgentProviderInstallApi({
    required AgentAppPackage Function(AgentAppPackage package) registerPackage,
    MethodChannel? channel,
  }) : _registerPackage = registerPackage,
       _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.napaxi.flutter/background';
  static const _installTimeout = Duration(minutes: 10);
  static const _hostInstanceIdKey = 'napaxi.agent_provider.host_instance_id.v1';

  final AgentAppPackage Function(AgentAppPackage package) _registerPackage;
  final MethodChannel _channel;

  Future<List<AgentProviderDescriptor>> discoverProviders() async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'listAgentProviders',
    );
    return (raw ?? const <dynamic>[])
        .whereType<Map>()
        .map(AgentProviderDescriptor.fromMap)
        .toList(growable: false);
  }

  /// Finds an installed Provider by its OS package/bundle identifier.
  Future<AgentProviderDescriptor?> discoverProviderForPackage(
    String packageName,
  ) async {
    final expected = packageName.trim();
    if (expected.isEmpty) return null;
    final providers = await discoverProviders();
    for (final provider in providers) {
      if (provider.packageName == expected ||
          provider.iosBundleId == expected) {
        return provider;
      }
    }
    return null;
  }

  /// Discovers and runs the trusted enable handshake for a newly installed
  /// Provider App. APK installation itself remains an explicit OS/user step.
  Future<AgentAppPackage> enableInstalledProvider(String packageName) async {
    final provider = await discoverProviderForPackage(packageName);
    if (provider == null) {
      throw StateError('Installed Agent App provider not found: $packageName');
    }
    return requestInstall(provider);
  }

  Future<AgentAppPackage> requestInstall(
    AgentProviderDescriptor provider,
  ) async {
    final request = await _createInstallRequest();
    return _requestInstall(provider, request, registerPackage: true);
  }

  /// Restores provider-side trusted state using the binding already owned by
  /// Core. This is intentionally different from a fresh install: identity and
  /// shared-secret material are preserved so the rejected proposal can be
  /// retried without changing its signature or idempotency key.
  Future<AgentAppPackage> restoreBinding(AgentAppPackage installed) async {
    return _restoreBinding(installed, registerPackage: false);
  }

  /// Refreshes a previously trusted Provider after an in-place app update.
  ///
  /// The OS package/bundle identity, signing identity, provider id, agent id,
  /// Host id, and shared secret must all remain stable. The returned manifest
  /// is registered in Core so newly added or removed actions take effect while
  /// Core preserves host-owned state such as the auto-invoke preference.
  Future<AgentAppPackage> refreshBinding(AgentAppPackage installed) async {
    return _restoreBinding(installed, registerPackage: true);
  }

  Future<AgentAppPackage> _restoreBinding(
    AgentAppPackage installed, {
    required bool registerPackage,
  }) async {
    final binding = installed.installBinding;
    if (binding == null ||
        binding.hostInstanceId.isEmpty ||
        binding.hostSharedSecret.isEmpty) {
      throw StateError('Agent App has no restorable trusted binding');
    }
    final platformId = binding.platform == 'ios'
        ? binding.iosBundleId
        : binding.appPackageName;
    final provider = binding.platform == 'ios'
        ? AgentProviderDescriptor(
            platform: 'ios',
            packageName: '',
            installActivityName: '',
            activityName: '',
            iosBundleId: binding.iosBundleId,
            iosTeamId: binding.iosTeamId,
            installUrl: binding.installUrl,
            actionUrl: binding.actionUrl,
            universalLinkDomain: binding.universalLinkDomain,
          )
        : await discoverProviderForPackage(platformId);
    if (provider == null) {
      throw StateError('Installed Agent App provider not found: $platformId');
    }
    if (binding.platform != 'ios' &&
        (provider.signingCertSha256.isEmpty ||
            provider.signingCertSha256.toLowerCase() !=
                binding.signingCertSha256.toLowerCase())) {
      throw StateError(
        'Provider app signature changed; explicit reconnect is required',
      );
    }
    final request = await _createInstallRequest(existingBinding: binding);
    final restored = await _requestInstall(
      provider,
      request,
      registerPackage: false,
    );
    if (restored.providerId != installed.providerId ||
        restored.agentId != installed.agentId) {
      throw StateError(
        'Restored Agent App identity does not match installation',
      );
    }
    return registerPackage ? _registerPackage(restored) : restored;
  }

  Future<AgentAppPackage> _requestInstall(
    AgentProviderDescriptor provider,
    AgentInstallRequest request, {
    required bool registerPackage,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'requestAgentProviderInstall',
      <String, dynamic>{
        'provider': provider.toJson(),
        'requestJson': request.toJsonString(),
      },
    );
    final response = Map<String, dynamic>.from(raw ?? const {});
    final installResultJson = response['installResultJson'] as String? ?? '';
    if (installResultJson.isEmpty) {
      throw StateError(
        response['error']?.toString() ?? 'Install result missing',
      );
    }

    final installResult = AgentInstallResult.fromMap(
      jsonDecode(installResultJson) as Map,
    );
    _validateInstallResult(installResult, request);

    final returnedPackage = installResult.package;
    if (returnedPackage == null) {
      throw StateError('Provider did not return an Agent package');
    }

    final binding = AgentAppInstallBinding.fromMap(
      Map<dynamic, dynamic>.from(
        response['installBinding'] as Map? ?? const {},
      ),
    );
    final package = _withInstallBinding(returnedPackage, binding);
    return registerPackage ? _registerPackage(package) : package;
  }

  Future<AgentAppPackage?> installFromLaunchIntent() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getPendingProviderInstallRequest',
    );
    if (raw == null || raw.isEmpty) return null;
    var provider = AgentProviderDescriptor.fromMap(raw);
    if (provider.platform != 'ios' &&
        (provider.installActivityName.isEmpty ||
            provider.activityName.isEmpty)) {
      final discovered = await discoverProviders();
      provider = discovered.firstWhere(
        (candidate) => candidate.packageName == provider.packageName,
        orElse: () => provider,
      );
    }
    final installed = await requestInstall(provider);
    await _channel.invokeMethod<void>('clearPendingProviderInstallRequest');
    return installed;
  }

  /// Reads Provider-owned crash reports through the model-hidden trusted
  /// diagnostics endpoint. Apps created before diagnostics support return an
  /// unsupported snapshot instead of failing their existing Agent actions.
  Future<AgentAppDiagnosticsSnapshot> listDiagnostics(
    AgentAppPackage package,
  ) => _requestDiagnostics(package, operation: 'list');

  /// Enables or disables debug-level collection inside the Provider app. Info,
  /// warning, error, and crash events remain enabled in both modes.
  Future<AgentAppDiagnosticsSnapshot> setDetailedDiagnostics(
    AgentAppPackage package,
    bool enabled,
  ) => _requestDiagnostics(
    package,
    operation: 'configure',
    detailedLogging: enabled,
  );

  Future<AgentAppDiagnosticsSnapshot> _requestDiagnostics(
    AgentAppPackage package, {
    required String operation,
    bool detailedLogging = false,
  }) async {
    final binding = package.installBinding;
    if (binding == null || binding.platform != 'android') {
      return const AgentAppDiagnosticsSnapshot(supported: false);
    }
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'listAgentProviderDiagnostics',
      <String, dynamic>{
        'packageJson': package.toJsonString(),
        'operation': operation,
        'detailedLogging': detailedLogging,
      },
    );
    final envelope = Map<String, dynamic>.from(raw ?? const {});
    final supported = envelope['supported'] as bool? ?? false;
    final platformError = envelope['error']?.toString() ?? '';
    if (!supported) {
      return AgentAppDiagnosticsSnapshot(
        supported: false,
        error: platformError,
      );
    }
    final responseJson = envelope['responseJson'] as String? ?? '';
    if (responseJson.isEmpty) {
      return AgentAppDiagnosticsSnapshot(
        supported: true,
        error: platformError.isEmpty
            ? 'Provider diagnostics response missing'
            : platformError,
      );
    }
    final response = jsonDecode(responseJson) as Map<String, dynamic>;
    final status = response['status'] as String? ?? '';
    final responseError = response['error'];
    final error = responseError is Map
        ? responseError['message']?.toString() ?? responseError.toString()
        : responseError?.toString() ?? '';
    if (status != 'succeeded') {
      return AgentAppDiagnosticsSnapshot(supported: true, error: error);
    }
    final reports = (response['reports'] as List? ?? const <Object>[])
        .whereType<Map>()
        .map(AgentAppDiagnosticReport.fromMap)
        .toList(growable: false);
    final logs = (response['logs'] as List? ?? const <Object>[])
        .whereType<Map>()
        .map(AgentAppDiagnosticLogEntry.fromMap)
        .toList(growable: false);
    return AgentAppDiagnosticsSnapshot(
      supported: true,
      reports: reports,
      logs: logs,
      detailedLoggingEnabled:
          response['detailed_logging_enabled'] as bool? ?? false,
    );
  }

  Future<AgentInstallRequest> _createInstallRequest({
    AgentAppInstallBinding? existingBinding,
  }) async {
    final now = DateTime.now().toUtc();
    final hostInfo = Map<String, dynamic>.from(
      await _channel.invokeMethod<Map<dynamic, dynamic>>(
            'getAgentProviderHostInfo',
          ) ??
          const {},
    );
    final requestId = _randomHex(16);
    final callbackScheme = hostInfo['callbackScheme'] as String? ?? '';
    final currentHostId =
        (hostInfo['packageName'] as String?) ??
        (hostInfo['bundleId'] as String?) ??
        '';
    final currentHostSigningCert =
        hostInfo['signingCertSha256'] as String? ?? '';
    if (existingBinding != null &&
        ((existingBinding.hostPackageName.isNotEmpty &&
                existingBinding.hostPackageName != currentHostId) ||
            (existingBinding.hostSigningCertSha256.isNotEmpty &&
                existingBinding.hostSigningCertSha256.toLowerCase() !=
                    currentHostSigningCert.toLowerCase()))) {
      throw StateError(
        'Host identity changed; explicit Agent App reconnect is required',
      );
    }
    final hostInstanceId = existingBinding?.hostInstanceId.isNotEmpty == true
        ? existingBinding!.hostInstanceId
        : await _stableHostInstanceId();
    final hostSharedSecret =
        existingBinding?.hostSharedSecret.isNotEmpty == true
        ? existingBinding!.hostSharedSecret
        : _randomHex(32);
    return AgentInstallRequest(
      protocolVersion: 2,
      requestId: requestId,
      nonce: _randomHex(16),
      hostPackageName: currentHostId,
      createdAt: now.toIso8601String(),
      expiresAt: now.add(_installTimeout).toIso8601String(),
      hostSigningCertSha256: currentHostSigningCert,
      hostInstanceId: hostInstanceId,
      hostSharedSecret: hostSharedSecret,
      hostBundleId: hostInfo['bundleId'] as String? ?? '',
      hostTeamId: hostInfo['teamId'] as String? ?? '',
      hostCallbackScheme: callbackScheme,
      callbackUrl: callbackScheme.isEmpty
          ? ''
          : '$callbackScheme://agent-provider/install-callback',
      backgroundTriggerSupported:
          hostInfo['backgroundTriggerSupported'] as bool? ?? false,
      hostBackgroundTriggerService:
          hostInfo['backgroundTriggerService'] as String? ?? '',
    );
  }

  Future<String> _stableHostInstanceId() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_hostInstanceIdKey)?.trim();
    if (existing != null && existing.isNotEmpty) return existing;
    final created = _randomHex(16);
    await preferences.setString(_hostInstanceIdKey, created);
    return created;
  }

  void _validateInstallResult(
    AgentInstallResult result,
    AgentInstallRequest request,
  ) {
    if (DateTime.now().toUtc().isAfter(DateTime.parse(request.expiresAt))) {
      throw StateError('Install request expired');
    }
    if (result.requestId != request.requestId ||
        result.nonce != request.nonce) {
      throw StateError('Install result does not match the request');
    }
    if (result.status != 'succeeded') {
      throw StateError(result.error?.toString() ?? 'Provider install failed');
    }
  }

  AgentAppPackage _withInstallBinding(
    AgentAppPackage package,
    AgentAppInstallBinding binding,
  ) {
    return AgentAppPackage(
      providerId: package.providerId,
      agentId: package.agentId,
      displayName: package.displayName,
      description: package.description,
      systemPrompt: package.systemPrompt,
      actions: package.actions,
      handoff: package.handoff,
      result: package.result,
      installBinding: binding,
      createdAt: package.createdAt,
      updatedAt: package.updatedAt,
    );
  }

  String _randomHex(int byteCount) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteCount, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Android [AgentAppActionExecutor] that dispatches provider actions over the
/// background method channel.
abstract interface class AgentProviderBindingRepair {
  Future<bool> repair(AgentAppActionRequest request);
}

class AndroidAgentProviderActionExecutor implements AgentAppActionExecutor {
  AndroidAgentProviderActionExecutor({
    MethodChannel? channel,
    AgentProviderBindingRepair? repairBinding,
  }) : _channel = channel ?? const MethodChannel(_channelName),
       _repairBinding = repairBinding;

  static const _channelName = 'com.napaxi.flutter/background';

  final MethodChannel _channel;
  final AgentProviderBindingRepair? _repairBinding;

  @override
  Future<AgentAppActionResult> execute(AgentAppActionRequest request) async {
    final first = await _executeOnce(request);
    final repairBinding = _repairBinding;
    if (!first.isTrustedBindingRejected || repairBinding == null) return first;
    try {
      final repaired = await repairBinding.repair(request);
      if (!repaired) return first;
    } catch (error) {
      return AgentAppActionResult(
        requestId: request.proposal.requestId,
        status: 'failed',
        error: 'binding_repair_failed: $error',
        completedAt: DateTime.now().toUtc().toIso8601String(),
      );
    }
    return _executeOnce(request);
  }

  Future<AgentAppActionResult> _executeOnce(
    AgentAppActionRequest request,
  ) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'executeAgentProviderAction',
      <String, dynamic>{
        'requestJson': jsonEncode(agentProviderRequestToJson(request)),
      },
    );
    final resultJson = raw?['resultJson'] as String?;
    if (resultJson == null || resultJson.isEmpty) {
      return AgentAppActionResult(
        requestId: request.proposal.requestId,
        status: 'failed',
        error: raw?['error']?.toString() ?? 'Provider action result missing',
        completedAt: DateTime.now().toUtc().toIso8601String(),
      );
    }
    return AgentAppActionResult.fromMap(jsonDecode(resultJson) as Map);
  }
}

/// iOS [AgentAppActionExecutor] that dispatches provider actions over the
/// background method channel.
class IosAgentProviderActionExecutor implements AgentAppActionExecutor {
  IosAgentProviderActionExecutor({
    MethodChannel? channel,
    AgentProviderBindingRepair? repairBinding,
  }) : _channel = channel ?? const MethodChannel(_channelName),
       _repairBinding = repairBinding;

  static const _channelName = 'com.napaxi.flutter/background';

  final MethodChannel _channel;
  final AgentProviderBindingRepair? _repairBinding;

  @override
  Future<AgentAppActionResult> execute(AgentAppActionRequest request) async {
    final first = await _executeOnce(request);
    final repairBinding = _repairBinding;
    if (!first.isTrustedBindingRejected || repairBinding == null) return first;
    try {
      final repaired = await repairBinding.repair(request);
      if (!repaired) return first;
    } catch (error) {
      return AgentAppActionResult(
        requestId: request.proposal.requestId,
        status: 'failed',
        error: 'binding_repair_failed: $error',
        completedAt: DateTime.now().toUtc().toIso8601String(),
      );
    }
    return _executeOnce(request);
  }

  Future<AgentAppActionResult> _executeOnce(
    AgentAppActionRequest request,
  ) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'executeAgentProviderAction',
      <String, dynamic>{
        'requestJson': jsonEncode(agentProviderRequestToJson(request)),
      },
    );
    final resultJson = raw?['resultJson'] as String?;
    if (resultJson == null || resultJson.isEmpty) {
      return AgentAppActionResult(
        requestId: request.proposal.requestId,
        status: 'failed',
        error: raw?['error']?.toString() ?? 'Provider action result missing',
        completedAt: DateTime.now().toUtc().toIso8601String(),
      );
    }
    return AgentAppActionResult.fromMap(jsonDecode(resultJson) as Map);
  }
}

Map<String, dynamic> agentProviderRequestToJson(
  AgentAppActionRequest request,
) => {
  'proposal': request.proposal.toJson(),
  'action': request.action.toJson(),
  'package': request.package,
};
