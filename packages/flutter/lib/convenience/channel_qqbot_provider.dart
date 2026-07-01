import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import '../engine.dart';
import '../generated/bridge/channel_qqbot.dart' as qq;
import '../models/channel.dart';
import '../models/channel_provider.dart';
import '../api/channel_provider_host.dart';

class QqBotChannelCredentials {
  static const configVersionKey = 'config_version';
  static const appIdKey = 'app_id';
  static const appSecretKey = 'app_secret';
  static const sandboxKey = 'sandbox';
  static const intentsKey = 'intents';
  static const agentIdKey = 'agent_id';

  static const configVersion = 2;
  static const defaultIntents = 1 << 25;
  static const legacyDefaultIntents = (1 << 25) | (1 << 12);

  const QqBotChannelCredentials({
    required this.appId,
    required this.appSecret,
    this.sandbox = false,
    this.intents = defaultIntents,
    this.agentId = NapaxiEngine.defaultAgentId,
  });

  factory QqBotChannelCredentials.fromMaps({
    required Map<String, String> secrets,
    Map<String, dynamic> config = const {},
  }) {
    final configVersion = _asInt(config[configVersionKey], fallback: 1);
    final rawIntents = _asInt(config[intentsKey], fallback: defaultIntents);
    return QqBotChannelCredentials(
      appId: secrets[appIdKey]?.trim() ?? '',
      appSecret: secrets[appSecretKey]?.trim() ?? '',
      sandbox: configVersion >= QqBotChannelCredentials.configVersion
          ? _asBool(config[sandboxKey], fallback: false)
          : false,
      intents: rawIntents == legacyDefaultIntents ? defaultIntents : rawIntents,
      agentId: _firstString([
        config[agentIdKey],
        NapaxiEngine.defaultAgentId,
      ]),
    );
  }

  final String appId;
  final String appSecret;
  final bool sandbox;
  final int intents;
  final String agentId;

  bool get isConfigured => appId.trim().isNotEmpty && appSecret.isNotEmpty;

  Map<String, String> toSecretMap() => {
        appIdKey: appId,
        appSecretKey: appSecret,
      };

  Map<String, dynamic> toConfigMap() => {
        configVersionKey: configVersion,
        sandboxKey: sandbox,
        intentsKey: intents,
        agentIdKey: agentId.trim().isEmpty
            ? NapaxiEngine.defaultAgentId
            : agentId.trim(),
      };
}

class QqBotChannelStatus {
  const QqBotChannelStatus({
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
    this.heartbeatAckCount = 0,
    this.inboundCount = 0,
    this.deliveredCount = 0,
  });

  final bool connected;
  final bool configured;
  final NapaxiChannelProviderManifest manifest;
  final List<NapaxiChannelRecord> channels;
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
  final int heartbeatAckCount;
  final int inboundCount;
  final int deliveredCount;
}

class QqBotChannelProvider implements NapaxiChannelProvider {
  static const providerId = 'napaxi.qqbot.provider';
  static const channelName = 'qqbot';
  static const _httpRequestTimeout = Duration(seconds: 15);
  static const _webSocketConnectTimeout = Duration(seconds: 15);
  static const _gatewayReadyTimeout = Duration(seconds: 12);

  static NapaxiChannelProviderManifest manifestFor(
    QqBotChannelCredentials? credentials,
  ) {
    return NapaxiChannelProviderManifest.im(
      providerId: providerId,
      channelName: channelName,
      displayName: 'QQBot Channel',
      description:
          'QQ official Bot Gateway/OpenAPI adapter for the Napaxi channel contract.',
      accountId: credentials?.appId.trim().isNotEmpty == true
          ? credentials!.appId.trim()
          : 'unconfigured',
      endpointKinds: const [
        NapaxiChannelEndpointKind.direct,
        NapaxiChannelEndpointKind.group,
        NapaxiChannelEndpointKind.room,
      ],
      modalities: const [
        NapaxiChannelModality.text,
        NapaxiChannelModality.image,
        NapaxiChannelModality.audio,
        NapaxiChannelModality.file,
      ],
      contentFormats: const [
        NapaxiChannelContentFormat.plainText,
        NapaxiChannelContentFormat.markdown,
      ],
      transport: 'qqbot_gateway_openapi',
      authRequirements: const ['qq_open_platform_app_credentials'],
      backgroundRequirements: const ['websocket_gateway'],
      config: {
        'sandbox': credentials?.sandbox ?? false,
        'intents':
            credentials?.intents ?? QqBotChannelCredentials.defaultIntents,
        'agent_id': credentials?.agentId.trim().isNotEmpty == true
            ? credentials!.agentId.trim()
            : NapaxiEngine.defaultAgentId,
        'markdown_endpoint_kinds': [
          NapaxiChannelEndpointKind.direct,
          NapaxiChannelEndpointKind.group,
        ],
        if (credentials?.appId.trim().isNotEmpty == true)
          'qq_app_id': credentials!.appId.trim(),
      },
    );
  }

