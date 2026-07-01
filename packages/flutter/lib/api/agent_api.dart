import 'dart:async';

import '../generated/bridge/agent.dart' as rust_agent;
import '../generated/bridge/agent_defs.dart' as rust_agent_defs;
import '../models/agent.dart';
import '../models/chat_event.dart';
import '../models/config.dart';
import '../models/session.dart';
import '../models/skill.dart';
import 'json_codec.dart';

/// Agent API: create/list/delete agents, send messages, and manage agent
/// definitions.
///
/// Owns its logic and calls the core bridge directly (handle + config supplied
/// by the engine as closures). `NapaxiEngine`'s flat agent methods forward to
/// this facade. Reference shape: [WorkspaceApi], [GroupApi].
class AgentApi {
  AgentApi(this._handle, {required LlmConfig Function() config})
      : _config = config;

  final int Function() _handle;
  final LlmConfig Function() _config;

  static const String _defaultAgentId = 'napaxi';

  Future<AgentHandle> getOrCreate(String agentId, {LlmConfig? config}) async {
    final effectiveConfig = config ?? _config();
    final json = await rust_agent.getOrCreateAgent(
      handle: _handle(),
      agentId: agentId,
      configJson: effectiveConfig.toJson(),
    );
    final map = decodeJsonObject(json);
    if (map.containsKey('error')) throw Exception(map['error']);
    return AgentHandle(agentId: map['agent_id'] as String);
  }

  List<String> list() {
    final json = rust_agent.listAgents(handle: _handle());
    return decodeJsonArray(json).cast<String>();
  }

  bool delete(String agentId) {
    if (agentId == _defaultAgentId) return false;
    return rust_agent.deleteAgent(handle: _handle(), agentId: agentId);
  }

  Stream<ChatEvent> send(
    AgentHandle agent,
    SessionKey session,
    String message, {
    LlmConfig? config,
    int maxIterations = 0,
  }) {
    final effectiveConfig = config ?? _config();
    final controller = StreamController<ChatEvent>();
    rust_agent
        .agentSend(
      handle: _handle(),
      agentId: agent.agentId,
      configJson: effectiveConfig.toJson(),
      sessionKeyJson: session.toJson(),
      message: message,
      maxIterations: maxIterations,
    )
        .then((resultJson) {
      final list = decodeJsonObjectList(resultJson, ChatEvent.fromMap);
      for (final item in list) {
        controller.add(item);
      }
      controller.close();
    }).catchError((Object e) {
      controller.addError(e);
      controller.close();
    });
    return controller.stream;
  }

  Future<AgentDefinition> createDefinition(AgentDefinition def) async {
    final json = await rust_agent_defs.createAgentDefinition(
      handle: _handle(),
      defJson: def.toJson(),
    );
    return AgentDefinition.fromJson(json);
  }

  Future<List<AgentDefinition>> listDefinitions() async {
    final json = await rust_agent_defs.listAgentDefinitions(handle: _handle());
    return decodeJsonObjectList(json, AgentDefinition.fromMap);
  }

  Future<AgentDefinition?> getDefinition(String defId) async {
    final json = await rust_agent_defs.getAgentDefinition(
      handle: _handle(),
      defId: defId,
    );
    if (json == 'null') return null;
    return AgentDefinition.fromJson(json);
  }

  Future<bool> updateDefinition(AgentDefinition def) async {
    return rust_agent_defs.updateAgentDefinition(
      handle: _handle(),
      defJson: def.toJson(),
    );
  }

  Future<bool> deleteDefinition(String defId) async {
    return rust_agent_defs.deleteAgentDefinition(
        handle: _handle(), defId: defId);
  }

  Future<AgentDefinition> importMarkdown(String content) async {
    final json = await rust_agent_defs.importAgentMd(
      handle: _handle(),
      content: content,
    );
    return AgentDefinition.fromJson(json);
  }

  Future<List<ToolInfo>> listAvailableTools() async {
    final json = await rust_agent_defs.listAvailableTools(handle: _handle());
    return decodeJsonObjectList(json, ToolInfo.fromMap);
  }

  Future<bool> createFromDefinition(String defId, {LlmConfig? config}) async {
    final effectiveConfig = config ?? _config();
    final result = await rust_agent_defs.createAgentFromDefinition(
      handle: _handle(),
      defId: defId,
      configJson: effectiveConfig.toJson(),
    );
    return result != 0;
  }
}
