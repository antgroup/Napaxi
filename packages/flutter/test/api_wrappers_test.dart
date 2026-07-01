import 'package:napaxi_flutter/api/session_api.dart';
import 'package:napaxi_flutter/engine.dart';
import 'package:napaxi_flutter/models/session.dart';
import 'package:test/test.dart';

// Pins that SessionApi's stateless CRUD wrappers are faithful pass-throughs:
// each forwards its arguments verbatim to the matching NapaxiEngine flat method
// and returns that method's result unchanged. A _FakeEngine records each call
// via noSuchMethod and returns a canned value, so no real FFI/dylib is needed.
//
// Facades whose logic was inverted (Workspace/Group/Agent/Skill/Evolution) or
// moved into EngineCore (Chat/Tool/Background + run-coupled Session methods) no
// longer delegate up into the engine and so have no pass-through test here; see
// engine_core_session_run_test.dart and the *_model_test.dart files.

/// Records every engine call (method symbol + positional/named args) and
/// returns a canned value registered for that method name. Implementing
/// NapaxiEngine via noSuchMethod avoids stubbing its full ~80-method surface.
class _FakeEngine implements NapaxiEngine {
  final List<Invocation> calls = [];
  final Map<Symbol, Object?> returns = {};

  void stub(String method, Object? value) => returns[Symbol(method)] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    return returns[invocation.memberName];
  }

  Invocation callTo(String method) =>
      calls.firstWhere((c) => c.memberName == Symbol(method));
}

void main() {
  late _FakeEngine engine;

  setUp(() => engine = _FakeEngine());

  // SessionApi stateless CRUD still forwards to the engine's flat bridge
  // methods, so the pass-through assertions remain valid. (The run-coupled
  // SessionApi methods — cancel / answerHumanRequest / injectMessage /
  // retractInjectedMessage — now route through EngineCore's session-run state
  // machine, covered behaviorally by engine_core_session_run_test.dart, so they
  // are no longer faked here.)
  group('SessionApi CRUD forwards to engine', () {
    final core = EngineCore.forTest();

    test('create passes named args and returns engine result', () async {
      const key =
          SessionKey(channelType: 'app', accountId: 'acct', threadId: 'thr');
      engine.stub('createSession', Future.value(key));

      final result = await SessionApi(engine, core).create(
        agentId: 'agent-x',
        channelType: 'web',
        accountId: 'acct',
        threadId: 'thr',
      );

      expect(result, same(key));
      final call = engine.callTo('createSession');
      expect(call.namedArguments[#agentId], 'agent-x');
      expect(call.namedArguments[#channelType], 'web');
      expect(call.namedArguments[#accountId], 'acct');
      expect(call.namedArguments[#threadId], 'thr');
    });

    test('delete forwards the session key positionally', () async {
      const key =
          SessionKey(channelType: 'app', accountId: 'a', threadId: 't');
      engine.stub('deleteSession', Future.value(true));

      final ok = await SessionApi(engine, core).delete(key);

      expect(ok, isTrue);
      expect(engine.callTo('deleteSession').positionalArguments, [key]);
    });

    test('saveAttachmentMetadata forwards thread, index and attachments', () {
      engine.stub('saveAttachmentMetadata', true);

      final ok = SessionApi(engine, core).saveAttachmentMetadata(
        threadId: 'thr',
        userMsgIndex: 2,
        attachments: const [],
      );

      expect(ok, isTrue);
      final call = engine.callTo('saveAttachmentMetadata');
      expect(call.namedArguments[#threadId], 'thr');
      expect(call.namedArguments[#userMsgIndex], 2);
      expect(call.namedArguments[#attachments], const <ChatAttachment>[]);
    });
  });

  // ChatApi, ToolApi, BackgroundApi, and the run-coupled SessionApi methods were
  // repointed to EngineCore (P3b): they no longer delegate up into NapaxiEngine,
  // so the old facade->engine pass-through groups were removed. Their logic
  // lives in EngineCore and is covered by engine_core_session_run_test.dart
  // (session-run state machine) plus integration; the clean facades
  // (Workspace/Group/Agent/Skill/Evolution) similarly have no pass-through tests
  // — their decode logic is covered by the *_model_test.dart files.
}
