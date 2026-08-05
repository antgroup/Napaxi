import '../file_bridge.dart';
import '../generated/bridge/project.dart' as rust_project;
import '../models/project.dart';
import '../models/session.dart';
import 'json_codec.dart';

/// Project display membership, runtime workspace, and project-file access.
class ProjectApi {
  ProjectApi(this._handle);

  final int Function() _handle;

  Future<NapaxiProject> register({
    required String projectId,
    required String accountId,
    required String agentId,
    required String name,
  }) async {
    final raw = await rust_project.registerProject(
      handle: _handle(),
      projectId: projectId,
      accountId: accountId,
      agentId: agentId,
      name: name,
    );
    final value = decodeJsonValue(raw);
    throwIfJsonError(value);
    return NapaxiProject.fromMap(asJsonObject(value)!);
  }

  Future<List<NapaxiProject>> list({
    required String accountId,
    required String agentId,
  }) async {
    final raw = await rust_project.listProjects(
      handle: _handle(),
      accountId: accountId,
      agentId: agentId,
    );
    final value = decodeJsonValue(raw);
    throwIfJsonError(value);
    return decodeJsonObjectListFromValue(value, NapaxiProject.fromMap);
  }

  Future<bool> archive(
    String projectId, {
    required String accountId,
    required String agentId,
  }) async {
    final raw = await rust_project.archiveProject(
      handle: _handle(),
      projectId: projectId,
      accountId: accountId,
      agentId: agentId,
    );
    final value = decodeJsonValue(raw);
    throwIfJsonError(value);
    return value == true;
  }

  Future<NapaxiSessionPlacement> placement(SessionKey sessionKey) async {
    final raw = await rust_project.getSessionPlacement(
      handle: _handle(),
      sessionKeyJson: sessionKey.toJson(),
    );
    final value = decodeJsonValue(raw);
    throwIfJsonError(value);
    return NapaxiSessionPlacement.fromMap(asJsonObject(value)!);
  }

  Future<List<NapaxiSessionPlacement>> listPlacements({
    required String accountId,
    required String agentId,
  }) async {
    final raw = await rust_project.listSessionPlacements(
      handle: _handle(),
      accountId: accountId,
      agentId: agentId,
    );
    final value = decodeJsonValue(raw);
    throwIfJsonError(value);
    return decodeJsonObjectListFromValue(value, NapaxiSessionPlacement.fromMap);
  }

  Future<NapaxiSessionPlacement> moveSession(
    SessionKey sessionKey, {
    String? projectId,
    required NapaxiWorkspacePolicy workspacePolicy,
    int? expectedRevision,
  }) async {
    final raw = await rust_project.moveSessionToProject(
      handle: _handle(),
      sessionKeyJson: sessionKey.toJson(),
      projectId: projectId,
      workspacePolicy: workspacePolicy.wireValue,
      expectedRevision: expectedRevision,
    );
    final value = decodeJsonValue(raw);
    throwIfJsonError(value);
    return NapaxiSessionPlacement.fromMap(asJsonObject(value)!);
  }

  Future<List<WorkspaceFileInfo>> listFiles(
    String projectId, {
    required String accountId,
    required String agentId,
    String? subdir,
    bool recursive = true,
  }) async {
    final raw = await rust_project.listProjectFiles(
      handle: _handle(),
      projectId: projectId,
      accountId: accountId,
      agentId: agentId,
      subdir: subdir,
      recursive: recursive,
    );
    final value = decodeJsonValue(raw);
    throwIfJsonError(value);
    return decodeJsonObjectListFromValue(value, WorkspaceFileInfo.fromMap);
  }
}