  // NOTE: the former buildOutboundPayloadForTesting / shouldFallbackMarkdownForTesting
  // hooks were removed. The QQ outbound payload shaping and the markdown 4xx
  // fallback rule are now owned by core (napaxi_core::api::channel_qqbot) and
  // verified there against the shared fixture
  // (packages/api_contract/fixtures/channel/qqbot/protocol.json). The adapter
  // is a thin transport shell and no longer re-implements that protocol.

  QqBotChannelProvider(this.credentials);

  final QqBotChannelCredentials credentials;

  @override
  NapaxiChannelProviderManifest get manifest => manifestFor(credentials);

  NapaxiChannelProviderContext? _context;
  WebSocket? _gatewaySocket;
  StreamSubscription<dynamic>? _gatewaySubscription;
  Timer? _heartbeatTimer;
  String? _accessToken;
  DateTime? _accessTokenExpiresAt;
  Completer<void>? _gatewayReadyWaiter;
  // Opaque protocol-state blob owned by the core gateway reducer. The adapter
  // holds it between frames and never interprets its protocol fields directly
  // (only mirrors them into diagnostics via _syncDiagnosticsFromState).
  Map<String, dynamic> _gatewayState = const {};
  String _gatewayPhase = 'idle';
  String? _gatewayUrl;
  int? _gatewayShardCount;
  int? _gatewaySessionRemaining;
  int? _gatewaySessionMaxConcurrency;
  String? _sessionId;
  int? _lastSequence;
  int? _lastOpcode;
  String? _lastEventType;
  int? _gatewayCloseCode;
  String? _gatewayCloseReason;
  String? _lastError;
  bool _connected = false;
  bool _stopping = false;
  bool _reconnectingGateway = false;
  int _heartbeatAckCount = 0;
  int _inboundCount = 0;
  int _deliveredCount = 0;
  int? _lastHeartbeatIntervalMs;

  String get _apiBase => credentials.sandbox
      ? 'https://sandbox.api.sgroup.qq.com'
      : 'https://api.sgroup.qq.com';

  QqBotChannelStatus status({List<NapaxiChannelRecord> channels = const []}) {
    return QqBotChannelStatus(
      connected: _connected,
      configured: credentials.isConfigured,
      manifest: manifest,
      channels: channels,
      mode: manifest.transport,
      gatewayPhase: _gatewayPhase,
      gatewayUrl: _gatewayUrl,
      gatewayShardCount: _gatewayShardCount,
      gatewaySessionRemaining: _gatewaySessionRemaining,
      gatewaySessionMaxConcurrency: _gatewaySessionMaxConcurrency,
      sessionId: _sessionId,
      lastOpcode: _lastOpcode,
      lastEventType: _lastEventType,
      gatewayCloseCode: _gatewayCloseCode,
      gatewayCloseReason: _gatewayCloseReason,
      lastError: _lastError,
      credentialFingerprint: _credentialFingerprint(credentials),
      heartbeatAckCount: _heartbeatAckCount,
      inboundCount: _inboundCount,
      deliveredCount: _deliveredCount,
    );
  }

  @override
  Future<void> start(NapaxiChannelProviderContext context) async {
    _context = context;
    _lastError = null;
    if (!credentials.isConfigured) {
      _lastError = 'QQBot credentials are not configured.';
      return;
    }
    try {
      await _connectGateway();
    } catch (error) {
      _connected = false;
      _lastError = 'QQBot Gateway connect failed: $error';
    }
  }

