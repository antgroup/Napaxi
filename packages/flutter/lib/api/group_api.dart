import 'dart:async';
import 'dart:convert';

import '../generated/bridge/group.dart' as rust_group;
import '../models/chat_event.dart';
import '../models/config.dart';
import '../models/group.dart';
import '../models/session.dart';
import 'json_codec.dart';

/// Group API: create, manage, and message multi-agent groups.
///
/// Owns its logic and calls the core bridge directly (handle + config supplied
/// by the engine as closures). `NapaxiEngine`'s flat group methods forward to
/// this facade. Reference shape: [WorkspaceApi], [AutomationApi].
class GroupApi {
  GroupApi(this._handle, {required LlmConfig Function() config})
      : _config = config;

  final int Function() _handle;
  final LlmConfig Function() _config;

  Future<String> create(String name, List<String> memberAgentIds) {
    return rust_group.createGroup(
      handle: _handle(),
      name: name,
      membersJson: jsonEncode(memberAgentIds),
    );
  }

  bool delete(String groupId) =>
      rust_group.deleteGroup(handle: _handle(), groupId: groupId);

  List<GroupInfo> list() {
    final json = rust_group.listGroups(handle: _handle());
    return decodeJsonObjectList(json, GroupInfo.fromMap);
  }

  GroupInfo? get(String groupId) {
    final json = rust_group.getGroup(handle: _handle(), groupId: groupId);
    if (json == 'null') return null;
    return GroupInfo.fromJson(json);
  }

  bool rename(String groupId, String newName) => rust_group.renameGroup(
        handle: _handle(),
        groupId: groupId,
        newName: newName,
      );

  Future<bool> updateMembers(String groupId, List<String> memberAgentIds) {
    return rust_group.updateGroupMembers(
      handle: _handle(),
      groupId: groupId,
      membersJson: jsonEncode(memberAgentIds),
    );
  }

  bool setCustomPrompt(String groupId, String? prompt) {
    return rust_group.setGroupCustomPrompt(
      handle: _handle(),
      groupId: groupId,
      prompt: prompt,
    );
  }

  List<GroupMessage> messages(String groupId) {
    final json =
        rust_group.getGroupMessages(handle: _handle(), groupId: groupId);
    return decodeJsonObjectList(json, GroupMessage.fromMap);
  }

  bool clearHistory(String groupId) =>
      rust_group.clearGroupHistory(handle: _handle(), groupId: groupId);

  Stream<ChatEvent> send(
    String groupId,
    String message, {
    int maxIterations = 0,
  }) {
    final controller = StreamController<ChatEvent>();
    rust_group
        .sendToGroup(
      handle: _handle(),
      groupId: groupId,
      configJson: _config().toJson(),
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

  Stream<ChatEvent> sendToAgent(
    String groupId,
    String agentId,
    SessionKey session,
    String message, {
    int maxIterations = 0,
  }) {
    final controller = StreamController<ChatEvent>();
    rust_group
        .sendToGroupAgent(
      handle: _handle(),
      groupId: groupId,
      agentId: agentId,
      configJson: _config().toJson(),
      sessionKeyJson: session.toJson(),
      message: message,
      maxIterations: maxIterations,
    )
        .then((resultJson) {
      final decoded = decodeJsonValue(resultJson);
      final error = jsonErrorMessage(decoded);
      if (error != null) {
        controller.addError(Exception(error));
      } else {
        for (final item in decodeJsonObjectListFromValue(
          decoded,
          ChatEvent.fromMap,
        )) {
          controller.add(item);
        }
      }
      controller.close();
    }).catchError((Object e) {
      controller.addError(e);
      controller.close();
    });
    return controller.stream;
  }

  String exportState() => rust_group.exportGroupState(handle: _handle());

  Future<bool> importState(String stateJson) =>
      rust_group.importGroupState(handle: _handle(), stateJson: stateJson);
}
