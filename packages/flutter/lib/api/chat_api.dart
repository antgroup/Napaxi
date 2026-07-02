import '../engine.dart';
import '../models/chat_event.dart';
import '../models/session.dart';

/// Chat API: send messages to the default or a specific session and stream
/// back [ChatEvent]s.
class ChatApi {
  ChatApi(this._core);

  final EngineCore _core;

  Stream<ChatEvent> send(
    String message, {
    List<McAttachment>? attachments,
    int maxIterations = 0,
  }) {
    return _core.send(
      message,
      attachments: attachments,
      maxIterations: maxIterations,
    );
  }

  Stream<ChatEvent> sendToSession(
    SessionKey session,
    String message, {
    List<McAttachment>? attachments,
    int maxIterations = 0,
    String agentId = NapaxiEngine.defaultAgentId,
  }) {
    return _core.sendToSession(
      session,
      message,
      attachments: attachments,
      maxIterations: maxIterations,
      agentId: agentId,
    );
  }
}
