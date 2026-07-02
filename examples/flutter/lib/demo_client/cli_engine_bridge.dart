part of '../main.dart';

// ---------------------------------------------------------------------------
// CLI Engine Bridge — connects to `codex app-server` (JSON-RPC 2.0) or
// CC (via node bridge script) over the sandbox PTY.
//
// For Codex: assumes `codex` CLI is pre-installed; speaks JSON-RPC directly.
// For CC: uses an embedded Node bridge script backed by Claude Agent SDK.
// ---------------------------------------------------------------------------

/// Minimal engine spec — holds storage keys for settings UI.
class _CliEngineSpec {
  const _CliEngineSpec._({required this.id, required this.storageKeyPrefix});

  final String id;
  final String storageKeyPrefix;

  String get apiKeyStorageKey => '$storageKeyPrefix.api_key';
  String get baseUrlStorageKey => '$storageKeyPrefix.base_url';
  String get modelStorageKey => '$storageKeyPrefix.model';
  String get workspacePath => '/workspace/$id';
  String get bridgeDirectory => '$workspacePath/.engine-bridge';

  /// Sandboxed HOME for the CC engine. Redirecting HOME here (instead of the
  /// shared proot `/root`) keeps every Claude-managed file — settings, session
  /// history (`~/.claude/projects`), todos, memory, shell snapshots — inside
  /// the engine workspace rather than scattered across the rootfs home.
  String get homeDir => '$workspacePath/.home';
  String get claudeConfigDir => '$homeDir/.claude';

  static const cc = _CliEngineSpec._(
    id: 'cc',
    storageKeyPrefix: 'napaxi.engine.cc',
  );

  static const codex = _CliEngineSpec._(
    id: 'codex',
    storageKeyPrefix: 'napaxi.engine.codex',
  );
}

enum _CliSessionState { uninitialized, installing, ready, busy }

Future<String> _resolveCliWorkspaceHostDir() async {
  try {
    final supportDir = await getApplicationSupportDirectory();
    final workspaceDir = Directory('${supportDir.path}/environment-workspace');
    if (!workspaceDir.existsSync()) {
      workspaceDir.createSync(recursive: true);
    }
    return workspaceDir.path;
  } catch (_) {
    return '/workspace';
  }
}

class _PendingCliHumanRequest {
  const _PendingCliHumanRequest({
    required this.rpcId,
    required this.questionId,
  });

  final Object rpcId;
  final String questionId;
}

/// Bridges a CLI engine running in the sandbox PTY to the chat event stream.
///
/// For Codex: speaks JSON-RPC 2.0 directly to `codex app-server` — no node needed.
/// For CC: uses an embedded node bridge script backed by Claude Agent SDK.
class _CliEngineBridge {
  _CliEngineBridge({required this.spec});

  final _CliEngineSpec spec;
  static const String _codexHistoryLogTag = 'napaxiCodexHistory';
  static const String _codexReasoningEffort = 'high';
  static const List<String> _codexThreadSourceKinds = [
    'cli',
    'vscode',
    'exec',
    'appServer',
    'subAgent',
    'subAgentReview',
    'subAgentCompact',
    'subAgentThreadSpawn',
    'subAgentOther',
    'unknown',
  ];

  _CliSessionState _state = _CliSessionState.uninitialized;
  int? _ptySessionId;
  StreamSubscription<dynamic>? _eventSub;
  StreamController<sdk.ChatEvent>? _activeController;
  Timer? _timeoutTimer;
  final StringBuffer _lineBuf = StringBuffer();

  int _rpcId = 1;
  String? _threadId;

  /// The UI-side thread id currently attached to this bridge. Conversation
  /// switches are detected by comparing against this; the matching native
  /// session id (codex thread / Claude session_id) is persisted in the
  /// native-id sidecar keyed by this value.
  String? _attachedThreadId;

  /// Optional callback fired once codex creates a real thread id (during the
  /// first turn of a brand-new conversation, where the UI sent a placeholder
  /// id). The UI uses it to migrate its session id to the real one.
  void Function(String nativeThreadId)? _onNativeThreadId;

  /// Resolves a pending CC `history` backfill request (see [readHistory]).
  Completer<List<Map<String, dynamic>>>? _ccHistoryCompleter;

  /// Pluggable handler for PTY output during different phases.
  void Function(String data)? _outputHandler;

  Completer<void>? _bootCompleter;

  /// Pending RPC responses keyed by request id.
  final Map<int, Completer<Map<String, dynamic>?>> _pendingRpc = {};
  final Map<String, String> _agentMessageByItemId = {};
  final Map<String, String> _reasoningByItemId = {};
  final Set<String> _startedToolCallIds = <String>{};
  final Map<String, _PendingCliHumanRequest> _pendingHumanRequests = {};

  // Long-running Codex/Claude Code turns can legitimately take several
  // minutes. Treat timeouts as inactivity detection, not total turn duration.
  static const Duration _responseIdleTimeout = Duration(minutes: 10);

  /// Reset thread state for a new conversation.
  /// The PTY session and codex app-server stay alive; only the thread is cleared
  /// so the next message creates a fresh Codex thread.
  void resetForNewConversation() {
    // Drop in-memory turn state and detach from the current UI thread so the
    // next send re-evaluates resume-vs-start. The persisted native-id sidecar
    // is intentionally left intact — it is what makes resume work across
    // restarts and conversation switches.
    _attachedThreadId = null;
    _threadId = null;
    _agentMessageByItemId.clear();
    _reasoningByItemId.clear();
    _startedToolCallIds.clear();
    _pendingHumanRequests.clear();
  }

  Stream<sdk.ChatEvent> send(
    String uiThreadId,
    String message, {
    void Function(String nativeThreadId)? onNativeThreadId,
  }) {
    final controller = StreamController<sdk.ChatEvent>();

    () async {
      try {
        // Reconcile against the requested conversation. Switching threads
        // drops in-memory turn state so _sendTurn re-evaluates resume-vs-start
        // for the new thread.
        if (_attachedThreadId != uiThreadId) {
          _attachedThreadId = uiThreadId;
          _threadId = null;
          _agentMessageByItemId.clear();
          _reasoningByItemId.clear();
          _startedToolCallIds.clear();
        }
        if (_state == _CliSessionState.uninitialized) {
          await _ensureReady(controller: controller);
        }
        if (_state != _CliSessionState.ready) {
          controller.add(
            sdk.ErrorEvent(message: 'Engine not ready (state: $_state)'),
          );
          await controller.close();
          return;
        }
        _state = _CliSessionState.busy;
        _activeController = controller;
        _lineBuf.clear();
        _startTimeout(controller);
        if (spec.id == 'codex') {
          // Codex: the UI thread id IS the codex thread id directly. For a
          // brand-new conversation it's a temporary placeholder that codex
          // doesn't know — thread/resume fails and we fall back to a fresh
          // thread, whose real id is reported back via [onNativeThreadId].
          _onNativeThreadId = onNativeThreadId;
          _sendTurn(message, uiThreadId);
        } else {
          final remembered = await _nativeIdFor(uiThreadId);
          _onNativeThreadId = null;
          _sendJsonEvent({
            'type': 'send',
            'text': message,
            if (remembered != null && remembered.isNotEmpty)
              'resume': remembered,
          });
        }
      } catch (e) {
        controller.add(sdk.ErrorEvent(message: e.toString()));
        if (!controller.isClosed) await controller.close();
        _state = _CliSessionState.uninitialized;
      }
    }();

    return controller.stream;
  }

