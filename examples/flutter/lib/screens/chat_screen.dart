part of '../main.dart';

const String _a2aProtocolFieldPattern =
    r'(?:kind|delivery|deliveryError|fromPeerId|toPeerId|peerId|sessionId|taskId|messageId|endpoint|transport|conversationTurn|conversationId|turnKind|turnId|replyToTurnId|sentIntent|remoteIntent|speechAct|requiresResponse|conversationOpen|conversationNeedsResponse|openQuestionCount|delivery_error|from_peer_id|to_peer_id|peer_id|session_id|task_id|message_id|conversation_turn|conversation_id|turn_kind|turn_id|reply_to_turn_id|sent_intent|remote_intent|speech_act|requires_response|conversation_open|conversation_needs_response|open_question_count)';

String _sanitizeA2AProtocolText(String value) {
  var text = value;
  final hasA2ASignal = RegExp(
    r'(A2A|Agent-to-Agent|trusted nearby Agent|Discussion goal|Conversation goal|Conversation so far|Recent dialogue|Incoming message|Reply naturally|Output only the next message|routing note|a2a_|peerId|sessionId|taskId|messageId|peer_id|session_id|task_id|message_id|endpoint|transport|a2a-collab|nearby-agent|napaxi:[A-Za-z0-9_.:-]+|ios-[A-Za-z0-9]|android-[A-Za-z0-9]|本地 A2A|附近 Agent|附近设备)',
    caseSensitive: false,
  ).hasMatch(text);
  if (!hasA2ASignal) return text;

  text = text
      .replaceAll('a2a_list_agents', '查找附近 Agent')
      .replaceAll('a2a_start_collaboration', '开启附近对话')
      .replaceAll('a2a_send_message', '发送消息')
      .replaceAll('a2a_wait_messages', '等待回复')
      .replaceAll('a2a_finish_collaboration', '结束附近对话')
      .replaceAll('local_a2a', '附近 Agent');

  text = text.replaceAll(
    RegExp(r'`?\ba2a-collab-[A-Za-z0-9_.:-]+(?:-task-[A-Za-z0-9_.:-]+)?\b`?'),
    '这次附近对话',
  );
  text = text.replaceAll(
    RegExp(r'`?\bnearby-agent:[A-Za-z0-9_.:-]+\b`?', caseSensitive: false),
    '附近 Agent',
  );
  text = text.replaceAll(
    RegExp(r'`?\bnapaxi:[A-Za-z0-9_.:-]+\b`?', caseSensitive: false),
    '附近 Agent',
  );
  text = text.replaceAll(
    RegExp(r'`?\bandroid-[A-Za-z0-9_.:-]{6,}\b`?', caseSensitive: false),
    'Android Agent',
  );
  text = text.replaceAll(
    RegExp(r'`?\bios-[A-Za-z0-9_.:-]{6,}\b`?', caseSensitive: false),
    'iOS Agent',
  );
  text = text.replaceAll(
    RegExp(
      r'`?(?:https?://)?(?:0\.0\.0\.0|127\.0\.0\.1|localhost|10(?:\.\d{1,3}){3}|192\.168(?:\.\d{1,3}){2}|172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2})(?::\d+)?(?:/[^\s`，。；;)]*)?`?',
      caseSensitive: false,
    ),
    '本地连接',
  );
  text = text.replaceAll(
    RegExp(
      '`?\\b$_a2aProtocolFieldPattern\\b\\s*[:：=]\\s*`?[^`\\s，。；;)]*`?',
      caseSensitive: false,
    ),
    '连接信息',
  );
  text = text.replaceAll(
    RegExp(
      '["`]$_a2aProtocolFieldPattern["`]\\s*[:：=]\\s*["`]?[^"`\\n,，。；;)}\\]]+["`]?,?',
      caseSensitive: false,
    ),
    '连接信息',
  );
  text = text.replaceAll(
    RegExp(
      '^\\s*[-*]?\\s*["`]?$_a2aProtocolFieldPattern["`]?\\s*[:：=].*\$',
      multiLine: true,
      caseSensitive: false,
    ),
    '',
  );
  text = text.replaceAll(
    RegExp(
      '^\\s*(?:Collaboration session|Conversation so far|Recent dialogue|Message from the other Agent|Incoming message(?: from [^:：]+)?|Discussion goal|Conversation goal|Sender|Mode|Goal|Intent|From peerId|Your peerId|Peer id|Sender id|Platform thread id|Platform message id|$_a2aProtocolFieldPattern)\\s*[:：=].*\$',
      multiLine: true,
      caseSensitive: false,
    ),
    '',
  );
  text = text.replaceAll(
    RegExp(
      '\\b$_a2aProtocolFieldPattern\\b\\s+["`]?[^"`\\s，。；;)]*["`]?',
      caseSensitive: false,
    ),
    '连接信息',
  );
  text = text.replaceAll(RegExp(r'^\s*连接信息\s*,?\s*$', multiLine: true), '');
  text = text.replaceAll(
    RegExp(
      r'A trusted nearby Agent is (?:talking|collaborating) with you\.?',
      caseSensitive: false,
    ),
    '附近 Agent 发来消息。',
  );
  text = text.replaceAll(
    RegExp(
      r'^\s*(?:You are replying to another trusted nearby Agent|Output only the next message|Reply naturally|Treat this as one turn|This is an ongoing Agent-to-Agent conversation|Your reply may be|If more exchange is needed|If another exchange would improve|Do not pretend the discussion is complete|If you need clarification|When you have a useful answer|The conversation can continue|Write naturally|Do not mention peerId|Do not mention transport details|Do not expose unrelated private data|Stay within this collaboration goal).*$',
      multiLine: true,
      caseSensitive: false,
    ),
    '',
  );
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return text;
}

bool _isLocalA2AChannelName(String value) {
  return value.trim().toLowerCase() == 'local_a2a';
}

bool _isHiddenSdkSessionInfo(sdk.SessionInfo info) {
  return _isLocalA2AChannelName(info.key.channelType);
}

bool _isGenericA2APeerLabel(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) return true;
  return normalized == 'napaxi' ||
      normalized.startsWith('napaxi:') ||
      normalized.startsWith('napaxi-') ||
      normalized.startsWith('napaxi ') ||
      normalized.startsWith('附近设备') ||
      normalized.startsWith('nearby device');
}

String _localA2AChannelPeerLabel(DemoChannelBridgeEvent event) {
  for (final value in [
    event.peerDisplayName,
    event.senderDisplayName,
    event.peerId,
    event.senderId,
  ]) {
    final label = (value ?? '').trim();
    final normalized = label.toLowerCase();
    if (normalized.startsWith('android-')) return 'Android Agent';
    if (normalized.startsWith('ios-')) return 'iOS Agent';
    if (_isGenericA2APeerLabel(label)) continue;
    return label;
  }
  return '附近 Agent';
}

String _channelBridgeVisibleInboundText(DemoChannelBridgeEvent event) {
  return _sanitizeA2AProtocolText(event.inboundText.trim());
}

