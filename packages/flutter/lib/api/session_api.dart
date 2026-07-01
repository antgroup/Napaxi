import '../engine.dart';
import '../models/session.dart';

/// Session API: create, list, and manage conversation sessions.
///
/// Stateless CRUD (create/list/delete/clear/history/context/attachments) calls
/// the engine's flat bridge methods; the run-coupled controls (cancel,
/// answerHumanRequest, injectMessage, retractInjectedMessage) go through the
/// session-run state machine in [EngineCore].
class SessionApi {
  SessionApi(this._engine, this._core);

  final NapaxiEngine _engine;
  final EngineCore _core;

  Future<SessionKey> create({
    String agentId = NapaxiEngine.defaultAgentId,
    String channelType = 'app',
    String accountId = NapaxiEngine.defaultAccountId,
    String? threadId,
  }) {
    return _engine.createSession(
      agentId: agentId,
      channelType: channelType,
      accountId: accountId,
      threadId: threadId,
    );
  }

  Future<List<SessionInfo>> list({
    String agentId = NapaxiEngine.defaultAgentId,
    String accountId = NapaxiEngine.defaultAccountId,
  }) {
    return _engine.listSessions(agentId: agentId, accountId: accountId);
  }

  Future<bool> delete(SessionKey sessionKey) =>
      _engine.deleteSession(sessionKey);

  Future<bool> clear(SessionKey sessionKey) => _engine.clearSession(sessionKey);

  Future<bool> cancel(SessionKey sessionKey,
      {String agentId = NapaxiEngine.defaultAgentId}) {
    return _core.cancelSession(sessionKey, agentId: agentId);
  }

  Future<bool> answerHumanRequest(String requestId, String response) {
    return _core.answerHumanRequest(requestId, response);
  }

  Future<List<ChatMessage>> history(
    String threadId, {
    String agentId = NapaxiEngine.defaultAgentId,
  }) {
    return _engine.getHistory(threadId, agentId: agentId);
  }

  Future<HistoryPage> historyPage(
    String threadId, {
    String agentId = NapaxiEngine.defaultAgentId,
    String? before,
    int limit = 50,
  }) {
    return _engine.getHistoryPage(
      threadId,
      agentId: agentId,
      before: before,
      limit: limit,
    );
  }

  Future<ContextStatus> compactContext(
    SessionKey sessionKey, {
    String agentId = NapaxiEngine.defaultAgentId,
    String? focus,
  }) {
    return _engine.compactContext(
      sessionKey,
      agentId: agentId,
      focus: focus,
    );
  }

  Future<ContextStatus> contextStatus(
    String threadId, {
    String agentId = NapaxiEngine.defaultAgentId,
  }) {
    return _engine.contextStatus(threadId, agentId: agentId);
  }

  /// Queue a message to be injected into a running (or next) session turn.
  Future<bool> injectMessage(
    SessionKey sessionKey,
    String message, {
    String agentId = NapaxiEngine.defaultAgentId,
    List<McAttachment>? attachments,
  }) {
    return _core.injectMessage(
      sessionKey,
      message,
      agentId: agentId,
      attachments: attachments,
    );
  }

  /// Retract the latest queued injected message matching [message].
  Future<bool> retractInjectedMessage(SessionKey sessionKey, String message) =>
      _core.retractInjectedMessage(sessionKey, message);

  /// Persist attachment metadata for a user message so history restoration can
  /// re-link the attachments to their turn.
  bool saveAttachmentMetadata({
    required String threadId,
    required int userMsgIndex,
    required List<ChatAttachment> attachments,
  }) {
    return _engine.saveAttachmentMetadata(
      threadId: threadId,
      userMsgIndex: userMsgIndex,
      attachments: attachments,
    );
  }
}