  /// Boot: initialize sandbox → open PTY → launch engine.
  Future<void> _ensureReady({
    required StreamController<sdk.ChatEvent> controller,
  }) async {
    await SandboxPtyEvents.method.invokeMethod<void>('initialize');

    _state = _CliSessionState.installing;
    if (spec.id == 'codex') {
      controller.add(const sdk.ResponseDeltaEvent(content: '正在连接 Codex...\n'));
    }

    final hostWorkspaceDir = await _resolveCliWorkspaceHostDir();
    final sessionId = await SandboxPtyEvents.method.invokeMethod<int>(
      'openSession',
      {
        'cols': 120,
        'rows': 40,
        if (hostWorkspaceDir != '/workspace') 'workspaceDir': hostWorkspaceDir,
      },
    );
    _ptySessionId = sessionId;

    final readyCompleter = Completer<void>();
    final shellReadyCompleter = Completer<void>();
    _bootCompleter = readyCompleter;

    if (spec.id == 'codex') {
      // Codex: watch for any JSON-RPC message from codex app-server.
      _outputHandler = (data) {
        if (data.isNotEmpty && !shellReadyCompleter.isCompleted) {
          shellReadyCompleter.complete();
        }
        _lineBuf.write(data);
        _drainJsonLines((msg) {
          if (msg.containsKey('jsonrpc') ||
              msg.containsKey('id') ||
              msg.containsKey('method')) {
            if (!readyCompleter.isCompleted) readyCompleter.complete();
          }
        });
      };
    } else {
      // CC: watch for {"type":"ready"} from the node bridge script.
      _outputHandler = (data) {
        if (data.isNotEmpty && !shellReadyCompleter.isCompleted) {
          shellReadyCompleter.complete();
        }
        _lineBuf.write(data);
        _drainJsonLines((event) {
          final type = event['type'] as String?;
          if (type == 'ready') {
            if (!readyCompleter.isCompleted) readyCompleter.complete();
          } else if (type == 'status') {
            final msg = event['message'] as String? ?? '';
            if (msg.isNotEmpty) {
              controller.add(sdk.ResponseDeltaEvent(content: '$msg\n'));
            }
          } else if (type == 'turn_failed') {
            final error = event['error'] as String? ?? 'Bridge startup failed';
            if (!readyCompleter.isCompleted) {
              readyCompleter.completeError(Exception(error));
            }
          }
        });
      };
    }

    _subscribeEvents();
    await _awaitShellReady(shellReadyCompleter);

    if (spec.id == 'codex') {
      // Assume config.toml and auth.json are already configured.
      // Just launch codex app-server with proper PTY raw mode.
      final cmd = StringBuffer()
        ..write('mkdir -p ${spec.workspacePath} && ')
        ..write('stty raw -echo -icanon -ixon -ixoff 2>/dev/null; ')
        ..write('exec codex app-server 2>/dev/null\n');
      await _writeToPty(cmd.toString());

      // Ping after a short startup delay with initialize handshake.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!readyCompleter.isCompleted) {
        _writeRpcRequest('initialize', {
          'clientInfo': {'name': 'napaxi', 'title': 'Napaxi', 'version': '1.0.0'},
          'capabilities': {'experimentalApi': true},
        });
      }
    } else {
      // CC: write the bridge script in CHUNKS. The PTY is still in canonical
      // mode here (we only `stty -echo`), and the canonical line buffer is
      // ~4096 bytes. The old code wrote the whole base64-encoded script as a
      // single >7KB line — the kernel dropped everything past 4096, including
      // the trailing newline, so the shell never executed the command at all
      // (not even mkdir). Each line below is short and \n-terminated.
      //
      // We also reuse the globally-installed SDK instead of running a local
      // `npm install` (shorter command, no network dependency).
      final bridgeDir = spec.bridgeDirectory;
      final scriptPath = '$bridgeDir/cc-bridge.mjs';
      final b64Path = '$bridgeDir/cc-bridge.b64';
      final scriptB64 = base64Encode(utf8.encode(_ccBridgeScript));

      const chunkSize = 800;
      final chunks = <String>[];
      for (var i = 0; i < scriptB64.length; i += chunkSize) {
        final end = i + chunkSize;
        chunks.add(
          scriptB64.substring(
            i,
            end > scriptB64.length ? scriptB64.length : end,
          ),
        );
      }

      final cmd = StringBuffer()
        ..write('stty -echo 2>/dev/null\n')
        ..write(
          "printf '%s\\n' '{\"type\":\"status\",\"message\":\"Preparing Claude bridge...\"}'\n",
        )
        ..write(
          'mkdir -p ${spec.workspacePath} $bridgeDir ${spec.homeDir}/.claude\n',
        );
      for (var i = 0; i < chunks.length; i++) {
        final redir = i == 0 ? '>' : '>>';
        // scriptB64 is pure [A-Za-z0-9+/=] — safe inside single quotes.
        cmd.write("printf '%s' '${chunks[i]}' $redir $b64Path\n");
      }
      cmd
        ..write(
          "printf '%s\\n' '{\"type\":\"status\",\"message\":\"Starting Claude bridge...\"}'\n",
        )
        ..write('base64 -d $b64Path > $scriptPath && rm -f $b64Path\n')
        ..write('cd $bridgeDir\n')
        ..write(
          'if [ -f /root/.claude/env.sh ] && [ ! -f ${spec.claudeConfigDir}/env.sh ]; then cp -a /root/.claude/. ${spec.claudeConfigDir}/; fi\n',
        )
        ..write(
          'if [ -f /root/.claude.json ] && [ ! -f ${spec.homeDir}/.claude.json ]; then cp -a /root/.claude.json ${spec.homeDir}/.claude.json; fi\n',
        )
        ..write('{ . ${spec.claudeConfigDir}/env.sh 2>/dev/null || true; }\n')
        ..write(
          "HOME='${_shellEscape(spec.homeDir)}' WORKSPACE_DIR='${_shellEscape(spec.workspacePath)}' node $scriptPath 2>&1 || printf '%s\\n' \"{\\\"type\\\":\\\"turn_failed\\\",\\\"error\\\":\\\"Claude bridge startup failed (exit \$?)\\\"}\"\n",
        );
      await _writeToPty(cmd.toString());
    }

    try {
      await readyCompleter.future.timeout(
        Duration(seconds: spec.id == 'codex' ? 30 : 120),
        onTimeout: () {
          throw TimeoutException('Engine startup timed out');
        },
      );
    } finally {
      _bootCompleter = null;
      _outputHandler = _onPtyOutput;
    }

    // Send 'initialized' notification to complete the handshake.
    if (spec.id == 'codex') {
      _writeRpcNotify('initialized');
    }

