part of '../engine.dart';

/// Library-private state machine for session runs, background execution, and
/// the custom-tool request listener.
///
/// Extracted out of [NapaxiEngine] as a behavior-preserving relocation. As a
/// `part of` the engine library it can read [NapaxiEngine]'s private fields
/// directly via the [_engine] back-reference. The cluster's OWN mutable state
/// (the run maps, the controller, the subscriptions) lives here; shared
/// engine state (`_handle`, `_config`, executors, controllers) stays on
/// [NapaxiEngine] and is reached via `_engine._x`.
class EngineCore {
  EngineCore(NapaxiEngine engine)
      : _engine = engine,
        _bg = engine._backgroundController;

  /// Test-only constructor: builds a core with no owning engine and an injected
  /// (optional) background controller, so the session-run state machine and
  /// [_wrapWithBackground] can be driven without a live FFI engine. Only the
  /// background-execution path is exercised through this seam; the
  /// engine-dependent methods (send/cancel/tool-listener) are never reached and
  /// would throw on the unset [_engine] if called.
  @visibleForTesting
  EngineCore.forTest({NapaxiBackgroundController? backgroundController})
      : _bg = backgroundController;

  /// Owning engine. Reached only by production methods that need
  /// handle/config/executors; unset (and never accessed) under [forTest].
  late final NapaxiEngine _engine;

  /// The background controller the cluster drives. Captured at construction
  /// from the engine in production, or injected directly under [forTest].
  final NapaxiBackgroundController? _bg;

  final Map<String, SessionRunInfo> _activeSessionRuns = {};
  final Map<String, String> _activeAgentEngineRuns = {};
  final Map<String, DateTime> _locallyCancelledSessionRuns = {};
  final StreamController<SessionRunInfo> _sessionRunController =
      StreamController<SessionRunInfo>.broadcast();
  StreamSubscription<BackgroundActionEvent>? _backgroundActionSubscription;
  StreamSubscription<String>? _toolRequestSubscription;

  /// In-memory updates for SDK session runs owned by this engine instance.
  Stream<SessionRunInfo> get sessionRunUpdates => _sessionRunController.stream;

  /// Snapshot of non-terminal runs currently active in this process.
  List<SessionRunInfo> get activeSessionRuns =>
      List.unmodifiable(_activeSessionRuns.values);

  /// Drives the session-run state machine over a stream, for tests. Production
  /// callers reach this via [NapaxiEngine.send]/[sendToSession].
  @visibleForTesting
  Stream<ChatEvent> wrapWithBackgroundForTest(
    Stream<ChatEvent> rawStream, {
    SessionRunInfo? runInfo,
  }) =>
      _wrapWithBackground(rawStream, runInfo: runInfo);

  /// The foreground-service controller, or null if background execution is not
  /// configured. Exposed for [BackgroundApi].
  NapaxiBackgroundController? get backgroundController => _bg;

  /// Stream of user actions from background notifications (empty when there is
  /// no background controller). Exposed for [BackgroundApi].
  Stream<BackgroundActionEvent> get onBackgroundAction =>
      _bg?.onAction ?? const Stream.empty();

  /// Update background notification copy without rebuilding the engine.
  void updateBackgroundConfig(BackgroundConfig config) {
    _bg?.updateConfig(config);
  }

  // ==========================================================================
  // 后台执行（Background Execution）
  // ==========================================================================

  String _sessionRunId(String agentId, SessionKey key) =>
      '$agentId:${key.channelType}:${key.accountId}:${key.threadId}';

  bool hasActiveSessionRun(
    SessionKey key, {
    String agentId = NapaxiEngine.defaultAgentId,
  }) =>
      _activeSessionRuns.containsKey(_sessionRunId(agentId, key));

  SessionRunInfo? activeSessionRun(
    SessionKey key, {
    String agentId = NapaxiEngine.defaultAgentId,
  }) {
    return _activeSessionRuns[_sessionRunId(agentId, key)];
  }

