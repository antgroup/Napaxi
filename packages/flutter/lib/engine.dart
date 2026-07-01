import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:meta/meta.dart';
import 'models/config.dart';
import 'models/chat_event.dart';
import 'models/custom_tool.dart';
import 'models/evolution.dart';
import 'models/session.dart';
import 'models/agent.dart';
import 'models/skill.dart';
import 'models/group.dart';
import 'models/workspace.dart';
import 'models/background.dart';
import 'models/capability.dart';
import 'models/channel.dart';
import 'models/agent_app.dart';
import 'agent_engine.dart';
import 'mcp.dart';
import 'file_bridge.dart';
import 'platform_context.dart';
import 'tool_executor.dart';
import 'browser_controller.dart';
import 'browser_tool_host.dart';
import 'platform_tools/capability_host.dart';
import 'platform_tools/platform_tool_provider.dart';
import 'background/background_controller.dart';
import 'background/automation_scheduler.dart';
import 'api/agent_api.dart';
import 'api/background_api.dart';
import 'api/capability_api.dart';
import 'api/channel_api.dart';
import 'api/channel_provider_host.dart';
import 'api/chat_api.dart';
import 'api/group_api.dart';
import 'api/json_codec.dart';
import 'api/session_api.dart';
import 'api/session_run_api.dart';
import 'api/skill_api.dart';
import 'api/agent_app_api.dart';
import 'api/a2a_api.dart';
import 'api/automation_api.dart';
import 'api/evolution_api.dart';
import 'api/tool_api.dart';
import 'api/workspace_api.dart';
import 'generated/bridge/file_bridge.dart' as rust_file_bridge;
import 'generated/bridge/init.dart' as rust_init;
import 'generated/bridge/session.dart' as rust_session;
import 'generated/frb_generated.dart';

part 'api/engine_core.dart';

/// An attachment (image, document, audio) to send with a message.
class McAttachment {
  /// Kind: "image", "document", or "audio".
  final String kind;

  /// MIME type (e.g. "image/jpeg", "application/pdf").
  final String mimeType;

  /// Original filename, if known.
  final String? filename;

  /// Sandbox path for metadata/history restoration, if the attachment has one.
  final String? sandboxPath;

  /// Original host/local file path, if the user selected a local file.
  final String? localPath;

  /// Raw file bytes.
  final Uint8List data;

  /// Pre-extracted text content (for documents: full text; for audio: transcript).
  final String? extractedText;

  const McAttachment({
    required this.kind,
    required this.mimeType,
    this.filename,
    this.sandboxPath,
    this.localPath,
    required this.data,
    this.extractedText,
  });

  Map<String, dynamic> toMap({String? sandboxPath}) {
    final effectiveSandboxPath = sandboxPath ?? this.sandboxPath;
    return {
      'kind': kind,
      'mime_type': mimeType,
      if (filename != null) 'filename': filename,
      if (effectiveSandboxPath != null) 'sandbox_path': effectiveSandboxPath,
      if (localPath != null) 'path': localPath,
      'data_base64': base64Encode(data),
      if (extractedText != null) 'extracted_text': extractedText,
    };
  }
}

String _encodeAttachments(
  List<McAttachment>? attachments, {
  List<String>? sandboxPaths,
}) {
  if (attachments == null || attachments.isEmpty) return '[]';
  return jsonEncode([
    for (var i = 0; i < attachments.length; i++)
      attachments[i].toMap(
        sandboxPath: sandboxPaths != null && i < sandboxPaths.length
            ? sandboxPaths[i]
            : null,
      ),
  ]);
}

/// Napaxi AI Agent 引擎
///
/// 提供完整的 AI Agent 能力，包括对话、会话管理、多 Agent、群组协作等。
/// 不包含 UI，所有界面由集成方实现。
///
/// ## 使用示例
///
/// ```dart
/// final engine = await NapaxiEngine.create(
///   config: LlmConfig(provider: 'anthropic', apiKey: 'sk-xxx', model: 'claude-sonnet-4-6'),
/// );
///
/// // 简单对话
/// engine.send('你好').listen((event) {
///   if (event is ResponseEvent) print(event.content);
/// });
///
/// // 多 Agent
/// final agent = await engine.getOrCreateAgent('travel', config: travelConfig);
/// final session = await engine.createSession(channelType: 'app', accountId: 'user1');
/// engine.agentSend(agent, session, '搜索北京到上海的机票').listen(...);
///
/// engine.dispose();
/// ```
class NapaxiEngine {
  static const String defaultAgentId = 'napaxi';
  static const String defaultAccountId = 'default';

  final int _handle;
  LlmConfig _config;
  final McToolExecutor? _toolExecutor;
  final AgentEngineExecutor? _agentEngineExecutor;
  final AgentAppActionExecutor? _agentAppActionExecutor;
  final McToolApprovalHandler? _toolApprovalHandler;
  final McToolResultObserver? _toolResultObserver;
  final FlutterCapabilityHost? _platformToolExecutor;
  final FlutterBrowserToolHost? _browserToolHost;
  final NapaxiBackgroundController? _backgroundController;
  final NapaxiAutomationScheduler? _automationScheduler;
  final bool _automationEnabled;
  final String filesDir;
  late final EngineCore _core;

