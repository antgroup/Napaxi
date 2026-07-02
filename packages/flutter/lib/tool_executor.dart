import 'models/agent_app.dart';

/// Immutable record emitted after a host-side tool execution finishes.
///
/// Hosts can observe this to build evidence-driven state, such as carrying
/// media artifacts returned by a platform tool into a later A2A send. The
/// observer must not throw; failures are ignored by the engine.
class McToolExecutionResult {
  const McToolExecutionResult({
    required this.toolName,
    required this.paramsJson,
    required this.result,
    required this.isError,
    this.context,
  });

  final String toolName;
  final String paramsJson;
  final String result;
  final bool isError;
  final Map<String, dynamic>? context;
}

typedef McToolResultObserver = void Function(McToolExecutionResult result);

/// Custom tool executor interface.
///
/// Implement this to handle custom tool calls from the AI Agent.
/// The executor is invoked asynchronously when a custom tool is called,
/// allowing HTTP requests, database queries, and other async operations.
///
/// Example:
/// ```dart
/// class MyToolExecutor extends McToolExecutor {
///   @override
///   Future<String> execute(String toolName, String paramsJson) async {
///     switch (toolName) {
///       case 'image_analyze':
///         return await callVisionApi(paramsJson);
///       default:
///         return jsonEncode({'error': 'unsupported tool: $toolName'});
///     }
///   }
/// }
/// ```
abstract class McToolExecutor {
  /// Execute a custom tool call.
  ///
  /// [toolName] The name of the tool being called.
  /// [paramsJson] The tool parameters as a JSON string.
  /// Returns: execution result string (JSON or plain text).
  Future<String> execute(String toolName, String paramsJson);
}

/// Dispatcher for provider-backed agent app actions.
///
/// Napaxi creates an auditable proposal; the host adapter decides whether to
/// hand off to an app, call a backend, or return an already-completed result.
abstract class AgentAppActionExecutor {
  Future<AgentAppActionResult> execute(AgentAppActionRequest request);
}

/// Deprecated alias for [AgentAppActionExecutor].
@Deprecated('Use AgentAppActionExecutor instead.')
typedef McAgentAppActionExecutor = AgentAppActionExecutor;