  void _emitSessionRun(SessionRunInfo info) {
    if (info.isTerminal) {
      final active = _activeSessionRuns[info.id];
      if (active == null || active.startedAt == info.startedAt) {
        _activeSessionRuns.remove(info.id);
      }
    } else {
      _activeSessionRuns[info.id] = info;
    }
    if (!_sessionRunController.isClosed) {
      _sessionRunController.add(info);
    }
    _updateBackgroundRunSummary();
  }

  SessionRunInfo _updateSessionRun(
    SessionRunInfo info, {
    SessionRunStatus? status,
    String? activity,
    String? humanRequestId,
    bool clearHumanRequest = false,
    String? error,
    bool clearError = false,
  }) {
    final updated = info.copyWith(
      status: status,
      activity: activity,
      humanRequestId: humanRequestId,
      clearHumanRequest: clearHumanRequest,
      error: error,
      clearError: clearError,
      updatedAt: DateTime.now(),
    );
    _emitSessionRun(updated);
    return updated;
  }

  void _updateBackgroundRunSummary() {
    final bg = _bg;
    if (bg == null || !bg.isRunning) return;
    final runs = _activeSessionRuns.values.toList();
    if (runs.isEmpty) return;
    if (runs.length == 1) {
      bg.updateNotification(message: runs.single.activity).catchError((_) {});
      return;
    }
    final waitingCount = runs
        .where((run) => run.status == SessionRunStatus.waitingForInput)
        .length;
    final suffix = waitingCount == 0 ? '' : ' · $waitingCount waiting';
    bg
        .updateNotification(message: '${runs.length} sessions running$suffix')
        .catchError((_) {});
  }

  /// Start the background foreground service manually.
  ///
  /// This is called automatically by [NapaxiEngine.send] and
  /// [NapaxiEngine.sendToSession] when [BackgroundConfig] is enabled. Call this
  /// directly if you need to start the service before sending a message (e.g.,
  /// during setup).
  Future<void> startBackgroundService() async {
    final bg = _bg;
    if (bg == null) return;
    final config = bg.currentConfig;
    if (config != null) {
      await bg.start(config);
    }
    _backgroundActionSubscription?.cancel();
    _backgroundActionSubscription = bg.onAction.listen(_handleBackgroundAction);
  }

  /// Stop the background foreground service manually.
  Future<void> stopBackgroundService() async {
    final bg = _bg;
    if (bg == null) return;
    _backgroundActionSubscription?.cancel();
    _backgroundActionSubscription = null;
    await bg.stop();
  }

