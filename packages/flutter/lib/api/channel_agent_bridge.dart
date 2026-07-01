import 'dart:async';
import 'dart:convert';

import '../engine.dart';
import '../models/background.dart';
import '../models/channel.dart';
import '../models/chat_event.dart';
import '../models/config.dart';
import '../models/session.dart';

typedef NapaxiChannelBridgeReconnect = Future<void> Function();

typedef NapaxiChannelBridgeConnected = bool Function();

typedef NapaxiChannelAgentEnsurer = Future<void> Function(String agentId);

class NapaxiChannelAgentBridgeEvent {
  const NapaxiChannelAgentBridgeEvent({
    required this.channelName,
    required this.agentId,
    required this.session,
    required this.inboundId,
    required this.peerKind,
    required this.peerId,
    required this.senderId,
    required this.inboundText,
    required this.responseText,
    required this.createdAt,
    required this.type,
    this.assistantMessageId,
    this.channelDisplayName,
    this.chatEvent,
    this.openAssistant = false,
    this.completeAssistant = false,
    this.platformMessageId,
    this.platformThreadId,
    this.peerDisplayName,
    this.senderDisplayName,
    this.humanRequestId,
    this.humanQuestion,
    this.humanOptions = const [],
    this.humanContext,
    this.humanResponseRequestId,
    this.error,
    this.raw = const {},
  });

  final String type;
  final String channelName;
  final String? channelDisplayName;
  final String agentId;
  final SessionKey session;
  final String inboundId;
  final String? platformMessageId;
  final String? platformThreadId;
  final String peerKind;
  final String peerId;
  final String? peerDisplayName;
  final String senderId;
  final String? senderDisplayName;
  final String inboundText;
  final String responseText;
  final DateTime createdAt;
  final String? assistantMessageId;
  final ChatEvent? chatEvent;
  final bool openAssistant;
  final bool completeAssistant;
  final String? humanRequestId;
  final String? humanQuestion;
  final List<String> humanOptions;
  final String? humanContext;
  final String? humanResponseRequestId;
  final String? error;
  final Map<String, dynamic> raw;

  String get sessionId => session.threadId;

  String get displayTitle {
    final channelLabel = _channelDisplayLabel(channelName, channelDisplayName);
    final peerName = peerDisplayName?.trim();
    if (peerName != null && peerName.isNotEmpty) {
      return '$channelLabel $peerName';
    }
    final senderName = senderDisplayName?.trim();
    if (senderName != null && senderName.isNotEmpty) {
      return '$channelLabel $senderName';
    }
    final endpointLabel = _endpointKindDisplayLabel(peerKind);
    if (endpointLabel.isNotEmpty) {
      return '$channelLabel $endpointLabel';
    }
    return '$channelLabel Channel';
  }
}

class NapaxiChannelAgentBridgeStatus {
  const NapaxiChannelAgentBridgeStatus({
    required this.running,
    required this.phase,
    this.lastError,
    this.processedCount = 0,
    this.replyCount = 0,
    this.activePumps = 0,
  });

  final bool running;
  final String phase;
  final String? lastError;
  final int processedCount;
  final int replyCount;
  final int activePumps;
}

class NapaxiChannelAgentBridge {
  NapaxiChannelAgentBridge({
    required this.engine,
    required this.channelName,
    required this.accountId,
    String? agentId,
    this.channelAccountId,
    this.pollInterval = const Duration(seconds: 1),
    this.inboundBatchSize = 4,
    this.keepAliveInBackground = false,
    this.backgroundConfig,
    this.isProviderConnected,
    this.reconnectProvider,
    this.ensureAgent,
    String? bridgeId,
  })  : agentId = _normalizedAgentId(agentId),
        bridgeId = bridgeId?.trim().isNotEmpty == true
            ? bridgeId!.trim()
            : 'napaxi.channel_agent_bridge';

  final NapaxiEngine engine;
  final String channelName;
  final String accountId;
  final String? channelAccountId;
  final String agentId;
  final Duration pollInterval;
  final int inboundBatchSize;
  final bool keepAliveInBackground;
  final BackgroundConfig? backgroundConfig;
  final NapaxiChannelBridgeConnected? isProviderConnected;
  final NapaxiChannelBridgeReconnect? reconnectProvider;
  final NapaxiChannelAgentEnsurer? ensureAgent;
  final String bridgeId;

  final StreamController<NapaxiChannelAgentBridgeEvent> _events =
      StreamController<NapaxiChannelAgentBridgeEvent>.broadcast();

  Timer? _timer;
  bool _leaseInProgress = false;
  bool _backgroundKeepAliveStarted = false;
  String _phase = 'stopped';
  String? _lastError;
  int _processedCount = 0;
  int _replyCount = 0;
  int _activePumps = 0;