  /// MCP server management API.
  late final McpApi mcp;
  late final ChatApi chat;
  late final SessionApi sessions;
  late final SessionRunApi sessionRuns;
  late final AgentApi agents;
  late final WorkspaceApi workspace;
  late final SkillApi skills;
  late final GroupApi groups;
  late final BackgroundApi background;
  late final ToolApi tools;
  late final CapabilityApi capabilities;
  late final ChannelApi channels;
  late final ChannelAgentApi channelAgents;
  late final NapaxiChannelProviderHost channelProviders;
  late final AgentAppApi agentApp;
  late final A2AApi a2a;
  late final AutomationApi automation;
  late final EvolutionApi evolution;

  NapaxiEngine._(
    this._handle,
    this._config,
    this._toolExecutor,
    this._agentEngineExecutor,
    this._agentAppActionExecutor,
    this._toolApprovalHandler,
    this._toolResultObserver,
    this._platformToolExecutor,
    this._browserToolHost,
    this._backgroundController,
    this._automationScheduler,
    this._automationEnabled,
    this.filesDir,
  ) {
    // The shared session-run / background / tool-listener state machine. Built
    // first so the entangled facades (chat/tools/background/sessions) can call
    // it directly instead of routing through engine shims.
    _core = EngineCore(this);
    mcp = McpApi(() => _handle, defaultAccountId);
    chat = ChatApi(_core);
    sessions = SessionApi(this, _core);
    sessionRuns = SessionRunApi(() => _handle);
    agents = AgentApi(() => _handle, config: () => _config);
    workspace = WorkspaceApi(() => _handle, config: () => _config);
    skills = SkillApi(() => _handle, config: () => _config);
    groups = GroupApi(() => _handle, config: () => _config);
    background = BackgroundApi(_core);
    tools = ToolApi(_core);
    capabilities = CapabilityApi(
      () => _handle,
      defaultProfile: _defaultCapabilityProfile(),
    );
    channels = ChannelApi(() => _handle);
    channelAgents = ChannelAgentApi(() => _handle);
    channelProviders = NapaxiChannelProviderHost(channels);
    agentApp = AgentAppApi(() => _handle);
    a2a = A2AApi(() => _handle);
    automation = AutomationApi(() => _handle);
    evolution = EvolutionApi(() => _handle);
    _automationScheduler?.startWakeListener();
  }

  static bool _rustLibInitialized = false;

  McpApi mcpForAccount(String accountId) {
    final effectiveAccountId = accountId.trim().isEmpty
        ? defaultAccountId
        : accountId.trim();
    return McpApi(() => _handle, effectiveAccountId);
  }

  NapaxiCapabilityProfile? _defaultCapabilityProfile() {
    String? platform;
    try {
      if (Platform.isAndroid) {
        platform = 'android';
      } else if (Platform.isIOS) {
        platform = 'ios';
      }
    } catch (_) {
      platform = null;
    }
    return NapaxiCapabilityProfile(
      platform: platform,
      supportedCapabilities: [
        NapaxiChannelCapability.im,
        NapaxiChannelCapability.device,
        if (_toolExecutor != null) 'napaxi.tool.custom_host',
        if (_agentEngineExecutor != null) 'napaxi.agent_engine.external_host',
        if (_agentAppActionExecutor != null) 'napaxi.tool.agent_app_action',
        if (_platformToolExecutor != null) 'napaxi.platform_tool.*',
        if (_browserToolHost != null) BrowserToolProvider.capabilityId,
        if (_automationEnabled) 'napaxi.service.automation',
      ],
    );
  }

  /// The background controller, or null if background execution is not enabled.
  NapaxiBackgroundController? get backgroundController => _backgroundController;

  /// Host-carried mobile scheduler for automation jobs.
  NapaxiAutomationScheduler? get automationScheduler => _automationScheduler;

  /// Update background notification copy without rebuilding the engine.
  void updateBackgroundConfig(BackgroundConfig config) =>
      _core.updateBackgroundConfig(config);

  /// Stream of user actions from background notifications.
  ///
  /// Listen to this to handle "View Result" taps and other notification interactions.
  /// This is a convenience accessor for the background controller's
  /// [NapaxiBackgroundController.onAction] stream.
  Stream<BackgroundActionEvent> get onBackgroundAction =>
      _backgroundController?.onAction ?? const Stream.empty();

  /// In-memory updates for SDK session runs owned by this engine instance.
  Stream<SessionRunInfo> get sessionRunUpdates => _core.sessionRunUpdates;

  /// Snapshot of non-terminal runs currently active in this process.
  List<SessionRunInfo> get activeSessionRuns => _core.activeSessionRuns;

  // ==========================================================================
  // 引擎生命周期
  // ==========================================================================

  /// 创建引擎实例
  static Future<NapaxiEngine> create({
    required LlmConfig config,
    McToolExecutor? toolExecutor,
    AgentEngineExecutor? agentEngineExecutor,
    AgentAppActionExecutor? agentAppActionExecutor,
    McToolApprovalHandler? toolApprovalHandler,
    McToolResultObserver? toolResultObserver,
    NapaxiBrowserController? browserController,
    BrowserMutationPolicy browserMutationPolicy =
        BrowserMutationPolicy.requireApproval,
    bool? enablePlatformTools,
    BackgroundConfig? backgroundConfig,
    bool? enableAutomation,
    NapaxiCapabilityProfile? capabilityProfile,
    NapaxiCapabilitySelection? capabilitySelection,
  }) async {
    if (!_rustLibInitialized) {
      // On iOS, the Rust static library is linked into the Runner binary.
      // We must use DynamicLibrary.process() instead of DynamicLibrary.open().
      if (Platform.isIOS) {
        await RustLib.init(
          externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true),
        );
      } else {
        await RustLib.init();
      }
      _rustLibInitialized = true;
    }