  /// Wrap a ChatEvent stream with automatic background service management.
  ///
  /// - Starts the foreground service before the stream begins
  /// - Updates notifications based on event types
  /// - Shows HITL notification for [AskingHumanEvent]
  /// - Shows completion/error notification when the stream ends
  /// - Stops the foreground service when the stream completes
  Stream<ChatEvent> _wrapWithBackground(
    Stream<ChatEvent> rawStream, {
    SessionRunInfo? runInfo,
  }) async* {
    final bg = _bg;

    // Start the foreground service immediately, before the stream begins.
    // This ensures the process priority is raised and WakeLock is held
    // before any HTTP requests are made.
    final config = bg?.currentConfig;
    if (bg != null && config != null && !bg.isRunning) {
      try {
        await bg.start(config);
      } catch (_) {
        // Service start failure is non-fatal; agent will still run in foreground.
      }
      _backgroundActionSubscription?.cancel();
      _backgroundActionSubscription = bg.onAction.listen(
        _handleBackgroundAction,
      );
    }

    if (runInfo != null) {
      _emitSessionRun(runInfo);
    }

    var currentRun = runInfo;
    var endedWithError = false;
    yield* rawStream.transform(
      StreamTransformer<ChatEvent, ChatEvent>.fromHandlers(
        handleData: (event, sink) {
          final nextRun = currentRun == null
              ? null
              : _sessionRunForEvent(currentRun!, event);
          if (nextRun != null) {
            currentRun = nextRun;
          }
          if (bg != null && _onChatEvent(event, bg)) {
            endedWithError = true;
          }
          sink.add(event);
        },
        handleError: (error, stackTrace, sink) {
          endedWithError = true;
          final run = currentRun;
          if (run != null) {
            currentRun = _updateSessionRun(
              run,
              status: SessionRunStatus.failed,
              activity: error.toString(),
              error: error.toString(),
            );
          }
          bg
              ?.showErrorNotification(
                title: bg.currentConfig?.notificationConfig.ongoingTitle ??
                    'Napaxi Agent',
                message:
                    '${bg.currentConfig?.notificationConfig.errorPrefix ?? 'Error'}: ${error.toString()}',
              )
              .catchError((_) {});
          bg?.stop().catchError((_) {});
          sink.addError(error, stackTrace);
        },
        handleDone: (sink) {
          final run = currentRun;
          if (run != null && !run.isTerminal) {
            final wasCancelled = run.status == SessionRunStatus.cancelling;
            currentRun = _updateSessionRun(
              run,
              status: wasCancelled
                  ? SessionRunStatus.cancelled
                  : SessionRunStatus.completed,
              activity: wasCancelled ? 'Cancelled' : 'Completed',
              clearHumanRequest: true,
            );
          }
          if (bg != null &&
              bg.isRunning &&
              !endedWithError &&
              _activeSessionRuns.isEmpty) {
            bg
                .showCompletionNotification(
                  title: bg.currentConfig?.notificationConfig.ongoingTitle ??
                      'Napaxi Agent',
                  message:
                      bg.currentConfig?.notificationConfig.completionMessage ??
                          'Task completed',
                )
                .catchError((_) {});
            bg.stop().catchError((_) {});
          }
          sink.close();
        },
      ),
    );
  }

  SessionRunInfo _sessionRunForEvent(SessionRunInfo run, ChatEvent event) {
    if (run.isTerminal) return run;
    final cancelledAt = _locallyCancelledSessionRuns[run.id];
    if (cancelledAt == run.startedAt) {
      return _updateSessionRun(
        run,
        status: SessionRunStatus.cancelled,
        activity: 'Cancelled',
        clearHumanRequest: true,
      );
    }
    return switch (event) {
      ToolCallEvent(:final name) => _updateSessionRun(
          run,
          status: SessionRunStatus.running,
          activity: 'Running: $name',
          clearHumanRequest: true,
          clearError: true,
        ),
      ToolCallDeltaEvent(:final name) => _updateSessionRun(
          run,
          status: SessionRunStatus.running,
          activity:
              name.trim().isEmpty ? 'Preparing tool call' : 'Preparing: $name',
          clearHumanRequest: true,
          clearError: true,
        ),
      AgentToolCallEvent(:final name, :final agentId) => _updateSessionRun(
          run,
          status: SessionRunStatus.running,
          activity: 'Agent $agentId: $name',
          clearHumanRequest: true,
          clearError: true,
        ),
      AgentToolCallDeltaEvent(:final name, :final agentId) => _updateSessionRun(
          run,
          status: SessionRunStatus.running,
          activity: name.trim().isEmpty
              ? 'Agent $agentId: preparing tool call'
              : 'Agent $agentId: preparing $name',
          clearHumanRequest: true,
          clearError: true,
        ),
      ToolOutputChunkEvent(:final stream) => _updateSessionRun(
          run,
          status: SessionRunStatus.running,
          activity: stream == 'stderr' ? 'Reading stderr' : 'Reading output',
          clearHumanRequest: true,
          clearError: true,
        ),
      ReasoningDeltaEvent() || ThinkingEvent() => _updateSessionRun(
          run,
          status: SessionRunStatus.running,
          activity: 'Thinking',
          clearHumanRequest: true,
          clearError: true,
        ),
      ResponseDeltaEvent() || ResponseEvent() => _updateSessionRun(
          run,
          status: SessionRunStatus.running,
          activity: 'Writing response',
          clearHumanRequest: true,
          clearError: true,
        ),
      AskingHumanEvent(:final requestId) => _updateSessionRun(
          run,
          status: SessionRunStatus.waitingForInput,
          activity: 'Waiting for input',
          humanRequestId: requestId,
          clearError: true,
        ),
      HumanResponseEvent() || MessageInjectedEvent() => _updateSessionRun(
          run,
          status: SessionRunStatus.running,
          activity: 'Continuing',
          clearHumanRequest: true,
          clearError: true,
        ),
      StreamResetEvent() => _updateSessionRun(
          run,
          status: SessionRunStatus.running,
          activity: 'Reconnecting',
          clearHumanRequest: true,
          clearError: true,
        ),
      ErrorEvent(:final message) => _updateSessionRun(
          run,
          status: SessionRunStatus.failed,
          activity: message,
          error: message,
        ),
      EvolutionQueuedEvent() => _updateSessionRun(
          run,
          status: SessionRunStatus.completed,
          activity: 'Queued learning',
          clearHumanRequest: true,
        ),
      SkillActivatedEvent(:final skills) => _updateSessionRun(
          run,
          status: SessionRunStatus.running,
          activity: _skillActivity(skills),
          clearHumanRequest: true,
          clearError: true,
        ),
      _ => run,
    };
  }

