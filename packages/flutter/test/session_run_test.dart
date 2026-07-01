import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/models/session.dart';
import 'package:napaxi_flutter/models/session_run.dart';

void main() {
  test('session run info tracks active and terminal states', () {
    final now = DateTime.utc(2026);
    const key = SessionKey(
      channelType: 'app',
      accountId: 'user-a',
      threadId: 'thread-a',
    );
    final run = SessionRunInfo(
      key: key,
      agentId: 'napaxi',
      status: SessionRunStatus.running,
      activity: 'Starting',
      startedAt: now,
      updatedAt: now,
    );

    expect(run.id, 'napaxi:app:user-a:thread-a');
    expect(run.isTerminal, isFalse);

    final waiting = run.copyWith(
      status: SessionRunStatus.waitingForInput,
      activity: 'Waiting',
      humanRequestId: 'human-1',
    );

    expect(waiting.needsInput, isTrue);
    expect(waiting.humanRequestId, 'human-1');

    final completed = waiting.copyWith(
      status: SessionRunStatus.completed,
      activity: 'Done',
      clearHumanRequest: true,
    );

    expect(completed.isTerminal, isTrue);
    expect(completed.humanRequestId, isNull);
  });

  test('session run record decodes evidence and unverified status', () {
    final record = SessionRunRecord.fromJson({
      'runId': 'run-1',
      'status': 'unverified',
      'agentId': 'agent',
      'sessionKey': '{}',
      'threadId': 'thread',
      'startedAt': 100,
      'completedAt': 150,
      'durationMs': 50,
      'evidenceKind': 'tool_observed',
      'verification': 'unverified',
      'toolCallCount': 1,
      'evidence': [
        {
          'kind': 'tool_observed',
          'source': 'read_file',
          'effect': 'read',
          'isError': false,
          'digest': 'abc',
        }
      ],
    });

    expect(record.status, SessionRunRecordStatus.unverified);
    expect(record.evidenceKind, RunEvidenceKind.toolObserved);
    expect(record.verification, RunVerification.unverified);
    expect(record.evidence.single.effect, 'read');
  });
}
