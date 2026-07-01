part of '../main.dart';

const String _a2aConversationSessionsKey =
    'napaxi_demo.a2a_conversation_sessions.v1';
const String _a2aDeletedConversationSessionsKey =
    'napaxi_demo.a2a_conversation_sessions.deleted.v1';
const String _a2aConversationSessionPrefix = 'nearby-agent';

String _a2aVisibleConversationSessionIdForCollaboration(
  String collaborationId,
) {
  final normalized = collaborationId.trim();
  if (normalized.isEmpty) return '';
  return '$_a2aConversationSessionPrefix:$normalized';
}

/// A2A local-pairing orchestration extracted from _ChatScreenState.
///
/// This mixin owns all A2A state (peer cache, inbound tasks, event
/// subscription, pairing session) and the ~70 methods that drive the
/// local-pairing and task flow. Cross-concern calls (message append,
/// SDK client access) reach the core _ChatScreenState methods through
/// the shared library scope.
mixin _ChatScreenA2AMixin on State<ChatScreen> {
  // A2A storage key (demo paired-peer set gate).
  static const String _a2aPairedPeersKey =
      'napaxi_demo.a2a_local.paired_peers.v1';
  static const String _a2aConnectionAllowedKey =
      'napaxi_demo.a2a_local.connection_allowed.v1';

  final sdk.A2AApi _localA2AHelper = sdk.A2AApi(() => 0);

  // Reusable local A2A pairing orchestration now lives in the SDK
  // (identity/secret/shared-secret/paired-state/invite codec). The demo keeps
  // only UI: slash parsing, dialogs, QR rendering, chat notices. The leaf
  // `_a2a*` helpers below delegate here. Uses the demo-grade plaintext store so
  // behavior matches the previous SharedPreferences keys; a real host would use
  // `A2ALocalPairingStore.secure()`.
  late final sdk.A2ALocalPairingSession _a2aPairingSession =
      sdk.A2ALocalPairingSession(
        store: sdk.A2ALocalPairingStore.insecureSharedPreferences(),
        loadSavedPeers: () async =>
            (await _getChatClient()).listLocalA2APeers(),
      );
  String? _editingMessageId;
  late final AnimationController _sessionMenuController;
  Offset? _chatDragStart;
  Offset? _chatDragLastPosition;
  bool _isOpeningSessionMenuDrag = false;
  bool _isHorizontalScrollableDrag = false;
  late final AnimationController _workbenchDrawerController;

  final Map<String, sdk.A2ALocalPeerAdvertisement> _a2aSlashPeers = {};
  final Map<String, _A2AInboundTask> _a2aInboundTasks = {};
  final Map<String, _A2APendingPairingCompletion>
  _a2aPendingPairingCompletions = {};
  final Map<String, _A2APendingPairingCompletion> _a2aPendingPairingAcks = {};
  String? _lastA2APairingDiagnostic;
  // Inbound dedup now lives in the SDK session (classifyInboundMessage).
  StreamSubscription<sdk.A2ALocalTransportEvent>? _a2aEventSubscription;
  Future<void>? _a2aConnectionRestoreFuture;

  void _disposeA2A() {
    _a2aEventSubscription?.cancel();
    for (final pending in _a2aPendingPairingCompletions.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(StateError('A2A pairing disposed'));
      }
    }
    _a2aPendingPairingCompletions.clear();
    for (final pending in _a2aPendingPairingAcks.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(StateError('A2A pairing disposed'));
      }
    }
    _a2aPendingPairingAcks.clear();
  }

  void _setA2APairingDiagnostic(String title, Iterable<String> lines) {
    final filtered = lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    _lastA2APairingDiagnostic = [
      title,
      ...filtered.map((line) => '• $line'),
    ].join('\n');
  }

  String _a2aUserFacingError(Object error) {
    var text = error.toString().trim();
    for (final prefix in const ['Bad state: ', 'StateError: ', 'Exception: ']) {
      if (text.startsWith(prefix)) text = text.substring(prefix.length).trim();
    }
    final lower = text.toLowerCase();
    if (lower.contains('timeout') ||
        text.contains('超时') ||
        text.contains('未收到对端')) {
      return '对方没有完成确认，请确认两台手机都打开“附近”后重试。';
    }
    if (text.contains('不可达') ||
        text.contains('未送达') ||
        lower.contains('endpoint') ||
        lower.contains('tcp://')) {
      return '当前网络暂时连接不到对方，请确认两台手机在同一网络并都打开“附近”。';
    }
    return text
        .replaceAll(RegExp(r'tcp://[^\s；，。`)]+'), '对端地址')
        .replaceAll(RegExp(r'(ios|android)-[A-Za-z0-9_-]+'), '设备');
  }

  // Core _ChatScreenState members this mixin depends on. Declared abstract so
  // the mixin type-checks against State<ChatScreen>; the concrete state class
  // satisfies them (fields, getters, methods defined in chat_screen.dart).
  List<ChatSession> get _sessions;
  set _sessions(List<ChatSession> value);
  int get _nextMessageId;
  set _nextMessageId(int value);
  ChatSession get _activeSession;
  ChatSessionRunState? get _activeRun;
  DemoAgent get _activeAgent;
  String get _activeAccountId;
  String get _activeAgentId;
  String get _activeSessionId;
  String get _responseLanguageCode;
  sdk.NapaxiCapabilitySelection get _activeScenarioCapabilitySelection;
  LlmModelProfile? _runtimeProfileForAgent(String agentId);
  Future<NapaxiChatClient> _getChatClient();
  void _appendSlashCommandResult(String command, String content);
  String _compactMiddle(String value);
  String _tracePreview(String value);
  void _scrollToBottom({bool force = false});
  void _showChatSnackBar(String message);
  void _showA2AConversationUpdatedNotice(String sessionId, {String? title});

  Future<void> _handleA2ASlashCommand(String commandText, String args) async {
    final parts = args
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final action = parts.isEmpty ? 'help' : parts.first.toLowerCase();
    switch (action) {
      case 'help':
        _appendSlashCommandResult(commandText, _slashA2AHelpMessage());
        return;
      case 'preflight':
      case 'ready':
        final client = await _getChatClient();
        _appendSlashCommandResult(
          commandText,
          await _slashA2APreflightMessage(client),
        );
        return;
      case 'status':
        final client = await _getChatClient();
        final status = await client.localA2AStatus();
        _appendSlashCommandResult(
          commandText,
          await _slashA2AStatusMessage(status),
        );
        return;
      case 'doctor':
      case 'check':
        final client = await _getChatClient();
        _appendSlashCommandResult(
          commandText,
          await _slashA2ADoctorMessage(client),
        );
        return;
      case 'e2e':
      case 'guide':
      case 'checklist':
      case 'test':
        final client = await _getChatClient();
        _appendSlashCommandResult(
          commandText,
          await _slashA2AE2EGuideMessage(client),
        );
        return;
      case 'inbox':
        final client = await _getChatClient();
        _appendSlashCommandResult(
          commandText,
          await _slashA2AInboxMessage(client),
        );
        return;
      case 'peers':
      case 'peer':
      case 'devices':
        final client = await _getChatClient();
        _appendSlashCommandResult(
          commandText,
          await _slashA2APeersMessage(client),
        );
        return;
      case 'tasks':
      case 'list':
      case 'outbox':
        final client = await _getChatClient();
        _appendSlashCommandResult(
          commandText,
          await _slashA2ATasksMessage(client),
        );
        return;
      case 'trace':
      case 'ledger':
      case 'messages':
        final client = await _getChatClient();
        final target = parts.length > 1
            ? parts.sublist(1).join(' ').trim()
            : '';
        _appendSlashCommandResult(
          commandText,
          await _slashA2ATraceMessage(client, target),
        );
        return;
      case 'start':
      case 'broadcast':
        final client = await _getChatClient();
        final status = await _ensureA2ALocalTransportStarted(client);
        if (status != null && status.supported && status.running) {
          await _saveA2AConnectionAllowed(true);
        }
        _appendSlashCommandResult(
          commandText,
          status != null && status.supported
              ? [
                  '本地 A2A 已启动。',
                  await _slashA2AStatusMessage(status),
                ].join('\n\n')
              : status == null
              ? '本地 A2A 需要附近 Wi-Fi/局域网发现权限。权限未授予，已取消启动。'
              : '当前平台不支持本地 A2A：${status.reason}',
        );
        return;
      case 'scan':
        await _scanA2AInvite(commandText);
        return;
      case 'discover':
        final client = await _getChatClient();
        final status = await _ensureA2ALocalTransportStarted(client);
        if (status == null || !status.supported || !status.running) {
          _appendSlashCommandResult(
            commandText,
            status == null
                ? '本地 A2A 需要附近 Wi-Fi/局域网发现权限。权限未授予，已取消扫描。'
                : '本地 A2A 未启动：${status.reason.isEmpty ? status.lastError : status.reason}',
          );
          return;
        }
        final timeoutMs = parts.length > 1
            ? (int.tryParse(parts[1]) ?? 6) * 1000
            : 6000;
        final peers = await _discoverA2APeersForSlash(
          client,
          timeoutMs: timeoutMs,
        );
        _appendSlashCommandResult(commandText, _slashA2APeerListMessage(peers));
        return;
      case 'invite':
      case 'code':
        await _createA2AInvite(commandText);
        return;
      case 'join':
      case 'connect':
        await _joinA2AInvite(commandText, args);
        return;
      case 'pair':
      case 'trust':
        await _pairA2ASlashPeer(commandText, args);
        return;
      case 'pair-accept':
      case 'accept-pair':
      case 'pair-confirm':
        await _acceptA2APairingRequest(commandText, args);
        return;
      case 'pair-request':
      case 'request-pair':
      case 'pairback':
        await _sendA2APairingRequest(commandText, args);
        return;
      case 'ask':
      case 'send':
        await _sendA2ASlashTask(commandText, args);
        return;
      case 'resend':
      case 'retry':
        await _resendA2ASlashTask(commandText, args);
        return;
      case 'run':
        await _runA2ASlashTask(commandText, args);
        return;
      case 'answer':
        await _answerA2ASlashTask(commandText, args);
        return;
      case 'accept':
      case 'fulfill':
      case 'complete':
        await _acceptA2ASlashTask(commandText, args);
        return;
      case 'progress':
        await _replyA2ASlashTask(commandText, args, result: false);
        return;
      case 'result':
      case 'done':
        await _replyA2ASlashTask(commandText, args, result: true);
        return;
      default:
        _appendSlashCommandResult(
          commandText,
          '未知 A2A 子命令 `$action`。\n\n${_slashA2AHelpMessage()}',
        );
        return;
    }
  }

  String _slashA2AHelpMessage() {
    return [
      '**附近设备**',
      '- `/a2a invite`：生成配对二维码',
      '- `/a2a scan`：扫码配对',
      '- `/a2a peers`：查看已配对设备',
      '- `/a2a doctor`：检查连接状态',
      '',
      '配对后可以直接在聊天里说“让附近的 Agent 问个好”或“让两台设备讨论一下这个问题”。一般不需要手动输入任务编号。',
      '',
      '**高级诊断**',
      '- `/a2a preflight`：连接预检',
      '- `/a2a inbox`：查看待处理消息',
      '- `/a2a tasks`：查看最近协作',
      '- `/a2a trace <编号>`：查看详细链路证据',
      '- `/a2a start`：手动启动附近连接',
      '- `/a2a discover`：重新发现附近设备',
    ].join('\n');
  }

  Future<String> _slashA2AE2EGuideMessage(NapaxiChatClient client) async {
    final status = await client.localA2AStatus();
    final permissionGranted = await client.checkLocalA2APermission();
    final savedPeers = await client.listLocalA2APeers();
    final pairedPeers = savedPeers
        .where((peer) => peer.trustLevel == 'user_confirmed')
        .map(_a2aAdvertisementFromSavedPeer)
        .nonNulls
        .toList(growable: false);
    for (final peer in pairedPeers) {
      _a2aSlashPeers[peer.peerId] = peer;
    }
    final tasks = await client.listLocalA2ATasks();
    final inboundTasks = tasks
        .where((task) => _a2aTaskDirection(task, status.peerId) == '收到')
        .toList(growable: false);
    final outboundTasks = tasks
        .where((task) => _a2aTaskDirection(task, status.peerId) == '发出')
        .toList(growable: false);
    final localPairingSecret = status.peerId.isEmpty
        ? ''
        : _localA2AHelper.formatPairingSecret(
            await _ensureA2ALocalPairingSecret(),
          );
    final localIdentityCode = status.peerId.isEmpty
        ? ''
        : _localA2AHelper.pairingCodeFromIdentity(
            status.peerId,
            await _ensureA2ALocalPublicKey(),
          );
    final pairedTarget = pairedPeers.isEmpty ? '<编号>' : '1';
    final pendingInbound = inboundTasks
        .where((task) => _isA2APendingTaskStatus(task.status))
        .toList(growable: false);
    final latestOutbound = outboundTasks.isEmpty ? null : outboundTasks.first;
    final latestInbound = inboundTasks.isEmpty ? null : inboundTasks.first;

    return [
      '**本地 A2A 双机 E2E 清单**',
      '- 本机支持：${status.supported ? '是' : '否'}',
      '- 权限：${permissionGranted ? '可用' : '不可用'}',
      '- 广播：${status.running ? '已启动' : '未启动'}',
      '- 地址：${status.endpoint.isEmpty ? '不可用' : status.endpoint}',
      '- 可信设备：${pairedPeers.length}',
      if (localIdentityCode.isNotEmpty) '- 我的身份码：$localIdentityCode',
      if (localPairingSecret.isNotEmpty) '- 我的配对密钥：$localPairingSecret',
      '',
      '**1. 两台手机准备**',
      '- A、B 连接同一 Wi-Fi，分别执行 `/a2a start`。',
      '- A、B 分别执行 `/a2a preflight`，确认支持、权限、广播和本机收发自检都正常。',
      '- 任一端失败时先执行 `/a2a doctor`，不要继续发送任务。',
      '',
      '**2. 邀请配对**',
      '- A 执行 `/a2a invite`，展示二维码邀请。',
      '- B 执行 `/a2a scan` 扫码，确认身份码后会自动保存 A，并向 A 发回确认。',
      '- A 收到确认卡片后点确认，双方都显示为已配对设备。',
      '- A、B 都执行 `/a2a preflight`，确认可信设备数量大于 0。',
      '- 如果扫码不通，可用二维码卡片里的文字码执行 `/a2a join <邀请码>`，或用 `/a2a doctor` 查看原因。',
      '',
      '**3. 任务、进度和结果**',
      '- A 执行 `/a2a ask $pairedTarget <任务内容>`。',
      '- B 执行 `/a2a inbox`，应看到收到的消息编号。',
      '- B 可执行 `/a2a progress <编号> <进度>` 回传进度。',
      '- B 可执行 `/a2a accept <编号>` 让本机 Agent 处理并自动回传结果。',
      '- A 执行 `/a2a tasks`，应看到回执、进度或结果状态变化。',
      '',
      '**4. 证据和恢复**',
      '- 发送失败：A 执行 `/a2a trace <编号>` 查看详细链路证据。',
      '- 对端没收到：A 执行 `/a2a resend <编号>` 重发原始消息。',
      '- B 已处理但 A 没更新：B 执行 `/a2a result <编号> <结果>` 手动补发结果。',
      if (pendingInbound.isNotEmpty) '- 本机有待处理消息，可执行 `/a2a inbox` 查看编号。',
      if (latestOutbound != null) '- 最近有一条发出的协作，可执行 `/a2a tasks` 查看编号。',
      if (latestInbound != null) '- 最近有一条收到的协作，可执行 `/a2a tasks` 查看编号。',
    ].join('\n');
  }

  Future<String> _slashA2APreflightMessage(NapaxiChatClient client) async {
    final status = await client.localA2AStatus();
    final permissionGranted = await client.checkLocalA2APermission();
    final loopback = status.running && status.listenerPort > 0
        ? await _runA2ALoopbackCheck(client, status)
        : _A2ALoopbackCheckResult.skipped(
            status.running ? '监听端口不可用。' : '本机尚未启动广播监听。',
          );
    final savedPeers = await client.listLocalA2APeers();
    final pairedPeers = savedPeers
        .where((peer) => peer.trustLevel == 'user_confirmed')
        .toList(growable: false);
    final pairedAdvertisements = pairedPeers
        .map(_a2aAdvertisementFromSavedPeer)
        .nonNulls
        .toList(growable: false);
    for (final peer in pairedAdvertisements) {
      _a2aSlashPeers[peer.peerId] = peer;
    }
    final durableTasks = await client.listLocalA2ATasks();
    final localPeerId = status.peerId;
    final inboundTasks = durableTasks
        .where((task) => _a2aTaskDirection(task, localPeerId) == '收到')
        .toList(growable: false);
    final outboundTasks = durableTasks
        .where((task) => _a2aTaskDirection(task, localPeerId) == '发出')
        .toList(growable: false);
    final pendingInbound = inboundTasks
        .where((task) => _isA2APendingTaskStatus(task.status))
        .toList(growable: false);
    final activeOutbound = outboundTasks
        .where((task) => _isA2AActiveTaskStatus(task.status))
        .toList(growable: false);
    final next = <String>[];

    if (!status.supported) {
      next.add('当前平台不支持本地 A2A：${status.reason}');
    } else if (!permissionGranted) {
      next.add('执行 `/a2a start` 并按系统提示授权局域网/附近设备能力。');
    } else if (!status.running) {
      next.add('两台手机都执行 `/a2a start`。');
    } else if (loopback.failed) {
      next.add('本机收发自检失败，先执行 `/a2a doctor` 查看端口、权限和最近错误。');
    } else if (pairedPeers.isEmpty && status.discoveredPeerCount == 0) {
      next.add('两台手机保持同一 Wi-Fi，然后执行 `/a2a discover`。');
    } else if (pairedPeers.isEmpty) {
      next.add('在“附近”里扫码配对，或执行 `/a2a scan`。');
    } else if (pendingInbound.isNotEmpty) {
      next.add('执行 `/a2a inbox` 查看待处理消息。');
    } else if (activeOutbound.isNotEmpty) {
      next.add('执行 `/a2a tasks` 查看最近协作。');
    } else if (pairedAdvertisements.isNotEmpty) {
      next.add('可以直接在聊天里让附近 Agent 打招呼、讨论问题或执行低风险任务。');
    } else {
      next.add('可以直接在聊天里让附近 Agent 打招呼。');
    }

    return [
      '**本地 A2A 预检**',
      '- 支持：${status.supported ? '是' : '否'}',
      '- 权限：${permissionGranted ? '可用' : '不可用'}',
      '- 广播：${status.running ? '已启动' : '未启动'}',
      '- 本机收发自检：${loopback.label}',
      '- 已发现：${status.discoveredPeerCount}',
      '- 可信设备：${pairedPeers.length}',
      if (pairedAdvertisements.isNotEmpty)
        for (final entry in pairedAdvertisements.take(4).indexed)
          '  ${entry.$1 + 1}. ${_a2aPeerLabel(entry.$2)}',
      '',
      '**最近协作**',
      '- 总数：${durableTasks.length}',
      '- 收到：${inboundTasks.length}，待处理：${pendingInbound.length}',
      '- 发出：${outboundTasks.length}，进行中：${activeOutbound.length}',
      if (pendingInbound.isNotEmpty)
        '- 最近待处理：${_a2aTaskTitleFromRecord(pendingInbound.first) ?? pendingInbound.first.request.message}',
      if (activeOutbound.isNotEmpty)
        '- 最近进行中：${_a2aTaskStatusLabel(activeOutbound.first.status)}',
      '',
      '**下一步**',
      ...next.map((item) => '- $item'),
      '',
      '**可信连接提醒**',
      '- 本地 A2A 是双向信任：A 配 B 只代表 A 信任 B；B 还需要配回 A，才会接收 A 的任务。',
    ].join('\n');
  }

  Future<String> _slashA2AInboxMessage(NapaxiChatClient client) async {
    final durableTasks = await client.listLocalA2ATasks();
    for (final record in durableTasks) {
      final task = _a2aInboundTaskFromRecord(record);
      if (task != null) _a2aInboundTasks[task.taskId] = task;
    }
    if (_a2aInboundTasks.isEmpty) {
      return [
        '**本地 A2A 收件箱**',
        '当前没有收到对端任务。',
        '',
        '两台手机完成 `/a2a start`、`/a2a discover`、`/a2a pair` 后，可让对端执行 `/a2a ask <编号> <任务>`。',
      ].join('\n');
    }
    final tasks = _a2aInboundTasks.values.toList()
      ..sort((a, b) => a.taskId.compareTo(b.taskId));
    return [
      '**本地 A2A 收件箱**',
      '- 待处理消息：${tasks.length}',
      for (final entry in tasks.take(12).indexed)
        ['- ${entry.$1 + 1}. 来自：附近 Agent', '  内容：${entry.$2.title}'].join('\n'),
      if (tasks.length > 12) '- 还有 ${tasks.length - 12} 个任务未显示',
      '',
      '执行 `/a2a accept 1` 让本机 Agent 处理第一条消息并自动回传。',
    ].join('\n');
  }

  Future<String> _slashA2ATasksMessage(NapaxiChatClient client) async {
    final durableTasks = await client.listLocalA2ATasks();
    final localPeerId = (await client.localA2AStatus()).peerId;
    for (final record in durableTasks) {
      final task = _a2aInboundTaskFromRecord(record);
      if (task != null && _a2aTaskDirection(record, localPeerId) == '收到') {
        _a2aInboundTasks[task.taskId] = task;
      }
    }
    if (durableTasks.isEmpty) {
      return [
        '**本地 A2A 任务**',
        '当前没有持久任务记录。',
        '',
        '两台手机完成 `/a2a start`、`/a2a discover`、`/a2a pair` 后，可用 `/a2a ask <编号> <任务>` 创建任务。',
      ].join('\n');
    }
    final tasks = durableTasks.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return [
      '**本地 A2A 任务**',
      '- 总数：${tasks.length}',
      for (final entry in tasks.take(12).indexed)
        _a2aTaskStatusLine(entry.$1, entry.$2, localPeerId),
      if (tasks.length > 12) '- 还有 ${tasks.length - 12} 个任务未显示',
      '',
      '收到的消息可执行 `/a2a accept 1`；需要排查时执行 `/a2a trace 1`。',
    ].join('\n');
  }

  Future<String> _slashA2ATraceMessage(
    NapaxiChatClient client,
    String target,
  ) async {
    final trimmed = target.trim();
    if (trimmed.isEmpty) {
      return [
        '**本地 A2A 证据**',
        '请提供要查看的编号。',
        '',
        '可先执行 `/a2a tasks`，再执行 `/a2a trace 1`。',
      ].join('\n');
    }

    final task = await _a2aTaskRecordByReference(client, trimmed);
    final sessionId = (task?.sessionId ?? '').trim().isNotEmpty
        ? task!.sessionId!.trim()
        : trimmed;
    final messages = await client.listLocalA2APeerMessages(
      sessionId,
      limit: 12,
    );
    final deliveries = await client.listLocalA2ADeliveryRecords(
      sessionId,
      limit: 20,
    );
    if (task == null && messages.isEmpty && deliveries.isEmpty) {
      return [
        '**本地 A2A 证据**',
        '没有找到 `$trimmed` 对应的记录。',
        '',
        '执行 `/a2a tasks` 查看本机持久任务；如果是刚发送失败，先执行 `/a2a preflight` 检查配对和广播。',
      ].join('\n');
    }

    final lines = <String>['**本地 A2A 证据**', '- 目标：$trimmed'];
    if (task != null) {
      lines.addAll(_a2aTaskTraceLines(task));
    }
    lines.add('');
    lines.add('**Peer messages**');
    if (messages.isEmpty) {
      lines.add('- 无记录');
    } else {
      lines.addAll(messages.take(8).map(_a2aPeerMessageTraceLine));
      if (messages.length > 8) lines.add('- 还有 ${messages.length - 8} 条未显示');
    }
    lines.add('');
    lines.add('**Delivery**');
    if (deliveries.isEmpty) {
      lines.add('- 无记录');
    } else {
      lines.addAll(deliveries.take(10).map(_a2aDeliveryTraceLine));
      if (deliveries.length > 10) {
        lines.add('- 还有 ${deliveries.length - 10} 条未显示');
      }
    }
    lines.add('');
    lines.add('**下一步**');
    lines.addAll(_a2aTraceNextSteps(task, messages, deliveries));
    return lines.join('\n');
  }

  Future<sdk.A2ATaskRecord?> _a2aTaskRecordByReference(
    NapaxiChatClient client,
    String reference,
  ) async {
    final target = reference.trim();
    if (target.isEmpty) return null;
    final index = int.tryParse(target);
    final tasks = await client.listLocalA2ATasks();
    final sortedTasks = tasks.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (index != null && index >= 1 && index <= sortedTasks.length) {
      return sortedTasks[index - 1];
    }
    try {
      return await client.getLocalA2ATask(target);
    } catch (_) {
      return null;
    }
  }

  Future<void> _createA2AInvite(String commandText) async {
    final client = await _getChatClient();
    final status = await _ensureA2ALocalTransportStarted(client);
    if (status == null || !status.supported || !status.running) {
      _appendSlashCommandResult(
        commandText,
        status == null
            ? '本地 A2A 需要附近 Wi-Fi/局域网发现权限。权限未授予，已取消生成邀请。'
            : '本地 A2A 未启动：${status.reason.isEmpty ? status.lastError : status.reason}',
      );
      return;
    }
    if (status.peerId.isEmpty || status.endpoint.isEmpty) {
      _appendSlashCommandResult(
        commandText,
        '本机 A2A 地址还没准备好，请稍后再试 `/a2a invite`。',
      );
      return;
    }
    await _ensureA2APairingMigrated();
    final invite = await _a2aPairingSession.buildInvite(
      localPeerId: status.peerId,
      agentId: status.agentId,
      displayName: status.displayName,
      endpoint: status.endpoint,
      transport: status.transport,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    final code = invite.toCode();
    _appendSlashCommandResult(
      commandText,
      [
        '**本地 A2A 二维码邀请已生成**',
        '- 本机：`${status.peerId}`',
        '- 地址：`${status.endpoint}`',
        '',
        '让另一台手机执行 `/a2a scan` 扫码加入。',
      ].join('\n'),
    );
    if (mounted) {
      await _showA2AInviteQrDialog(code);
    }
  }

  Future<void> _scanA2AInvite(String commandText) async {
    final code = await _scanA2AInviteQrCode();
    if (!mounted) return;
    if (code == null || code.trim().isEmpty) {
      _appendSlashCommandResult(commandText, '已取消扫码加入。');
      return;
    }
    await _joinA2AInvite(commandText, 'join $code', showProgress: true);
  }

  Future<void> _showA2AInviteQrDialog(String code) {
    final qrData = _a2aInviteQrPayload(code);
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFAFAFA),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          '邀请附近设备',
          style: TextStyle(
            color: Color(0xFF111111),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 224,
                  height: 224,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '另一台手机打开“附近”并扫码，即可配对。',
                style: TextStyle(
                  color: Color(0xFF555555),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF111111),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  Future<String?> _scanA2AInviteQrCode() async {
    final controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      formats: const [BarcodeFormat.qrCode],
    );
    var consumed = false;
    try {
      return await showDialog<String?>(
        context: context,
        builder: (context) => Dialog.fullscreen(
          backgroundColor: const Color(0xFFFAFAFA),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '扫描邀请码',
                          style: TextStyle(
                            color: Color(0xFF111111),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF333333),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: MobileScanner(
                        controller: controller,
                        onDetect: (capture) {
                          if (consumed) return;
                          for (final barcode in capture.barcodes) {
                            final code = _normalizeA2AInviteQrPayload(
                              barcode.rawValue ?? '',
                            );
                            if (code == null) continue;
                            consumed = true;
                            Navigator.of(context).pop(code);
                            return;
                          }
                        },
                        errorBuilder: (context, error) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              '无法打开相机：$error',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Text(
                    '对准另一台手机上的二维码。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF666666), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showA2APairingProgressDialog() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFFFAFAFA),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: const Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Color(0xFF111111),
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  '正在完成配对…',
                  style: TextStyle(
                    color: Color(0xFF111111),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _joinA2AInvite(
    String commandText,
    String args, {
    bool showProgress = false,
  }) async {
    final parts = args
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final code = parts.length > 1 ? parts.sublist(1).join('').trim() : '';
    if (code.isEmpty) {
      _appendSlashCommandResult(
        commandText,
        '用法：`/a2a join <邀请码>`。\n让对方执行 `/a2a invite` 获取邀请码。',
      );
      return;
    }
    final invite = _a2aPairingSession.decodeInvite(code);
    if (invite == null) {
      _appendSlashCommandResult(
        commandText,
        '邀请码无法解析，请确认完整复制 `/a2a invite` 输出里的 code。',
      );
      return;
    }
    final remoteSecret = _localA2AHelper.normalizePairingSecret(
      invite.pairingSecret,
    );
    final peer = invite.toPeerAdvertisement();
    if (peer.peerId.isEmpty || peer.endpoint.isEmpty || remoteSecret.isEmpty) {
      _appendSlashCommandResult(commandText, '邀请码内容不完整，请让对方重新打开“附近”生成邀请。');
      return;
    }
    final confirmed = await _confirmA2ASlashPair(
      peer,
      remotePairingSecret: remoteSecret,
    );
    if (confirmed != true) {
      _appendSlashCommandResult(commandText, '已取消加入邀请。');
      return;
    }
    var progressVisible = false;
    if (showProgress && mounted) {
      progressVisible = true;
      unawaited(_showA2APairingProgressDialog());
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    void closeProgress() {
      if (!progressVisible || !mounted) return;
      progressVisible = false;
      Navigator.of(context, rootNavigator: true).pop();
    }

    final client = await _getChatClient();
    try {
      final status = await _ensureA2ALocalTransportStarted(client);
      if (status == null || !status.supported || !status.running) {
        _setA2APairingDiagnostic('配对失败', [
          status == null ? '本地 A2A 状态不可用' : '本地 A2A 未启动',
          if (status != null && status.reason.isNotEmpty) '原因：${status.reason}',
          if (status != null && status.lastError.isNotEmpty)
            '错误：${status.lastError}',
        ]);
        closeProgress();
        _appendSlashCommandResult(
          commandText,
          status == null
              ? '本地 A2A 需要附近 Wi-Fi/局域网发现权限。权限未授予，已取消加入。'
              : '本地 A2A 未启动：${status.reason.isEmpty ? status.lastError : status.reason}',
        );
        return;
      }
      await _saveA2APairedPeer(
        client,
        status,
        peer,
        remotePairingSecret: remoteSecret,
      );
      _setA2APairingDiagnostic('配对进行中', [
        '设备：${_a2aPeerLabel(peer)}',
        '正在发送配对确认',
      ]);
      final savedAfterJoin = await _hasSavedA2APeer(client, peer.peerId);
      _a2aSlashPeers[peer.peerId] = peer;
      final accept = await _createA2APairingAcceptMessage(status, peer);
      final completion = _waitForA2APairingComplete(
        peer.peerId,
        ackForMessageId: accept.messageId,
      );
      try {
        await _sendA2AHandshakeMessageToPeerOrThrow(
          client,
          accept,
          peer,
          purpose: '发送配对确认',
        );
        await completion;
      } catch (error) {
        _cancelA2APairingCompleteWait(peer.peerId, error);
        final failureStatus = await client.localA2AStatus();
        await _forgetA2APairedPeer(client, peer);
        debugPrint(
          '[napaxiToolTrace] local A2A pairing wait failed peer=${peer.peerId} endpoint=${peer.endpoint} error=$error',
        );
        _setA2APairingDiagnostic('配对失败', [
          '阶段：等待对端完成回执',
          '对端：${_a2aPeerLabel(peer)}',
          '错误：${_a2aUserFacingError(error)}',
          if (failureStatus.lastError.trim().isNotEmpty)
            '传输错误：${_a2aUserFacingError(failureStatus.lastError.trim())}',
        ]);
        rethrow;
      }
      closeProgress();
      _setA2APairingDiagnostic('配对成功', ['对端：${_a2aPeerLabel(peer)}', '对方已确认']);
      await _saveA2AConnectionAllowed(true);
      _appendSlashCommandResult(
        commandText,
        showProgress
            ? '配对成功：`${_a2aPeerLabel(peer)}` 已添加。'
            : [
                '已加入 `${_a2aPeerLabel(peer)}` 的邀请。',
                savedAfterJoin ? '- 已添加到附近设备。' : '- 正在同步附近设备列表。',
                '- 现在可以在聊天里让附近 Agent 和它对话。',
              ].join('\n'),
      );
    } catch (error) {
      closeProgress();
      _appendSlashCommandResult(
        commandText,
        [
          '配对失败：${_a2aUserFacingError(error)}',
          '已回滚本机保存的 `${_a2aPeerLabel(peer)}`，请确认两台手机都打开“附近”后重新扫码。',
        ].join('\n'),
      );
    }
  }

  List<String> _a2aTaskTraceLines(sdk.A2ATaskRecord task) {
    return [
      '- taskId：`${task.taskId}`',
      '- status：`${task.status}`',
      '- source：`${task.source}`',
      '- trust：`${task.trust}`',
      if ((task.peerMessageId ?? '').trim().isNotEmpty)
        '- peerMessageId：`${task.peerMessageId!.trim()}`',
      if ((task.sessionKey ?? '').trim().isNotEmpty)
        '- sessionKey：`${task.sessionKey!.trim()}`',
      if ((task.runId ?? '').trim().isNotEmpty)
        '- runId：`${task.runId!.trim()}`',
      if ((task.summary ?? '').trim().isNotEmpty)
        '- summary：${task.summary!.trim()}',
      if ((task.error ?? '').trim().isNotEmpty) '- error：${task.error!.trim()}',
    ];
  }

  String _a2aPeerMessageTraceLine(sdk.A2APeerMessage message) {
    final payload = _tracePreview(jsonEncode(message.payload));
    return [
      '- `${message.kind}` messageId：`${message.messageId}`',
      '  from：`${_compactMiddle(message.fromPeerId)}` -> `${_compactMiddle(message.toPeerId)}`',
      '  createdAt：${message.createdAt}',
      if (payload.isNotEmpty) '  payload：$payload',
    ].join('\n');
  }

  String _a2aDeliveryTraceLine(sdk.A2ADeliveryRecord delivery) {
    return [
      '- `${delivery.direction}` `${delivery.kind}` delivery：`${delivery.status}`',
      '  messageId：`${delivery.messageId}`',
      if ((delivery.taskId ?? '').trim().isNotEmpty)
        '  taskId：`${delivery.taskId!.trim()}`',
      if ((delivery.error ?? '').trim().isNotEmpty)
        '  deliveryError：${delivery.error!.trim()}',
      '  updatedAt：${delivery.updatedAt}',
    ].join('\n');
  }

  List<String> _a2aTraceNextSteps(
    sdk.A2ATaskRecord? task,
    List<sdk.A2APeerMessage> messages,
    List<sdk.A2ADeliveryRecord> deliveries,
  ) {
    final steps = <String>[];
    if (task != null && _isA2APendingTaskStatus(task.status)) {
      steps.add('- 收到的任务可执行 `/a2a accept ${task.taskId}`。');
    }
    if (deliveries.any((delivery) => delivery.status == 'failed')) {
      steps.add('- 有发送失败记录，执行 `/a2a preflight` 检查广播、配对和可信连接。');
      if (task != null && task.source == 'local_transport_outbound') {
        steps.add('- 修复后可执行 `/a2a resend ${task.taskId}` 重发原任务。');
      }
    }
    if (messages.isEmpty && deliveries.isEmpty) {
      steps.add('- 当前 session 没有消息证据，执行 `/a2a tasks` 确认 taskId/sessionId。');
    }
    if (steps.isEmpty) {
      steps.add('- 用 `/a2a tasks` 继续观察状态；需要处理收到的任务时执行 `/a2a accept <taskId>`。');
    }
    return steps;
  }

  _A2AInboundTask? _a2aInboundTaskFromRecord(sdk.A2ATaskRecord record) {
    final sessionId = record.sessionId ?? '';
    final peerId = record.sender.peerId;
    final title = record.request.message.trim();
    if (record.taskId.isEmpty || sessionId.isEmpty || peerId.isEmpty) {
      return null;
    }
    return _A2AInboundTask(
      taskId: record.taskId,
      sessionId: sessionId,
      fromPeerId: peerId,
      title: title.isEmpty ? record.taskId : title,
    );
  }

  Future<_A2AInboundTask?> _resolveA2AInboundTask(String taskId) async {
    final target = taskId.trim();
    final cached = _a2aInboundTasks[target];
    if (cached != null) return cached;
    final client = await _getChatClient();
    final tasks = <_A2AInboundTask>[];
    for (final record in await client.listLocalA2ATasks()) {
      final task = _a2aInboundTaskFromRecord(record);
      if (task == null) continue;
      _a2aInboundTasks[task.taskId] = task;
      tasks.add(task);
      if (task.taskId == target) return task;
    }
    final index = int.tryParse(target);
    if (index != null && index >= 1 && index <= tasks.length) {
      tasks.sort((a, b) => a.taskId.compareTo(b.taskId));
      return tasks[index - 1];
    }
    return null;
  }

  String _a2aTaskStatusLine(
    int index,
    sdk.A2ATaskRecord record,
    String localPeerId,
  ) {
    final direction = _a2aTaskDirection(record, localPeerId);
    final title =
        _a2aTaskTitleFromRecord(record) ??
        (record.request.message.trim().isEmpty
            ? '附近 Agent 消息'
            : record.request.message.trim());
    final details = <String>[
      '- ${index + 1}. [$direction] ${_a2aTaskStatusLabel(record.status)}',
      '  内容：$title',
      if ((record.summary ?? '').trim().isNotEmpty)
        '  回复：${record.summary!.trim()}',
      if ((record.error ?? '').trim().isNotEmpty)
        '  错误：${record.error!.trim()}',
      '  诊断：`/a2a trace ${index + 1}`',
    ];
    return details.join('\n');
  }

  String _a2aTaskStatusLabel(String status) {
    return switch (status.trim().toLowerCase()) {
      'pending' || 'queued' || 'accepted' || 'received' => '待处理',
      'running' || 'in_progress' => '处理中',
      'succeeded' => '已完成',
      'failed' => '失败',
      'rejected' => '已拒绝',
      'cancelled' => '已取消',
      _ => status.trim().isEmpty ? '未知状态' : status.trim(),
    };
  }

  String _a2aTaskDirection(sdk.A2ATaskRecord record, String localPeerId) {
    if (record.source == 'local_transport_outbound') return '发出';
    if (localPeerId.isNotEmpty && record.sender.peerId == localPeerId) {
      return '发出';
    }
    return '收到';
  }

  bool _isA2APendingTaskStatus(String status) {
    final normalized = status.toLowerCase();
    return normalized == 'pending' ||
        normalized == 'queued' ||
        normalized == 'accepted' ||
        normalized == 'received';
  }

  bool _isA2AActiveTaskStatus(String status) {
    final normalized = status.toLowerCase();
    return normalized == 'pending' ||
        normalized == 'queued' ||
        normalized == 'accepted' ||
        normalized == 'received' ||
        normalized == 'running' ||
        normalized == 'in_progress';
  }

  Future<String> _slashA2AStatusMessage(
    sdk.A2ALocalTransportStatus status,
  ) async {
    final lines = <String>[
      '**本地 A2A 状态**',
      '- 支持：${status.supported ? '是' : '否'}',
      '- 广播：${status.running ? '已启动' : '未启动'}',
    ];
    if (status.transport.isNotEmpty) {
      lines.add('- 传输：${status.transport}');
    }
    if (status.endpoint.isNotEmpty) {
      lines.add('- 地址：${status.endpoint}');
    }
    if (status.listenerPort > 0) {
      lines.add('- 监听端口：${status.listenerPort}');
    }
    if (status.peerId.isNotEmpty) {
      lines.add('- Peer：${_compactMiddle(status.peerId)}');
      final publicKey = await _ensureA2ALocalPublicKey();
      final pairingSecret = await _ensureA2ALocalPairingSecret();
      lines.add(
        '- 我的身份码：${_localA2AHelper.pairingCodeFromIdentity(status.peerId, publicKey)}',
      );
      lines.add(
        '- 我的配对密钥：${_localA2AHelper.formatPairingSecret(pairingSecret)}',
      );
    }
    lines.add('- 已发现：${status.discoveredPeerCount}');
    lines.add('- 已发送：${status.sentMessageCount}');
    lines.add('- 已接收：${status.receivedMessageCount}');
    if (status.multicastLockHeld) {
      lines.add('- Android 组播锁：已持有');
    }
    if (status.lastError.isNotEmpty) {
      lines.add('- 最近错误：${status.lastError}');
    }
    if (status.reason.isNotEmpty) {
      lines.add('- 原因：${status.reason}');
    }
    return lines.join('\n');
  }

  Future<String> _slashA2ADoctorMessage(NapaxiChatClient client) async {
    final status = await client.localA2AStatus();
    final permissionGranted = await client.checkLocalA2APermission();
    final loopback = status.running && status.listenerPort > 0
        ? await _runA2ALoopbackCheck(client, status)
        : _A2ALoopbackCheckResult.skipped(
            status.running ? '监听端口不可用。' : '本机尚未启动广播监听。',
          );
    final issues = <String>[];
    final next = <String>[];

    if (!status.supported) {
      issues.add('当前平台未声明支持本地 A2A。');
    }
    if (!permissionGranted) {
      issues.add('附近 Wi-Fi/局域网发现权限未授予。');
      next.add('执行 `/a2a start` 并按系统提示授权。');
    }
    if (status.supported && permissionGranted && !status.running) {
      issues.add('本机尚未启动广播监听。');
      next.add('两台手机都执行 `/a2a start`。');
    }
    if (status.running && status.listenerPort <= 0) {
      issues.add('广播已启动，但监听端口尚不可用。');
    }
    if (status.running && status.endpoint.isEmpty) {
      issues.add('广播已启动，但本机 endpoint 为空。');
    }
    if (loopback.failed) {
      issues.add('本机收发自检失败：${loopback.message}');
    }
    if (status.running && status.discoveredPeerCount == 0) {
      next.add('两台手机在同一 Wi-Fi 下分别执行 `/a2a discover`。');
    }
    if (status.discoveredPeerCount > 0) {
      next.add('在“附近”里扫码配对，或执行 `/a2a scan`。');
    }
    if (status.lastError.isNotEmpty) {
      issues.add('最近错误：${status.lastError}');
    }
    if (status.reason.isNotEmpty) {
      issues.add('原因：${status.reason}');
    }
    if (issues.isEmpty) {
      issues.add(status.running ? '本机本地 A2A 基础状态正常。' : '未发现阻断问题。');
    }
    if (next.isEmpty) {
      next.add('完成配对后可以直接在聊天里让附近 Agent 打招呼。');
    }

    return [
      '**本地 A2A 诊断**',
      '- 支持：${status.supported ? '是' : '否'}',
      '- 权限：${permissionGranted ? '可用' : '不可用'}',
      '- 广播：${status.running ? '已启动' : '未启动'}',
      '- 端口：${status.listenerPort > 0 ? status.listenerPort : '不可用'}',
      '- 地址：${status.endpoint.isEmpty ? '不可用' : status.endpoint}',
      '- 本机收发自检：${loopback.label}',
      '- 已发现：${status.discoveredPeerCount}',
      '- 收发：${status.sentMessageCount}/${status.receivedMessageCount}',
      '',
      '**诊断**',
      ...issues.map((issue) => '- $issue'),
      '',
      '**下一步**',
      ...next.map((item) => '- $item'),
    ].join('\n');
  }

  Future<_A2ALoopbackCheckResult> _runA2ALoopbackCheck(
    NapaxiChatClient client,
    sdk.A2ALocalTransportStatus status,
  ) async {
    if (status.peerId.isEmpty) {
      return _A2ALoopbackCheckResult.failed('本机 peerId 为空。');
    }
    final completer = Completer<_A2ALoopbackCheckResult>();
    StreamSubscription<sdk.A2ALocalTransportEvent>? subscription;
    try {
      final message = await client.createLocalA2ADiagnosticMessage(
        localPeerId: status.peerId,
      );
      subscription = client.localA2AEvents.listen((event) {
        final inbound = event.message;
        if (inbound == null || inbound.messageId != message.messageId) return;
        if (!completer.isCompleted) {
          completer.complete(_A2ALoopbackCheckResult.passed());
        }
      });
      final endpoint = 'tcp://127.0.0.1:${status.listenerPort}/a2a';
      final sent = await client.sendLocalA2ADiagnosticMessage(
        message,
        endpoint: endpoint,
      );
      if (!sent && !completer.isCompleted) {
        completer.complete(_A2ALoopbackCheckResult.failed('发送到 $endpoint 失败。'));
      }
      return await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () =>
            _A2ALoopbackCheckResult.failed('3 秒内没有收到 loopback 事件。'),
      );
    } catch (error) {
      return _A2ALoopbackCheckResult.failed(error.toString());
    } finally {
      final activeSubscription = subscription;
      if (activeSubscription != null) unawaited(activeSubscription.cancel());
    }
  }

  String _slashA2APeerListMessage(List<sdk.A2ALocalPeerAdvertisement> peers) {
    if (peers.isEmpty) {
      return '没有发现附近设备。请确认两台手机在同一 Wi-Fi 下，并都执行 `/a2a discover`。';
    }
    return [
      '**发现 ${peers.length} 台附近设备**',
      for (final entry in peers.take(8).indexed)
        '- `${entry.$1 + 1}` ${_a2aPeerLabel(entry.$2)}',
      if (peers.length > 8) '- 还有 ${peers.length - 8} 台未显示',
      '',
      '在“附近”里扫码配对后，就可以让两个 Agent 对话。',
    ].join('\n');
  }

  Future<String> _slashA2APeersMessage(NapaxiChatClient client) async {
    final savedPeers = await client.listLocalA2APeers();
    final savedById = <String, sdk.A2APeer>{
      for (final peer in savedPeers)
        if (peer.peerId.isNotEmpty) peer.peerId: peer,
    };
    final merged = <String, sdk.A2ALocalPeerAdvertisement>{};
    for (final peer in _a2aSlashPeers.values) {
      if (peer.peerId.isNotEmpty) merged[peer.peerId] = peer;
    }
    for (final peer in savedPeers) {
      final advertisement = _a2aAdvertisementFromSavedPeer(peer);
      if (advertisement != null) merged[advertisement.peerId] = advertisement;
    }
    final peers = _sortedA2APeers(merged.values);
    if (peers.isEmpty) {
      return [
        '**本地 A2A 设备**',
        '还没有发现或信任的设备。',
        '',
        '下一步：两台手机都执行 `/a2a start`，然后执行 `/a2a discover`。',
      ].join('\n');
    }
    final trustedCount = savedPeers
        .where((peer) => peer.trustLevel == 'user_confirmed')
        .length;
    final lines = <String>[
      '**附近设备**',
      '- 总数：${peers.length}',
      '- 已配对：$trustedCount',
      '',
    ];
    for (final entry in peers.take(12).indexed) {
      final peer = entry.$2;
      final saved = savedById[peer.peerId];
      final trusted = saved?.trustLevel == 'user_confirmed';
      final label = _a2aPeerLabel(peer);
      lines.add(
        [
          '- `${entry.$1 + 1}` $label',
          '  状态：${trusted ? '已配对，可对话' : '未配对'}',
          '  下一步：${trusted ? '直接在聊天里让附近 Agent 对话' : '在“附近”里扫码配对'}',
        ].join('\n'),
      );
    }
    if (peers.length > 12) {
      lines.add('- 还有 ${peers.length - 12} 台未显示。');
    }
    lines.addAll([
      '',
      '**提示**',
      '- 编号来自当前列表。',
      '- 连接异常时执行 `/a2a doctor` 查看诊断。',
    ]);
    return lines.join('\n');
  }

  Future<List<sdk.A2ALocalPeerAdvertisement>> _discoverA2APeersForSlash(
    NapaxiChatClient client, {
    required int timeoutMs,
  }) async {
    final found = <String, sdk.A2ALocalPeerAdvertisement>{
      for (final peer in _a2aSlashPeers.values) peer.peerId: peer,
    };
    late final StreamSubscription<sdk.A2ALocalTransportEvent> subscription;
    subscription = client.localA2AEvents.listen((event) {
      final peer = event.peer;
      if (peer == null) return;
      found[peer.peerId] = peer;
      _a2aSlashPeers[peer.peerId] = peer;
    });
    try {
      final immediate = await client.discoverLocalA2APeers(
        timeoutMs: timeoutMs,
      );
      for (final peer in immediate) {
        found[peer.peerId] = peer;
        _a2aSlashPeers[peer.peerId] = peer;
      }
      return _sortedA2APeers(found.values);
    } finally {
      unawaited(subscription.cancel());
    }
  }

  String _a2aInviteQrPayload(String code) => '${sdk.A2AInvite.qrPrefix}$code';

  // Normalize a scanned/typed value to a decodable invite code (or null). The
  // SDK codec owns the wire-shape parsing; the demo only needs the resulting
  // string to hand to `_joinA2AInvite`.
  String? _normalizeA2AInviteQrPayload(String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty) return null;
    if (value.startsWith(sdk.A2AInvite.qrPrefix)) {
      final code = value.substring(sdk.A2AInvite.qrPrefix.length).trim();
      return code.isEmpty ? null : code;
    }
    final joinMatch = RegExp(
      r'(?:^|\s)/a2a\s+join\s+([A-Za-z0-9_-]+)',
      caseSensitive: false,
    ).firstMatch(value);
    if (joinMatch != null) return joinMatch.group(1);
    return sdk.A2AInvite.tryDecodeCode(value) == null ? null : value;
  }

  Future<void> _pairA2ASlashPeer(String commandText, String args) async {
    final parts = args
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 3) {
      _appendSlashCommandResult(
        commandText,
        '建议在“附近”里扫码配对。需要手动配对时，先执行 `/a2a discover` 查看编号。',
      );
      return;
    }
    final target = parts[1];
    final remotePairingSecret = _localA2AHelper.normalizePairingSecret(
      parts.skip(2).join(' '),
    );
    if (remotePairingSecret.isEmpty) {
      _appendSlashCommandResult(
        commandText,
        '对方配对密钥为空。请让对方执行 `/a2a status`，再复制“我的配对密钥”。',
      );
      return;
    }
    final peer = _resolveA2ASlashPeer(target);
    if (peer == null) {
      _appendSlashCommandResult(
        commandText,
        '找不到设备 `$target`。请先执行 `/a2a discover`。',
      );
      return;
    }
    await _completeA2ASlashPair(
      commandText,
      peer,
      remotePairingSecret: remotePairingSecret,
      successTarget: target,
    );
  }

  Future<void> _acceptA2APairingRequest(String commandText, String args) async {
    final parts = args
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 3) {
      _appendSlashCommandResult(commandText, '建议在“附近”里扫码配对。手动确认只用于高级排障。');
      return;
    }
    final target = parts[1];
    final remotePairingSecret = _localA2AHelper.normalizePairingSecret(
      parts.skip(2).join(' '),
    );
    if (remotePairingSecret.isEmpty) {
      _appendSlashCommandResult(
        commandText,
        '对方配对密钥为空。请让对方执行 `/a2a status`，再复制“我的配对密钥”。',
      );
      return;
    }
    final peer = _resolveA2ASlashPeer(target);
    if (peer == null) {
      _appendSlashCommandResult(
        commandText,
        '找不到配对请求 `$target`。请确认聊天里已有“确认配对”卡片，或先重新发现附近设备。',
      );
      return;
    }
    await _completeA2ASlashPair(
      commandText,
      peer,
      remotePairingSecret: remotePairingSecret,
      successTarget: peer.peerId,
      acceptedRequest: true,
    );
  }

  Future<void> _completeA2ASlashPair(
    String commandText,
    sdk.A2ALocalPeerAdvertisement peer, {
    required String remotePairingSecret,
    required String successTarget,
    bool acceptedRequest = false,
  }) async {
    if (await _isA2APeerPaired(peer)) {
      _appendSlashCommandResult(commandText, '`${_a2aPeerLabel(peer)}` 已经配对。');
      return;
    }
    final confirmed = await _confirmA2ASlashPair(
      peer,
      remotePairingSecret: remotePairingSecret,
    );
    if (confirmed != true) {
      _appendSlashCommandResult(commandText, '已取消配对。');
      return;
    }
    final client = await _getChatClient();
    final status = await client.localA2AStatus();
    await _saveA2APairedPeer(
      client,
      status,
      peer,
      remotePairingSecret: remotePairingSecret,
    );
    await _saveA2AConnectionAllowed(true);
    _appendSlashCommandResult(
      commandText,
      acceptedRequest
          ? '已确认 `${_a2aPeerLabel(peer)}` 的配对。现在两台设备可以互相对话。'
          : '已配对 `${_a2aPeerLabel(peer)}`。现在可以在聊天里让附近 Agent 和它对话。',
    );
  }

  Future<void> _saveA2APairedPeer(
    NapaxiChatClient client,
    sdk.A2ALocalTransportStatus status,
    sdk.A2ALocalPeerAdvertisement peer, {
    required String remotePairingSecret,
  }) async {
    final localPublicKey = await _ensureA2ALocalPublicKey();
    final localPairingSecret = await _ensureA2ALocalPairingSecret();
    await client.openLocalA2ASession(
      peer,
      sharedSecret: _localA2AHelper.deriveLocalSharedSecret(
        localPeerId: status.peerId,
        localPublicKey: localPublicKey,
        localPairingSecret: localPairingSecret,
        remotePairingSecret: remotePairingSecret,
        peer: peer,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    final paired =
        prefs.getStringList(_a2aPairedPeersKey)?.toSet() ?? <String>{};
    paired.add(_localA2AHelper.pairingKey(peer));
    await prefs.setStringList(_a2aPairedPeersKey, paired.toList()..sort());
    await _a2aSaveRemotePairingSecret(peer, remotePairingSecret);
    if (!await _hasSavedA2APeer(client, peer.peerId)) {
      throw StateError('配对信息已生成，但没有写入已信任设备列表。');
    }
  }

  Future<bool> _hasSavedA2APeer(NapaxiChatClient client, String peerId) async {
    for (final saved in await client.listLocalA2APeers()) {
      final trust = saved.trustLevel.trim().toLowerCase();
      if (saved.peerId == peerId &&
          (trust == 'user_confirmed' ||
              trust == 'trusted' ||
              saved.sharedSecret.trim().isNotEmpty)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _forgetA2APairedPeer(
    NapaxiChatClient client,
    sdk.A2ALocalPeerAdvertisement peer,
  ) async {
    await client.deleteLocalA2APeer(peer.peerId);
    _a2aSlashPeers.remove(peer.peerId);
    final prefs = await SharedPreferences.getInstance();
    final paired =
        prefs.getStringList(_a2aPairedPeersKey)?.toSet() ?? <String>{};
    paired.remove(_localA2AHelper.pairingKey(peer));
    await prefs.setStringList(_a2aPairedPeersKey, paired.toList()..sort());
    await _a2aPairingSession.store.deleteRemotePairingSecret(
      _localA2AHelper.pairingKey(peer),
    );
  }

  Future<void> _deleteA2APairedPeer(sdk.A2APeer peer) async {
    final client = await _getChatClient();
    await client.deleteLocalA2APeer(peer.peerId);
    _a2aSlashPeers.remove(peer.peerId);
    final advertisement = _a2aAdvertisementFromSavedPeer(peer);
    if (advertisement != null) {
      final prefs = await SharedPreferences.getInstance();
      final paired =
          prefs.getStringList(_a2aPairedPeersKey)?.toSet() ?? <String>{};
      paired.remove(_localA2AHelper.pairingKey(advertisement));
      await prefs.setStringList(_a2aPairedPeersKey, paired.toList()..sort());
      await _a2aPairingSession.store.deleteRemotePairingSecret(
        _localA2AHelper.pairingKey(advertisement),
      );
    }
  }

  Future<void> _sendA2APairingRequest(String commandText, String args) async {
    final parts = args
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 2) {
      _appendSlashCommandResult(commandText, '建议在“附近”里扫码配对。手动配对请求只用于高级排障。');
      return;
    }
    final target = parts[1];
    final peer =
        _resolveA2ASlashPeer(target) ?? await _resolveA2APairedPeer(target);
    if (peer == null) {
      _appendSlashCommandResult(
        commandText,
        '找不到设备 `$target`。请先执行 `/a2a discover`。',
      );
      return;
    }
    final client = await _getChatClient();
    final status = await _ensureA2ALocalTransportStarted(client);
    if (status == null || !status.supported || !status.running) {
      _appendSlashCommandResult(
        commandText,
        status == null
            ? '本地 A2A 需要附近 Wi-Fi/局域网发现权限。权限未授予，已取消发送配对请求。'
            : '本地 A2A 未启动：${status.reason.isEmpty ? status.lastError : status.reason}',
      );
      return;
    }
    if (status.peerId.isEmpty) {
      _appendSlashCommandResult(commandText, '本机 peerId 为空，无法发送配对请求。');
      return;
    }
    final request = await _createA2APairingRequestMessage(status, peer);
    try {
      await _sendA2AMessageToPeerOrThrow(
        client,
        request,
        peer,
        purpose: '发送配对请求',
      );
      _appendSlashCommandResult(
        commandText,
        [
          '已向 `${_a2aPeerLabel(peer)}` 发送配对请求。',
          '请在对方手机上确认配对，然后回到“附近”查看已配对设备。',
        ].join('\n'),
      );
    } catch (error) {
      _appendSlashCommandResult(
        commandText,
        '向 `${_a2aPeerLabel(peer)}` 发送配对请求失败：$error',
      );
      return;
    }
  }

  Future<sdk.A2APeerMessage> _createA2APairingRequestMessage(
    sdk.A2ALocalTransportStatus status,
    sdk.A2ALocalPeerAdvertisement peer,
  ) async {
    final now = DateTime.now().toUtc();
    final nonce = now.microsecondsSinceEpoch.toString();
    final publicKey = await _ensureA2ALocalPublicKey();
    return sdk.A2APeerMessage(
      messageId: 'pair-$nonce',
      sessionId: 'pairing:${status.peerId}:${peer.peerId}',
      fromPeerId: status.peerId,
      toPeerId: peer.peerId,
      kind: 'pairing_request',
      createdAt: now.toIso8601String(),
      expiresAt: now.add(const Duration(minutes: 10)).toIso8601String(),
      nonce: nonce,
      idempotencyKey: 'pair-$nonce',
      payload: {
        'displayName': status.displayName,
        'agentId': status.agentId,
        'publicKey': publicKey,
        'endpoint': status.endpoint,
        'transport': status.transport,
        'pairingCode': _localA2AHelper.pairingCodeFromIdentity(
          status.peerId,
          publicKey,
        ),
        'instruction': '请确认身份码后，用对方提供的配对密钥执行 /a2a pair。',
      },
    );
  }

  Future<sdk.A2APeerMessage> _createA2APairingAcceptMessage(
    sdk.A2ALocalTransportStatus status,
    sdk.A2ALocalPeerAdvertisement peer,
  ) async {
    final now = DateTime.now().toUtc();
    final nonce = now.microsecondsSinceEpoch.toString();
    final publicKey = await _ensureA2ALocalPublicKey();
    final pairingSecret = await _ensureA2ALocalPairingSecret();
    return sdk.A2APeerMessage(
      messageId: 'pair-accept-$nonce',
      sessionId: 'pairing:${status.peerId}:${peer.peerId}',
      fromPeerId: status.peerId,
      toPeerId: peer.peerId,
      kind: 'pairing_accept',
      createdAt: now.toIso8601String(),
      expiresAt: now.add(const Duration(minutes: 10)).toIso8601String(),
      nonce: nonce,
      idempotencyKey: 'pair-accept-$nonce',
      payload: {
        'displayName': status.displayName,
        'agentId': status.agentId,
        'publicKey': publicKey,
        'pairingSecret': pairingSecret,
        'endpoint': status.endpoint,
        'transport': status.transport,
        'pairingCode': _localA2AHelper.pairingCodeFromIdentity(
          status.peerId,
          publicKey,
        ),
      },
    );
  }

  Future<sdk.A2APeerMessage> _createA2APairingCompleteMessage(
    sdk.A2ALocalTransportStatus status,
    sdk.A2ALocalPeerAdvertisement peer, {
    required String ackForMessageId,
  }) async {
    final now = DateTime.now().toUtc();
    final nonce = now.microsecondsSinceEpoch.toString();
    return sdk.A2APeerMessage(
      messageId: 'pair-complete-$nonce',
      sessionId: 'pairing:${status.peerId}:${peer.peerId}',
      fromPeerId: status.peerId,
      toPeerId: peer.peerId,
      kind: 'pairing_complete',
      createdAt: now.toIso8601String(),
      expiresAt: now.add(const Duration(minutes: 10)).toIso8601String(),
      nonce: nonce,
      idempotencyKey: 'pair-complete-$nonce',
      payload: {
        'ackForMessageId': ackForMessageId,
        'displayName': status.displayName,
        'agentId': status.agentId,
        'endpoint': status.endpoint,
        'transport': status.transport,
      },
    );
  }

  Future<sdk.A2APeerMessage> _createA2APairingCompleteAckMessage(
    sdk.A2ALocalTransportStatus status,
    sdk.A2ALocalPeerAdvertisement peer, {
    required String ackForMessageId,
  }) async {
    final now = DateTime.now().toUtc();
    final nonce = now.microsecondsSinceEpoch.toString();
    return sdk.A2APeerMessage(
      messageId: 'pair-complete-ack-$nonce',
      sessionId: 'pairing:${status.peerId}:${peer.peerId}',
      fromPeerId: status.peerId,
      toPeerId: peer.peerId,
      kind: 'ack',
      createdAt: now.toIso8601String(),
      expiresAt: now.add(const Duration(minutes: 10)).toIso8601String(),
      nonce: nonce,
      idempotencyKey: 'pair-complete-ack-$nonce',
      payload: {
        'ackKind': 'pairing_complete',
        'ackForMessageId': ackForMessageId,
        'displayName': status.displayName,
        'agentId': status.agentId,
        'endpoint': status.endpoint,
        'transport': status.transport,
      },
    );
  }

  Future<void> _sendA2ASlashTask(String commandText, String args) async {
    final parts = args
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final action = parts.isEmpty ? 'ask' : parts.first.toLowerCase();
    final rest = parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';
    final separator = rest.indexOf(RegExp(r'\s+'));
    if (separator <= 0 || separator >= rest.length - 1) {
      _appendSlashCommandResult(
        commandText,
        '用法：`/a2a $action <编号> <任务>`。\n先执行 `/a2a peers` 查看可信设备。',
      );
      return;
    }
    final target = rest.substring(0, separator).trim();
    final message = rest.substring(separator).trim();
    final peer = await _resolveA2APairedPeer(target);
    if (peer == null) {
      _appendSlashCommandResult(
        commandText,
        '找不到已配对设备 `$target`。请先在“附近”里扫码配对，或执行 `/a2a discover` 重新发现。',
      );
      return;
    }
    final client = await _getChatClient();
    final status = await _ensureA2ALocalTransportStarted(client);
    if (status == null || !status.supported || !status.running) {
      _appendSlashCommandResult(
        commandText,
        status == null
            ? '本地 A2A 需要附近 Wi-Fi/局域网发现权限。权限未授予，已取消发送。'
            : '本地 A2A 未启动：${status.reason.isEmpty ? status.lastError : status.reason}',
      );
      return;
    }
    final sharedSecret = await _a2aSharedSecretForPeer(peer, status: status);
    if (sharedSecret == null) {
      _appendSlashCommandResult(
        commandText,
        '设备 `${_a2aPeerLabel(peer)}` 缺少可信共享密钥。请重新执行 `/a2a pair $target <对方配对密钥>`。',
      );
      return;
    }
    final session = await client.openLocalA2ASession(
      peer,
      sharedSecret: sharedSecret,
    );
    final task = await client.createLocalA2ATaskMessage(
      session.sessionId,
      message,
    );
    try {
      await _sendA2AMessageToPeerOrThrow(client, task, peer, purpose: '发送任务');
      _appendA2AConversationMessage(
        message,
        sessionId: session.sessionId,
        peerLabel: _a2aPeerLabel(peer),
        messageId: '${task.messageId}-local-sent',
        createdAt: DateTime.tryParse(task.createdAt),
        role: ChatRole.user,
      );
    } catch (error) {
      _appendSlashCommandResult(
        commandText,
        _a2aSendFailureMessage(peer, task, purpose: '发送任务', error: error),
      );
      return;
    }
  }

  Future<void> _resendA2ASlashTask(String commandText, String args) async {
    final parts = args
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final taskId = parts.length > 1 ? parts[1].trim() : '';
    if (taskId.isEmpty) {
      _appendSlashCommandResult(
        commandText,
        '用法：`/a2a resend <taskId>`。\n先执行 `/a2a tasks` 或 `/a2a trace <taskId>` 找到已发任务。',
      );
      return;
    }
    final client = await _getChatClient();
    final task = await client.getLocalA2ATask(taskId);
    if (task == null || task.source != 'local_transport_outbound') {
      _appendSlashCommandResult(
        commandText,
        '找不到可重发的已发任务 `$taskId`。只有本机通过 `/a2a send` 发出的任务才能重发。',
      );
      return;
    }
    final message = await _a2aOriginalTaskRequestMessage(client, task);
    if (message == null) {
      _appendSlashCommandResult(
        commandText,
        '任务 `$taskId` 缺少原始 task_request 消息，无法安全重发。可执行 `/a2a trace $taskId` 查看账本。',
      );
      return;
    }
    final peer = await _resolveA2APairedPeer(message.toPeerId);
    if (peer == null) {
      _appendSlashCommandResult(
        commandText,
        '找不到任务 `$taskId` 的可信对端 `${message.toPeerId}`。请先执行 `/a2a discover` 或重新配对。',
      );
      return;
    }
    final status = await _ensureA2ALocalTransportStarted(client);
    if (status == null || !status.supported || !status.running) {
      _appendSlashCommandResult(
        commandText,
        status == null
            ? '本地 A2A 需要附近 Wi-Fi/局域网发现权限。权限未授予，已取消重发。'
            : '本地 A2A 未启动：${status.reason.isEmpty ? status.lastError : status.reason}',
      );
      return;
    }
    final sharedSecret = await _a2aSharedSecretForPeer(peer, status: status);
    if (sharedSecret == null) {
      _appendSlashCommandResult(
        commandText,
        '设备 `${_a2aPeerLabel(peer)}` 缺少可信共享密钥。请重新执行 `/a2a pair ${message.toPeerId} <对方配对密钥>`。',
      );
      return;
    }
    try {
      await _sendA2AMessageToPeerOrThrow(
        client,
        message,
        peer,
        purpose: '重发任务',
      );
      _appendSlashCommandResult(
        commandText,
        [
          '已重新发送给 ${_a2aPeerLabel(peer)}。',
          '对方回复会显示在附近对话里。',
          '需要排查时可用 `/a2a trace $taskId`。',
        ].join('\n'),
      );
    } catch (error) {
      _appendSlashCommandResult(
        commandText,
        _a2aSendFailureMessage(
          peer,
          message,
          purpose: '重发任务',
          error: error,
          taskId: taskId,
        ),
      );
    }
  }

  Future<sdk.A2APeerMessage?> _a2aOriginalTaskRequestMessage(
    NapaxiChatClient client,
    sdk.A2ATaskRecord task,
  ) async {
    final sessionId = task.sessionId?.trim() ?? '';
    if (sessionId.isEmpty) return null;
    final messages = await client.listLocalA2APeerMessages(
      sessionId,
      limit: 50,
    );
    for (final message in messages) {
      if (message.kind != 'task_request') continue;
      if (_a2aTaskIdFromMessage(message) == task.taskId) return message;
    }
    return null;
  }

  String _a2aSendFailureMessage(
    sdk.A2ALocalPeerAdvertisement peer,
    sdk.A2APeerMessage message, {
    required String purpose,
    required Object error,
    String? taskId,
  }) {
    final resolvedTaskId = taskId ?? _a2aTaskIdFromMessage(message);
    return [
      '向 `${_a2aPeerLabel(peer)}` $purpose 失败：$error',
      if (resolvedTaskId != null && resolvedTaskId.isNotEmpty)
        '可用 `/a2a trace $resolvedTaskId` 查看诊断。'
      else
        '可用 `/a2a doctor` 查看连接状态。',
    ].join('\n');
  }

  Future<void> _runA2ASlashTask(String commandText, String args) async {
    final taskId = args.trim().substring('run'.length).trim();
    if (taskId.isEmpty) {
      _appendSlashCommandResult(
        commandText,
        '用法：`/a2a run <taskId>`。\n收到对端任务后，聊天记录里会显示 taskId。',
      );
      return;
    }
    final task = await _resolveA2AInboundTask(taskId);
    if (task == null) {
      _appendSlashCommandResult(commandText, '找不到这条附近消息。请先确认对端已经发来消息。');
      return;
    }
    final run = _activeRun;
    if (run != null && !run.isTerminal) {
      _appendSlashCommandResult(
        commandText,
        '当前 Agent 还在运行中。请等待完成或先使用 `/stop`。',
      );
      return;
    }
    _appendSlashCommandResult(commandText, '正在让本机 Agent 处理这条附近消息。');
    final client = await _getChatClient();
    final record = await client.runLocalA2ATask(taskId);
    final summary = record.summary?.trim() ?? '';
    _appendA2ANoticeMessage(
      [
        if (record.error?.isNotEmpty == true) '处理失败：${record.error}',
        if (summary.isNotEmpty) summary,
        summary.isEmpty ? '任务没有产生可回传摘要。' : '可以执行 `/a2a answer $taskId` 发回对方。',
      ].join('\n'),
    );
  }

  Future<void> _answerA2ASlashTask(String commandText, String args) async {
    final taskId = args.trim().substring('answer'.length).trim();
    if (taskId.isEmpty) {
      _appendSlashCommandResult(
        commandText,
        '用法：`/a2a answer <taskId>`。\n先用 `/a2a run <taskId>` 让本机 Agent 完成任务。',
      );
      return;
    }
    final task = await _resolveA2AInboundTask(taskId);
    if (task == null) {
      _appendSlashCommandResult(commandText, '找不到这条附近消息。请先确认对端已经发来消息。');
      return;
    }
    final run = _activeRun;
    if (run != null && !run.isTerminal) {
      _appendSlashCommandResult(
        commandText,
        '当前 Agent 还在运行中，等回复完成后再执行 `/a2a answer $taskId`。',
      );
      return;
    }
    final answer = await _latestA2AAgentAnswerForTask(taskId);
    if (answer == null) {
      _appendSlashCommandResult(
        commandText,
        '还没有可回传的 Agent 回复。请先执行 `/a2a run $taskId`。',
      );
      return;
    }
    await _replyA2ASlashTask(
      commandText,
      'result $taskId $answer',
      result: true,
    );
  }

  Future<void> _acceptA2ASlashTask(String commandText, String args) async {
    final parts = args
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final taskId = parts.length > 1 ? parts[1].trim() : '';
    if (taskId.isEmpty) {
      _appendSlashCommandResult(
        commandText,
        '用法：`/a2a accept <编号>`。\n收到附近消息后，可在 `/a2a inbox` 里查看编号。',
      );
      return;
    }
    final taskInfo = await _resolveA2AInboundTask(taskId);
    if (taskInfo == null) {
      _appendSlashCommandResult(commandText, '找不到这条附近消息。请先确认对端已经发来消息。');
      return;
    }
    final run = _activeRun;
    if (run != null && !run.isTerminal) {
      _appendSlashCommandResult(
        commandText,
        '当前 Agent 还在运行中。请等待完成或先使用 `/stop`。',
      );
      return;
    }
    final peer = await _resolveA2APairedPeer(taskInfo.fromPeerId);
    if (peer == null) {
      _appendSlashCommandResult(
        commandText,
        '找不到对方的可用连接。请确认两台手机都打开“附近”，或重新扫码配对。',
      );
      return;
    }
    final client = await _getChatClient();
    final status = await _ensureA2ALocalTransportStarted(client);
    if (status == null || !status.supported || !status.running) {
      _appendSlashCommandResult(
        commandText,
        status == null
            ? '本地 A2A 需要附近 Wi-Fi/局域网发现权限。权限未授予，已取消执行。'
            : '本地 A2A 未启动：${status.reason.isEmpty ? status.lastError : status.reason}',
      );
      return;
    }
    final sharedSecret = await _a2aSharedSecretForPeer(peer, status: status);
    if (sharedSecret == null) {
      _appendSlashCommandResult(
        commandText,
        '设备 `${_a2aPeerLabel(peer)}` 缺少可信共享密钥。请重新执行 `/a2a pair ${taskInfo.fromPeerId} <对方配对密钥>`。',
      );
      return;
    }
    await client.openLocalA2ASession(peer, sharedSecret: sharedSecret);
    final record = await client.getLocalA2ATask(taskId);
    if (record == null) {
      _appendSlashCommandResult(commandText, '这条附近消息的记录不完整，暂时无法处理。');
      return;
    }
    _appendSlashCommandResult(commandText, '正在让本机 Agent 回复这条附近消息。');
    try {
      final progress = await client.createLocalA2AProgressMessage(
        taskInfo.sessionId,
        taskInfo.taskId,
        '对端已确认，正在交给本机 Agent。',
        status: 'running',
      );
      final progressEvidence = await _sendA2AMessageToPeerOrThrow(
        client,
        progress,
        peer,
        purpose: '回传任务进度',
      );

      final receipt = await client.submitLocalA2AChannelTask(
        task: record,
        peer: peer,
      );
      final run = await client.runLocalA2AChannelTask(
        taskId: taskId,
        agentId: _activeAgentId,
      );
      if (!run.delivered) {
        final error = (run.error ?? '').trim();
        debugPrint(
          '[napaxiToolTrace] local A2A task result not delivered task=$taskId inbound=${receipt.inboundId} progress=${progressEvidence.deliveryStatus} error=$error',
        );
      } else {
        debugPrint(
          '[napaxiToolTrace] local A2A task delivered task=$taskId inbound=${receipt.inboundId} duplicate=${receipt.duplicate} phase=${run.phase} progress=${progressEvidence.deliveryStatus}',
        );
      }
    } catch (error) {
      final failure = await client.createLocalA2AResultMessage(
        taskInfo.sessionId,
        taskInfo.taskId,
        '本机 Agent 执行失败：$error',
        status: 'failed',
      );
      try {
        final failureEvidence = await _sendA2AMessageToPeerOrThrow(
          client,
          failure,
          peer,
          purpose: '回传任务失败结果',
        );
        if (!mounted) return;
        debugPrint(
          '[napaxiToolTrace] local A2A task failed task=$taskId message=${failureEvidence.messageId} delivery=${failureEvidence.deliveryStatus} error=$error',
        );
      } catch (sendError) {
        if (!mounted) return;
        debugPrint(
          '[napaxiToolTrace] local A2A failure result not delivered task=$taskId sendError=$sendError original=$error',
        );
      }
    }
  }

  Future<void> _replyA2ASlashTask(
    String commandText,
    String args, {
    required bool result,
  }) async {
    final trimmed = args.trim();
    final parts = trimmed.split(RegExp(r'\s+'));
    final action = parts.isEmpty
        ? (result ? 'result' : 'progress')
        : parts.first;
    final rest = trimmed.substring(action.length).trim();
    final separator = rest.indexOf(RegExp(r'\s+'));
    if (separator <= 0 || separator >= rest.length - 1) {
      _appendSlashCommandResult(
        commandText,
        '用法：`/a2a $action <编号> <内容>`。\n收到附近消息后，可在 `/a2a inbox` 里查看编号。',
      );
      return;
    }
    final taskId = rest.substring(0, separator).trim();
    final content = rest.substring(separator).trim();
    final task = await _resolveA2AInboundTask(taskId);
    if (task == null) {
      _appendSlashCommandResult(commandText, '找不到这条附近消息。请先确认对端已经发来消息。');
      return;
    }
    final peer = await _resolveA2APairedPeer(task.fromPeerId);
    if (peer == null) {
      _appendSlashCommandResult(
        commandText,
        '找不到对方的可用连接。请确认两台手机都打开“附近”，或重新扫码配对。',
      );
      return;
    }
    final client = await _getChatClient();
    final status = await _ensureA2ALocalTransportStarted(client);
    if (status == null || !status.supported || !status.running) {
      _appendSlashCommandResult(
        commandText,
        status == null
            ? '本地 A2A 需要附近 Wi-Fi/局域网发现权限。权限未授予，已取消回传。'
            : '本地 A2A 未启动：${status.reason.isEmpty ? status.lastError : status.reason}',
      );
      return;
    }
    final sharedSecret = await _a2aSharedSecretForPeer(peer, status: status);
    if (sharedSecret == null) {
      _appendSlashCommandResult(
        commandText,
        '设备 `${_a2aPeerLabel(peer)}` 缺少可信共享密钥。请重新执行 `/a2a pair ${task.fromPeerId} <对方配对密钥>`。',
      );
      return;
    }
    await client.openLocalA2ASession(peer, sharedSecret: sharedSecret);
    final message = result
        ? await client.createLocalA2AResultMessage(
            task.sessionId,
            task.taskId,
            content,
          )
        : await client.createLocalA2AProgressMessage(
            task.sessionId,
            task.taskId,
            content,
          );
    try {
      await _sendA2AMessageToPeerOrThrow(
        client,
        message,
        peer,
        purpose: result ? '回传任务结果' : '回传任务进度',
      );
    } catch (error) {
      _appendSlashCommandResult(
        commandText,
        _a2aSendFailureMessage(
          peer,
          message,
          purpose: result ? '回传结果' : '回传进度',
          error: error,
          taskId: taskId,
        ),
      );
      return;
    }
    _appendSlashCommandResult(
      commandText,
      [
        result ? '已回复 ${_a2aPeerLabel(peer)}。' : '已更新 ${_a2aPeerLabel(peer)}。',
        result ? content : '对方会在附近对话里看到更新。',
        '需要排查时可用 `/a2a trace $taskId`。',
      ].join('\n'),
    );
  }

  Future<_A2ASendEvidence> _sendA2AMessageToPeerOrThrow(
    NapaxiChatClient client,
    sdk.A2APeerMessage message,
    sdk.A2ALocalPeerAdvertisement peer, {
    required String purpose,
    bool requireFreshDiscovery = false,
  }) async {
    if (!requireFreshDiscovery) {
      return _sendA2AHandshakeMessageToPeerOrThrow(
        client,
        message,
        peer,
        purpose: purpose,
      );
    }
    final refreshed = await _refreshA2APeerEndpointForSend(client, peer);
    if (refreshed != null) {
      return _sendA2AMessageToEndpointOrThrow(
        client,
        message,
        refreshed.endpoint,
        purpose: purpose,
      );
    }
    return _sendA2AHandshakeMessageToPeerOrThrow(
      client,
      message,
      peer,
      purpose: purpose,
    );
  }

  Future<_A2ASendEvidence> _sendA2AHandshakeMessageToPeerOrThrow(
    NapaxiChatClient client,
    sdk.A2APeerMessage message,
    sdk.A2ALocalPeerAdvertisement peer, {
    required String purpose,
  }) async {
    Object? directError;
    if (peer.endpoint.trim().isNotEmpty) {
      try {
        return await _sendA2AMessageToEndpointOrThrow(
          client,
          message,
          peer.endpoint,
          purpose: purpose,
        );
      } catch (error) {
        directError = error;
      }
    }

    try {
      final refreshed = await _refreshA2APeerEndpointForSend(client, peer);
      if (refreshed == null) {
        throw StateError('附近未发现 ${_a2aPeerLabel(peer)}，无法刷新可用连接。');
      }
      return await _sendA2AMessageToEndpointOrThrow(
        client,
        message,
        refreshed.endpoint,
        purpose: purpose,
      );
    } catch (error) {
      if (directError == null) rethrow;
      throw StateError(
        '$purpose 失败：直连地址 ${peer.endpoint} 不可达；附近发现兜底也失败：$error；直连错误：$directError',
      );
    }
  }

  Future<_A2ASendEvidence> _sendA2AMessageToEndpointOrThrow(
    NapaxiChatClient client,
    sdk.A2APeerMessage message,
    String endpoint, {
    required String purpose,
  }) async {
    final normalizedEndpoint = endpoint.trim();
    if (normalizedEndpoint.isEmpty) {
      throw StateError('$purpose 缺少对端地址');
    }
    final sent = await client.sendLocalA2AMessage(
      message,
      endpoint: normalizedEndpoint,
    );
    if (!sent) {
      throw StateError('$purpose 未送达 $normalizedEndpoint');
    }
    return _A2ASendEvidence(
      messageId: message.messageId,
      endpoint: normalizedEndpoint,
      deliveryStatus: await _a2aDeliveryStatusForMessage(client, message),
    );
  }

  Future<sdk.A2ALocalPeerAdvertisement?> _refreshA2APeerEndpointForSend(
    NapaxiChatClient client,
    sdk.A2ALocalPeerAdvertisement peer,
  ) async {
    try {
      final discovered = await client.discoverLocalA2APeers(timeoutMs: 2200);
      for (final candidate in discovered) {
        if (candidate.peerId != peer.peerId ||
            candidate.endpoint.trim().isEmpty) {
          continue;
        }
        _a2aSlashPeers[candidate.peerId] = candidate;
        return candidate;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<String> _a2aDeliveryStatusForMessage(
    NapaxiChatClient client,
    sdk.A2APeerMessage message,
  ) async {
    try {
      final deliveries = await client.listLocalA2ADeliveryRecords(
        message.sessionId,
        limit: 20,
      );
      sdk.A2ADeliveryRecord? best;
      for (final delivery in deliveries) {
        if (delivery.messageId != message.messageId) continue;
        if (best == null ||
            _a2aDeliveryStatusRank(delivery.status) >
                _a2aDeliveryStatusRank(best.status)) {
          best = delivery;
        }
      }
      if (best != null) return best.status;
    } catch (_) {
      return 'unknown';
    }
    return 'unknown';
  }

  int _a2aDeliveryStatusRank(String status) {
    return switch (status.trim().toLowerCase()) {
      'failed' => 90,
      'succeeded' => 80,
      'running' => 70,
      'accepted' => 60,
      'rejected' => 55,
      'delivered' => 50,
      'sent' => 40,
      'expired' => 30,
      'duplicate' => 25,
      'created' => 10,
      _ => 0,
    };
  }

  Future<sdk.A2ALocalTransportStatus?> _ensureA2ALocalTransportStarted(
    NapaxiChatClient client, {
    bool requestPermission = true,
  }) async {
    await _ensureA2AEventSubscription();
    var status = await client.localA2AStatus();
    if (status.running) return status;
    if (!status.supported) return status;
    final permissionGranted = requestPermission
        ? await client.requestLocalA2APermission()
        : await client.checkLocalA2APermission();
    if (!permissionGranted) return null;
    status = await client.startLocalA2A(
      agentId: _activeAgentId,
      displayName: _activeAgent.label(widget.language),
      publicKey: await _ensureA2ALocalPublicKey(),
    );
    if (!status.running) {
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        status = await client.localA2AStatus();
        if (status.running) break;
      }
    }
    return status;
  }

  Future<bool?> _loadA2AConnectionAllowedPreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_a2aConnectionAllowedKey);
  }

  Future<void> _saveA2AConnectionAllowed(bool allowed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_a2aConnectionAllowedKey, allowed);
  }

  Future<void> _setA2AConnectionAllowedFromSettings(bool allowed) async {
    final client = await _getChatClient();
    if (!allowed) {
      await _saveA2AConnectionAllowed(false);
      await client.stopLocalA2A();
      return;
    }
    final status = await _ensureA2ALocalTransportStarted(client);
    final started = status != null && status.supported && status.running;
    await _saveA2AConnectionAllowed(started);
  }

  void _scheduleA2AConnectionRestoreIfAllowed() {
    if (_a2aConnectionRestoreFuture != null) return;
    final restore = _restoreA2AConnectionIfAllowed();
    _a2aConnectionRestoreFuture = restore;
    unawaited(
      restore.whenComplete(() {
        if (identical(_a2aConnectionRestoreFuture, restore)) {
          _a2aConnectionRestoreFuture = null;
        }
      }),
    );
  }

  Future<void> _ensureA2AConnectionReadyForUserTurn() async {
    final allowedPreference = await _loadA2AConnectionAllowedPreference();
    if (allowedPreference == false) return;

    final pendingRestore = _a2aConnectionRestoreFuture;
    if (pendingRestore != null) {
      try {
        await pendingRestore.timeout(const Duration(milliseconds: 1600));
      } catch (_) {
        // The normal restore path continues in the background. This gate only
        // prevents the first user turn from racing the common fast path.
      }
    }

    final client = await _getChatClient();
    if (allowedPreference != true && !await _hasAnyTrustedA2APeer(client)) {
      return;
    }
    await _ensureA2ALocalTransportStarted(client, requestPermission: false);
  }

  Future<void> _restoreA2AConnectionIfAllowed() async {
    final allowedPreference = await _loadA2AConnectionAllowedPreference();
    if (allowedPreference == false) return;
    try {
      final client = await _getChatClient();
      final profile = _runtimeProfileForAgent(_activeAgentId);
      if (profile != null &&
          profile.hasModel &&
          profile.apiKey.trim().isNotEmpty) {
        await client.configure(
          profile,
          responseLanguage: _responseLanguageCode,
          capabilitySelection: _activeScenarioCapabilitySelection,
        );
      } else {
        await client.configureForManagement(
          capabilitySelection: _activeScenarioCapabilitySelection,
        );
      }
      if (allowedPreference != true && !await _hasAnyTrustedA2APeer(client)) {
        return;
      }
      await _ensureA2ALocalTransportStarted(client, requestPermission: false);
    } catch (error) {
      debugPrint('A2A auto-restore skipped: $error');
    }
  }

  Future<bool> _hasAnyTrustedA2APeer(NapaxiChatClient client) async {
    for (final peer in await client.listLocalA2APeers()) {
      final trust = peer.trustLevel.trim().toLowerCase();
      if (peer.sharedSecret.trim().isNotEmpty ||
          trust == 'user_confirmed' ||
          trust == 'trusted') {
        return true;
      }
    }
    return false;
  }

  Future<void> _ensureA2AEventSubscription() async {
    if (_a2aEventSubscription != null) return;
    final client = await _getChatClient();
    if (!mounted || _a2aEventSubscription != null) return;
    _a2aEventSubscription = client.localA2AEvents.listen(
      (event) {
        unawaited(_handleA2APageEvent(client, event));
      },
      onError: (Object error) {
        debugPrint('A2A event subscription error: $error');
      },
    );
  }

  Future<void> _handleA2APageEvent(
    NapaxiChatClient client,
    sdk.A2ALocalTransportEvent event,
  ) async {
    if (_isA2ABlobFrameEvent(event)) {
      await client.handleLocalA2ABlobFrame(event);
      return;
    }
    final peer = event.peer;
    if (peer != null) {
      _a2aSlashPeers[peer.peerId] = peer;
      return;
    }
    final message = event.message;
    if (message == null) return;
    if (_isA2APairingCompleteAckMessage(message)) {
      _handleA2APairingCompleteAckMessage(message);
      return;
    }
    if (message.kind == 'pairing_complete') {
      await _handleA2APairingCompleteMessage(client, message);
      return;
    }
    // The SDK session owns the parity-critical routing decision (dedup,
    // loopback filter, kind mapping); the demo keeps all UI/side effects.
    final route = _a2aPairingSession.classifyInboundMessage(message);
    switch (route) {
      case sdk.A2AInboundRoute.duplicate:
      case sdk.A2AInboundRoute.loopback:
        return;
      case sdk.A2AInboundRoute.pairingAccept:
        await _handleA2APairingAcceptMessage(client, message);
        return;
      case sdk.A2AInboundRoute.pairingRequest:
        final requestPeer = _a2aPeerFromPairingRequest(message);
        if (requestPeer != null) {
          _a2aSlashPeers[requestPeer.peerId] = requestPeer;
        }
        _appendA2APairingRequestNotice(message);
        return;
      case sdk.A2AInboundRoute.taskRequest:
      case sdk.A2AInboundRoute.other:
        break;
    }
    late final sdk.A2ADeliveryRecord delivery;
    try {
      delivery = await client.recordLocalA2AMessage(message);
    } catch (error) {
      if (!mounted) return;
      debugPrint('[napaxiToolTrace] local A2A message record failed: $error');
      _showChatSnackBar('附近消息记录失败。');
      return;
    }
    final failed = delivery.status.trim().toLowerCase() == 'failed';
    if (failed) {
      if (!mounted) return;
      final reason = (delivery.error ?? '').trim();
      debugPrint(
        '[napaxiToolTrace] local A2A message trust failed reason=$reason',
      );
      _showChatSnackBar('收到附近消息，但设备信任校验没有通过。');
      return;
    }
    if (!mounted) return;
    try {
      final peer = await _resolveA2APairedPeer(message.fromPeerId);
      var autoRunCollaboration = false;
      sdk.A2ATaskRecord? taskRecord;
      final messageTaskId = delivery.taskId ?? _a2aTaskIdFromMessage(message);
      if (messageTaskId != null && messageTaskId.isNotEmpty) {
        taskRecord = await client.getLocalA2ATask(messageTaskId);
      }
      taskRecord ??= await _a2aTaskRecordForPeerMessage(
        client,
        message.messageId,
      );
      final isTaskRequest =
          route == sdk.A2AInboundRoute.taskRequest ||
          message.kind == 'task_request';
      final isTaskUpdate =
          message.kind == 'task_progress' || message.kind == 'task_result';
      var visibleAttachments = await _a2aVisibleAttachmentsForMessage(
        client,
        message,
        taskRecord,
      );
      if (isTaskUpdate && !isTaskRequest) {
        if (message.kind == 'task_result') {
          _appendA2AInboundChatMessage(
            client,
            message,
            delivery,
            peer: peer,
            taskRecord: taskRecord,
            attachments: visibleAttachments,
          );
        }
        return;
      }
      if (isTaskRequest) {
        final taskId = delivery.taskId ?? message.messageId;
        taskRecord ??= await client.getLocalA2ATask(taskId);
        visibleAttachments = await _a2aVisibleAttachmentsForMessage(
          client,
          message,
          taskRecord,
        );
        final title =
            _a2aTaskTitleFromRecord(taskRecord) ?? _a2aTaskTitle(message);
        _a2aInboundTasks[taskId] = _A2AInboundTask(
          taskId: taskId,
          sessionId: message.sessionId,
          fromPeerId: message.fromPeerId,
          title: title,
        );
        if (delivery.status == 'delivered' && peer != null) {
          unawaited(
            _sendA2ATaskReceipt(client, peer, message.sessionId, taskId),
          );
        }
        autoRunCollaboration =
            peer != null &&
            _shouldAutoRunA2ACollaboration(taskRecord, delivery);
      }
      if (peer == null) {
        _appendA2AInboundChatMessage(
          client,
          message,
          delivery,
          peer: peer,
          taskRecord: taskRecord,
          attachments: visibleAttachments,
        );
      } else if (autoRunCollaboration) {
        final taskId = delivery.taskId ?? message.messageId;
        _appendA2AInboundChatMessage(
          client,
          message,
          delivery,
          peer: peer,
          taskRecord: taskRecord,
          attachments: visibleAttachments,
        );
        unawaited(
          _autoRunA2ACollaborationTask(
            client,
            peer: peer,
            taskId: taskId,
            message: message,
            taskRecord: taskRecord,
          ),
        );
      } else {
        _appendA2AInboundChatMessage(
          client,
          message,
          delivery,
          peer: peer,
          taskRecord: taskRecord,
          attachments: visibleAttachments,
        );
      }
    } catch (error) {
      if (!mounted) return;
      debugPrint('[napaxiToolTrace] local A2A message display failed: $error');
      _showChatSnackBar('附近消息展示失败。');
    }
  }

  bool _isA2ABlobFrameEvent(sdk.A2ALocalTransportEvent event) {
    final payloadFrame = event.message?.payload['a2aBlobFrame'];
    if (payloadFrame is Map) {
      final frameType = payloadFrame['frameType']?.toString().trim() ?? '';
      if (frameType.startsWith('a2a_blob_')) return true;
    }
    final raw = event.messageJson.trim();
    if (raw.isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final payload = decoded['payload'];
      if (payload is Map) {
        final frame = payload['a2aBlobFrame'];
        if (frame is Map) {
          final frameType = frame['frameType']?.toString().trim() ?? '';
          return frameType.startsWith('a2a_blob_');
        }
      }
      final frameType = decoded['frameType']?.toString().trim() ?? '';
      return frameType.startsWith('a2a_blob_');
    } catch (_) {
      return false;
    }
  }

  bool _isA2APairingCompleteAckMessage(sdk.A2APeerMessage message) {
    if (message.kind == 'pairing_complete_ack') return true;
    return message.kind == 'ack' &&
        message.payload['ackKind'] == 'pairing_complete';
  }

  Future<void> _handleA2APairingAcceptMessage(
    NapaxiChatClient client,
    sdk.A2APeerMessage message,
  ) async {
    final peer = _a2aPeerFromPairingRequest(message);
    final remoteSecret = _localA2AHelper.normalizePairingSecret(
      message.payload['pairingSecret']?.toString() ?? '',
    );
    if (peer == null || remoteSecret.isEmpty) {
      _appendA2ANoticeMessage(
        [
          '**收到配对确认，但无法完成配对**',
          '- 原因：确认消息内容不完整。',
          '',
          '请重新打开“附近”扫码配对。',
        ].join('\n'),
      );
      return;
    }
    _a2aSlashPeers[peer.peerId] = peer;
    final status = await _ensureA2ALocalTransportStarted(client);
    if (status == null || !status.supported || !status.running) {
      _setA2APairingDiagnostic('配对失败', [
        '阶段：处理对端确认',
        '本地 A2A 未启动',
        if (status != null && status.reason.isNotEmpty) '原因：${status.reason}',
        if (status != null && status.lastError.isNotEmpty)
          '错误：${status.lastError}',
      ]);
      _appendA2ANoticeMessage(
        status == null
            ? '本地 A2A 需要附近 Wi-Fi/局域网发现权限。权限未授予，暂时无法保存配对确认。'
            : '本地 A2A 未启动：${status.reason.isEmpty ? status.lastError : status.reason}',
      );
      return;
    }
    await _saveA2APairedPeer(
      client,
      status,
      peer,
      remotePairingSecret: remoteSecret,
    );
    _setA2APairingDiagnostic('配对进行中', [
      '阶段：已收到对端确认',
      '设备：${_a2aPeerLabel(peer)}',
      '正在发送完成回执',
    ]);
    try {
      final complete = await _createA2APairingCompleteMessage(
        status,
        peer,
        ackForMessageId: message.messageId,
      );
      final ack = _waitForA2APairingCompleteAck(
        peer.peerId,
        ackForMessageId: complete.messageId,
      );
      Object? sendError;
      try {
        await _sendA2AHandshakeMessageToPeerOrThrow(
          client,
          complete,
          peer,
          purpose: '发送配对完成回执',
        );
      } catch (error) {
        sendError = error;
      }
      try {
        await ack;
      } catch (ackError) {
        _cancelA2APairingCompleteAckWait(peer.peerId, ackError);
        if (sendError != null) {
          throw StateError('$sendError；且未收到对端应用层 ACK：$ackError');
        }
        rethrow;
      }
    } catch (error) {
      final failureStatus = await client.localA2AStatus();
      await _forgetA2APairedPeer(client, peer);
      final transportError = failureStatus.lastError.trim();
      debugPrint(
        '[napaxiToolTrace] local A2A pairing completion failed peer=${peer.peerId} endpoint=${peer.endpoint} error=$error transport=$transportError',
      );
      _setA2APairingDiagnostic('配对失败', [
        '阶段：发送完成回执',
        '对端：${_a2aPeerLabel(peer)}',
        '错误：${_a2aUserFacingError(error)}',
        if (transportError.isNotEmpty)
          '传输错误：${_a2aUserFacingError(transportError)}',
      ]);
      _appendA2ANoticeMessage(
        [
          '**配对完成回执发送失败，已回滚本机配对**',
          '- 设备：`${_a2aPeerLabel(peer)}`',
          '- 错误：${_a2aUserFacingError(error)}',
          if (transportError.isNotEmpty)
            '- 传输错误：${_a2aUserFacingError(transportError)}',
          '',
          '两台设备都不会保留这次失败配对。请确认“附近”开启后重新扫码。',
        ].join('\n'),
      );
      return;
    }
    _setA2APairingDiagnostic('配对成功', ['对端：${_a2aPeerLabel(peer)}', '对方已确认']);
    await _saveA2AConnectionAllowed(true);
    _appendA2ANoticeMessage('配对成功：`${_a2aPeerLabel(peer)}` 已添加。');
  }

  Future<void> _handleA2APairingCompleteMessage(
    NapaxiChatClient client,
    sdk.A2APeerMessage message,
  ) async {
    final pending = _a2aPendingPairingCompletions[message.fromPeerId];
    if (pending == null || pending.completer.isCompleted) return;
    final ackFor = message.payload['ackForMessageId']?.toString().trim() ?? '';
    if (ackFor != pending.ackForMessageId) return;
    final peer =
        _a2aSlashPeers[message.fromPeerId] ??
        _a2aPeerFromPairingRequest(message);
    if (peer == null) {
      _a2aPendingPairingCompletions.remove(message.fromPeerId);
      pending.completer.completeError(StateError('配对完成回执内容不完整'));
      return;
    }
    try {
      final status = await _ensureA2ALocalTransportStarted(client);
      if (status == null || !status.supported || !status.running) {
        throw StateError('本地 A2A 未启动，无法发送完成 ACK');
      }
      final ack = await _createA2APairingCompleteAckMessage(
        status,
        peer,
        ackForMessageId: message.messageId,
      );
      await _sendA2AHandshakeMessageToPeerOrThrow(
        client,
        ack,
        peer,
        purpose: '发送配对完成 ACK',
      );
      _a2aPendingPairingCompletions.remove(message.fromPeerId);
      pending.completer.complete(message);
    } catch (error) {
      _a2aPendingPairingCompletions.remove(message.fromPeerId);
      pending.completer.completeError(error);
      await _forgetA2APairedPeer(client, peer);
    }
  }

  void _handleA2APairingCompleteAckMessage(sdk.A2APeerMessage message) {
    final pending = _a2aPendingPairingAcks[message.fromPeerId];
    if (pending == null || pending.completer.isCompleted) return;
    final ackFor = message.payload['ackForMessageId']?.toString().trim() ?? '';
    if (ackFor != pending.ackForMessageId) return;
    _a2aPendingPairingAcks.remove(message.fromPeerId);
    pending.completer.complete(message);
  }

  Future<sdk.A2APeerMessage> _waitForA2APairingComplete(
    String peerId, {
    required String ackForMessageId,
  }) {
    final existing = _a2aPendingPairingCompletions.remove(peerId);
    if (existing != null && !existing.completer.isCompleted) {
      existing.completer.completeError(StateError('A2A pairing superseded'));
    }
    final completer = Completer<sdk.A2APeerMessage>();
    _a2aPendingPairingCompletions[peerId] = _A2APendingPairingCompletion(
      ackForMessageId: ackForMessageId,
      completer: completer,
    );
    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        _a2aPendingPairingCompletions.remove(peerId);
        throw TimeoutException('对端没有确认配对落库');
      },
    );
  }

  void _cancelA2APairingCompleteWait(String peerId, Object error) {
    final pending = _a2aPendingPairingCompletions.remove(peerId);
    if (pending == null || pending.completer.isCompleted) return;
    pending.completer.completeError(error);
  }

  Future<sdk.A2APeerMessage> _waitForA2APairingCompleteAck(
    String peerId, {
    required String ackForMessageId,
  }) {
    final existing = _a2aPendingPairingAcks.remove(peerId);
    if (existing != null && !existing.completer.isCompleted) {
      existing.completer.completeError(
        StateError('A2A pairing ack superseded'),
      );
    }
    final completer = Completer<sdk.A2APeerMessage>();
    _a2aPendingPairingAcks[peerId] = _A2APendingPairingCompletion(
      ackForMessageId: ackForMessageId,
      completer: completer,
    );
    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        _a2aPendingPairingAcks.remove(peerId);
        throw TimeoutException('对端没有确认收到配对完成回执');
      },
    );
  }

  void _cancelA2APairingCompleteAckWait(String peerId, Object error) {
    final pending = _a2aPendingPairingAcks.remove(peerId);
    if (pending == null || pending.completer.isCompleted) return;
    pending.completer.completeError(error);
  }

  void _appendA2APairingRequestNotice(sdk.A2APeerMessage message) {
    final displayName = message.payload['displayName']?.toString().trim();
    final pairingCode = message.payload['pairingCode']?.toString().trim();
    _appendA2ANoticeMessage(
      [
        '**确认配对**',
        if (displayName != null && displayName.isNotEmpty) '- 名称：$displayName',
        if (pairingCode != null && pairingCode.isNotEmpty)
          '- 对方身份码：`$pairingCode`',
        '',
        '请确认这是你要连接的设备。建议优先在“附近”里扫码配对。',
      ].join('\n'),
    );
  }

  sdk.A2ALocalPeerAdvertisement? _a2aPeerFromPairingRequest(
    sdk.A2APeerMessage message,
  ) {
    final endpoint = message.payload['endpoint']?.toString().trim() ?? '';
    if (message.fromPeerId.isEmpty || endpoint.isEmpty) return null;
    final transport = message.payload['transport']?.toString().trim() ?? '';
    return sdk.A2ALocalPeerAdvertisement(
      peerId: message.fromPeerId,
      agentId: message.payload['agentId']?.toString().trim() ?? '',
      displayName: message.payload['displayName']?.toString().trim() ?? '',
      publicKey: message.payload['publicKey']?.toString().trim() ?? '',
      transport: transport.isEmpty ? 'lan_tcp_jsonl' : transport,
      endpoint: endpoint,
    );
  }

  Map<String, dynamic> _a2aCollaborationForVisibleMessage(
    sdk.A2APeerMessage message,
    sdk.A2ATaskRecord? taskRecord,
  ) {
    final taskCollaboration = taskRecord?.request.context['a2aCollaboration'];
    if (taskCollaboration is Map) {
      return Map<String, dynamic>.from(taskCollaboration);
    }
    final messageCollaboration = _a2aCollaborationContext(message);
    if (messageCollaboration != null) {
      return Map<String, dynamic>.from(messageCollaboration);
    }
    return const <String, dynamic>{};
  }

  String? _a2aStringField(Map<dynamic, dynamic> map, Iterable<String> keys) {
    for (final key in keys) {
      final value = map[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  List<sdk.A2AArtifact> _a2aArtifactsFromDynamic(Object? raw) {
    if (raw is! List) return const [];
    final artifacts = <sdk.A2AArtifact>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        artifacts.add(
          sdk.A2AArtifact.fromJson(Map<String, dynamic>.from(item)),
        );
      } catch (_) {}
    }
    return artifacts;
  }

  List<sdk.A2AArtifact> _a2aArtifactsFromPeerMessage(
    sdk.A2APeerMessage message,
    String payloadKey,
  ) {
    final payload = message.payload[payloadKey];
    if (payload is! Map) return const [];
    return _a2aArtifactsFromDynamic(payload['artifacts']);
  }

  List<sdk.A2AArtifact> _a2aArtifactsForVisibleMessage(
    sdk.A2APeerMessage message,
    sdk.A2ATaskRecord? taskRecord,
  ) {
    if (message.kind == 'task_result') {
      if (taskRecord?.resultArtifacts.isNotEmpty == true) {
        return taskRecord!.resultArtifacts;
      }
      return _a2aArtifactsFromPeerMessage(message, 'result');
    }
    if (taskRecord?.request.artifacts.isNotEmpty == true) {
      return taskRecord!.request.artifacts;
    }
    return _a2aArtifactsFromPeerMessage(message, 'task');
  }

  Future<List<ChatAttachment>> _a2aVisibleAttachmentsForMessage(
    NapaxiChatClient client,
    sdk.A2APeerMessage message,
    sdk.A2ATaskRecord? taskRecord,
  ) async {
    final artifacts = _a2aArtifactsForVisibleMessage(message, taskRecord);
    if (artifacts.isEmpty) return const [];
    final resolved = await client.resolveLocalA2AArtifacts(artifacts);
    return _a2aChatAttachmentsFromArtifacts(resolved);
  }

  List<ChatAttachment> _a2aChatAttachmentsFromArtifacts(
    List<sdk.A2AArtifact> artifacts,
  ) {
    final attachments = <ChatAttachment>[];
    final seen = <String>{};
    for (final artifact in artifacts) {
      final realPath = _a2aArtifactRealPath(artifact);
      if (realPath.isEmpty || !File(realPath).existsSync()) continue;
      final sandboxPath = _a2aArtifactSandboxPath(artifact);
      final identity = sandboxPath.isNotEmpty ? sandboxPath : realPath;
      if (!seen.add(identity)) continue;
      final mime = artifact.mimeType.trim();
      final name = artifact.name.trim().isNotEmpty
          ? artifact.name.trim()
          : realPath.split(Platform.pathSeparator).last;
      attachments.add(
        ChatAttachment(
          name: name.isEmpty ? 'A2A attachment' : name,
          path: realPath,
          type: mime.toLowerCase().startsWith('image/')
              ? ChatAttachmentType.image
              : ChatAttachmentType.file,
          sandboxPath: sandboxPath.isEmpty ? null : sandboxPath,
          mimeTypeOverride: mime.isEmpty ? null : mime,
        ),
      );
    }
    return List.unmodifiable(attachments);
  }

  String _a2aArtifactSandboxPath(sdk.A2AArtifact artifact) {
    final metadata = artifact.metadata;
    final fromMetadata = _a2aStringField(metadata, const [
      'sandbox_path',
      'sandboxPath',
    ]);
    if (fromMetadata != null) return fromMetadata;
    final uri = artifact.uri?.trim() ?? '';
    if (uri.startsWith('/workspace/')) return uri;
    if (uri.startsWith('napaxi-sandbox://')) {
      return uri.substring('napaxi-sandbox://'.length);
    }
    return '';
  }

  String _a2aArtifactRealPath(sdk.A2AArtifact artifact) {
    final uri = artifact.uri?.trim() ?? '';
    if (uri.startsWith('a2a-blob://')) return '';
    final candidates = <String>[];
    void addCandidate(String? path) {
      final value = path?.trim() ?? '';
      if (value.isEmpty || candidates.contains(value)) return;
      candidates.add(value);
    }

    if (uri.startsWith('file://')) {
      try {
        addCandidate(Uri.parse(uri).toFilePath());
      } catch (_) {}
    }
    final sandboxPath = _a2aArtifactSandboxPath(artifact);
    if (sandboxPath.isNotEmpty && sdk.NapaxiFileBridge.isInitialized) {
      final bridge = sdk.NapaxiFileBridge.instance;
      addCandidate(
        bridge.sandboxToRealScoped(
          sandboxPath,
          accountId: _activeAccountId,
          agentId: _activeAgentId,
        ),
      );
      addCandidate(bridge.sandboxToReal(sandboxPath));
    }
    if (uri.startsWith('/') && !uri.startsWith('/workspace/')) {
      addCandidate(uri);
    }
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return '';
  }

  bool _a2aTaskBelongsToLocalOutbound(sdk.A2ATaskRecord? taskRecord) {
    return (taskRecord?.source.trim().toLowerCase() ?? '') ==
        'local_transport_outbound';
  }

  String _a2aVisibleConversationSessionId(
    sdk.A2APeerMessage message,
    sdk.A2ADeliveryRecord? delivery, {
    sdk.A2ALocalPeerAdvertisement? peer,
    sdk.A2ATaskRecord? taskRecord,
  }) {
    final collaboration = _a2aCollaborationForVisibleMessage(
      message,
      taskRecord,
    );
    final collaborationId = collaboration['sessionId']?.toString().trim() ?? '';
    if (collaborationId.isNotEmpty) {
      return _a2aVisibleConversationSessionIdForCollaboration(collaborationId);
    }

    final deliverySessionId = delivery?.sessionId.trim() ?? '';
    if (deliverySessionId.isNotEmpty) return deliverySessionId;
    return message.sessionId;
  }

  void _appendA2AInboundChatMessage(
    NapaxiChatClient client,
    sdk.A2APeerMessage message,
    sdk.A2ADeliveryRecord delivery, {
    sdk.A2ALocalPeerAdvertisement? peer,
    sdk.A2ATaskRecord? taskRecord,
    List<ChatAttachment> attachments = const [],
  }) {
    final label = peer == null ? '附近 Agent' : _a2aPeerLabel(peer);
    final text =
        _a2aMessageTextFromRecord(taskRecord) ?? _a2aMessageText(message);
    final taskTitle =
        _a2aTaskTitleFromRecord(taskRecord) ?? _a2aTaskTitle(message);
    final conversation = _a2aCollaborationContext(message);
    final content = switch (message.kind) {
      'task_request' when conversation != null => taskTitle,
      'task_request' => taskTitle,
      'task_progress' => '',
      'task_result' when _a2aResultStatus(message) == 'failed' =>
        '回复失败：\n\n$text',
      'task_result' => text,
      _ => text,
    };
    if (content.trim().isEmpty && attachments.isEmpty) return;
    final role = message.kind == 'task_request'
        ? ChatRole.user
        : ChatRole.assistant;
    final visibleSessionId = _a2aVisibleConversationSessionId(
      message,
      delivery,
      peer: peer,
      taskRecord: taskRecord,
    );
    _appendA2AConversationMessage(
      content,
      sessionId: visibleSessionId,
      peerLabel: label,
      messageId: _a2aVisibleConversationMessageId(
        message,
        delivery,
        taskRecord: taskRecord,
      ),
      createdAt: DateTime.tryParse(message.createdAt),
      role: role,
      attachments: attachments,
    );
    _scheduleA2AAttachmentRefreshIfNeeded(
      client,
      message,
      delivery,
      peer: peer,
      taskRecord: taskRecord,
      currentAttachments: attachments,
    );
  }

  void _scheduleA2AAttachmentRefreshIfNeeded(
    NapaxiChatClient client,
    sdk.A2APeerMessage message,
    sdk.A2ADeliveryRecord delivery, {
    sdk.A2ALocalPeerAdvertisement? peer,
    sdk.A2ATaskRecord? taskRecord,
    List<ChatAttachment> currentAttachments = const [],
  }) {
    if (currentAttachments.isNotEmpty) return;
    final artifacts = _a2aArtifactsForVisibleMessage(message, taskRecord);
    if (!_a2aHasPendingBlobArtifacts(artifacts)) return;
    final sessionId = _a2aVisibleConversationSessionId(
      message,
      delivery,
      peer: peer,
      taskRecord: taskRecord,
    );
    final messageId = _a2aVisibleConversationMessageId(
      message,
      delivery,
      taskRecord: taskRecord,
    );
    if (sessionId.trim().isEmpty || messageId.trim().isEmpty) return;
    debugPrint(
      '[napaxiToolTrace] local A2A attachment refresh scheduled session=$sessionId message=$messageId artifacts=${artifacts.length}',
    );
    unawaited(
      _refreshA2AConversationAttachments(
        client,
        sessionId: sessionId,
        messageId: messageId,
        artifacts: artifacts,
      ),
    );
  }

  bool _a2aHasPendingBlobArtifacts(List<sdk.A2AArtifact> artifacts) {
    return artifacts.any((artifact) {
      final uri = artifact.uri?.trim() ?? '';
      if (uri.startsWith('a2a-blob://')) return true;
      final metadata = artifact.metadata;
      final manifestId = _a2aStringField(metadata, const [
        'manifest_id',
        'manifestId',
      ]);
      final transport = metadata['transport']?.toString().trim() ?? '';
      return manifestId != null &&
          manifestId.isNotEmpty &&
          transport == 'local_blob';
    });
  }

  Future<void> _refreshA2AConversationAttachments(
    NapaxiChatClient client, {
    required String sessionId,
    required String messageId,
    required List<sdk.A2AArtifact> artifacts,
  }) async {
    const delays = [
      Duration(milliseconds: 300),
      Duration(milliseconds: 900),
      Duration(milliseconds: 1800),
      Duration(milliseconds: 3200),
      Duration(milliseconds: 5200),
      Duration(milliseconds: 8000),
    ];
    for (final delay in delays) {
      await Future<void>.delayed(delay);
      if (!mounted) return;
      final resolved = await client.resolveLocalA2AArtifacts(artifacts);
      final attachments = _a2aChatAttachmentsFromArtifacts(resolved);
      if (attachments.isEmpty) continue;
      debugPrint(
        '[napaxiToolTrace] local A2A attachment refresh resolved session=$sessionId message=$messageId attachments=${attachments.length}',
      );
      _updateA2AConversationMessageAttachments(
        sessionId: sessionId,
        messageId: messageId,
        attachments: attachments,
      );
      return;
    }
    debugPrint(
      '[napaxiToolTrace] local A2A attachment refresh unresolved session=$sessionId message=$messageId artifacts=${artifacts.length}',
    );
  }

  String _a2aVisibleConversationMessageId(
    sdk.A2APeerMessage message,
    sdk.A2ADeliveryRecord delivery, {
    sdk.A2ATaskRecord? taskRecord,
  }) {
    final taskId = taskRecord?.taskId.trim().isNotEmpty == true
        ? taskRecord!.taskId.trim()
        : delivery.taskId?.trim().isNotEmpty == true
        ? delivery.taskId!.trim()
        : _a2aTaskIdFromMessage(message);
    if (message.kind == 'task_result' && taskId != null && taskId.isNotEmpty) {
      final localOutbound =
          taskRecord == null || _a2aTaskBelongsToLocalOutbound(taskRecord);
      return localOutbound ? '$taskId-remote-reply' : '$taskId-local-reply';
    }
    if (message.kind == 'task_request' && taskId != null && taskId.isNotEmpty) {
      final peerMessageId = message.messageId.trim();
      if (peerMessageId.isNotEmpty) return peerMessageId;
      return _a2aVisibleMessageId('ledger-request-$taskId');
    }
    final messageId = message.messageId.trim();
    if (messageId.isNotEmpty) return messageId;
    return taskId == null || taskId.isEmpty
        ? 'message-${DateTime.now().microsecondsSinceEpoch}'
        : '$taskId-${message.kind}';
  }

  String? _a2aTaskIdFromMessage(sdk.A2APeerMessage message) {
    for (final key in const ['task', 'progress', 'result']) {
      final payload = message.payload[key];
      if (payload is! Map) continue;
      final taskId =
          payload['taskId']?.toString().trim() ??
          payload['task_id']?.toString().trim();
      if (taskId != null && taskId.isNotEmpty) return taskId;
    }
    return null;
  }

  Future<sdk.A2ATaskRecord?> _a2aTaskRecordForPeerMessage(
    NapaxiChatClient client,
    String messageId,
  ) async {
    final target = messageId.trim();
    if (target.isEmpty) return null;
    for (final task in await client.listLocalA2ATasks(limit: 100)) {
      if (task.peerMessageId == target || task.envelopeId == target) {
        return task;
      }
    }
    return null;
  }

  bool _shouldAutoRunA2ACollaboration(
    sdk.A2ATaskRecord? task,
    sdk.A2ADeliveryRecord delivery,
  ) {
    if (task == null) return false;
    if (delivery.status != 'delivered') return false;
    final collaboration = task.request.context['a2aCollaboration'];
    if (collaboration == null) return false;
    final autoAccept = collaboration['autoAcceptLowRisk'] == true;
    final risk = collaboration['risk']?.toString().trim().toLowerCase() ?? '';
    final sessionId = collaboration['sessionId']?.toString().trim() ?? '';
    return autoAccept && risk == 'low' && sessionId.isNotEmpty;
  }

  Map<String, dynamic>? _a2aCollaborationContext(sdk.A2APeerMessage message) {
    final task = message.payload['task'];
    if (task is! Map) return null;
    final context = task['context'];
    if (context is! Map) return null;
    final collaboration = context['a2aCollaboration'];
    if (collaboration is! Map) return null;
    return Map<String, dynamic>.from(collaboration);
  }

  Future<void> _autoRunA2ACollaborationTask(
    NapaxiChatClient client, {
    required sdk.A2ALocalPeerAdvertisement peer,
    required String taskId,
    required sdk.A2APeerMessage message,
    required sdk.A2ATaskRecord? taskRecord,
  }) async {
    final collaboration = taskRecord?.request.context['a2aCollaboration'];
    final sessionId = collaboration?['sessionId']?.toString().trim() ?? '';
    if (sessionId.isEmpty) return;
    if (!client.claimLocalA2AAutoRunTask(taskId)) {
      unawaited(
        _projectClaimedA2AAutoRunTask(
          client,
          peer: peer,
          taskId: taskId,
          message: message,
          taskRecord: taskRecord,
        ),
      );
      return;
    }
    var handled = false;
    var conversationSessionId = sessionId;
    try {
      final status = await _ensureA2ALocalTransportStarted(client);
      if (status == null || !status.supported || !status.running) {
        _showChatSnackBar('附近消息暂时无法处理：本地连接不可用。');
        return;
      }
      final sharedSecret = await _a2aSharedSecretForPeer(peer, status: status);
      if (sharedSecret == null) {
        _showChatSnackBar('附近消息暂时无法处理：设备信任信息不完整。');
        return;
      }
      await client.openLocalA2ASession(peer, sharedSecret: sharedSecret);
      final record = await client.getLocalA2ATask(taskId);
      if (record == null) {
        _showChatSnackBar('附近消息暂时无法处理：消息记录不完整。');
        return;
      }
      conversationSessionId = _a2aVisibleConversationSessionId(
        message,
        null,
        peer: peer,
        taskRecord: record,
      );
      _appendA2AConversationPendingReply(
        sessionId: conversationSessionId,
        peerLabel: _a2aPeerLabel(peer),
        taskId: taskId,
      );

      try {
        final progress = await client.createLocalA2AProgressMessage(
          message.sessionId,
          taskId,
          '已收到，正在回复。',
          status: 'running',
        );
        await _sendA2AMessageToPeerOrThrow(
          client,
          progress,
          peer,
          purpose: '回传协作进度',
        );
      } catch (_) {
        // Progress is helpful evidence, but failure to send it should not stop
        // the actual collaboration run.
      }

      await client.submitLocalA2AChannelTask(task: record, peer: peer);
      final run = await client.runLocalA2AChannelTask(
        taskId: taskId,
        agentId: _activeAgentId,
      );
      if (!mounted) return;
      final completed = await client.getLocalA2ATask(taskId);
      final summary = run.summary.trim().isNotEmpty
          ? run.summary.trim()
          : completed?.summary?.trim() ?? '';
      final error = (run.error ?? '').trim();
      if (run.delivered) {
        handled = true;
        _appendA2AConversationMessage(
          summary.isEmpty ? '我暂时还没有想好怎么回复。' : summary,
          sessionId: conversationSessionId,
          peerLabel: _a2aPeerLabel(peer),
          messageId: '$taskId-local-reply',
          role: ChatRole.assistant,
        );
        return;
      }
      _appendA2AConversationMessage(
        '我刚才的回复没有送达。',
        sessionId: conversationSessionId,
        peerLabel: _a2aPeerLabel(peer),
        messageId: '$taskId-local-reply',
        role: ChatRole.assistant,
      );
      debugPrint(
        '[napaxiToolTrace] local A2A auto response not delivered task=$taskId summary=${summary.isNotEmpty} error=$error',
      );
    } catch (error) {
      try {
        final failure = await client.createLocalA2AResultMessage(
          message.sessionId,
          taskId,
          '我暂时没能完成回复。',
          status: 'failed',
        );
        await _sendA2AMessageToPeerOrThrow(
          client,
          failure,
          peer,
          purpose: '回传协作失败结果',
        );
        handled = true;
      } catch (_) {}
      if (!mounted) return;
      _appendA2AConversationMessage(
        '我暂时没能完成回复。',
        sessionId: conversationSessionId,
        peerLabel: _a2aPeerLabel(peer),
        messageId: '$taskId-local-reply',
        role: ChatRole.assistant,
      );
      _showChatSnackBar('附近消息处理失败。');
    } finally {
      client.releaseLocalA2AAutoRunTask(taskId, handled: handled);
    }
  }

  Future<void> _projectClaimedA2AAutoRunTask(
    NapaxiChatClient client, {
    required sdk.A2ALocalPeerAdvertisement peer,
    required String taskId,
    required sdk.A2APeerMessage message,
    required sdk.A2ATaskRecord? taskRecord,
  }) async {
    var record = taskRecord ?? await client.getLocalA2ATask(taskId);
    var conversationSessionId = _a2aVisibleConversationSessionId(
      message,
      null,
      peer: peer,
      taskRecord: record,
    );
    _appendA2AConversationPendingReply(
      sessionId: conversationSessionId,
      peerLabel: _a2aPeerLabel(peer),
      taskId: taskId,
    );

    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (mounted && DateTime.now().isBefore(deadline)) {
      record = await client.getLocalA2ATask(taskId);
      if (record != null) {
        conversationSessionId = _a2aVisibleConversationSessionId(
          message,
          null,
          peer: peer,
          taskRecord: record,
        );
        if (_a2aTaskHasUserVisibleResult(record)) break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    if (!mounted) return;
    final completedRecord = record;
    if (completedRecord == null ||
        !_a2aTaskHasUserVisibleResult(completedRecord)) {
      _removeA2AConversationPendingReply(
        sessionId: conversationSessionId,
        taskId: taskId,
      );
      return;
    }

    final summary = completedRecord.summary?.trim() ?? '';
    final status = completedRecord.status.trim().toLowerCase();
    final content = summary.isNotEmpty
        ? summary
        : status == 'failed' || status == 'rejected' || status == 'cancelled'
        ? '我暂时没能完成回复。'
        : '我暂时还没有想好怎么回复。';
    _appendA2AConversationMessage(
      content,
      sessionId: conversationSessionId,
      peerLabel: _a2aPeerLabel(peer),
      messageId: '$taskId-local-reply',
      role: ChatRole.assistant,
    );
  }

  void _removeA2AConversationPendingReply({
    required String sessionId,
    required String taskId,
  }) {
    final targetSessionId = sessionId.trim();
    final stableMessageId = _a2aVisibleLocalReplyMessageId(taskId.trim());
    if (targetSessionId.isEmpty || stableMessageId.isEmpty) return;
    var didRemove = false;
    setState(() {
      _sessions = _sessions
          .map((session) {
            if (session.id != targetSessionId) return session;
            final messages = session.messages
                .where((message) {
                  final remove =
                      message.id == stableMessageId &&
                      message.isStreaming &&
                      message.content.trim().isEmpty;
                  if (remove) didRemove = true;
                  return !remove;
                })
                .toList(growable: false);
            if (!didRemove) return session;
            return session.copyWith(messages: List.unmodifiable(messages));
          })
          .toList(growable: false);
    });
  }

  Future<void> _sendA2ATaskReceipt(
    NapaxiChatClient client,
    sdk.A2ALocalPeerAdvertisement peer,
    String sessionId,
    String taskId,
  ) async {
    try {
      final receipt = await client.createLocalA2AProgressMessage(
        sessionId,
        taskId,
        '已收到。',
        status: 'accepted',
      );
      await _sendA2AMessageToPeerOrThrow(
        client,
        receipt,
        peer,
        purpose: '回传任务接收回执',
      );
    } catch (error) {
      debugPrint('[napaxiToolTrace] local A2A receipt send failed: $error');
    }
  }

  String _a2aVisibleMessageId(String rawMessageId) {
    final normalized = rawMessageId.trim();
    if (normalized.isEmpty) return '';
    return normalized.startsWith('a2a-') ? normalized : 'a2a-$normalized';
  }

  String _a2aVisibleLocalReplyMessageId(String taskId) {
    final normalized = taskId.trim();
    if (normalized.isEmpty) return '';
    return _a2aVisibleMessageId('$normalized-local-reply');
  }

  void _appendA2AConversationMessage(
    String content, {
    String? sessionId,
    String? peerLabel,
    String? messageId,
    DateTime? createdAt,
    ChatRole role = ChatRole.user,
    List<ChatAttachment> attachments = const [],
  }) {
    final targetSessionId = sessionId?.trim() ?? '';
    if (targetSessionId.isEmpty) {
      _appendA2ANoticeMessage(_sanitizeA2AProtocolText(content));
      return;
    }
    final sanitizedContent = _sanitizeA2AProtocolText(content);
    if (sanitizedContent.trim().isEmpty && attachments.isEmpty) return;
    final now = createdAt?.toLocal() ?? DateTime.now();
    final label = (peerLabel ?? '').trim();
    final title = label.isEmpty ? '附近 Agent 对话' : '和 $label 的对话';
    final rawMessageId = (messageId ?? '').trim();
    final stableMessageId = rawMessageId.isEmpty
        ? 'a2a-${_nextMessageId++}'
        : _a2aVisibleMessageId(rawMessageId);
    final wasActiveSession = _activeSessionId == targetSessionId;
    var didInsert = false;
    setState(() {
      final existingIndex = _sessions.indexWhere(
        (session) => session.id == targetSessionId,
      );
      final existing = existingIndex == -1 ? null : _sessions[existingIndex];
      final messages = [
        for (final message in existing?.messages ?? const <ChatMessage>[])
          if (message.id != 'welcome') message,
      ];
      final duplicate = messages.any(
        (message) => message.id == stableMessageId,
      );
      if (!duplicate) {
        didInsert = true;
        messages.add(
          ChatMessage(
            id: stableMessageId,
            role: role,
            content: sanitizedContent,
            createdAt: now,
            completedAt: now,
            attachments: List.unmodifiable(attachments),
          ),
        );
      } else {
        final existingMessageIndex = messages.indexWhere(
          (message) => message.id == stableMessageId,
        );
        final existingMessage = messages[existingMessageIndex];
        final mergedAttachments = _mergeA2AChatAttachments(
          existingMessage.attachments,
          attachments,
        );
        final hasNewAttachments =
            mergedAttachments.length != existingMessage.attachments.length;
        if (existingMessage.isStreaming ||
            existingMessage.content.trim().isEmpty ||
            hasNewAttachments) {
          didInsert = true;
          messages[existingMessageIndex] = existingMessage.copyWith(
            role: role,
            content: sanitizedContent.trim().isEmpty
                ? existingMessage.content
                : sanitizedContent,
            isStreaming: false,
            completedAt: now,
            attachments: List.unmodifiable(mergedAttachments),
          );
        }
      }
      final updatedSession = ChatSession(
        id: targetSessionId,
        title:
            existing != null &&
                existing.title.trim().isNotEmpty &&
                !_isWeakA2AConversationTitle(existing.title)
            ? existing.title
            : title,
        isPinned: existing?.isPinned ?? false,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        messages: List.unmodifiable(messages),
      );
      _sessions = List.unmodifiable([
        updatedSession,
        for (final session in _sessions)
          if (session.id != targetSessionId) session,
      ]);
      _nextMessageId = _nextMessageNumber(_sessions);
    });
    if (wasActiveSession) {
      _scrollToBottom(force: true);
    } else if (didInsert) {
      _showA2AConversationUpdatedNotice(targetSessionId, title: title);
    }
    unawaited(_forgetDeletedA2AConversationSession(targetSessionId));
    unawaited(_persistA2AConversationSessions());
  }

  void _updateA2AConversationMessageAttachments({
    required String sessionId,
    required String messageId,
    required List<ChatAttachment> attachments,
  }) {
    final targetSessionId = sessionId.trim();
    final stableMessageId = _a2aVisibleMessageId(messageId.trim());
    if (targetSessionId.isEmpty ||
        stableMessageId.isEmpty ||
        attachments.isEmpty) {
      return;
    }
    var didUpdate = false;
    setState(() {
      final sessionIndex = _sessions.indexWhere(
        (session) => session.id == targetSessionId,
      );
      if (sessionIndex == -1) return;
      final session = _sessions[sessionIndex];
      final messages = session.messages.toList(growable: true);
      final messageIndex = messages.indexWhere(
        (message) => message.id == stableMessageId,
      );
      if (messageIndex == -1) return;
      final message = messages[messageIndex];
      final merged = _mergeA2AChatAttachments(message.attachments, attachments);
      if (merged.length == message.attachments.length) return;
      didUpdate = true;
      messages[messageIndex] = message.copyWith(
        attachments: List.unmodifiable(merged),
        completedAt: message.completedAt ?? DateTime.now(),
      );
      final updatedSession = session.copyWith(
        updatedAt: DateTime.now(),
        messages: List.unmodifiable(messages),
      );
      _sessions = List.unmodifiable([
        updatedSession,
        for (final existing in _sessions)
          if (existing.id != targetSessionId) existing,
      ]);
    });
    if (!didUpdate) return;
    if (_activeSessionId == targetSessionId) {
      _scrollToBottom(force: true);
    }
    unawaited(_persistA2AConversationSessions());
  }

  List<ChatAttachment> _mergeA2AChatAttachments(
    List<ChatAttachment> existing,
    List<ChatAttachment> incoming,
  ) {
    if (incoming.isEmpty) return existing;
    final merged = existing.toList(growable: true);
    final seen = {
      for (final attachment in merged) _a2aChatAttachmentIdentity(attachment),
    };
    for (final attachment in incoming) {
      if (seen.add(_a2aChatAttachmentIdentity(attachment))) {
        merged.add(attachment);
      }
    }
    return List.unmodifiable(merged);
  }

  String _a2aChatAttachmentIdentity(ChatAttachment attachment) {
    final sandbox = attachment.sandboxPath?.trim() ?? '';
    if (sandbox.isNotEmpty) return 'sandbox:$sandbox';
    final path = attachment.path.trim();
    if (path.isNotEmpty) return 'path:$path';
    return 'name:${attachment.name}';
  }

  void _appendA2AConversationPendingReply({
    required String sessionId,
    required String peerLabel,
    required String taskId,
  }) {
    final targetSessionId = sessionId.trim();
    final normalizedTaskId = taskId.trim();
    if (targetSessionId.isEmpty || normalizedTaskId.isEmpty) return;
    final now = DateTime.now();
    final label = peerLabel.trim();
    final title = label.isEmpty ? '附近 Agent 对话' : '和 $label 的对话';
    final stableMessageId = _a2aVisibleLocalReplyMessageId(normalizedTaskId);
    final wasActiveSession = _activeSessionId == targetSessionId;
    var didInsert = false;
    setState(() {
      final existingIndex = _sessions.indexWhere(
        (session) => session.id == targetSessionId,
      );
      final existing = existingIndex == -1 ? null : _sessions[existingIndex];
      final messages = [
        for (final message in existing?.messages ?? const <ChatMessage>[])
          if (message.id != 'welcome') message,
      ];
      if (!messages.any((message) => message.id == stableMessageId)) {
        didInsert = true;
        messages.add(
          ChatMessage(
            id: stableMessageId,
            role: ChatRole.assistant,
            content: '',
            createdAt: now,
            isStreaming: true,
          ),
        );
      }
      final updatedSession = ChatSession(
        id: targetSessionId,
        title:
            existing != null &&
                existing.title.trim().isNotEmpty &&
                !_isWeakA2AConversationTitle(existing.title)
            ? existing.title
            : title,
        isPinned: existing?.isPinned ?? false,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        messages: List.unmodifiable(messages),
      );
      _sessions = List.unmodifiable([
        updatedSession,
        for (final session in _sessions)
          if (session.id != targetSessionId) session,
      ]);
      _nextMessageId = _nextMessageNumber(_sessions);
    });
    if (wasActiveSession) {
      _scrollToBottom(force: true);
    } else if (didInsert) {
      _showA2AConversationUpdatedNotice(targetSessionId, title: title);
    }
    unawaited(_forgetDeletedA2AConversationSession(targetSessionId));
  }

  bool _isA2AConversationMessage(ChatMessage message) {
    return message.id.startsWith('a2a-') &&
        !message.isStreaming &&
        (message.content.trim().isNotEmpty || message.attachments.isNotEmpty);
  }

  Map<String, Object?> _a2aConversationMessageToMap(ChatMessage message) => {
    'id': message.id,
    'role': message.role.name,
    'content': message.content,
    'created_at': message.createdAt.toIso8601String(),
    if (message.completedAt != null)
      'completed_at': message.completedAt!.toIso8601String(),
    if (message.attachments.isNotEmpty)
      'attachments': message.attachments
          .map(_a2aChatAttachmentToMap)
          .toList(growable: false),
  };

  Map<String, Object?> _a2aChatAttachmentToMap(ChatAttachment attachment) => {
    'name': attachment.name,
    'path': attachment.path,
    'type': attachment.type.name,
    if (attachment.sandboxPath?.trim().isNotEmpty == true)
      'sandbox_path': attachment.sandboxPath,
    if (attachment.mimeTypeOverride?.trim().isNotEmpty == true)
      'mime_type': attachment.mimeTypeOverride,
  };

  ChatAttachment? _a2aChatAttachmentFromMap(Map<dynamic, dynamic> map) {
    final name = map['name']?.toString().trim() ?? '';
    final path = map['path']?.toString().trim() ?? '';
    final sandboxPath = map['sandbox_path']?.toString().trim();
    final mimeType = map['mime_type']?.toString().trim();
    if (name.isEmpty || path.isEmpty) return null;
    return ChatAttachment(
      name: name,
      path: path,
      type:
          map['type']?.toString().trim().toLowerCase() ==
                  ChatAttachmentType.image.name ||
              (mimeType ?? '').toLowerCase().startsWith('image/')
          ? ChatAttachmentType.image
          : ChatAttachmentType.file,
      sandboxPath: sandboxPath?.isEmpty == true ? null : sandboxPath,
      mimeTypeOverride: mimeType?.isEmpty == true ? null : mimeType,
    );
  }

  ChatMessage? _a2aConversationMessageFromMap(Map<dynamic, dynamic> map) {
    final id = map['id']?.toString().trim() ?? '';
    final content = _sanitizeA2AProtocolText(map['content']?.toString() ?? '');
    final rawAttachments = map['attachments'];
    final attachments = rawAttachments is List
        ? rawAttachments
              .whereType<Map>()
              .map(_a2aChatAttachmentFromMap)
              .whereType<ChatAttachment>()
              .toList(growable: false)
        : const <ChatAttachment>[];
    if (id.isEmpty || (content.trim().isEmpty && attachments.isEmpty)) {
      return null;
    }
    final roleName = map['role']?.toString().trim().toLowerCase() ?? '';
    final role = roleName == ChatRole.user.name
        ? ChatRole.user
        : ChatRole.assistant;
    final createdAt =
        DateTime.tryParse(map['created_at']?.toString() ?? '') ??
        DateTime.now();
    final completedAt = DateTime.tryParse(
      map['completed_at']?.toString() ?? '',
    );
    return ChatMessage(
      id: id,
      role: role,
      content: content,
      createdAt: createdAt,
      completedAt: completedAt ?? createdAt,
      attachments: List.unmodifiable(attachments),
    );
  }

  Map<String, Object?> _a2aConversationSessionToMap(ChatSession session) {
    final messages = session.messages
        .where(_isA2AConversationMessage)
        .map(_a2aConversationMessageToMap)
        .toList(growable: false);
    return {
      'account_id': _activeAccountId,
      'agent_id': _activeAgentId,
      'id': session.id,
      'title': session.title,
      'created_at': session.createdAt.toIso8601String(),
      'updated_at': session.updatedAt.toIso8601String(),
      'messages': messages,
    };
  }

  ChatSession? _a2aConversationSessionFromMap(Map<dynamic, dynamic> map) {
    if ((map['account_id']?.toString() ?? '') != _activeAccountId) {
      return null;
    }
    if ((map['agent_id']?.toString() ?? '') != _activeAgentId) {
      return null;
    }
    final id = map['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    final canonicalId = _canonicalA2AConversationSessionId(id);
    final rawMessages = map['messages'];
    if (rawMessages is! List) return null;
    final messages = rawMessages
        .whereType<Map>()
        .map(_a2aConversationMessageFromMap)
        .whereType<ChatMessage>()
        .toList(growable: false);
    if (messages.isEmpty) return null;
    final createdAt =
        DateTime.tryParse(map['created_at']?.toString() ?? '') ??
        messages.first.createdAt;
    final updatedAt =
        DateTime.tryParse(map['updated_at']?.toString() ?? '') ??
        messages.last.createdAt;
    return ChatSession(
      id: canonicalId,
      title: _sanitizeA2AProtocolText(map['title']?.toString() ?? ''),
      createdAt: createdAt,
      updatedAt: updatedAt,
      messages: List.unmodifiable(messages),
    );
  }

  List<ChatMessage> _mergeA2AConversationMessages(
    List<ChatMessage> existing,
    List<ChatMessage> overlay,
  ) {
    final seenIds = <String>{};
    final seenSemanticKeys = <String>{};
    final welcome = <ChatMessage>[];
    final merged = <ChatMessage>[];
    void add(ChatMessage message) {
      if (message.id == 'welcome') {
        if (welcome.isEmpty) welcome.add(message);
        return;
      }
      final existingIdIndex = merged.indexWhere(
        (item) => item.id == message.id,
      );
      if (existingIdIndex != -1) {
        if (message.attachments.isNotEmpty &&
            merged[existingIdIndex].attachments.isEmpty) {
          merged[existingIdIndex] = merged[existingIdIndex].copyWith(
            attachments: message.attachments,
          );
        }
        return;
      }
      seenIds.add(message.id);
      final semanticKey = _a2aConversationSemanticKey(message);
      if (semanticKey != null) {
        final existingSemanticIndex = merged.indexWhere(
          (item) => _a2aConversationSemanticKey(item) == semanticKey,
        );
        if (existingSemanticIndex != -1) {
          if (message.attachments.isNotEmpty &&
              merged[existingSemanticIndex].attachments.isEmpty) {
            merged[existingSemanticIndex] = merged[existingSemanticIndex]
                .copyWith(attachments: message.attachments);
          }
          return;
        }
        seenSemanticKeys.add(semanticKey);
      }
      merged.add(message);
    }

    for (final message in existing) {
      add(message);
    }
    for (final message in overlay) {
      add(message);
    }
    merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable([...welcome, ...merged]);
  }

  String? _a2aConversationSemanticKey(ChatMessage message) {
    if (!message.id.startsWith('a2a-')) return null;
    final content = _sanitizeA2AProtocolText(message.content).trim();
    if (content.isEmpty) return null;
    final bucket =
        message.createdAt.millisecondsSinceEpoch ~/
        const Duration(seconds: 2).inMilliseconds;
    return '${message.role.name}|$bucket|$content';
  }

  ChatSession _mergeA2AConversationOverlayIntoSession(
    ChatSession session,
    ChatSession overlay,
  ) {
    final messages = _mergeA2AConversationMessages(
      session.messages,
      overlay.messages,
    );
    final updatedAt = session.updatedAt.isAfter(overlay.updatedAt)
        ? session.updatedAt
        : overlay.updatedAt;
    final overlayTitle = overlay.title.trim();
    final sessionTitle = session.title.trim();
    return session.copyWith(
      title: !_isWeakA2AConversationTitle(sessionTitle) || overlayTitle.isEmpty
          ? session.title
          : overlay.title,
      updatedAt: updatedAt,
      messages: messages,
    );
  }

  bool _isWeakA2AConversationTitle(String title) {
    final normalized = title.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return normalized.contains('napaxi:') ||
        normalized.contains('nearby-agent') ||
        normalized.contains('session') ||
        normalized.contains('task') ||
        RegExp(r'\bandroid-[a-z0-9_.:-]{6,}\b').hasMatch(normalized) ||
        RegExp(r'\bios-[a-z0-9_.:-]{6,}\b').hasMatch(normalized);
  }

  bool _isCanonicalA2AConversationSessionId(String sessionId) {
    final normalized = sessionId.trim();
    const prefix = '$_a2aConversationSessionPrefix:';
    if (!normalized.startsWith(prefix)) return false;
    final tail = normalized.substring(prefix.length).trim();
    return tail.isNotEmpty && !tail.contains(':');
  }

  String _canonicalA2AConversationSessionId(String sessionId) {
    final normalized = sessionId.trim();
    if (_isCanonicalA2AConversationSessionId(normalized)) return normalized;
    const prefix = '$_a2aConversationSessionPrefix:';
    if (!normalized.startsWith(prefix)) return normalized;
    final tail = normalized.substring(prefix.length);
    for (final part in tail.split(':').reversed) {
      final candidate = part.trim();
      if (candidate.startsWith('a2a-collab-')) {
        return _a2aVisibleConversationSessionIdForCollaboration(candidate);
      }
    }
    return normalized;
  }

  List<ChatSession> _dropRecoverableLegacyA2AConversationSessions(
    List<ChatSession> overlays,
    List<ChatSession> ledgerOverlays,
  ) {
    if (ledgerOverlays.isEmpty) return overlays;
    return overlays
        .where(
          (session) =>
              _isCanonicalA2AConversationSessionId(session.id) ||
              !session.messages.any(_isA2AConversationMessage),
        )
        .toList(growable: false);
  }

  List<ChatSession> _mergeA2AConversationSessions(
    List<ChatSession> base,
    List<ChatSession> overlays,
  ) {
    if (overlays.isEmpty) return base;
    final sessions = [...base];
    for (final overlay in overlays) {
      final index = sessions.indexWhere((session) => session.id == overlay.id);
      if (index == -1) {
        sessions.add(overlay);
      } else {
        sessions[index] = _mergeA2AConversationOverlayIntoSession(
          sessions[index],
          overlay,
        );
      }
    }
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(sessions);
  }

  ChatSession? _a2aConversationOverlayForSession(
    List<ChatSession> overlays,
    String sessionId,
  ) {
    for (final overlay in overlays) {
      if (overlay.id == sessionId) return overlay;
    }
    return null;
  }

  String _a2aPeerIdFromCollaboration(
    Map<dynamic, dynamic> collaboration, {
    required bool localOutbound,
    required sdk.A2ATaskRecord task,
  }) {
    final keys = localOutbound
        ? const ['toPeerId', 'to_peer_id']
        : const ['fromPeerId', 'from_peer_id'];
    final fromCollaboration = _a2aStringField(collaboration, keys);
    if (fromCollaboration != null) return fromCollaboration;
    final senderPeerId = task.sender.peerId.trim();
    if (senderPeerId.isNotEmpty) return senderPeerId;
    return 'nearby-agent';
  }

  String _a2aDisplayLabelForPeerId(
    Map<dynamic, dynamic> collaboration,
    String peerId,
  ) {
    final participants = collaboration['participants'];
    if (participants is List) {
      for (final participant in participants) {
        if (participant is! Map) continue;
        if (participant['peerId']?.toString().trim() != peerId) continue;
        final displayLabel = participant['displayLabel']?.toString().trim();
        if (displayLabel != null &&
            displayLabel.isNotEmpty &&
            !_isGenericA2APeerLabel(displayLabel)) {
          return displayLabel;
        }
        final displayName = participant['displayName']?.toString().trim();
        if (displayName != null &&
            displayName.isNotEmpty &&
            !_isGenericA2APeerLabel(displayName)) {
          return displayName;
        }
      }
    }
    final normalized = peerId.trim().toLowerCase();
    if (normalized.startsWith('ios-')) return 'iOS Agent';
    if (normalized.startsWith('android-')) return 'Android Agent';
    return '附近 Agent';
  }

  String? _a2aVisibleConversationSessionIdFromToolResult(
    Map<String, dynamic> decoded,
    Map<dynamic, dynamic> item,
  ) {
    final collaboration = decoded['collaboration'];
    if (collaboration is! Map) return null;
    final collaborationId = collaboration['sessionId']?.toString().trim() ?? '';
    if (collaborationId.isEmpty) return null;
    return _a2aVisibleConversationSessionIdForCollaboration(collaborationId);
  }

  String _a2aVisibleConversationTitleFromToolResult(
    Map<String, dynamic> decoded,
    Map<dynamic, dynamic> item,
  ) {
    final collaboration = decoded['collaboration'];
    final displayText = collaboration is Map
        ? collaboration['displayText']?.toString().trim()
        : null;
    if (displayText != null && displayText.isNotEmpty) return displayText;
    final label =
        _a2aStringField(item, const [
          'toDisplayLabel',
          'displayLabel',
          'fromDisplayLabel',
        ]) ??
        '';
    if (label.isEmpty || _isGenericA2APeerLabel(label)) {
      return '附近 Agent 对话';
    }
    return '和 $label 的对话';
  }

  String _a2aConversationSessionIdFromTask(
    sdk.A2ATaskRecord task,
    Map<dynamic, dynamic> collaboration, {
    required bool localOutbound,
  }) {
    final conversationTurn = task.request.context['conversationTurn'];
    final conversationTurnId = conversationTurn is Map
        ? _a2aStringField(conversationTurn, const [
            'conversationId',
            'conversation_id',
          ])
        : null;
    final collaborationId =
        conversationTurnId ??
        collaboration['sessionId']?.toString().trim() ??
        '';
    final peerId = _a2aPeerIdFromCollaboration(
      collaboration,
      localOutbound: localOutbound,
      task: task,
    );
    final safeCollaborationId = collaborationId.isEmpty
        ? task.sessionId?.trim().isNotEmpty == true
              ? task.sessionId!.trim()
              : task.taskId
        : collaborationId;
    if (collaborationId.isNotEmpty) {
      return _a2aVisibleConversationSessionIdForCollaboration(
        safeCollaborationId,
      );
    }
    return '$_a2aConversationSessionPrefix:$peerId:$safeCollaborationId';
  }

  DateTime _a2aTaskDate(String value, DateTime fallback) {
    return DateTime.tryParse(value)?.toLocal() ?? fallback;
  }

  ChatMessage? _a2aTaskLedgerMessage({
    required String id,
    required ChatRole role,
    required String label,
    required String text,
    required DateTime createdAt,
    List<ChatAttachment> attachments = const [],
  }) {
    final sanitized = _sanitizeA2AProtocolText(text);
    if (sanitized.trim().isEmpty && attachments.isEmpty) return null;
    return ChatMessage(
      id: id,
      role: role,
      content: sanitized,
      createdAt: createdAt,
      completedAt: createdAt,
      attachments: List.unmodifiable(attachments),
    );
  }

  Future<List<ChatSession>> _loadA2AConversationSessionsFromLedger() async {
    try {
      final client = await _getChatClient();
      final tasks = await client.listLocalA2ATasks(limit: 200);
      final bySessionId = <String, ChatSession>{};
      final now = DateTime.now();

      for (final task in tasks) {
        final collaboration = task.request.context['a2aCollaboration'];
        if (collaboration is! Map) continue;
        final conversationTurn = task.request.context['conversationTurn'];
        final collaborationId = conversationTurn is Map
            ? _a2aStringField(conversationTurn, const [
                    'conversationId',
                    'conversation_id',
                  ]) ??
                  collaboration['sessionId']?.toString().trim() ??
                  ''
            : collaboration['sessionId']?.toString().trim() ?? '';
        if (collaborationId.isEmpty) continue;
        final localOutbound = _a2aTaskBelongsToLocalOutbound(task);
        final sessionId = _a2aConversationSessionIdFromTask(
          task,
          collaboration,
          localOutbound: localOutbound,
        );
        final peerId = _a2aPeerIdFromCollaboration(
          collaboration,
          localOutbound: localOutbound,
          task: task,
        );
        final peerLabel = _a2aDisplayLabelForPeerId(collaboration, peerId);
        final createdAt = _a2aTaskDate(task.createdAt, now);
        final updatedAt = _a2aTaskDate(task.updatedAt, createdAt);
        final requestText =
            collaboration['message']?.toString().trim().isNotEmpty == true
            ? collaboration['message']!.toString().trim()
            : _a2aExtractCollaborationMessage(task.request.message);
        final summary = _a2aTaskHasUserVisibleResult(task)
            ? task.summary?.trim() ?? ''
            : '';
        final requestAttachments = _a2aChatAttachmentsFromArtifacts(
          await client.resolveLocalA2AArtifacts(task.request.artifacts),
        );
        final resultAttachments = _a2aChatAttachmentsFromArtifacts(
          await client.resolveLocalA2AArtifacts(task.resultArtifacts),
        );
        final messages = <ChatMessage>[];

        if (requestText.isNotEmpty || requestAttachments.isNotEmpty) {
          messages.addAll(
            [
              if (localOutbound)
                _a2aTaskLedgerMessage(
                  id: _a2aVisibleMessageId('${task.taskId}-local-sent'),
                  role: ChatRole.user,
                  label: '我',
                  text: requestText,
                  createdAt: createdAt,
                  attachments: requestAttachments,
                )
              else
                _a2aTaskLedgerMessage(
                  id: task.peerMessageId?.trim().isNotEmpty == true
                      ? _a2aVisibleMessageId(task.peerMessageId!.trim())
                      : _a2aVisibleMessageId(
                          'a2a-ledger-request-${task.taskId}',
                        ),
                  role: ChatRole.user,
                  label: peerLabel,
                  text: requestText,
                  createdAt: createdAt,
                  attachments: requestAttachments,
                ),
            ].whereType<ChatMessage>(),
          );
        }
        if (summary.isNotEmpty || resultAttachments.isNotEmpty) {
          messages.addAll(
            [
              if (localOutbound)
                _a2aTaskLedgerMessage(
                  id: _a2aVisibleMessageId('${task.taskId}-remote-reply'),
                  role: ChatRole.assistant,
                  label: peerLabel,
                  text: summary,
                  createdAt: updatedAt,
                  attachments: resultAttachments,
                )
              else
                _a2aTaskLedgerMessage(
                  id: _a2aVisibleLocalReplyMessageId(task.taskId),
                  role: ChatRole.assistant,
                  label: '我',
                  text: summary,
                  createdAt: updatedAt,
                  attachments: resultAttachments,
                ),
            ].whereType<ChatMessage>(),
          );
        }
        if (messages.isEmpty) continue;

        final title =
            peerLabel.trim().isEmpty || _isGenericA2APeerLabel(peerLabel)
            ? '附近 Agent 对话'
            : '和 $peerLabel 的对话';
        final existing = bySessionId[sessionId];
        final overlay = ChatSession(
          id: sessionId,
          title: title,
          createdAt: existing?.createdAt ?? createdAt,
          updatedAt: existing != null && existing.updatedAt.isAfter(updatedAt)
              ? existing.updatedAt
              : updatedAt,
          messages: _mergeA2AConversationMessages(
            existing?.messages ?? const <ChatMessage>[],
            messages,
          ),
        );
        bySessionId[sessionId] = overlay;
      }
      return bySessionId.values.toList(growable: false);
    } catch (error) {
      debugPrint('[napaxiToolTrace] local A2A ledger restore failed: $error');
      return const [];
    }
  }

  Future<List<ChatSession>> _loadA2AConversationSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_a2aConversationSessionsKey);
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(_a2aConversationSessionFromMap)
          .whereType<ChatSession>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<Set<String>> _loadDeletedA2AConversationSessionIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_a2aDeletedConversationSessionsKey) ??
              const <String>[])
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet();
    } catch (_) {
      return const <String>{};
    }
  }

  Future<void> _saveDeletedA2AConversationSessionIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final values = ids.toList()..sort();
    await prefs.setStringList(_a2aDeletedConversationSessionsKey, values);
  }

  Future<void> _markDeletedA2AConversationSession(String sessionId) async {
    final target = sessionId.trim();
    if (target.isEmpty) return;
    final ids = await _loadDeletedA2AConversationSessionIds();
    await _saveDeletedA2AConversationSessionIds({...ids, target});
  }

  Future<void> _forgetDeletedA2AConversationSession(String sessionId) async {
    final target = sessionId.trim();
    if (target.isEmpty) return;
    final ids = await _loadDeletedA2AConversationSessionIds();
    if (!ids.remove(target)) return;
    await _saveDeletedA2AConversationSessionIds(ids);
  }

  Future<void> _restoreA2AConversationSessions() async {
    final overlays = await _loadA2AConversationSessions();
    final ledgerOverlays = await _loadA2AConversationSessionsFromLedger();
    final deletedSessionIds = await _loadDeletedA2AConversationSessionIds();
    final cleanedOverlays = _dropRecoverableLegacyA2AConversationSessions(
      overlays,
      ledgerOverlays,
    );
    final mergedOverlays = _mergeA2AConversationSessions(
      cleanedOverlays,
      ledgerOverlays,
    ).where((session) => !deletedSessionIds.contains(session.id)).toList();
    if (!mounted || mergedOverlays.isEmpty) return;
    setState(() {
      _sessions = _mergeA2AConversationSessions(_sessions, mergedOverlays);
      _nextMessageId = _nextMessageNumber(_sessions);
    });
    unawaited(_persistA2AConversationSessions());
  }

  Future<void> _persistA2AConversationSessions() async {
    try {
      final records = _sessions
          .where((session) => session.messages.any(_isA2AConversationMessage))
          .map(_a2aConversationSessionToMap)
          .where((record) => (record['messages'] as List).isNotEmpty)
          .toList(growable: false);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_a2aConversationSessionsKey, jsonEncode(records));
    } catch (_) {
      // Conversation projection is recoverable from A2A/task ledgers; ignore
      // local overlay persistence errors instead of interrupting chat.
    }
  }

  void _appendA2ANoticeMessage(String content) {
    final sanitizedContent = _sanitizeA2AProtocolText(content);
    if (sanitizedContent.trim().isEmpty) return;
    final now = DateTime.now();
    final sessionId = _activeSessionId;
    setState(() {
      _sessions = _sessions.map((session) {
        if (session.id != sessionId) return session;
        return session.copyWith(
          updatedAt: now,
          messages: List.unmodifiable([
            ...session.messages,
            ChatMessage(
              id: 'assistant-${_nextMessageId++}',
              role: ChatRole.assistant,
              content: sanitizedContent,
              createdAt: now,
              completedAt: now,
            ),
          ]),
        );
      }).toList();
    });
    _scrollToBottom(force: true);
  }

  String _a2aTaskTitle(sdk.A2APeerMessage message) {
    if (_a2aPayloadEncrypted(message)) return '发来一条消息';
    final task = message.payload['task'];
    if (task is Map) {
      final context = task['context'];
      if (context is Map) {
        final collaboration = context['a2aCollaboration'];
        if (collaboration is Map) {
          final collaborationMessage = collaboration['message']
              ?.toString()
              .trim();
          if (collaborationMessage != null && collaborationMessage.isNotEmpty) {
            return collaborationMessage;
          }
        }
      }
      final title = task['message']?.toString().trim();
      if (title != null && title.isNotEmpty) return title;
    }
    return _a2aMessageText(message);
  }

  String? _a2aTaskTitleFromRecord(sdk.A2ATaskRecord? task) {
    if (task == null) return null;
    final collaboration = task.request.context['a2aCollaboration'];
    if (collaboration is Map) {
      final message = collaboration['message']?.toString().trim();
      if (message != null && message.isNotEmpty) return message;
    }
    final message = _a2aExtractCollaborationMessage(task.request.message);
    if (message.isEmpty) return null;
    return message;
  }

  String? _a2aMessageTextFromRecord(sdk.A2ATaskRecord? task) {
    if (task == null) return null;
    final summary = task.summary?.trim() ?? '';
    if (summary.isNotEmpty) return summary;
    final error = task.error?.trim() ?? '';
    if (error.isNotEmpty) return error;
    return null;
  }

  bool _a2aTaskHasUserVisibleResult(sdk.A2ATaskRecord task) {
    final status = task.status.trim().toLowerCase();
    return status == 'succeeded' ||
        status == 'failed' ||
        status == 'rejected' ||
        status == 'cancelled';
  }

  String _a2aMessageText(sdk.A2APeerMessage message) {
    if (_a2aPayloadEncrypted(message)) return '收到一条回复。';
    final result = message.payload['result'];
    if (result is Map) {
      final text = result['message']?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    final progress = message.payload['progress'];
    if (progress is Map) {
      final text = progress['message']?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    final messageText = message.payload['message']?.toString().trim();
    if (messageText != null && messageText.isNotEmpty) return messageText;
    return '收到一条消息。';
  }

  bool _a2aPayloadEncrypted(sdk.A2APeerMessage message) {
    return message.payload['encrypted'] is Map;
  }

  String _a2aExtractCollaborationMessage(String value) {
    final text = value.trim();
    if (text.isEmpty) return '';
    const marker = 'Message from the other Agent:';
    final markerIndex = text.indexOf(marker);
    if (markerIndex < 0) return text;
    final tail = text.substring(markerIndex + marker.length).trimLeft();
    final endMarkers = [
      '\n\nTreat this as one turn',
      '\n\nIf you need clarification,',
      '\n\nYour reply may be',
      '\n\nThis message does not require a reply.',
      '\n\nWhen writing the final answer,',
      '\n\nWrite naturally,',
    ];
    var endIndex = tail.length;
    for (final endMarker in endMarkers) {
      final index = tail.indexOf(endMarker);
      if (index >= 0 && index < endIndex) endIndex = index;
    }
    return tail.substring(0, endIndex).trim();
  }

  String _a2aResultStatus(sdk.A2APeerMessage message) {
    final result = message.payload['result'];
    if (result is Map) {
      return result['status']?.toString().trim().toLowerCase() ?? '';
    }
    return '';
  }

  String? _latestA2AAgentAnswer() {
    for (final message in _activeSession.messages.reversed) {
      if (message.role != ChatRole.assistant || message.id == 'welcome') {
        continue;
      }
      if (message.isStreaming || message.completedAt == null) continue;
      final content = message.content.trim();
      if (content.isEmpty) continue;
      if (_isA2ASystemNotice(content)) continue;
      return content;
    }
    return null;
  }

  Future<String?> _latestA2AAgentAnswerForTask(String taskId) async {
    final client = await _getChatClient();
    final record = await client.getLocalA2ATask(taskId);
    final summary = record?.summary?.trim();
    if (summary != null && summary.isNotEmpty) return summary;
    return _latestA2AAgentAnswer();
  }

  bool _isA2ASystemNotice(String content) {
    return content.startsWith('**本地 A2A') ||
        content.startsWith('**收到本地 A2A') ||
        content.startsWith('**确认配对') ||
        content.startsWith('附近设备：') ||
        content.startsWith('来自 ') ||
        content.contains(' 回复：') ||
        content.startsWith('我已回复 ') ||
        content.startsWith('我已经想好回复') ||
        content.startsWith('我处理了 ') ||
        content.startsWith('本地 A2A 已启动') ||
        content.startsWith('已向 `') ||
        content.startsWith('用法：`/a2a') ||
        content.startsWith('找不到收到的任务') ||
        content.startsWith('设备 `') ||
        content.startsWith('当前 Agent 还在运行中') ||
        content.startsWith('还没有可回传的 Agent 回复');
  }

  sdk.A2ALocalPeerAdvertisement? _resolveA2ASlashPeer(String target) {
    final peers = _sortedA2APeers(_a2aSlashPeers.values);
    final index = int.tryParse(target);
    if (index != null && index >= 1 && index <= peers.length) {
      return peers[index - 1];
    }
    for (final peer in peers) {
      if (peer.peerId == target || peer.peerId.startsWith(target)) {
        return peer;
      }
    }
    return null;
  }

  Future<sdk.A2ALocalPeerAdvertisement?> _resolveA2APairedPeer(
    String target,
  ) async {
    final scanned = _resolveA2ASlashPeer(target);
    if (scanned != null && await _isA2APeerPaired(scanned)) return scanned;

    final client = await _getChatClient();
    final savedPeers = await client.listLocalA2APeers();
    for (final saved in savedPeers) {
      final peer = _a2aAdvertisementFromSavedPeer(saved);
      if (peer == null) continue;
      _a2aSlashPeers[peer.peerId] = peer;
      final matches =
          peer.peerId == target ||
          peer.peerId.startsWith(target) ||
          saved.agentId == target;
      if (!matches) continue;
      if (await _isA2APeerPaired(peer)) return peer;
    }
    return null;
  }

  sdk.A2ALocalPeerAdvertisement? _a2aAdvertisementFromSavedPeer(
    sdk.A2APeer peer,
  ) {
    final endpoint = peer.endpoints.isEmpty ? null : peer.endpoints.first;
    if (peer.peerId.isEmpty || endpoint == null || endpoint.uri.isEmpty) {
      return null;
    }
    return sdk.A2ALocalPeerAdvertisement(
      peerId: peer.peerId,
      agentId: peer.agentId,
      displayName: peer.displayName,
      publicKey: peer.publicKey,
      transport: endpoint.transport,
      endpoint: endpoint.uri,
    );
  }

  List<sdk.A2ALocalPeerAdvertisement> _sortedA2APeers(
    Iterable<sdk.A2ALocalPeerAdvertisement> peers,
  ) {
    return peers.toList()
      ..sort((a, b) => _a2aPeerLabel(a).compareTo(_a2aPeerLabel(b)));
  }

  Future<bool> _isA2APeerPaired(sdk.A2ALocalPeerAdvertisement peer) async {
    if (await _a2aSavedSharedSecret(peer) != null) return true;
    final prefs = await SharedPreferences.getInstance();
    final paired = prefs.getStringList(_a2aPairedPeersKey)?.toSet() ?? const {};
    if (!paired.contains(_localA2AHelper.pairingKey(peer))) return false;
    return (await _a2aRemotePairingSecret(peer)) != null;
  }

  Future<String?> _a2aSharedSecretForPeer(
    sdk.A2ALocalPeerAdvertisement peer, {
    required sdk.A2ALocalTransportStatus status,
  }) async {
    await _ensureA2APairingMigrated();
    return _a2aPairingSession.sharedSecretForPeer(
      peer,
      localPeerId: status.peerId,
    );
  }

  Future<String?> _a2aSavedSharedSecret(
    sdk.A2ALocalPeerAdvertisement peer,
  ) async {
    final client = await _getChatClient();
    for (final saved in await client.listLocalA2APeers()) {
      if (saved.peerId != peer.peerId) continue;
      final sharedSecret = saved.sharedSecret.trim();
      if (sharedSecret.isNotEmpty) return sharedSecret;
    }
    return null;
  }

  Future<bool?> _confirmA2ASlashPair(
    sdk.A2ALocalPeerAdvertisement peer, {
    required String remotePairingSecret,
  }) {
    assert(remotePairingSecret.isNotEmpty);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFAFAFA),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          '确认配对',
          style: TextStyle(
            color: Color(0xFF111111),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _a2aPeerLabel(peer),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF111111),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '确认后，两台设备可以互相对话。',
              style: TextStyle(
                color: Color(0xFF555555),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF333333),
            ),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF111111),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  String _a2aPeerLabel(sdk.A2ALocalPeerAdvertisement peer) {
    final displayName = peer.displayName.trim();
    if (_isGenericA2APeerLabel(displayName)) {
      final peerId = peer.peerId.trim().toLowerCase();
      if (peerId.startsWith('ios-')) return 'iOS Agent';
      if (peerId.startsWith('android-')) return 'Android Agent';
      return '附近 Agent';
    }
    return displayName;
  }

  Future<String> _ensureA2ALocalPublicKey() async {
    await _ensureA2APairingMigrated();
    return _a2aPairingSession.localPublicKey();
  }

  Future<String> _ensureA2ALocalPairingSecret() async {
    await _ensureA2APairingMigrated();
    return _a2aPairingSession.localPairingSecret();
  }

  // The SDK session persists identity/secrets under its own keys; migrate the
  // demo's prior plaintext keys once so existing pairings survive the upgrade.
  bool _a2aPairingMigrated = false;
  Future<void> _ensureA2APairingMigrated() async {
    if (_a2aPairingMigrated) return;
    _a2aPairingMigrated = true;
    await _a2aPairingSession.store.migrateLegacyPlaintextIfPresent();
  }

  Future<String?> _a2aRemotePairingSecret(
    sdk.A2ALocalPeerAdvertisement peer,
  ) async {
    await _ensureA2APairingMigrated();
    return _a2aPairingSession.remotePairingSecret(peer);
  }

  Future<void> _a2aSaveRemotePairingSecret(
    sdk.A2ALocalPeerAdvertisement peer,
    String secret,
  ) async {
    await _ensureA2APairingMigrated();
    await _a2aPairingSession.saveRemotePairingSecret(peer, secret);
  }
}