    _lineBuf.clear();
    _state = _CliSessionState.ready;
    if (spec.id == 'codex') {
      controller.add(const sdk.ResponseDeltaEvent(content: 'Codex 就绪。\n'));
    }
  }

  // --- JSON-RPC 2.0 protocol ---

  void _sendTurn(String prompt, String threadId) {
    if (_threadId == null) {
      // Try to resume the thread first. For an existing codex thread this
      // reopens it; for a brand-new placeholder id, thread/resume fails and
      // _resumeThread falls back to _startThread.
      _resumeThread(threadId, prompt);
    } else {
      _startTurnInThread(prompt);
    }
  }

  void _startThread(String prompt) {
    final id = _writeRpcRequest('thread/start', {
      'cwd': spec.workspacePath,
      'approvalPolicy': 'never',
      'sandbox': 'danger-full-access',
    });
    // When thread/start responds, extract threadId and send turn.
    _pendingRpc[id] = Completer<Map<String, dynamic>?>()
      ..future
          .then((result) async {
            if (result != null) {
              final thread = result['thread'] as Map<String, dynamic>?;
              _threadId =
                  thread?['id'] as String? ?? result['threadId'] as String?;
            }
            if (_threadId != null) {
              // Report the freshly created codex thread id back to the UI so it
              // can migrate the placeholder session id to this real one. Then
              // attach this thread so future turns append to it.
              final attached = _attachedThreadId;
              if (attached != null && attached != _threadId) {
                _attachedThreadId = _threadId;
                _onNativeThreadId?.call(_threadId!);
              }
              _startTurnInThread(prompt);
            } else {
              final controller = _activeController;
              if (controller != null && !controller.isClosed) {
                controller.add(
                  const sdk.ErrorEvent(
                    message:
                        'Failed to create Codex thread (no threadId returned)',
                  ),
                );
                _completeResponse();
              }
            }
          })
          .catchError((Object e) {
            final controller = _activeController;
            if (controller != null && !controller.isClosed) {
              controller.add(
                sdk.ErrorEvent(message: 'thread/start failed: $e'),
              );
              _completeResponse();
            }
          });
  }

  /// Reopen an existing codex thread by id so subsequent turns append to it.
  /// Falls back to creating a fresh thread if the id is unknown to codex
  /// (e.g. the session rollup is missing, or this is a brand-new placeholder id).
  void _resumeThread(String codexThreadId, String prompt) {
    final id = _writeRpcRequest('thread/resume', {
      'threadId': codexThreadId,
      'approvalPolicy': 'never',
      'sandbox': 'danger-full-access',
    });
    _pendingRpc[id] = Completer<Map<String, dynamic>?>()
      ..future
          .then((result) {
            final thread = result?['thread'];
            final resumed = thread is Map ? thread['id']?.toString() : null;
            _threadId = (resumed != null && resumed.isNotEmpty)
                ? resumed
                : codexThreadId;
            _startTurnInThread(prompt);
          })
          .catchError((Object e) {
            // Unknown/expired thread (or a fresh placeholder id) — start fresh
            // so the turn still completes.
            _threadId = null;
            _startThread(prompt);
          });
  }

  void _startTurnInThread(String prompt) {
    _writeRpcRequest('turn/start', {
      'threadId': _threadId,
      'input': [
        {'type': 'text', 'text': prompt},
      ],
      'approvalPolicy': 'never',
      'sandboxPolicy': {'type': 'dangerFullAccess'},
      'effort': _codexReasoningEffort,
    });
  }

  int _writeRpcRequest(String method, Map<String, dynamic> params) {
    final id = _rpcId++;
    final payload = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    _writeToPty('$payload\n');
    return id;
  }

  void _writeRpcNotify(String method, [Map<String, dynamic>? params]) {
    final payload = jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      ...?(params == null ? null : <String, dynamic>{'params': params}),
    });
    _writeToPty('$payload\n');
  }

  // --- PTY event handling ---

  void _subscribeEvents() {
    _eventSub?.cancel();
    _eventSub = SandboxPtyEvents.shared.listen((raw) {
      if (raw is! Map) return;
      final map = Map<String, dynamic>.from(raw);
      if (map['sessionId'] != _ptySessionId) return;
      final kind = map['kind'] as String?;
      switch (kind) {
        case 'SessionOutput':
          _outputHandler?.call(map['data'] as String? ?? '');
        case 'SessionExit':
        case 'SessionClosed':
          _onSessionEnded();
      }
    });
  }

  void _onPtyOutput(String data) {
    if (data.isNotEmpty) {
      _refreshTimeout();
    }
    _lineBuf.write(data);
    if (spec.id == 'codex') {
      _drainJsonLines(_handleRpcMessage);
    } else {
      _drainJsonLines(_handleCcEvent);
    }
  }

  void _drainJsonLines(void Function(Map<String, dynamic>) handler) {
    final text = _lineBuf.toString();
    final lines = text.split('\n');
    if (lines.length <= 1) return;

    _lineBuf
      ..clear()
      ..write(lines.last);

    for (var i = 0; i < lines.length - 1; i++) {
      var line = lines[i].trim();
      if (line.isEmpty) continue;
      // Strip ANSI escape sequences and any leading non-JSON garbage.
      line = line.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');
      final jsonStart = line.indexOf('{');
      if (jsonStart < 0) continue;
      if (jsonStart > 0) line = line.substring(jsonStart);
      try {
        final map = jsonDecode(line);
        if (map is Map<String, dynamic>) handler(map);
      } catch (_) {}
    }
  }

  /// Handle a JSON-RPC message (response or notification) from codex app-server.
  void _handleRpcMessage(Map<String, dynamic> msg) {
    final method = msg['method'] as String?;
    final rawId = msg['id'];
    if (method != null && rawId != null) {
      _handleServerRequest(rawId, method, msg['params']);
      return;
    }

    // RPC response (has id field).
    if (rawId != null) {
      final id = rawId;
      final intId = id is int ? id : (id is num ? id.toInt() : null);

      // Handle RPC error responses.
      if (msg.containsKey('error')) {
        final error = msg['error'];
        final errorMsg = error is Map
            ? (error['message'] as String? ?? jsonEncode(error))
            : error.toString();
        // If there's a pending completer, reject it (e.g. thread/start failure).
        if (intId != null && _pendingRpc.containsKey(intId)) {
          final pending = _pendingRpc.remove(intId)!;
          if (!pending.isCompleted) {
            pending.completeError(Exception(errorMsg));
          }
        } else {
          final controller = _activeController;
          if (controller != null && !controller.isClosed) {
            controller.add(sdk.ErrorEvent(message: 'RPC error: $errorMsg'));
            _completeResponse();
          }
        }
        return;
      }

      // Resolve pending completer if any.
      final result = msg['result'] as Map<String, dynamic>?;
      if (intId != null) {
        final pending = _pendingRpc.remove(intId);
        if (pending != null && !pending.isCompleted) {
          pending.complete(result);
        }
      }
      return;
    }

    // RPC notification (has method, no id).
    if (method == null) return;
    final params = msg['params'] as Map<String, dynamic>? ?? {};
    _handleNotification(method, params);
  }

  void _handleServerRequest(Object rawId, String method, Object? rawParams) {
    final params = rawParams is Map<String, dynamic>
        ? rawParams
        : rawParams is Map
        ? Map<String, dynamic>.from(rawParams)
        : <String, dynamic>{};
    switch (method) {
      case 'item/tool/requestUserInput':
        _handleToolRequestUserInput(rawId, params);
      default:
        _writeRpcResponse(
          rawId,
          error: {
            'code': -32601,
            'message': 'Unsupported server request: $method',
          },
        );
    }
  }

  void _handleNotification(String method, Map<String, dynamic> params) {
    final controller = _activeController;
    if (controller == null || controller.isClosed) return;

    switch (method) {
      case 'item/started':
        _handleCodexItemStarted(controller, params);

      case 'item/completed':
        _handleCodexItemCompleted(controller, params);

      // Text streaming delta.
      case 'item/agentMessage/delta':
        final itemId = params['itemId']?.toString().trim() ?? '';
        final delta = params['delta'] as String? ?? '';
        if (delta.isNotEmpty) {
          if (itemId.isNotEmpty) {
            _agentMessageByItemId[itemId] =
                (_agentMessageByItemId[itemId] ?? '') + delta;
          }
          controller.add(sdk.ResponseDeltaEvent(content: delta));
        }

      // Reasoning / thinking deltas from the model.
      case 'item/reasoning/textDelta':
      case 'item/reasoning/summaryTextDelta':
        final itemId = params['itemId']?.toString().trim() ?? '';
        final delta = params['delta'] as String? ?? '';
        if (delta.isNotEmpty) {
          if (itemId.isNotEmpty) {
            _reasoningByItemId[itemId] =
                (_reasoningByItemId[itemId] ?? '') + delta;
          }
          controller.add(sdk.ReasoningDeltaEvent(content: delta));
        }

      case 'item/commandExecution/outputDelta':
        final itemId = params['itemId']?.toString().trim() ?? '';
        final delta = params['delta'] as String? ?? '';
        if (itemId.isNotEmpty && delta.isNotEmpty) {
          controller.add(
            sdk.ToolOutputChunkEvent(
              callId: itemId,
              content: delta,
              stream: 'stdout',
            ),
          );
        }

      case 'item/commandExecution/terminalInteraction':
        final itemId = params['itemId']?.toString().trim() ?? '';
        final stdin = params['stdin'] as String? ?? '';
        if (itemId.isNotEmpty && stdin.isNotEmpty) {
          controller.add(
            sdk.ToolOutputChunkEvent(
              callId: itemId,
              content: stdin,
              stream: 'stdin',
            ),
          );
        }

      // Legacy command execution notifications.
      case 'codex/event/exec_command_begin':
        final cmdArgs = params['args'] as List?;
        final cmdStr = cmdArgs != null
            ? cmdArgs.join(' ')
            : (params['command'] as String? ?? 'exec');
        final callId = params['call_id'] as String? ?? 'codex-cmd-$_rpcId';
        final arguments = _jsonString({
          'cmd': cmdStr,
          if ((params['cwd'] as String?)?.trim().isNotEmpty == true)
            'cwd': (params['cwd'] as String).trim(),
        });
        _ensureToolCallStarted(
          controller,
          callId: callId,
          name: 'shell',
          arguments: arguments,
        );

      case 'codex/event/exec_command_end':
        final output =
            params['stdout'] as String? ?? params['output'] as String? ?? '';
        final callId = params['call_id'] as String? ?? 'codex-cmd-$_rpcId';
        final arguments = _jsonString({
          'cmd': (params['command'] as String? ?? 'exec').trim(),
          if ((params['cwd'] as String?)?.trim().isNotEmpty == true)
            'cwd': (params['cwd'] as String).trim(),
        });
        _ensureToolCallStarted(
          controller,
          callId: callId,
          name: 'shell',
          arguments: arguments,
        );
        controller.add(
          sdk.ToolResultEvent(
            callId: callId,
            name: 'shell',
            output: output,
            isError: (params['exit_code'] as int? ?? 0) != 0,
          ),
        );

      // Turn completed.
      case 'turn/completed':
        _completeResponse();

      case 'codex/event/task_complete':
        _completeResponse();

      // Turn aborted/error.
      case 'codex/event/turn_aborted':
        final error = params['reason'] as String? ?? 'Turn aborted';
        controller.add(sdk.ErrorEvent(message: error));
        _completeResponse();

      // Fallback: any unmatched notification with text-like content.
      default:
        break;
    }
  }

  void _handleToolRequestUserInput(Object rawId, Map<String, dynamic> params) {
    final controller = _activeController;
    if (controller == null || controller.isClosed) {
      _writeRpcResponse(
        rawId,
        error: {'code': -32000, 'message': 'No active turn for user input'},
      );
      return;
    }
    final questions =
        (params['questions'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false) ??
        const <Map<String, dynamic>>[];
    if (questions.isEmpty) {
      _writeRpcResponse(
        rawId,
        error: {
          'code': -32602,
          'message': 'Missing request_user_input question',
        },
      );
      return;
    }
    final first = questions.first;
    final requestId = rawId.toString();
    final questionId = first['id']?.toString().trim() ?? '';
    if (questionId.isEmpty) {
      _writeRpcResponse(
        rawId,
        error: {
          'code': -32602,
          'message': 'Missing request_user_input question id',
        },
      );
      return;
    }
    _pendingHumanRequests[requestId] = _PendingCliHumanRequest(
      rpcId: rawId,
      questionId: questionId,
    );
    final header = first['header']?.toString().trim() ?? '';
    final options =
        (first['options'] as List?)
            ?.whereType<Map>()
            .map((item) => item['label']?.toString().trim() ?? '')
            .where((item) => item.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    controller.add(
      sdk.AskingHumanEvent(
        question: first['question']?.toString() ?? 'Input required',
        requestId: requestId,
        options: options,
        context: header.isEmpty ? null : header,
      ),
    );
  }

  void _handleCodexItemStarted(
    StreamController<sdk.ChatEvent> controller,
    Map<String, dynamic> params,
  ) {
    final item = _threadItem(params);
    if (item.isEmpty) return;
    final callId = item['id']?.toString().trim() ?? '';
    if (callId.isEmpty) return;
    switch (item['type']) {
      case 'commandExecution':
        _ensureToolCallStarted(
          controller,
          callId: callId,
          name: 'shell',
          arguments: _commandExecutionArguments(item),
        );
      case 'dynamicToolCall':
        _ensureToolCallStarted(
          controller,
          callId: callId,
          name: _dynamicToolName(item),
          arguments: _jsonString(item['arguments']),
        );
    }
  }

  void _handleCodexItemCompleted(
    StreamController<sdk.ChatEvent> controller,
    Map<String, dynamic> params,
  ) {
    final item = _threadItem(params);
    if (item.isEmpty) return;
    final itemType = item['type']?.toString().trim() ?? '';
    final itemId = item['id']?.toString().trim() ?? '';
    switch (itemType) {
      case 'agentMessage':
        final text = item['text']?.toString() ?? '';
        final emitted = _agentMessageByItemId[itemId] ?? '';
        final trailing = _trailingSuffix(emitted, text);
        _agentMessageByItemId[itemId] = text;
        if (trailing.isNotEmpty) {
          controller.add(sdk.ResponseDeltaEvent(content: trailing));
        }
      case 'reasoning':
        final text = _reasoningText(item);
        if (text.isEmpty) return;
        final emitted = _reasoningByItemId[itemId] ?? '';
        final trailing = _trailingSuffix(emitted, text);
        _reasoningByItemId[itemId] = text;
        if (trailing.isNotEmpty) {
          controller.add(sdk.ReasoningDeltaEvent(content: trailing));
        }
      case 'commandExecution':
        if (itemId.isEmpty) return;
        const name = 'shell';
        final arguments = _commandExecutionArguments(item);
        _ensureToolCallStarted(
          controller,
          callId: itemId,
          name: name,
          arguments: arguments,
        );
        controller.add(
          sdk.ToolResultEvent(
            callId: itemId,
            name: name,
            output: item['aggregatedOutput']?.toString() ?? '',
            isError: _commandExecutionFailed(item),
          ),
        );
      case 'dynamicToolCall':
        if (itemId.isEmpty) return;
        final name = _dynamicToolName(item);
        final arguments = _jsonString(item['arguments']);
        _ensureToolCallStarted(
          controller,
          callId: itemId,
          name: name,
          arguments: arguments,
        );
        controller.add(
          sdk.ToolResultEvent(
            callId: itemId,
            name: name,
            output: _dynamicToolOutput(item),
            isError: _dynamicToolFailed(item),
          ),
        );
      case 'imageGeneration':
        final status = item['status']?.toString().trim().toLowerCase() ?? '';
        if (status != 'completed') return;
        final savedPath = _firstNonEmptyString([
          item['savedPath'],
          item['saved_path'],
        ]);
        final result = item['result']?.toString() ?? '';
        if (result.startsWith('data:image/')) {
          controller.add(
            sdk.ImageGeneratedEvent(dataUrl: result, path: savedPath),
          );
        } else if (savedPath.isNotEmpty) {
          controller.add(
            sdk.ResponseDeltaEvent(content: '\n![Image]($savedPath)\n'),
          );
        }
      case 'imageView':
        final path = item['path']?.toString().trim() ?? '';
        if (path.isNotEmpty) {
          controller.add(
            sdk.ResponseDeltaEvent(content: '\n![Image]($path)\n'),
          );
        }
    }
  }

  Map<String, dynamic> _threadItem(Map<String, dynamic> params) {
    final rawItem = params['item'];
    if (rawItem is Map<String, dynamic>) return rawItem;
    if (rawItem is Map) return Map<String, dynamic>.from(rawItem);
    return const <String, dynamic>{};
  }

  void _ensureToolCallStarted(
    StreamController<sdk.ChatEvent> controller, {
    required String callId,
    required String name,
    required String arguments,
  }) {
    if (callId.isEmpty || _startedToolCallIds.contains(callId)) return;
    _startedToolCallIds.add(callId);
    controller.add(
      sdk.ToolCallEvent(callId: callId, name: name, arguments: arguments),
    );
  }

  String _commandExecutionArguments(Map<String, dynamic> item) {
    return _jsonString({
      'cmd': item['command']?.toString() ?? '',
      if ((item['cwd']?.toString().trim() ?? '').isNotEmpty)
        'cwd': item['cwd']?.toString().trim(),
    });
  }

  bool _commandExecutionFailed(Map<String, dynamic> item) {
    final status = item['status']?.toString().trim().toLowerCase() ?? '';
    if (status == 'failed' || status == 'rejected') return true;
    final exitCode = item['exitCode'];
    return exitCode is num && exitCode.toInt() != 0;
  }

  String _dynamicToolName(Map<String, dynamic> item) {
    final namespace = item['namespace']?.toString().trim() ?? '';
    final tool = item['tool']?.toString().trim() ?? 'tool';
    return namespace.isEmpty ? tool : '$namespace.$tool';
  }

  bool _dynamicToolFailed(Map<String, dynamic> item) {
    final status = item['status']?.toString().trim().toLowerCase() ?? '';
    if (status == 'failed' || status == 'rejected') return true;
    final success = item['success'];
    if (success is bool) return !success;
    return false;
  }

  String _dynamicToolOutput(Map<String, dynamic> item) {
    final contentItems = item['contentItems'];
    if (contentItems is List) {
      final parts = contentItems
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .map((entry) {
            final type = entry['type']?.toString() ?? '';
            if (type == 'inputText') return entry['text']?.toString() ?? '';
            if (type == 'inputImage') {
              return entry['imageUrl']?.toString() ?? '';
            }
            return jsonEncode(entry);
          })
          .where((part) => part.trim().isNotEmpty)
          .toList(growable: false);
      if (parts.isNotEmpty) return parts.join('\n');
    }
    return jsonEncode(item);
  }

  String _reasoningText(Map<String, dynamic> item) {
    final parts = <String>[];
    void appendAll(Object? raw) {
      if (raw is List) {
        for (final value in raw) {
          final text = value?.toString() ?? '';
          if (text.trim().isNotEmpty) parts.add(text);
        }
      }
    }

    appendAll(item['summary']);
    appendAll(item['content']);
    return parts.join('\n');
  }

  String _trailingSuffix(String alreadyEmitted, String finalText) {
    if (finalText.isEmpty) return '';
    if (alreadyEmitted.isEmpty) return finalText;
    if (finalText == alreadyEmitted) return '';
    if (finalText.startsWith(alreadyEmitted)) {
      return finalText.substring(alreadyEmitted.length);
    }
    return finalText;
  }

  String _jsonString(Object? value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return value?.toString() ?? '';
    }
  }

  String _firstNonEmptyString(List<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  void _writeRpcResponse(Object id, {Object? result, Object? error}) {
    final payload = <String, dynamic>{'jsonrpc': '2.0', 'id': id};
    if (error != null) {
      payload['error'] = error;
    } else {
      payload['result'] = result ?? {};
    }
    _writeToPty('${jsonEncode(payload)}\n');
  }

  Future<bool> answerHumanRequest(String requestId, String response) async {
    final pending = _pendingHumanRequests.remove(requestId);
    if (pending == null) return false;
    _writeRpcResponse(
      pending.rpcId,
      result: {
        'answers': {
          pending.questionId: {
            'answers': [response],
          },
        },
      },
    );
    final controller = _activeController;
    if (controller != null && !controller.isClosed) {
      controller.add(
        sdk.HumanResponseEvent(requestId: requestId, response: response),
      );
    }
    return true;
  }

  void _completeResponse() {
    _timeoutTimer?.cancel();
    final controller = _activeController;
    _activeController = null;
    _lineBuf.clear();
    _state = _CliSessionState.ready;
    if (controller != null && !controller.isClosed) {
      controller.close();
    }
  }

  void _onSessionEnded() {
    _timeoutTimer?.cancel();
    _ptySessionId = null;
    _state = _CliSessionState.uninitialized;
    _pendingHumanRequests.clear();

    final boot = _bootCompleter;
    if (boot != null && !boot.isCompleted) {
      boot.completeError(Exception('Engine session exited during startup'));
      return;
    }

    final controller = _activeController;
    _activeController = null;
    if (controller != null && !controller.isClosed) {
      controller.add(
        const sdk.ErrorEvent(message: 'Engine session ended unexpectedly'),
      );
      controller.close();
    }
  }

  void _startTimeout(StreamController<sdk.ChatEvent> controller) {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_responseIdleTimeout, () {
      if (_state == _CliSessionState.busy) {
        controller.add(
          const sdk.ErrorEvent(
            message: 'Response timed out after 10 minutes of inactivity',
          ),
        );
        _completeResponse();
      }
    });
  }

  void _refreshTimeout() {
    final controller = _activeController;
    if (controller == null || controller.isClosed) return;
    if (_state != _CliSessionState.busy) return;
    _startTimeout(controller);
  }

  Future<void> _awaitShellReady(Completer<void> shellReadyCompleter) async {
    if (shellReadyCompleter.isCompleted) {
      return;
    }
    try {
      await shellReadyCompleter.future.timeout(
        const Duration(milliseconds: 400),
      );
    } on TimeoutException {
      // Some shells do not emit an initial prompt immediately. A short fallback
      // delay is still better than writing the bootstrap synchronously.
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  void sendInterrupt() {
    if (spec.id == 'codex') {
      _writeRpcNotify('turn/cancel');
    } else {
      _sendJsonEvent({'type': 'cancel'});
    }
    // Emit InterruptedEvent so the chat UI marks the run as cancelled and
    // flips in-flight tool cards to "cancelled" state.
    final controller = _activeController;
    if (controller != null && !controller.isClosed) {
      controller.add(const sdk.InterruptedEvent());
    }
    _completeResponse();
  }

  /// Handle CC bridge JSON event ({"type":"assistant_delta",...} protocol).
  void _handleCcEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;

    // Persist the Claude session_id (emitted on every `result`) so subsequent
    // turns and post-restart resumes can continue this conversation.
    if (type == 'session_id') {
      final sid =
          event['sessionId'] as String? ?? event['session_id'] as String? ?? '';
      if (sid.isNotEmpty) {
        unawaited(_saveNativeId(_attachedThreadId, sid));
      }
      return;
    }

    // Backfill response for a readHistory() request.
    if (type == 'history') {
      final rawItems = event['items'] as List? ?? const [];
      final items = rawItems
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList(growable: false);
      final completer = _ccHistoryCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(items);
      }
      return;
    }

    final controller = _activeController;
    if (controller == null || controller.isClosed) return;

    switch (type) {
      case 'assistant_delta':
        final text = event['text'] as String? ?? '';
        if (text.isNotEmpty) {
          controller.add(sdk.ResponseDeltaEvent(content: text));
        }

      case 'thinking_delta':
        final text = event['text'] as String? ?? '';
        if (text.isNotEmpty) {
          controller.add(sdk.ThinkingEvent(content: text));
        }

      case 'tool_call_start':
        final callId = event['id'] as String? ?? '';
        final name = event['name'] as String? ?? 'tool';
        final input = event['input'] as String? ?? '';
        controller.add(
          sdk.ToolCallEvent(callId: callId, name: name, arguments: input),
        );

      case 'tool_call_done':
        final callId = event['id'] as String? ?? '';
        final name = event['name'] as String? ?? 'tool';
        final output = event['output'] as String? ?? '';
        final isError = event['isError'] as bool? ?? false;
        controller.add(
          sdk.ToolResultEvent(
            callId: callId,
            name: name,
            output: output,
            isError: isError,
          ),
        );

      case 'turn_completed':
        _completeResponse();

      case 'turn_failed':
        final error = event['error'] as String? ?? 'Unknown error';
        controller.add(sdk.ErrorEvent(message: error));
        _completeResponse();

      case 'status':
        final msg = event['message'] as String? ?? '';
        if (msg.isNotEmpty) {
          controller.add(sdk.ResponseDeltaEvent(content: '$msg\n'));
        }
    }
  }

  // --- I/O helpers ---

  void _sendJsonEvent(Map<String, dynamic> data) {
    _writeToPty('${jsonEncode(data)}\n');
  }

  Future<void> _writeToPty(String data) async {
    final id = _ptySessionId;
    if (id == null) return;
    await SandboxPtyEvents.method.invokeMethod<void>('writeSession', {
      'sessionId': id,
      'data': data,
    });
  }

  Future<void> dispose() async {
    _timeoutTimer?.cancel();
    _activeController?.close();
    _activeController = null;
    _eventSub?.cancel();
    _eventSub = null;
    _pendingRpc.clear();
    _pendingHumanRequests.clear();
    final id = _ptySessionId;
    if (id != null) {
      _ptySessionId = null;
      try {
        await SandboxPtyEvents.method.invokeMethod<void>('closeSession', {
          'sessionId': id,
        });
      } catch (_) {}
    }
    _state = _CliSessionState.uninitialized;
  }

  // --- Native session resume + history backfill ------------------------------
  //
  // The sandbox FS persists across app restarts, so codex threads
  // (~/.codex/sessions) and Claude sessions (~/.claude/projects) survive. The
  // only thing we must remember ourselves is which native session id belongs to
  // a given UI thread id — kept in a tiny sidecar JSON on the host workspace.

  Future<String> _sessionsFilePath() async {
    final dir = await _resolveCliWorkspaceHostDir();
    return '$dir/cli-engine-sessions.json';
  }

  Future<Map<String, dynamic>> _loadSessionsDoc() async {
    try {
      final file = File(await _sessionsFilePath());
      if (!file.existsSync()) return <String, dynamic>{};
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is Map<String, dynamic>) return raw;
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<void> _writeSessionsDoc(Map<String, dynamic> doc) async {
    try {
      final file = File(await _sessionsFilePath());
      await file.writeAsString(jsonEncode(doc), flush: true);
    } catch (_) {}
  }

  Future<String?> _nativeIdFor(String? threadId) async {
    if (threadId == null || threadId.isEmpty) return null;
    final doc = await _loadSessionsDoc();
    final engine = doc[spec.id];
    if (engine is Map) {
      final value = engine[threadId];
      if (value is String && value.isNotEmpty) return value;
    }
    if (spec.id == 'cc') {
      final historyFile = await _ccHistoryFileForSession(threadId);
      if (historyFile != null) return threadId;
    }
    return null;
  }

  Future<File?> _ccHistoryFileForSession(String sessionId) async {
    if (spec.id != 'cc' || sessionId.trim().isEmpty) return null;
    final hostWorkspaceDir = await _resolveCliWorkspaceHostDir();
    final projectsRoot = Directory(
      '$hostWorkspaceDir/${spec.id}/.home/.claude/projects',
    );
    if (!projectsRoot.existsSync()) return null;
    final direct = File(
      '${projectsRoot.path}/${_projectDirName(spec.workspacePath)}/$sessionId.jsonl',
    );
    if (direct.existsSync()) return direct;
    for (final entity in projectsRoot.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final candidate = File('${entity.path}/$sessionId.jsonl');
      if (candidate.existsSync()) return candidate;
    }
    return null;
  }

  String _projectDirName(String path) => path.replaceAll('/', '-');

  Future<void> _saveNativeId(String? threadId, String? nativeId) async {
    if (threadId == null || threadId.isEmpty) return;
    if (nativeId == null || nativeId.isEmpty) return;
    final doc = await _loadSessionsDoc();
    final engine = doc[spec.id] is Map
        ? Map<String, dynamic>.from(doc[spec.id] as Map)
        : <String, dynamic>{};
    if (engine[threadId] == nativeId) return;
    engine[threadId] = nativeId;
    doc[spec.id] = engine;
    await _writeSessionsDoc(doc);
  }

  /// Drop this engine's persisted native-id mappings and detach in-memory
  /// state, so the next turn starts a brand-new native session. Used by the
  /// "new conversation" action (CC only; codex has no mapping layer).
  Future<void> clearNativeIds() async {
    final doc = await _loadSessionsDoc();
    if (doc.remove(spec.id) != null) {
      await _writeSessionsDoc(doc);
    }
    _attachedThreadId = null;
    _threadId = null;
    _agentMessageByItemId.clear();
    _reasoningByItemId.clear();
    _startedToolCallIds.clear();
  }

  Future<List<sdk.SessionInfo>> listCcSessions({
    required String agentId,
  }) async {
    if (spec.id != 'cc') return const [];
    final hostWorkspaceDir = await _resolveCliWorkspaceHostDir();
    final projectsRoot = Directory(
      '$hostWorkspaceDir/${spec.id}/.home/.claude/projects',
    );
    if (!projectsRoot.existsSync()) return const [];

    final discovered = <_CcLocalSessionSummary>[];
    final seenSessionIds = <String>{};
    for (final entity in projectsRoot.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.jsonl')) continue;
      final summary = _parseCcLocalSessionSummary(entity);
      if (summary == null) continue;
      if (!seenSessionIds.add(summary.sessionId)) continue;
      discovered.add(summary);
    }

    discovered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return discovered
        .map(
          (summary) => sdk.SessionInfo(
            key: sdk.SessionKey(
              channelType: 'cli',
              accountId: agentId,
              threadId: summary.uiThreadId,
            ),
            title: summary.title,
            preview: summary.preview,
            messageCount: summary.messageCount,
            createdAt: summary.createdAt.toIso8601String(),
            updatedAt: summary.updatedAt.toIso8601String(),
          ),
        )
        .toList(growable: false);
  }

  _CcLocalSessionSummary? _parseCcLocalSessionSummary(File file) {
    List<String> lines;
    try {
      lines = file.readAsLinesSync();
    } catch (_) {
      return null;
    }
    if (lines.isEmpty) return null;

    String? sessionId;
    DateTime? createdAt;
    DateTime? updatedAt;
    String firstUserMessage = '';
    String lastPreview = '';
    var messageCount = 0;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      Map<String, dynamic>? record;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) {
          record = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        continue;
      }
      if (record == null) continue;
      final recordSessionId = _ccSessionIdFromRecord(record);
      if (recordSessionId != null && recordSessionId.isNotEmpty) {
        sessionId ??= recordSessionId;
      }
      final timestamp = _ccTimestampFromRecord(record);
      if (timestamp != null) {
        createdAt ??= timestamp;
        updatedAt = timestamp;
      }
      final message = record['message'];
      if (message is! Map) continue;
      final role = message['role']?.toString().trim() ?? '';
      final content = _ccMessageText(message);
      if (content.isEmpty) continue;
      messageCount += 1;
      if (role == 'user' && firstUserMessage.isEmpty) {
        firstUserMessage = content;
      }
      lastPreview = content;
    }

    if ((sessionId == null || sessionId.isEmpty) &&
        file.uri.pathSegments.isNotEmpty) {
      sessionId = file.uri.pathSegments.last.replaceFirst(
        RegExp(r'\.jsonl$'),
        '',
      );
    }
    if (sessionId == null || sessionId.isEmpty) return null;

    final fileStat = file.statSync();
    final safeCreatedAt = createdAt ?? fileStat.modified;
    final safeUpdatedAt = updatedAt ?? fileStat.modified;
    final preview = _truncateCcPreview(lastPreview);
    final titleSource = firstUserMessage.isNotEmpty
        ? firstUserMessage
        : preview;
    final title = _truncateCcTitle(titleSource);

    return _CcLocalSessionSummary(
      sessionId: sessionId,
      uiThreadId: sessionId,
      title: title,
      preview: preview,
      messageCount: messageCount,
      createdAt: safeCreatedAt,
      updatedAt: safeUpdatedAt,
    );
  }

  String? _ccSessionIdFromRecord(Map<String, dynamic> record) {
    final direct = record['sessionId']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final snake = record['session_id']?.toString().trim();
    if (snake != null && snake.isNotEmpty) return snake;
    final result = record['result'];
    if (result is Map) {
      final nested = result['session_id']?.toString().trim();
      if (nested != null && nested.isNotEmpty) return nested;
    }
    return null;
  }

  DateTime? _ccTimestampFromRecord(Map<String, dynamic> record) {
    final raw =
        record['timestamp'] ??
        record['created_at'] ??
        record['createdAt'] ??
        record['updated_at'] ??
        record['updatedAt'];
    if (raw is String && raw.trim().isNotEmpty) {
      return DateTime.tryParse(raw.trim());
    }
    if (raw is num) {
      final value = raw.toDouble();
      final millis = value > 1e12 ? value.toInt() : (value * 1000).toInt();
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    return null;
  }

  String _ccMessageText(Map<dynamic, dynamic> message) {
    final content = message['content'];
    if (content is List) {
      final parts = <String>[];
      for (final block in content) {
        if (block is String) {
          final normalized = block.trim();
          if (normalized.isNotEmpty) parts.add(normalized);
          continue;
        }
        if (block is! Map) continue;
        final type = block['type']?.toString().trim() ?? '';
        if (type == 'text') {
          final text = block['text']?.toString().trim() ?? '';
          if (text.isNotEmpty) parts.add(text);
          continue;
        }
        if (type == 'tool_result') {
          final text = _ccToolOutputText(block['content']).trim();
          if (text.isNotEmpty) parts.add(text);
        }
      }
      return parts.join('\n').trim();
    }
    return message['text']?.toString().trim() ?? '';
  }

  String _ccToolOutputText(dynamic value) {
    if (value is String) return value;
    if (value is List) {
      return value
          .map((item) {
            if (item is String) return item;
            if (item is Map && item['text'] is String) {
              return item['text'] as String;
            }
            try {
              return jsonEncode(item);
            } catch (_) {
              return '$item';
            }
          })
          .where((item) => item.trim().isNotEmpty)
          .join('\n');
    }
    if (value is Map && value['text'] is String) {
      return value['text'] as String;
    }
    if (value == null) return '';
    try {
      return jsonEncode(value);
    } catch (_) {
      return '$value';
    }
  }

  String _truncateCcTitle(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) return '';
    return compact.length <= 42 ? compact : '${compact.substring(0, 42)}...';
  }

  String _truncateCcPreview(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) return '';
    return compact.length <= 120 ? compact : '${compact.substring(0, 120)}...';
  }

  /// Send a JSON-RPC request and await its result object (null on error/empty).
  Future<Map<String, dynamic>?> _rpcCall(
    String method,
    Map<String, dynamic> params,
  ) {
    final id = _writeRpcRequest(method, params);
    final completer = Completer<Map<String, dynamic>?>();
    _pendingRpc[id] = completer;
    return completer.future;
  }

  /// List codex threads for this engine's workspace. Returns a list of
  /// thread metadata: {id, name, preview, createdAt(ms), updatedAt(ms)}.
  /// For CC, returns an empty list (CC doesn't expose a thread list RPC).
  Future<List<Map<String, dynamic>>> listThreads() async {
    if (spec.id != 'codex') return const [];
    final controller = StreamController<sdk.ChatEvent>.broadcast();
    try {
      if (_state == _CliSessionState.uninitialized) {
        try {
          await _ensureReady(controller: controller);
        } catch (error) {
          debugPrint(
            '[$_codexHistoryLogTag] app-server startup failed: $error',
          );
          return const [];
        }
      }
      if (_state != _CliSessionState.ready) {
        debugPrint('[$_codexHistoryLogTag] app-server not ready: $_state');
        return const [];
      }

      var data = await _listCodexThreadData(cwd: spec.workspacePath);
      debugPrint(
        '[$_codexHistoryLogTag] thread/list cwd=${spec.workspacePath} count=${data.length}',
      );
      if (data.isEmpty) {
        data = await _listCodexThreadData();
        debugPrint(
          '[$_codexHistoryLogTag] thread/list all count=${data.length}',
        );
      }

      final threads = data
          .whereType<Map>()
          .map((t) => Map<String, dynamic>.from(t))
          .map((thread) {
            final createdAt = thread['createdAt'];
            final updatedAt = thread['updatedAt'];
            // Codex returns Unix *seconds*; convert to milliseconds for UI.
            final int createdMs = createdAt is num
                ? (createdAt.toDouble() * 1000).toInt()
                : DateTime.now().millisecondsSinceEpoch;
            final int updatedMs = updatedAt is num
                ? (updatedAt.toDouble() * 1000).toInt()
                : DateTime.now().millisecondsSinceEpoch;
            return <String, dynamic>{
              'id': thread['id']?.toString() ?? '',
              'name': thread['name']?.toString() ?? '',
              'preview': thread['preview']?.toString() ?? '',
              'createdAt': createdMs,
              'updatedAt': updatedMs,
            };
          })
          .where((m) => (m['id'] as String).isNotEmpty)
          .toList(growable: false);
      debugPrint(
        '[$_codexHistoryLogTag] thread/list mapped count=${threads.length} first=${threads.isEmpty ? 'none' : threads.first['id']}',
      );
      return threads;
    } catch (error) {
      debugPrint('[$_codexHistoryLogTag] thread/list failed: $error');
      return const [];
    } finally {
      if (!controller.isClosed) await controller.close();
    }
  }

  Future<List<dynamic>> _listCodexThreadData({String? cwd}) async {
    final result = await _rpcCall('thread/list', {
      // ignore: use_null_aware_elements
      if (cwd != null) 'cwd': cwd,
      'limit': 50,
      'sortDirection': 'desc',
      'sortKey': 'updated_at',
      'sourceKinds': _codexThreadSourceKinds,
    }).timeout(const Duration(seconds: 10));
    final data = result?['data'];
    return data is List ? data : const [];
  }

  /// Backfill a conversation's history from the engine's own native store
  /// (codex thread items / Claude session jsonl). Returns history-item maps in
  /// the core session schema so callers can feed them straight to
  /// `ChatMessage.fromMap`. Empty when no native session is known yet.
  Future<List<Map<String, dynamic>>> readHistory(String uiThreadId) async {
    if (spec.id == 'codex') return _readCodexHistory(uiThreadId);
    return _readCcHistory(uiThreadId);
  }

  Future<List<Map<String, dynamic>>> _readCodexHistory(
    String uiThreadId,
  ) async {
    // uiThreadId is now the codex thread id directly (no mapping lookup).
    if (uiThreadId.isEmpty) return const [];
    final controller = StreamController<sdk.ChatEvent>.broadcast();
    try {
      if (_state == _CliSessionState.uninitialized) {
        try {
          await _ensureReady(controller: controller);
        } catch (error) {
          debugPrint(
            '[$_codexHistoryLogTag] readHistory startup failed thread=$uiThreadId error=$error',
          );
        }
      }
      if (_state != _CliSessionState.ready) return const [];

      // thread/resume reopens the thread from its rollup and typically returns
      // its items in the response payload.
      Map<String, dynamic>? resumeResult;
      var resumed = false;
      try {
        resumeResult = await _rpcCall('thread/resume', {
          'threadId': uiThreadId,
          'approvalPolicy': 'never',
          'sandbox': 'danger-full-access',
        }).timeout(const Duration(seconds: 15));
        resumed = true;
      } catch (_) {
        resumeResult = null;
      }
      // Only treat the thread as loaded when resume actually succeeded. On
      // failure (expired/unknown thread) leave _threadId null so the next send
      // falls back to a fresh thread instead of turning into a dead id.
      if (resumed) {
        _threadId = uiThreadId;
        _attachedThreadId = uiThreadId;
      }

      var items = _extractCodexItems(resumeResult);
      debugPrint(
        '[$_codexHistoryLogTag] readHistory resume thread=$uiThreadId resumed=$resumed items=${items.length} types=${_codexItemTypeSummary(items)}',
      );
      if (items.isEmpty) {
        try {
          final readResult = await _rpcCall('thread/read', {
            'threadId': uiThreadId,
            'includeTurns': true,
          }).timeout(const Duration(seconds: 15));
          items = _extractCodexItems(readResult);
          debugPrint(
            '[$_codexHistoryLogTag] readHistory read thread=$uiThreadId items=${items.length} types=${_codexItemTypeSummary(items)}',
          );
        } catch (error) {
          debugPrint(
            '[$_codexHistoryLogTag] readHistory read failed thread=$uiThreadId error=$error',
          );
        }
      }
      final mapped = items
          .map(_codexItemToHistoryMap)
          .where((m) => m.isNotEmpty)
          .toList(growable: false);
      debugPrint(
        '[$_codexHistoryLogTag] readHistory mapped thread=$uiThreadId messages=${mapped.length} roles=${_historyRoleSummary(mapped)}',
      );
      return mapped;
    } finally {
      if (!controller.isClosed) await controller.close();
    }
  }

  String _codexItemTypeSummary(List<Map<String, dynamic>> items) {
    final counts = <String, int>{};
    for (final item in items) {
      final type = item['type']?.toString().trim();
      if (type == null || type.isEmpty) continue;
      counts[type] = (counts[type] ?? 0) + 1;
    }
    if (counts.isEmpty) return 'none';
    return counts.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join(',');
  }

  String _historyRoleSummary(List<Map<String, dynamic>> items) {
    final counts = <String, int>{};
    for (final item in items) {
      final role = item['role']?.toString().trim();
      if (role == null || role.isEmpty) continue;
      counts[role] = (counts[role] ?? 0) + 1;
    }
    if (counts.isEmpty) return 'none';
    return counts.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join(',');
  }

  Future<List<Map<String, dynamic>>> _readCcHistory(String uiThreadId) async {
    final sessionId = await _nativeIdFor(uiThreadId);
    if (sessionId == null || sessionId.isEmpty) return const [];
    final controller = StreamController<sdk.ChatEvent>.broadcast();
    try {
      if (_state == _CliSessionState.uninitialized) {
        try {
          await _ensureReady(controller: controller);
        } catch (_) {}
      }
      if (_state != _CliSessionState.ready) return const [];
      _attachedThreadId = uiThreadId;
      final completer = Completer<List<Map<String, dynamic>>>();
      _ccHistoryCompleter = completer;
      _sendJsonEvent({'type': 'history', 'sessionId': sessionId});
      return await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => const [],
      );
    } finally {
      _ccHistoryCompleter = null;
      if (!controller.isClosed) await controller.close();
    }
  }

  /// Locate the item list inside a thread/resume or thread/read result.
  /// Codex 0.141+ returns `thread.turns[].items[]`. Fall back to legacy
  /// `thread.items[]` for older versions.
  List<Map<String, dynamic>> _extractCodexItems(Map<String, dynamic>? result) {
    List? list;
    if (result != null) {
      // New format (codex 0.141+): thread.turns[].items[]
      final thread = result['thread'];
      if (thread is Map) {
        final turns = thread['turns'];
        if (turns is List) {
          // Flatten all items from all turns
          final flattened = <Map<String, dynamic>>[];
          for (final turn in turns) {
            if (turn is Map) {
              final turnItems = turn['items'];
              if (turnItems is List) {
                for (final item in turnItems) {
                  if (item is Map && item['type'] != null) {
                    flattened.add(Map<String, dynamic>.from(item));
                  }
                }
              }
            }
          }
          if (flattened.isNotEmpty) return flattened;
        }
        // Legacy fallback: thread.items[] or thread.content[]
        final threadItems = thread['items'];
        if (threadItems is List) {
          list = threadItems;
        } else if (thread['content'] is List) {
          list = thread['content'];
        }
      }
      // Top-level items fallback
      if (list == null) {
        final items = result['items'];
        if (items is List) {
          list = items;
        }
      }
    }
    if (list == null) return const [];
    return list
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((m) => m['type'] != null)
        .toList(growable: false);
  }

  /// Map one codex thread item to the core history-item schema.
  Map<String, dynamic> _codexItemToHistoryMap(Map raw) {
    final item = Map<String, dynamic>.from(raw);
    final type = item['type']?.toString().trim() ?? '';
    final id = item['id']?.toString();
    switch (type) {
      case 'agentMessage':
        final text = item['text']?.toString() ?? '';
        if (text.trim().isEmpty) return const {};
        final m = <String, dynamic>{'role': 'assistant', 'content': text};
        if (id != null && id.isNotEmpty) m['id'] = id;
        return m;
      case 'userMessage':
        final text = _userMessageText(item);
        if (text.trim().isEmpty) return const {};
        final m = <String, dynamic>{'role': 'user', 'content': text};
        if (id != null && id.isNotEmpty) m['id'] = id;
        return m;
      case 'reasoning':
        final text = _reasoningText(item);
        if (text.trim().isEmpty) return const {};
        final m = <String, dynamic>{'role': 'reasoning', 'content': text};
        if (id != null && id.isNotEmpty) m['id'] = id;
        return m;
      case 'commandExecution':
      case 'dynamicToolCall':
        final isShell = type == 'commandExecution';
        final name = isShell ? 'shell' : _dynamicToolName(item);
        final arguments = isShell
            ? _commandExecutionArguments(item)
            : _jsonString(item['arguments']);
        final output = isShell
            ? (item['aggregatedOutput']?.toString() ?? '')
            : _dynamicToolOutput(item);
        final isError = isShell
            ? _commandExecutionFailed(item)
            : _dynamicToolFailed(item);
        final call = <String, dynamic>{
          'name': name,
          'call_id': id ?? '',
          'arguments': arguments,
          if (output.isNotEmpty) 'result': output,
          if (isError && output.isNotEmpty) 'error': output,
        };
        final m = <String, dynamic>{
          'role': 'tool_calls',
          'content': _jsonString({
            'narrative': isShell ? 'Ran command' : 'Called $name',
            'calls': [call],
          }),
        };
        if (id != null && id.isNotEmpty) m['id'] = id;
        return m;
      case 'mcpToolCall':
        // mcpToolCall: server, tool, arguments, result, error, status
        final server = item['server']?.toString().trim() ?? '';
        final tool = item['tool']?.toString().trim() ?? '';
        if (server.isEmpty || tool.isEmpty) return const {};
        final fullName = '$server.$tool';
        final arguments = _jsonString(item['arguments'] ?? {});
        final output =
            item['result']?.toString() ?? item['error']?.toString() ?? '';
        final status = item['status']?.toString().trim().toLowerCase() ?? '';
        final isError = status == 'failed' || status == 'rejected';
        final call = <String, dynamic>{
          'name': fullName,
          'call_id': id ?? '',
          'arguments': arguments,
          if (output.isNotEmpty) 'result': output,
          if (isError && output.isNotEmpty) 'error': output,
        };
        final m = <String, dynamic>{
          'role': 'tool_calls',
          'content': _jsonString({
            'narrative': 'Called $fullName',
            'calls': [call],
          }),
        };
        if (id != null && id.isNotEmpty) m['id'] = id;
        return m;
      case 'fileChange':
        // fileChange: changes, status. Map as a tool call for visibility.
        final changes = item['changes'];
        final status = item['status']?.toString().trim().toLowerCase() ?? '';
        final isError = status == 'failed' || status == 'rejected';
        final call = <String, dynamic>{
          'name': 'fileChange',
          'call_id': id ?? '',
          'arguments': _jsonString({'changes': changes}),
          if (isError) 'error': 'File change failed',
        };
        final m = <String, dynamic>{
          'role': 'tool_calls',
          'content': _jsonString({
            'narrative': isError ? 'File change failed' : 'File change',
            'calls': [call],
          }),
        };
        if (id != null && id.isNotEmpty) m['id'] = id;
        return m;
      case 'webSearch':
        // Codex WebSearchItem: { id, query, action }. No structured results
        // surface on the thread item, so render it as a `web_search` tool
        // call — the trace renderer special-cases name == 'web_search'
        // (chat_tool_trace.dart). Without this case the item fell through to
        // `default` and was dropped (it has no text/content field).
        final query = item['query']?.toString().trim() ?? '';
        final call = <String, dynamic>{
          'name': 'web_search',
          'call_id': id ?? '',
          'arguments': _jsonString({'query': query}),
        };
        final m = <String, dynamic>{
          'role': 'tool_calls',
          'content': _jsonString({
            'narrative': query.isEmpty ? 'Searched the web' : 'Searched: $query',
            'calls': [call],
          }),
        };
        if (id != null && id.isNotEmpty) m['id'] = id;
        return m;
      default:
        final text =
            item['text']?.toString() ?? item['content']?.toString() ?? '';
        if (text.trim().isEmpty) {
          // Surface unmapped Codex item types so new tool kinds (e.g. image
          // generation) are noticed instead of silently dropped from history.
          debugPrint(
            '[$_codexHistoryLogTag] unmapped item type=$type '
            'keys=${item.keys.toList().join(',')}',
          );
          return const {};
        }
        final isUser = type.toLowerCase().contains('user');
        final m = <String, dynamic>{
          'role': isUser ? 'user' : 'assistant',
          'content': text,
        };
        if (id != null && id.isNotEmpty) m['id'] = id;
        return m;
    }
  }

  static String _shellEscape(String s) => s.replaceAll("'", r"'\''");

  String _userMessageText(Map<String, dynamic> item) {
    final content = item['content'];
    if (content is List) {
      final parts = <String>[];
      for (final entry in content) {
        if (entry is String) {
          parts.add(entry);
          continue;
        }
        if (entry is! Map) continue;
        final type = entry['type']?.toString().trim() ?? '';
        final text = entry['text']?.toString() ?? '';
        if (type == 'text' && text.isNotEmpty) {
          parts.add(text);
        }
      }
      return parts.join('').trim();
    }
    return item['text']?.toString() ?? content?.toString() ?? '';
  }

  /// Write Codex config files (config.toml + auth.json) into the sandbox.
  /// Call this from settings when the user saves Codex engine configuration.
  static Future<void> writeCodexConfig({
    required String apiKey,
    String? baseUrl,
    String? model,
  }) async {
    const method = SandboxPtyEvents.method;

    // Initialize sandbox if not already.
    await method.invokeMethod<void>('initialize');

    // Open a temporary PTY session to write files.
    final hostWorkspaceDir = await _resolveCliWorkspaceHostDir();
    final sessionId = await method.invokeMethod<int>('openSession', {
      'cols': 80,
      'rows': 24,
      if (hostWorkspaceDir != '/workspace') 'workspaceDir': hostWorkspaceDir,
    });
    if (sessionId == null) return;

    final modelName = model?.trim().isNotEmpty == true
        ? model!.trim()
        : 'GLM-4.7';
    final configToml = StringBuffer()
      ..write('model_provider = "custom"\n')
      ..write('model = "$modelName"\n')
      ..write('model_reasoning_effort = "$_codexReasoningEffort"\n')
      ..write('disable_response_storage = true\n')
      ..write('\n[model_providers.custom]\n')
      ..write('name = "custom"\n');
    if (baseUrl != null && baseUrl.trim().isNotEmpty) {
      configToml.write('base_url = "${baseUrl.trim()}"\n');
    }
    configToml
      ..write('wire_api = "responses"\n')
      ..write('requires_openai_auth = true\n')
      ..write('\n[projects."${_CliEngineSpec.codex.workspacePath}"]\n')
      ..write('trust_level = "trusted"\n');

    final authJson = jsonEncode({'OPENAI_API_KEY': apiKey});

    final cmd =
        'mkdir -p /root/.codex && '
        'printf \'%s\' \'${_shellEscape(configToml.toString())}\' > /root/.codex/config.toml && '
        'printf \'%s\' \'${_shellEscape(authJson)}\' > /root/.codex/auth.json\n';

    await method.invokeMethod<void>('writeSession', {
      'sessionId': sessionId,
      'data': cmd,
    });

    // Give it a moment to execute, then close.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    try {
      await method.invokeMethod<void>('closeSession', {'sessionId': sessionId});
    } catch (_) {}
  }

  /// Write Claude Code config file (settings.json) into the sandbox.
  /// Call this from settings when the user saves CC engine configuration.
  static Future<void> writeCcConfig({
    required String apiKey,
    String? baseUrl,
    String? model,
  }) async {
    const method = SandboxPtyEvents.method;

    // Initialize sandbox if not already.
    await method.invokeMethod<void>('initialize');

    // Open a temporary PTY session to write files.
    final hostWorkspaceDir = await _resolveCliWorkspaceHostDir();
    final sessionId = await method.invokeMethod<int>('openSession', {
      'cols': 80,
      'rows': 24,
      if (hostWorkspaceDir != '/workspace') 'workspaceDir': hostWorkspaceDir,
    });
    if (sessionId == null) return;

    final normalizedApiKey = apiKey.trim();
    final normalizedBaseUrl = baseUrl?.trim();
    final normalizedModel = model?.trim();

    final env = <String, dynamic>{'ANTHROPIC_API_KEY': normalizedApiKey};
    if (normalizedBaseUrl != null && normalizedBaseUrl.isNotEmpty) {
      env['ANTHROPIC_BASE_URL'] = normalizedBaseUrl;
    }

    final settings = <String, dynamic>{'env': env};
    if (normalizedModel != null && normalizedModel.isNotEmpty) {
      settings['model'] = normalizedModel;
    }
    final settingsJson = jsonEncode(settings);

    final envSh = StringBuffer();
    envSh.writeln(
      "export ANTHROPIC_API_KEY='${_shellEscape(normalizedApiKey)}'",
    );
    if (normalizedBaseUrl != null && normalizedBaseUrl.isNotEmpty) {
      envSh.writeln(
        "export ANTHROPIC_BASE_URL='${_shellEscape(normalizedBaseUrl)}'",
      );
    }

    final configDir = _CliEngineSpec.cc.claudeConfigDir;
    final cmd =
        'mkdir -p $configDir && '
        'printf \'%s\' \'${_shellEscape(settingsJson)}\' > $configDir/settings.json && '
        'printf \'%s\' \'${_shellEscape(envSh.toString())}\' > $configDir/env.sh\n';

    await method.invokeMethod<void>('writeSession', {
      'sessionId': sessionId,
      'data': cmd,
    });

    // Give it a moment to execute, then close.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    try {
      await method.invokeMethod<void>('closeSession', {'sessionId': sessionId});
    } catch (_) {}
  }
}

