import 'dart:convert';

import 'api/json_codec.dart';
import 'models/chat_event.dart';
import 'models/custom_tool.dart';

/// Engine id identifying the built-in Napaxi core agent loop.
const String napaxiCoreAgentEngineId = 'napaxi_core';

/// Engine id identifying a host-supplied external agent loop.
const String externalHostAgentEngineId = 'external_host';

/// Host-carried agent loop executor.
///
/// External engines own the loop, while tool discovery and execution continue
/// through [AgentEngineToolBroker] so Napaxi core remains the policy boundary.
abstract class AgentEngineExecutor {
  /// Runs one turn of the external agent loop, using [tools] to discover and
  /// invoke tools through Napaxi core.
  Future<AgentEngineTurnResult> startTurn(
    AgentEngineTurnRequest request,
    AgentEngineToolBroker tools,
  );

  /// Cancels an in-flight run; returns whether the cancellation was honored.
  Future<bool> cancel({
    required String runId,
    required String sessionKeyJson,
  }) async {
    return false;
  }

  /// Resumes a previously interrupted run. Unsupported by default.
  Future<AgentEngineTurnResult> resume(
    AgentEngineTurnRequest request,
    AgentEngineToolBroker tools,
  ) async {
    return AgentEngineTurnResult.error('Agent engine resume is unsupported');
  }
}

/// Input for a single external-engine turn: identifies the engine, run,
/// account/agent, session, working directories, and the user message plus
/// attachments to process.
class AgentEngineTurnRequest {
  final String engineId;
  final String engineProfileId;
  final Map<String, dynamic> engineConfig;
  final String runId;
  final String filesDir;
  final String workspaceFilesDir;
  final String accountId;
  final String agentId;
  final String sessionKeyJson;
  final String message;
  final String attachmentsJson;
  final String configJson;

  const AgentEngineTurnRequest({
    required this.engineId,
    this.engineProfileId = '',
    this.engineConfig = const {},
    required this.runId,
    required this.filesDir,
    required this.workspaceFilesDir,
    required this.accountId,
    required this.agentId,
    required this.sessionKeyJson,
    required this.message,
    required this.attachmentsJson,
    required this.configJson,
  });

  factory AgentEngineTurnRequest.fromMap(Map<String, dynamic> map) {
    final rawConfig = map['engine_config'];
    return AgentEngineTurnRequest(
      engineId: map['engine_id'] as String? ?? externalHostAgentEngineId,
      engineProfileId: map['engine_profile_id'] as String? ?? '',
      engineConfig: rawConfig is Map
          ? Map<String, dynamic>.from(rawConfig)
          : const <String, dynamic>{},
      runId: map['run_id'] as String? ?? '',
      filesDir: map['files_dir'] as String? ?? '',
      workspaceFilesDir: map['workspace_files_dir'] as String? ?? '',
      accountId: map['account_id'] as String? ?? '',
      agentId: map['agent_id'] as String? ?? '',
      sessionKeyJson: map['session_key_json'] as String? ?? '{}',
      message: map['message'] as String? ?? '',
      attachmentsJson: map['attachments_json'] as String? ?? '[]',
      configJson: map['config_json'] as String? ?? '{}',
    );
  }

  Map<String, dynamic> toMap() => {
        'engine_id': engineId,
        'engine_profile_id': engineProfileId,
        'engine_config': engineConfig,
        'run_id': runId,
        'files_dir': filesDir,
        'workspace_files_dir': workspaceFilesDir,
        'account_id': accountId,
        'agent_id': agentId,
        'session_key_json': sessionKeyJson,
        'message': message,
        'attachments_json': attachmentsJson,
        'config_json': configJson,
      };
}

/// Result of a turn: the ordered list of [ChatEvent]s (as maps) the engine
/// emitted back to Napaxi core.
class AgentEngineTurnResult {
  final List<Map<String, dynamic>> events;

  const AgentEngineTurnResult({required this.events});

  /// Builds a result containing a single final text response.
  factory AgentEngineTurnResult.response(String content) {
    return AgentEngineTurnResult(
      events: [
        {'type': 'response', 'content': content},
      ],
    );
  }