  @override
  Future<void> stop() async {
    _stopping = true;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _completeGatewayReadyWait();
    await _gatewaySubscription?.cancel();
    _gatewaySubscription = null;
    final socket = _gatewaySocket;
    _gatewaySocket = null;
    if (socket != null) {
      await socket.close(WebSocketStatus.goingAway, 'napaxi channel stopped');
    }
    _context = null;
    _connected = false;
    _stopping = false;
  }

  @override
  Future<NapaxiChannelOutboundDeliveryResult> deliverOutbound(
    NapaxiChannelOutboundMessage message,
  ) async {
    if (!credentials.isConfigured) {
      return const NapaxiChannelOutboundDeliveryResult.failed(
        'QQBot credentials are not configured.',
      );
    }
    final text = message.text?.trim() ?? '';
    if (text.isEmpty) {
      return const NapaxiChannelOutboundDeliveryResult.failed(
        'QQBot text outbound requires non-empty text.',
      );
    }
    try {
      final endpoint = _outboundEndpoint(message);
      final token = await _ensureAccessToken();
      final requestedFormat = _requestedContentFormatLabel(message.format);
      final markdownKinds = _markdownEndpointKindsFromConfig(manifest.config);
      var payload = _coreBuildOutboundPayload(
        message,
        markdownEndpointKinds: markdownKinds,
      );
      var markdownFallback = false;
      var markdownErrorStatusCode = 0;
      var markdownErrorBody = '';
      var response = await _postJson(
        endpoint,
        headers: {'Authorization': 'QQBot $token'},
        body: payload.body,
      );
      if (payload.usedMarkdown &&
          qq.qqbotShouldFallbackFromMarkdown(status: response.statusCode)) {
        markdownFallback = true;
        markdownErrorStatusCode = response.statusCode;
        markdownErrorBody = response.body;
        payload = _coreBuildOutboundPayload(
          message,
          forcePlainText: true,
          markdownEndpointKinds: markdownKinds,
        );
        response = await _postJson(
          endpoint,
          headers: {'Authorization': 'QQBot $token'},
          body: payload.body,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return NapaxiChannelOutboundDeliveryResult.failed(
          'QQBot send failed: HTTP ${response.statusCode}',
        );
      }
      _deliveredCount += 1;
      final receipt = _decodeJsonMap(response.body) ?? const {};
      return NapaxiChannelOutboundDeliveryResult.delivered(
        receipt: {
          'provider_id': providerId,
          'endpoint': endpoint.path,
          'peer_id': message.peer.id,
          'peer_kind': message.peer.kind,
          'content_format': payload.contentFormat,
          'requested_content_format': requestedFormat,
          if (markdownFallback) 'markdown_fallback': true,
          if (markdownFallback)
            'markdown_error_status': markdownErrorStatusCode,
          if (markdownFallback && markdownErrorBody.trim().isNotEmpty)
            'markdown_error_body': _truncateForStatus(markdownErrorBody.trim()),
          if (receipt.isNotEmpty) 'qq_receipt': receipt,
        },
      );
    } catch (error) {
      return NapaxiChannelOutboundDeliveryResult.failed(
        'QQBot send failed: $error',
      );
    }
  }

  Future<void> _connectGateway() => _connectGatewayWithMode(resume: false);

  Future<void> _connectGatewayWithMode({required bool resume}) async {
    _connected = false;
    _lastError = null;
    _gatewayCloseCode = null;
    _gatewayCloseReason = null;
    if (!resume) {
      _lastOpcode = null;
      _lastEventType = null;
      _lastSequence = null;
      _sessionId = null;
      _heartbeatAckCount = 0;
      _gatewayState = const {};
    }
    _gatewayReadyWaiter = Completer<void>();
    _gatewayPhase = resume ? 'resume_access_token' : 'access_token';
    final token = await _ensureAccessToken();
    _gatewayPhase = resume
        ? (credentials.sandbox
            ? 'resume_fetch_sandbox_gateway'
            : 'resume_fetch_gateway')
        : (credentials.sandbox ? 'fetch_sandbox_gateway' : 'fetch_gateway');
    final gateway = await _fetchGateway(token);
    _gatewayUrl = gateway.url;
    _gatewayShardCount = gateway.shards;
    _gatewaySessionRemaining = gateway.sessionRemaining;
    _gatewaySessionMaxConcurrency = gateway.sessionMaxConcurrency;
    // Seed the core reducer with a fresh state + the identify config it needs
    // to build the op-2 frame. Transport-fetched values (token, shard count)
    // and platform-specific properties ($os/$device) are supplied here; the
    // protocol decisions stay in core.
    _seedGatewayState(token: token, gateway: gateway, resume: resume);
    _gatewayPhase = resume ? 'resume_socket_connecting' : 'socket_connecting';
    final socket = await WebSocket.connect(
      _gatewayUrl!,
    ).timeout(_webSocketConnectTimeout);
    _gatewaySocket = socket;
    _stopping = false;
    _gatewayPhase = 'socket_open';
    _gatewaySubscription = socket.listen(
      _handleGatewayFrame,
      onDone: () {
        _connected = false;
        _gatewayPhase = 'closed';
        _gatewayCloseCode = socket.closeCode;
        _gatewayCloseReason = socket.closeReason;
        if (!_stopping && !_reconnectingGateway) {
          _lastError ??= _gatewayClosedSummary(socket);
        }
        _completeGatewayReadyWait();
      },
      onError: (Object error) {
        _connected = false;
        _gatewayPhase = 'error';
        if (!_reconnectingGateway) {
          _lastError = 'QQBot Gateway error: $error';
        }
        _completeGatewayReadyWait();
      },
      cancelOnError: false,
    );
    try {
      await _gatewayReadyWaiter!.future.timeout(_gatewayReadyTimeout);
    } on TimeoutException {
      if (!_connected) {
        _gatewayPhase = 'ready_timeout';
        _lastError = 'QQBot Gateway READY timeout after '
            '${_gatewayReadyTimeout.inSeconds}s '
            '(phase=$_gatewayPhase, last_op=${_lastOpcode ?? 'none'}, '
            'last_event=${_lastEventType ?? 'none'}).';
      }
    }
  }

  void _seedGatewayState({
    required String token,
    required _QqGatewayInfo gateway,
    required bool resume,
  }) {
    final identify = {
      'token': token,
      'intents': credentials.intents,
      'shard_count': gateway.shards,
      'os': Platform.operatingSystem,
      'browser': 'napaxi',
      'device': 'napaxi_flutter_sdk',
    };
    if (!resume) {
      _gatewayState = {'identify': identify};
      return;
    }
    final state = Map<String, dynamic>.from(_gatewayState);
    state['identify'] = identify;
    state['resume_requested'] = true;
    final sessionId = _firstOptionalString([state['session_id'], _sessionId]);
    if (sessionId != null) state['session_id'] = sessionId;
    final sequence = _asNullableInt(state['seq']) ?? _lastSequence;
    if (sequence != null) state['seq'] = sequence;
    _gatewayState = state;
  }

  Future<void> _reconnectGateway({required bool resume}) async {
    if (_reconnectingGateway || _stopping) return;
    _reconnectingGateway = true;
    final canResume = resume &&
        _firstOptionalString([_gatewayState['session_id'], _sessionId]) != null;
    try {
      _connected = false;
      _gatewayPhase =
          canResume ? 'reconnecting_resume' : 'reconnecting_identify';
      _completeGatewayReadyWait();
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      final subscription = _gatewaySubscription;
      _gatewaySubscription = null;
      await subscription?.cancel();
      final socket = _gatewaySocket;
      _gatewaySocket = null;
      if (socket != null) {
        try {
          await socket.close(
            WebSocketStatus.goingAway,
            canResume
                ? 'napaxi channel resume reconnect'
                : 'napaxi channel reconnect',
          );
        } catch (_) {
          // Closing an already-closed socket is harmless during reconnect.
        }
      }
      if (_stopping) return;
      await _connectGatewayWithMode(resume: canResume);
    } catch (error) {
      _connected = false;
      _gatewayPhase = 'reconnect_failed';
      _lastError = 'QQBot Gateway reconnect failed: $error';
    } finally {
      _reconnectingGateway = false;
    }
  }

  Future<String> _ensureAccessToken() async {
    final token = _accessToken;
    final expiresAt = _accessTokenExpiresAt;
    if (token != null &&
        expiresAt != null &&
        DateTime.now().isBefore(
          expiresAt.subtract(const Duration(minutes: 5)),
        )) {
      return token;
    }

    final response = await _postJson(
      Uri.parse('https://bots.qq.com/app/getAppAccessToken'),
      body: {
        'appId': credentials.appId.trim(),
        'clientSecret': credentials.appSecret,
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_accessTokenErrorSummary(response));
    }
    final body = _decodeJsonMap(response.body);
    final accessToken = _firstString([
      body?['access_token'],
      body?['accessToken'],
    ]);
    if (accessToken.isEmpty) {
      throw StateError(_accessTokenErrorSummary(response));
    }
    final expiresIn = _asInt(body?['expires_in'], fallback: 7200);
    _accessToken = accessToken;
    _accessTokenExpiresAt = DateTime.now().add(Duration(seconds: expiresIn));
    return accessToken;
  }

  Future<_QqGatewayInfo> _fetchGateway(String token) async {
    final botGateway = await _getGateway(
      Uri.parse('$_apiBase/gateway/bot'),
      token,
    );
    if (botGateway != null) return botGateway;
    final gateway = await _getGateway(Uri.parse('$_apiBase/gateway'), token);
    if (gateway != null) return gateway;
    throw StateError('Gateway response did not include url');
  }

  Future<_QqGatewayInfo?> _getGateway(Uri uri, String token) async {
    final response = await _getJson(
      uri,
      headers: {'Authorization': 'QQBot $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final body = _decodeJsonMap(response.body);
    final url = _firstString([body?['url']]);
    if (url.isEmpty) return null;
    final sessionLimit = Map<String, dynamic>.from(
      body?['session_start_limit'] as Map? ?? const {},
    );
    return _QqGatewayInfo(
      url: url,
      shards: _asInt(body?['shards'], fallback: 1),
      sessionRemaining: _asNullableInt(sessionLimit['remaining']),
      sessionMaxConcurrency: _asNullableInt(
        sessionLimit['max_concurrency'],
      ),
    );
  }

  /// Feeds an incoming gateway frame to the core sans-IO reducer and executes
  /// the actions it returns. All protocol decisions (opcode dispatch, identify,
  /// heartbeat seq, READY/RESUMED, reconnect classification, inbound
  /// normalization) live in core; the adapter only owns the socket, the
  /// heartbeat timer, and the opaque protocol-state blob.
  void _handleGatewayFrame(dynamic frame) {
    final text = frame is String ? frame : utf8.decode(frame as List<int>);
    _driveGateway({'type': 'frame', 'text': text});
  }

  // Where built frames are written. Defaults to the live socket; tests record.
  void Function(Map<String, dynamic> frame)? _frameSink;
  FutureOr<void> Function(bool resume)? _reconnectSink;

  // The single FFI seam is the qqbotGatewayStep call below. The gateway glue
  // test does not exercise it — it replays the reducer's recorded actions
  // straight into [applyGatewayActions], so the pure-Dart action
  // interpretation is covered without the native lib.
  void _driveGateway(Map<String, dynamic> event) {
    final raw = qq.qqbotGatewayStep(
      stateJson: jsonEncode(_gatewayState),
      eventJson: jsonEncode(event),
    );
    final out = _decodeJsonMap(raw);
    if (out == null) return;
    final newState = out['state'];
    if (newState is Map) {
      _gatewayState = Map<String, dynamic>.from(newState);
    }
    _syncDiagnosticsFromState();
    final actions = out['actions'];
    if (actions is List) _applyGatewayActions(actions);
  }

  /// Pure-Dart (no FFI): apply the actions the reducer returned. Exposed for
  /// testing so the gateway action-interpretation is covered without loading
  /// the native library (the reducer itself is verified in Rust).
  @visibleForTesting
  void applyGatewayActions(List<dynamic> actions) =>
      _applyGatewayActions(actions);

  /// Wires test seams: a recording [frameSink] for emitted gateway frames and
  /// a fake [context] to capture submitted inbound messages. For the gateway
  /// glue test only.
  @visibleForTesting
  void configureForGatewayGlueTest({
    required void Function(Map<String, dynamic> frame) frameSink,
    required NapaxiChannelProviderContext context,
    FutureOr<void> Function(bool resume)? reconnectSink,
  }) {
    _frameSink = frameSink;
    _reconnectSink = reconnectSink;
    _context = context;
  }

  /// Last heartbeat interval the reducer asked to start (test observation).
  @visibleForTesting
  int? get lastHeartbeatIntervalMs => _lastHeartbeatIntervalMs;

  /// Whether the gateway ready-waiter has completed (test observation).
  @visibleForTesting
  bool get isGatewayReadyCompleted =>
      _gatewayReadyWaiter == null || _gatewayReadyWaiter!.isCompleted;

  /// Arms the ready-waiter so [isGatewayReadyCompleted] starts false (test).
  @visibleForTesting
  void armGatewayReadyWaiterForTest() {
    _gatewayReadyWaiter = Completer<void>();
  }

  void _applyGatewayActions(List<dynamic> actions) {
    for (final action in actions) {
      if (action is Map) {
        _executeGatewayAction(Map<String, dynamic>.from(action));
      }
    }
  }

  void _executeGatewayAction(Map<String, dynamic> action) {
    switch (action['type']) {
      case 'send_frame':
        final frame = action['frame'];
        if (frame is Map) {
          final framePayload = Map<String, dynamic>.from(frame);
          final sink = _frameSink;
          if (sink != null) {
            sink(framePayload);
          } else {
            _sendGatewayPayload(framePayload);
          }
        }
        return;
      case 'start_heartbeat':
        final intervalMs = _asInt(action['interval_ms'], fallback: 45000);
        _lastHeartbeatIntervalMs = intervalMs;
        _heartbeatTimer?.cancel();
        // Only arm the live timer when a socket is present (production). In
        // tests there is no socket, so the interval is captured above without
        // scheduling a tick that would re-enter the reducer.
        if (_gatewaySocket != null) {
          _heartbeatTimer = Timer.periodic(
            Duration(milliseconds: intervalMs),
            (_) => _driveGateway({'type': 'heartbeat_due'}),
          );
        }
        return;
      case 'mark_ready':
        _completeGatewayReadyWait();
        return;
      case 'submit_inbound':
        _submitInboundAction(action);
        return;
      case 'reconnect':
        final resume = _asBool(action['resume'], fallback: false);
        _completeGatewayReadyWait();
        final reconnectSink = _reconnectSink;
        if (reconnectSink != null) {
          unawaited(Future<void>.sync(() => reconnectSink(resume)));
        } else {
          unawaited(_reconnectGateway(resume: resume));
        }
        return;
    }
  }

  void _submitInboundAction(Map<String, dynamic> action) {
    final context = _context;
    if (context == null) return;
    final inbound = action['inbound'];
    if (inbound is! Map) return;
    final peerMap = inbound['peer'];
    if (peerMap is! Map) {
      final error = inbound['error'];
      if (error is String) _lastError = error;
      return;
    }
    final senderMap =
        Map<String, dynamic>.from(inbound['sender'] as Map? ?? const {});
    final eventType = _firstString([action['event_type']]);
    final rawData = action['raw'];
    context.submitTextInbound(
      peer: NapaxiChannelPeer(
        kind: _firstString([peerMap['kind']]),
        id: _firstString([peerMap['id']]),
        displayName: _firstOptionalString([peerMap['display_name']]),
      ),
      sender: NapaxiChannelActor(
        id: _firstString([senderMap['id']]),
        displayName: _firstOptionalString([senderMap['display_name']]),
        isBot: senderMap['is_bot'] == true,
      ),
      text: _firstString([inbound['text']]),
      platformMessageId: _firstOptionalString([inbound['platform_message_id']]),
      threadId: _firstOptionalString([inbound['thread_id']]),
      raw: {
        'provider_id': providerId,
        'qq_event_type': eventType,
        'qq_payload': rawData,
      },
    );
    _inboundCount += 1;
  }

  /// Mirrors the core gateway state's protocol fields into the adapter's
  /// status diagnostics (these are read-only views for `status()`).
  void _syncDiagnosticsFromState() {
    _gatewayPhase = _firstString([_gatewayState['phase']]).isEmpty
        ? _gatewayPhase
        : _gatewayState['phase'] as String;
    _lastSequence = _asNullableInt(_gatewayState['seq']) ?? _lastSequence;
    _lastOpcode = _asNullableInt(_gatewayState['last_opcode']) ?? _lastOpcode;
    final eventType = _firstOptionalString([_gatewayState['last_event_type']]);
    if (eventType != null) _lastEventType = eventType;
    final sessionId = _firstOptionalString([_gatewayState['session_id']]);
    if (sessionId != null) _sessionId = sessionId;
    _heartbeatAckCount = _asInt(_gatewayState['heartbeat_ack_count'],
        fallback: _heartbeatAckCount);
    _connected = _gatewayState['connected'] == true;
    final error = _gatewayState['last_error'];
    _lastError = error is String ? error : null;
  }

  Uri _outboundEndpoint(NapaxiChannelOutboundMessage message) {
    // Endpoint routing (peer kind -> path, with peer-id encoding) is core-owned
    // protocol; the adapter only supplies the platform/sandbox base host.
    final path = qq.qqbotOutboundEndpointPath(
      peerKind: message.peer.kind,
      peerId: message.peer.id,
    );
    return Uri.parse('$_apiBase$path');
  }

  /// Transport: write a protocol frame (built by core) to the live socket.
  void _sendGatewayPayload(Map<String, dynamic> payload) {
    try {
      _gatewaySocket?.add(jsonEncode(payload));
    } catch (error) {
      _lastError = 'QQBot Gateway send failed: $error';
    }
  }

  void _completeGatewayReadyWait() {
    final waiter = _gatewayReadyWaiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
  }
}

class _QqGatewayInfo {
  const _QqGatewayInfo({
    required this.url,
    required this.shards,
    this.sessionRemaining,
    this.sessionMaxConcurrency,
  });

  final String url;
  final int shards;
  final int? sessionRemaining;
  final int? sessionMaxConcurrency;
}

class _JsonHttpResponse {
  const _JsonHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

class _QqOutboundPayload {
  const _QqOutboundPayload({
    required this.body,
    required this.contentFormat,
    required this.usedMarkdown,
  });

  final Map<String, dynamic> body;
  final String contentFormat;
  final bool usedMarkdown;
}

/// Builds the QQ outbound payload by delegating to the core protocol (single
/// source of truth). `markdownEndpointKinds` overrides the core default
/// (direct+group); pass null to use that default.
_QqOutboundPayload _coreBuildOutboundPayload(
  NapaxiChannelOutboundMessage message, {
  bool forcePlainText = false,
  List<String>? markdownEndpointKinds,
}) {
  final messageJson = jsonEncode({
    'peer': {'kind': message.peer.kind, 'id': message.peer.id},
    if (message.text != null) 'text': message.text,
    if (message.replyToMessageId != null)
      'reply_to_message_id': message.replyToMessageId,
    if (message.format != null) 'format': message.format,
  });
  final raw = forcePlainText
      ? qq.qqbotBuildOutboundPayloadPlain(messageJson: messageJson)
      : qq.qqbotBuildOutboundPayload(
          messageJson: messageJson,
          markdownEndpointKindsJson: markdownEndpointKinds == null
              ? ''
              : jsonEncode(markdownEndpointKinds),
        );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return _QqOutboundPayload(
    body: Map<String, dynamic>.from(decoded['body'] as Map),
    contentFormat: decoded['content_format'] as String,
    usedMarkdown: decoded['used_markdown'] as bool,
  );
}

List<String>? _markdownEndpointKindsFromConfig(Map<String, dynamic> config) {
  final raw = config['markdown_endpoint_kinds'];
  if (raw is! List) return null;
  final values = raw
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  return values.isEmpty ? null : values;
}

String _requestedContentFormatLabel(String? format) {
  // Display label for the delivery receipt only (not wire-affecting). The
  // canonical markdown/plain decision lives in core (qqbotBuildOutboundPayload).
  final normalized =
      (format ?? NapaxiChannelContentFormat.plainText).trim().toLowerCase();
  if (normalized == 'md' || normalized == NapaxiChannelContentFormat.markdown) {
    return NapaxiChannelContentFormat.markdown;
  }
  return NapaxiChannelContentFormat.plainText;
}

Future<_JsonHttpResponse> _postJson(
  Uri uri, {
  Map<String, String> headers = const {},
  required Object body,
}) async {
  final client = HttpClient();
  client.connectionTimeout = QqBotChannelProvider._httpRequestTimeout;
  try {
    final request = await client
        .postUrl(uri)
        .timeout(QqBotChannelProvider._httpRequestTimeout);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    request.add(utf8.encode(jsonEncode(body)));
    final response =
        await request.close().timeout(QqBotChannelProvider._httpRequestTimeout);
    return _JsonHttpResponse(
      statusCode: response.statusCode,
      body: await utf8
          .decodeStream(response)
          .timeout(QqBotChannelProvider._httpRequestTimeout),
    );
  } finally {
    client.close(force: true);
  }
}

Future<_JsonHttpResponse> _getJson(
  Uri uri, {
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();
  client.connectionTimeout = QqBotChannelProvider._httpRequestTimeout;
  try {
    final request = await client
        .getUrl(uri)
        .timeout(QqBotChannelProvider._httpRequestTimeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    final response =
        await request.close().timeout(QqBotChannelProvider._httpRequestTimeout);
    return _JsonHttpResponse(
      statusCode: response.statusCode,
      body: await utf8
          .decodeStream(response)
          .timeout(QqBotChannelProvider._httpRequestTimeout),
    );
  } finally {
    client.close(force: true);
  }
}

Map<String, dynamic>? _decodeJsonMap(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {
    return null;
  }
  return null;
}

bool _asBool(Object? value, {required bool fallback}) {
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

int _asInt(Object? value, {required int fallback}) {
  return _asNullableInt(value) ?? fallback;
}

int? _asNullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

String _firstString(Iterable<Object?> values) {
  for (final value in values) {
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isEmpty) continue;
    return text;
  }
  return '';
}

String? _firstOptionalString(Iterable<Object?> values) {
  final text = _firstString(values);
  return text.isEmpty ? null : text;
}

String _accessTokenErrorSummary(_JsonHttpResponse response) {
  final body = _decodeJsonMap(response.body);
  final parts = <String>['AccessToken failed'];
  parts.add('HTTP ${response.statusCode}');
  if (body == null) {
    final raw = _redactQqTokenFields(response.body.trim());
    if (raw.isNotEmpty) parts.add('body=${_truncateForStatus(raw)}');
    return parts.join(': ');
  }

  for (final key in const [
    'code',
    'errcode',
    'error',
    'message',
    'errmsg',
    'error_description',
    'trace_id',
    'request_id',
  ]) {
    final value = body[key];
    if (value == null) continue;
    final text = _redactQqTokenFields(value.toString().trim());
    if (text.isNotEmpty) parts.add('$key=$text');
  }
  if (parts.length <= 2) {
    parts.add(
      'body=${_truncateForStatus(_redactQqTokenFields(jsonEncode(body)))}',
    );
  }
  return parts.join(': ');
}

String _gatewayClosedSummary(WebSocket socket) {
  return [
    'QQBot Gateway closed',
    'code=${socket.closeCode ?? 'unknown'}',
    'reason=${socket.closeReason?.trim().isNotEmpty == true ? socket.closeReason : 'none'}',
  ].join(': ');
}

String _redactQqTokenFields(String value) {
  return value
      .replaceAll(
        RegExp(r'access[_-]?token["\s:=]+[^,"\s}]+', caseSensitive: false),
        'access_token=<redacted>',
      )
      .replaceAll(
        RegExp(r'client[_-]?secret["\s:=]+[^,"\s}]+', caseSensitive: false),
        'clientSecret=<redacted>',
      );
}

String _truncateForStatus(String value, {int max = 240}) {
  if (value.length <= max) return value;
  return '${value.substring(0, max)}...';
}

String _credentialFingerprint(QqBotChannelCredentials credentials) {
  final secret = credentials.appSecret;
  return 'secret_len=${secret.length}, secret_fnv64=${_fnv64Hex(secret)}';
}

String _fnv64Hex(String value) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}