  Stream<NapaxiChannelAgentBridgeEvent> get events => _events.stream;

  NapaxiChannelAgentBridgeStatus get status => NapaxiChannelAgentBridgeStatus(
        running: _timer != null,
        phase: _phase,
        lastError: _lastError,
        processedCount: _processedCount,
        replyCount: _replyCount,
        activePumps: _activePumps,
      );

  void start() {
    _timer?.cancel();
    _phase = 'idle';
    _lastError = null;
    _registerDefaultRoute();
    _timer = Timer.periodic(pollInterval, (_) {
      unawaited(pump());
    });
    unawaited(pump());
    unawaited(_ensureBackgroundKeepAlive());
  }

  void stop({bool stopBackground = true}) {
    _timer?.cancel();
    _timer = null;
    _leaseInProgress = false;
    _phase = 'stopped';
    if (stopBackground && _backgroundKeepAliveStarted) {
      _backgroundKeepAliveStarted = false;
      unawaited(engine.stopBackgroundService());
    }
  }

  Future<void> dispose({bool stopBackground = true}) async {
    stop(stopBackground: stopBackground);
    await _events.close();
  }

  Future<void> pump() async {
    if (_timer == null) {
      _phase = 'stopped';
      return;
    }
    if (_leaseInProgress) return;
    final runtimeIssue = _channelRuntimeConfigIssue(engine.config);
    if (runtimeIssue != null) {
      _phase = 'waiting_runtime';
      _lastError = runtimeIssue;
      unawaited(_ensureBackgroundKeepAlive());
      return;
    }
    if (isProviderConnected != null && !isProviderConnected!()) {
      _phase = 'reconnecting_provider';
      if (reconnectProvider != null) {
        try {
          await reconnectProvider!();
        } catch (error) {
          _lastError = 'Channel provider reconnect failed: $error';
        }
      }
      if (isProviderConnected != null && !isProviderConnected!()) {
        _phase = 'waiting_provider';
        unawaited(_ensureBackgroundKeepAlive());
        return;
      }
    }
    _leaseInProgress = true;
    _phase = 'pumping_core';
    unawaited(_driveCorePump());
  }

  void _registerDefaultRoute() {
    try {
      engine.channelAgents.registerRoute(
        NapaxiChannelAgentRoute.channelDefault(
          channelName: channelName,
          channelAccountId: channelAccountId,
          sessionAccountId: accountId,
          agentId: agentId,
        ),
      );
    } catch (error) {
      _lastError = 'Channel route registration failed: $error';
    }
  }

  Future<void> _driveCorePump() async {
    var leaseReleased = false;
    _activePumps += 1;
    try {
      await ensureAgent?.call(agentId);
      await for (final raw in engine.channelAgents.streamPump(
        configJson: engine.config.toJson(),
        bridgeConfigJson: jsonEncode(_bridgeConfig()),
      )) {
        if (!leaseReleased) {
          _leaseInProgress = false;
          leaseReleased = true;
        }
        await _handleCoreEvent(raw);
      }
      if (_phase != 'stopped') _phase = 'idle';
    } catch (error) {
      _lastError = 'Channel core pump failed: $error';
      _phase = 'error';
    } finally {
      if (!leaseReleased) {
        _leaseInProgress = false;
      }
      _activePumps = _activePumps > 0 ? _activePumps - 1 : 0;
      if (_backgroundKeepAliveStarted) {
        unawaited(_ensureBackgroundKeepAlive());
      }
    }
  }

  Map<String, dynamic> _bridgeConfig() => {
        'channel_name': channelName,
        'session_account_id': accountId,
        'default_agent_id': agentId,
        'inbound_limit': inboundBatchSize,
        'max_iterations': engine.config.maxToolIterations,
      };