  String _skillActivity(List<ActivatedSkillInfo> skills) {
    if (skills.length == 1) {
      final name = skills.single.name.trim();
      return name.isEmpty ? 'Using skill' : 'Using skill: $name';
    }
    return 'Using ${skills.length} skills';
  }

  /// Handle a ChatEvent for background notification updates.
  bool _onChatEvent(ChatEvent event, NapaxiBackgroundController bg) {
    switch (event) {
      case ToolCallEvent(:final name):
        if (_activeSessionRuns.length > 1) {
          _updateBackgroundRunSummary();
        } else {
          bg.updateNotification(message: 'Running: $name').catchError((_) {});
        }
      case ToolCallDeltaEvent(:final name):
        if (_activeSessionRuns.length > 1) {
          _updateBackgroundRunSummary();
        } else if (name.trim().isNotEmpty) {
          bg.updateNotification(message: 'Preparing: $name').catchError((_) {});
        }
      case AgentToolCallEvent(:final name, :final agentId):
        if (_activeSessionRuns.length > 1) {
          _updateBackgroundRunSummary();
        } else {
          bg
              .updateNotification(message: 'Agent $agentId: $name')
              .catchError((_) {});
        }
      case AgentToolCallDeltaEvent(:final name, :final agentId):
        if (_activeSessionRuns.length > 1) {
          _updateBackgroundRunSummary();
        } else if (name.trim().isNotEmpty) {
          bg
              .updateNotification(message: 'Agent $agentId: preparing $name')
              .catchError((_) {});
        }
      case AskingHumanEvent(:final question, :final requestId, :final options):
        final waitingCount = _activeSessionRuns.values
            .where((run) => run.status == SessionRunStatus.waitingForInput)
            .length;
        if (waitingCount <= 1) {
          bg
              .showHitlNotification(
                requestId: requestId,
                question: question,
                options: options.isNotEmpty ? options : null,
              )
              .catchError((_) {});
        } else {
          bg
              .updateNotification(message: '$waitingCount sessions need input')
              .catchError((_) {});
        }
      case ErrorEvent(:final message):
        bg
            .showErrorNotification(
              title: bg.currentConfig?.notificationConfig.ongoingTitle ??
                  'Napaxi Agent',
              message: message,
            )
            .catchError((_) {});
        bg.stop().catchError((_) {});
        return true;
      case SkillActivatedEvent(:final skills):
        if (_activeSessionRuns.length > 1) {
          _updateBackgroundRunSummary();
        } else {
          bg
              .updateNotification(message: _skillActivity(skills))
              .catchError((_) {});
        }
      default:
        break;
    }
    return false;
  }

