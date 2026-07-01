import 'dart:convert';

import '../generated/bridge/agent_app.dart' as rust_agent_app;
import '../models/agent_app.dart';

/// Agent-app API: register and list agent-app packages with the engine.
class AgentAppApi {
  AgentAppApi(this._handle);

  final int Function() _handle;

  AgentAppPackage registerPackage(AgentAppPackage package) {
    final json = rust_agent_app.registerAgentAppPackage(
      handle: _handle(),
      packageJson: package.toJsonString(),
    );
    _throwIfError(json);
    return AgentAppPackage.fromMap(jsonDecode(json) as Map);
  }

  List<AgentAppPackage> listPackages() {
    return decodeAgentAppPackages(
      rust_agent_app.listAgentAppPackages(handle: _handle()),
    );
  }

  AgentAppPackage? getPackage(String agentId) {
    final json = rust_agent_app.getAgentAppPackage(
      handle: _handle(),
      agentId: agentId,
    );
    if (json == 'null') return null;
    return AgentAppPackage.fromMap(jsonDecode(json) as Map);
  }

  bool deletePackage(String agentId) {
    return rust_agent_app.deleteAgentAppPackage(
      handle: _handle(),
      agentId: agentId,
    );
  }

  AgentAppActionRecord submitResult(AgentAppActionResult result) {
    final json = rust_agent_app.submitAgentAppActionResult(
      handle: _handle(),
      resultJson: result.toJsonString(),
    );
    _throwIfError(json);
    return AgentAppActionRecord.fromMap(jsonDecode(json) as Map);
  }

  List<AgentAppActionRecord> listProposals({String agentId = ''}) {
    return decodeAgentAppActionRecords(
      rust_agent_app.listAgentAppActionProposals(
        handle: _handle(),
        agentId: agentId,
      ),
    );
  }

  AgentAppActionRecord? getProposal(String requestId) {
    final json = rust_agent_app.getAgentAppActionProposal(
      handle: _handle(),
      requestId: requestId,
    );
    if (json == 'null') return null;
    return AgentAppActionRecord.fromMap(jsonDecode(json) as Map);
  }

  void _throwIfError(String json) {
    final decoded = jsonDecode(json);
    if (decoded is Map && decoded['error'] != null) {
      throw StateError(decoded['error'].toString());
    }
  }
}