class _CcLocalSessionSummary {
  const _CcLocalSessionSummary({
    required this.sessionId,
    required this.uiThreadId,
    required this.title,
    required this.preview,
    required this.messageCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final String sessionId;
  final String uiThreadId;
  final String title;
  final String preview;
  final int messageCount;
  final DateTime createdAt;
  final DateTime updatedAt;
}

// ---------------------------------------------------------------------------
// Embedded CC bridge script (written to sandbox at runtime).
// Only used for the CC engine — Codex speaks JSON-RPC directly, no script.
// ---------------------------------------------------------------------------

const _ccBridgeScript = r'''
import { createRequire } from "module";
import { spawn, execSync } from "child_process";
import { createInterface } from "readline";
import fs from "fs";
import path from "path";
// Load the SDK from the global install (environment panel installs
// @anthropic-ai/claude-agent-sdk globally). ESM `import` would only resolve
// a local node_modules, which we no longer create.
const _sdkGlobalRoot = (() => {
  try { return execSync("npm root -g").toString().trim(); } catch { return ""; }
})();
const _require = createRequire((_sdkGlobalRoot || "/usr/lib/node_modules") + "/");
const { query } = _require("@anthropic-ai/claude-agent-sdk");
const CWD = process.env.WORKSPACE_DIR || "/workspace";
const emit = o => process.stdout.write(JSON.stringify(o) + "\n");
let ac = null;
function resolveClaudeCodeExecutable() {
  const explicit = (process.env.CLAUDE_CODE_BIN || process.env.CLAUDE_BIN || "").trim();
  return explicit || undefined;
}
function spawnClaudeCodeProcess(options) {
  const command =
    options.command === "node" || options.command === "bun"
      ? process.execPath
      : options.command;
  return spawn(command, options.args, {
    cwd: options.cwd,
    env: { ...process.env, ...(options.env ?? {}) },
    stdio: ["pipe", "pipe", "pipe"],
    shell: false,
    signal: options.signal,
  });
}
function stringifyToolOutput(value) {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) {
    return value.map(item => {
      if (typeof item === "string") return item;
      if (item && typeof item.text === "string") return item.text;
      try { return JSON.stringify(item); } catch { return String(item ?? ""); }
    }).filter(Boolean).join("\n");
  }
  if (value && typeof value.text === "string") return value.text;
  if (value == null) return "";
  try { return JSON.stringify(value); } catch { return String(value); }
}
function emitToolResults(message) {
  const content = message?.message?.content;
  if (!Array.isArray(content)) return;
  for (const block of content) {
    if (block?.type === "tool_result") {
      emit({
        type: "tool_call_done",
        id: block.tool_use_id ?? "",
        output: stringifyToolOutput(block.content).slice(0, 2000),
      });
    }
  }
}
async function send(text, resume) {
  ac = new AbortController();
  let resultError = null;
  try {
    const msgs = query({
      prompt: text,
      options: {
        abortController: ac,
        cwd: CWD,
        maxTurns: 30,
        includePartialMessages: true,
        permissionMode: "bypassPermissions",
        allowDangerouslySkipPermissions: true,
        pathToClaudeCodeExecutable: resolveClaudeCodeExecutable(),
        spawnClaudeCodeProcess,
        stderr: data => {
          const text = String(data ?? "").trim();
          if (text) emit({ type: "status", message: text });
        },
        ...(resume ? { resume } : {}),
      },
    });
    for await (const m of msgs) {
      if (ac.signal.aborted) break;
      if (m.type === "assistant") {
        for (const b of m.message?.content ?? []) {
          if (b.type === "tool_use") emit({ type: "tool_call_start", id: b.id, name: b.name, input: JSON.stringify(b.input ?? {}).slice(0, 500) });
        }
      } else if (m.type === "user") {
        emitToolResults(m);
      } else if (m.type === "tool_progress") {
        emit({ type: "status", message: `Running ${m.tool_name}...` });
      } else if (m.type === "stream_event" && m.event?.type === "content_block_delta") {
        const d = m.event.delta;
        if (d?.type === "text_delta" && d.text) emit({ type: "assistant_delta", text: d.text });
        else if (d?.type === "thinking_delta" && d.thinking) emit({ type: "thinking_delta", text: d.thinking });
      } else if (m.type === "result") {
        if (m.session_id) emit({ type: "session_id", sessionId: m.session_id });
        if (m.subtype !== "success") resultError = m.result || "Claude run failed";
      }
    }
    if (resultError && !ac.signal.aborted) {
      emit({ type: "turn_failed", error: resultError });
    } else {
      emit({ type: "turn_completed" });
    }
  } catch (e) {
    emit(ac.signal.aborted ? { type: "turn_completed" } : { type: "turn_failed", error: e?.message ?? String(e) });
  } finally { ac = null; }
}
function projectDirName(cwd) { return String(cwd || "").replace(/\//g, "-"); }
function sendHistory(sessionId) {
  try {
    if (!sessionId) { emit({ type: "history", items: [] }); return; }
    const home = process.env.HOME || process.env.USERPROFILE || "/root";
    const projectsRoot = path.join(home, ".claude", "projects");
    const candidates = [path.join(projectsRoot, projectDirName(CWD), sessionId + ".jsonl")];
    try {
      if (fs.existsSync(projectsRoot)) {
        for (const dir of fs.readdirSync(projectsRoot)) {
          candidates.push(path.join(projectsRoot, dir, sessionId + ".jsonl"));
        }
      }
    } catch {}
    let file = null;
    for (const c of candidates) { if (fs.existsSync(c)) { file = c; break; } }
    if (!file) { emit({ type: "history", items: [] }); return; }
    const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
    // Parse records once, preserving original conversational order.
    const records = [];
    for (const line of lines) {
      if (!line.trim()) continue;
      let rec; try { rec = JSON.parse(line); } catch { continue; }
      const msg = rec && rec.message;
      if (!msg || !Array.isArray(msg.content)) continue;
      records.push(msg);
    }
    // Pass 1: resolve each tool_use against its later tool_result so the call
    // can carry its output. Result/error may live in a following user turn.
    const toolUses = {};
    for (const msg of records) {
      if (msg.role === "assistant") {
        for (const b of msg.content) {
          if (b.type === "tool_use") {
            toolUses[b.id] = { name: b.name || "tool", input: JSON.stringify(b.input ?? {}).slice(0, 2000) };
          }
        }
      } else if (msg.role === "user") {
        for (const b of msg.content) {
          if (b.type === "tool_result") {
            const tu = toolUses[b.tool_use_id];
            if (tu) { tu.result = stringifyToolOutput(b.content).slice(0, 2000); tu.isError = !!b.is_error; }
          }
        }
      }
    }
    // Pass 2: emit in original order, keeping each turn's [assistant_text,
    // tool_calls] adjacent. This lets the UI attach the calls to the assistant
    // message they belong to instead of dumping every call at the very end.
    const items = [];
    for (const msg of records) {
      if (msg.role === "user") {
        for (const b of msg.content) {
          if (b.type === "text" && b.text) items.push({ role: "user", content: b.text });
        }
      } else if (msg.role === "assistant") {
        for (const b of msg.content) {
          if (b.type === "text" && b.text) {
            items.push({ role: "assistant", content: b.text });
          } else if (b.type === "tool_use") {
            const tu = toolUses[b.id] || { name: b.name || "tool", input: JSON.stringify(b.input ?? {}).slice(0, 2000) };
            items.push({
              role: "tool_calls",
              content: JSON.stringify({
                narrative: "Called " + tu.name,
                calls: [{ name: tu.name, call_id: b.id || "", arguments: tu.input, ...(tu.result != null ? { result: tu.result } : {}), ...(tu.isError ? { error: tu.result || "" } : {}) }],
              }),
            });
          }
        }
      }
    }
    emit({ type: "history", items });
  } catch {
    emit({ type: "history", items: [] });
  }
}
const rl = createInterface({ input: process.stdin });
rl.on("line", l => { const t = l.trim(); if (!t.startsWith("{")) return; try { const m = JSON.parse(t); if (m.type === "send") send(m.text ?? "", m.resume); else if (m.type === "history") sendHistory(m.sessionId); else if (m.type === "cancel" && ac) ac.abort(); } catch {} });
rl.on("close", () => process.exit(0));
emit({ type: "ready" });
''';