  /// Handle background notification actions (HITL approve/deny, stop, view).
  void _handleBackgroundAction(BackgroundActionEvent event) {
    switch (event.action) {
      case BackgroundAction.stop:
        final runs = _activeSessionRuns.values.toList();
        for (final run in runs) {
          cancelSession(run.key, agentId: run.agentId).catchError((_) => false);
        }
        _bg?.stop().catchError((_) {});
      case BackgroundAction.hitlApprove:
        final requestId = event.requestId;
        final effectiveRequestId = requestId ?? _singleWaitingRequestId();
        if (effectiveRequestId != null && effectiveRequestId.isNotEmpty) {
          answerHumanRequest(
            effectiveRequestId,
            event.payload ?? 'approved',
          ).catchError((_) => false);
        }
      case BackgroundAction.hitlDeny:
        final requestId = event.requestId;
        final effectiveRequestId = requestId ?? _singleWaitingRequestId();
        if (effectiveRequestId != null && effectiveRequestId.isNotEmpty) {
          answerHumanRequest(
            effectiveRequestId,
            event.payload ?? 'denied',
          ).catchError((_) => false);
        }
      case BackgroundAction.viewResult:
        // Forwarded to the host app via onBackgroundAction stream
        break;
      case BackgroundAction.agentTrigger:
        // Forwarded to the host app via onBackgroundAction stream
        break;
      case BackgroundAction.automationWake:
        // The automation scheduler listens to native wake events directly.
        break;
    }
  }

  String? _singleWaitingRequestId() {
    final waiting = _activeSessionRuns.values
        .where((run) => run.status == SessionRunStatus.waitingForInput)
        .toList();
    if (waiting.length != 1) return null;
    return waiting.single.humanRequestId;
  }

  // ==========================================================================
  // 自定义工具（Custom Tools）
  // ==========================================================================

  /// Register/update custom tools.
  ///
  /// Custom tools are executed on the Dart side when called by the AI agent.
  /// The [McToolExecutor] passed to [NapaxiEngine.create] handles tool
  /// execution. Built-in platform tools are automatically merged when enabled.
  ///
  /// Call [startToolRequestListener] first to set up the request stream.
  bool updateCustomTools(List<CustomToolDef> tools) {
    return _syncAllTools(tools);
  }

  bool _syncAllTools(List<CustomToolDef> userTools) {
    final allTools = <CustomToolDef>[
      if (_engine._platformToolExecutor != null)
        ...PlatformToolProvider.getToolDefinitions(),
      if (_engine._browserToolHost != null)
        ...BrowserToolProvider.getToolDefinitions(),
      ...userTools,
    ];
    return rust_init.updateCustomTools(
      handle: _engine._handle,
      toolsJson: jsonEncode(allTools.map((t) => t.toJson()).toList()),
    );
  }

  /// Start listening for custom tool requests from the Rust engine.
  ///
  /// When a custom tool executes, the engine sends a request via a stream.
  /// This method processes requests using the [McToolExecutor] and forwards
  /// results back to the engine over the bridge.
  ///
  /// Must be called before [updateCustomTools] to register the stream.
  void startToolRequestListener() {
    if (_engine._toolExecutor == null &&
        _engine._agentEngineExecutor == null &&
        _engine._agentAppActionExecutor == null &&
        _engine._platformToolExecutor == null &&
        _engine._browserToolHost == null &&
        _engine._toolApprovalHandler == null) {
      return;
    }
    if (_toolRequestSubscription != null) return;

    _toolRequestSubscription = rust_init.registerToolRequestStream().listen(
      (jsonStr) {
        _handleToolRequest(jsonStr);
      },
      onError: (Object e) {
        // Stream error — log and continue.
      },
    );

    if (_engine._toolExecutor != null ||
        _engine._agentEngineExecutor != null ||
        _engine._agentAppActionExecutor != null ||
        _engine._platformToolExecutor != null ||
        _engine._browserToolHost != null ||
        _engine._toolApprovalHandler != null) {
      _syncAllTools([]);
    }
  }