    final platformContext = await NapaxiPlatformContextResolver.resolve();
    final platformContextMap = decodeJsonObject(
      platformContext.platformContextJson,
    );
    final platformToolsEnabled =
        enablePlatformTools ?? PlatformToolProvider.isSupported;
    final automationEnabled = enableAutomation ?? backgroundConfig != null;
    final effectiveCapabilityProfile =
        capabilityProfile ??
        _buildHostCapabilityProfile(
          platform: platformContextMap['platform'] as String?,
          hasCustomToolExecutor: toolExecutor != null,
          hasAgentEngineExecutor: agentEngineExecutor != null,
          hasAgentAppActionExecutor: agentAppActionExecutor != null,
          hasBrowserController: browserController != null,
          enablePlatformTools: platformToolsEnabled,
          enableAutomation: automationEnabled,
        );
    platformContextMap['capability_profile'] = effectiveCapabilityProfile
        .toJson();
    platformContextMap['skill_readiness'] = {
      'platform': platformContextMap['platform'],
      'capabilities': effectiveCapabilityProfile.supportedCapabilities,
      'use_process_fallback': false,
    };
    final effectiveCapabilitySelection =
        capabilitySelection ??
        _buildHostCapabilitySelection(
          hasCustomToolExecutor: toolExecutor != null,
          hasAgentEngineExecutor: agentEngineExecutor != null,
          hasAgentAppActionExecutor: agentAppActionExecutor != null,
          hasBrowserController: browserController != null,
          enableAutomation: automationEnabled,
        );
    platformContextMap['capability_selection'] = effectiveCapabilitySelection
        .toJson();
    final handle = rust_init.createEngine(
      configJson: config.toJson(),
      platformContextJson: jsonEncode(platformContextMap),
    );
    if (handle == 0) throw Exception('Failed to create Napaxi engine');
    final platformTools = platformToolsEnabled
        ? FlutterCapabilityHost(filesDir: platformContext.filesDir)
        : null;
    final browserToolHost = browserController == null
        ? null
        : FlutterBrowserToolHost(
            controller: browserController,
            approvalHandler: toolApprovalHandler,
            mutationPolicy: browserMutationPolicy,
          );

    // Initialize background controller if configured and supported
    NapaxiBackgroundController? bgController;
    if (backgroundConfig != null &&
        backgroundConfig.enabled &&
        isBackgroundExecutionSupported()) {
      bgController = NapaxiBackgroundController(backgroundConfig);
    }

    NapaxiFileBridge.init(filesDir: platformContext.filesDir, handle: handle);

