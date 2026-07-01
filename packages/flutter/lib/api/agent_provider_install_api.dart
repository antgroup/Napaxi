import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import '../models/agent_app.dart';
import '../models/agent_provider_install.dart';
import '../tool_executor.dart';

/// Agent-provider install API: discovers installable providers and drives the
/// install handshake (over the background channel), registering packages.
class AgentProviderInstallApi {
  AgentProviderInstallApi({
    required AgentAppPackage Function(AgentAppPackage package) registerPackage,
    MethodChannel? channel,
  })  : _registerPackage = registerPackage,
        _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.napaxi.flutter/background';
  static const _installTimeout = Duration(minutes: 10);

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

  Future<AgentAppPackage> requestInstall(
    AgentProviderDescriptor provider,
  ) async {
    final request = await _createInstallRequest();
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
          response['error']?.toString() ?? 'Install result missing');
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
    return _registerPackage(package);
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

  Future<AgentInstallRequest> _createInstallRequest() async {
    final now = DateTime.now().toUtc();
    final hostInfo = Map<String, dynamic>.from(
      await _channel.invokeMethod<Map<dynamic, dynamic>>(
            'getAgentProviderHostInfo',
          ) ??
          const {},
    );
    final requestId = _randomHex(16);
    final callbackScheme = hostInfo['callbackScheme'] as String? ?? '';
    return AgentInstallRequest(
      protocolVersion: 2,
      requestId: requestId,
      nonce: _randomHex(16),
      hostPackageName: (hostInfo['packageName'] as String?) ??
          (hostInfo['bundleId'] as String?) ??
          '',
      createdAt: now.toIso8601String(),
      expiresAt: now.add(_installTimeout).toIso8601String(),
      hostSigningCertSha256: hostInfo['signingCertSha256'] as String? ?? '',
      hostInstanceId: _randomHex(16),
      hostSharedSecret: _randomHex(32),
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
class AndroidAgentProviderActionExecutor implements AgentAppActionExecutor {
  AndroidAgentProviderActionExecutor({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.napaxi.flutter/background';

  final MethodChannel _channel;

  @override
  Future<AgentAppActionResult> execute(AgentAppActionRequest request) async {
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
  IosAgentProviderActionExecutor({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.napaxi.flutter/background';

  final MethodChannel _channel;

  @override
  Future<AgentAppActionResult> execute(AgentAppActionRequest request) async {
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
        AgentAppActionRequest request) =>
    {
      'proposal': request.proposal.toJson(),
      'action': request.action.toJson(),
      'package': request.package,
    };