  Future<void> _handleToolRequest(String jsonStr) async {
    try {
      final request = decodeJsonObject(jsonStr);
      final requestId = BigInt.from(request['request_id'] as int);
      final toolName = request['tool_name'] as String;
      final paramsJson = request['params_json'] as String;
      final context = request['context'] as Map<String, dynamic>?;
      final workspaceFilesDir = context?['workspace_files_dir'] as String?;

      try {
        String result;
        var isError = false;
        if (toolName == '__napaxi_approval__') {
          result = await _handleToolApprovalRequest(requestId, paramsJson);
        } else if (toolName == '__napaxi_agent_engine_turn__') {
          result = await _handleAgentEngineTurn(paramsJson);
        } else if (toolName == '__napaxi_agent_app_action__') {
          result = await _handleAgentAppActionRequest(paramsJson);
        } else if (_engine._platformToolExecutor?.canHandle(toolName) == true) {
          result = await _engine._platformToolExecutor!.execute(
            toolName,
            paramsJson,
            workspaceFilesDir: workspaceFilesDir,
          );
        } else if (_engine._browserToolHost?.canHandle(toolName) == true) {
          result =
              await _engine._browserToolHost!.execute(toolName, paramsJson);
          isError = _jsonResultIndicatesFailure(result);
        } else if (_engine._toolExecutor != null) {
          result = await _engine._toolExecutor.execute(toolName, paramsJson);
        } else {
          result = 'No executor for tool: $toolName';
          isError = true;
        }
        _notifyToolResult(
          toolName: toolName,
          paramsJson: paramsJson,
          result: result,
          isError: isError,
          context: context,
        );
        rust_init.resolveToolExecution(
          requestId: requestId,
          result: result,
          isError: isError,
        );
      } catch (e) {
        rust_init.resolveToolExecution(
          requestId: requestId,
          result: e.toString(),
          isError: true,
        );
      }
    } catch (e) {
      // Malformed request JSON — can't resolve since we don't have request_id.
    }
  }

  void _notifyToolResult({
    required String toolName,
    required String paramsJson,
    required String result,
    required bool isError,
    required Map<String, dynamic>? context,
  }) {
    final observer = _engine._toolResultObserver;
    if (observer == null) return;
    try {
      observer(
        McToolExecutionResult(
          toolName: toolName,
          paramsJson: paramsJson,
          result: result,
          isError: isError,
          context: context == null ? null : Map<String, dynamic>.from(context),
        ),
      );
    } catch (_) {}
  }

  bool _jsonResultIndicatesFailure(String result) {
    try {
      final decoded = jsonDecode(result);
      return decoded is Map && decoded['success'] == false;
    } catch (_) {
      return false;
    }
  }

  Future<String> _handleAgentEngineTurn(String paramsJson) async {
    final executor = _engine._agentEngineExecutor;
    if (executor == null) {
      return AgentEngineTurnResult.error(
        'No agent engine executor registered',
      ).toJsonString();
    }
    final request = AgentEngineTurnRequest.fromMap(
      decodeJsonObject(paramsJson),
    );
    final tools = AgentEngineToolBroker(
      () => _engine._handle,
      listToolsJson: (handle, requestJson) => rust_init.toolBrokerListTools(
        handle: handle,
        requestJson: requestJson,
      ),
      callToolJson: (handle, requestJson) => rust_init.toolBrokerCallTool(
        handle: handle,
        requestJson: requestJson,
      ),
    );
    _activeAgentEngineRuns[request.sessionKeyJson] = request.runId;
    try {
      final result = await executor.startTurn(request, tools);
      return result.toJsonString();
    } finally {
      if (_activeAgentEngineRuns[request.sessionKeyJson] == request.runId) {
        _activeAgentEngineRuns.remove(request.sessionKeyJson);
      }
    }
  }