    final engine = NapaxiEngine._(
      handle,
      config,
      toolExecutor,
      agentEngineExecutor,
      agentAppActionExecutor,
      toolApprovalHandler,
      toolResultObserver,
      platformTools,
      browserToolHost,
      bgController,
      automationEnabled
          ? NapaxiAutomationScheduler(AutomationApi(() => handle))
          : null,
      automationEnabled,
      platformContext.filesDir,
    );
    engine._core.startToolRequestListener();
    return engine;
  }

  static NapaxiCapabilityProfile _buildHostCapabilityProfile({
    required String? platform,
    required bool hasCustomToolExecutor,
    required bool hasAgentEngineExecutor,
    required bool hasAgentAppActionExecutor,
    required bool hasBrowserController,
    required bool enablePlatformTools,
    required bool enableAutomation,
  }) {
    return NapaxiCapabilityProfile(
      platform: platform,
      supportedCapabilities: [
        NapaxiChannelCapability.im,
        NapaxiChannelCapability.device,
        if (hasCustomToolExecutor) 'napaxi.tool.custom_host',
        if (hasAgentEngineExecutor) 'napaxi.agent_engine.external_host',
        if (hasAgentAppActionExecutor) 'napaxi.tool.agent_app_action',
        if (enablePlatformTools) 'napaxi.platform_tool.*',
        if (hasBrowserController) BrowserToolProvider.capabilityId,
        if (enableAutomation) 'napaxi.service.automation',
      ],
    );
  }

  static NapaxiCapabilitySelection _buildHostCapabilitySelection({
    required bool hasCustomToolExecutor,
    required bool hasAgentEngineExecutor,
    required bool hasAgentAppActionExecutor,
    required bool hasBrowserController,
    required bool enableAutomation,
  }) {
    return NapaxiCapabilitySelection(
      enabledCapabilities: [
        NapaxiChannelCapability.im,
        NapaxiChannelCapability.device,
        if (hasCustomToolExecutor) 'napaxi.tool.custom_host',
        if (hasAgentEngineExecutor) 'napaxi.agent_engine.external_host',
        if (hasAgentAppActionExecutor) 'napaxi.tool.agent_app_action',
        if (hasBrowserController) BrowserToolProvider.capabilityId,
        if (enableAutomation) 'napaxi.service.automation',
      ],
    );
  }

  /// 获取当前配置
  LlmConfig get config => _config;

  /// 热更新 LLM 配置（不重建 Agent）
  bool updateConfig(LlmConfig newConfig) {
    final result = rust_init.updateConfig(
      handle: _handle,
      configJson: newConfig.toJson(),
    );
    if (result) _config = newConfig;
    return result;
  }

  /// 预创建默认 Agent（"napaxi"），确保 listSkills 等 API 可立即使用。
  ///
  /// 如果 Agent 已存在则立即返回 true。通常在进入 Agent 页面时调用。
  bool ensureAgent() {
    return rust_init.ensureAgentReady(
      handle: _handle,
      configJson: _config.toJson(),
    );
  }

  /// 销毁引擎
  void dispose() {
    _core.dispose();
    channelProviders.dispose();
    _automationScheduler?.dispose();
    _backgroundController?.dispose();
    rust_init.disposeEngine(handle: _handle);
  }

  // ==========================================================================
  // 后台执行（Background Execution）
  // ==========================================================================

  bool hasActiveSessionRun(SessionKey key, {String agentId = defaultAgentId}) =>
      _core.hasActiveSessionRun(key, agentId: agentId);

  SessionRunInfo? activeSessionRun(
    SessionKey key, {
    String agentId = defaultAgentId,
  }) => _core.activeSessionRun(key, agentId: agentId);

  /// Start the background foreground service manually.
  ///
  /// This is called automatically by [send] and [sendToSession] when
  /// [BackgroundConfig] is enabled. Call this directly if you need to
  /// start the service before sending a message (e.g., during setup).
  Future<void> startBackgroundService() => _core.startBackgroundService();

  /// Stop the background foreground service manually.
  Future<void> stopBackgroundService() => _core.stopBackgroundService();

  // ==========================================================================
  // 自定义工具（Custom Tools）
  // ==========================================================================

  /// Register/update custom tools.
  ///
  /// Custom tools are executed on the Dart side when called by the AI agent.
  /// The [McToolExecutor] passed to [create] handles tool execution.
  /// Built-in platform tools are automatically merged when enabled.
  ///
  /// Call [startToolRequestListener] first to set up the request stream.
  bool updateCustomTools(List<CustomToolDef> tools) =>
      _core.updateCustomTools(tools);

  /// Start listening for custom tool requests from the Rust engine.
  ///
  /// When a custom tool executes, the engine sends a request via a stream.
  /// This method processes requests using the [McToolExecutor] and forwards
  /// results back to the engine over the bridge.
  ///
  /// Must be called before [updateCustomTools] to register the stream.
  void startToolRequestListener() => _core.startToolRequestListener();

  // ==========================================================================
  // 对话（核心）
  // ==========================================================================

  /// 发消息到默认 Agent，返回事件流（实时流式推送）
  ///
  /// 如果配置了 [BackgroundConfig]，会自动：
  /// - 启动 Foreground Service 保持后台运行
  /// - 根据事件更新通知状态（工具调用进度、HITL 确认、完成/错误）
  /// - 流结束后停止 Foreground Service
  Stream<ChatEvent> send(
    String message, {
    List<McAttachment>? attachments,
    int maxIterations = 0,
  }) => _core.send(
    message,
    attachments: attachments,
    maxIterations: maxIterations,
  );

  /// 向指定会话发送消息（实时流式推送）
  ///
  /// 当 [attachments] 非空时，附件元数据会自动持久化到本地，
  /// 后续 [getHistory] 可恢复。[sandboxPaths] 用于记录沙箱路径。
  ///
  /// 如果配置了 [BackgroundConfig]，会自动管理 Foreground Service 和通知。
  Stream<ChatEvent> sendToSession(
    SessionKey sessionKey,
    String message, {
    String agentId = defaultAgentId,
    List<McAttachment>? attachments,
    List<String>? sandboxPaths,
    int? userMsgIndex,
    int maxIterations = 0,
  }) => _core.sendToSession(
    sessionKey,
    message,
    agentId: agentId,
    attachments: attachments,
    sandboxPaths: sandboxPaths,
    userMsgIndex: userMsgIndex,
    maxIterations: maxIterations,
  );

  /// 向正在运行的 Agent 会话注入用户消息（HITL Phase 1）
  ///
  /// 消息会在 Agent 下一轮循环迭代时被注入到上下文中。
  /// 可选传入附件（如图片）使 Agent 在下一轮也能看到。
  /// 返回 true 表示入队成功，false 表示线程未找到或队列已满。
  Future<bool> injectMessage(
    SessionKey sessionKey,
    String message, {
    String agentId = defaultAgentId,
    List<McAttachment>? attachments,
  }) => _core.injectMessage(
    sessionKey,
    message,
    agentId: agentId,
    attachments: attachments,
  );

  /// Retract the latest queued injected message matching [message].
  Future<bool> retractInjectedMessage(SessionKey sessionKey, String message) =>
      _core.retractInjectedMessage(sessionKey, message);

  /// Answer a pending [AskingHumanEvent] request.
  Future<bool> answerHumanRequest(String requestId, String response) =>
      _core.answerHumanRequest(requestId, response);

  /// 取消正在运行的会话（中断当前 Agent 处理）
  ///
  /// 设置线程状态为 Interrupted，agentic loop 会在下一个检查点停止。
  /// 返回 true 表示中断成功，false 表示线程未找到。
  Future<bool> cancelSession(
    SessionKey sessionKey, {
    String agentId = defaultAgentId,
  }) => _core.cancelSession(sessionKey, agentId: agentId);

  // NOTE: evolution logic now lives in `EvolutionApi` (engine.evolution).
  // These flat methods are forwarding shims; deprecated at P4, removed at 1.0.

  /// List pending self-evolution suggestions awaiting user confirmation.
  List<Map<String, dynamic>> listPendingEvolution() => evolution.listPending();

  /// Apply a pending self-evolution suggestion by ID.
  Future<Map<String, dynamic>> applyPendingEvolution(String pendingId) =>
      evolution.applyPending(pendingId);

  /// Reject a pending self-evolution suggestion by ID.
  Future<Map<String, dynamic>> rejectPendingEvolution(String pendingId) =>
      evolution.rejectPending(pendingId);

  /// List self-evolution review runs, optionally filtered by run IDs.
  List<EvolutionRun> listEvolutionRuns({List<String>? runIds}) =>
      evolution.runs(runIds: runIds);

  /// List persisted self-evolution diagnostics.
  List<EvolutionDiagnostic> listEvolutionDiagnostics() =>
      evolution.diagnostics();

  /// Run a skill consolidation review that only proposes pending actions.
  Future<SkillConsolidationReviewResult> runSkillConsolidationReview({
    String agentId = defaultAgentId,
    bool dryRun = true,
  }) => skills.runConsolidationReview(agentId: agentId, dryRun: dryRun);

  // ==========================================================================
  // 会话管理
  // ==========================================================================

  /// 创建或恢复会话
  Future<SessionKey> createSession({
    String agentId = defaultAgentId,
    String channelType = 'app',
    String accountId = defaultAccountId,
    String? threadId,
  }) async {
    final json = await rust_session.createSession(
      handle: _handle,
      configJson: _config.toJson(),
      agentId: agentId,
      channelType: channelType,
      accountId: accountId,
      existingThreadId: threadId,
    );
    return SessionKey.fromJson(json);
  }

  /// 列出所有会话
  Future<List<SessionInfo>> listSessions({
    String agentId = defaultAgentId,
    String accountId = defaultAccountId,
  }) async {
    final json = await rust_session.listSessions(
      handle: _handle,
      configJson: _config.toJson(),
      agentId: agentId,
      accountId: accountId,
    );
    return decodeJsonObjectList(
      json,
      (item) => SessionInfo.fromJson(jsonEncode(item)),
    );
  }

  /// 删除会话（Rust 侧同时清理附件 metadata）
  Future<bool> deleteSession(
    SessionKey sessionKey, {
    String agentId = defaultAgentId,
  }) {
    return rust_session.deleteSession(
      handle: _handle,
      configJson: _config.toJson(),
      agentId: agentId,
      sessionKeyJson: sessionKey.toJson(),
    );
  }

  /// 清空会话历史（Rust 侧同时清理附件 metadata）
  Future<bool> clearSession(
    SessionKey sessionKey, {
    String agentId = defaultAgentId,
  }) {
    return rust_session.clearSession(
      handle: _handle,
      configJson: _config.toJson(),
      agentId: agentId,
      sessionKeyJson: sessionKey.toJson(),
    );
  }

  /// 获取对话历史（Rust 侧自动合并附件元数据）
  Future<List<ChatMessage>> getHistory(
    String threadId, {
    String agentId = defaultAgentId,
  }) async {
    final json = await rust_session.getHistory(
      handle: _handle,
      configJson: _config.toJson(),
      agentId: agentId,
      threadId: threadId,
    );
    return decodeJsonObjectList(json, ChatMessage.fromMap);
  }

  /// 分页获取对话历史（Rust 侧自动合并附件元数据）。
  ///
  /// [before] is an RFC3339 timestamp cursor returned by the previous page.
  Future<HistoryPage> getHistoryPage(
    String threadId, {
    String agentId = defaultAgentId,
    String? before,
    int limit = 80,
  }) async {
    final json = await rust_session.getHistoryPage(
      handle: _handle,
      configJson: _config.toJson(),
      agentId: agentId,
      threadId: threadId,
      before: before,
      limit: limit,
    );
    return HistoryPage.fromJson(json);
  }

  /// Force compaction for a session and return the updated context status.
  Future<ContextStatus> compactContext(
    SessionKey sessionKey, {
    String agentId = defaultAgentId,
    String? focus,
  }) async {
    final json = await rust_session.compactContext(
      handle: _handle,
      configJson: _config.toJson(),
      agentId: agentId,
      sessionKeyJson: sessionKey.toJson(),
      focus: focus,
    );
    return ContextStatus.fromJson(json);
  }

  /// Read the persisted context compaction state for a session thread.
  Future<ContextStatus> contextStatus(
    String threadId, {
    String agentId = defaultAgentId,
  }) async {
    final json = await rust_session.contextStatus(
      handle: _handle,
      configJson: _config.toJson(),
      agentId: agentId,
      threadId: threadId,
    );
    return ContextStatus.fromJson(json);
  }

  /// Save attachment metadata for a user message without sending it.
  bool saveAttachmentMetadata({
    required String threadId,
    required int userMsgIndex,
    required List<ChatAttachment> attachments,
  }) {
    if (attachments.isEmpty) return true;
    return rust_file_bridge.saveMessageAttachments(
      handle: _handle,
      threadId: threadId,
      userMsgIndex: userMsgIndex,
      attachmentsJson: jsonEncode(attachments.map((a) => a.toMap()).toList()),
    );
  }

  // ==========================================================================
  // 多 Agent
  // ==========================================================================

  // NOTE: agent + agent-definition logic now lives in `AgentApi`
  // (engine.agents). These flat methods are forwarding shims kept for
  // backwards compatibility and Android/iOS engine-parity; deprecated at P4,
  // removed at 1.0.

  /// 获取或创建 Agent
  Future<AgentHandle> getOrCreateAgent(String agentId, {LlmConfig? config}) =>
      agents.getOrCreate(agentId, config: config);

  /// 列出所有 Agent ID
  List<String> listAgents() => agents.list();

  /// 删除 Agent
  bool deleteAgent(String agentId) => agents.delete(agentId);

  /// 向指定 Agent 发消息
  Stream<ChatEvent> agentSend(
    AgentHandle agent,
    SessionKey session,
    String message, {
    LlmConfig? config,
    int maxIterations = 0,
  }) => agents.send(
    agent,
    session,
    message,
    config: config,
    maxIterations: maxIterations,
  );

  // ==========================================================================
  // Skill 管理
  // ==========================================================================

  // NOTE: skill logic now lives in SkillApi (engine.skills); these are
  // forwarding shims, deprecated at P4, removed at 1.0.

  /// 列出指定 Agent 的所有 Skill
  List<SkillInfo> listSkills({String agentId = ''}) =>
      skills.list(agentId: agentId);

  SkillStatusReport listSkillStatus({String agentId = ''}) =>
      skills.status(agentId: agentId);

  SkillSourceReport listSkillSources({String agentId = ''}) =>
      skills.sources(agentId: agentId);

  Future<SkillRefreshResult> recordSkillSourceChanged(
    String sourceId, {
    String agentId = '',
  }) => skills.recordSourceChanged(sourceId, agentId: agentId);

  SkillStatusEntry? getSkillStatus(String skillName, {String agentId = ''}) =>
      skills.getStatus(skillName, agentId: agentId);

  SkillStatusReport checkSkills({String agentId = ''}) =>
      skills.check(agentId: agentId);

  SkillCommandReport listSkillCommands({String agentId = ''}) =>
      skills.commands(agentId: agentId);

  SkillCommandResolution resolveSkillCommand(
    String text, {
    String agentId = '',
  }) => skills.resolveCommand(text, agentId: agentId);

  Future<SkillCommandRun> runSkillCommand(
    String commandName, {
    String agentId = '',
    String? args,
    SessionKey? sessionKey,
  }) => skills.runCommand(commandName, agentId: agentId, args: args);

  Future<String> setSkillEnabled(
    String skillName, {
    String agentId = '',
    required bool enabled,
  }) => skills.setEnabled(skillName, agentId: agentId, enabled: enabled);

  Future<String> updateSkillConfig(
    String skillKey,
    Map<String, dynamic> patch, {
    String agentId = '',
  }) => skills.updateConfig(skillKey, patch, agentId: agentId);

  List<SkillRemediationAction> listSkillRemediationActions(
    String skillName, {
    String agentId = '',
  }) => skills.remediationActions(skillName, agentId: agentId);

  SkillSnapshotList listSkillSnapshots({
    String agentId = '',
    int limit = 50,
    int offset = 0,
  }) => skills.snapshots(agentId: agentId, limit: limit, offset: offset);

  SkillSnapshot? getSkillSnapshot(String snapshotId) =>
      skills.snapshot(snapshotId);

  SkillSecretRequirementReport listSkillSecretRequirements({
    String agentId = '',
    String? skillName,
  }) => skills.secretRequirements(agentId: agentId, skillName: skillName);

  Future<SkillStatusReport> recordSkillSecretAvailability(
    String skillName,
    String key, {
    String agentId = '',
    required bool available,
    String source = 'host',
  }) => skills.recordSecretAvailability(
    skillName,
    key,
    agentId: agentId,
    available: available,
    source: source,
  );

  Future<SkillRemediationRun> requestSkillRemediation(
    String skillName,
    String actionId, {
    String agentId = '',
  }) => skills.requestRemediation(skillName, actionId, agentId: agentId);

  Future<SkillRemediationRun> updateSkillRemediationRun(
    String runId,
    String status, {
    String agentId = '',
    Map<String, dynamic>? result,
  }) => skills.updateRemediationRun(
    runId,
    status,
    agentId: agentId,
    result: result,
  );

  SkillRemediationRunList listSkillRemediationRuns({
    String agentId = '',
    String? skillName,
    int limit = 50,
    int offset = 0,
  }) => skills.remediationRuns(
    agentId: agentId,
    skillName: skillName,
    limit: limit,
    offset: offset,
  );

  Future<String> recordSkillRequirementResolution(
    String skillName,
    String actionId,
    Map<String, dynamic> result, {
    String agentId = '',
  }) => skills.recordRequirementResolution(
    skillName,
    actionId,
    result,
    agentId: agentId,
  );

  /// 获取单个 Skill 详情
  SkillInfo? getSkill(String skillName, {String agentId = ''}) =>
      skills.get(skillName, agentId: agentId);

  /// 安装 Skill，既支持原始 SKILL.md，也支持附带支持文件的 bundle。
  Future<SkillInstallResult> installSkill(
    Object skill, {
    String agentId = '',
  }) => skills.install(skill, agentId: agentId);

  /// 移除 Skill
  Future<bool> removeSkill(String skillName, {String agentId = ''}) =>
      skills.remove(skillName, agentId: agentId);

  /// 重新发现并加载所有 Skill
  Future<List<String>> reloadSkills({String agentId = ''}) =>
      skills.reload(agentId: agentId);

  List<SkillUsageRecord> listSkillUsage({String agentId = ''}) =>
      skills.usage(agentId: agentId);

  Future<String> pinSkill(
    String skillName, {
    String agentId = '',
    bool pinned = true,
  }) => pinned
      ? skills.pin(skillName, agentId: agentId)
      : skills.unpin(skillName, agentId: agentId);

  Future<String> archiveSkill(String skillName, {String agentId = ''}) =>
      skills.archive(skillName, agentId: agentId);

  Future<String> restoreSkill(String skillName, {String agentId = ''}) =>
      skills.restore(skillName, agentId: agentId);

  Future<CuratorRunSummary> runSkillCurator({
    String agentId = '',
    bool dryRun = true,
  }) => skills.runCurator(agentId: agentId, dryRun: dryRun);

  Future<SkillSupportFileReadResult> readSkillSupportFile(
    String skillName,
    String filePath, {
    String agentId = '',
  }) => skills.readSupportFile(skillName, filePath, agentId: agentId);

  // ==========================================================================
  // Skill catalog provider (currently backed by ClawHub).
  // ==========================================================================

  /// 搜索当前技能目录提供方。
  Future<String> searchCatalog(String query) => skills.searchCatalog(query);

  /// 浏览当前技能目录提供方的包列表。
  ///
  /// 这是 catalog 的通用分页入口，宿主 App 可用它实现默认商店、
  /// 最近更新或推荐列表 UI；具体排序由目录服务端决定。
  Future<CatalogPackagePage> listCatalogPackages({
    int limit = 50,
    String? cursor,
  }) => skills.listCatalogPackages(limit: limit, cursor: cursor);

  /// 获取技能目录详情。
  Future<String> getCatalogSkill(String slug) => skills.getCatalogSkill(slug);

  /// 从技能目录下载并安装 Skill。
  Future<String> installFromCatalog(String slug, {String agentId = ''}) =>
      skills.installFromCatalog(slug, agentId: agentId);

  // ==========================================================================
  // Agent 定义（CRUD）
  // ==========================================================================

  /// 创建 Agent 定义
  Future<AgentDefinition> createAgentDefinition(AgentDefinition def) =>
      agents.createDefinition(def);

  /// 列出所有 Agent 定义
  Future<List<AgentDefinition>> listAgentDefinitions() =>
      agents.listDefinitions();

  /// 获取单个 Agent 定义
  Future<AgentDefinition?> getAgentDefinition(String defId) =>
      agents.getDefinition(defId);

  /// 更新 Agent 定义
  Future<bool> updateAgentDefinition(AgentDefinition def) =>
      agents.updateDefinition(def);

  /// 删除 Agent 定义
  Future<bool> deleteAgentDefinition(String defId) =>
      agents.deleteDefinition(defId);

  /// 从 AGENT.md 导入 Agent 定义
  Future<AgentDefinition> importAgentMd(String content) =>
      agents.importMarkdown(content);

  /// 列出所有可用工具
  Future<List<ToolInfo>> listAvailableTools() => agents.listAvailableTools();

  /// 从定义创建 Agent 实例
  Future<bool> createAgentFromDefinition(String defId, {LlmConfig? config}) =>
      agents.createFromDefinition(defId, config: config);

  // ==========================================================================
  // 群组协作
  // ==========================================================================

  // NOTE: group logic now lives in `GroupApi` (engine.groups). These flat
  // methods are forwarding shims kept for backwards compatibility and
  // Android/iOS engine-parity; they will be deprecated (P4) and removed at 1.0.

  /// 创建群组
  Future<String> createGroup(String name, List<String> memberAgentIds) =>
      groups.create(name, memberAgentIds);

  /// 删除群组
  bool deleteGroup(String groupId) => groups.delete(groupId);

  /// 列出所有群组
  List<GroupInfo> listGroups() => groups.list();

  /// 获取群组信息
  GroupInfo? getGroup(String groupId) => groups.get(groupId);

  /// 重命名群组
  bool renameGroup(String groupId, String newName) =>
      groups.rename(groupId, newName);

  /// 更新群组成员
  Future<bool> updateGroupMembers(
    String groupId,
    List<String> memberAgentIds,
  ) => groups.updateMembers(groupId, memberAgentIds);

  /// 设置群组自定义指令
  bool setGroupCustomPrompt(String groupId, String? prompt) =>
      groups.setCustomPrompt(groupId, prompt);

  /// 获取群组消息历史
  List<GroupMessage> getGroupMessages(String groupId) =>
      groups.messages(groupId);

  /// 清空群组历史
  bool clearGroupHistory(String groupId) => groups.clearHistory(groupId);

  /// 向群组发送消息（触发 coordinator → 成员委托流程）
  Stream<ChatEvent> sendToGroup(
    String groupId,
    String message, {
    int maxIterations = 0,
  }) => groups.send(groupId, message, maxIterations: maxIterations);

  /// 向群组内指定 Agent 发送消息
  Stream<ChatEvent> sendToGroupAgent(
    String groupId,
    String agentId,
    SessionKey session,
    String message, {
    int maxIterations = 0,
  }) => groups.sendToAgent(
    groupId,
    agentId,
    session,
    message,
    maxIterations: maxIterations,
  );

  /// 导出群组状态（用于持久化）
  String exportGroupState() => groups.exportState();

  /// 恢复群组状态
  Future<bool> importGroupState(String stateJson) =>
      groups.importState(stateJson);

  // ==========================================================================
  // Workspace（记忆与人格）
  // ==========================================================================

  // NOTE: workspace logic now lives in `WorkspaceApi` (engine.workspace). These
  // flat methods are forwarding shims kept for backwards compatibility and
  // Android/iOS engine-parity; they will be deprecated (P4) and removed at 1.0.
  // They preserve the engine's historical defaults (agentId = '') by forwarding
  // explicitly.

  /// 读取 workspace 文件。返回 [WorkspaceFile]，文件不存在返回 null。
  Future<WorkspaceFile?> readWorkspaceFile(
    String path, {
    String accountId = defaultAccountId,
    String agentId = '',
  }) => workspace.readFile(path, accountId: accountId, agentId: agentId);

  /// 写入 workspace 文件（完整替换内容）。
  Future<bool> writeWorkspaceFile(
    String path,
    String content, {
    String accountId = defaultAccountId,
    String agentId = '',
  }) => workspace.writeFile(
    path,
    content,
    accountId: accountId,
    agentId: agentId,
  );

  /// 追加内容到 workspace 文件（文件不存在则创建）。
  Future<bool> appendWorkspaceFile(
    String path,
    String content, {
    String accountId = defaultAccountId,
    String agentId = '',
  }) => workspace.appendFile(
    path,
    content,
    accountId: accountId,
    agentId: agentId,
  );

  /// 删除 workspace 文件。
  Future<bool> deleteWorkspaceFile(
    String path, {
    String accountId = defaultAccountId,
    String agentId = '',
  }) => workspace.deleteFile(path, accountId: accountId, agentId: agentId);

  /// 列出 workspace 目录下的文件。[directory] 为空则列出根目录。
  Future<List<WorkspaceEntry>> listWorkspaceFiles(
    String directory, {
    String accountId = defaultAccountId,
    String agentId = '',
  }) => workspace.listFiles(
    directory: directory,
    accountId: accountId,
    agentId: agentId,
  );

  /// Search curated memory, the core-owned journal, and legacy daily logs.
  Future<List<MemorySearchResult>> searchMemory(
    String query, {
    int limit = 5,
    String accountId = defaultAccountId,
    String agentId = '',
  }) => workspace.search(
    query,
    limit: limit,
    accountId: accountId,
    agentId: agentId,
  );

  /// Recall and summarize matching past sessions on demand.
  Future<List<MemoryRecallSession>> recallSessions(
    String query, {
    int limit = 3,
    String accountId = defaultAccountId,
    String agentId = '',
    String currentThreadId = '',
  }) => workspace.recallSessions(
    query,
    limit: limit,
    accountId: accountId,
    agentId: agentId,
    currentThreadId: currentThreadId,
  );

  /// Rebuild the local recall index from raw memory and journal sources.
  Future<RecallIndexStats> rebuildRecallIndex({
    String accountId = defaultAccountId,
    String agentId = '',
  }) => workspace.rebuildRecallIndex(accountId: accountId, agentId: agentId);

  /// Read local recall index stats for diagnostics.
  Future<RecallIndexStats> recallIndexStats({
    String accountId = defaultAccountId,
    String agentId = '',
  }) => workspace.recallIndexStats(accountId: accountId, agentId: agentId);

  /// List journal days for the scoped account/agent.
  Future<List<JournalDay>> listJournalDays({
    String accountId = defaultAccountId,
    String agentId = '',
  }) => workspace.listJournalDays(accountId: accountId, agentId: agentId);

  /// Read one journal day. Separate from workspace file reads so raw journals
  /// are never treated as prompt memory files.
  Future<List<JournalTurnRecord>> readJournalDay(
    String date, {
    String accountId = defaultAccountId,
    String agentId = '',
  }) => workspace.readJournalDay(date, accountId: accountId, agentId: agentId);

  /// 获取 Agent 组装后的完整 system prompt。
  Future<String> getSystemPrompt({
    String accountId = defaultAccountId,
    String agentId = '',
  }) => workspace.systemPrompt(accountId: accountId, agentId: agentId);

  /// 重新播种 workspace（仅创建缺失的默认文件）。返回新创建的文件数。
  Future<int> reseedWorkspace({
    String accountId = defaultAccountId,
    String agentId = '',
  }) => workspace.reseed(accountId: accountId, agentId: agentId);
}