  /// Builds a result containing a single error event.
  factory AgentEngineTurnResult.error(String message) {
    return AgentEngineTurnResult(
      events: [
        {'type': 'error', 'message': message},
      ],
    );
  }

  /// Builds a result by encoding a list of typed [ChatEvent]s.
  factory AgentEngineTurnResult.fromEvents(List<ChatEvent> events) {
    return AgentEngineTurnResult(
      events: events.map(chatEventToMap).toList(growable: false),
    );
  }

  Map<String, dynamic> toMap() => {'events': events};

  String toJsonString() => jsonEncode(toMap());
}

/// Request to feed a single streamed engine event into Napaxi core for a run.
class AgentEngineRunEventRequest {
  final String runId;
  final String sessionKeyJson;
  final Map<String, dynamic> event;

  const AgentEngineRunEventRequest({
    required this.runId,
    this.sessionKeyJson = '',
    required this.event,
  });

  Map<String, dynamic> toMap() => {
        'run_id': runId,
        'session_key_json': sessionKeyJson,
        'event': event,
      };

  String toJsonString() => jsonEncode(toMap());
}

/// Result of feeding one run event into core: the (possibly transformed) event,
/// the accumulated final content, and whether the run errored or completed.
class AgentEngineRunEventResult {
  final Map<String, dynamic> event;
  final String finalContent;
  final bool isError;
  final bool completed;

  const AgentEngineRunEventResult({
    required this.event,
    this.finalContent = '',
    this.isError = false,
    this.completed = false,
  });

  /// Parses a result from its JSON-string wire form.
  factory AgentEngineRunEventResult.fromJsonString(String jsonStr) {
    final decoded = decodeJsonObject(jsonStr);
    return AgentEngineRunEventResult(
      event: decoded['event'] is Map
          ? Map<String, dynamic>.from(decoded['event'] as Map)
          : const <String, dynamic>{},
      finalContent: decoded['final_content'] as String? ?? '',
      isError: decoded['is_error'] as bool? ?? false,
      completed: decoded['completed'] as bool? ?? false,
    );
  }
}

/// Bridge an external engine uses to discover and call Napaxi-managed tools.
///
/// Wraps host callbacks that marshal tool listing/invocation across the FFI
/// boundary, keeping Napaxi core as the policy/admission boundary.
class AgentEngineToolBroker {
  AgentEngineToolBroker(
    this._handle, {
    Future<String> Function(int handle, String requestJson)? listToolsJson,
    Future<String> Function(int handle, String requestJson)? callToolJson,
  })  : _listToolsJson = listToolsJson,
        _callToolJson = callToolJson;

  final int Function() _handle;
  final Future<String> Function(int handle, String requestJson)? _listToolsJson;
  final Future<String> Function(int handle, String requestJson)? _callToolJson;

  /// Lists the tools available to [agentId] for the given account/session.
  Future<List<CustomToolDef>> listTools({
    required String agentId,
    required String accountId,
    String? sessionKeyJson,
  }) async {
    final listToolsJson = _listToolsJson;
    if (listToolsJson == null) {
      throw UnsupportedError('AgentEngineToolBroker listTools is unsupported');
    }
    final response = await listToolsJson(
      _handle(),
      jsonEncode({
        'agent_id': agentId,
        'account_id': accountId,
        if (sessionKeyJson != null) 'session_key_json': sessionKeyJson,
      }),
    );
    final decoded = jsonDecode(response);
    if (decoded is Map && decoded['error'] != null) {
      throw StateError(decoded['error'].toString());
    }
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => CustomToolDef.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  /// Invokes the named tool with [arguments] and returns its result.
  Future<AgentEngineToolCallResult> callTool({
    required String callId,
    required String name,
    required Map<String, dynamic> arguments,
    required String agentId,
    required String accountId,
    String? sessionKeyJson,
  }) async {
    final callToolJson = _callToolJson;
    if (callToolJson == null) {
      throw UnsupportedError('AgentEngineToolBroker callTool is unsupported');
    }
    final response = await callToolJson(
      _handle(),
      jsonEncode({
        'call_id': callId,
        'name': name,
        'arguments': arguments,
        'agent_id': agentId,
        'account_id': accountId,
        if (sessionKeyJson != null) 'session_key_json': sessionKeyJson,
      }),
    );
    return AgentEngineToolCallResult.fromJsonString(response);
  }
}

/// Outcome of a brokered tool call: textual [output], error flag, any side
/// [ChatEvent]s the tool emitted, and the declared [effect] category.
class AgentEngineToolCallResult {
  final String output;
  final bool isError;
  final List<ChatEvent> events;
  final String effect;