String _channelBridgeDisplayTitle(DemoChannelBridgeEvent event) {
  if (_isLocalA2AChannelName(event.channelName)) {
    return '和 ${_localA2AChannelPeerLabel(event)} 的对话';
  }
  return event.displayTitle;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.language,
    required this.onLanguageChanged,
    required this.configStore,
    required this.updateService,
    required this.feedbackService,
    this.chatClientFactory,
    this.terminalBackendFactory,
  });

  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final sdk.NapaxiConfigStore configStore;
  final DemoUpdateService updateService;
  final DemoFeedbackService feedbackService;
  final NapaxiChatClientFactory? chatClientFactory;

  /// 终端后端工厂（测试注入 / 未来 PTY 替换）。为空时 [SandboxTerminalScreen]
  /// 用默认的 [ReplTerminalBackend]。
  final TerminalBackend Function()? terminalBackendFactory;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with
        TickerProviderStateMixin,
        WidgetsBindingObserver,
        _ChatScreenChannelMixin,
        _ChatScreenA2AMixin {
  static const String _favoriteAttachmentsKey =
      'napaxi_demo.favorite_attachments.v1';
  static const String _pinnedSessionsKey = 'napaxi_demo.pinned_sessions.v1';
  static const String _assistantAttachmentsKey =
      'napaxi_demo.assistant_attachments.v1';
  static const String _seenAttachmentsKey = 'napaxi_demo.seen_attachments.v1';
  static const String _activeScenarioKey = 'napaxi_demo.active_scenario.v1';
  static const double _sessionMenuFlingVelocity = 650;
  static const double _bottomFollowThreshold = 72;
  static const double _historyTopLoadThreshold = 360;
  static const int _initialHistoryPageLimit = 30;
  static const int _olderHistoryPageLimit = 24;
  static const Duration _contextStatusRefreshTimeout = Duration(seconds: 8);
  static const List<_SlashCommandSpec> _slashCommands = [
    _SlashCommandSpec(
      name: '/help',
      aliases: ['/commands'],
      title: '命令帮助',
      description: '查看可用斜杠命令。',
    ),
    _SlashCommandSpec(
      name: '/status',
      title: '当前状态',
      description: '查看 Agent、模型、任务和上下文状态。',
    ),
    _SlashCommandSpec(
      name: '/context',
      aliases: ['/ctx'],
      title: '上下文',
      description: '查看有效预算、当前窗口和剩余百分比。',
    ),
    _SlashCommandSpec(
      name: '/compact',
      title: '压缩上下文',
      description: '手动压缩当前会话上下文。',
    ),
    _SlashCommandSpec(name: '/stop', title: '停止', description: '停止当前正在运行的回复。'),
    _SlashCommandSpec(name: '/new', title: '新会话', description: '创建一个新的聊天会话。'),
    _SlashCommandSpec(
      name: '/model',
      aliases: ['/models'],
      title: '模型设置',
      description: '打开模型配置页面。',
    ),
    _SlashCommandSpec(
      name: '/tools',
      title: '工具',
      description: '查看移动端当前开放的工具入口。',
    ),
    _SlashCommandSpec(
      name: '/tasks',
      title: '任务',
      description: '查看当前运行和等待中的任务。',
    ),
    _SlashCommandSpec(
      name: '/a2a',
      aliases: ['/peer'],
      title: '本地 A2A',
      description: '通过斜杠指令发现、配对并协作附近设备。',
    ),
    _SlashCommandSpec(
      name: '/channel',
      aliases: ['/channels'],
      title: 'Channel',
      description: '配置并连接 IM 或外设 channel provider。',
    ),
  ];

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  bool _autoFollowEnabled = true;
  bool _isPinnedToBottom = true;
  bool _showJumpToLatest = false;
  bool _isProgrammaticScrollInFlight = false;
  bool _isPrependingHistory = false;
  int _autoFollowSyncToken = 0;

  LlmConfigState _config = const LlmConfigState();
  int _configRevision = 0;
  @override
  int _nextMessageId = 1;
  int _nextSessionId = 1;
  NapaxiChatClient? _chatClient;
  Future<NapaxiChatClient>? _chatClientFuture;
  sdk.NapaxiBrowserController? _browserController;
  bool _browserPanelVisible = false;
  bool _browserPanelExpanded = false;
  String? _browserPanelAgentId;
  String? _browserPanelSessionId;
  StreamSubscription<sdk.BackgroundActionEvent>? _backgroundActionSubscription;
  StreamSubscription<DemoChannelBridgeEvent>? _channelBridgeSubscription;
  final Map<String, Timer> _evolutionPollTimers = {};
  final Map<String, Timer> _evolutionHideTimers = {};
  final Map<String, ChatSessionRunState> _sessionRuns = {};
  final Set<String> _a2aUnreadConversationSessionIds = <String>{};
  _SessionHistoryView _sessionHistoryInitialView = _SessionHistoryView.menu;
  _SettingsSection _sessionHistoryInitialSettingsSection =
      _SettingsSection.menu;
  _SkillsInitialTab _sessionHistoryInitialSkillsTab =
      _SkillsInitialTab.installed;
  String _activeScenarioId = _generalScenarioId;
  String _activeDeveloperEngineId = _defaultDeveloperEngineId;
  DemoGitSettings _gitSettings = const DemoGitSettings();
  final Set<String> _stoppingSessionIds = {};
  int _nextInterjectionId = 1;
  bool _isHandlingNotificationStop = false;
  bool _isHandlingProviderInstall = false;
  bool _isHandlingAgentTrigger = false;
  bool _isEnsuringConfiguredChannels = false;
  int _channelInputRefreshSerial = 0;
  int _channelInputLoopSerial = 0;
  bool _initialStateRestored = false;
  Future<void>? _restorePersistedStateFuture;
  bool _isCheckingForUpdate = false;
  List<DemoChannelInputSource> _channelInputSources = const [];
  String? _channelInputBusyAccountId;
  String? _channelInputActiveAccountId;
  final Map<String, sdk.SessionKey> _sdkSessions = {};
  Set<String> _pinnedSessionIds = const {};
  List<FavoriteAttachment> _favoriteAttachments = const [];
  Map<String, List<ChatAttachment>> _assistantAttachmentCache = const {};
  Map<String, List<ChatAttachment>> _pendingAssistantAttachments = const {};
  Map<String, Set<String>> _seenAttachmentIds = const {};
  bool _seenAttachmentsRestored = false;
  final Map<String, sdk.ContextStatus> _contextStatuses = {};
  final Set<String> _contextStatusLoading = {};
  final Map<String, String?> _historyNextBefore = {};
  final Set<String> _historyHasMore = {};
  final Set<String> _historyPageLoading = {};
  final Map<String, AgentToolCall> _fullHistoryToolCallCache = {};
  final Map<String, _ContextCompactionNotice> _contextCompactionNotices = {};
  final Map<String, Timer> _contextCompactionHideTimers = {};
  final Set<String> _projectedA2AObservationKeys = {};
  final Map<String, DateTime> _a2aConversationNoticeTimes = {};
  @override
  String _activeAgentId = sdk.NapaxiEngine.defaultAgentId;
  List<DemoAgent> _agents = const [_defaultDemoAgent];
  List<_SlashCommandSpec> _skillSlashCommands = const [];

  final Map<String, _TerminalSession> _terminalSessionMap = {};
  int _nextTerminalId = 0;

  bool _isTerminalSession(String id) => id.startsWith('terminal-');

  _TerminalSession? get _activeTerminalSession =>
      _terminalSessionMap[_activeSessionId];

  @override
  late String _activeSessionId = _newSessionId();
  @override
  late List<ChatSession> _sessions = [
    ChatSession(
      id: _activeSessionId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      messages: [_welcomeMessage(widget.language, _config)],
    ),
  ];

  @override
  ChatSession get _activeSession {
    return _sessions.firstWhere((session) => session.id == _activeSessionId);
  }

  List<ChatMessage> get _messages => _activeSession.messages;

  @override
  ChatSessionRunState? get _activeRun => _sessionRuns[_activeSessionId];

  bool get _isActiveSessionSending => _activeRun?.isRunning ?? false;

  @override
  sdk.NapaxiCapabilitySelection get _activeScenarioCapabilitySelection {
    return _scenarioCapabilitySelection(
      _activeScenarioId,
      gitSettings: _gitSettings,
      developerEngineId: _activeDeveloperEngineId,
    );
  }

  DemoScenarioRuntimeProfile get _activeRuntimeProfile {
    return _scenarioRuntimeProfileFor(
      _activeScenarioId,
      developerEngineId: _activeDeveloperEngineId,
    );
  }

  @override
  String get _activeAccountId => _activeRuntimeProfile.accountId;

  String _newSessionId() => 'session-${_nextSessionId++}';

  List<_ConversationAttachmentItem> get _activeConversationAttachments {
    final seen = <String>{};
    final items = <_ConversationAttachmentItem>[];
    for (final message in _activeSession.messages.reversed) {
      for (final attachment in message.attachments.reversed) {
        final source =
            message.isUser || _hasUploadedAttachmentSandboxIdentity(attachment)
            ? _ConversationAttachmentSource.uploaded
            : _ConversationAttachmentSource.generated;
        final identity = _attachmentIdentity(attachment).trim();
        if (identity.isEmpty || !seen.add(identity)) continue;
        items.add(
          _ConversationAttachmentItem(
            attachment: attachment,
            source: source,
            createdAt: message.createdAt,
          ),
        );
      }
    }
    return List.unmodifiable(items);
  }

  List<FavoriteAttachment> get _activeFavoriteAttachments {
    return _favoriteAttachments
        .where(
          (favorite) =>
              favorite.accountId == _activeAccountId &&
              favorite.agentId == _activeAgentId,
        )
        .toList(growable: false);
  }

  /// Flatten the active session's messages into render items, aggregating each
  /// turn's generated attachments into a single block at the END OF THAT TURN.
  ///
  /// A turn is one user message plus the assistant/tool messages that follow it
  /// until the next user message. Generated attachments are deduped within the
  /// turn by identity, so a file regenerated in a later turn reappears at the
  /// end of that later turn. Uploaded attachments live on user messages and are
  /// rendered inline, so they are skipped here.
  List<_ChatRenderItem> _buildChatRenderItems() {
    final items = <_ChatRenderItem>[];
    var turnIdentities = <String>{};
    var turnAttachments = <ChatAttachment>[];
    String? turnUserMessageId;
    var turnIndex = 0;

    void flushTurn() {
      if (turnAttachments.isEmpty) return;
      items.add(
        _GeneratedAttachmentsItem(
          attachments: List.unmodifiable(turnAttachments),
          turnIndex: turnIndex,
          turnUserMessageId: turnUserMessageId,
        ),
      );
    }

    for (final message in _messages) {
      if (message.isUser) {
        // Close out the previous turn before this user bubble starts a new one.
        flushTurn();
        turnIdentities = <String>{};
        turnAttachments = <ChatAttachment>[];
        turnUserMessageId = message.id;
        turnIndex++;
        items.add(_MessageItem(message));
        continue;
      }
      if (_isUserVisibleChatMessage(message)) {
        items.add(_MessageItem(message));
      }
      for (final attachment in message.attachments) {
        if (_hasUploadedAttachmentSandboxIdentity(attachment)) continue;
        final identity = _attachmentIdentity(attachment).trim();
        if (identity.isEmpty || !turnIdentities.add(identity)) continue;
        turnAttachments.add(attachment);
      }
    }
    flushTurn();
    return items;
  }

  bool _isUserVisibleChatMessage(ChatMessage message) {
    if (message.isUser || message.isStreaming) return true;
    if (message.content.trim().isNotEmpty &&
        _sanitizeA2AProtocolText(message.content).trim().isNotEmpty) {
      return true;
    }
    if (message.attachments.isNotEmpty ||
        message.humanRequest != null ||
        message.evolutionStatus != null ||
        message.action != null) {
      return true;
    }
    return _hasVisibleAgentTrace(message);
  }

  /// Identities of every generated attachment across the conversation, used to
  /// suppress inline rendering inside bubbles (each is shown in its turn block).
  Set<String> _generatedAttachmentIdentities(ChatSession session) {
    final identities = <String>{};
    for (final message in session.messages) {
      if (message.isUser) continue;
      for (final attachment in message.attachments) {
        if (_hasUploadedAttachmentSandboxIdentity(attachment)) continue;
        final identity = _attachmentIdentity(attachment).trim();
        if (identity.isEmpty) continue;
        identities.add(identity);
      }
    }
    return Set.unmodifiable(identities);
  }

  @override
  DemoAgent get _activeAgent {
    return _agents.firstWhere(
      (agent) => agent.id == _activeAgentId,
      orElse: () => _defaultDemoAgent,
    );
  }

  String _sessionCacheKey(String agentId, String sessionId) {
    return '$_activeAccountId::$agentId::$sessionId';
  }

  String get _activeSessionCacheKey {
    return _sessionCacheKey(_activeAgentId, _activeSessionId);
  }

  sdk.ContextStatus? get _activeContextStatus {
    return _contextStatuses[_activeSessionCacheKey];
  }

  bool get _isActiveContextStatusLoading {
    return _contextStatusLoading.contains(_activeSessionCacheKey);
  }

  _ContextCompactionNotice? get _activeContextCompactionNotice {
    return _contextCompactionNotices[_activeSessionCacheKey];
  }

  List<_SlashCommandSpec> get _availableSlashCommands {
    if (_skillSlashCommands.isEmpty) return _slashCommands;
    return List.unmodifiable([..._slashCommands, ..._skillSlashCommands]);
  }

  String? _modelProfileIdForAgent(String agentId) {
    if (agentId == sdk.NapaxiEngine.defaultAgentId) return null;
    for (final agent in _agents) {
      if (agent.id == agentId) return agent.modelProfileId;
    }
    return null;
  }

  @override
  LlmModelProfile? _runtimeProfileForAgent(String agentId) {
    return _config.runtimeProfileFor(
      chatProfileId: _modelProfileIdForAgent(agentId),
    );
  }

  @override
  String get _responseLanguageCode {
    return widget.language == AppLanguage.chinese ? 'zh' : 'en';
  }

  void _showMissingAgentModel(String profileId) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.of(context).agentModelMissing(profileId)),
      ),
    );
  }

  ChatMessage _welcomeMessage(AppLanguage language, LlmConfigState config) {
    final selectedProfile = config.selectedRuntimeProfile;
    final hasReadyChatModel =
        selectedProfile != null &&
        selectedProfile.hasModel &&
        selectedProfile.apiKey.trim().isNotEmpty;
    final strings = AppStrings.forLanguage(language);
    return ChatMessage(
      id: 'welcome',
      role: ChatRole.assistant,
      content: hasReadyChatModel
          ? strings.welcomeReadyMessage
          : strings.welcomeMessage,
      createdAt: DateTime.now(),
    );
  }

  ChatSession _refreshWelcomeMessage(ChatSession session) {
    final messages = [...session.messages];
    final welcomeIndex = messages.indexWhere(
      (message) => message.id == 'welcome',
    );
    if (welcomeIndex == -1) return session;
    messages[welcomeIndex] = _welcomeMessage(widget.language, _config);
    return session.copyWith(messages: List.unmodifiable(messages));
  }

  @override
  void initState() {
    super.initState();
    _sessionMenuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _workbenchDrawerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 220),
    );
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_handleChatScroll);
    _inputFocusNode.addListener(_handleInputFocusChanged);
    _restorePersistedStateFuture = _restorePersistedState();
    unawaited(_restorePersistedStateFuture);
    unawaited(_restoreFavoriteAttachments());
    unawaited(_restorePinnedSessions());
    unawaited(_restoreAssistantAttachments());
    unawaited(_restoreSeenAttachments());
    unawaited(_refreshSkillSlashCommands());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_checkForUpdates(automatic: true));
    });
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language == widget.language) return;

    setState(() {
      _sessions = _sessions.map(_refreshWelcomeMessage).toList();
    });
  }

  @override
  void dispose() {
    _disposeA2A();
    for (final ts in _terminalSessionMap.values) {
      ts.dispose();
    }
    _terminalSessionMap.clear();
    for (final run in _sessionRuns.values) {
      unawaited(run.subscription.cancel());
    }
    for (final timer in _evolutionPollTimers.values) {
      timer.cancel();
    }
    for (final timer in _evolutionHideTimers.values) {
      timer.cancel();
    }
    for (final timer in _contextCompactionHideTimers.values) {
      timer.cancel();
    }
    _backgroundActionSubscription?.cancel();
    _channelBridgeSubscription?.cancel();
    _chatClient?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _sessionMenuController.dispose();
    _workbenchDrawerController.dispose();
    _autoFollowSyncToken += 1;
    _scrollController.removeListener(_handleChatScroll);
    _inputFocusNode.removeListener(_handleInputFocusChanged);
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _handleInputFocusChanged() {
    if (!_inputFocusNode.hasFocus) return;
    _scrollToBottom(force: true);
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!_inputFocusNode.hasFocus) return;
    _scrollToBottom(force: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_handlePendingProviderInstall());
      unawaited(_handlePendingAgentTrigger());
      unawaited(_ensureConfiguredChannelsConnected());
      _scheduleA2AConnectionRestoreIfAllowed();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(_ensureConfiguredChannelsConnected());
    }
  }

  void _handleChatScroll() {
    if (!_scrollController.hasClients) return;
    final isNearBottom = _isNearBottom();
    if (_isProgrammaticScrollInFlight) {
      if (!mounted) return;
      setState(() {
        _isPinnedToBottom = isNearBottom;
        if (isNearBottom) _showJumpToLatest = false;
      });
      return;
    }
    final nextAutoFollowEnabled = isNearBottom;
    final nextShowJumpToLatest = isNearBottom ? false : _showJumpToLatest;
    if (isNearBottom == _isPinnedToBottom &&
        nextAutoFollowEnabled == _autoFollowEnabled &&
        nextShowJumpToLatest == _showJumpToLatest) {
      _maybeLoadOlderHistory();
      return;
    }
    if (!mounted) return;
    setState(() {
      _autoFollowEnabled = nextAutoFollowEnabled;
      _isPinnedToBottom = isNearBottom;
      _showJumpToLatest = nextShowJumpToLatest;
    });
    _maybeLoadOlderHistory();
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return true;
    return (position.maxScrollExtent - position.pixels) <=
        _bottomFollowThreshold;
  }

  bool _isNearHistoryTop() {
    if (!_scrollController.hasClients) return false;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return false;
    return position.pixels <= _historyTopLoadThreshold;
  }

  void _markNewContentAvailable() {
    if (_autoFollowEnabled || _showJumpToLatest || !mounted) return;
    setState(() => _showJumpToLatest = true);
  }

  void _handleMessageListSizeChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isPrependingHistory) return;
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (!position.hasContentDimensions) return;
      if (_autoFollowEnabled || _isProgrammaticScrollInFlight) {
        _scheduleAutoFollowSync();
      } else {
        _markNewContentAvailable();
      }
    });
  }

  void _scheduleAutoFollowSync({
    bool force = false,
    int stablePassesRequired = 2,
  }) {
    if (_isPrependingHistory && !force) return;
    if (!force && !_autoFollowEnabled) {
      _markNewContentAvailable();
      return;
    }

    final token = ++_autoFollowSyncToken;
    double? lastTarget;
    var stablePasses = 0;

    void step() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || token != _autoFollowSyncToken) return;
        if (!_scrollController.hasClients) return;
        if (_isPrependingHistory && !force) return;
        if (!force && !_autoFollowEnabled) {
          _markNewContentAvailable();
          return;
        }

        final position = _scrollController.position;
        if (!position.hasContentDimensions) {
          WidgetsBinding.instance.scheduleFrameCallback((_) => step());
          return;
        }

        final target = position.maxScrollExtent;
        _isProgrammaticScrollInFlight = true;
        _scrollController.jumpTo(target);
        _isProgrammaticScrollInFlight = false;

        if (lastTarget != null && (target - lastTarget!).abs() < 1) {
          stablePasses += 1;
        } else {
          stablePasses = 0;
        }
        lastTarget = target;

        final isNearBottom = _isNearBottom();
        if (mounted &&
            (isNearBottom != _isPinnedToBottom ||
                !_autoFollowEnabled ||
                _showJumpToLatest)) {
          setState(() {
            _autoFollowEnabled = true;
            _isPinnedToBottom = isNearBottom;
            _showJumpToLatest = false;
          });
        }

        if (stablePasses < stablePassesRequired) {
          WidgetsBinding.instance.scheduleFrameCallback((_) => step());
        }
      });
    }

    if (force && mounted && (!_autoFollowEnabled || _showJumpToLatest)) {
      setState(() {
        _autoFollowEnabled = true;
        _showJumpToLatest = false;
      });
    }
    step();
  }

  Future<void> _checkForUpdates({required bool automatic}) async {
    if (_isCheckingForUpdate) return;
    setState(() => _isCheckingForUpdate = true);
    try {
      final result = await widget.updateService.checkForUpdate(
        respectSkippedVersion: automatic,
      );
      if (!mounted) return;
      final strings = AppStrings.of(context);
      if (result.skipped || (automatic && !result.hasUpdate)) {
        return;
      }
      if (!result.hasUpdate) {
        if (!automatic &&
            result.unconfigured &&
            widget.updateService.supportsExternalUpdatePage) {
          await _showReleasePageDialog();
          return;
        }
        final message =
            result.message ??
            (result.unconfigured || result.unsupported
                ? strings.updateCheckUnavailable
                : strings.noUpdateAvailable);
        if (!automatic) await _showUpdateNoticeDialog(message);
        return;
      }
      await _showUpdateDialog(result.update!, result.currentVersion);
    } catch (error) {
      if (!mounted || automatic) return;
      await _showUpdateNoticeDialog(
        AppStrings.of(context).updateCheckFailed(_friendlyDisplayError(error)),
      );
    } finally {
      if (mounted) setState(() => _isCheckingForUpdate = false);
    }
  }

  Future<void> _showUpdateDialog(
    DemoUpdateInfo update,
    DemoAppVersion currentVersion,
  ) async {
    final strings = AppStrings.of(context);
    var stage = _UpdateInstallStage.idle;
    var receivedBytes = 0;
    int? totalBytes;
    String? installError;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final progress = totalBytes == null || totalBytes == 0
                ? null
                : receivedBytes / totalBytes!;
            final downloading = stage == _UpdateInstallStage.downloading;
            return PopScope(
              canPop: !downloading && !update.needForceUpdate,
              child: AlertDialog(
                title: Text(strings.updateAvailableTitle),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.updateVersionLine(
                        currentVersion.display,
                        _formatUpdateVersion(update),
                      ),
                    ),
                    if (update.fileSizeBytes != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        strings.updateSize(
                          _formatFileSize(update.fileSizeBytes!),
                        ),
                      ),
                    ],
                    if (update.needForceUpdate) ...[
                      const SizedBox(height: 8),
                      Text(
                        strings.forceUpdate,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      strings.updateDescription,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      update.updateDescription.trim().isEmpty
                          ? strings.noUpdateDescription
                          : update.updateDescription.trim(),
                    ),
                    if (downloading) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(value: progress),
                      const SizedBox(height: 8),
                      Text(
                        _formatUpdateProgress(
                          strings,
                          receivedBytes,
                          totalBytes,
                        ),
                      ),
                    ],
                    if (stage == _UpdateInstallStage.installerOpened) ...[
                      const SizedBox(height: 12),
                      Text(
                        strings.updateInstallerOpened,
                        style: const TextStyle(
                          color: Color(0xFF166534),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (stage == _UpdateInstallStage.permissionRequired) ...[
                      const SizedBox(height: 12),
                      Text(
                        strings.updatePermissionRequired,
                        style: const TextStyle(
                          color: Color(0xFF92400E),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (stage == _UpdateInstallStage.failed &&
                        installError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        strings.updateDownloadFailed(installError!),
                        style: const TextStyle(color: Color(0xFFB91C1C)),
                      ),
                    ],
                  ],
                ),
                actions: [
                  if (stage == _UpdateInstallStage.idle &&
                      !update.needForceUpdate)
                    TextButton(
                      key: const Key('update_later_button'),
                      onPressed: () {
                        unawaited(widget.updateService.skipUpdate(update));
                        Navigator.of(dialogContext).pop();
                      },
                      child: Text(strings.later),
                    ),
                  if (stage == _UpdateInstallStage.failed &&
                      update.appUrl.isNotEmpty)
                    TextButton(
                      key: const Key('open_pgyer_install_page_button'),
                      onPressed: () {
                        unawaited(widget.updateService.openInstallPage(update));
                      },
                      child: Text(strings.openInstallPage),
                    ),
                  if (stage == _UpdateInstallStage.failed &&
                      widget.updateService.supportsExternalUpdatePage)
                    TextButton(
                      key: const Key('open_release_page_button'),
                      onPressed: () {
                        unawaited(_showReleasePageDialog());
                      },
                      child: Text(strings.openReleasePage),
                    ),
                  if (stage == _UpdateInstallStage.installerOpened ||
                      stage == _UpdateInstallStage.permissionRequired)
                    TextButton(
                      key: const Key('update_done_button'),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(
                        MaterialLocalizations.of(context).okButtonLabel,
                      ),
                    ),
                  if (stage == _UpdateInstallStage.idle ||
                      stage == _UpdateInstallStage.failed)
                    FilledButton(
                      key: const Key('install_update_button'),
                      onPressed: () async {
                        setDialogState(() {
                          stage = _UpdateInstallStage.downloading;
                          installError = null;
                          receivedBytes = 0;
                          totalBytes = null;
                        });
                        final result = await widget.updateService
                            .downloadAndInstall(
                              update,
                              onProgress: (received, total) {
                                if (!mounted || !dialogContext.mounted) {
                                  return;
                                }
                                setDialogState(() {
                                  receivedBytes = received;
                                  totalBytes = total;
                                });
                              },
                            );
                        if (!mounted || !dialogContext.mounted) return;
                        setDialogState(() {
                          if (result.permissionRequired) {
                            stage = _UpdateInstallStage.permissionRequired;
                          } else if (result.success || result.installerOpened) {
                            stage = _UpdateInstallStage.installerOpened;
                          } else {
                            stage = _UpdateInstallStage.failed;
                            installError =
                                result.message ?? strings.updateUnknownError;
                          }
                        });
                      },
                      child: Text(strings.updateNow),
                    )
                  else if (downloading)
                    FilledButton(
                      onPressed: null,
                      child: Text(strings.updateInstalling),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatUpdateVersion(DemoUpdateInfo update) {
    final version = update.buildVersion.isEmpty ? '-' : update.buildVersion;
    if (update.buildVersionNo.isNotEmpty) {
      return '$version+${update.buildVersionNo}';
    }
    if (update.buildBuildVersion != null) {
      return '$version+${update.buildBuildVersion}';
    }
    return version;
  }

  String _formatUpdateProgress(
    AppStrings strings,
    int receivedBytes,
    int? totalBytes,
  ) {
    if (receivedBytes <= 0) return strings.updateInstalling;
    final received = _formatFileSize(receivedBytes);
    if (totalBytes == null || totalBytes <= 0) {
      return '${strings.updateInstalling} $received';
    }
    return '${strings.updateInstalling} $received / ${_formatFileSize(totalBytes)}';
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// host 侧沙箱 workspace 目录（与 environment_panel 共用同一沙箱）。
  /// path_provider 在某些环境（如纯单元测试）不可用，失败时回退到 guest 路径。
  Future<String> _resolveWorkspaceDir() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final workspaceDir = Directory(
        '${supportDir.path}/environment-workspace',
      );
      if (!workspaceDir.existsSync()) {
        workspaceDir.createSync(recursive: true);
      }
      return workspaceDir.path;
    } catch (_) {
      return '/workspace';
    }
  }

  Future<void> _openSandboxTerminal() async {
    final factory = widget.terminalBackendFactory;
    TerminalBackend Function() effectiveFactory;

    if (factory != null) {
      effectiveFactory = factory;
    } else if (Platform.isAndroid) {
      final workspaceDir = await _resolveWorkspaceDir();
      if (!mounted) return;
      effectiveFactory = () => PtyTerminalBackend(workspaceDir: workspaceDir);
    } else {
      final workspaceDir = await _resolveWorkspaceDir();
      if (!mounted) return;
      effectiveFactory = () => ReplTerminalBackend(workspaceDir: workspaceDir);
    }

    if (!mounted) return;

    final num = ++_nextTerminalId;
    final terminalId = 'terminal-$num';
    final backend = effectiveFactory();
    final terminal = Terminal(maxLines: 10000);
    final session = _TerminalSession(
      id: terminalId,
      backend: backend,
      terminal: terminal,
    );

    session.outputSubscription = backend.output.listen(terminal.write);
    terminal.onOutput = (data) =>
        backend.write(session.modifiers.consumeTextInput(data));
    terminal.onResize = (w, h, pw, ph) => backend.resize(w, h);

    backend.start(
      argv: const ['/bin/sh', '-lc'],
      workdir: '/workspace',
      cols: terminal.viewWidth,
      rows: terminal.viewHeight,
    );

    final now = DateTime.now();
    setState(() {
      _terminalSessionMap[terminalId] = session;
      _activeSessionId = terminalId;
      _sessions = [
        ChatSession(
          id: terminalId,
          title: '${AppStrings.of(context).terminalTitle} #$num',
          createdAt: now,
          updatedAt: now,
          messages: const [],
        ),
        ..._sessions,
      ];
      _editingMessageId = null;
      _inputController.clear();
    });
    _dismissKeyboard();
  }

  static const _lightTerminalTheme = TerminalTheme(
    cursor: Color(0xFF333333),
    selection: Color(0x40007AFF),
    foreground: Color(0xFF1E1E1E),
    background: Color(0xFFF5F5F5),
    black: Color(0xFF000000),
    red: Color(0xFFC41A15),
    green: Color(0xFF007400),
    yellow: Color(0xFF826B28),
    blue: Color(0xFF0451A5),
    magenta: Color(0xFFBC05BC),
    cyan: Color(0xFF0598BC),
    white: Color(0xFFE5E5E5),
    brightBlack: Color(0xFF666666),
    brightRed: Color(0xFFCD3131),
    brightGreen: Color(0xFF14CE14),
    brightYellow: Color(0xFFB5BA00),
    brightBlue: Color(0xFF0451A5),
    brightMagenta: Color(0xFFBC05BC),
    brightCyan: Color(0xFF0598BC),
    brightWhite: Color(0xFFA5A5A5),
    searchHitBackground: Color(0xFFFFDF5F),
    searchHitBackgroundCurrent: Color(0xFFA8F29B),
    searchHitForeground: Color(0xFF000000),
  );

  Widget _buildTerminalView() {
    final ts = _activeTerminalSession;
    if (ts == null) return const SizedBox.shrink();
    return TerminalViewWrapper(
      key: const Key('chat_terminal_view'),
      terminal: ts.terminal,
      backend: ts.backend,
      child: Column(
        children: [
          Expanded(
            child: Container(
              color: _lightTerminalTheme.background,
              child: TerminalView(
                ts.terminal,
                controller: ts.controller,
                theme: _lightTerminalTheme,
                autofocus: true,
              ),
            ),
          ),
          if (Platform.isAndroid || Platform.isIOS)
            TerminalToolbar(terminal: ts.terminal, modifiers: ts.modifiers),
        ],
      ),
    );
  }

  Future<void> _copyWorkspacePath() async {
    // 复制「当前平台终端里实际会用到的工作区路径」：Android 沙箱里是 guest 路径
    // `/workspace`，host（桌面 / iOS 终端）则是真实沙箱目录，由 runner 统一映射，
    // 避免在非 Android 平台复制一个不存在的 `/workspace`。
    final workspaceDir = await _resolveWorkspaceDir();
    final runner = DemoGitRunner.defaultFor(Directory(workspaceDir));
    await Clipboard.setData(
      ClipboardData(text: runner.workspacePath(workspaceDir)),
    );
    if (mounted) _showSnackBar(AppStrings.of(context).copiedToClipboard);
  }

  Future<void> _copyBranchName() async {
    // state 里没有现成 branch，点击时跑一次 git 取当前分支。
    final workspaceDir = await _resolveWorkspaceDir();
    final runner = DemoGitRunner.defaultFor(Directory(workspaceDir));
    final result = await runner.runGit(
      ['rev-parse', '--abbrev-ref', 'HEAD'],
      workingDirectory: runner.workspacePath(workspaceDir),
    );
    if (!mounted) return;
    final exitCode = result['exitCode'] as int? ?? -1;
    final branch = (result['stdout'] ?? '').toString().trim();
    // detached HEAD 时 `--abbrev-ref` 返回 "HEAD"，不算真正的分支名。
    final resolved = exitCode == 0 &&
            branch.isNotEmpty &&
            branch != 'HEAD'
        ? branch
        : null;
    if (resolved != null) {
      await Clipboard.setData(ClipboardData(text: resolved));
      if (mounted) _showSnackBar(AppStrings.of(context).copiedToClipboard);
    } else if (mounted) {
      _showSnackBar(AppStrings.of(context).copyBranchNameUnavailable);
    }
  }

  @override
  void _showA2AConversationUpdatedNotice(String sessionId, {String? title}) {
    final targetSessionId = sessionId.trim();
    if (!mounted || targetSessionId.isEmpty) return;
    if (_activeSessionId == targetSessionId) {
      if (_a2aUnreadConversationSessionIds.remove(targetSessionId)) {
        setState(() {});
      }
      return;
    }
    if (_a2aUnreadConversationSessionIds.add(targetSessionId)) {
      setState(() {});
    }
    final now = DateTime.now();
    final lastShown = _a2aConversationNoticeTimes[targetSessionId];
    if (lastShown != null && now.difference(lastShown).inSeconds < 8) {
      return;
    }
    _a2aConversationNoticeTimes[targetSessionId] = now;
    final sanitizedTitle = _sanitizeA2AProtocolText(title ?? '').trim();
    final displayTitle = sanitizedTitle.isNotEmpty ? sanitizedTitle : '附近对话';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$displayTitle 有新消息'),
          action: SnackBarAction(
            label: '查看',
            onPressed: () {
              if (!mounted) return;
              _selectSession(targetSessionId);
            },
          ),
        ),
      );
  }

  Future<void> _showUpdateNoticeDialog(String message) {
    final strings = AppStrings.of(context);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(strings.checkForUpdates),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(strings.updateNoticeClose),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showReleasePageDialog() async {
    final strings = AppStrings.of(context);
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(strings.checkForUpdates),
          content: Text(strings.updateReleasePagePrompt),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              key: const Key('confirm_open_release_page_button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings.openReleasePage),
            ),
          ],
        );
      },
    );
    if (shouldOpen != true || !mounted) return;
    final opened = await widget.updateService.openExternalUpdatePage();
    if (!mounted || opened) return;
    await _showUpdateNoticeDialog(strings.releasePageOpenFailed);
  }

  Future<void> _loadSessionHistory(String sessionId) async {
    await _loadSessionHistoryPage(sessionId, prepend: false);
  }

  void _maybeLoadOlderHistory() {
    if (!_isNearHistoryTop()) return;
    if (_isPrependingHistory) return;
    final sessionId = _activeSessionId;
    final cacheKey = _activeSessionCacheKey;
    if (!_historyHasMore.contains(cacheKey)) return;
    if (_historyPageLoading.contains(cacheKey)) return;
    if (_hasLiveSessionRun(sessionId)) return;
    unawaited(_loadSessionHistoryPage(sessionId, prepend: true));
  }

  Future<void> _loadSessionHistoryPage(
    String sessionId, {
    required bool prepend,
  }) async {
    if (_hasLiveSessionRun(sessionId)) return;
    final client = await _getChatClient();
    final agentId = _activeAgentId;
    final cacheKey = _sessionCacheKey(agentId, sessionId);
    if (_historyPageLoading.contains(cacheKey)) return;
    final before = prepend ? _historyNextBefore[cacheKey] : null;
    if (prepend && before == null) return;
    if (mounted) {
      setState(() {
        _historyPageLoading.add(cacheKey);
        if (prepend) {
          _isPrependingHistory = true;
          _autoFollowEnabled = false;
          _isPinnedToBottom = false;
          _showJumpToLatest = false;
          _autoFollowSyncToken += 1;
        }
      });
    } else {
      _historyPageLoading.add(cacheKey);
      if (prepend) {
        _isPrependingHistory = true;
        _autoFollowEnabled = false;
        _isPinnedToBottom = false;
        _showJumpToLatest = false;
        _autoFollowSyncToken += 1;
      }
    }

    final previousScrollMetrics = prepend && _scrollController.hasClients
        ? (
            pixels: _scrollController.position.pixels,
            maxScrollExtent: _scrollController.position.maxScrollExtent,
          )
        : null;
    final sdk.HistoryPage page;
    try {
      page = await client.getHistoryPage(
        sessionId,
        agentId: agentId,
        before: before,
        limit: prepend ? _olderHistoryPageLimit : _initialHistoryPageLimit,
      );
      final logTag = agentId == 'engine.cc'
          ? 'napaxiCCHistory'
          : 'napaxiCodexHistory';
      debugPrint(
        '[$logTag] historyPage session=$sessionId agent=$agentId prepend=$prepend sdkMessages=${page.messages.length} hasMore=${page.hasMore} nextBefore=${page.nextBefore}',
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _historyPageLoading.remove(cacheKey);
          if (prepend) _isPrependingHistory = false;
        });
      } else {
        _historyPageLoading.remove(cacheKey);
        if (prepend) _isPrependingHistory = false;
      }
      return;
    }
    if (!mounted ||
        _activeAgentId != agentId ||
        _activeSessionId != sessionId ||
        _hasLiveSessionRun(sessionId)) {
      _historyPageLoading.remove(cacheKey);
      if (prepend) _isPrependingHistory = false;
      return;
    }
    final a2aOverlays = await _loadA2AConversationSessions();
    if (!mounted ||
        _activeAgentId != agentId ||
        _activeSessionId != sessionId ||
        _hasLiveSessionRun(sessionId)) {
      _historyPageLoading.remove(cacheKey);
      if (prepend) _isPrependingHistory = false;
      return;
    }
    final a2aOverlay = _a2aConversationOverlayForSession(
      a2aOverlays,
      sessionId,
    );
    if (page.messages.isEmpty && !prepend) {
      setState(() {
        _historyPageLoading.remove(cacheKey);
        _historyNextBefore[cacheKey] = page.nextBefore;
        if (page.hasMore) {
          _historyHasMore.add(cacheKey);
        } else {
          _historyHasMore.remove(cacheKey);
        }
        if (a2aOverlay != null) {
          _sessions = _sessions
              .map(
                (session) => session.id == sessionId
                    ? _mergeA2AConversationOverlayIntoSession(
                        session,
                        a2aOverlay,
                      )
                    : session,
              )
              .toList(growable: false);
        }
      });
      unawaited(_refreshContextStatusForSession(agentId, sessionId));
      return;
    }
    final messages = _messagesFromSdkHistory(
      page.messages,
      accountId: _activeAccountId,
      agentId: agentId,
      generatedIdStart: prepend ? _nextMessageNumber(_sessions) : 1,
    );
    final logTag = agentId == 'engine.cc'
        ? 'napaxiCCHistory'
        : 'napaxiCodexHistory';
    debugPrint(
      '[$logTag] historyPage mapped session=$sessionId agent=$agentId prepend=$prepend uiMessages=${messages.length} first=${messages.isEmpty ? 'none' : '${messages.first.role}:${messages.first.content.length}'}',
    );
    setState(() {
      _historyPageLoading.remove(cacheKey);
      _historyNextBefore[cacheKey] = page.nextBefore;
      if (page.hasMore) {
        _historyHasMore.add(cacheKey);
      } else {
        _historyHasMore.remove(cacheKey);
      }
      _sessions = _sessions.map((session) {
        if (session.id != sessionId) return session;
        if (prepend) {
          final mergedSession = session.copyWith(
            messages: List.unmodifiable([...messages, ...session.messages]),
          );
          return _mergeStoredAssistantAttachments(
            a2aOverlay == null
                ? mergedSession
                : _mergeA2AConversationOverlayIntoSession(
                    mergedSession,
                    a2aOverlay,
                  ),
          );
        }
        final historySession = session.copyWith(
          messages: List.unmodifiable(messages),
        );
        return _mergeStoredAssistantAttachments(
          a2aOverlay == null
              ? historySession
              : _mergeA2AConversationOverlayIntoSession(
                  historySession,
                  a2aOverlay,
                ),
        );
      }).toList();
      _nextMessageId = _nextMessageNumber(_sessions);
    });
    if (prepend && previousScrollMetrics != null) {
      _preserveScrollOffsetAfterPrepend(
        previousPixels: previousScrollMetrics.pixels,
        previousScrollExtent: previousScrollMetrics.maxScrollExtent,
      );
    } else {
      if (prepend) _isPrependingHistory = false;
      if (!prepend) _scrollToBottom(force: true);
    }
    unawaited(_refreshContextStatusForSession(agentId, sessionId));
  }

  Future<AgentToolCall?> _loadFullHistoryToolCall(
    AgentToolCall compactCall,
  ) async {
    if (!compactCall.outputTruncated && !compactCall.argumentsTruncated) {
      return compactCall;
    }
    final agentId = _activeAgentId;
    final sessionId = _activeSessionId;
    final cacheKey = _fullHistoryToolCallCacheKey(
      agentId: agentId,
      sessionId: sessionId,
      historyMessageId: compactCall.historyMessageId,
      callId: compactCall.callId,
    );
    final cached = _fullHistoryToolCallCache[cacheKey];
    if (cached != null) return cached;

    final client = await _getChatClient();
    final history = await client.getHistory(sessionId, agentId: agentId);
    if (!mounted ||
        _activeAgentId != agentId ||
        _activeSessionId != sessionId) {
      return null;
    }

    for (final item in history) {
      final historyMessageId = compactCall.historyMessageId;
      if (historyMessageId != null && item.id != historyMessageId) continue;
      final toolCalls = item.toolCalls ?? const <sdk.ToolCallInfo>[];
      for (final call in toolCalls) {
        if (call.callId != compactCall.callId) continue;
        final createdAt = _parseStoredDate(item.createdAt ?? '');
        final fullCall = _toolCallFromSdk(
          call,
          createdAt,
          historyMessageId: item.id,
        );
        _fullHistoryToolCallCache[cacheKey] = fullCall;
        if (_fullHistoryToolCallCache.length > 8) {
          _fullHistoryToolCallCache.remove(
            _fullHistoryToolCallCache.keys.first,
          );
        }
        return fullCall;
      }
    }
    return null;
  }

  String _fullHistoryToolCallCacheKey({
    required String agentId,
    required String sessionId,
    required String? historyMessageId,
    required String callId,
  }) {
    return '$agentId::$sessionId::${historyMessageId ?? ''}::$callId';
  }

  void _preserveScrollOffsetAfterPrepend({
    required double previousPixels,
    required double previousScrollExtent,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        if (mounted) setState(() => _isPrependingHistory = false);
        return;
      }
      final position = _scrollController.position;
      if (!position.hasContentDimensions) {
        if (mounted) setState(() => _isPrependingHistory = false);
        return;
      }
      final delta = position.maxScrollExtent - previousScrollExtent;
      if (delta <= 0) {
        if (mounted) setState(() => _isPrependingHistory = false);
        return;
      }
      final target = (previousPixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      _isProgrammaticScrollInFlight = true;
      _scrollController.jumpTo(target);
      _isProgrammaticScrollInFlight = false;
      if (mounted) {
        setState(() => _isPrependingHistory = false);
      } else {
        _isPrependingHistory = false;
      }
    });
  }

  Future<sdk.ContextStatus?> _loadContextStatusForSession(
    String agentId,
    String sessionId,
  ) async {
    final cacheKey = _sessionCacheKey(agentId, sessionId);
    final sdkSession = _sdkSessions[cacheKey];
    if (sdkSession == null) {
      return null;
    }
    if (_contextStatusLoading.contains(cacheKey)) {
      return _contextStatuses[cacheKey];
    }
    if (mounted) {
      setState(() => _contextStatusLoading.add(cacheKey));
    }
    try {
      final client = await _getChatClient();
      final status = await client
          .contextStatus(sdkSession.threadId, agentId: agentId)
          .timeout(_contextStatusRefreshTimeout);
      if (!mounted) return status;
      setState(() => _contextStatuses[cacheKey] = status);
      return status;
    } catch (_) {
      // Context telemetry is diagnostic; chat should keep working if it fails.
      return _contextStatuses[cacheKey];
    } finally {
      if (mounted) {
        setState(() => _contextStatusLoading.remove(cacheKey));
      }
    }
  }

  Future<void> _refreshContextStatusForSession(
    String agentId,
    String sessionId,
  ) async {
    await _loadContextStatusForSession(agentId, sessionId);
  }

  Future<void> _refreshActiveContextStatus() {
    return _refreshContextStatusForSession(_activeAgentId, _activeSessionId);
  }

  Future<bool> _compactActiveContext() async {
    final agentId = _activeAgentId;
    final sessionId = _activeSessionId;
    final cacheKey = _sessionCacheKey(agentId, sessionId);
    final sdkSession = _sdkSessions[cacheKey];
    if (sdkSession == null || _contextStatusLoading.contains(cacheKey)) {
      return false;
    }
    _showContextCompactingNotice(
      agentId,
      sessionId,
      _contextStatuses[cacheKey]?.usagePercent ?? 0,
      strategy: _contextStatuses[cacheKey]?.compactionStrategy ?? 'llm_summary',
    );
    setState(() => _contextStatusLoading.add(cacheKey));
    try {
      final client = await _getChatClient();
      final status = await client.compactContext(
        sdkSession,
        agentId: agentId,
        focus: 'Manual compact from the Flutter demo context status bar.',
      );
      if (!mounted) return false;
      setState(() => _contextStatuses[cacheKey] = status);
      _showContextCompactedNotice(
        agentId,
        sessionId,
        tokensBefore: status.tokensBefore,
        tokensAfter: status.tokensAfter,
        strategy: status.compactionStrategy,
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      _showContextCompactionFailedNotice(agentId, sessionId, error);
      _showChatSnackBar(_friendlyDisplayError(error));
      return false;
    } finally {
      if (mounted) {
        setState(() => _contextStatusLoading.remove(cacheKey));
      }
    }
  }

  void _showContextCompactingNotice(
    String agentId,
    String sessionId,
    double usagePercent, {
    required String strategy,
  }) {
    final cacheKey = _sessionCacheKey(agentId, sessionId);
    _setContextCompactionNotice(
      cacheKey,
      _ContextCompactionNotice.compacting(
        usagePercent: usagePercent,
        strategy: strategy,
      ),
    );
  }

  void _showContextCompactedNotice(
    String agentId,
    String sessionId, {
    required int tokensBefore,
    required int tokensAfter,
    int turnsRemoved = 0,
    String? strategy,
  }) {
    final cacheKey = _sessionCacheKey(agentId, sessionId);
    final previous = _contextCompactionNotices[cacheKey];
    _setContextCompactionNotice(
      cacheKey,
      _ContextCompactionNotice.compacted(
        tokensBefore: tokensBefore,
        tokensAfter: tokensAfter,
        turnsRemoved: turnsRemoved,
        strategy: strategy ?? previous?.strategy ?? 'llm_summary',
      ),
      hideAfter: const Duration(seconds: 5),
    );
  }

  void _showContextCompactionFailedNotice(
    String agentId,
    String sessionId,
    Object error,
  ) {
    final cacheKey = _sessionCacheKey(agentId, sessionId);
    final previous = _contextCompactionNotices[cacheKey];
    _setContextCompactionNotice(
      cacheKey,
      _ContextCompactionNotice.failed(
        message: _friendlyDisplayError(error),
        strategy: previous?.strategy ?? 'llm_summary',
      ),
      hideAfter: const Duration(seconds: 6),
    );
  }

  void _setContextCompactionNotice(
    String cacheKey,
    _ContextCompactionNotice notice, {
    Duration? hideAfter,
  }) {
    _contextCompactionHideTimers.remove(cacheKey)?.cancel();
    if (!mounted) return;
    setState(() => _contextCompactionNotices[cacheKey] = notice);
    if (hideAfter == null) return;
    _contextCompactionHideTimers[cacheKey] = Timer(hideAfter, () {
      if (!mounted) return;
      final current = _contextCompactionNotices[cacheKey];
      if (current?.updatedAt != notice.updatedAt) return;
      setState(() {
        _contextCompactionNotices.remove(cacheKey);
        _contextCompactionHideTimers.remove(cacheKey);
      });
    });
  }

  void _handleContextStatusTap() {
    final status = _activeContextStatus;
    if (status != null) {
      _showContextStatusDetails(
        context,
        status,
        onConfigure: () => unawaited(_openActiveContextModelConfig()),
        onCompact: () => unawaited(_compactActiveContext()),
      );
      return;
    }
    if (!_isActiveContextStatusLoading) {
      unawaited(_refreshActiveContextStatus());
    }
  }

  bool _hasLiveSessionRun(String sessionId) {
    final run = _sessionRuns[sessionId];
    return run != null && !run.isTerminal;
  }

  @override
  bool get _usesInjectedChatClient => widget.chatClientFactory != null;

  void _handleConfigChanged(LlmConfigState config) {
    _configRevision += 1;
    setState(() {
      _config = config;
      _sessions = _sessions.map(_refreshWelcomeMessage).toList();
    });
    unawaited(_persistConfig(config));
  }

  Future<void> _restorePersistedState() async {
    final revision = _configRevision;
    try {
      final profiles = await widget.configStore.loadProfiles();
      final selection = await widget.configStore.loadSelection();
      final preferences = await SharedPreferences.getInstance();
      final restoredScenarioId = _normalizeDemoScenarioId(
        preferences.getString(_activeScenarioKey),
      );
      final restoredDeveloperEngineId =
          preferences.getString(_activeDeveloperEngineKey) ??
          _defaultDeveloperEngineId;
      final restoredRuntimeProfile = _scenarioRuntimeProfileFor(
        restoredScenarioId,
        developerEngineId: restoredDeveloperEngineId,
      );
      final restoredGitSettings = await _loadDemoGitSettings();
      final restoredProfiles = <LlmModelProfile>[];
      for (final profile in profiles) {
        final apiKey = await widget.configStore.readApiKey(profile.id);
        restoredProfiles.add(_profileFromStoredProfile(profile, apiKey));
      }
      final restoredConfig = LlmConfigState(
        profiles: List.unmodifiable(restoredProfiles),
        selectedProfileId: selection.selectedProfileId,
        selectedProfileIdByCapability: _capabilitySelectionFromStored(
          selection,
        ),
        systemPrompt: selection.systemPrompt.trim().isNotEmpty
            ? selection.systemPrompt.trim()
            : restoredProfiles
                  .map((profile) => profile.systemPrompt.trim())
                  .firstWhere((prompt) => prompt.isNotEmpty, orElse: () => ''),
        maxToolIterations: selection.maxToolIterations,
      );
      if (!mounted || revision != _configRevision) return;
      setState(() {
        _config = restoredConfig;
        _activeScenarioId = restoredRuntimeProfile.scenarioId;
        _activeDeveloperEngineId = restoredRuntimeProfile.activeEngineId;
        _activeAgentId = restoredRuntimeProfile.agentId;
        if (!restoredRuntimeProfile.supportsAgents) {
          _agents = [restoredRuntimeProfile.primaryAgent];
        }
        _gitSettings = restoredGitSettings;
        _sessions = _sessions.map(_refreshWelcomeMessage).toList();
      });
      await _refreshAgents();
      await _restoreSdkSessions(restoredConfig);
      if (!_usesInjectedChatClient) {
        await _restoreA2AConversationSessions();
      }
      _initialStateRestored = true;
      if (!_usesInjectedChatClient) {
        unawaited(_ensureConfiguredChannelsConnected());
        _scheduleA2AConnectionRestoreIfAllowed();
      }
      await _handlePendingProviderInstall();
      await _handlePendingAgentTrigger();
    } catch (_) {
      // Best-effort restore: failures should not block a fresh chat session.
      if (!_usesInjectedChatClient) {
        await _restoreA2AConversationSessions();
      }
      _initialStateRestored = true;
      if (!_usesInjectedChatClient) {
        unawaited(_ensureConfiguredChannelsConnected());
        _scheduleA2AConnectionRestoreIfAllowed();
      }
      await _handlePendingProviderInstall();
      await _handlePendingAgentTrigger();
    }
  }

  Future<void> _restoreConfigForFirstTurn() async {
    try {
      final profiles = await widget.configStore.loadProfiles();
      final selection = await widget.configStore.loadSelection();
      final restoredProfiles = <LlmModelProfile>[];
      for (final profile in profiles) {
        final apiKey = await widget.configStore.readApiKey(profile.id);
        restoredProfiles.add(_profileFromStoredProfile(profile, apiKey));
      }
      if (!mounted || restoredProfiles.isEmpty) return;
      final restoredConfig = LlmConfigState(
        profiles: List.unmodifiable(restoredProfiles),
        selectedProfileId: selection.selectedProfileId,
        selectedProfileIdByCapability: _capabilitySelectionFromStored(
          selection,
        ),
        systemPrompt: selection.systemPrompt.trim().isNotEmpty
            ? selection.systemPrompt.trim()
            : restoredProfiles
                  .map((profile) => profile.systemPrompt.trim())
                  .firstWhere((prompt) => prompt.isNotEmpty, orElse: () => ''),
        maxToolIterations: selection.maxToolIterations,
      );
      setState(() {
        _config = restoredConfig;
        _sessions = _sessions.map(_refreshWelcomeMessage).toList();
      });
    } catch (_) {
      // Keep the normal no-model prompt if the config store is unavailable.
    }
  }

  Future<void> _restoreFavoriteAttachments() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_favoriteAttachmentsKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final favorites = decoded
          .whereType<Map>()
          .map(
            (entry) =>
                FavoriteAttachment.fromMap(Map<String, Object?>.from(entry)),
          )
          .where((favorite) => favorite.id.trim().isNotEmpty)
          .toList(growable: false);
      if (!mounted) return;
      setState(
        () => _favoriteAttachments = _dedupeFavoriteAttachments(favorites),
      );
    } catch (_) {
      // Favorites are a convenience cache; ignore corrupt local state.
    }
  }

  Future<void> _persistFavoriteAttachments() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _favoriteAttachmentsKey,
      jsonEncode([
        for (final favorite in _favoriteAttachments) favorite.toMap(),
      ]),
    );
  }

  String _pinnedSessionKey(String agentId, String sessionId) {
    return _sessionCacheKey(agentId, sessionId);
  }

  bool _isSessionPinned(String agentId, String sessionId) {
    return _pinnedSessionIds.contains(_pinnedSessionKey(agentId, sessionId));
  }

  Future<void> _restorePinnedSessions() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getStringList(_pinnedSessionsKey) ?? const [];
      if (!mounted) return;
      final pinnedSessionIds = raw
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
      setState(() {
        _pinnedSessionIds = pinnedSessionIds;
        _sessions = _sessions
            .map(
              (session) => session.copyWith(
                isPinned: _isSessionPinned(_activeAgentId, session.id),
              ),
            )
            .toList();
      });
    } catch (_) {
      // Pinning is local UI state; ignore corrupt preferences.
    }
  }

  Future<void> _persistPinnedSessions() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _pinnedSessionsKey,
      _pinnedSessionIds.toList()..sort(),
    );
  }

  Future<void> _restoreAssistantAttachments() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_assistantAttachmentsKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final restored = <String, List<ChatAttachment>>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! List) continue;
        final attachments = value
            .whereType<Map>()
            .map(
              (item) => _chatAttachmentFromMap(Map<String, Object?>.from(item)),
            )
            .where(
              (attachment) =>
                  _attachmentIdentity(attachment).trim().isNotEmpty &&
                  !_hasUploadedAttachmentSandboxIdentity(attachment),
            )
            .toList(growable: false);
        if (attachments.isNotEmpty) {
          restored[entry.key.toString()] = List.unmodifiable(attachments);
        }
      }
      if (!mounted || restored.isEmpty) return;
      setState(() {
        _assistantAttachmentCache = Map.unmodifiable(restored);
        _sessions = _sessions.map(_mergeStoredAssistantAttachments).toList();
      });
    } catch (_) {
      // Assistant-generated attachment previews are local UI state.
    }
  }

  Future<void> _persistAssistantAttachments() async {
    if (_assistantAttachmentCache.isEmpty) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _assistantAttachmentsKey,
        jsonEncode({
          for (final entry in _assistantAttachmentCache.entries)
            entry.key: [
              for (final attachment in entry.value)
                _chatAttachmentToMap(attachment),
            ],
        }),
      );
    } catch (_) {
      // Attachment previews should never block the chat flow.
    }
  }

  Future<void> _restoreSeenAttachments() async {
    Map<String, Set<String>> restored = const {};
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_seenAttachmentsKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final next = <String, Set<String>>{};
          for (final entry in decoded.entries) {
            final value = entry.value;
            if (value is! List) continue;
            final ids = value
                .map((item) => item?.toString().trim() ?? '')
                .where((id) => id.isNotEmpty)
                .toSet();
            if (ids.isNotEmpty) {
              next[entry.key.toString()] = ids;
            }
          }
          restored = next;
        }
      }
    } catch (_) {
      // Seen-attachment markers are local UI state.
    }
    if (!mounted) return;
    setState(() {
      _seenAttachmentIds = Map<String, Set<String>>.from(restored);
      _seedSeenAttachmentsForExistingSessions();
      _seenAttachmentsRestored = true;
    });
    unawaited(_persistSeenAttachments());
  }

  Future<void> _persistSeenAttachments() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (_seenAttachmentIds.isEmpty) {
        await preferences.remove(_seenAttachmentsKey);
        return;
      }
      await preferences.setString(
        _seenAttachmentsKey,
        jsonEncode({
          for (final entry in _seenAttachmentIds.entries)
            entry.key: entry.value.toList(),
        }),
      );
    } catch (_) {
      // Seen-attachment markers should never block the chat flow.
    }
  }

  void _seedSeenAttachmentsForExistingSessions() {
    for (final session in _sessions) {
      final seenKey = _seenAttachmentKey(session.id);
      if (_seenAttachmentIds.containsKey(seenKey)) continue;
      final identities = _conversationAttachmentIdsFor(session);
      if (identities.isEmpty) continue;
      _seenAttachmentIds[seenKey] = identities;
    }
  }

  Set<String> _conversationAttachmentIdsFor(ChatSession session) {
    final ids = <String>{};
    for (final message in session.messages) {
      for (final attachment in message.attachments) {
        final identity = _attachmentIdentity(attachment).trim();
        if (identity.isEmpty) continue;
        ids.add(identity);
      }
    }
    return ids;
  }

  int _newAttachmentCountFor(String sessionId) {
    if (!_seenAttachmentsRestored) return 0;
    final session = _sessionById(sessionId);
    if (session == null) return 0;
    final current = _conversationAttachmentIdsFor(session);
    if (current.isEmpty) return 0;
    final seen =
        _seenAttachmentIds[_seenAttachmentKey(sessionId)] ?? const <String>{};
    var count = 0;
    for (final id in current) {
      if (!seen.contains(id)) count += 1;
    }
    return count;
  }

  ChatSession? _sessionById(String sessionId) {
    for (final session in _sessions) {
      if (session.id == sessionId) return session;
    }
    return null;
  }

  void _markActiveAttachmentsSeen(String sessionId) {
    final session = _sessionById(sessionId);
    if (session == null) return;
    final seenKey = _seenAttachmentKey(sessionId);
    final ids = _conversationAttachmentIdsFor(session);
    final previous = _seenAttachmentIds[seenKey];
    if (previous != null &&
        ids.length == previous.length &&
        ids.every(previous.contains)) {
      return;
    }
    setState(() {
      _seenAttachmentIds = {..._seenAttachmentIds, seenKey: ids};
    });
    unawaited(_persistSeenAttachments());
  }

  void _removeSeenAttachmentsForSession(String sessionId) {
    final seenKey = _seenAttachmentKey(sessionId);
    if (!_seenAttachmentIds.containsKey(seenKey)) return;
    final next = Map<String, Set<String>>.from(_seenAttachmentIds)
      ..remove(seenKey);
    _seenAttachmentIds = next;
    unawaited(_persistSeenAttachments());
  }

  String _seenAttachmentKey(String sessionId) {
    return _sessionCacheKey(_activeAgentId, sessionId);
  }

  ChatAttachment _chatAttachmentFromMap(Map<String, Object?> map) {
    final rawType = map['type'] as String? ?? ChatAttachmentType.file.name;
    return ChatAttachment(
      name: map['name'] as String? ?? 'Attachment',
      path: map['path'] as String? ?? '',
      type: rawType == ChatAttachmentType.image.name
          ? ChatAttachmentType.image
          : ChatAttachmentType.file,
      sandboxPath: map['sandbox_path'] as String?,
      mimeTypeOverride: map['mime_type'] as String?,
    );
  }

  Map<String, Object?> _chatAttachmentToMap(ChatAttachment attachment) => {
    'name': attachment.name,
    'path': attachment.path,
    'type': attachment.type.name,
    if (attachment.sandboxPath != null &&
        attachment.sandboxPath!.trim().isNotEmpty)
      'sandbox_path': attachment.sandboxPath,
    if (attachment.mimeTypeOverride != null &&
        attachment.mimeTypeOverride!.trim().isNotEmpty)
      'mime_type': attachment.mimeTypeOverride,
  };

  ChatSession _mergeStoredAssistantAttachments(ChatSession session) {
    var assistantIndex = 0;
    var didChange = false;
    var didCacheChange = false;
    final cacheUpdates = <String, List<ChatAttachment>>{};
    final messages = session.messages
        .map((message) {
          if (message.role != ChatRole.assistant || message.id == 'welcome') {
            return message;
          }
          final key = _assistantAttachmentCacheKey(
            _activeAgentId,
            session.id,
            assistantIndex++,
          );
          final stored = _assistantAttachmentCache[key] ?? const [];
          final restored = stored.isNotEmpty
              ? stored
              : _restoredGeneratedAttachmentsForMessage(message);
          if (restored.isEmpty) return message;
          if (stored.isEmpty) {
            cacheUpdates[key] = List<ChatAttachment>.unmodifiable(restored);
            didCacheChange = true;
          }
          final effectiveMerged = _mergeAttachmentLists(
            message.attachments,
            restored,
          );
          if (identical(effectiveMerged, message.attachments)) return message;
          didChange = true;
          return message.copyWith(attachments: effectiveMerged);
        })
        .toList(growable: false);
    if (didCacheChange) {
      _assistantAttachmentCache = Map.unmodifiable({
        ..._assistantAttachmentCache,
        ...cacheUpdates,
      });
      unawaited(_persistAssistantAttachments());
    }
    return didChange
        ? session.copyWith(messages: List.unmodifiable(messages))
        : session;
  }

  List<ChatAttachment> _restoredGeneratedAttachmentsForMessage(
    ChatMessage message,
  ) {
    final producedText = _generatedFileReferenceText(message);
    if (producedText.trim().isEmpty) return const [];
    final client = _chatClient;
    if (client == null) return const [];
    final files = _normalizeResolvedFiles(
      client.detectProducedFiles(producedText, agentId: _activeAgentId),
    );
    if (files.isEmpty) return const [];
    return files.map(_chatAttachmentFromResolvedFile).toList(growable: false);
  }

  Future<void> _restoreSdkSessions(LlmConfigState config) async {
    if (_isCliAgent(_activeAgentId)) {
      // CLI engines (CC/Codex) own one persistent conversation per engine and
      // restore straight from their native session store — no Rust record.
      await _restoreCliEngineSession(_activeAgentId);
      return;
    }
    final selectedProfile = config.runtimeProfileFor(
      chatProfileId: _modelProfileIdForAgent(_activeAgentId),
    );
    if (selectedProfile == null ||
        !selectedProfile.hasModel ||
        selectedProfile.apiKey.trim().isEmpty) {
      return;
    }
    final client = await _getChatClient();
    await client.configure(
      selectedProfile,
      responseLanguage: _responseLanguageCode,
    );
    final agentId = _activeAgentId;
    final sessionInfos = (await client.listSessions(
      agentId: agentId,
    )).where((info) => !_isHiddenSdkSessionInfo(info)).toList(growable: false);
    if (!mounted || sessionInfos.isEmpty) return;

    final sortedSessionInfos = [...sessionInfos]
      ..sort((a, b) {
        return _parseStoredDate(
          b.updatedAt,
        ).compareTo(_parseStoredDate(a.updatedAt));
      });
    final restoredSessions = <ChatSession>[];
    for (final info in sortedSessionInfos) {
      final sessionId = info.key.threadId;
      if (sessionId.trim().isEmpty) continue;
      _sdkSessions[_sessionCacheKey(agentId, sessionId)] = info.key;
      restoredSessions.add(
        ChatSession(
          id: sessionId,
          title: info.title,
          isPinned: _isSessionPinned(agentId, sessionId),
          createdAt: _parseStoredDate(info.createdAt),
          updatedAt: _parseStoredDate(info.updatedAt),
          messages: [_welcomeMessage(widget.language, _config)],
        ),
      );
    }
    if (restoredSessions.isEmpty) return;
    setState(() {
      _sessions = List.unmodifiable(restoredSessions);
      _activeSessionId = restoredSessions.first.id;
      _nextSessionId = _nextSessionNumber(restoredSessions);
      _editingMessageId = null;
      _inputController.clear();
    });
    await _loadSessionHistory(_activeSessionId);
    unawaited(_refreshContextStatusForSession(agentId, _activeSessionId));
  }

  bool _isCliAgent(String agentId) =>
      agentId == 'engine.cc' || agentId == 'engine.codex';

  /// Restore CLI engine sessions. CLI engines bypass the Rust session store.
  /// For Codex, conversations are pulled straight from `thread/list` (one UI
  /// session per codex thread). For CC there's no list RPC, so we fall back to
  /// a single fresh conversation.
  Future<void> _restoreCliEngineSession(String agentId) async {
    final logTag = agentId == 'engine.cc'
        ? 'napaxiCCHistory'
        : 'napaxiCodexHistory';
    debugPrint(
      '[$logTag] restoreCli start agent=$agentId active=$_activeAgentId session=$_activeSessionId',
    );
    final client = await _getChatClient();
    List<sdk.SessionInfo> sessionInfos;
    try {
      debugPrint('[$logTag] restoreCli calling listSessions agent=$agentId');
      sessionInfos = await client.listSessions(agentId: agentId);
    } catch (_) {
      sessionInfos = const [];
    }
    debugPrint(
      '[$logTag] restoreCli listed agent=$agentId sessions=${sessionInfos.length}',
    );

    // Sort newest-first by updatedAt so the most recent conversation lands on
    // top and becomes the active one.
    final sorted = [...sessionInfos]
      ..sort(
        (a, b) => _parseStoredDate(
          b.updatedAt,
        ).compareTo(_parseStoredDate(a.updatedAt)),
      );

    if (sorted.isEmpty) {
      // No persisted conversations — create one fresh placeholder session.
      final now = DateTime.now();
      final session = ChatSession(
        id: _newSessionId(),
        createdAt: now,
        updatedAt: now,
        messages: [_welcomeMessage(widget.language, _config)],
      );
      if (!mounted) return;
      setState(() {
        _activeAgentId = agentId;
        _activeSessionId = session.id;
        final hasExisting = _sessions.any((s) => s.id == session.id);
        if (!hasExisting) {
          _sessions = [session, ..._sessions];
        }
        _nextMessageId = _nextMessageNumber(_sessions);
        _editingMessageId = null;
        _inputController.clear();
      });
      debugPrint(
        '[$logTag] restoreCli empty agent=$_activeAgentId activeSession=$_activeSessionId',
      );
      return;
    }

    final restored = <ChatSession>[];
    for (final info in sorted) {
      final sessionId = info.key.threadId;
      if (sessionId.trim().isEmpty) continue;
      _sdkSessions[_sessionCacheKey(agentId, sessionId)] = info.key;
      final title = info.title.trim().isNotEmpty
          ? info.title
          : (info.preview.trim().isNotEmpty ? info.preview : '');
      restored.add(
        ChatSession(
          id: sessionId,
          title: title,
          isPinned: _isSessionPinned(agentId, sessionId),
          createdAt: _parseStoredDate(info.createdAt),
          updatedAt: _parseStoredDate(info.updatedAt),
          messages: [_welcomeMessage(widget.language, _config)],
        ),
      );
    }
    if (restored.isEmpty || !mounted) return;
    setState(() {
      _activeAgentId = agentId;
      _sessions = List.unmodifiable(restored);
      _activeSessionId = restored.first.id;
      _nextSessionId = _nextSessionNumber(restored);
      _editingMessageId = null;
      _inputController.clear();
    });
    debugPrint(
      '[$logTag] restoreCli applied agent=$_activeAgentId activeSession=$_activeSessionId restored=${restored.length}',
    );
    // History backfill may boot the CLI engine (PTY + codex app-server / node
    // bridge), which can take a while — run it in the background so the engine
    // switch stays responsive. Stale loads bail out via the active-session guard.
    unawaited(_loadSessionHistory(_activeSessionId));
  }

  Future<void> _ensureConfiguredChannelsConnected() async {
    if (!_initialStateRestored || _isEnsuringConfiguredChannels) return;
    _isEnsuringConfiguredChannels = true;
    try {
      final client = await _getChatClient();
      final capabilitySelection = _activeScenarioCapabilitySelection;
      final profile =
          _runtimeProfileForAgent(_activeAgentId) ??
          _config.selectedRuntimeProfile;
      if (profile != null &&
          profile.hasModel &&
          profile.apiKey.trim().isNotEmpty) {
        await client.configure(
          profile,
          responseLanguage: _responseLanguageCode,
          capabilitySelection: capabilitySelection,
        );
      } else {
        await client.configureForManagement(
          capabilitySelection: capabilitySelection,
        );
      }
      await client.ensureConfiguredChannelsConnected();
      await _refreshChannelInputSources();
    } catch (_) {
      // Channel recovery is best-effort. Detailed failures stay visible in
      // `/channel qqbot status` without interrupting ordinary app launch.
    } finally {
      _isEnsuringConfiguredChannels = false;
    }
  }

  Future<void> _refreshChannelInputSources() async {
    if (!_initialStateRestored) return;
    final agentId = _activeAgentId;
    final serial = ++_channelInputRefreshSerial;
    try {
      final client = await _getChatClient();
      final sources = await client.listChannelInputSources(agentId: agentId);
      if (!mounted ||
          serial != _channelInputRefreshSerial ||
          _activeAgentId != agentId) {
        return;
      }
      setState(() => _channelInputSources = sources);
    } catch (_) {
      if (!mounted ||
          serial != _channelInputRefreshSerial ||
          _activeAgentId != agentId) {
        return;
      }
      setState(() => _channelInputSources = const []);
    }
  }

  void _clearChannelInputState() {
    _channelInputLoopSerial += 1;
    _channelInputActiveAccountId = null;
    _channelInputBusyAccountId = null;
  }

  Future<void> _captureChannelInput(DemoChannelInputSource source) async {
    final accountId = source.accountId.trim();
    if (accountId.isEmpty) return;
    if (_channelInputActiveAccountId == accountId) {
      _channelInputLoopSerial += 1;
      setState(() => _channelInputActiveAccountId = null);
      _showChatSnackBar(
        _channelText(
          context,
          zh: '语音输入将在当前识别结束后停止',
          en: 'Voice input will stop after the current capture.',
        ),
      );
      return;
    }
    if (_channelInputBusyAccountId != null) return;
    final loopSerial = ++_channelInputLoopSerial;
    setState(() {
      _channelInputActiveAccountId = accountId;
      _channelInputBusyAccountId = accountId;
    });
    _inputFocusNode.unfocus();
    _showChatSnackBar(
      _channelText(
        context,
        zh: '连续语音已开启，请对 ${source.label} 说话',
        en: 'Continuous voice input is on for ${source.label}.',
      ),
    );
    try {
      final client = await _getChatClient();
      while (mounted &&
          _channelInputLoopSerial == loopSerial &&
          _channelInputActiveAccountId == accountId) {
        if (_channelInputBusyAccountId != accountId) {
          setState(() => _channelInputBusyAccountId = accountId);
        }
        final result = await client.captureHeadsetTranscript(
          accountId: accountId,
          agentId: _activeAgentId,
        );
        if (!mounted || _channelInputLoopSerial != loopSerial) return;
        final transcript = result.transcript?.trim() ?? '';
        final failed =
            !result.accepted || (result.error?.trim().isNotEmpty == true);
        if (failed) {
          _showChatSnackBar(
            result.error?.trim().isNotEmpty == true
                ? result.error!.trim()
                : _channelText(
                    context,
                    zh: '语音输入未完成',
                    en: 'Voice input did not complete',
                  ),
          );
          break;
        }
        _showChatSnackBar(
          transcript.isEmpty
              ? _channelText(
                  context,
                  zh: '语音已发送，正在继续听',
                  en: 'Voice sent. Listening again.',
                )
              : _channelText(
                  context,
                  zh: '已识别：$transcript',
                  en: 'Heard: $transcript',
                ),
        );
        unawaited(_refreshChannelInputSources());
        if (_channelInputActiveAccountId != accountId) break;
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
    } catch (error) {
      if (!mounted) return;
      _showChatSnackBar(_friendlyDisplayError(error));
    } finally {
      if (mounted) {
        if (_channelInputLoopSerial == loopSerial) {
          setState(() {
            _channelInputActiveAccountId = null;
            _channelInputBusyAccountId = null;
          });
        } else if (_channelInputBusyAccountId == accountId &&
            _channelInputActiveAccountId != accountId) {
          setState(() => _channelInputBusyAccountId = null);
        }
      }
    }
  }

  Future<void> _refreshAgents() async {
    final runtimeProfile = _activeRuntimeProfile;
    if (!runtimeProfile.supportsAgents) {
      if (!mounted) return;
      setState(() {
        _agents = [runtimeProfile.primaryAgent];
        _activeAgentId = runtimeProfile.agentId;
        _channelInputSources = const [];
        _clearChannelInputState();
      });
      unawaited(_refreshChannelInputSources());
      return;
    }
    try {
      final client = await _getChatClient();
      final agents = await client.listAgents();
      final visibleAgents = _visibleAgentsForRuntimeProfile(
        runtimeProfile,
        agents,
      );
      if (!mounted) return;
      setState(() {
        _agents = visibleAgents.isEmpty
            ? const [_defaultDemoAgent]
            : visibleAgents;
        if (!_agents.any((agent) => agent.id == _activeAgentId)) {
          _activeAgentId = sdk.NapaxiEngine.defaultAgentId;
          _channelInputSources = const [];
          _clearChannelInputState();
        }
      });
      unawaited(_refreshChannelInputSources());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _agents = const [_defaultDemoAgent];
        _channelInputSources = const [];
        _clearChannelInputState();
      });
    }
  }

  Future<void> _handlePendingAgentTrigger() async {
    if (!_initialStateRestored) return;
    if (!_activeRuntimeProfile.supportsAgents) return;
    if (_isHandlingAgentTrigger) return;
    _isHandlingAgentTrigger = true;
    try {
      final client = await _getChatClient();
      final accepted = await client.consumePendingAgentTrigger();
      if (accepted == null || !mounted) return;
      await _refreshAgents();
      if (!mounted) return;
      final agentId = accepted.request.agentId;
      if (!_agents.any((agent) => agent.id == agentId)) {
        setState(() {
          _agents = List.unmodifiable([
            ..._agents,
            DemoAgent(
              id: agentId,
              name: accepted.displayName,
              icon: Icons.sensors_rounded,
            ),
          ]);
        });
      }
      await _openFreshTriggeredSession(agentId);
      if (!mounted) return;
      final source = accepted.request.source.trim().isEmpty
          ? accepted.displayName
          : accepted.request.source;
      _showSnackBar('来自 $source');
      await _startNewSessionTurn(accepted.request.message, const []);
    } catch (error) {
      if (mounted) {
        _showSnackBar('App-to-Agent trigger failed: $error');
      }
    } finally {
      _isHandlingAgentTrigger = false;
    }
  }

  Future<void> _handlePendingProviderInstall() async {
    if (!_initialStateRestored) return;
    if (!_activeRuntimeProfile.supportsAgents) return;
    if (_isHandlingProviderInstall) return;
    _isHandlingProviderInstall = true;
    try {
      final client = await _getChatClient();
      final agent = await client.installPendingAgentProvider();
      if (agent == null || !mounted) return;
      await _refreshAgents();
      if (!mounted) return;
      if (!_agents.any((candidate) => candidate.id == agent.id)) {
        setState(() {
          _agents = List.unmodifiable([..._agents, agent]);
        });
      }
      await _selectAgent(agent.id);
      if (!mounted) return;
      _showSnackBar(
        'Installed ${agent.name}. Tap the provider button again to trigger Agent.',
      );
    } catch (error) {
      if (mounted) {
        _showSnackBar('Provider install failed: $error');
      }
    } finally {
      _isHandlingProviderInstall = false;
    }
  }

  Future<void> _openFreshTriggeredSession(String agentId) async {
    if (_activeAgentId != agentId) {
      await _selectAgent(agentId);
    }
    if (!mounted) return;
    for (final run in _sessionRuns.values) {
      await run.subscription.cancel();
    }
    _sessionRuns.clear();
    final now = DateTime.now();
    final sessionId = _newSessionId();
    setState(() {
      _activeAgentId = agentId;
      _activeSessionId = sessionId;
      _channelInputSources = const [];
      _clearChannelInputState();
      _sessions = [
        ChatSession(
          id: sessionId,
          createdAt: now,
          updatedAt: now,
          messages: [_welcomeMessage(widget.language, _config)],
        ),
      ];
      _nextMessageId = _nextMessageNumber(_sessions);
      _editingMessageId = null;
      _inputController.clear();
    });
  }

  Future<void> _persistConfig(LlmConfigState config) async {
    final existingProfiles = await widget.configStore.loadProfiles();
    final nextProfileIds = config.profiles.map((profile) => profile.id).toSet();
    for (final profile in existingProfiles) {
      if (!nextProfileIds.contains(profile.id)) {
        await widget.configStore.deleteProfile(profile.id);
      }
    }
    for (final profile in config.profiles) {
      await widget.configStore.saveProfile(
        _storedProfileFromProfile(profile),
        apiKey: profile.apiKey.trim(),
      );
    }
    await widget.configStore.saveSelection(_storedSelectionFromConfig(config));
  }

  void _updateSessionRun(
    String sessionId,
    ChatSessionRunState Function(ChatSessionRunState run) update,
  ) {
    if (!mounted) return;
    setState(() {
      final run = _sessionRuns[sessionId];
      if (run == null) return;
      _sessionRuns[sessionId] = update(run);
    });
  }

  void _finishSessionRun(
    String sessionId,
    String? messageId, {
    required sdk.SessionRunStatus status,
    required String activity,
    String? error,
    bool clearPendingInterjections = false,
  }) {
    if (!mounted) return;
    setState(() {
      final run = _sessionRuns[sessionId];
      if (run == null) return;
      final unread = sessionId != _activeSessionId;
      final deferredInterjections = run.pendingInterjections
          .where((item) => !item.retractsFromSdk)
          .toList(growable: false);
      _sessionRuns[sessionId] = run.copyWith(
        status: status,
        activity: activity,
        unread: unread || run.unread,
        error: error,
        clearError: error == null,
        updatedAt: DateTime.now(),
        clearPendingHumanRequest: true,
        clearPendingHumanMessage: true,
        pendingInterjections: clearPendingInterjections
            ? const []
            : List.unmodifiable(deferredInterjections),
      );
    });
    if (messageId != null) {
      _completeAssistantMessage(messageId);
    }
  }

  String _migrateLiveSessionId({
    required String agentId,
    required String oldSessionId,
    required sdk.SessionKey sessionKey,
  }) {
    final nextSessionId = sessionKey.threadId.trim();
    if (nextSessionId.isEmpty || nextSessionId == oldSessionId) {
      _sdkSessions[_sessionCacheKey(agentId, oldSessionId)] = sessionKey;
      return oldSessionId;
    }

    final oldSdkCacheKey = _sessionCacheKey(agentId, oldSessionId);
    final nextSdkCacheKey = _sessionCacheKey(agentId, nextSessionId);
    final oldPinnedKey = _pinnedSessionKey(agentId, oldSessionId);
    final nextPinnedKey = _pinnedSessionKey(agentId, nextSessionId);
    final wasPinned = _pinnedSessionIds.contains(oldPinnedKey);
    final assistantPrefix = '$agentId::$oldSessionId::';
    var didMoveAssistantCache = false;

    setState(() {
      _sessions = _sessions.map((session) {
        if (session.id != oldSessionId) return session;
        return session.copyWith(
          id: nextSessionId,
          isPinned: wasPinned || _isSessionPinned(agentId, nextSessionId),
        );
      }).toList();
      if (_activeSessionId == oldSessionId) {
        _activeSessionId = nextSessionId;
      }

      _sdkSessions.remove(oldSdkCacheKey);
      _sdkSessions[nextSdkCacheKey] = sessionKey;
      final contextStatus = _contextStatuses.remove(oldSdkCacheKey);
      if (contextStatus != null) {
        _contextStatuses[nextSdkCacheKey] = contextStatus;
      }
      _contextStatusLoading.remove(oldSdkCacheKey);

      final run = _sessionRuns.remove(oldSessionId);
      if (run != null) _sessionRuns[nextSessionId] = run;

      final pending = _pendingAssistantAttachments[oldSessionId];
      if (pending != null) {
        _pendingAssistantAttachments = Map.unmodifiable({
          for (final entry in _pendingAssistantAttachments.entries)
            if (entry.key != oldSessionId) entry.key: entry.value,
          nextSessionId: pending,
        });
      }

      if (_stoppingSessionIds.remove(oldSessionId)) {
        _stoppingSessionIds.add(nextSessionId);
      }

      _pinnedSessionIds = {
        for (final key in _pinnedSessionIds)
          if (key != oldPinnedKey) key,
        if (wasPinned) nextPinnedKey,
      };

      _assistantAttachmentCache = Map.unmodifiable({
        for (final entry in _assistantAttachmentCache.entries)
          if (entry.key.startsWith(assistantPrefix))
            '$agentId::$nextSessionId::${entry.key.substring(assistantPrefix.length)}':
                entry.value
          else
            entry.key: entry.value,
      });
      didMoveAssistantCache = _assistantAttachmentCache.keys.any(
        (key) => key.startsWith('$agentId::$nextSessionId::'),
      );
    });

    if (wasPinned) unawaited(_persistPinnedSessions());
    if (didMoveAssistantCache) unawaited(_persistAssistantAttachments());
    return nextSessionId;
  }

  Future<void> _sendMessage(
    List<ChatAttachment> attachments, {
    List<String> pinnedSkillNames = const [],
  }) async {
    final text = _inputController.text.trim();
    if (text.isEmpty && attachments.isEmpty) return;
    if (!_initialStateRestored) await _restoreConfigForFirstTurn();
    if (await _handleSlashCommand(text, attachments)) return;
    await _ensureA2AConnectionReadyForUserTurn();

    // Prepend /skill_name mentions for pinned skills so the engine
    // activates them explicitly on this turn. The display text (shown in
    // the user message bubble) remains the original user input.
    final effectiveText = pinnedSkillNames.isEmpty
        ? text
        : '${pinnedSkillNames.map((n) => '/$n').join(' ')} $text';

    final activeRun = _activeRun;
    _traceChat(
      'send pressed session=$_activeSessionId active=${activeRun?.status.name ?? 'none'} '
      'text="${_tracePreview(text)}"',
    );
    if (activeRun != null && !activeRun.isTerminal) {
      if (_shouldSendAfterActiveRun(activeRun)) {
        _traceChat(
          'route=defer-new-turn session=$_activeSessionId '
          'assistant=${activeRun.assistantMessageId}',
        );
        await _sendAfterActiveRun(
          effectiveText,
          attachments,
          displayText: text,
          pinnedSkillNames: pinnedSkillNames,
        );
        return;
      }
      _traceChat(
        'route=inject-running session=$_activeSessionId '
        'assistant=${activeRun.assistantMessageId}',
      );
      await _sendRunningMessage(effectiveText, attachments);
      return;
    }
    _traceChat('route=new-turn session=$_activeSessionId');
    await _startNewSessionTurn(
      effectiveText,
      attachments,
      displayText: text,
      pinnedSkillNames: pinnedSkillNames,
    );
  }

  Future<bool> _handleSlashCommand(
    String text,
    List<ChatAttachment> attachments,
  ) async {
    final invocation = _SlashCommandInvocation.parse(
      text,
      _availableSlashCommands,
    );
    if (invocation == null) return false;

    setState(() {
      _editingMessageId = null;
      _inputController.clear();
    });

    if (!invocation.isKnown) {
      _appendSlashCommandResult(
        text,
        '未知命令 `${invocation.rawCommand}`。\n\n${_slashHelpMessage()}',
      );
      return true;
    }

    if (invocation.command.isSkillCommand) {
      final client = await _getChatClient();
      final sessionKey = _sdkSessions[_activeSessionCacheKey];
      final commandName = invocation.command.name.replaceFirst('/', '');
      final run = await client.runSkillCommand(
        commandName,
        agentId: _activeAgentId,
        args: invocation.arguments.isEmpty ? null : invocation.arguments,
        sessionKey: sessionKey,
      );
      if (!run.success || run.message == null || run.message!.trim().isEmpty) {
        _appendSlashCommandResult(
          text,
          run.error ?? '技能命令 `${invocation.command.name}` 暂不可用。',
        );
        return true;
      }
      await _startNewSessionTurn(run.message!.trim(), attachments);
      return true;
    }

    switch (invocation.command.name) {
      case '/help':
        _appendSlashCommandResult(text, _slashHelpMessage());
        return true;
      case '/status':
        _appendSlashCommandResult(text, _slashStatusMessage());
        return true;
      case '/context':
        await _refreshActiveContextStatus();
        _appendSlashCommandResult(text, _slashContextMessage());
        return true;
      case '/compact':
        if (_activeRun != null && !_activeRun!.isTerminal) {
          _appendSlashCommandResult(text, '当前回复还在运行中。请先使用 `/stop` 停止，再压缩上下文。');
          return true;
        }
        final didCompact = await _compactActiveContext();
        final status = _activeContextStatus;
        final summary = status == null
            ? '当前会话还没有可压缩的上下文。'
            : _slashContextMessage(title: didCompact ? '上下文已压缩' : '上下文压缩未完成');
        _appendSlashCommandResult(text, summary);
        return true;
      case '/stop':
        final run = _activeRun;
        if (run == null || run.isTerminal) {
          _appendSlashCommandResult(text, '当前没有正在运行的回复。');
          return true;
        }
        await _stopActiveSend();
        _appendSlashCommandResult(text, '已停止当前回复。');
        return true;
      case '/new':
        _startNewSession();
        _showChatSnackBar('已创建新会话');
        return true;
      case '/model':
        _appendSlashCommandResult(text, '正在打开模型设置。');
        await _openConfigPage();
        return true;
      case '/tools':
        _appendSlashCommandResult(text, _slashToolsMessage());
        return true;
      case '/tasks':
        _appendSlashCommandResult(text, _slashTasksMessage());
        return true;
      case '/a2a':
        await _handleA2ASlashCommand(text, invocation.arguments);
        return true;
      case '/channel':
        await _handleChannelSlashCommand(text, invocation.arguments);
        return true;
    }

    return false;
  }

  @override
  void _appendSlashCommandResult(String command, String content) {
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
              id: 'user-${_nextMessageId++}',
              role: ChatRole.user,
              content: command,
              createdAt: now,
            ),
            ChatMessage(
              id: 'assistant-${_nextMessageId++}',
              role: ChatRole.assistant,
              content: content,
              createdAt: now,
              completedAt: now,
            ),
          ]),
        );
      }).toList();
    });
    _inputFocusNode.unfocus();
    _scrollToBottom(force: true);
  }

  String _slashHelpMessage() {
    final lines = _availableSlashCommands
        .map((command) {
          final aliasText = command.aliases.isEmpty
              ? ''
              : ' (${command.aliases.join(', ')})';
          return '- `${command.name}`$aliasText：${command.description}';
        })
        .join('\n');
    return '**斜杠命令**\n$lines';
  }

  String _slashStatusMessage() {
    final agent = _activeAgent.label(widget.language);
    final profile = _runtimeProfileForAgent(_activeAgentId);
    final model = profile == null
        ? '未选择'
        : profile.hasModel
        ? profile.displayName
        : '未选择模型';
    final run = _activeRun;
    final runStatus = run == null || run.isTerminal
        ? '空闲'
        : _sessionRunStatusLabel(run.status);
    return [
      '**当前状态**',
      '- Agent：$agent',
      '- 模型：$model',
      '- 运行：$runStatus',
      '- 上下文：${_slashContextInline()}',
    ].join('\n');
  }

  String _slashContextMessage({String title = '上下文'}) {
    final status = _activeContextStatus;
    if (status == null) {
      return '**$title**\n当前会话还没有上下文数据。发送消息后可查看。';
    }
    return [
      '**$title**',
      '- 有效预算：${_formatContextTokens(status.effectiveContextWindowTokens)}',
      '- 当前窗口：${_formatContextTokens(status.currentWindowTokens)}',
      '- 会话记录：${_formatContextTokens(status.transcriptEstimatedTokens)}',
      '- 剩余：${_formatContextPercent(_contextRemainingPercent(status))}',
    ].join('\n');
  }

  String _slashContextInline() {
    final status = _activeContextStatus;
    if (status == null) return '暂无数据';
    return '当前窗口 ${_formatContextTokens(status.currentWindowTokens)}/${_formatContextTokens(status.effectiveContextWindowTokens)}，会话记录 ${_formatContextTokens(status.transcriptEstimatedTokens)}';
  }

  String _slashToolsMessage() {
    return [
      '**工具入口**',
      '- 文件：右上角文件夹查看会话文件，输入框 `+` 可添加附件。',
      '- 浏览器：当 Agent 使用网页工具时，会在当前会话内打开浏览面板。',
      '- 平台动作：外部 Agent/provider 的动作会继续走宿主确认和能力准入。',
      '',
      '更底层的工具 schema、MCP、插件管理不放在移动端斜杠命令里。',
    ].join('\n');
  }

  String _slashTasksMessage() {
    final activeRuns = _sessionRuns.entries
        .where((entry) => !entry.value.isTerminal)
        .toList();
    if (activeRuns.isEmpty) {
      return '**任务**\n当前没有正在运行的任务。';
    }
    final lines = activeRuns
        .map((entry) {
          final run = entry.value;
          final pending = run.pendingInterjections.length;
          final pendingText = pending == 0 ? '' : '，等待消息 $pending 条';
          return '- `${entry.key}`：${_sessionRunStatusLabel(run.status)}$pendingText';
        })
        .join('\n');
    return '**任务**\n$lines';
  }

  @override
  String _compactMiddle(String value) {
    if (value.length <= 18) return value;
    return '${value.substring(0, 8)}...${value.substring(value.length - 8)}';
  }

  String _sessionRunStatusLabel(sdk.SessionRunStatus status) {
    return switch (status) {
      sdk.SessionRunStatus.running => '运行中',
      sdk.SessionRunStatus.waitingForInput => '等待输入',
      sdk.SessionRunStatus.cancelling => '停止中',
      sdk.SessionRunStatus.completed => '已完成',
      sdk.SessionRunStatus.failed => '失败',
      sdk.SessionRunStatus.cancelled => '已取消',
    };
  }

  bool _shouldSendAfterActiveRun(ChatSessionRunState run) {
    if (run.needsInput) return false;
    final assistant = _messageByIdInSession(
      _activeSessionId,
      run.assistantMessageId,
    );
    return assistant != null && assistant.content.trim().isNotEmpty;
  }

  Future<void> _sendAfterActiveRun(
    String text,
    List<ChatAttachment> attachments, {
    String? displayText,
    List<String> pinnedSkillNames = const [],
  }) async {
    final sessionId = _activeSessionId;
    final interjection = PendingInterjection(
      id: 'interjection-${_nextInterjectionId++}',
      content: text,
      attachments: List.unmodifiable(attachments),
      attachmentCount: attachments.length,
      createdAt: DateTime.now(),
      retractsFromSdk: false,
    );
    setState(() {
      _editingMessageId = null;
      _inputController.clear();
    });
    _updateSessionRun(
      sessionId,
      (run) => run.copyWith(
        activity: 'Queued message',
        pendingInterjections: List.unmodifiable([
          ...run.pendingInterjections,
          interjection,
        ]),
      ),
    );
    _inputFocusNode.unfocus();
    _scrollToBottom(force: true);
    _traceChat('defer wait session=$sessionId text="${_tracePreview(text)}"');
    while (mounted) {
      final run = _sessionRuns[sessionId];
      if (run == null || run.isTerminal) break;
      if (!run.pendingInterjections.any((item) => item.id == interjection.id)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!mounted || _activeSessionId != sessionId) return;
    final run = _sessionRuns[sessionId];
    if (run != null &&
        !run.pendingInterjections.any((item) => item.id == interjection.id)) {
      return;
    }
    _removePendingInterjection(sessionId, interjection.id);
    _traceChat('defer flush session=$sessionId text="${_tracePreview(text)}"');
    await _startNewSessionTurn(
      text,
      attachments,
      displayText: displayText,
      pinnedSkillNames: pinnedSkillNames,
    );
  }

  ChatMessage? _messageByIdInSession(String sessionId, String messageId) {
    for (final session in _sessions) {
      if (session.id != sessionId) continue;
      for (final message in session.messages) {
        if (message.id == messageId) return message;
      }
    }
    return null;
  }

  Future<void> _startNewSessionTurn(
    String text,
    List<ChatAttachment> attachments, {
    String? displayText,
    List<String> pinnedSkillNames = const [],
  }) async {
    final strings = AppStrings.of(context);
    final now = DateTime.now();
    final activeSession = _activeSession;
    var sessionId = activeSession.id;
    final assistantMessageId = 'assistant-${_nextMessageId++}';
    final agentId = _activeAgentId;
    final isCliEngine = agentId == 'engine.cc' || agentId == 'engine.codex';
    final agentModelProfileId = _modelProfileIdForAgent(agentId);
    final selectedProfile = _runtimeProfileForAgent(agentId);
    final hasChatModel = selectedProfile?.hasModel ?? false;
    _traceChat(
      'start turn session=$sessionId assistant=$assistantMessageId agent=$agentId '
      'text="${_tracePreview(text)}"',
    );
    if (agentModelProfileId != null &&
        _config.profileById(agentModelProfileId) == null) {
      _showMissingAgentModel(agentModelProfileId);
    }
    final nextMessages = [
      ...activeSession.messages,
      ChatMessage(
        id: 'user-${_nextMessageId++}',
        role: ChatRole.user,
        content: displayText ?? text,
        attachments: attachments,
        pinnedSkillNames: pinnedSkillNames,
        createdAt: now,
      ),
      ChatMessage(
        id: assistantMessageId,
        role: ChatRole.assistant,
        content: isCliEngine
            ? ''
            : selectedProfile == null || !hasChatModel
            ? strings.chooseChatModelToChat
            : selectedProfile.apiKey.trim().isEmpty
            ? strings.configureModelToChat
            : '',
        action: isCliEngine
            ? null
            : selectedProfile == null ||
                  !hasChatModel ||
                  selectedProfile.apiKey.trim().isEmpty
            ? ChatMessageAction.openConfiguration
            : null,
        createdAt: now,
        isStreaming:
            isCliEngine ||
            (selectedProfile != null &&
                hasChatModel &&
                selectedProfile.apiKey.trim().isNotEmpty),
      ),
    ];

    setState(() {
      _pendingAssistantAttachments = Map.unmodifiable({
        for (final entry in _pendingAssistantAttachments.entries)
          if (entry.key != sessionId) entry.key: entry.value,
      });
      _sessions = _sessions.map((session) {
        if (session.id != sessionId) return session;
        return session.copyWith(
          title: session.title.isEmpty && text.isNotEmpty ? text : null,
          updatedAt: now,
          messages: List.unmodifiable(nextMessages),
        );
      }).toList();
      _editingMessageId = null;
      _inputController.clear();
    });

    _inputFocusNode.unfocus();
    _scrollToBottom(force: true);

    if (!isCliEngine &&
        (selectedProfile == null ||
            !hasChatModel ||
            selectedProfile.apiKey.trim().isEmpty)) {
      return;
    }

    try {
      final client = await _getChatClient();
      if (!isCliEngine) {
        await client.configure(
          selectedProfile!,
          responseLanguage: _responseLanguageCode,
        );
        try {
          await client.localA2AStatus();
        } catch (error) {
          debugPrint('A2A status probe skipped: $error');
        }
        _listenForBackgroundActions(client);
        await _prepareBackgroundRunFeedback(client);
      }
      final sdk.SessionKey session;
      if (isCliEngine) {
        // CLI bridges (CC/Codex) manage their own sessions through PTY.
        // Create a synthetic SessionKey so downstream fields are type-correct.
        session = sdk.SessionKey(
          channelType: 'cli',
          accountId: agentId,
          threadId: activeSession.id,
        );
      } else {
        session = await _getSdkSession(client, activeSession.id, agentId);
        if (!mounted) return;
        sessionId = _migrateLiveSessionId(
          agentId: agentId,
          oldSessionId: sessionId,
          sessionKey: session,
        );
        unawaited(_refreshContextStatusForSession(agentId, sessionId));
      }
      final sdkAttachments = await _toSdkAttachments(attachments);
      if (!mounted) return;

      // Codex only knows the real thread id once thread/start responds. For a
      // brand-new conversation the UI sent a placeholder id; migrate it to the
      // real id (and move the live run with it) the moment codex reports it.
      void Function(String)? onNativeThreadId;
      if (isCliEngine && agentId == 'engine.codex') {
        onNativeThreadId = (String nativeThreadId) {
          if (!mounted) return;
          final newKey = sdk.SessionKey(
            channelType: 'cli',
            accountId: agentId,
            threadId: nativeThreadId,
          );
          sessionId = _migrateLiveSessionId(
            agentId: agentId,
            oldSessionId: sessionId,
            sessionKey: newKey,
          );
          unawaited(_refreshContextStatusForSession(agentId, sessionId));
        };
      }

      var currentAssistantMessageId = assistantMessageId;
      var sawResponseDelta = false;
      late final StreamSubscription<sdk.ChatEvent> subscription;
      subscription = client
          .sendToSession(
            session,
            text,
            agentId: agentId,
            attachments: sdkAttachments,
            maxIterations: _config.maxToolIterations,
            onNativeThreadId: onNativeThreadId,
          )
          .listen(
            (event) {
              if (!mounted) return;
              void markRun({
                sdk.SessionRunStatus status = sdk.SessionRunStatus.running,
                String activity = 'Running',
                String? pendingHumanRequestId,
                String? pendingHumanMessageId,
                bool clearPendingHuman = true,
                String? error,
              }) {
                _updateSessionRun(sessionId, (run) {
                  return run.copyWith(
                    assistantMessageId: currentAssistantMessageId,
                    status: status,
                    activity: activity,
                    pendingHumanRequestId: pendingHumanRequestId,
                    pendingHumanMessageId: pendingHumanMessageId,
                    clearPendingHumanRequest: clearPendingHuman,
                    clearPendingHumanMessage: clearPendingHuman,
                    unread: sessionId == _activeSessionId ? run.unread : true,
                    error: error,
                    clearError: error == null,
                    updatedAt: DateTime.now(),
                  );
                });
              }

              switch (event) {
                case sdk.SkillActivatedEvent(:final skills):
                  markRun(activity: _skillActivityLabel(skills, strings));
                  _setActivatedSkills(currentAssistantMessageId, skills);
                case sdk.ResponseEvent(:final content):
                  _traceChat(
                    'event=response session=$sessionId assistant=$currentAssistantMessageId '
                    'content="${_tracePreview(content)}"',
                  );
                  markRun(activity: 'Writing response');
                  if (!sawResponseDelta) {
                    _updateAssistantMessage(
                      currentAssistantMessageId,
                      (message) =>
                          message.copyWith(content: content, clearAction: true),
                    );
                  }
                case sdk.ResponseDeltaEvent(:final content):
                  if (!sawResponseDelta) {
                    _traceChat(
                      'event=response-delta-first session=$sessionId '
                      'assistant=$currentAssistantMessageId '
                      'content="${_tracePreview(content)}"',
                    );
                  }
                  markRun(activity: 'Writing response');
                  sawResponseDelta = true;
                  _updateAssistantMessage(
                    currentAssistantMessageId,
                    (message) => message.copyWith(
                      content: message.content + content,
                      clearAction: true,
                    ),
                  );
                case sdk.StreamResetEvent():
                  _traceChat(
                    'event=stream-reset session=$sessionId '
                    'assistant=$currentAssistantMessageId',
                  );
                  markRun(activity: 'Reconnecting');
                  sawResponseDelta = false;
                  _updateAssistantMessage(
                    currentAssistantMessageId,
                    (message) =>
                        message.copyWith(content: '', clearAction: true),
                  );
                case sdk.ReasoningDeltaEvent(:final content):
                  markRun(activity: 'Thinking');
                  currentAssistantMessageId = _messageIdForNextTraceSegment(
                    currentAssistantMessageId,
                  );
                  markRun(activity: 'Thinking');
                  _appendTraceReasoning(currentAssistantMessageId, content);
                case sdk.ThinkingEvent(:final content):
                  markRun(activity: 'Thinking');
                  currentAssistantMessageId = _messageIdForNextTraceSegment(
                    currentAssistantMessageId,
                  );
                  markRun(activity: 'Thinking');
                  _appendTraceReasoning(currentAssistantMessageId, content);
                case sdk.ToolCallEvent(
                  :final callId,
                  :final name,
                  :final arguments,
                ):
                  final isA2ATool = _isA2AToolName(name);
                  markRun(activity: isA2ATool ? '附近 Agent' : 'Running: $name');
                  if (!isA2ATool) {
                    _appendToolCall(
                      currentAssistantMessageId,
                      AgentToolCall(
                        callId: callId,
                        name: name,
                        arguments: arguments,
                        startedAt: DateTime.now(),
                      ),
                    );
                  }
                case sdk.ToolCallDeltaEvent(
                  :final callId,
                  :final name,
                  :final argumentsSoFar,
                ):
                  final isA2ATool = _isA2AToolName(name);
                  markRun(
                    activity: isA2ATool
                        ? '附近 Agent'
                        : name.trim().isEmpty
                        ? 'Preparing tool call'
                        : 'Preparing: $name',
                  );
                  if (!isA2ATool) {
                    _appendToolCallDelta(
                      currentAssistantMessageId,
                      callId: callId,
                      name: name,
                      argumentsSoFar: argumentsSoFar,
                    );
                  }
                case sdk.ToolResultEvent(
                  :final name,
                  :final callId,
                  :final output,
                  :final isError,
                ):
                  final isA2ATool = _isA2AToolName(name);
                  markRun(
                    activity: isA2ATool
                        ? '附近 Agent'
                        : isError
                        ? 'Tool failed'
                        : 'Tool completed',
                  );
                  if (!isA2ATool) {
                    _completeToolCall(
                      currentAssistantMessageId,
                      callId: callId,
                      output: output,
                      isError: isError,
                    );
                  }
                  if (!isError && name == 'a2a_wait_messages') {
                    _projectA2AWaitMessagesResult(
                      sessionId,
                      output,
                      beforeMessageId: currentAssistantMessageId,
                    );
                  }
                  if (!isError && name == 'a2a_send_message') {
                    _projectA2ASendMessageResult(
                      sessionId,
                      output,
                      beforeMessageId: currentAssistantMessageId,
                    );
                  }
                  if (!isError &&
                      name == 'browser_open' &&
                      _browserOpenSucceeded(output)) {
                    unawaited(
                      _showBrowserPanelEntry(
                        agentId: agentId,
                        sessionId: sessionId,
                      ),
                    );
                  }
                  if (!isError && _isGeneratedFileTool(name)) {
                    _appendProducedFileAttachments(
                      sessionId,
                      output,
                      agentId: agentId,
                    );
                  }
                case sdk.AgentToolCallEvent(
                  :final callId,
                  :final name,
                  :final arguments,
                  :final agentId,
                ):
                  markRun(activity: 'Agent $agentId: $name');
                  _appendToolCall(
                    currentAssistantMessageId,
                    AgentToolCall(
                      callId: callId,
                      name: '$agentId · $name',
                      arguments: arguments,
                      startedAt: DateTime.now(),
                    ),
                  );
                case sdk.AgentToolCallDeltaEvent(
                  :final callId,
                  :final name,
                  :final argumentsSoFar,
                  :final agentId,
                ):
                  markRun(
                    activity: name.trim().isEmpty
                        ? 'Agent $agentId: preparing tool call'
                        : 'Agent $agentId: preparing $name',
                  );
                  _appendToolCallDelta(
                    currentAssistantMessageId,
                    callId: callId,
                    name: '$agentId · $name',
                    argumentsSoFar: argumentsSoFar,
                  );
                case sdk.AgentToolResultEvent(
                  :final name,
                  :final callId,
                  :final output,
                  :final isError,
                ):
                  markRun(activity: isError ? 'Tool failed' : 'Tool completed');
                  _completeToolCall(
                    currentAssistantMessageId,
                    callId: callId,
                    output: output,
                    isError: isError,
                  );
                  if (!isError && _isGeneratedFileTool(name)) {
                    _appendProducedFileAttachments(
                      sessionId,
                      output,
                      agentId: agentId,
                    );
                  }
                case sdk.ImageGeneratedEvent(:final dataUrl, :final path):
                  markRun(activity: 'Image generated');
                  unawaited(
                    _appendGeneratedImageAttachment(
                      sessionId,
                      dataUrl: dataUrl,
                      sandboxPath: path,
                      agentId: agentId,
                    ),
                  );
                case sdk.ToolOutputChunkEvent(
                  :final callId,
                  :final content,
                  :final stream,
                ):
                  markRun(
                    activity: stream == 'stderr'
                        ? 'Reading stderr'
                        : 'Reading output',
                  );
                  _appendToolOutput(
                    currentAssistantMessageId,
                    callId: callId,
                    stream: stream,
                    content: content,
                  );
                case sdk.AskingHumanEvent(
                  :final requestId,
                  :final question,
                  :final options,
                  :final context,
                ):
                  _traceChat(
                    'event=asking-human session=$sessionId '
                    'assistant=$currentAssistantMessageId request=$requestId',
                  );
                  markRun(
                    status: sdk.SessionRunStatus.waitingForInput,
                    activity: 'Waiting for input',
                    pendingHumanRequestId: requestId,
                    pendingHumanMessageId: currentAssistantMessageId,
                    clearPendingHuman: false,
                  );
                  _updateAssistantMessage(currentAssistantMessageId, (message) {
                    var traceSteps = message.traceSteps;
                    final calls = message.toolCalls.map((call) {
                      if (call.name != 'ask_human' || call.isComplete) {
                        return call;
                      }
                      traceSteps = _updateTraceToolCall(
                        traceSteps,
                        call.callId,
                        (existing) => existing.copyWith(awaitingHuman: true),
                      );
                      return call.copyWith(awaitingHuman: true);
                    }).toList();
                    return message.copyWith(
                      content: '',
                      humanRequest: HumanRequest(
                        requestId: requestId,
                        question: question,
                        options: options,
                        context: context,
                      ),
                      isStreaming: false,
                      clearAction: true,
                      toolCalls: List.unmodifiable(calls),
                      traceSteps: traceSteps,
                    );
                  });
                case sdk.HumanResponseEvent(:final requestId, :final response):
                  final run = _sessionRuns[sessionId];
                  if (run?.pendingHumanRequestId == requestId &&
                      response.isNotEmpty) {
                    _appendLocalUserMessage(sessionId, response, const []);
                  }
                  _markHumanRequestAnswered(sessionId, requestId);
                  currentAssistantMessageId = 'assistant-${_nextMessageId++}';
                  sawResponseDelta = false;
                  markRun(activity: 'Continuing');
                  _appendAssistantShell(sessionId, currentAssistantMessageId);
                case sdk.MessageInjectedEvent(:final content):
                  _traceChat(
                    'event=message-injected session=$sessionId '
                    'assistant=$currentAssistantMessageId '
                    'content="${_tracePreview(content)}"',
                  );
                  _ackPendingInterjection(sessionId, content);
                  if (!_isLastMessage(sessionId, currentAssistantMessageId)) {
                    currentAssistantMessageId = 'assistant-${_nextMessageId++}';
                    sawResponseDelta = false;
                    _appendAssistantShell(sessionId, currentAssistantMessageId);
                  }
                  markRun(activity: 'Continuing');
                  break;
                case sdk.ContextCompactingEvent(
                  :final usagePercent,
                  :final strategy,
                ):
                  markRun(
                    activity:
                        'Compacting context ${usagePercent.toStringAsFixed(1)}%',
                  );
                  _showContextCompactingNotice(
                    agentId,
                    sessionId,
                    usagePercent,
                    strategy: strategy,
                  );
                  break;
                case sdk.ContextCompactedEvent(
                  :final turnsRemoved,
                  :final tokensBefore,
                  :final tokensAfter,
                ):
                  markRun(activity: 'Context compacted');
                  _showContextCompactedNotice(
                    agentId,
                    sessionId,
                    turnsRemoved: turnsRemoved,
                    tokensBefore: tokensBefore,
                    tokensAfter: tokensAfter,
                  );
                  unawaited(
                    _refreshContextStatusForSession(agentId, sessionId),
                  );
                  break;
                case sdk.AgentDelegationEvent(:final toAgent, :final message):
                  markRun(activity: 'Delegating to $toAgent');
                  _appendToolCall(
                    currentAssistantMessageId,
                    AgentToolCall(
                      callId: 'delegation:$toAgent',
                      name: 'delegate · $toAgent',
                      arguments: message,
                      startedAt: DateTime.now(),
                    ),
                  );
                case sdk.AgentDelegationResultEvent(
                  :final toAgent,
                  :final content,
                  :final isError,
                ):
                  markRun(
                    activity: isError
                        ? 'Delegation failed'
                        : 'Delegation completed',
                  );
                  _completeToolCall(
                    currentAssistantMessageId,
                    callId: 'delegation:$toAgent',
                    output: content,
                    isError: isError,
                  );
                case sdk.EvolutionQueuedEvent(:final reviewTypes, :final runs):
                  _finishSessionRun(
                    sessionId,
                    currentAssistantMessageId,
                    status: sdk.SessionRunStatus.completed,
                    activity: 'Learning queued',
                  );
                  _markEvolutionQueued(
                    currentAssistantMessageId,
                    reviewTypes,
                    runs,
                  );
                  _startEvolutionResultPolling(
                    currentAssistantMessageId,
                    runs.map((run) => run.id).toList(growable: false),
                  );
                case sdk.ErrorEvent(:final message):
                  _traceChat(
                    'event=error session=$sessionId '
                    'assistant=$currentAssistantMessageId message="${_tracePreview(message)}"',
                  );
                  markRun(
                    status: sdk.SessionRunStatus.failed,
                    activity: message,
                    error: message,
                  );
                  _flushPendingAssistantAttachments(
                    sessionId,
                    currentAssistantMessageId,
                  );
                  _updateAssistantMessage(
                    currentAssistantMessageId,
                    (chatMessage) => chatMessage.copyWith(
                      content: strings.sdkError(message),
                      isStreaming: false,
                      action: ChatMessageAction.openConfiguration,
                      completedAt: DateTime.now(),
                    ),
                  );
                case sdk.InterruptedEvent():
                  _traceChat(
                    'event=interrupted session=$sessionId '
                    'assistant=$currentAssistantMessageId',
                  );
                  _forceCompleteInflightToolCalls(currentAssistantMessageId);
                  markRun(
                    status: sdk.SessionRunStatus.cancelled,
                    activity: 'Stopped',
                  );
                  _flushPendingAssistantAttachments(
                    sessionId,
                    currentAssistantMessageId,
                  );
                  _updateAssistantMessage(
                    currentAssistantMessageId,
                    (chatMessage) => chatMessage.copyWith(
                      isStreaming: false,
                      completedAt: DateTime.now(),
                    ),
                  );
                default:
                  break;
              }
              _scrollToBottom();
            },
            onError: (Object error) {
              if (!mounted) return;
              _traceChat(
                'stream-error session=$sessionId assistant=$currentAssistantMessageId '
                'error="${_tracePreview(_friendlyError(error))}"',
              );
              _finishSessionRun(
                sessionId,
                currentAssistantMessageId,
                status: sdk.SessionRunStatus.failed,
                activity: _friendlyError(error),
                error: _friendlyError(error),
              );
              _flushPendingAssistantAttachments(
                sessionId,
                currentAssistantMessageId,
              );
              _updateAssistantMessage(
                currentAssistantMessageId,
                (message) => message.copyWith(
                  content: strings.sdkError(_friendlyError(error)),
                  isStreaming: false,
                  action: ChatMessageAction.openConfiguration,
                  completedAt: DateTime.now(),
                ),
              );
              unawaited(_refreshContextStatusForSession(agentId, sessionId));
              _scrollToBottom();
            },
            onDone: () {
              if (!mounted) return;
              _traceChat(
                'stream-done session=$sessionId assistant=$currentAssistantMessageId',
              );
              unawaited(
                _appendFinalResponseAttachments(
                  sessionId,
                  currentAssistantMessageId,
                  agentId: agentId,
                ),
              );
              final run = _sessionRuns[sessionId];
              if (run == null || !run.isTerminal) {
                _finishSessionRun(
                  sessionId,
                  currentAssistantMessageId,
                  status: sdk.SessionRunStatus.completed,
                  activity: 'Completed',
                );
              }
              unawaited(_refreshContextStatusForSession(agentId, sessionId));
              _scrollToBottom();
            },
          );
      setState(() {
        _sessionRuns[sessionId] = ChatSessionRunState(
          sessionKey: session,
          agentId: agentId,
          assistantMessageId: assistantMessageId,
          subscription: subscription,
          startedAt: DateTime.now(),
          updatedAt: DateTime.now(),
          activity: 'Starting',
        );
      });
      _traceChat(
        'run registered session=$sessionId assistant=$assistantMessageId',
      );
    } catch (error) {
      if (!mounted) return;
      _traceChat(
        'start failed session=$sessionId assistant=$assistantMessageId '
        'error="${_tracePreview(_friendlyError(error))}"',
      );
      _finishSessionRun(
        sessionId,
        assistantMessageId,
        status: sdk.SessionRunStatus.failed,
        activity: _friendlyError(error),
        error: _friendlyError(error),
      );
      _updateAssistantMessage(
        assistantMessageId,
        (message) => message.copyWith(
          content: strings.sdkError(_friendlyError(error)),
          isStreaming: false,
          action: ChatMessageAction.openConfiguration,
          completedAt: DateTime.now(),
        ),
      );
      _scrollToBottom(force: true);
    }
  }

  Future<void> _sendRunningMessage(
    String text,
    List<ChatAttachment> attachments,
  ) async {
    if (text.isEmpty && attachments.isEmpty) return;
    final sessionId = _activeSessionId;
    final run = _sessionRuns[sessionId];
    if (run == null || run.isTerminal) return;
    final now = DateTime.now();
    _traceChat(
      'inject start session=$sessionId assistant=${run.assistantMessageId} '
      'text="${_tracePreview(text)}"',
    );
    setState(() {
      _editingMessageId = null;
      _inputController.clear();
    });

    final client = await _getChatClient();
    final pendingRequestId = run.pendingHumanRequestId;
    if (pendingRequestId != null) {
      final ok = await client.answerHumanRequest(pendingRequestId, text);
      if (ok && mounted) {
        _appendLocalUserMessage(sessionId, text, attachments);
        _markHumanRequestAnswered(sessionId, pendingRequestId);
        _scrollToBottom(force: true);
      }
      return;
    }

    final interjection = PendingInterjection(
      id: 'interjection-${_nextInterjectionId++}',
      content: text,
      attachments: List.unmodifiable(attachments),
      attachmentCount: attachments.length,
      createdAt: now,
    );
    _updateSessionRun(
      sessionId,
      (run) => run.copyWith(
        activity: 'Queued message',
        pendingInterjections: List.unmodifiable([
          ...run.pendingInterjections,
          interjection,
        ]),
      ),
    );
    _scrollToBottom(force: true);
    final sdkAttachments = await _toSdkAttachments(attachments);
    final ok = await client.injectMessage(
      run.sessionKey,
      text,
      agentId: run.agentId,
      attachments: sdkAttachments,
    );
    _traceChat(
      'inject result session=$sessionId assistant=${run.assistantMessageId} ok=$ok '
      'text="${_tracePreview(text)}"',
    );
    if (!ok && mounted) {
      _updateSessionRun(
        sessionId,
        (run) => run.copyWith(
          activity: 'Message was not accepted',
          pendingInterjections: List.unmodifiable([
            for (final item in run.pendingInterjections)
              if (item.id == interjection.id)
                item.copyWith(status: PendingInterjectionStatus.failed)
              else
                item,
          ]),
        ),
      );
    }
  }

  Future<void> _stopActiveSend() async {
    final run = _activeRun;
    if (run != null && run.pendingInterjections.isNotEmpty) {
      await _restoreLatestPendingInterjection(_activeSessionId, run);
    }
    await _stopSessionRun(_activeSessionId, clearPendingInterjections: true);
  }

  Future<void> _restoreLatestPendingInterjection(
    String sessionId,
    ChatSessionRunState run,
  ) async {
    final interjection = run.pendingInterjections.last;
    if (interjection.retractsFromSdk) {
      final client = await _getChatClient();
      try {
        await client.retractInjectedMessage(
          run.sessionKey,
          interjection.content,
        );
      } catch (_) {
        // The run is being cancelled; restoring the draft locally is still useful.
      }
      if (!mounted) return;
    }
    _removePendingInterjection(sessionId, interjection.id);
    _inputController.value = TextEditingValue(
      text: interjection.content,
      selection: TextSelection.collapsed(offset: interjection.content.length),
    );
    _inputFocusNode.requestFocus();
  }

  void _removePendingInterjection(String sessionId, String interjectionId) {
    _updateSessionRun(sessionId, (run) {
      final pending = [...run.pendingInterjections];
      final index = pending.lastIndexWhere((item) => item.id == interjectionId);
      if (index == -1) return run;
      pending.removeAt(index);
      return run.copyWith(
        activity: pending.isEmpty ? 'Running' : 'Processing queued messages',
        pendingInterjections: List.unmodifiable(pending),
      );
    });
  }

  Future<void> _stopSessionRun(
    String sessionId, {
    bool clearPendingInterjections = false,
  }) async {
    if (_stoppingSessionIds.contains(sessionId)) return;
    final client = _chatClient;
    final run = _sessionRuns[sessionId];
    if (run == null) return;
    final messageId = run.assistantMessageId;
    final subscription = run.subscription;

    if (mounted) {
      setState(() {
        _stoppingSessionIds.add(sessionId);
        _sessionRuns[sessionId] = run.copyWith(
          status: sdk.SessionRunStatus.cancelling,
          activity: 'Stopping',
        );
      });
    }
    try {
      _updateAssistantMessage(
        messageId,
        (message) => message.copyWith(
          content: message.content.isEmpty
              ? AppStrings.of(context).stoppedMessage
              : null,
          isStreaming: false,
          completedAt: DateTime.now(),
        ),
      );

      if (client != null) {
        try {
          await client.cancelSession(run.sessionKey, agentId: run.agentId);
        } catch (_) {
          // The local stream has already been stopped; SDK cancellation is best effort.
        }
      }

      // Let the Rust stream's bounded cancel sequence (terminal ToolResult +
      // Interrupted + close) drive `onDone`. If it doesn't close within the
      // grace window we force-cancel locally so the UI never hangs.
      final closed = await _awaitSubscriptionDone(
        subscription,
        timeout: const Duration(seconds: 4),
      );
      if (!closed) {
        _forceCompleteInflightToolCalls(messageId);
        unawaited(subscription.cancel());
      }

      final hasOtherActiveRuns = _sessionRuns.entries.any(
        (entry) => entry.key != sessionId && !entry.value.isTerminal,
      );
      if (!hasOtherActiveRuns) {
        await client?.stopBackgroundService();
      }
      _flushPendingAssistantAttachments(sessionId, messageId);
      final latest = _sessionRuns[sessionId];
      if (latest == null || !latest.isTerminal) {
        _finishSessionRun(
          sessionId,
          messageId,
          status: sdk.SessionRunStatus.cancelled,
          activity: 'Stopped',
          clearPendingInterjections: clearPendingInterjections,
        );
      } else if (clearPendingInterjections) {
        _finishSessionRun(
          sessionId,
          null,
          status: latest.status,
          activity: latest.activity,
          clearPendingInterjections: true,
        );
      }
    } finally {
      if (mounted) setState(() => _stoppingSessionIds.remove(sessionId));
    }
  }

  Future<bool> _awaitSubscriptionDone(
    StreamSubscription<sdk.ChatEvent> subscription, {
    required Duration timeout,
  }) async {
    final completer = Completer<bool>();
    Timer? timer;
    timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });
    Future<void> notifyDone() async {
      if (!completer.isCompleted) completer.complete(true);
    }

    subscription.onDone(notifyDone);
    subscription.onError((Object _) => notifyDone());
    final result = await completer.future;
    timer.cancel();
    return result;
  }

  void _forceCompleteInflightToolCalls(String messageId) {
    _updateAssistantMessage(messageId, (message) {
      final updatedCalls = message.toolCalls.map((call) {
        if (call.completedAt != null) return call;
        return call.copyWith(
          output: 'Tool execution cancelled by user.',
          isError: true,
          completedAt: DateTime.now(),
        );
      }).toList();
      return message.copyWith(
        toolCalls: List.unmodifiable(updatedCalls),
        traceSteps: _forceCompleteTraceToolCalls(message.traceSteps),
      );
    });
  }

  void _listenForBackgroundActions(NapaxiChatClient client) {
    _backgroundActionSubscription?.cancel();
    _backgroundActionSubscription = client.onBackgroundAction.listen(
      _handleBackgroundAction,
    );
  }

  void _listenForChannelBridgeEvents(NapaxiChatClient client) {
    _channelBridgeSubscription?.cancel();
    _channelBridgeSubscription = client.onChannelBridgeEvent.listen(
      _handleChannelBridgeEvent,
    );
  }

  void _handleChannelBridgeEvent(DemoChannelBridgeEvent event) {
    if (!mounted) return;
    final isLocalA2A = _isLocalA2AChannelName(event.channelName);
    if (isLocalA2A) {
      _handleLocalA2ABridgeEvent(event);
      return;
    }
    final sessionId = event.sessionId.trim();
    if (sessionId.isEmpty) return;
    final agentId = event.agentId.trim().isEmpty
        ? sdk.NapaxiEngine.defaultAgentId
        : event.agentId.trim();
    final inboundId = event.inboundId.trim().isNotEmpty
        ? event.inboundId.trim()
        : event.platformMessageId?.trim().isNotEmpty == true
        ? event.platformMessageId!.trim()
        : event.createdAt.microsecondsSinceEpoch.toString();
    final userMessageId = 'channel-$inboundId-user';
    final assistantMessageId =
        event.assistantMessageId?.trim().isNotEmpty == true
        ? event.assistantMessageId!.trim()
        : 'channel-$inboundId-assistant';
    final wasAgentChanged = _activeAgentId != agentId;
    final cacheKey = _sessionCacheKey(agentId, sessionId);
    final inboundText = _channelBridgeVisibleInboundText(event);
    final responseText = event.responseText.trim();
    final visibleResponseText = _sanitizeA2AProtocolText(responseText);
    final shouldOpenAssistant =
        event.openAssistant ||
        event.chatEvent != null ||
        event.humanRequestId != null ||
        visibleResponseText.isNotEmpty;

    final previousAgentId = _activeAgentId;
    final previousSessionId = _activeSessionId;

    setState(() {
      if (!isLocalA2A || event.openAssistant) {
        if (_activeAgentId != agentId) {
          _channelInputSources = const [];
          _clearChannelInputState();
        }
        _activeAgentId = agentId;
        _activeSessionId = sessionId;
      }
      _sdkSessions[cacheKey] = event.session;

      final existingIndex = _sessions.indexWhere(
        (session) => session.id == sessionId,
      );
      final existing = existingIndex == -1 ? null : _sessions[existingIndex];
      final messages = [
        for (final message in existing?.messages ?? const <ChatMessage>[])
          if (message.id != 'welcome') message,
      ];
      final inboundDuplicate =
          inboundText.isNotEmpty &&
          messages.any(
            (message) =>
                message.role == ChatRole.user &&
                message.content.trim() == inboundText.trim(),
          );
      if (inboundText.isNotEmpty &&
          !inboundDuplicate &&
          !messages.any((message) => message.id == userMessageId)) {
        messages.add(
          ChatMessage(
            id: userMessageId,
            role: ChatRole.user,
            content: inboundText,
            createdAt: event.createdAt,
          ),
        );
      }
      if (shouldOpenAssistant &&
          !messages.any((message) => message.id == assistantMessageId)) {
        messages.add(
          ChatMessage(
            id: assistantMessageId,
            role: ChatRole.assistant,
            content: '',
            createdAt: event.createdAt,
            isStreaming:
                !event.completeAssistant &&
                event.humanRequestId == null &&
                visibleResponseText.isEmpty,
          ),
        );
      }
      if (event.humanResponseRequestId != null) {
        for (var index = 0; index < messages.length; index += 1) {
          final message = messages[index];
          final request = message.humanRequest;
          if (request?.requestId != event.humanResponseRequestId) continue;
          messages[index] = message.copyWith(
            humanRequest: request!.copyWith(answered: true),
          );
        }
      }
      if (event.humanRequestId != null && event.humanQuestion != null) {
        final humanRequest = HumanRequest(
          requestId: event.humanRequestId!,
          question: event.humanQuestion!,
          options: event.humanOptions,
          context: event.humanContext,
        );
        final assistantIndex = messages.indexWhere(
          (message) => message.id == assistantMessageId,
        );
        if (assistantIndex == -1) {
          messages.add(
            ChatMessage(
              id: assistantMessageId,
              role: ChatRole.assistant,
              content: '',
              humanRequest: humanRequest,
              createdAt: event.createdAt,
              completedAt: event.createdAt,
            ),
          );
        } else {
          messages[assistantIndex] = messages[assistantIndex].copyWith(
            content: '',
            humanRequest: humanRequest,
            isStreaming: false,
            completedAt: event.createdAt,
          );
        }
      } else if (visibleResponseText.isNotEmpty) {
        final assistantIndex = messages.indexWhere(
          (message) => message.id == assistantMessageId,
        );
        if (assistantIndex == -1) {
          messages.add(
            ChatMessage(
              id: assistantMessageId,
              role: ChatRole.assistant,
              content: visibleResponseText,
              createdAt: event.createdAt,
              completedAt: event.createdAt,
            ),
          );
        } else {
          messages[assistantIndex] = messages[assistantIndex].copyWith(
            content: visibleResponseText,
            isStreaming: false,
            completedAt: event.createdAt,
          );
        }
      }
      final title = existing?.title.trim().isNotEmpty == true
          ? existing!.title
          : _channelBridgeDisplayTitle(event);
      final updatedSession = ChatSession(
        id: sessionId,
        title: title,
        isPinned: _isSessionPinned(agentId, sessionId),
        createdAt: existing?.createdAt ?? event.createdAt,
        updatedAt: event.createdAt,
        messages: List.unmodifiable(messages),
      );
      _sessions = List.unmodifiable([
        updatedSession,
        for (final session in _sessions)
          if (session.id != sessionId) session,
      ]);
      _nextMessageId = _nextMessageNumber(_sessions);
      if (!isLocalA2A || event.openAssistant) {
        _editingMessageId = null;
        _inputController.clear();
      }
    });

    if ((_activeAgentId != previousAgentId || wasAgentChanged) &&
        (!isLocalA2A || event.openAssistant)) {
      unawaited(_refreshSkillSlashCommands());
      unawaited(_refreshChannelInputSources());
    }
    _applyChannelBridgeChatEvent(
      event,
      sessionId: sessionId,
      agentId: agentId,
      assistantMessageId: assistantMessageId,
    );
    if (event.completeAssistant) {
      _forceCompleteInflightToolCalls(assistantMessageId);
      _updateAssistantMessage(
        assistantMessageId,
        (message) => message.copyWith(
          isStreaming: false,
          completedAt: message.completedAt ?? DateTime.now(),
        ),
      );
    }
    if (!isLocalA2A || event.openAssistant || previousSessionId == sessionId) {
      _scrollToBottom(force: inboundText.isNotEmpty || event.openAssistant);
    }
    if (inboundText.isNotEmpty ||
        event.completeAssistant ||
        event.humanRequestId != null ||
        event.humanResponseRequestId != null) {
      unawaited(_refreshContextStatusForSession(agentId, sessionId));
    }
  }

  void _recordLocalA2ABridgeEvidence(DemoChannelBridgeEvent event) {
    final error = event.error?.trim() ?? '';
    if (error.isEmpty) return;
    debugPrint(
      '[napaxiToolTrace] local A2A bridge evidence '
      'type=${event.type} inbound=${event.inboundId} error=$error',
    );
  }

  void _handleLocalA2ABridgeEvent(DemoChannelBridgeEvent event) {
    _recordLocalA2ABridgeEvidence(event);
    final ui = event.raw['a2a_ui'];
    if (ui is! Map) return;
    final sessionId = ui['conversationSessionId']?.toString().trim() ?? '';
    final messageId = ui['localReplyMessageId']?.toString().trim() ?? '';
    final taskId = ui['taskId']?.toString().trim() ?? '';
    final peerLabel = ui['peerLabel']?.toString().trim() ?? '';
    if (sessionId.isEmpty || messageId.isEmpty) return;
    if (taskId.isNotEmpty) {
      unawaited(
        _projectLocalA2ABridgeInboundTask(
          sessionId: sessionId,
          taskId: taskId,
          peerLabel: peerLabel,
        ),
      );
      _appendA2AConversationPendingReply(
        sessionId: sessionId,
        peerLabel: peerLabel,
        taskId: taskId,
      );
    }

    _applyChannelBridgeChatEvent(
      event,
      sessionId: sessionId,
      agentId: event.agentId.trim().isEmpty ? _activeAgentId : event.agentId,
      assistantMessageId: messageId,
    );
    _updateAssistantMessage(messageId, _sanitizeLocalA2AVisibleMessage);

    final visibleResponseText = _sanitizeA2AProtocolText(
      event.responseText.trim(),
    );
    if (visibleResponseText.isNotEmpty) {
      _updateAssistantMessage(
        messageId,
        (message) => message.copyWith(
          role: ChatRole.assistant,
          content: visibleResponseText,
          isStreaming: false,
          completedAt: DateTime.now(),
        ),
      );
      unawaited(_forgetDeletedA2AConversationSession(sessionId));
      unawaited(_persistA2AConversationSessions());
    }
    if (event.completeAssistant) {
      _forceCompleteInflightToolCalls(messageId);
      _updateAssistantMessage(
        messageId,
        (message) => message.copyWith(
          role: ChatRole.assistant,
          isStreaming: false,
          completedAt: message.completedAt ?? DateTime.now(),
        ),
      );
      unawaited(_forgetDeletedA2AConversationSession(sessionId));
      unawaited(_persistA2AConversationSessions());
    }
    if (_activeSessionId == sessionId) {
      _scrollToBottom(force: event.chatEvent != null);
    }
  }

  Future<void> _projectLocalA2ABridgeInboundTask({
    required String sessionId,
    required String taskId,
    required String peerLabel,
  }) async {
    final normalizedSessionId = sessionId.trim();
    final normalizedTaskId = taskId.trim();
    if (normalizedSessionId.isEmpty || normalizedTaskId.isEmpty) return;
    try {
      final client = await _getChatClient();
      final task = await client.getLocalA2ATask(normalizedTaskId);
      if (!mounted || task == null) return;
      final collaboration = task.request.context['a2aCollaboration'];
      final collaborationText = collaboration is Map
          ? collaboration['message']?.toString().trim() ?? ''
          : '';
      final text = collaborationText.isNotEmpty
          ? collaborationText
          : _a2aExtractCollaborationMessage(task.request.message);
      final resolved = await client.resolveLocalA2AArtifacts(
        task.request.artifacts,
      );
      if (!mounted) return;
      final attachments = _a2aChatAttachmentsFromArtifacts(resolved);
      final messageId = task.peerMessageId?.trim().isNotEmpty == true
          ? task.peerMessageId!.trim()
          : 'ledger-request-${task.taskId}';
      _appendA2AConversationMessage(
        text,
        sessionId: normalizedSessionId,
        peerLabel: peerLabel,
        messageId: messageId,
        createdAt: DateTime.tryParse(task.createdAt),
        role: ChatRole.user,
        attachments: attachments,
      );
      if (attachments.isEmpty && task.request.artifacts.isNotEmpty) {
        unawaited(
          _refreshA2AConversationAttachments(
            client,
            sessionId: normalizedSessionId,
            messageId: messageId,
            artifacts: task.request.artifacts,
          ),
        );
      }
    } catch (error) {
      debugPrint(
        '[napaxiToolTrace] local A2A bridge inbound projection failed task=$taskId error=$error',
      );
    }
  }

  void _applyChannelBridgeChatEvent(
    DemoChannelBridgeEvent bridgeEvent, {
    required String sessionId,
    required String agentId,
    required String assistantMessageId,
  }) {
    final event = bridgeEvent.chatEvent;
    if (event == null) return;
    final strings = AppStrings.of(context);
    switch (event) {
      case sdk.SkillActivatedEvent(:final skills):
        _setActivatedSkills(assistantMessageId, skills);
      case sdk.ResponseEvent(:final content):
        _updateAssistantMessage(
          assistantMessageId,
          (message) => message.copyWith(content: content, clearAction: true),
        );
      case sdk.ResponseDeltaEvent(:final content):
        _updateAssistantMessage(
          assistantMessageId,
          (message) => message.copyWith(
            content: message.content + content,
            clearAction: true,
          ),
        );
      case sdk.StreamResetEvent():
        _updateAssistantMessage(
          assistantMessageId,
          (message) => message.copyWith(content: '', clearAction: true),
        );
      case sdk.ReasoningDeltaEvent(:final content):
        _appendTraceReasoning(assistantMessageId, content);
      case sdk.ThinkingEvent(:final content):
        _appendTraceReasoning(assistantMessageId, content);
      case sdk.ToolCallEvent(:final callId, :final name, :final arguments):
        if (!_isA2AToolName(name)) {
          _appendToolCall(
            assistantMessageId,
            AgentToolCall(
              callId: callId,
              name: name,
              arguments: arguments,
              startedAt: DateTime.now(),
            ),
          );
        }
      case sdk.ToolCallDeltaEvent(
        :final callId,
        :final name,
        :final argumentsSoFar,
      ):
        if (!_isA2AToolName(name)) {
          _appendToolCallDelta(
            assistantMessageId,
            callId: callId,
            name: name,
            argumentsSoFar: argumentsSoFar,
          );
        }
      case sdk.ToolResultEvent(
        :final name,
        :final callId,
        :final output,
        :final isError,
      ):
        if (!_isA2AToolName(name)) {
          _completeToolCall(
            assistantMessageId,
            callId: callId,
            output: output,
            isError: isError,
          );
        }
        if (!isError && name == 'a2a_wait_messages') {
          _projectA2AWaitMessagesResult(
            sessionId,
            output,
            beforeMessageId: assistantMessageId,
          );
        }
        if (!isError && name == 'a2a_send_message') {
          _projectA2ASendMessageResult(
            sessionId,
            output,
            beforeMessageId: assistantMessageId,
          );
        }
        if (!isError && _isGeneratedFileTool(name)) {
          _appendProducedFileAttachments(sessionId, output, agentId: agentId);
        }
      case sdk.AgentToolCallEvent(
        :final callId,
        :final name,
        :final arguments,
        :final agentId,
      ):
        _appendToolCall(
          assistantMessageId,
          AgentToolCall(
            callId: callId,
            name: '$agentId · $name',
            arguments: arguments,
            startedAt: DateTime.now(),
          ),
        );
      case sdk.AgentToolCallDeltaEvent(
        :final callId,
        :final name,
        :final argumentsSoFar,
        :final agentId,
      ):
        _appendToolCallDelta(
          assistantMessageId,
          callId: callId,
          name: '$agentId · $name',
          argumentsSoFar: argumentsSoFar,
        );
      case sdk.AgentToolResultEvent(
        :final name,
        :final callId,
        :final output,
        :final isError,
      ):
        _completeToolCall(
          assistantMessageId,
          callId: callId,
          output: output,
          isError: isError,
        );
        if (!isError && _isGeneratedFileTool(name)) {
          _appendProducedFileAttachments(sessionId, output, agentId: agentId);
        }
      case sdk.ToolOutputChunkEvent(
        :final callId,
        :final content,
        :final stream,
      ):
        _appendToolOutput(
          assistantMessageId,
          callId: callId,
          stream: stream,
          content: content,
        );
      case sdk.ImageGeneratedEvent(:final dataUrl, :final path):
        unawaited(
          _appendGeneratedImageAttachment(
            sessionId,
            dataUrl: dataUrl,
            sandboxPath: path,
            agentId: agentId,
          ),
        );
      case sdk.AskingHumanEvent(
        :final requestId,
        :final question,
        :final options,
        :final context,
      ):
        _updateAssistantMessage(assistantMessageId, (message) {
          var traceSteps = message.traceSteps;
          final calls = message.toolCalls.map((call) {
            if (call.name != 'ask_human' || call.isComplete) return call;
            traceSteps = _updateTraceToolCall(
              traceSteps,
              call.callId,
              (existing) => existing.copyWith(awaitingHuman: true),
            );
            return call.copyWith(awaitingHuman: true);
          }).toList();
          return message.copyWith(
            content: '',
            humanRequest: HumanRequest(
              requestId: requestId,
              question: question,
              options: options,
              context: context,
            ),
            isStreaming: false,
            clearAction: true,
            toolCalls: List.unmodifiable(calls),
            traceSteps: traceSteps,
          );
        });
      case sdk.HumanResponseEvent(:final requestId):
        _markHumanRequestAnswered(sessionId, requestId);
      case sdk.ErrorEvent(:final message):
        _updateAssistantMessage(
          assistantMessageId,
          (chatMessage) => chatMessage.copyWith(
            content: strings.sdkError(message),
            isStreaming: false,
            action: ChatMessageAction.openConfiguration,
            completedAt: DateTime.now(),
          ),
        );
      default:
        break;
    }
  }

  Future<void> _prepareBackgroundRunFeedback(NapaxiChatClient client) async {
    if (!client.supportsBackgroundExecution) return;
    final allowed = await client.requestBackgroundPermission();
    if (!mounted) return;
    if (!allowed) {
      _showChatSnackBar(AppStrings.of(context).backgroundUnavailable);
    }
  }

  void _handleBackgroundAction(sdk.BackgroundActionEvent event) {
    switch (event.action) {
      case sdk.BackgroundAction.stop:
        if (_isHandlingNotificationStop) return;
        _isHandlingNotificationStop = true;
        final targetSessionId = _singleActiveRunSessionId() ?? _activeSessionId;
        unawaited(
          _stopSessionRun(targetSessionId).whenComplete(() {
            _isHandlingNotificationStop = false;
          }),
        );
      case sdk.BackgroundAction.hitlApprove:
        _appendNotificationActionTrace(
          AppStrings.of(context).notificationApproved,
        );
        _focusAttentionSession();
      case sdk.BackgroundAction.hitlDeny:
        _appendNotificationActionTrace(
          AppStrings.of(context).notificationDenied,
        );
        _focusAttentionSession();
      case sdk.BackgroundAction.viewResult:
        _focusAttentionSession();
      case sdk.BackgroundAction.agentTrigger:
        unawaited(_handlePendingAgentTrigger());
      case sdk.BackgroundAction.automationWake:
        break;
    }
  }

  void _appendNotificationActionTrace(String content) {
    final targetSessionId = _singleWaitingRunSessionId() ?? _activeSessionId;
    final messageId = _sessionRuns[targetSessionId]?.assistantMessageId;
    if (messageId == null) return;
    _updateAssistantMessage(
      messageId,
      (message) => message.copyWith(
        reasoning: _joinTraceText(message.reasoning, content),
        traceSteps: List.unmodifiable([
          ...message.traceSteps,
          AgentTraceStep(reasoning: content),
        ]),
      ),
    );
  }

  void _traceChat(String message) {
    debugPrint('[napaxiChatTrace] $message');
  }

  @override
  String _tracePreview(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 80) return compact;
    return '${compact.substring(0, 80)}...';
  }

  String _joinTraceText(String existing, String content) {
    if (existing.trim().isEmpty) return content;
    return '$existing\n$content';
  }

  void _focusAttentionSession() {
    final sessionId =
        _singleWaitingRunSessionId() ?? _singleActiveRunSessionId();
    if (sessionId != null &&
        _sessions.any((session) => session.id == sessionId)) {
      if (mounted && _activeSessionId != sessionId) {
        _selectSession(sessionId);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToBottom(force: true);
    });
  }

  String? _singleActiveRunSessionId() {
    final running = _sessionRuns.entries
        .where((entry) => !entry.value.isTerminal)
        .map((entry) => entry.key)
        .toList();
    return running.length == 1 ? running.single : null;
  }

  String? _singleWaitingRunSessionId() {
    final waiting = _sessionRuns.entries
        .where((entry) => entry.value.needsInput)
        .map((entry) => entry.key)
        .toList();
    return waiting.length == 1 ? waiting.single : null;
  }

  @override
  void _showChatSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  bool _isFavoriteAttachment(ChatAttachment attachment) {
    return _activeFavoriteAttachments.any(
      (favorite) => _favoriteMatchesAttachment(favorite, attachment),
    );
  }

  void _toggleFavoriteAttachment(ChatAttachment attachment) {
    final id = _attachmentFavoriteId(attachment);
    final index = _favoriteAttachments.indexWhere(
      (favorite) =>
          favorite.accountId == _activeAccountId &&
          favorite.agentId == _activeAgentId &&
          (favorite.id == id ||
              _favoriteMatchesAttachment(favorite, attachment)),
    );
    setState(() {
      if (index == -1) {
        _favoriteAttachments = _dedupeFavoriteAttachments([
          FavoriteAttachment(
            id: id,
            attachment: attachment,
            createdAt: DateTime.now(),
            accountId: _activeAccountId,
            agentId: _activeAgentId,
          ),
          ..._favoriteAttachments,
        ]);
      } else {
        _favoriteAttachments = _dedupeFavoriteAttachments([
          for (var i = 0; i < _favoriteAttachments.length; i++)
            if (i != index) _favoriteAttachments[i],
        ]);
      }
    });
    unawaited(_persistFavoriteAttachments());
  }

  void _openFavoriteAttachment(ChatAttachment attachment) {
    unawaited(
      _openAttachment(
        context,
        attachment,
        accountId: _activeAccountId,
        agentId: _activeAgentId,
      ),
    );
  }

  Future<void> _openConversationAttachments() async {
    final items = _activeConversationAttachments;
    _markActiveAttachmentsSeen(_activeSessionId);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return _ConversationAttachmentsSheet(
          items: items,
          onOpenAttachment: (attachment) {
            Navigator.of(sheetContext).pop();
            unawaited(
              _openAttachment(
                context,
                attachment,
                accountId: _activeAccountId,
                agentId: _activeAgentId,
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showBrowserPanelEntry({
    String? agentId,
    String? sessionId,
  }) async {
    final client = await _getChatClient();
    final controller = client.browserController;
    if (!mounted || controller == null || !controller.hasPage) return;
    final ownerAgentId = agentId ?? _activeAgentId;
    final ownerSessionId = sessionId ?? _activeSessionId;
    _browserController = controller;
    final isWide = MediaQuery.sizeOf(context).width >= 840;
    setState(() {
      _browserPanelAgentId = ownerAgentId;
      _browserPanelSessionId = ownerSessionId;
      if (isWide) {
        _browserPanelVisible = false;
        _browserPanelExpanded = false;
      } else {
        _browserPanelVisible = true;
        _browserPanelExpanded = false;
      }
    });
  }

  bool _browserOpenSucceeded(String output) {
    try {
      final decoded = jsonDecode(output);
      if (decoded is! Map) return false;
      return decoded['success'] == true &&
          (decoded['url'] as String? ?? '').trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _closeBrowserSidePanel() {
    setState(() {
      _browserPanelVisible = false;
      _browserPanelExpanded = false;
      _browserPanelAgentId = null;
      _browserPanelSessionId = null;
    });
  }

  void _minimizeBrowserPanel() {
    setState(() => _browserPanelExpanded = false);
  }

  void _expandBrowserPanel() {
    setState(() {
      _browserPanelVisible = true;
      _browserPanelExpanded = true;
      _browserPanelAgentId ??= _activeAgentId;
      _browserPanelSessionId ??= _activeSessionId;
    });
  }

  Future<void> _copyUserMessage(ChatMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!mounted) return;
    _showChatSnackBar(AppStrings.of(context).messageCopied);
  }

  void _editUserMessage(ChatMessage message) {
    setState(() {
      _editingMessageId = message.id;
      _inputController.value = TextEditingValue(
        text: message.content,
        selection: TextSelection.collapsed(offset: message.content.length),
      );
    });
    _inputFocusNode.requestFocus();
    _scrollToBottom(force: true);
  }

  void _cancelUserMessageEdit() {
    setState(() {
      _editingMessageId = null;
      _inputController.clear();
    });
    _inputFocusNode.requestFocus();
  }

  void _markEvolutionQueued(
    String messageId,
    List<String> reviewTypes,
    List<sdk.EvolutionQueuedRun> runs,
  ) {
    final effectiveReviewTypes = runs.isEmpty
        ? reviewTypes
        : runs.map((run) => run.reviewType).toList(growable: false);
    _evolutionHideTimers.remove(messageId)?.cancel();
    _updateAssistantMessage(
      messageId,
      (message) => message.copyWith(
        evolutionStatus: ChatEvolutionStatus(
          runIds: runs.map((run) => run.id).toList(growable: false),
          reviewTypes: effectiveReviewTypes,
          stage: ChatEvolutionStage.reviewing,
        ),
      ),
    );
  }

  void _startEvolutionResultPolling(String messageId, List<String> runIds) {
    _evolutionPollTimers.remove(messageId)?.cancel();
    if (runIds.isEmpty) {
      _scheduleEvolutionStatusHide(messageId);
      return;
    }

    var attempts = 0;
    Future<void> poll() async {
      if (!mounted) return;
      attempts += 1;
      final List<sdk.EvolutionRun> runs;
      try {
        final client = await _getChatClient();
        runs = await client.listEvolutionRuns(runIds: runIds);
      } catch (_) {
        return;
      }
      if (!mounted || runs.isEmpty) return;
      final shouldContinue = _applyEvolutionRuns(messageId, runs);
      if (!shouldContinue) {
        _evolutionPollTimers.remove(messageId)?.cancel();
      } else if (attempts >= 30) {
        _evolutionPollTimers.remove(messageId)?.cancel();
        _updateEvolutionStatusStage(messageId, ChatEvolutionStage.failed);
      }
    }

    unawaited(poll());
    _evolutionPollTimers[messageId] = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(poll()),
    );
  }

  bool _applyEvolutionRuns(String messageId, List<sdk.EvolutionRun> runs) {
    final hasRunning = runs.any((run) => !run.isFinished);
    final hasFailed = runs.any(
      (run) => run.status == sdk.EvolutionRunStatus.failed,
    );
    final pendingCount = runs.fold<int>(
      0,
      (sum, run) => sum + run.pendingCount,
    );
    final autoAppliedCount = runs.fold<int>(
      0,
      (sum, run) => sum + run.autoAppliedCount,
    );
    final reviewTypes = runs.map((run) => run.reviewType).toSet().toList();
    final stage = hasRunning
        ? ChatEvolutionStage.reviewing
        : hasFailed
        ? ChatEvolutionStage.failed
        : pendingCount > 0
        ? ChatEvolutionStage.pending
        : autoAppliedCount > 0
        ? ChatEvolutionStage.updated
        : ChatEvolutionStage.reviewed;

    _updateAssistantMessage(
      messageId,
      (message) => message.copyWith(
        evolutionStatus: ChatEvolutionStatus(
          runIds: runs.map((run) => run.id).toList(growable: false),
          reviewTypes: reviewTypes,
          stage: stage,
          autoAppliedCount: autoAppliedCount,
          pendingCount: pendingCount,
        ),
      ),
    );
    if (stage == ChatEvolutionStage.reviewed) {
      _scheduleEvolutionStatusHide(messageId);
    }
    return hasRunning;
  }

  void _updateEvolutionStatusStage(String messageId, ChatEvolutionStage stage) {
    _updateAssistantMessage(messageId, (message) {
      final status = message.evolutionStatus;
      if (status == null) return message;
      return message.copyWith(
        evolutionStatus: ChatEvolutionStatus(
          runIds: status.runIds,
          reviewTypes: status.reviewTypes,
          stage: stage,
          autoAppliedCount: status.autoAppliedCount,
          pendingCount: status.pendingCount,
        ),
      );
    });
  }

  Future<void> _refreshPendingEvolutionFromSkills() async {
    final List<Map<String, dynamic>> pending;
    try {
      final client = await _getChatClient();
      pending = await client.listPendingEvolution();
    } catch (_) {
      return;
    }
    if (!mounted) return;

    final normalizedAgentId = _normalizeSkillGovernanceAgentId(_activeAgentId);
    final pendingCount = pending
        .where(
          (item) =>
              _normalizeSkillGovernanceAgentId(
                item['agent_id'] as String? ?? '',
              ) ==
              normalizedAgentId,
        )
        .length;
    final pendingMessages = _messages
        .where(
          (message) =>
              message.evolutionStatus?.stage == ChatEvolutionStage.pending,
        )
        .map((message) => message.id)
        .toList();

    for (final messageId in pendingMessages) {
      _updateAssistantMessage(messageId, (message) {
        final status = message.evolutionStatus;
        if (status == null) return message;
        return message.copyWith(
          evolutionStatus: ChatEvolutionStatus(
            runIds: status.runIds,
            reviewTypes: status.reviewTypes,
            stage: pendingCount == 0
                ? ChatEvolutionStage.reviewed
                : ChatEvolutionStage.pending,
            autoAppliedCount: status.autoAppliedCount,
            pendingCount: pendingCount,
          ),
        );
      });
      if (pendingCount == 0) {
        _scheduleEvolutionStatusHide(messageId);
      }
    }
  }

  void _scheduleEvolutionStatusHide(String messageId) {
    _evolutionHideTimers.remove(messageId)?.cancel();
    _evolutionHideTimers[messageId] = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      _updateAssistantMessage(
        messageId,
        (message) => message.copyWith(clearEvolutionStatus: true),
      );
      _evolutionHideTimers.remove(messageId);
    });
  }

  void _markHumanRequestAnswered(String sessionId, String requestId) {
    final messageId = _sessionRuns[sessionId]?.pendingHumanMessageId;
    _updateSessionRun(
      sessionId,
      (run) => run.copyWith(
        status: sdk.SessionRunStatus.running,
        activity: 'Continuing',
        clearPendingHumanRequest: true,
        clearPendingHumanMessage: true,
      ),
    );
    if (messageId == null) return;
    _updateAssistantMessage(messageId, (message) {
      var traceSteps = message.traceSteps;
      final calls = message.toolCalls.map((call) {
        if (call.name != 'ask_human' ||
            call.isComplete && !call.awaitingHuman) {
          return call;
        }
        final now = DateTime.now();
        traceSteps = _updateTraceToolCall(
          traceSteps,
          call.callId,
          (existing) => existing.copyWith(
            output: existing.output ?? '',
            completedAt: now,
            awaitingHuman: false,
          ),
        );
        return call.copyWith(
          output: call.output ?? '',
          completedAt: now,
          awaitingHuman: false,
        );
      }).toList();
      return message.copyWith(
        humanRequest: message.humanRequest?.copyWith(answered: true),
        toolCalls: List.unmodifiable(calls),
        traceSteps: traceSteps,
      );
    });
  }

  void _ackPendingInterjection(String sessionId, String content) {
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      final run = _sessionRuns[sessionId];
      if (run == null) return;
      final pending = [...run.pendingInterjections];
      final index = pending.indexWhere(
        (item) =>
            item.status == PendingInterjectionStatus.queued &&
            item.content == content,
      );
      if (index == -1) {
        _sessionRuns[sessionId] = run.copyWith(activity: 'Continuing');
        return;
      }
      final interjection = pending.removeAt(index);
      _sessionRuns[sessionId] = run.copyWith(
        activity: pending.isEmpty ? 'Continuing' : 'Processing queued messages',
        pendingInterjections: List.unmodifiable(pending),
      );
      _sessions = _sessions.map((session) {
        if (session.id != sessionId) return session;
        return session.copyWith(
          updatedAt: now,
          messages: List.unmodifiable([
            ...session.messages,
            ChatMessage(
              id: 'user-${_nextMessageId++}',
              role: ChatRole.user,
              content: interjection.content,
              attachments: interjection.attachments,
              createdAt: now,
            ),
          ]),
        );
      }).toList();
    });
  }

  bool _isLastMessage(String sessionId, String messageId) {
    for (final session in _sessions) {
      if (session.id != sessionId || session.messages.isEmpty) continue;
      return session.messages.last.id == messageId;
    }
    return false;
  }

  void _appendAssistantShell(String sessionId, String messageId) {
    final now = DateTime.now();
    setState(() {
      _sessions = _sessions.map((session) {
        if (session.id != sessionId) return session;
        return session.copyWith(
          updatedAt: now,
          messages: List.unmodifiable([
            ...session.messages,
            ChatMessage(
              id: messageId,
              role: ChatRole.assistant,
              content: '',
              createdAt: now,
              isStreaming: true,
            ),
          ]),
        );
      }).toList();
    });
  }

  void _appendLocalUserMessage(
    String sessionId,
    String content,
    List<ChatAttachment> attachments,
  ) {
    final now = DateTime.now();
    setState(() {
      _sessions = _sessions.map((session) {
        if (session.id != sessionId) return session;
        return session.copyWith(
          updatedAt: now,
          messages: List.unmodifiable([
            ...session.messages,
            ChatMessage(
              id: 'user-${_nextMessageId++}',
              role: ChatRole.assistant,
              content: content,
              attachments: attachments,
              createdAt: now,
            ),
          ]),
        );
      }).toList();
    });
  }

  @override
  Future<NapaxiChatClient> _getChatClient() {
    final existing = _chatClient;
    if (existing != null) return Future.value(existing);

    final inFlight = _chatClientFuture;
    if (inFlight != null) return inFlight;

    final future =
        (widget.chatClientFactory ?? () async => NapaxiSdkChatClient())();
    _chatClientFuture = future.then((client) {
      _chatClient = client;
      _browserController = client.browserController;
      _listenForChannelBridgeEvents(client);
      return client;
    });
    return _chatClientFuture!;
  }

  Future<void> _refreshSkillSlashCommands() async {
    final agentId = _activeAgentId;
    try {
      final client = await _getChatClient();
      final report = await client.listSkillCommands(agentId: agentId);
      if (!mounted || _activeAgentId != agentId) return;
      final commands = report.commands
          .where(
            (command) => command.eligible && command.name.trim().isNotEmpty,
          )
          .map(
            (command) => _SlashCommandSpec(
              name: '/${command.name}',
              title: command.skillName,
              description: command.description.trim().isEmpty
                  ? '运行 ${command.skillName} 技能'
                  : command.description,
              isSkillCommand: true,
              skillName: command.skillName,
            ),
          )
          .toList(growable: false);
      setState(() {
        _skillSlashCommands = commands;
      });
    } catch (_) {
      if (!mounted || _activeAgentId != agentId) return;
      setState(() {
        _skillSlashCommands = const [];
      });
    }
  }

  Future<sdk.SessionKey> _getSdkSession(
    NapaxiChatClient client,
    String sessionId,
    String agentId,
  ) async {
    final cacheKey = _sessionCacheKey(agentId, sessionId);
    final existing = _sdkSessions[cacheKey];
    if (existing != null) return existing;
    final session = await client.createSession(
      threadId: sessionId,
      agentId: agentId,
    );
    _sdkSessions[cacheKey] = session;
    return session;
  }

  Future<List<sdk.McAttachment>> _toSdkAttachments(
    List<ChatAttachment> attachments,
  ) async {
    final sdkAttachments = <sdk.McAttachment>[];
    for (final attachment in attachments) {
      sdkAttachments.add(
        sdk.McAttachment(
          kind: attachment.isImage ? 'image' : 'document',
          mimeType: attachment.mimeType,
          filename: attachment.name,
          sandboxPath: attachment.sandboxPath,
          localPath: attachment.path.trim().isEmpty ? null : attachment.path,
          data: await File(attachment.path).readAsBytes(),
        ),
      );
    }
    return sdkAttachments;
  }

  Future<void> _appendInlineHtmlAttachment(
    String sessionId,
    String messageId,
  ) async {
    final message = _messageById(messageId);
    if (message == null || message.attachments.any(_isHtmlAttachment)) return;
    final pending = _pendingAssistantAttachments[sessionId];
    if (pending != null && pending.any(_isHtmlAttachment)) return;
    final html = _extractInlineHtml(message.content);
    if (html == null) return;
    final dir = Directory(
      '${sdk.NapaxiFileBridge.instance.filesDir}/generated_html',
    );
    await dir.create(recursive: true);
    final file = File(
      '${dir.path}/preview_${DateTime.now().millisecondsSinceEpoch}.html',
    );
    await file.writeAsString(html);
    if (!mounted) return;
    _queueAssistantAttachments(sessionId, [
      ChatAttachment(
        name: file.uri.pathSegments.last,
        path: file.path,
        type: ChatAttachmentType.file,
        mimeTypeOverride: 'text/html',
      ),
    ]);
    _scrollToBottom();
  }

  Future<void> _appendFinalResponseAttachments(
    String sessionId,
    String messageId, {
    required String agentId,
  }) async {
    final message = _messageById(messageId);
    if (message == null) return;
    final producedText = _generatedFileReferenceText(message);
    if (producedText.trim().isNotEmpty) {
      _appendProducedFileAttachments(sessionId, producedText, agentId: agentId);
    }
    await _appendInlineHtmlAttachment(sessionId, messageId);
    _flushPendingAssistantAttachments(sessionId, messageId);
  }

  ChatMessage? _messageById(String messageId) {
    for (final session in _sessions) {
      for (final message in session.messages) {
        if (message.id == messageId) return message;
      }
    }
    return null;
  }

  bool _isHtmlAttachment(ChatAttachment attachment) {
    return attachment.extension == 'html' ||
        attachment.extension == 'htm' ||
        attachment.mimeType == 'text/html';
  }

  /// Tools whose result reliably names files the assistant actually created or
  /// modified — these explicitly declare the affected paths in their structured
  /// result. `shell` is intentionally excluded: its result is plain
  /// stdout/stderr with no file manifest, so (matching Codex) files written as
  /// a side effect of shell commands are NOT surfaced as generated attachments.
  /// This avoids noise like a `python -m venv` run dumping the whole venv tree.
  bool _isGeneratedFileTool(String toolName) {
    return switch (_canonicalToolName(toolName)) {
      'write_file' || 'apply_patch' => true,
      _ => false,
    };
  }

  String _generatedFileReferenceText(ChatMessage message) {
    final buffer = StringBuffer();
    for (final toolCall in message.toolCalls) {
      if (!_isGeneratedFileTool(toolCall.name)) continue;
      _appendGeneratedPathsForToolCall(buffer, toolCall);
    }
    for (final step in message.traceSteps) {
      for (final toolCall in step.toolCalls) {
        if (!_isGeneratedFileTool(toolCall.name)) continue;
        _appendGeneratedPathsForToolCall(buffer, toolCall);
      }
    }
    return buffer.toString();
  }

  void _appendGeneratedPathsForToolCall(
    StringBuffer buffer,
    AgentToolCall toolCall,
  ) {
    final canonicalName = _canonicalToolName(toolCall.name);
    if (canonicalName != 'write_file' && canonicalName != 'apply_patch') {
      return;
    }
    for (final file in _collectWriteFileResults(toolCall)) {
      if (file.action == 'deleted' || file.path.trim().isEmpty) continue;
      buffer.writeln(file.path);
    }
  }

  String? _extractInlineHtml(String content) {
    final fenced = RegExp(
      r'```(?:html|HTML)?\s*([\s\S]*?)```',
      multiLine: true,
    ).firstMatch(content);
    final candidate = fenced?.group(1)?.trim() ?? content.trim();
    if (candidate.isEmpty) return null;
    final lower = candidate.toLowerCase();
    final hasHtmlPair = lower.contains('<html') && lower.contains('</html>');
    final looksLikeDocument =
        hasHtmlPair ||
        (fenced != null &&
            (lower.contains('<!doctype html') ||
                lower.contains('<canvas') ||
                lower.contains('<script') ||
                lower.contains('<body') ||
                lower.contains('<style')));
    if (!looksLikeDocument) return null;
    if (lower.contains('<html')) return candidate;
    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>napaxi Preview</title>
</head>
<body>
$candidate
</body>
</html>
''';
  }

  void _appendProducedFileAttachments(
    String sessionId,
    String text, {
    required String agentId,
  }) {
    if (text.trim().isEmpty) return;
    final client = _chatClient;
    if (client == null) return;
    final files = _normalizeResolvedFiles(
      client.detectProducedFiles(text, agentId: agentId),
    );
    if (files.isEmpty) return;
    _queueAssistantAttachments(
      sessionId,
      files.map(_chatAttachmentFromResolvedFile).toList(growable: false),
    );
  }

  List<sdk.ResolvedFile> _normalizeResolvedFiles(
    Iterable<sdk.ResolvedFile> files,
  ) {
    final merged = <String, sdk.ResolvedFile>{};
    for (final file in files) {
      if (!file.exists ||
          file.isDirectory ||
          _resolvedFilePointsToDirectory(file) ||
          _isUploadedAttachmentSandboxPath(file.sandboxPath.trim()) ||
          file.realPath.trim().isEmpty ||
          file.sandboxPath.trim().isEmpty ||
          file.mimeType.trim().toLowerCase() == 'inode/directory') {
        continue;
      }
      merged[file.sandboxPath] = file;
    }
    return merged.values.toList(growable: false);
  }

  bool _resolvedFilePointsToDirectory(sdk.ResolvedFile file) {
    final realPath = file.realPath.trim();
    if (realPath.isEmpty) return false;
    try {
      return FileSystemEntity.typeSync(realPath) ==
          FileSystemEntityType.directory;
    } catch (_) {
      return false;
    }
  }

  ChatAttachment _chatAttachmentFromResolvedFile(sdk.ResolvedFile file) {
    return ChatAttachment(
      name: file.filename.isEmpty
          ? file.sandboxPath.split('/').last
          : file.filename,
      path: file.realPath,
      sandboxPath: file.sandboxPath,
      mimeTypeOverride: file.mimeType,
      type: file.isImage ? ChatAttachmentType.image : ChatAttachmentType.file,
    );
  }

  Future<void> _appendGeneratedImageAttachment(
    String sessionId, {
    required String dataUrl,
    required String? sandboxPath,
    required String agentId,
  }) async {
    if (sandboxPath != null && sandboxPath.trim().isNotEmpty) {
      _appendProducedFileAttachments(sessionId, sandboxPath, agentId: agentId);
      return;
    }
    final match = RegExp(r'^data:([^;]+);base64,(.+)$').firstMatch(dataUrl);
    if (match == null || !sdk.NapaxiFileBridge.isInitialized) return;
    final mimeType = match.group(1) ?? 'image/png';
    final extension = switch (mimeType) {
      'image/jpeg' => 'jpg',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      _ => 'png',
    };
    final bytes = base64Decode(match.group(2)!);
    final dir = Directory(
      '${sdk.NapaxiFileBridge.instance.filesDir}/generated_images',
    );
    await dir.create(recursive: true);
    final file = File(
      '${dir.path}/image_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(bytes);
    _queueAssistantAttachments(sessionId, [
      ChatAttachment(
        name: file.uri.pathSegments.last,
        path: file.path,
        type: ChatAttachmentType.image,
        mimeTypeOverride: mimeType,
      ),
    ]);
  }

  void _queueAssistantAttachments(
    String sessionId,
    List<ChatAttachment> attachments,
  ) {
    final normalizedAttachments = _normalizeAssistantAttachments(attachments);
    if (normalizedAttachments.isEmpty) return;
    final existing = _pendingAssistantAttachments[sessionId] ?? const [];
    final next = _mergeAttachmentLists(existing, normalizedAttachments);
    if (identical(next, existing)) return;
    _pendingAssistantAttachments = Map.unmodifiable({
      ..._pendingAssistantAttachments,
      sessionId: next,
    });
  }

  void _flushPendingAssistantAttachments(String sessionId, String messageId) {
    final pending = _pendingAssistantAttachments[sessionId];
    if (pending == null || pending.isEmpty) return;
    _pendingAssistantAttachments = Map.unmodifiable({
      for (final entry in _pendingAssistantAttachments.entries)
        if (entry.key != sessionId) entry.key: entry.value,
    });
    _appendAssistantAttachments(messageId, pending);
  }

  void _appendAssistantAttachments(
    String messageId,
    List<ChatAttachment> attachments,
  ) {
    final normalizedAttachments = _normalizeAssistantAttachments(attachments);
    if (normalizedAttachments.isEmpty) return;
    ChatMessage? updatedMessage;
    String? updatedSessionId;
    _updateAssistantMessage(messageId, (message) {
      final next = _mergeAttachmentLists(
        message.attachments,
        normalizedAttachments,
      );
      if (identical(next, message.attachments)) return message;
      updatedMessage = message.copyWith(attachments: next);
      updatedSessionId = _sessionIdForMessage(messageId);
      return updatedMessage!;
    });
    final sessionId = updatedSessionId;
    final message = updatedMessage;
    if (sessionId != null && message != null) {
      _rememberAssistantAttachments(sessionId, messageId, message.attachments);
    }
  }

  List<ChatAttachment> _normalizeAssistantAttachments(
    Iterable<ChatAttachment> attachments,
  ) {
    final merged = <String, ChatAttachment>{};
    for (final attachment in attachments) {
      if (_hasUploadedAttachmentSandboxIdentity(attachment)) continue;
      final sandboxPath = attachment.sandboxPath?.trim() ?? '';
      final identity = sandboxPath.isNotEmpty
          ? sandboxPath
          : attachment.path.trim();
      if (identity.isEmpty) continue;
      merged[identity] = attachment;
    }
    return merged.values.toList(growable: false);
  }

  List<ChatAttachment> _mergeAttachmentLists(
    List<ChatAttachment> existing,
    List<ChatAttachment> incoming,
  ) {
    final existingKeys = {
      for (final attachment in existing) _attachmentIdentity(attachment),
    };
    final next = [...existing];
    for (final attachment in incoming) {
      if (existingKeys.add(_attachmentIdentity(attachment))) {
        next.add(attachment);
      }
    }
    if (next.length == existing.length) return existing;
    return List.unmodifiable(next);
  }

  String? _sessionIdForMessage(String messageId) {
    for (final session in _sessions) {
      if (session.messages.any((message) => message.id == messageId)) {
        return session.id;
      }
    }
    return null;
  }

  int? _assistantMessageIndex(String sessionId, String messageId) {
    final session = _sessions.firstWhere(
      (session) => session.id == sessionId,
      orElse: () => ChatSession(
        id: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        messages: const [],
      ),
    );
    if (session.id.isEmpty) return null;
    var index = 0;
    for (final message in session.messages) {
      if (message.role != ChatRole.assistant || message.id == 'welcome') {
        continue;
      }
      if (message.id == messageId) return index;
      index += 1;
    }
    return null;
  }

  void _rememberAssistantAttachments(
    String sessionId,
    String messageId,
    List<ChatAttachment> attachments,
  ) {
    final messageIndex = _assistantMessageIndex(sessionId, messageId);
    if (messageIndex == null) return;
    final cacheKey = _assistantAttachmentCacheKey(
      _activeAgentId,
      sessionId,
      messageIndex,
    );
    _assistantAttachmentCache = Map.unmodifiable({
      ..._assistantAttachmentCache,
      cacheKey: List<ChatAttachment>.unmodifiable(attachments),
    });
    unawaited(_persistAssistantAttachments());
  }

  String _assistantAttachmentCacheKey(
    String agentId,
    String sessionId,
    int assistantMessageIndex,
  ) {
    return '$_activeAccountId::$agentId::$sessionId::$assistantMessageIndex';
  }

  String _attachmentIdentity(ChatAttachment attachment) {
    final sandboxPath = attachment.sandboxPath?.trim();
    if (sandboxPath != null && sandboxPath.isNotEmpty) return sandboxPath;
    return attachment.path;
  }

  void _updateAssistantMessage(
    String messageId,
    ChatMessage Function(ChatMessage message) update,
  ) {
    setState(() {
      _sessions = _sessions.map((session) {
        var didUpdate = false;
        final messages = session.messages.map((message) {
          if (message.id != messageId) return message;
          didUpdate = true;
          return _sanitizeAssistantVisibleMessage(update(message));
        }).toList();
        if (!didUpdate) return session;
        return session.copyWith(
          updatedAt: DateTime.now(),
          messages: List.unmodifiable(messages),
        );
      }).toList();
    });
  }

  ChatMessage _sanitizeAssistantVisibleMessage(ChatMessage message) {
    if (message.role != ChatRole.assistant || message.content.isEmpty) {
      return message;
    }
    final sanitized = _sanitizeA2AProtocolText(message.content);
    if (sanitized == message.content) return message;
    return message.copyWith(content: sanitized);
  }

  ChatMessage _sanitizeLocalA2AVisibleMessage(ChatMessage message) {
    if (message.role != ChatRole.assistant) return message;
    final sanitizedToolCalls = message.toolCalls
        .map(_sanitizeLocalA2AToolCall)
        .toList(growable: false);
    final sanitizedTraceSteps = message.traceSteps
        .map(
          (step) => step.copyWith(
            reasoning: _sanitizeA2AProtocolText(step.reasoning),
            toolCalls: step.toolCalls
                .map(_sanitizeLocalA2AToolCall)
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
    return message.copyWith(
      content: _sanitizeA2AProtocolText(message.content),
      reasoning: _sanitizeA2AProtocolText(message.reasoning),
      toolCalls: List.unmodifiable(sanitizedToolCalls),
      traceSteps: List.unmodifiable(sanitizedTraceSteps),
      clearAction: true,
    );
  }

  AgentToolCall _sanitizeLocalA2AToolCall(AgentToolCall call) {
    return call.copyWith(
      arguments: _sanitizeA2AProtocolText(call.arguments),
      output: call.output == null
          ? null
          : _sanitizeA2AProtocolText(call.output!),
      streamingOutput: _sanitizeA2AProtocolText(call.streamingOutput),
      outputChunks: List.unmodifiable([
        for (final chunk in call.outputChunks)
          AgentToolOutputChunk(
            stream: chunk.stream,
            content: _sanitizeA2AProtocolText(chunk.content),
          ),
      ]),
    );
  }

  String _messageIdForNextTraceSegment(String messageId) {
    ChatMessage? currentMessage;
    for (final session in _sessions) {
      for (final message in session.messages) {
        if (message.id == messageId) {
          currentMessage = message;
          break;
        }
      }
      if (currentMessage != null) break;
    }
    if (currentMessage == null || currentMessage.content.trim().isEmpty) {
      return messageId;
    }

    final nextMessageId = 'assistant-${_nextMessageId++}';
    final now = DateTime.now();
    setState(() {
      _sessions = _sessions.map((session) {
        final messages = <ChatMessage>[];
        var didInsert = false;
        for (final message in session.messages) {
          if (message.id != messageId) {
            messages.add(message);
            continue;
          }
          didInsert = true;
          messages.add(message.copyWith(isStreaming: false, completedAt: now));
          messages.add(
            ChatMessage(
              id: nextMessageId,
              role: ChatRole.assistant,
              content: '',
              createdAt: now,
              isStreaming: true,
            ),
          );
        }
        if (!didInsert) return session;
        return session.copyWith(
          updatedAt: now,
          messages: List.unmodifiable(messages),
        );
      }).toList();
    });
    return nextMessageId;
  }

  void _appendToolCall(String messageId, AgentToolCall toolCall) {
    _updateAssistantMessage(messageId, (message) {
      final calls = [...message.toolCalls];
      final index = calls.indexWhere((call) => call.callId == toolCall.callId);
      if (index == -1) {
        calls.add(toolCall);
      } else {
        calls[index] = toolCall;
      }
      return message.copyWith(
        toolCalls: List.unmodifiable(calls),
        traceSteps: _upsertTraceToolCall(message.traceSteps, toolCall),
      );
    });
  }

  void _setActivatedSkills(
    String messageId,
    List<sdk.ActivatedSkillInfo> skills,
  ) {
    _updateAssistantMessage(messageId, (message) {
      return message.copyWith(activatedSkills: List.unmodifiable(skills));
    });
  }

  String _skillActivityLabel(
    List<sdk.ActivatedSkillInfo> skills,
    AppStrings strings,
  ) {
    final hasLoaded = skills.any((skill) => skill.reason == 'loaded');
    final isChinese = strings.skillReasonLoaded == '已加载';
    if (skills.length == 1) {
      final name = skills.single.name.trim();
      if (hasLoaded && isChinese) {
        return name.isEmpty ? '使用技能' : '使用技能：$name';
      }
      return name.isEmpty ? 'Using skill' : 'Using skill: $name';
    }
    if (hasLoaded && isChinese) {
      return '使用 ${skills.length} 个技能';
    }
    return 'Using ${skills.length} skills';
  }

  void _appendToolCallDelta(
    String messageId, {
    required String callId,
    required String name,
    required String argumentsSoFar,
  }) {
    _updateAssistantMessage(messageId, (message) {
      final calls = [...message.toolCalls];
      final index = calls.indexWhere((call) => call.callId == callId);
      final nextName = name.trim();
      if (index == -1) {
        calls.add(
          AgentToolCall(
            callId: callId,
            name: nextName.isEmpty ? 'tool_call' : nextName,
            arguments: argumentsSoFar,
            startedAt: DateTime.now(),
          ),
        );
      } else {
        final current = calls[index];
        calls[index] = current.copyWith(
          name: nextName.isEmpty ? current.name : nextName,
          arguments: argumentsSoFar,
        );
      }
      return message.copyWith(
        toolCalls: List.unmodifiable(calls),
        traceSteps: _upsertTraceToolCall(
          message.traceSteps,
          calls.firstWhere((call) => call.callId == callId),
        ),
      );
    });
  }

  void _completeToolCall(
    String messageId, {
    required String callId,
    required String output,
    required bool isError,
  }) {
    _updateAssistantMessage(messageId, (message) {
      final calls = message.toolCalls.map((call) {
        if (call.callId != callId) return call;
        return call.copyWith(
          output: output,
          isError: isError,
          completedAt: DateTime.now(),
        );
      }).toList();
      return message.copyWith(
        toolCalls: List.unmodifiable(calls),
        traceSteps: _updateTraceToolCall(
          message.traceSteps,
          callId,
          (call) => call.copyWith(
            output: output,
            isError: isError,
            completedAt: DateTime.now(),
          ),
        ),
      );
    });
  }

  void _projectA2ASendMessageResult(
    String sessionId,
    String output, {
    required String beforeMessageId,
  }) {
    final decoded = _decodeJsonObject(output);
    if (decoded == null || decoded['success'] != true) return;
    final messages = decoded['sentMessages'];
    if (messages is! List || messages.isEmpty) return;
    final projectedBySession = <String, List<ChatMessage>>{};
    final titlesBySession = <String, String>{};
    for (final item in messages) {
      if (item is! Map) continue;
      final rawText = item['text']?.toString().trim() ?? '';
      if (rawText.isEmpty) continue;
      final rawLabel = item['displayLabel']?.toString().trim() ?? '';
      final label = rawLabel.isEmpty ? '我' : rawLabel;
      final sanitizedText = _sanitizeA2AProtocolText(rawText);
      final attachments = _a2aChatAttachmentsFromArtifacts(
        _a2aArtifactsFromDynamic(item['visibleArtifacts']),
      );
      if (sanitizedText.trim().isEmpty && attachments.isEmpty) continue;
      final createdAtMs = item['createdAtMs']?.toString().trim() ?? '';
      final taskId = item['taskId']?.toString().trim() ?? '';
      final targetSessionId = _a2aVisibleConversationSessionIdFromToolResult(
        decoded,
        item,
      );
      if (targetSessionId == null) continue;
      titlesBySession[targetSessionId] =
          _a2aVisibleConversationTitleFromToolResult(decoded, item);
      final key = [
        targetSessionId,
        'send',
        taskId.isEmpty ? createdAtMs : taskId,
        label,
        sanitizedText,
      ].join('|');
      if (!_projectedA2AObservationKeys.add(key)) continue;
      final createdAt = item['createdAtMs'] is int
          ? DateTime.fromMillisecondsSinceEpoch(
              item['createdAtMs'] as int,
              isUtc: true,
            ).toLocal()
          : DateTime.now();
      projectedBySession
          .putIfAbsent(targetSessionId, () => [])
          .add(
            ChatMessage(
              id: taskId.isEmpty
                  ? _a2aVisibleMessageId(
                      createdAtMs.isEmpty
                          ? 'sent-${_nextMessageId++}'
                          : 'sent-$createdAtMs',
                    )
                  : _a2aVisibleMessageId('$taskId-local-sent'),
              role: ChatRole.user,
              content: sanitizedText,
              createdAt: createdAt,
              completedAt: createdAt,
              attachments: List.unmodifiable(attachments),
            ),
          );
    }
    for (final entry in projectedBySession.entries) {
      _insertProjectedA2AMessages(
        entry.key,
        entry.value,
        beforeMessageId: beforeMessageId,
        newSessionTitle: titlesBySession[entry.key],
      );
    }
  }

  void _projectA2AWaitMessagesResult(
    String sessionId,
    String output, {
    required String beforeMessageId,
  }) {
    final decoded = _decodeJsonObject(output);
    if (decoded == null || decoded['success'] != true) return;
    final messages = decoded['messages'];
    if (messages is! List || messages.isEmpty) return;
    final projectedBySession = <String, List<ChatMessage>>{};
    final titlesBySession = <String, String>{};
    for (final item in messages) {
      if (item is! Map) continue;
      final rawText = item['text']?.toString().trim() ?? '';
      if (rawText.isEmpty) continue;
      final rawLabel = item['displayLabel']?.toString().trim() ?? '';
      final label = _isGenericA2APeerLabel(rawLabel) || rawLabel.isEmpty
          ? '附近 Agent'
          : rawLabel;
      final sanitizedText = _sanitizeA2AProtocolText(rawText);
      final attachments = _a2aChatAttachmentsFromArtifacts(
        _a2aArtifactsFromDynamic(item['visibleArtifacts']),
      );
      if (sanitizedText.trim().isEmpty && attachments.isEmpty) continue;
      final content = sanitizedText;
      final taskId = item['taskId']?.toString().trim() ?? '';
      final updatedAtMs = item['updatedAtMs']?.toString().trim() ?? '';
      final targetSessionId = _a2aVisibleConversationSessionIdFromToolResult(
        decoded,
        item,
      );
      if (targetSessionId == null) continue;
      titlesBySession[targetSessionId] =
          _a2aVisibleConversationTitleFromToolResult(decoded, item);
      final key = [
        targetSessionId,
        'wait',
        taskId.isEmpty ? updatedAtMs : taskId,
        label,
        sanitizedText,
      ].join('|');
      if (!_projectedA2AObservationKeys.add(key)) continue;
      final now = item['updatedAtMs'] is int
          ? DateTime.fromMillisecondsSinceEpoch(
              item['updatedAtMs'] as int,
              isUtc: true,
            ).toLocal()
          : DateTime.now();
      projectedBySession
          .putIfAbsent(targetSessionId, () => [])
          .add(
            ChatMessage(
              id: taskId.isEmpty
                  ? _a2aVisibleMessageId(
                      updatedAtMs.isEmpty
                          ? 'observation-${_nextMessageId++}'
                          : 'observation-$updatedAtMs',
                    )
                  : _a2aVisibleMessageId('$taskId-remote-reply'),
              role: ChatRole.assistant,
              content: content,
              createdAt: now,
              completedAt: now,
              attachments: List.unmodifiable(attachments),
            ),
          );
    }
    for (final entry in projectedBySession.entries) {
      _insertProjectedA2AMessages(
        entry.key,
        entry.value,
        beforeMessageId: beforeMessageId,
        newSessionTitle: titlesBySession[entry.key],
      );
    }
  }

  void _insertProjectedA2AMessages(
    String sessionId,
    List<ChatMessage> projected, {
    required String beforeMessageId,
    String? newSessionTitle,
  }) {
    if (projected.isEmpty) return;
    var didInsert = false;
    setState(() {
      var foundSession = false;
      _sessions = _sessions
          .map((session) {
            if (session.id != sessionId) return session;
            foundSession = true;
            final existingMessages = [...session.messages];
            final existingIds = {
              for (final message in existingMessages) message.id,
            };
            final newMessages = projected
                .where((message) => !existingIds.contains(message.id))
                .toList(growable: false);
            if (newMessages.isEmpty) return session;
            final anchorIndex = existingMessages.indexWhere(
              (message) => message.id == beforeMessageId,
            );
            if (anchorIndex == -1) {
              existingMessages.addAll(newMessages);
            } else {
              existingMessages.insertAll(anchorIndex, newMessages);
            }
            didInsert = true;
            final trimmedNewTitle = newSessionTitle?.trim() ?? '';
            final currentTitle = session.title.trim();
            final shouldUpdateTitle =
                trimmedNewTitle.isNotEmpty &&
                (currentTitle.isEmpty ||
                    _isWeakA2AConversationTitle(currentTitle));
            return session.copyWith(
              title: shouldUpdateTitle ? trimmedNewTitle : session.title,
              updatedAt: DateTime.now(),
              messages: List.unmodifiable(existingMessages),
            );
          })
          .toList(growable: false);
      if (!foundSession) {
        final now = DateTime.now();
        final title = newSessionTitle?.trim().isNotEmpty == true
            ? newSessionTitle!.trim()
            : '附近 Agent 对话';
        _sessions = List.unmodifiable([
          ChatSession(
            id: sessionId,
            title: title,
            createdAt: projected.first.createdAt,
            updatedAt: now,
            messages: List.unmodifiable(projected),
          ),
          ..._sessions,
        ]);
        didInsert = true;
      }
      if (didInsert) {
        _nextMessageId = _nextMessageNumber(_sessions);
      }
    });
    if (didInsert) {
      unawaited(_forgetDeletedA2AConversationSession(sessionId));
      unawaited(_persistA2AConversationSessions());
      _showA2AConversationUpdatedNotice(sessionId, title: newSessionTitle);
    }
  }

  Map<String, dynamic>? _decodeJsonObject(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }

  void _appendToolOutput(
    String messageId, {
    required String callId,
    required String stream,
    required String content,
  }) {
    _updateAssistantMessage(messageId, (message) {
      final calls = message.toolCalls.map((call) {
        if (call.callId != callId) return call;
        return call.copyWith(
          streamingOutput: call.streamingOutput + content,
          outputChunks: List.unmodifiable([
            ...call.outputChunks,
            AgentToolOutputChunk(stream: stream, content: content),
          ]),
        );
      }).toList();
      return message.copyWith(
        toolCalls: List.unmodifiable(calls),
        traceSteps: _updateTraceToolCall(
          message.traceSteps,
          callId,
          (call) => call.copyWith(
            streamingOutput: call.streamingOutput + content,
            outputChunks: List.unmodifiable([
              ...call.outputChunks,
              AgentToolOutputChunk(stream: stream, content: content),
            ]),
          ),
        ),
      );
    });
  }

  void _appendTraceReasoning(String messageId, String content) {
    _updateAssistantMessage(messageId, (message) {
      final steps = [...message.traceSteps];
      if (steps.isEmpty || steps.last.toolCalls.isNotEmpty) {
        steps.add(AgentTraceStep(reasoning: content));
      } else {
        final last = steps.removeLast();
        steps.add(last.copyWith(reasoning: last.reasoning + content));
      }
      return message.copyWith(
        reasoning: message.reasoning + content,
        traceSteps: List.unmodifiable(steps),
      );
    });
  }

  List<AgentTraceStep> _upsertTraceToolCall(
    List<AgentTraceStep> traceSteps,
    AgentToolCall toolCall,
  ) {
    final steps = [...traceSteps];
    for (var i = 0; i < steps.length; i++) {
      final calls = [...steps[i].toolCalls];
      final index = calls.indexWhere((call) => call.callId == toolCall.callId);
      if (index == -1) continue;
      calls[index] = toolCall;
      steps[i] = steps[i].copyWith(toolCalls: List.unmodifiable(calls));
      return List.unmodifiable(steps);
    }

    if (steps.isEmpty) {
      steps.add(AgentTraceStep(toolCalls: [toolCall]));
    } else {
      final last = steps.removeLast();
      steps.add(
        last.copyWith(
          toolCalls: List.unmodifiable([...last.toolCalls, toolCall]),
        ),
      );
    }
    return List.unmodifiable(steps);
  }

  List<AgentTraceStep> _updateTraceToolCall(
    List<AgentTraceStep> traceSteps,
    String callId,
    AgentToolCall Function(AgentToolCall call) update,
  ) {
    var didUpdate = false;
    final steps = traceSteps.map((step) {
      final calls = step.toolCalls.map((call) {
        if (call.callId != callId) return call;
        didUpdate = true;
        return update(call);
      }).toList();
      return step.copyWith(toolCalls: List.unmodifiable(calls));
    }).toList();
    return didUpdate ? List.unmodifiable(steps) : traceSteps;
  }

  List<AgentTraceStep> _forceCompleteTraceToolCalls(
    List<AgentTraceStep> traceSteps,
  ) {
    var didUpdate = false;
    final steps = traceSteps.map((step) {
      final calls = step.toolCalls.map((call) {
        if (call.completedAt != null) return call;
        didUpdate = true;
        return call.copyWith(
          output: 'Tool execution cancelled by user.',
          isError: true,
          completedAt: DateTime.now(),
        );
      }).toList();
      return step.copyWith(toolCalls: List.unmodifiable(calls));
    }).toList();
    return didUpdate ? List.unmodifiable(steps) : traceSteps;
  }

  void _completeAssistantMessage(String messageId) {
    _updateAssistantMessage(
      messageId,
      (message) =>
          message.copyWith(isStreaming: false, completedAt: DateTime.now()),
    );
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    const exceptionPrefix = 'Exception: ';
    if (text.startsWith(exceptionPrefix)) {
      return text.substring(exceptionPrefix.length);
    }
    return text;
  }

  @override
  void _scrollToBottom({bool force = false}) {
    _scheduleAutoFollowSync(force: force);
  }

  Future<void> _openConfigPage() async {
    _dismissKeyboard();
    setState(() {
      _sessionHistoryInitialView = _SessionHistoryView.settings;
      _sessionHistoryInitialSettingsSection = _SettingsSection.configuration;
      _sessionHistoryInitialSkillsTab = _SkillsInitialTab.installed;
    });
    await _sessionMenuController.forward();
  }

  Future<void> _openActiveContextModelConfig() async {
    _dismissKeyboard();
    final explicitProfileId = _modelProfileIdForAgent(_activeAgentId);
    final profile =
        _config.profileById(explicitProfileId) ??
        _config.selectedProfileFor(ModelCapability.chat) ??
        _config.selectedProfile;
    if (profile == null) {
      await _openConfigPage();
      return;
    }

    final updatedProfile = await Navigator.of(context).push<LlmModelProfile>(
      MaterialPageRoute(
        builder: (context) => _LlmModelProfilePage(initialProfile: profile),
      ),
    );
    if (updatedProfile == null) return;

    final nextProfiles = _config.profiles
        .map((item) => item.id == updatedProfile.id ? updatedProfile : item)
        .toList();
    final nextCapabilitySelection =
        Map<ModelCapability, String>.from(_config.selectedProfileIdByCapability)
          ..removeWhere((capability, profileId) {
            return profileId == updatedProfile.id &&
                !updatedProfile.supports(capability);
          });

    _handleConfigChanged(
      LlmConfigState(
        profiles: List.unmodifiable(nextProfiles),
        selectedProfileId: _config.selectedProfileId ?? updatedProfile.id,
        selectedProfileIdByCapability: Map.unmodifiable(
          nextCapabilitySelection,
        ),
        systemPrompt: _config.systemPrompt,
        maxToolIterations: _config.maxToolIterations,
      ),
    );
    unawaited(_refreshActiveContextStatus());
  }

  Future<NapaxiChatClient> _buildFilesClientFuture() {
    final strings = AppStrings.of(context);
    final agentId = _activeAgentId;
    final selectedProfile = _runtimeProfileForAgent(agentId);
    return () async {
      if (selectedProfile == null ||
          !selectedProfile.hasModel ||
          selectedProfile.apiKey.trim().isEmpty) {
        throw Exception(strings.configureToViewFiles);
      }
      final client = await _getChatClient();
      await client.configure(
        selectedProfile,
        responseLanguage: _responseLanguageCode,
        capabilitySelection: _activeScenarioCapabilitySelection,
      );
      return client;
    }();
  }

  Future<NapaxiChatClient> _buildSkillsClientFuture() {
    final strings = AppStrings.of(context);
    final agentId = _activeAgentId;
    final selectedProfile = _runtimeProfileForAgent(agentId);
    return () async {
      if (selectedProfile == null ||
          !selectedProfile.hasModel ||
          selectedProfile.apiKey.trim().isEmpty) {
        throw Exception(strings.configureToViewSkills);
      }
      final client = await _getChatClient();
      await client.configure(
        selectedProfile,
        responseLanguage: _responseLanguageCode,
        capabilitySelection: _activeScenarioCapabilitySelection,
      );
      return client;
    }();
  }

  Future<NapaxiChatClient> _buildScenariosClientFuture() async {
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
      await client.applyCapabilitySelection(_activeScenarioCapabilitySelection);
    }
    return client;
  }

  Future<void> _activateRuntimeProfile(
    DemoScenarioRuntimeProfile runtimeProfile, {
    bool restoreSessions = true,
  }) async {
    final logTag = runtimeProfile.agentId == 'engine.cc'
        ? 'napaxiCCHistory'
        : runtimeProfile.agentId == 'engine.codex'
        ? 'napaxiCodexHistory'
        : 'napaxiCCHistory';
    debugPrint(
      '[$logTag] activateRuntime scenario=${runtimeProfile.scenarioId} engine=${runtimeProfile.activeEngineId} agent=${runtimeProfile.agentId} restore=$restoreSessions',
    );
    final now = DateTime.now();
    final sessionId = _newSessionId();
    setState(() {
      _activeScenarioId = runtimeProfile.scenarioId;
      _activeDeveloperEngineId = runtimeProfile.activeEngineId;
      _activeAgentId = runtimeProfile.agentId;
      _channelInputSources = const [];
      _clearChannelInputState();
      if (!runtimeProfile.supportsAgents) {
        _agents = [runtimeProfile.primaryAgent];
      }
      _activeSessionId = sessionId;
      _sessions = [
        ChatSession(
          id: sessionId,
          createdAt: now,
          updatedAt: now,
          messages: [_welcomeMessage(widget.language, _config)],
        ),
      ];
      _nextMessageId = _nextMessageNumber(_sessions);
      _editingMessageId = null;
      _inputController.clear();
      _autoFollowEnabled = true;
      _showJumpToLatest = false;
    });
    await _refreshAgents();
    if (restoreSessions) {
      await _restoreSdkSessions(_config);
    }
    debugPrint(
      '[$logTag] activateRuntime done active=$_activeAgentId session=$_activeSessionId sessions=${_sessions.length}',
    );
    unawaited(_refreshSkillSlashCommands());
    unawaited(_refreshActiveContextStatus());
    unawaited(_refreshChannelInputSources());
  }

  Future<void> _handleScenarioApplied(String scenarioId) async {
    final normalized = _normalizeDemoScenarioId(scenarioId);
    final runtimeProfile = _scenarioRuntimeProfileFor(
      normalized,
      developerEngineId: _activeDeveloperEngineId,
    );
    final selection = _scenarioCapabilitySelection(
      normalized,
      gitSettings: _gitSettings,
      developerEngineId: runtimeProfile.activeEngineId,
    );
    final client = await _getChatClient();
    await client.applyCapabilitySelection(selection);
    final profile = _runtimeProfileForAgent(runtimeProfile.agentId);
    if (profile != null &&
        profile.hasModel &&
        profile.apiKey.trim().isNotEmpty) {
      await client.configure(
        profile,
        responseLanguage: _responseLanguageCode,
        capabilitySelection: selection,
      );
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_activeScenarioKey, normalized);
    await preferences.setString(
      _activeDeveloperEngineKey,
      runtimeProfile.activeEngineId,
    );
    if (!mounted) return;
    await _activateRuntimeProfile(runtimeProfile);
    if (!mounted) return;
    _showChatSnackBar(
      AppStrings.of(context).scenarioApplied(
        _scenarioLabelForId(AppStrings.of(context), normalized),
      ),
    );
  }

  Future<void> _handleGitSettingsChanged(DemoGitSettings settings) async {
    await _saveDemoGitSettings(settings);
    // Write the commit identity into the sandbox rootfs ~/.gitconfig so the
    // agent's `git commit` authors commits with the configured name/email.
    // Requires the file bridge (engine) to be initialized.
    if (settings.hasCommitIdentity && sdk.NapaxiFileBridge.isInitialized) {
      sdk.NapaxiFileBridge.instance.configureGitIdentity(
        name: settings.commitName,
        email: settings.commitEmail,
      );
    }
    if (!mounted) return;
    setState(() => _gitSettings = settings);
    final selection = _activeScenarioCapabilitySelection;
    final client = await _getChatClient();
    await client.applyCapabilitySelection(selection);
    final profile = _runtimeProfileForAgent(_activeAgentId);
    if (profile != null &&
        profile.hasModel &&
        profile.apiKey.trim().isNotEmpty) {
      await client.configure(
        profile,
        responseLanguage: _responseLanguageCode,
        capabilitySelection: selection,
      );
    }
    unawaited(_refreshActiveContextStatus());
  }

  Future<void> _handleGitSettingsCleared() async {
    await _clearDemoGitSettings();
    if (!mounted) return;
    setState(() => _gitSettings = const DemoGitSettings());
    final selection = _activeScenarioCapabilitySelection;
    final client = await _getChatClient();
    await client.applyCapabilitySelection(selection);
    final profile = _runtimeProfileForAgent(_activeAgentId);
    if (profile != null &&
        profile.hasModel &&
        profile.apiKey.trim().isNotEmpty) {
      await client.configure(
        profile,
        responseLanguage: _responseLanguageCode,
        capabilitySelection: selection,
      );
    }
    unawaited(_refreshActiveContextStatus());
  }

  Future<void> _openAgentManager() async {
    if (!_activeRuntimeProfile.supportsAgents) return;
    _dismissKeyboard();
    final selectedProfile = _config.selectedRuntimeProfile;
    final client = await _getChatClient();
    if (!mounted) return;

    final selectedAgentId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => _AgentManagerPage(
          client: client,
          initialAgents: _agents,
          activeAgentId: _activeAgentId,
          profiles: _config.profiles,
          managementProfile: selectedProfile,
        ),
      ),
    );
    await _refreshAgents();
    if (selectedAgentId != null && mounted) {
      await _selectAgent(selectedAgentId);
    }
  }

  Future<void> _selectAgent(String agentId) async {
    if (!_activeRuntimeProfile.supportsAgents) return;
    if (_activeAgentId == agentId) return;
    // CLI engines use a different session restoration mechanism
    if (_isCliAgent(agentId)) {
      await _restoreCliEngineSession(agentId);
      unawaited(_refreshSkillSlashCommands());
      return;
    }

    final now = DateTime.now();
    final sessionId = _newSessionId();
    setState(() {
      _activeAgentId = agentId;
      _activeSessionId = sessionId;
      _channelInputSources = const [];
      _clearChannelInputState();
      _sessions = [
        ChatSession(
          id: sessionId,
          createdAt: now,
          updatedAt: now,
          messages: [_welcomeMessage(widget.language, _config)],
        ),
      ];
      _nextMessageId = _nextMessageNumber(_sessions);
      _editingMessageId = null;
      _inputController.clear();
    });
    final selectedProfile = _config.selectedRuntimeProfile;
    if (selectedProfile != null &&
        selectedProfile.hasModel &&
        selectedProfile.apiKey.trim().isNotEmpty) {
      await _restoreSdkSessions(_config);
    }
    unawaited(_refreshSkillSlashCommands());
    unawaited(_refreshChannelInputSources());
  }

  Future<void> _selectDeveloperEngine(String engineId) async {
    final currentRuntime = _activeRuntimeProfile;
    if (!currentRuntime.isDeveloper) return;
    final nextRuntime = _scenarioRuntimeProfileFor(
      currentRuntime.scenarioId,
      developerEngineId: engineId,
    );
    if (nextRuntime.activeEngineId == _activeDeveloperEngineId &&
        nextRuntime.agentId == _activeAgentId) {
      return;
    }
    final selection = _scenarioCapabilitySelection(
      nextRuntime.scenarioId,
      gitSettings: _gitSettings,
      developerEngineId: nextRuntime.activeEngineId,
    );
    final client = await _getChatClient();
    await client.applyCapabilitySelection(selection);
    final profile = _runtimeProfileForAgent(nextRuntime.agentId);
    if (profile != null &&
        profile.hasModel &&
        profile.apiKey.trim().isNotEmpty) {
      await client.configure(
        profile,
        responseLanguage: _responseLanguageCode,
        capabilitySelection: selection,
      );
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _activeDeveloperEngineKey,
      nextRuntime.activeEngineId,
    );
    if (!mounted) return;
    final logTag = nextRuntime.agentId == 'engine.cc'
        ? 'napaxiCCHistory'
        : nextRuntime.agentId == 'engine.codex'
        ? 'napaxiCodexHistory'
        : 'napaxiCCHistory';
    debugPrint(
      '[$logTag] selectDeveloperEngine from=$_activeDeveloperEngineId/$_activeAgentId to=${nextRuntime.activeEngineId}/${nextRuntime.agentId}',
    );
    await _activateRuntimeProfile(nextRuntime);
  }

  Future<void> _refreshVisibleSessions() async {
    final logTag = _activeAgentId == 'engine.cc'
        ? 'napaxiCCHistory'
        : _activeAgentId == 'engine.codex'
        ? 'napaxiCodexHistory'
        : 'napaxiCCHistory';
    debugPrint(
      '[$logTag] refreshSessions agent=$_activeAgentId activeSession=$_activeSessionId',
    );
    if (_isCliAgent(_activeAgentId)) {
      await _restoreCliEngineSession(_activeAgentId);
      return;
    }
    await _restoreSdkSessions(_config);
  }

  void _startNewSession() {
    final agentId = _activeAgentId;
    final now = DateTime.now();
    final sessionId = _newSessionId();

    if (_isCliAgent(agentId)) {
      // CLI engines: create a fresh placeholder conversation. The first message
      // triggers codex's thread/start (or CC's resume-less query), whose real
      // native id is reported back and used to migrate this placeholder id — so
      // no native mapping needs clearing up front.
      setState(() {
        _activeSessionId = sessionId;
        _sessions = [
          ChatSession(
            id: sessionId,
            createdAt: now,
            updatedAt: now,
            messages: [_welcomeMessage(widget.language, _config)],
          ),
          ..._sessions,
        ];
        _editingMessageId = null;
        _inputController.clear();
      });
      _dismissKeyboard();
      return;
    }

    setState(() {
      _activeSessionId = sessionId;
      _sessions = [
        ChatSession(
          id: sessionId,
          createdAt: now,
          updatedAt: now,
          messages: [_welcomeMessage(widget.language, _config)],
        ),
        ..._sessions,
      ];
      _editingMessageId = null;
      _inputController.clear();
    });
    _dismissKeyboard();
  }

  void _selectSession(String sessionId) {
    if (_activeSessionId == sessionId) return;
    final shouldLoadHistory = !_hasLiveSessionRun(sessionId);
    setState(() {
      _activeSessionId = sessionId;
      final run = _sessionRuns[sessionId];
      if (run != null) {
        _sessionRuns[sessionId] = run.copyWith(unread: false);
      }
      _a2aUnreadConversationSessionIds.remove(sessionId);
      _editingMessageId = null;
      _inputController.clear();
    });
    _dismissKeyboard();
    _scrollToBottom(force: true);
    if (shouldLoadHistory) {
      unawaited(_loadSessionHistory(sessionId));
    }
    unawaited(_refreshContextStatusForSession(_activeAgentId, sessionId));
  }

  void _toggleSessionPin(String sessionId) {
    final pinKey = _pinnedSessionKey(_activeAgentId, sessionId);
    setState(() {
      final pinnedSessionIds = {..._pinnedSessionIds};
      final isPinned = pinnedSessionIds.contains(pinKey);
      if (isPinned) {
        pinnedSessionIds.remove(pinKey);
      } else {
        pinnedSessionIds.add(pinKey);
      }
      _pinnedSessionIds = pinnedSessionIds;
      _sessions = _sessions
          .map(
            (session) => session.id == sessionId
                ? session.copyWith(isPinned: !isPinned)
                : session,
          )
          .toList();
    });
    unawaited(_persistPinnedSessions());
  }

  Future<void> _confirmDeleteSession(String sessionId) async {
    final strings = AppStrings.of(context);
    ChatSession? session;
    for (final item in _sessions) {
      if (item.id == sessionId) {
        session = item;
        break;
      }
    }
    if (session == null) return;
    final sanitizedTitle = _sanitizeA2AProtocolText(
      session.displayTitle,
    ).trim();
    final sessionTitle = sanitizedTitle.isEmpty
        ? '附近 Agent 对话'
        : sanitizedTitle;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.deleteChatConfirmationTitle),
        content: Text(strings.deleteChatConfirmationMessage(sessionTitle)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          TextButton(
            key: const Key('confirm_delete_session_button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              strings.deleteChat,
              style: const TextStyle(color: Color(0xFFDC2626)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _deleteSession(sessionId);
  }

  Future<void> _deleteSession(String sessionId) async {
    // Terminal sessions: clean up backend, skip SDK operations.
    if (_isTerminalSession(sessionId)) {
      final ts = _terminalSessionMap.remove(sessionId);
      if (ts != null) {
        ts.dispose();
      }
      final remainingSessions = _sessions
          .where((s) => s.id != sessionId)
          .toList();
      final now = DateTime.now();
      final shouldCreate = remainingSessions.isEmpty;
      final replacementId = shouldCreate ? _newSessionId() : null;
      final nextSessions = shouldCreate
          ? [
              ChatSession(
                id: replacementId!,
                createdAt: now,
                updatedAt: now,
                messages: [_welcomeMessage(widget.language, _config)],
              ),
            ]
          : remainingSessions;
      setState(() {
        _sessions = List.unmodifiable(nextSessions);
        _activeSessionId = _activeSessionId == sessionId
            ? (replacementId ?? nextSessions.first.id)
            : _activeSessionId;
        _editingMessageId = null;
        _inputController.clear();
      });
      return;
    }

    final strings = AppStrings.of(context);
    final agentId = _activeAgentId;
    final cacheKey = _sessionCacheKey(agentId, sessionId);
    final sdkSession = _sdkSessions[cacheKey];
    try {
      final run = _sessionRuns[sessionId];
      if (sdkSession != null) {
        final client = await _getChatClient();
        if (run != null && !run.isTerminal) {
          await client.cancelSession(sdkSession, agentId: agentId);
        }
        final deleted = await client.deleteSession(
          sdkSession,
          agentId: agentId,
        );
        if (!deleted) {
          throw Exception(strings.deleteChat);
        }
      }
      if (run != null) {
        unawaited(run.subscription.cancel());
      }
      if (!mounted || _activeAgentId != agentId) return;

      final remainingSessions = _sessions
          .where((session) => session.id != sessionId)
          .toList();
      final firstRemainingSessionId = remainingSessions.isEmpty
          ? null
          : remainingSessions.first.id;
      final nextActiveSessionId = _activeSessionId == sessionId
          ? firstRemainingSessionId
          : _activeSessionId;
      final shouldCreateReplacement = nextActiveSessionId == null;
      final now = DateTime.now();
      final replacementSessionId = shouldCreateReplacement
          ? _newSessionId()
          : null;
      final nextSessions = shouldCreateReplacement
          ? [
              ChatSession(
                id: replacementSessionId!,
                createdAt: now,
                updatedAt: now,
                messages: [_welcomeMessage(widget.language, _config)],
              ),
            ]
          : remainingSessions;
      final pinKey = _pinnedSessionKey(agentId, sessionId);
      setState(() {
        _sessions = List.unmodifiable(nextSessions);
        _activeSessionId = replacementSessionId ?? nextActiveSessionId!;
        _sessionRuns.remove(sessionId);
        _a2aUnreadConversationSessionIds.remove(sessionId);
        _sdkSessions.remove(cacheKey);
        _contextStatuses.remove(cacheKey);
        _contextStatusLoading.remove(cacheKey);
        _pinnedSessionIds = {..._pinnedSessionIds}..remove(pinKey);
        if (_browserPanelAgentId == agentId &&
            _browserPanelSessionId == sessionId) {
          _browserPanelVisible = false;
          _browserPanelExpanded = false;
          _browserPanelAgentId = null;
          _browserPanelSessionId = null;
        }
        _nextMessageId = _nextMessageNumber(_sessions);
        _editingMessageId = null;
        _inputController.clear();
      });
      _removeSeenAttachmentsForSession(sessionId);
      unawaited(_persistPinnedSessions());
      unawaited(_markDeletedA2AConversationSession(sessionId));
      unawaited(_persistA2AConversationSessions());
      if (_activeSessionId != sessionId &&
          replacementSessionId == null &&
          !_hasLiveSessionRun(_activeSessionId)) {
        unawaited(_loadSessionHistory(_activeSessionId));
      }
      _showChatSnackBar(strings.chatDeleted);
    } catch (error) {
      if (!mounted) return;
      _showChatSnackBar(strings.chatActionFailed(_friendlyDisplayError(error)));
    }
  }

  void _openSessionHistory() {
    _dismissKeyboard();
    setState(() {
      _sessionHistoryInitialView = _SessionHistoryView.menu;
      _sessionHistoryInitialSettingsSection = _SettingsSection.menu;
      _sessionHistoryInitialSkillsTab = _SkillsInitialTab.installed;
    });
    _sessionMenuController.forward();
  }

  void _openScenariosFromChat() {
    _dismissKeyboard();
    setState(() {
      _sessionHistoryInitialView = _SessionHistoryView.settings;
      _sessionHistoryInitialSettingsSection = _SettingsSection.scenarios;
      _sessionHistoryInitialSkillsTab = _SkillsInitialTab.installed;
    });
    _sessionMenuController.forward();
  }

  void _openSkillOrganizeFromChat(ChatMessage message) {
    final status = message.evolutionStatus;
    if (status == null || status.stage != ChatEvolutionStage.pending) return;
    _dismissKeyboard();
    // Show a unified pending sheet that displays both memory and skill
    // suggestions. The sheet internally filters by type and shows all items.
    _showMemoryPendingSheet(message.id);
  }

  void _showMemoryPendingSheet(String messageId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => _MemoryPendingSheet(
          clientFuture: _getChatClient(),
          scrollController: scrollController,
          onApplied: () {
            unawaited(_refreshEvolutionStatus(messageId));
          },
        ),
      ),
    );
  }

  Future<void> _refreshEvolutionStatus(String messageId) async {
    // Re-query pending count — only clear the badge when nothing is left.
    final List<Map<String, dynamic>> pending;
    try {
      final client = await _getChatClient();
      pending = await client.listPendingEvolution();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final normalizedAgentId = _normalizeSkillGovernanceAgentId(_activeAgentId);
    final pendingCount = pending
        .where(
          (item) =>
              _normalizeSkillGovernanceAgentId(
                item['agent_id'] as String? ?? '',
              ) ==
              normalizedAgentId,
        )
        .length;
    if (pendingCount == 0) {
      _updateEvolutionStatusStage(messageId, ChatEvolutionStage.reviewed);
      _scheduleEvolutionStatusHide(messageId);
    } else {
      _updateAssistantMessage(messageId, (message) {
        final status = message.evolutionStatus;
        if (status == null) return message;
        return message.copyWith(
          evolutionStatus: ChatEvolutionStatus(
            runIds: status.runIds,
            reviewTypes: status.reviewTypes,
            stage: ChatEvolutionStage.pending,
            autoAppliedCount: status.autoAppliedCount,
            pendingCount: pendingCount,
          ),
        );
      });
    }
  }

  void _closeSessionHistory() {
    _sessionMenuController.reverse();
    unawaited(_refreshChannelInputSources());
  }

  void _handleSessionMenuDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? details.delta.dx;
    if (_sessionMenuController.value == 0 && delta <= 0) return;

    _dismissKeyboard();
    final width = MediaQuery.sizeOf(context).width;
    _sessionMenuController.value =
        (_sessionMenuController.value + delta / width).clamp(0.0, 1.0);
  }

  void _handleSessionMenuDragEnd(DragEndDetails details) {
    final velocity =
        details.primaryVelocity ?? details.velocity.pixelsPerSecond.dx;

    if (velocity > _sessionMenuFlingVelocity) {
      _sessionMenuController.forward();
      return;
    }
    if (velocity < -_sessionMenuFlingVelocity) {
      _sessionMenuController.reverse();
      return;
    }

    if (_sessionMenuController.value >= 0.75) {
      _sessionMenuController.forward();
    } else {
      _sessionMenuController.reverse();
    }
  }

  void _openWorkbenchDrawer() {
    _dismissKeyboard();
    _workbenchDrawerController.forward();
  }

  void _closeWorkbenchDrawer() {
    _workbenchDrawerController.reverse();
  }

  void _handleWorkbenchDrawerDragUpdate(DragUpdateDetails details) {
    // The right drawer dismisses with a rightward swipe, so invert the delta
    // relative to the left session-history drawer.
    final delta = details.primaryDelta ?? details.delta.dx;
    if (_workbenchDrawerController.value == 0 && delta >= 0) return;

    _dismissKeyboard();
    final width = MediaQuery.sizeOf(context).width;
    _workbenchDrawerController.value =
        (_workbenchDrawerController.value - delta / width).clamp(0.0, 1.0);
  }

  void _handleWorkbenchDrawerDragEnd(DragEndDetails details) {
    final velocity =
        details.primaryVelocity ?? details.velocity.pixelsPerSecond.dx;

    if (velocity < -_sessionMenuFlingVelocity) {
      _workbenchDrawerController.forward();
      return;
    }
    if (velocity > _sessionMenuFlingVelocity) {
      _workbenchDrawerController.reverse();
      return;
    }

    if (_workbenchDrawerController.value >= 0.75) {
      _workbenchDrawerController.forward();
    } else {
      _workbenchDrawerController.reverse();
    }
  }

  void _handleChatPointerDown(PointerDownEvent event) {
    _chatDragStart = event.position;
    _chatDragLastPosition = event.position;
    _isOpeningSessionMenuDrag = false;
    _isHorizontalScrollableDrag = _hasHorizontalScrollableAt(event.position);
  }

  void _handleChatPointerMove(PointerMoveEvent event) {
    if (_isHorizontalScrollableDrag) return;

    final start = _chatDragStart;
    final lastPosition = _chatDragLastPosition;
    if (start == null || lastPosition == null) return;

    final totalDelta = event.position - start;
    final isHorizontalOpenDrag =
        totalDelta.dx > 8 && totalDelta.dx.abs() > totalDelta.dy.abs() * 1.2;
    if (!_isOpeningSessionMenuDrag && !isHorizontalOpenDrag) {
      _chatDragLastPosition = event.position;
      return;
    }

    _isOpeningSessionMenuDrag = true;
    _dismissKeyboard();
    final width = MediaQuery.sizeOf(context).width;
    final delta = event.position.dx - lastPosition.dx;
    _sessionMenuController.value =
        (_sessionMenuController.value + delta / width).clamp(0.0, 1.0);
    _chatDragLastPosition = event.position;
  }

  void _handleChatPointerEnd(PointerEvent event) {
    if (_isOpeningSessionMenuDrag) {
      if (_sessionMenuController.value >= 0.25) {
        _sessionMenuController.forward();
      } else {
        _sessionMenuController.reverse();
      }
    }
    _chatDragStart = null;
    _chatDragLastPosition = null;
    _isOpeningSessionMenuDrag = false;
    _isHorizontalScrollableDrag = false;
  }

  bool _hasHorizontalScrollableAt(Offset globalPosition) {
    var found = false;

    void visit(Element element) {
      if (found) return;

      final widget = element.widget;
      if (widget is Scrollable &&
          axisDirectionToAxis(widget.axisDirection) == Axis.horizontal) {
        final renderObject = element.renderObject;
        if (renderObject is RenderBox && renderObject.hasSize) {
          final localPosition = renderObject.globalToLocal(globalPosition);
          found = renderObject.size.contains(localPosition);
          if (found) return;
        }
      }

      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    return found;
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final browserBelongsToActiveSession =
        _browserPanelAgentId == _activeAgentId &&
        _browserPanelSessionId == _activeSessionId;
    final hasActiveMobileBrowser =
        _browserPanelVisible &&
        browserBelongsToActiveSession &&
        (_browserController?.hasPage ?? false) &&
        size.width < 840;
    final showMobileBrowserDock =
        hasActiveMobileBrowser && !keyboardVisible && !_browserPanelExpanded;
    final showMobileBrowserOverlay =
        hasActiveMobileBrowser && _browserPanelExpanded;
    final compactionNotice = _activeContextCompactionNotice;
    final messageListTopPadding = compactionNotice == null ? 18.0 : 86.0;
    final renderItems = _buildChatRenderItems();
    final generatedIdentities = _generatedAttachmentIdentities(_activeSession);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _handleChatPointerDown,
            onPointerMove: _handleChatPointerMove,
            onPointerUp: _handleChatPointerEnd,
            onPointerCancel: _handleChatPointerEnd,
            child: SafeArea(
              child: Column(
                children: [
                  _ChatTopBar(
                    activeAgent: _activeAgent,
                    agents: _agents,
                    runtimeProfile: _activeRuntimeProfile,
                    language: widget.language,
                    hasAttachments: _activeConversationAttachments.isNotEmpty,
                    newAttachmentCount: _newAttachmentCountFor(
                      _activeSessionId,
                    ),
                    onAgentSelected: _selectAgent,
                    onEngineSelected: _selectDeveloperEngine,
                    onManageAgents: _openAgentManager,
                    onSessionsTap: _openSessionHistory,
                    onAttachmentsTap: _openConversationAttachments,
                    onNewTerminal: _activeRuntimeProfile.isDeveloper
                        ? _openSandboxTerminal
                        : null,
                    onCopyWorkspacePath: _activeRuntimeProfile.isDeveloper
                        ? _copyWorkspacePath
                        : null,
                    onCopyBranchName: _activeRuntimeProfile.isDeveloper
                        ? _copyBranchName
                        : null,
                    onOpenWorkbench: _activeRuntimeProfile.isDeveloper
                        ? _openWorkbenchDrawer
                        : null,
                  ),
                  const Divider(height: 1),
                  if (_activeScenarioId != _generalScenarioId)
                    _ScenarioRuntimeBar(
                      scenarioId: _activeScenarioId,
                      onTap: _openScenariosFromChat,
                    ),
                  Expanded(
                    child: _isTerminalSession(_activeSessionId)
                        ? _buildTerminalView()
                        : GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _dismissKeyboard,
                            child: Stack(
                              children: [
                                NotificationListener<
                                  SizeChangedLayoutNotification
                                >(
                                  onNotification: (_) {
                                    _handleMessageListSizeChanged();
                                    return false;
                                  },
                                  child: SizeChangedLayoutNotifier(
                                    child: ListView.builder(
                                      key: const Key('chat_message_list'),
                                      controller: _scrollController,
                                      keyboardDismissBehavior:
                                          ScrollViewKeyboardDismissBehavior
                                              .onDrag,
                                      padding: EdgeInsets.fromLTRB(
                                        16,
                                        messageListTopPadding,
                                        16,
                                        18,
                                      ),
                                      itemCount: renderItems.length,
                                      itemBuilder: (context, index) {
                                        final item = renderItems[index];
                                        if (item is _GeneratedAttachmentsItem) {
                                          return _ConversationGeneratedAttachmentsView(
                                            key: Key(
                                              'turn_generated_attachments_'
                                              '${item.turnUserMessageId ?? 'lead'}'
                                              '_${item.turnIndex}',
                                            ),
                                            attachments: item.attachments,
                                            accountId: _activeAccountId,
                                            agentId: _activeAgentId,
                                            isFavoriteAttachment:
                                                _isFavoriteAttachment,
                                            onToggleFavoriteAttachment:
                                                _toggleFavoriteAttachment,
                                          );
                                        }
                                        final message =
                                            (item as _MessageItem).message;
                                        return _ChatBubble(
                                          message: message,
                                          accountId: _activeAccountId,
                                          agentId: _activeAgentId,
                                          onLoadFullToolCall:
                                              _loadFullHistoryToolCall,
                                          onOpenConfiguration: _openConfigPage,
                                          isFavoriteAttachment:
                                              _isFavoriteAttachment,
                                          onToggleFavoriteAttachment:
                                              _toggleFavoriteAttachment,
                                          onOpenSkillOrganize:
                                              _openSkillOrganizeFromChat,
                                          onCopyUserMessage: (message) {
                                            unawaited(
                                              _copyUserMessage(message),
                                            );
                                          },
                                          onEditUserMessage: _editUserMessage,
                                          onAnswerHumanRequest:
                                              (requestId, response) {
                                                _inputController.text =
                                                    response;
                                                unawaited(
                                                  _sendRunningMessage(
                                                    response,
                                                    const [],
                                                  ),
                                                );
                                              },
                                          aggregatedAttachmentIdentities:
                                              generatedIdentities,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 16,
                                  right: 16,
                                  top: 12,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 180),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    child: compactionNotice == null
                                        ? const SizedBox.shrink()
                                        : _ContextCompactionBanner(
                                            key: ValueKey(
                                              compactionNotice
                                                  .updatedAt
                                                  .microsecondsSinceEpoch,
                                            ),
                                            notice: compactionNotice,
                                            status: _activeContextStatus,
                                            onTap: _handleContextStatusTap,
                                          ),
                                  ),
                                ),
                                Positioned(
                                  right: 16,
                                  bottom: 16,
                                  child: AnimatedSlide(
                                    duration: const Duration(milliseconds: 180),
                                    offset: _showJumpToLatest
                                        ? Offset.zero
                                        : const Offset(0, 1.4),
                                    child: AnimatedOpacity(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      opacity: _showJumpToLatest ? 1 : 0,
                                      child: IgnorePointer(
                                        ignoring: !_showJumpToLatest,
                                        child: Tooltip(
                                          message: AppStrings.of(
                                            context,
                                          ).jumpToLatestMessages,
                                          key: const Key(
                                            'jump_to_latest_button',
                                          ),
                                          child: Material(
                                            color: Colors.white,
                                            elevation: 4,
                                            shadowColor: Colors.black
                                                .withValues(alpha: 0.14),
                                            shape: const CircleBorder(
                                              side: BorderSide(
                                                color: Color(0xFFD1D5DB),
                                              ),
                                            ),
                                            child: InkWell(
                                              customBorder:
                                                  const CircleBorder(),
                                              onTap: () =>
                                                  _scrollToBottom(force: true),
                                              child: const SizedBox(
                                                width: 46,
                                                height: 46,
                                                child: Center(
                                                  child: Icon(
                                                    Icons
                                                        .keyboard_arrow_down_rounded,
                                                    color: Colors.black,
                                                    size: 26,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  if (_activeRun?.pendingInterjections.isNotEmpty ?? false)
                    _PendingInterjectionQueue(
                      language: widget.language,
                      interjections: _activeRun!.pendingInterjections,
                    ),
                  if (!_isTerminalSession(_activeSessionId))
                    _ChatInputShell(
                      roundedBottom: showMobileBrowserDock,
                      child: _ChatInputBar(
                        controller: _inputController,
                        focusNode: _inputFocusNode,
                        isSending: _isActiveSessionSending,
                        isEditing: _editingMessageId != null,
                        slashCommands: _availableSlashCommands,
                        contextStatus: _activeContextStatus,
                        isContextStatusLoading: _isActiveContextStatusLoading,
                        hasContextSession: _sdkSessions.containsKey(
                          _activeSessionCacheKey,
                        ),
                        onCancelEdit: _cancelUserMessageEdit,
                        onContextStatusTap: _handleContextStatusTap,
                        onSend: _sendMessage,
                        onStop: _stopActiveSend,
                        channelInputSources: _channelInputSources,
                        channelInputBusyAccountId: _channelInputBusyAccountId,
                        channelInputActiveAccountId:
                            _channelInputActiveAccountId,
                        onChannelInputSelected: _captureChannelInput,
                        chatClient: _chatClient,
                        agentId: _activeAgentId,
                      ),
                    ),
                  if (showMobileBrowserDock)
                    _BrowserMobileDock(
                      controller: _browserController,
                      onExpand: _expandBrowserPanel,
                      onClose: _closeBrowserSidePanel,
                    ),
                ],
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _sessionMenuController,
            builder: (context, _) {
              if (_sessionMenuController.value == 0) {
                return const SizedBox.shrink();
              }

              final progress = Curves.easeOutCubic.transform(
                _sessionMenuController.value,
              );
              final width = MediaQuery.sizeOf(context).width;

              return IgnorePointer(
                ignoring: _sessionMenuController.value == 0,
                child: Stack(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _closeSessionHistory,
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.18 * progress),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(-width * (1 - progress), 0),
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragUpdate: _handleSessionMenuDragUpdate,
                        onHorizontalDragEnd: _handleSessionMenuDragEnd,
                        child: _SessionHistorySheet(
                          activeAgent: _activeAgent,
                          sessions: _sessions,
                          sessionRuns: Map.unmodifiable(_sessionRuns),
                          a2aUnreadSessionIds: Set.unmodifiable(
                            _a2aUnreadConversationSessionIds,
                          ),
                          activeSessionId: _activeSessionId,
                          favoriteAttachments: _activeFavoriteAttachments,
                          initialView: _sessionHistoryInitialView,
                          initialSettingsSection:
                              _sessionHistoryInitialSettingsSection,
                          initialSkillsTab: _sessionHistoryInitialSkillsTab,
                          createFilesClientFuture: _buildFilesClientFuture,
                          createSkillsClientFuture: _buildSkillsClientFuture,
                          createScenariosClientFuture:
                              _buildScenariosClientFuture,
                          createNearbyClientFuture: _getChatClient,
                          activeScenarioId: _activeScenarioId,
                          gitSettings: _gitSettings,
                          onScenarioApplied: _handleScenarioApplied,
                          onGitSettingsChanged: _handleGitSettingsChanged,
                          onGitSettingsCleared: _handleGitSettingsCleared,
                          updateService: widget.updateService,
                          feedbackService: widget.feedbackService,
                          config: _config,
                          onConfigChanged: _handleConfigChanged,
                          onLanguageChanged: widget.onLanguageChanged,
                          onFavoriteTap: _openFavoriteAttachment,
                          onFavoriteRemove: _toggleFavoriteAttachment,
                          onCheckForUpdates: () =>
                              _checkForUpdates(automatic: false),
                          onNearbyStart: () =>
                              _setA2AConnectionAllowedFromSettings(true),
                          onNearbyStop: () =>
                              _setA2AConnectionAllowedFromSettings(false),
                          onNearbyInvite: () => _createA2AInvite('/a2a invite'),
                          onNearbyScan: () => _scanA2AInvite('/a2a scan'),
                          onNearbyDeletePeer: _deleteA2APairedPeer,
                          getNearbyPairingDiagnostic: () async =>
                              _lastA2APairingDiagnostic,
                          onNewSession: () {
                            _closeSessionHistory();
                            _startNewSession();
                          },
                          onRefreshSessions: _refreshVisibleSessions,
                          onSessionSelected: (sessionId) {
                            _closeSessionHistory();
                            _selectSession(sessionId);
                          },
                          onSessionPinToggle: _toggleSessionPin,
                          onSessionDelete: (sessionId) {
                            unawaited(_confirmDeleteSession(sessionId));
                          },
                          onPendingEvolutionChanged:
                              _refreshPendingEvolutionFromSkills,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (_activeRuntimeProfile.isDeveloper)
            AnimatedBuilder(
              animation: _workbenchDrawerController,
              builder: (context, _) {
                if (_workbenchDrawerController.value == 0) {
                  return const SizedBox.shrink();
                }

                final progress = Curves.easeOutCubic.transform(
                  _workbenchDrawerController.value,
                );
                final size = MediaQuery.sizeOf(context);

                return IgnorePointer(
                  ignoring: _workbenchDrawerController.value == 0,
                  child: Stack(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _closeWorkbenchDrawer,
                        child: ColoredBox(
                          color: Colors.black.withValues(
                            alpha: 0.18 * progress,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(size.width * (1 - progress), 0),
                        child: SizedBox(
                          width: size.width,
                          height: size.height,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onHorizontalDragUpdate:
                                _handleWorkbenchDrawerDragUpdate,
                            onHorizontalDragEnd: _handleWorkbenchDrawerDragEnd,
                            child: _WorkbenchRightDrawerPanel(
                              agentId: _activeAgentId,
                              activeScenarioId: _activeScenarioId,
                              createScenariosClientFuture:
                                  _buildScenariosClientFuture,
                              onClose: _closeWorkbenchDrawer,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          if (_browserPanelVisible &&
              browserBelongsToActiveSession &&
              MediaQuery.sizeOf(context).width >= 840)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 12,
              bottom: 12,
              width: math.min(MediaQuery.sizeOf(context).width * 0.46, 560),
              child: _BrowserSidePanel(
                controller: _browserController,
                onClose: _closeBrowserSidePanel,
              ),
            ),
          if (showMobileBrowserOverlay)
            Positioned.fill(
              child: _BrowserFullscreenPanel(
                controller: _browserController,
                onMinimize: _minimizeBrowserPanel,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Memory Pending Suggestions Sheet
// ---------------------------------------------------------------------------

class _MemoryPendingSheet extends StatefulWidget {
  const _MemoryPendingSheet({
    required this.clientFuture,
    required this.scrollController,
    required this.onApplied,
  });

  final Future<NapaxiChatClient> clientFuture;
  final ScrollController scrollController;
  final VoidCallback onApplied;

  @override
  State<_MemoryPendingSheet> createState() => _MemoryPendingSheetState();
}

class _MemoryPendingSheetState extends State<_MemoryPendingSheet> {
  late Future<List<Map<String, dynamic>>> _pendingFuture;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _pendingFuture = _loadPending();
  }

  Future<List<Map<String, dynamic>>> _loadPending() async {
    final client = await widget.clientFuture;
    final all = await client.listPendingEvolution();
    return all;
  }

  Future<void> _apply(Map<String, dynamic> item) async {
    final id = item['id'] as String? ?? '';
    if (id.isEmpty || _busyId != null) return;
    setState(() => _busyId = id);
    try {
      final client = await widget.clientFuture;
      await client.applyPendingEvolution(id);
      if (mounted) {
        final nextPending = _loadPending();
        setState(() {
          _pendingFuture = nextPending;
        });
        widget.onApplied();
      }
    } catch (_) {}
    if (mounted) setState(() => _busyId = null);
  }

  Future<void> _reject(Map<String, dynamic> item) async {
    final id = item['id'] as String? ?? '';
    if (id.isEmpty || _busyId != null) return;
    setState(() => _busyId = id);
    try {
      final client = await widget.clientFuture;
      await client.rejectPendingEvolution(id);
      if (mounted) {
        final nextPending = _loadPending();
        setState(() {
          _pendingFuture = nextPending;
        });
        widget.onApplied();
      }
    } catch (_) {}
    if (mounted) setState(() => _busyId = null);
  }

  @override
  Widget build(BuildContext context) {
    final isChinese =
        _AppLanguageScope.languageOf(context) == AppLanguage.chinese;

    return Column(
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            isChinese ? '待确认建议' : 'Pending Suggestions',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _pendingFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF111827)),
                );
              }
              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return Center(
                  child: Text(
                    isChinese ? '暂无待确认的建议' : 'No pending suggestions',
                    style: const TextStyle(color: Color(0xFF6B7280)),
                  ),
                );
              }
              return ListView.separated(
                controller: widget.scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final id = item['id'] as String? ?? '';
                  final isBusy = _busyId == id;
                  return _MemoryPendingCard(
                    item: item,
                    isBusy: isBusy,
                    isChinese: isChinese,
                    onApply: () => _apply(item),
                    onReject: () => _reject(item),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MemoryPendingCard extends StatelessWidget {
  const _MemoryPendingCard({
    required this.item,
    required this.isBusy,
    required this.isChinese,
    required this.onApply,
    required this.onReject,
  });

  final Map<String, dynamic> item;
  final bool isBusy;
  final bool isChinese;
  final VoidCallback onApply;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final actionType = (item['action_type'] as String? ?? '').toLowerCase();
    final action = _extractAction(item);
    final entryType = action['entry_type'] as String? ?? '';
    final content =
        action['content'] as String? ?? action['new_content'] as String? ?? '';
    final reasoning = item['reasoning'] as String? ?? '';
    final skillName = action['skill_name'] as String? ?? '';
    final reviewType = item['review_type'] as String? ?? '';

    final targetLabel = actionType.contains('memory')
        ? switch (entryType) {
            'user_profile' => 'USER.md',
            'project' => 'PROJECT.md',
            _ => 'MEMORY.md',
          }
        : skillName.isNotEmpty
        ? skillName
        : actionType;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  targetLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
              if (reviewType.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: reviewType == 'memory'
                        ? const Color(0xFFEFF6FF)
                        : const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    reviewType == 'memory'
                        ? (isChinese ? '记忆' : 'Memory')
                        : (isChinese ? '技能' : 'Skill'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: reviewType == 'memory'
                          ? const Color(0xFF1D4ED8)
                          : const Color(0xFF6D28D9),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _humanizeActionType(
                    item['action_type'] as String? ?? '',
                    entryType,
                  ),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF14532D),
                  ),
                ),
              ),
            ],
          ),
          if (content.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                content,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF374151),
                  height: 1.4,
                ),
              ),
            ),
          ],
          if (reasoning.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              reasoning,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF9CA3AF),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: isBusy ? null : onReject,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6B7280),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                ),
                child: Text(isChinese ? '忽略' : 'Ignore'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: isBusy ? null : onApply,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF111827),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 32),
                ),
                child: isBusy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(isChinese ? '确认写入' : 'Confirm'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _humanizeActionType(String actionType, String entryType) {
    if (actionType.toLowerCase().contains('memory')) {
      return switch (entryType) {
        'user_profile' => isChinese ? '用户画像' : 'User Profile',
        'project' => isChinese ? '项目记忆' : 'Project',
        _ => isChinese ? '长期记忆' : 'Memory',
      };
    }
    return switch (actionType.toLowerCase()) {
      'skillcreate' => isChinese ? '创建技能' : 'Create Skill',
      'skilledit' => isChinese ? '编辑技能' : 'Edit Skill',
      'skillpatch' => isChinese ? '更新技能' : 'Patch Skill',
      'skilldelete' => isChinese ? '删除技能' : 'Delete Skill',
      _ => actionType,
    };
  }

  Map<String, dynamic> _extractAction(Map<String, dynamic> item) {
    final action = item['action'] as Map<String, dynamic>? ?? {};
    if (action.isNotEmpty) return action;
    final actions = item['aggregated_actions'] as List? ?? [];
    if (actions.isNotEmpty) {
      return (actions.first as Map<String, dynamic>?) ?? {};
    }
    return {};
  }
}

enum _UpdateInstallStage {
  idle,
  downloading,
  installerOpened,
  permissionRequired,
  failed,
}