class _A2ASendEvidence {
  const _A2ASendEvidence({
    required this.messageId,
    required this.endpoint,
    required this.deliveryStatus,
  });

  final String messageId;
  final String endpoint;
  final String deliveryStatus;
}

class _A2APendingPairingCompletion {
  const _A2APendingPairingCompletion({
    required this.ackForMessageId,
    required this.completer,
  });

  final String ackForMessageId;
  final Completer<sdk.A2APeerMessage> completer;
}

class _A2AInboundTask {
  const _A2AInboundTask({
    required this.taskId,
    required this.sessionId,
    required this.fromPeerId,
    required this.title,
  });

  final String taskId;
  final String sessionId;
  final String fromPeerId;
  final String title;
}

class _A2ALoopbackCheckResult {
  const _A2ALoopbackCheckResult._(this.state, this.message);

  factory _A2ALoopbackCheckResult.passed() =>
      const _A2ALoopbackCheckResult._('passed', '通过');

  factory _A2ALoopbackCheckResult.failed(String message) =>
      _A2ALoopbackCheckResult._('failed', message);

  factory _A2ALoopbackCheckResult.skipped(String message) =>
      _A2ALoopbackCheckResult._('skipped', message);

  final String state;
  final String message;

  bool get failed => state == 'failed';

  String get label => switch (state) {
    'passed' => '通过',
    'failed' => '失败（$message）',
    _ => '未运行（$message）',
  };
}
