import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi/main.dart';
import 'package:napaxi_flutter/napaxi_flutter.dart' as sdk;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a terminal chat run cannot be reopened by a late async update',
    () async {
      final events = StreamController<sdk.ChatEvent>();
      final subscription = events.stream.listen((_) {});
      final startedAt = DateTime(2026, 8, 4, 19, 51);
      final running = ChatSessionRunState(
        sessionKey: const sdk.SessionKey(
          channelType: 'app',
          accountId: 'test',
          threadId: 'session-1',
        ),
        agentId: sdk.NapaxiEngine.defaultAgentId,
        assistantMessageId: 'assistant-1',
        subscription: subscription,
        startedAt: startedAt,
        updatedAt: startedAt,
        pendingHumanRequestId: 'human-1',
        pendingHumanMessageId: 'assistant-1',
      );
      final completed = running.copyWith(
        status: sdk.SessionRunStatus.completed,
        activity: 'Completed',
        updatedAt: startedAt.add(const Duration(seconds: 2)),
        clearPendingHumanRequest: true,
        clearPendingHumanMessage: true,
      );

      final lateHumanAnswer = completed.copyWith(
        status: sdk.SessionRunStatus.running,
        activity: 'Continuing',
        updatedAt: startedAt.add(const Duration(seconds: 3)),
      );
      final reconciled = lateHumanAnswer.preserveTerminalFrom(completed);

      expect(reconciled.status, sdk.SessionRunStatus.completed);
      expect(reconciled.activity, 'Completed');
      expect(reconciled.isRunning, isFalse);
      expect(reconciled.pendingHumanRequestId, isNull);

      await subscription.cancel();
      await events.close();
    },
  );

  test('a cancelling chat run only advances to cancelled', () async {
    final events = StreamController<sdk.ChatEvent>();
    final subscription = events.stream.listen((_) {});
    final startedAt = DateTime(2026, 8, 6, 10, 6);
    final running = ChatSessionRunState(
      sessionKey: const sdk.SessionKey(
        channelType: 'app',
        accountId: 'test',
        threadId: 'session-1',
      ),
      agentId: sdk.NapaxiEngine.defaultAgentId,
      assistantMessageId: 'assistant-1',
      subscription: subscription,
      startedAt: startedAt,
      updatedAt: startedAt,
    );
    final cancelling = running.copyWith(
      status: sdk.SessionRunStatus.cancelling,
      activity: 'Stopping',
    );

    final lateRunning = running
        .copyWith(activity: 'Reconnecting')
        .preserveTerminalFrom(cancelling);
    final lateCompleted = running
        .copyWith(status: sdk.SessionRunStatus.completed, activity: 'Completed')
        .preserveTerminalFrom(cancelling);
    final cancelled = running
        .copyWith(status: sdk.SessionRunStatus.cancelled, activity: 'Stopped')
        .preserveTerminalFrom(cancelling);

    expect(lateRunning.status, sdk.SessionRunStatus.cancelling);
    expect(lateRunning.activity, 'Stopping');
    expect(lateCompleted.status, sdk.SessionRunStatus.cancelling);
    expect(cancelled.status, sdk.SessionRunStatus.cancelled);

    await subscription.cancel();
    await events.close();
  });
}
