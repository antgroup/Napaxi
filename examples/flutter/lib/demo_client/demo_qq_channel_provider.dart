part of '../main.dart';

class DemoChannelCredentials {
  final String channelName;
  final Map<String, String> secrets;
  final Map<String, dynamic> config;

  const DemoChannelCredentials({
    required this.channelName,
    this.secrets = const {},
    this.config = const {},
  });

  String secret(String key) => secrets[key]?.trim() ?? '';

  String configString(String key, {String fallback = ''}) {
    final value = config[key];
    if (value == null) return fallback;
    return value.toString();
  }

  bool configBool(String key, {bool fallback = false}) {
    final value = config[key];
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return fallback;
  }

  int configInt(String key, {required int fallback}) {
    final value = config[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  bool get isConfigured {
    if (channelName == sdk.QqBotChannelProvider.channelName) {
      return secret(DemoQqChannelCredentials.appIdKey).isNotEmpty &&
          secret(DemoQqChannelCredentials.appSecretKey).isNotEmpty;
    }
    if (channelName == sdk.BluetoothHeadsetChannelProvider.channelName) {
      return configString(
        DemoBluetoothHeadsetChannelCredentials.deviceIdKey,
        fallback: sdk.BluetoothHeadsetChannelCredentials.defaultDeviceId,
      ).trim().isNotEmpty;
    }
    return secrets.values.any((value) => value.trim().isNotEmpty);
  }
}

class DemoChannelStatus {
  final bool connected;
  final bool configured;
  final sdk.NapaxiChannelProviderManifest manifest;
  final List<sdk.NapaxiChannelRecord> channels;
  final String mode;
  final String? gatewayPhase;
  final String? gatewayUrl;
  final int? gatewayShardCount;
  final int? gatewaySessionRemaining;
  final int? gatewaySessionMaxConcurrency;
  final String? sessionId;
  final int? lastOpcode;
  final String? lastEventType;
  final int? gatewayCloseCode;
  final String? gatewayCloseReason;
  final String? lastError;
  final String? credentialFingerprint;
  final String? deviceId;
  final String? deviceName;
  final bool listening;
  final String? lastTranscript;
  final String? lastSpokenText;
  final String? bridgePhase;
  final String? bridgeLastError;
  final int bridgeProcessedCount;
  final int bridgeReplyCount;
  final int heartbeatAckCount;
  final int inboundCount;
  final int deliveredCount;

  const DemoChannelStatus({
    required this.connected,
    required this.configured,
    required this.manifest,
    this.channels = const [],
    this.mode = '',
    this.gatewayPhase,
    this.gatewayUrl,
    this.gatewayShardCount,
    this.gatewaySessionRemaining,
    this.gatewaySessionMaxConcurrency,
    this.sessionId,
    this.lastOpcode,
    this.lastEventType,
    this.gatewayCloseCode,
    this.gatewayCloseReason,
    this.lastError,
    this.credentialFingerprint,
    this.deviceId,
    this.deviceName,
    this.listening = false,
    this.lastTranscript,
    this.lastSpokenText,
    this.bridgePhase,
    this.bridgeLastError,
    this.bridgeProcessedCount = 0,
    this.bridgeReplyCount = 0,
    this.heartbeatAckCount = 0,
    this.inboundCount = 0,
    this.deliveredCount = 0,
  });

  factory DemoChannelStatus.fromQqBot(
    sdk.QqBotChannelStatus status, {
    sdk.NapaxiChannelAgentBridgeStatus? bridgeStatus,
  }) {
    return DemoChannelStatus(
      connected: status.connected,
      configured: status.configured,
      manifest: status.manifest,
      channels: status.channels,
      mode: status.mode,
      gatewayPhase: status.gatewayPhase,
      gatewayUrl: status.gatewayUrl,
      gatewayShardCount: status.gatewayShardCount,
      gatewaySessionRemaining: status.gatewaySessionRemaining,
      gatewaySessionMaxConcurrency: status.gatewaySessionMaxConcurrency,
      sessionId: status.sessionId,
      lastOpcode: status.lastOpcode,
      lastEventType: status.lastEventType,
      gatewayCloseCode: status.gatewayCloseCode,
      gatewayCloseReason: status.gatewayCloseReason,
      lastError: status.lastError,
      credentialFingerprint: status.credentialFingerprint,
      bridgePhase: bridgeStatus?.phase,
      bridgeLastError: bridgeStatus?.lastError,
      bridgeProcessedCount: bridgeStatus?.processedCount ?? 0,
      bridgeReplyCount: bridgeStatus?.replyCount ?? 0,
      heartbeatAckCount: status.heartbeatAckCount,
      inboundCount: status.inboundCount,
      deliveredCount: status.deliveredCount,
    );
  }

  factory DemoChannelStatus.fromBluetoothHeadset(
    sdk.BluetoothHeadsetChannelStatus status, {
    sdk.NapaxiChannelAgentBridgeStatus? bridgeStatus,
  }) {
    return DemoChannelStatus(
      connected: status.connected,
      configured: status.configured,
      manifest: status.manifest,
      channels: status.channels,
      mode: status.mode,
      lastError: status.lastError,
      deviceId:
          status.deviceState?.deviceId ??
          status.manifest.config['device_id']?.toString(),
      deviceName:
          status.deviceState?.displayName ??
          status.manifest.config['device_name']?.toString(),
      listening: status.listening,
      lastTranscript: status.lastTranscript,
      lastSpokenText: status.lastSpokenText,
      bridgePhase: bridgeStatus?.phase,
      bridgeLastError: bridgeStatus?.lastError,
      bridgeProcessedCount: bridgeStatus?.processedCount ?? 0,
      bridgeReplyCount: bridgeStatus?.replyCount ?? 0,
      inboundCount: status.inboundCount,
      deliveredCount: status.deliveredCount,
    );
  }

  DemoChannelStatus copyWith({
    bool? connected,
    bool? configured,
    sdk.NapaxiChannelProviderManifest? manifest,
    List<sdk.NapaxiChannelRecord>? channels,
    String? mode,
    String? gatewayPhase,
    String? gatewayUrl,
    int? gatewayShardCount,
    int? gatewaySessionRemaining,
    int? gatewaySessionMaxConcurrency,
    String? sessionId,
    int? lastOpcode,
    String? lastEventType,
    int? gatewayCloseCode,
    String? gatewayCloseReason,
    String? lastError,
    String? credentialFingerprint,
    String? deviceId,
    String? deviceName,
    bool? listening,
    String? lastTranscript,
    String? lastSpokenText,
    String? bridgePhase,
    String? bridgeLastError,
    int? bridgeProcessedCount,
    int? bridgeReplyCount,
    int? heartbeatAckCount,
    int? inboundCount,
    int? deliveredCount,
  }) {
    return DemoChannelStatus(
      connected: connected ?? this.connected,
      configured: configured ?? this.configured,
      manifest: manifest ?? this.manifest,
      channels: channels ?? this.channels,
      mode: mode ?? this.mode,
      gatewayPhase: gatewayPhase ?? this.gatewayPhase,
      gatewayUrl: gatewayUrl ?? this.gatewayUrl,
      gatewayShardCount: gatewayShardCount ?? this.gatewayShardCount,
      gatewaySessionRemaining:
          gatewaySessionRemaining ?? this.gatewaySessionRemaining,
      gatewaySessionMaxConcurrency:
          gatewaySessionMaxConcurrency ?? this.gatewaySessionMaxConcurrency,
      sessionId: sessionId ?? this.sessionId,
      lastOpcode: lastOpcode ?? this.lastOpcode,
      lastEventType: lastEventType ?? this.lastEventType,
      gatewayCloseCode: gatewayCloseCode ?? this.gatewayCloseCode,
      gatewayCloseReason: gatewayCloseReason ?? this.gatewayCloseReason,
      lastError: lastError ?? this.lastError,
      credentialFingerprint:
          credentialFingerprint ?? this.credentialFingerprint,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      listening: listening ?? this.listening,
      lastTranscript: lastTranscript ?? this.lastTranscript,
      lastSpokenText: lastSpokenText ?? this.lastSpokenText,
      bridgePhase: bridgePhase ?? this.bridgePhase,
      bridgeLastError: bridgeLastError ?? this.bridgeLastError,
      bridgeProcessedCount: bridgeProcessedCount ?? this.bridgeProcessedCount,
      bridgeReplyCount: bridgeReplyCount ?? this.bridgeReplyCount,
      heartbeatAckCount: heartbeatAckCount ?? this.heartbeatAckCount,
      inboundCount: inboundCount ?? this.inboundCount,
      deliveredCount: deliveredCount ?? this.deliveredCount,
    );
  }
}

class DemoChannelInputSource {
  const DemoChannelInputSource({
    required this.channelName,
    required this.accountId,
    required this.agentId,
    required this.label,
    required this.description,
    required this.status,
  });

  factory DemoChannelInputSource.fromBluetoothHeadset(
    DemoChannelStatus status,
  ) {
    final accountId = _demoStatusAccountId(status);
    final label = (status.deviceName ?? '').trim().isNotEmpty
        ? status.deviceName!.trim()
        : (status.deviceId ?? '').trim().isNotEmpty
        ? status.deviceId!.trim()
        : 'Bluetooth device';
    return DemoChannelInputSource(
      channelName: sdk.BluetoothHeadsetChannelProvider.channelName,
      accountId: accountId.isEmpty
          ? sdk.BluetoothHeadsetChannelCredentials.defaultAccountId
          : accountId,
      agentId: _demoStatusAgentId(status),
      label: label,
      description: status.connected ? 'Ready for voice input' : 'Offline',
      status: status,
    );
  }

  final String channelName;
  final String accountId;
  final String agentId;
  final String label;
  final String description;
  final DemoChannelStatus status;

  bool get connected => status.connected;
  bool get configured => status.configured;
}

String _normalizeDemoChannelAgentId(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? sdk.NapaxiEngine.defaultAgentId : trimmed;
}

String _demoStatusAgentId(DemoChannelStatus status) {
  return _normalizeDemoChannelAgentId(
    status.manifest.config['agent_id']?.toString() ?? '',
  );
}

String _demoStatusAccountId(DemoChannelStatus status) {
  final account = status.manifest.accountId.trim();
  if (account.isNotEmpty && account != 'unconfigured') return account;
  final deviceId = status.deviceId?.trim() ?? '';
  if (deviceId.isNotEmpty) return deviceId;
  return '';
}

bool _demoStatusBelongsToAgent(DemoChannelStatus status, String agentId) {
  return _demoStatusAgentId(status) == _normalizeDemoChannelAgentId(agentId);
}

typedef DemoChannelBridgeEvent = sdk.NapaxiChannelAgentBridgeEvent;

class DemoHeadsetTranscriptResult {
  const DemoHeadsetTranscriptResult({
    required this.accepted,
    required this.status,
    this.inboundId,
    this.transcript,
    this.error,
  });

  final bool accepted;
  final DemoChannelStatus status;
  final String? inboundId;
  final String? transcript;
  final String? error;
}

class DemoQqChannelCredentials extends sdk.QqBotChannelCredentials {
  static const configVersionKey = sdk.QqBotChannelCredentials.configVersionKey;
  static const appIdKey = sdk.QqBotChannelCredentials.appIdKey;
  static const appSecretKey = sdk.QqBotChannelCredentials.appSecretKey;
  static const sandboxKey = sdk.QqBotChannelCredentials.sandboxKey;
  static const intentsKey = sdk.QqBotChannelCredentials.intentsKey;
  static const agentIdKey = sdk.QqBotChannelCredentials.agentIdKey;
  static const sessionAccountIdKey = 'session_account_id';

  static const configVersion = sdk.QqBotChannelCredentials.configVersion;
  static const defaultIntents = sdk.QqBotChannelCredentials.defaultIntents;
  static const legacyDefaultIntents =
      sdk.QqBotChannelCredentials.legacyDefaultIntents;

  const DemoQqChannelCredentials({
    required super.appId,
    required super.appSecret,
    super.sandbox,
    super.intents,
    super.agentId,
    this.sessionAccountId = '',
  });

  final String sessionAccountId;

  factory DemoQqChannelCredentials.fromChannelCredentials(
    DemoChannelCredentials credentials,
  ) {
    final qqCredentials = sdk.QqBotChannelCredentials.fromMaps(
      secrets: credentials.secrets,
      config: credentials.config,
    );
    return DemoQqChannelCredentials(
      appId: qqCredentials.appId,
      appSecret: qqCredentials.appSecret,
      sandbox: qqCredentials.sandbox,
      intents: qqCredentials.intents,
      agentId: qqCredentials.agentId,
      sessionAccountId:
          credentials.config[sessionAccountIdKey]?.toString().trim() ?? '',
    );
  }

  DemoChannelCredentials toChannelCredentials() {
    final config = toConfigMap();
    if (sessionAccountId.trim().isNotEmpty) {
      config[sessionAccountIdKey] = sessionAccountId.trim();
    }
    return DemoChannelCredentials(
      channelName: sdk.QqBotChannelProvider.channelName,
      secrets: toSecretMap(),
      config: config,
    );
  }
}

class DemoBluetoothHeadsetChannelCredentials
    extends sdk.BluetoothHeadsetChannelCredentials {
  static const configVersionKey =
      sdk.BluetoothHeadsetChannelCredentials.configVersionKey;
  static const deviceIdKey = sdk.BluetoothHeadsetChannelCredentials.deviceIdKey;
  static const deviceNameKey =
      sdk.BluetoothHeadsetChannelCredentials.deviceNameKey;
  static const accountIdKey =
      sdk.BluetoothHeadsetChannelCredentials.accountIdKey;
  static const agentIdKey = sdk.BluetoothHeadsetChannelCredentials.agentIdKey;
  static const ttsEnabledKey =
      sdk.BluetoothHeadsetChannelCredentials.ttsEnabledKey;
  static const sessionAccountIdKey = 'session_account_id';

  const DemoBluetoothHeadsetChannelCredentials({
    super.deviceId,
    super.deviceName,
    super.accountId,
    super.agentId,
    super.ttsEnabled,
    this.sessionAccountId = '',
  });

  final String sessionAccountId;

  factory DemoBluetoothHeadsetChannelCredentials.fromChannelCredentials(
    DemoChannelCredentials credentials,
  ) {
    final headsetCredentials = sdk.BluetoothHeadsetChannelCredentials.fromMaps(
      secrets: credentials.secrets,
      config: credentials.config,
    );
    return DemoBluetoothHeadsetChannelCredentials(
      deviceId: headsetCredentials.deviceId,
      deviceName: headsetCredentials.deviceName,
      accountId: headsetCredentials.accountId,
      agentId: headsetCredentials.agentId,
      ttsEnabled: headsetCredentials.ttsEnabled,
      sessionAccountId:
          credentials.config[sessionAccountIdKey]?.toString().trim() ?? '',
    );
  }

  DemoChannelCredentials toChannelCredentials() {
    final config = toConfigMap();
    if (sessionAccountId.trim().isNotEmpty) {
      config[sessionAccountIdKey] = sessionAccountId.trim();
    }
    return DemoChannelCredentials(
      channelName: sdk.BluetoothHeadsetChannelProvider.channelName,
      secrets: toSecretMap(),
      config: config,
    );
  }
}