  Future<String> _handleAgentAppActionRequest(String paramsJson) async {
    final executor = _engine._agentAppActionExecutor;
    if (executor == null) {
      final decoded = decodeJsonObject(paramsJson);
      final proposal = AgentAppActionProposal.fromMap(
        decoded['proposal'] as Map? ?? const {},
      );
      return AgentAppActionResult(
        requestId: proposal.requestId,
        status: 'failed',
        error: 'No agent app action executor registered',
        completedAt: DateTime.now().toUtc().toIso8601String(),
      ).toJsonString();
    }
    final request = AgentAppActionRequest.fromMap(decodeJsonObject(paramsJson));
    final result = await executor.execute(request);
    return result.toJsonString();
  }

  Future<String> _handleToolApprovalRequest(
    BigInt requestId,
    String paramsJson,
  ) async {
    final decoded = decodeJsonObject(paramsJson);
    final handler = _engine._toolApprovalHandler;
    if (handler == null) {
      return jsonEncode({
        'approved': false,
        'message': 'No tool approval handler registered',
      });
    }
    final response = await handler(
      McToolApprovalRequest(
        requestId: requestId,
        toolName: decoded['tool_name'] as String? ?? '',
        description: decoded['description'] as String? ?? '',
        parametersJson: decoded['parameters'] as String? ?? '{}',
        allowAlways: decoded['allow_always'] as bool? ?? false,
      ),
    );
    return jsonEncode(response.toJson());
  }

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
  }) {
    final attachmentsJson = _encodeAttachments(attachments);
    final rawStream = rust_init
        .sendMessageStream(
          handle: _engine._handle,
          configJson: _engine._config.toJson(),
          message: message,
          attachmentsJson: attachmentsJson,
          maxIterations: maxIterations,
        )
        .map((jsonStr) => ChatEvent.fromMap(decodeJsonObject(jsonStr)));

    return _wrapWithBackground(rawStream);
  }

  /// 向指定会话发送消息（实时流式推送）
  ///
  /// 当 [attachments] 非空时，附件元数据会自动持久化到本地，
  /// 后续 [NapaxiEngine.getHistory] 可恢复。[sandboxPaths] 用于记录沙箱路径。
  ///
  /// 如果配置了 [BackgroundConfig]，会自动管理 Foreground Service 和通知。
  Stream<ChatEvent> sendToSession(
    SessionKey sessionKey,
    String message, {
    String agentId = NapaxiEngine.defaultAgentId,
    List<McAttachment>? attachments,
    List<String>? sandboxPaths,
    int? userMsgIndex,
    int maxIterations = 0,
  }) {
    final runId = _sessionRunId(agentId, sessionKey);
    if (_activeSessionRuns.containsKey(runId)) {
      throw StateError('Session is already running: ${sessionKey.threadId}');
    }
    _locallyCancelledSessionRuns.remove(runId);
    final attachmentsJson = _encodeAttachments(
      attachments,
      sandboxPaths: sandboxPaths,
    );
    final rawStream = rust_init
        .sendToSessionStream(
          handle: _engine._handle,
          configJson: _engine._config.toJson(),
          agentId: agentId,
          sessionKeyJson: sessionKey.toJson(),
          message: message,
          attachmentsJson: attachmentsJson,
          maxIterations: maxIterations,
        )
        .map((jsonStr) => ChatEvent.fromMap(decodeJsonObject(jsonStr)));

    final now = DateTime.now();
    return _wrapWithBackground(
      rawStream,
      runInfo: SessionRunInfo(
        key: sessionKey,
        agentId: agentId,
        status: SessionRunStatus.running,
        activity: 'Starting',
        startedAt: now,
        updatedAt: now,
      ),
    );
  }

  /// 向正在运行的 Agent 会话注入用户消息（HITL Phase 1）
  ///
  /// 消息会在 Agent 下一轮循环迭代时被注入到上下文中。
  /// 可选传入附件（如图片）使 Agent 在下一轮也能看到。
  /// 返回 true 表示入队成功，false 表示线程未找到或队列已满。
  Future<bool> injectMessage(
    SessionKey sessionKey,
    String message, {
    String agentId = NapaxiEngine.defaultAgentId,
    List<McAttachment>? attachments,
  }) {
    final attachmentsJson = _encodeAttachments(attachments);
    return rust_session.injectMessage(
      handle: _engine._handle,
      configJson: _engine._config.toJson(),
      agentId: agentId,
      sessionKeyJson: sessionKey.toJson(),
      message: message,
      attachmentsJson: attachmentsJson,
    );
  }

  /// Retract the latest queued injected message matching [message].
  Future<bool> retractInjectedMessage(SessionKey sessionKey, String message) {
    return rust_session.retractInjectedMessage(
      handle: _engine._handle,
      sessionKeyJson: sessionKey.toJson(),
      message: message,
    );
  }

  /// Answer a pending [AskingHumanEvent] request.
  Future<bool> answerHumanRequest(String requestId, String response) {
    return rust_session.answerHumanRequest(
      handle: _engine._handle,
      requestId: requestId,
      response: response,
    );
  }

  /// 取消正在运行的会话（中断当前 Agent 处理）
  ///
  /// 设置线程状态为 Interrupted，agentic loop 会在下一个检查点停止。
  /// 返回 true 表示中断成功，false 表示线程未找到。
  Future<bool> cancelSession(
    SessionKey sessionKey, {
    String agentId = NapaxiEngine.defaultAgentId,
  }) async {
    final sessionKeyJson = sessionKey.toJson();
    final run = activeSessionRun(sessionKey, agentId: agentId);
    if (run != null) {
      _updateSessionRun(
        run,
        status: SessionRunStatus.cancelling,
        activity: 'Stopping',
      );
    }
    var externalCancelled = false;
    final agentEngineRunId = _activeAgentEngineRuns[sessionKeyJson];
    final agentEngineExecutor = _engine._agentEngineExecutor;
    if (agentEngineExecutor != null && agentEngineRunId != null) {
      try {
        externalCancelled = await agentEngineExecutor.cancel(
          runId: agentEngineRunId,
          sessionKeyJson: sessionKeyJson,
        );
      } catch (_) {
        externalCancelled = false;
      }
    }
    final coreCancelled = await rust_session.cancelSession(
      handle: _engine._handle,
      configJson: _engine._config.toJson(),
      agentId: agentId,
      sessionKeyJson: sessionKeyJson,
    );
    final cancelled = coreCancelled || externalCancelled;
    if (cancelled && run != null) {
      _locallyCancelledSessionRuns[run.id] = run.startedAt;
      final latest = activeSessionRun(sessionKey, agentId: agentId);
      if (latest != null && latest.startedAt == run.startedAt) {
        _updateSessionRun(
          latest,
          status: SessionRunStatus.cancelled,
          activity: 'Cancelled',
          clearHumanRequest: true,
        );
      }
    }
    return cancelled;
  }

  /// Cluster cleanup: cancel the tool-request and background-action
  /// subscriptions and close the session-run controller (in that order).
  void dispose() {
    _toolRequestSubscription?.cancel();
    _toolRequestSubscription = null;
    _backgroundActionSubscription?.cancel();
    _backgroundActionSubscription = null;
    _sessionRunController.close();
  }
}
