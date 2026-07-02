import 'dart:async';

import 'package:napaxi_flutter/engine.dart';
import 'package:napaxi_flutter/background/background_controller.dart';
import 'package:napaxi_flutter/models/background.dart';
import 'package:napaxi_flutter/models/chat_event.dart';
import 'package:napaxi_flutter/models/session.dart';
import 'package:test/test.dart';

// Behavioral safety net for the session-run state machine that P3a moved from
// NapaxiEngine into EngineCore. This is the FIRST test coverage of this logic on
// any platform: it drives `_wrapWithBackground` (via the visibleForTesting
// `wrapWithBackgroundForTest` seam) with canned ChatEvent streams and a fake
// background controller, asserting the run-status transitions, the
// sessionRunUpdates emissions, the activeSessionRuns snapshot lifecycle, and the
// critical start-before-first-event ordering invariant. No FFI / native lib.
void main() {
  SessionRunInfo runningRun() {
    final now = DateTime.utc(2026);
    return SessionRunInfo(
      key: const SessionKey(
          channelType: 'app', accountId: 'acct', threadId: 'thr'),
      agentId: 'napaxi',
      status: SessionRunStatus.running,
      activity: 'Working',
      startedAt: now,
      updatedAt: now,
    );
  }

  Future<List<SessionRunInfo>> drain(EngineCore core, Stream<ChatEvent> raw,
      {SessionRunInfo? runInfo}) async {
    final updates = <SessionRunInfo>[];
    final sub = core.sessionRunUpdates.listen(updates.add);
    await core
        .wrapWithBackgroundForTest(raw, runInfo: runInfo)
        .toList()
        .catchError((_) => <ChatEvent>[]);
    await sub.cancel();
    return updates;
  }

  test('normal stream: running -> completed, active then empty', () async {
    final bg = _FakeBackgroundController();
    final core = EngineCore.forTest(backgroundController: bg);
    final run = runningRun();

    final updates = await drain(
      core,
      Stream<ChatEvent>.fromIterable(const [ResponseEvent(content: 'hi')]),
      runInfo: run,
    );

    // First emission is the seeded running run; last is the terminal completed.
    expect(updates.first.status, SessionRunStatus.running);
    expect(updates.last.status, SessionRunStatus.completed);
    // The run is gone from the active snapshot once terminal.
    expect(core.activeSessionRuns, isEmpty);
  });

  test('error stream: running -> failed', () async {
    final bg = _FakeBackgroundController();
    final core = EngineCore.forTest(backgroundController: bg);

    final controller = StreamController<ChatEvent>();
    final updatesFuture = drain(core, controller.stream, runInfo: runningRun());
    controller.addError(StateError('boom'));
    await controller.close();
    final updates = await updatesFuture;

    expect(updates.any((u) => u.status == SessionRunStatus.failed), isTrue);
    expect(updates.last.status, SessionRunStatus.failed);
    expect(core.activeSessionRuns, isEmpty);
  });

  test('asking-human event drives waitingForInput then completion', () async {
    final bg = _FakeBackgroundController();
    final core = EngineCore.forTest(backgroundController: bg);

    final updates = await drain(
      core,
      Stream<ChatEvent>.fromIterable(const [
        AskingHumanEvent(question: 'ok?', requestId: 'req-1'),
        ResponseEvent(content: 'done'),
      ]),
      runInfo: runningRun(),
    );

    expect(
      updates.any((u) => u.status == SessionRunStatus.waitingForInput),
      isTrue,
    );
    expect(updates.last.status, SessionRunStatus.completed);
  });

  test('foreground service starts BEFORE the first event (ordering invariant)',
      () async {
    final bg = _FakeBackgroundController();
    final core = EngineCore.forTest(backgroundController: bg);

    final order = <String>[];
    bg.onStart = () => order.add('start');

    final raw = Stream<ChatEvent>.fromIterable(const [ResponseEvent(content: 'x')])
        .map((e) {
      order.add('event');
      return e;
    });

    await core
        .wrapWithBackgroundForTest(raw, runInfo: runningRun())
        .toList();

    expect(order.isNotEmpty, isTrue);
    expect(order.first, 'start',
        reason: 'service must start before any stream event is processed');
  });

  test('no background controller: state machine still tracks runs', () async {
    final core = EngineCore.forTest();
    final updates = await drain(
      core,
      Stream<ChatEvent>.fromIterable(const [ResponseEvent(content: 'hi')]),
      runInfo: runningRun(),
    );
    expect(updates.first.status, SessionRunStatus.running);
    expect(updates.last.status, SessionRunStatus.completed);
  });
}

/// Records start/stop without touching the platform MethodChannel, and reports
/// running so the notification-update path is exercised.
class _FakeBackgroundController extends NapaxiBackgroundController {
  _FakeBackgroundController()
      : super(const BackgroundConfig(enabled: true));

  bool _running = false;
  void Function()? onStart;

  @override
  bool get isRunning => _running;

  @override
  BackgroundConfig? get currentConfig => const BackgroundConfig(enabled: true);

  @override
  Future<void> start(BackgroundConfig config) async {
    _running = true;
    onStart?.call();
  }

  @override
  Future<void> stop() async {
    _running = false;
  }

  @override
  Future<void> updateNotification({String? message, int? progress}) async {}

  @override
  Future<void> showCompletionNotification({
    String title = 'Napaxi Agent',
    String message = 'Task completed',
  }) async {}

  @override
  Future<void> showErrorNotification({
    String title = 'Napaxi Agent',
    String message = 'An error occurred',
  }) async {}
}