  Future<void> _handleCoreEvent(String raw) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return;
    final map = Map<String, dynamic>.from(decoded);
    final type = map['type'] as String? ?? '';
    switch (type) {
      case 'inbound_received':
        _processedCount += 1;
        _phase = 'running_agent';
      case 'human_question_queued':
        _replyCount += 1;
        _phase = 'waiting_human';
        await engine.channelProviders.pump(
          channelName,
          accountId: channelAccountId,
        );
      case 'outbound_queued':
        _replyCount += 1;
        _phase = 'deliver_reply';
        await engine.channelProviders.pump(
          channelName,
          accountId: channelAccountId,
        );
      case 'human_answer_received':
        _phase = 'running_agent';
      case 'failed':
        _phase = 'error';
        _lastError = map['error'] as String?;
      case 'completed':
        _phase = 'idle';
      default:
        break;
    }
    _emit(map);
  }

  void _emit(Map<String, dynamic> map) {
    if (_events.isClosed) return;
    final type = map['type'] as String? ?? '';
    final chatEvent = _chatEventFromMap(map['chat_event']);
    final session = _sessionKeyFromMap(map['session_key']);
    final inboundId = map['inbound_id'] as String? ?? '';
    final eventChannelName = map['channel_name'] as String? ?? channelName;
    final eventChannelAccountId =
        map['channel_account_id'] as String? ?? channelAccountId;
    _events.add(
      NapaxiChannelAgentBridgeEvent(
        type: type,
        channelName: eventChannelName,
        channelDisplayName: engine.channelProviders
            .providerManifest(eventChannelName,
                accountId: eventChannelAccountId)
            ?.displayName,
        agentId: map['agent_id'] as String? ?? agentId,
        session: session,
        inboundId: inboundId,
        platformMessageId: map['platform_message_id'] as String?,
        platformThreadId: map['platform_thread_id'] as String?,
        peerKind: map['peer_kind'] as String? ?? '',
        peerId: map['peer_id'] as String? ?? '',
        peerDisplayName: map['peer_display_name'] as String?,
        senderId: map['sender_id'] as String? ?? '',
        senderDisplayName: map['sender_display_name'] as String?,
        inboundText: map['display_text'] as String? ?? '',
        responseText: map['response_text'] as String? ?? '',
        assistantMessageId: inboundId.isEmpty ? null : '$bridgeId:$inboundId',
        chatEvent: chatEvent,
        openAssistant: _opensAssistant(type),
        completeAssistant: _completesAssistant(type),
        humanRequestId: map['human_request_id'] as String?,
        humanQuestion: map['human_question'] as String?,
        humanOptions: _stringList(map['human_options']),
        humanContext: map['human_context'] as String?,
        humanResponseRequestId: type == 'human_answer_received'
            ? map['human_request_id'] as String?
            : null,
        error: map['error'] as String?,
        createdAt: DateTime.now(),
        raw: map,
      ),
    );
  }

  Future<void> _ensureBackgroundKeepAlive() async {
    if (!keepAliveInBackground || backgroundConfig == null) return;
    try {
      engine.updateBackgroundConfig(backgroundConfig!);
      await engine.startBackgroundService();
      _backgroundKeepAliveStarted = true;
    } catch (error) {
      _backgroundKeepAliveStarted = false;
      _lastError = 'Channel background keep-alive failed: $error';
    }
  }
}

String? _channelRuntimeConfigIssue(LlmConfig config) {
  if (config.provider.trim().isEmpty) {
    return 'Channel runtime LLM provider is not configured';
  }
  if (config.model.trim().isEmpty) {
    return 'Channel runtime LLM model is not configured';
  }
  if (config.apiKey.trim().isEmpty) {
    return 'Channel runtime LLM API key is not configured';
  }
  return null;
}

SessionKey _sessionKeyFromMap(Object? value) {
  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    return SessionKey(
      channelType: map['channel_type'] as String? ?? 'app',
      accountId: map['account_id'] as String? ?? '',
      threadId: map['thread_id'] as String? ?? '',
    );
  }
  return const SessionKey(channelType: 'app', accountId: '', threadId: '');
}

ChatEvent? _chatEventFromMap(Object? value) {
  if (value is! Map) return null;
  try {
    return ChatEvent.fromMap(Map<String, dynamic>.from(value));
  } catch (_) {
    return null;
  }
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).toList(growable: false);
}

bool _opensAssistant(String type) {
  return const {
    'inbound_received',
    'chat_event',
    'human_question_queued',
    'human_answer_received',
  }.contains(type);
}

bool _completesAssistant(String type) {
  return const {
    'human_question_queued',
    'outbound_queued',
    'completed',
    'failed',
  }.contains(type);
}

String _normalizedAgentId(String? agentId) {
  final trimmed = agentId?.trim() ?? '';
  return trimmed.isEmpty ? NapaxiEngine.defaultAgentId : trimmed;
}

String _channelDisplayLabel(String channelName, String? channelDisplayName) {
  final displayName = channelDisplayName?.trim();
  if (displayName != null && displayName.isNotEmpty) return displayName;
  final trimmed = channelName.trim();
  return trimmed.isEmpty ? 'Channel' : trimmed;
}

String _endpointKindDisplayLabel(String peerKind) {
  final normalized = peerKind.trim();
  if (normalized.isEmpty) return '';
  switch (normalized) {
    case NapaxiChannelEndpointKind.direct:
      return '私聊';
    case NapaxiChannelEndpointKind.group:
      return '群聊';
    case NapaxiChannelEndpointKind.room:
      return '频道';
    case NapaxiChannelEndpointKind.thread:
      return '话题';
    case NapaxiChannelEndpointKind.broadcast:
      return '广播';
    case NapaxiChannelEndpointKind.device:
      return '设备';
    default:
      return normalized;
  }
}