  const AgentEngineToolCallResult({
    required this.output,
    required this.isError,
    this.events = const [],
    this.effect = 'unknown',
  });

  /// Parses a tool-call result from its JSON-string wire form.
  factory AgentEngineToolCallResult.fromJsonString(String jsonStr) {
    final decoded = decodeJsonObject(jsonStr);
    if (decoded['error'] != null) {
      return AgentEngineToolCallResult(
        output: decoded['error'].toString(),
        isError: true,
      );
    }
    return AgentEngineToolCallResult(
      output: decoded['output'] as String? ?? '',
      isError: decoded['is_error'] as bool? ?? false,
      events: (decoded['events'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => ChatEvent.fromMap(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      effect: decoded['effect'] as String? ?? 'unknown',
    );
  }
}

/// Encodes a typed [ChatEvent] into its JSON-map wire form for transport back
/// to Napaxi core. Unsupported event types collapse to an error event.
Map<String, dynamic> chatEventToMap(ChatEvent event) {
  return switch (event) {
    RunStartedEvent(:final runId, :final sessionKey, :final agentId) => {
        'type': 'run_started',
        'run_id': runId,
        'session_key': sessionKey,
        'agent_id': agentId,
      },
    RunProgressEvent(:final runId, :final kind, :final message) => {
        'type': 'run_progress',
        'run_id': runId,
        'kind': kind,
        'message': message,
      },
    RunCompletedEvent(
      :final runId,
      :final status,
      :final evidenceKind,
      :final verification,
      :final toolCallCount,
    ) =>
      {
        'type': 'run_completed',
        'run_id': runId,
        'status': status,
        'evidence_kind': evidenceKind,
        'verification': verification,
        'tool_call_count': toolCallCount,
      },
    ToolCallEvent(:final callId, :final name, :final arguments) => {
        'type': 'tool_call',
        'call_id': callId,
        'name': name,
        'arguments': arguments,
      },
    ToolCallDeltaEvent(
      :final callId,
      :final name,
      :final argumentsDelta,
      :final argumentsSoFar,
    ) =>
      {
        'type': 'tool_call_delta',
        'call_id': callId,
        'name': name,
        'arguments_delta': argumentsDelta,
        'arguments_so_far': argumentsSoFar,
      },
    ToolResultEvent(
      :final callId,
      :final name,
      :final output,
      :final isError,
    ) =>
      {
        'type': 'tool_result',
        'call_id': callId,
        'name': name,
        'output': output,
        'is_error': isError,
      },
    ResponseEvent(:final content) => {'type': 'response', 'content': content},
    ResponseDeltaEvent(:final content) => {
        'type': 'response_delta',
        'content': content,
      },
    ReasoningDeltaEvent(:final content) => {
        'type': 'reasoning_delta',
        'content': content,
      },
    ThinkingEvent(:final content) => {'type': 'thinking', 'content': content},
    ErrorEvent(:final message) => {'type': 'error', 'message': message},
    ToolOutputChunkEvent(:final callId, :final content, :final stream) => {
        'type': 'tool_output_chunk',
        'call_id': callId,
        'content': content,
        'stream': stream,
      },
    InterruptedEvent() => {'type': 'interrupted'},
    StreamResetEvent(:final reason) => {'type': 'stream_reset', 'reason': reason},
    _ => {'type': 'error', 'message': 'Unsupported ChatEvent encoding'},
  };
}
