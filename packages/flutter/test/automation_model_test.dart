import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/models/automation.dart';

void main() {
  test('AutomationJob encodes v1 one-shot system event shape', () {
    final job = AutomationJob(
      name: 'Morning review',
      accountId: 'user-a',
      agentId: 'napaxi',
      trigger: const AutomationTrigger.oneShotAt(atMs: 1800000000000),
      payload: const AutomationPayload.systemEvent(text: 'Review plan.'),
    );

    final json = job.toJson();

    expect(json['trigger'], {'kind': 'oneShotAt', 'atMs': 1800000000000});
    expect(json['payload'], {
      'kind': 'systemEvent',
      'text': 'Review plan.',
      'wakeMode': 'next_foreground_or_host_wake',
    });
    expect(json['policy']['allowHighRiskTools'], false);
  });

  test('AutomationTrigger encodes local time schedule shape', () {
    const trigger = AutomationTrigger.localTime(
      hour: 9,
      minute: 30,
      timezone: 'Asia/Shanghai',
      daysOfWeek: [1, 3, 5],
    );

    expect(trigger.toJson(), {
      'kind': 'localTime',
      'timezone': 'Asia/Shanghai',
      'hour': 9,
      'minute': 30,
      'daysOfWeek': [1, 3, 5],
    });
  });

  test('AutomationPayload agent turn can target an existing session', () {
    const payload = AutomationPayload.agentTurn(
      message: 'Write the daily report.',
      sessionKeyJson:
          '{"channel_type":"app","account_id":"default","thread_id":"t1"}',
      sessionMode: 'main',
      maxIterations: 6,
    );

    expect(payload.toJson(), {
      'kind': 'agentTurn',
      'sessionKey':
          '{"channel_type":"app","account_id":"default","thread_id":"t1"}',
      'message': 'Write the daily report.',
      'sessionMode': 'main',
      'maxIterations': 6,
    });
  });

  test('AutomationRun decodes core camelCase and legacy snake_case shapes', () {
    final camel = AutomationRun.fromJson({
      'runId': 'run-1',
      'jobId': 'job-1',
      'status': 'succeeded',
      'triggerSource': 'manual',
      'startedAt': 1,
      'completedAt': 2,
      'durationMs': 1,
      'sessionKey': '{"thread_id":"t"}',
      'toolCallCount': 3,
      'deliveryStatus': 'not_requested',
    });
    final snake = AutomationRun.fromJson({
      'run_id': 'run-2',
      'job_id': 'job-2',
      'status': 'failed',
      'trigger_source': 'due',
      'started_at': 4,
      'delivery_status': 'unknown',
    });

    expect(camel.runId, 'run-1');
    expect(camel.toolCallCount, 3);
    expect(snake.jobId, 'job-2');
    expect(snake.triggerSource, 'due');
  });

  test('decodeAutomationJobs parses list payload', () {
    final jobs = decodeAutomationJobs(
      jsonEncode([
        {
          'id': 'job-1',
          'name': 'Interval',
          'trigger': {'kind': 'interval', 'everyMs': 60000},
          'payload': {'kind': 'agentTurn', 'message': 'Summarize.'},
          'state': {'nextRunAtMs': 10},
        },
      ]),
    );

    expect(jobs, hasLength(1));
    expect(jobs.single.trigger.kind, 'interval');
    expect(jobs.single.payload.sessionMode, 'isolated');
    expect(jobs.single.state.nextRunAtMs, 10);
  });
}
