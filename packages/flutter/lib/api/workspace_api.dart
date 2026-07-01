import '../generated/bridge/workspace.dart' as rust_workspace;
import '../models/config.dart';
import '../models/workspace.dart';
import 'json_codec.dart';

/// Workspace API: read and write files, search memory, and inspect the
/// journal/recall index for an agent's workspace.
///
/// Owns its logic and calls the core bridge directly (handle + config supplied
/// by the engine as closures). `NapaxiEngine`'s flat workspace methods forward
/// to this facade. Reference shape: [AutomationApi], [CapabilityApi].
class WorkspaceApi {
  WorkspaceApi(this._handle, {required LlmConfig Function() config})
      : _config = config;

  final int Function() _handle;
  final LlmConfig Function() _config;

  static const String _defaultAccountId = 'default';
  static const String _defaultAgentId = 'napaxi';

  Future<WorkspaceFile?> readFile(
    String path, {
    String accountId = _defaultAccountId,
    String agentId = _defaultAgentId,
  }) async {
    final json = await rust_workspace.readWorkspaceFile(
      handle: _handle(),
      accountId: accountId,
      agentId: agentId,
      path: path,
    );
    if (json == 'null') return null;
    final map = decodeJsonObject(json);
    if (map.containsKey('error')) throw Exception(map['error']);
    return WorkspaceFile.fromMap(map);
  }

  Future<bool> writeFile(
    String path,
    String content, {
    String accountId = _defaultAccountId,
    String agentId = _defaultAgentId,
  }) {
    return rust_workspace.writeWorkspaceFile(
      handle: _handle(),
      accountId: accountId,
      agentId: agentId,
      path: path,
      content: content,
    );
  }

  Future<bool> appendFile(
    String path,
    String content, {
    String accountId = _defaultAccountId,
    String agentId = _defaultAgentId,
  }) {
    return rust_workspace.appendWorkspaceFile(
      handle: _handle(),
      accountId: accountId,
      agentId: agentId,
      path: path,
      content: content,
    );
  }

  Future<bool> deleteFile(
    String path, {
    String accountId = _defaultAccountId,
    String agentId = _defaultAgentId,
  }) {
    return rust_workspace.deleteWorkspaceFile(
      handle: _handle(),
      accountId: accountId,
      agentId: agentId,
      path: path,
    );
  }

  Future<List<WorkspaceEntry>> listFiles({
    String directory = '',
    String accountId = _defaultAccountId,
    String agentId = _defaultAgentId,
  }) async {
    final json = await rust_workspace.listWorkspaceFiles(
      handle: _handle(),
      accountId: accountId,
      agentId: agentId,
      directory: directory,
    );
    return decodeJsonObjectList(json, WorkspaceEntry.fromMap);
  }

  Future<List<MemorySearchResult>> search(
    String query, {
    int limit = 5,
    String accountId = _defaultAccountId,
    String agentId = _defaultAgentId,
  }) async {
    final json = await rust_workspace.searchMemory(
      handle: _handle(),
      accountId: accountId,
      agentId: agentId,
      query: query,
      limit: limit.clamp(1, 20).toInt(),
    );
    final decoded = decodeJsonValue(json);
    throwIfJsonError(decoded);
    final list = decoded is List
        ? decoded
        : asJsonObject(decoded)?['results'] as List? ?? const [];
    return list
        .map((e) => MemorySearchResult.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MemoryRecallSession>> recallSessions(
    String query, {
    int limit = 3,
    String accountId = _defaultAccountId,
    String agentId = _defaultAgentId,
    String currentThreadId = '',
  }) async {
    final json = await rust_workspace.recallSessions(
      handle: _handle(),
      configJson: _config().toJson(),
      accountId: accountId,
      agentId: agentId,
      currentThreadId: currentThreadId,
      query: query,
      limit: limit.clamp(1, 5).toInt(),
    );
    final decoded = decodeJsonValue(json);
    throwIfJsonError(decoded);
    final list = decoded is List
        ? decoded
        : asJsonObject(decoded)?['results'] as List? ?? const [];
    return list
        .map((e) => MemoryRecallSession.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<RecallIndexStats> rebuildRecallIndex({
    String accountId = _defaultAccountId,
    String agentId = _defaultAgentId,
  }) async {
    final json = await rust_workspace.rebuildRecallIndex(
      handle: _handle(),
      accountId: accountId,
      agentId: agentId,
    );
    final decoded = decodeJsonValue(json);
    throwIfJsonError(decoded);
    return RecallIndexStats.fromMap(
      asJsonObject(decoded) ?? const <String, dynamic>{},
    );
  }

  Future<RecallIndexStats> recallIndexStats({
    String accountId = _defaultAccountId,
    String agentId = _defaultAgentId,
  }) async {
    final json = await rust_workspace.recallIndexStats(
      handle: _handle(),
      accountId: accountId,
      agentId: agentId,
    );
    final decoded = decodeJsonValue(json);
    throwIfJsonError(decoded);
    return RecallIndexStats.fromMap(
      asJsonObject(decoded) ?? const <String, dynamic>{},
    );
  }

  Future<List<JournalDay>> listJournalDays({
    String accountId = _defaultAccountId,
    String agentId = _defaultAgentId,
  }) async {
    final json = await rust_workspace.listJournalDays(
      handle: _handle(),
      accountId: accountId,
      agentId: agentId,
    );
    final decoded = decodeJsonValue(json);
    throwIfJsonError(decoded);
    return decodeJsonObjectListFromValue(decoded, JournalDay.fromMap);
  }

  Future<List<JournalTurnRecord>> readJournalDay(
    String date, {
    String accountId = _defaultAccountId,
    String agentId = _defaultAgentId,
  }) async {
    final json = await rust_workspace.readJournalDay(
      handle: _handle(),
      accountId: accountId,
      agentId: agentId,
      date: date,
    );
    final decoded = decodeJsonValue(json);
    throwIfJsonError(decoded);
    return decodeJsonObjectListFromValue(decoded, JournalTurnRecord.fromMap);
  }

  Future<String> systemPrompt({
    String accountId = _defaultAccountId,
    String agentId = _defaultAgentId,
  }) {
    return rust_workspace.getSystemPrompt(
      handle: _handle(),
      accountId: accountId,
      agentId: agentId,
    );
  }

  Future<int> reseed({
    String accountId = _defaultAccountId,
    String agentId = _defaultAgentId,
  }) async {
    final json = await rust_workspace.reseedWorkspace(
      handle: _handle(),
      accountId: accountId,
      agentId: agentId,
    );
    final map = decodeJsonObject(json);
    return map['seeded'] as int? ?? 0;
  }
}
