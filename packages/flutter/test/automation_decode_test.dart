import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/models/automation.dart';

// Covers the pure decode boundary in models/automation.dart — the part that
// turns Rust wire JSON into typed models. The Rust side emits camelCase, but
// these decoders also accept the snake_case legacy shape; this is exactly where
// a wire-format drift would silently drop fields, so both formats plus the
// defaults and the defensive list/error-envelope helpers are exercised here.
void main() {
  group('AutomationTrigger.fromJson', () {
    test('accepts camelCase keys', () {
      final t = AutomationTrigger.fromJson({
        'kind': 'interval',
        'atMs': 1000,
        'everyMs': 5000,
        'anchorMs': 200,
        'eventType': 'boot',
        'timezone': 'UTC',
        'source': 'host',
      });
      expect(t.kind, 'interval');
      expect(t.atMs, 1000);
      expect(t.everyMs, 5000);
      expect(t.anchorMs, 200);
      expect(t.eventType, 'boot');
    });

    test('accepts snake_case legacy keys', () {
      final t = AutomationTrigger.fromJson({
        'kind': 'interval',
        'at_ms': 1000,
        'every_ms': 5000,
        'anchor_ms': 200,
        'event_type': 'boot',
      });
      expect(t.atMs, 1000);
      expect(t.everyMs, 5000);
      expect(t.anchorMs, 200);
      expect(t.eventType, 'boot');
    });

    test('kind defaults to manual when absent', () {
      expect(AutomationTrigger.fromJson({}).kind, 'manual');
    });
  });

  group('AutomationPayload.fromJson', () {
    test('defaults kind, wakeMode, and sessionMode', () {
      final p = AutomationPayload.fromJson({});
      expect(p.kind, 'systemEvent');
      expect(p.wakeMode, 'next_foreground_or_host_wake');
      expect(p.sessionMode, 'isolated');
    });

    test('reads snake_case session and model keys', () {
      final p = AutomationPayload.fromJson({
        'kind': 'agentTurn',
        'session_key': '{"thread_id":"t1"}',
        'session_mode': 'shared',
        'model_profile_id': 'fast',
        'max_iterations': 7,
        'message': 'go',
      });
      expect(p.sessionKeyJson, '{"thread_id":"t1"}');
      expect(p.sessionMode, 'shared');
      expect(p.modelProfileId, 'fast');
      expect(p.maxIterations, 7);
      expect(p.message, 'go');
    });
  });

  group('AutomationPolicy.fromJson', () {
    test('applies documented defaults when fields are absent', () {
      final policy = AutomationPolicy.fromJson({});
      expect(policy.requiresUserVisibleNotification, isTrue);
      expect(policy.allowHighRiskTools, isFalse);
      expect(policy.maxRunDurationMs, 600000);
      expect(policy.maxRetries, 2);
      expect(policy.retryBackoffMs, [30000, 300000]);
      expect(policy.deleteAfterSuccess, isNull);
    });

    test('reads snake_case keys', () {
      final policy = AutomationPolicy.fromJson({
        'requires_user_visible_notification': false,
        'allow_high_risk_tools': true,
        'max_run_duration_ms': 1000,
        'max_retries': 5,
        'delete_after_success': true,
      });
      expect(policy.requiresUserVisibleNotification, isFalse);
      expect(policy.allowHighRiskTools, isTrue);
      expect(policy.maxRunDurationMs, 1000);
      expect(policy.maxRetries, 5);
      expect(policy.deleteAfterSuccess, isTrue);
    });

    test('retryBackoffMs drops non-positive entries', () {
      final policy = AutomationPolicy.fromJson({
        'retryBackoffMs': [1000, 0, -5, 2000],
      });
      expect(policy.retryBackoffMs, [1000, 2000]);
    });
  });

  group('AutomationJobState.fromJson', () {
    test('reads snake_case keys and defaults consecutiveErrors', () {
      final state = AutomationJobState.fromJson({
        'next_run_at_ms': 100,
        'last_run_status': 'completed',
        'last_error': 'none',
        'running_run_id': 'r1',
        'last_wake_source': 'alarm',
      });
      expect(state.nextRunAtMs, 100);
      expect(state.lastRunStatus, 'completed');
      expect(state.lastError, 'none');
      expect(state.runningRunId, 'r1');
      expect(state.lastWakeSource, 'alarm');
      expect(state.consecutiveErrors, 0);
    });
  });

  group('_int coercion (via AutomationTrigger.atMs)', () {
    int? atMsFrom(Object? value) =>
        AutomationTrigger.fromJson({'atMs': value}).atMs;

    test('passes through int', () => expect(atMsFrom(42), 42));
    test('truncates num', () => expect(atMsFrom(42.9), 42));
    test('parses numeric string', () => expect(atMsFrom('42'), 42));
    test('non-numeric string is null', () => expect(atMsFrom('abc'), isNull));
    test('null stays null', () => expect(atMsFrom(null), isNull));
  });

  group('AutomationRun.fromJson', () {
    test('decodes camelCase shape', () {
      final run = AutomationRun.fromJson({
        'runId': 'r1',
        'jobId': 'j1',
        'status': 'completed',
        'triggerSource': 'manual',
        'startedAt': 100,
        'completedAt': 200,
        'toolCallCount': 3,
        'deliveryStatus': 'delivered',
      });
      expect(run.runId, 'r1');
      expect(run.jobId, 'j1');
      expect(run.startedAt, 100);
      expect(run.completedAt, 200);
      expect(run.toolCallCount, 3);
      expect(run.deliveryStatus, 'delivered');
    });

    test('deliveryStatus defaults to unknown, startedAt to 0', () {
      final run = AutomationRun.fromJson({
        'run_id': 'r1',
        'job_id': 'j1',
        'status': 'queued',
        'trigger_source': 'host',
      });
      expect(run.startedAt, 0);
      expect(run.toolCallCount, 0);
      expect(run.deliveryStatus, 'unknown');
    });
  });

  group('AutomationWake.fromJson', () {
    test('decodes nested trigger and defaults', () {
      final wake = AutomationWake.fromJson({
        'jobId': 'j1',
        'atMs': 500,
        'trigger': {'kind': 'schedule', 'atMs': 500},
      });
      expect(wake.jobId, 'j1');
      expect(wake.atMs, 500);
      expect(wake.trigger.kind, 'schedule');
    });

    test('missing trigger falls back to a manual trigger', () {
      final wake = AutomationWake.fromJson({'jobId': 'j1', 'atMs': 0});
      expect(wake.trigger.kind, 'manual');
    });
  });

  group('decodeJsonObjectOrNull', () {
    test('returns the map for a plain object', () {
      expect(decodeJsonObjectOrNull('{"a":1}'), {'a': 1});
    });

    test('returns null for an error envelope', () {
      expect(decodeJsonObjectOrNull('{"error":"boom"}'), isNull);
    });

    test('returns null for a non-object payload', () {
      expect(decodeJsonObjectOrNull('[1,2,3]'), isNull);
    });
  });

  group('decodeAutomationJobs / decodeAutomationRuns', () {
    test('non-list payloads decode to empty lists', () {
      expect(decodeAutomationJobs('{"error":"x"}'), isEmpty);
      expect(decodeAutomationRuns('null'), isEmpty);
    });

    test('decodeAutomationJobs filters non-map entries', () {
      final jobs = decodeAutomationJobs(jsonEncode([
        {
          'id': 'j1',
          'name': 'job one',
          'trigger': {'kind': 'manual'},
          'payload': {'kind': 'systemEvent', 'text': 'hi'},
          'policy': {},
          'state': {},
          'createdAt': 1,
          'updatedAt': 2,
        },
        'not-a-map',
        42,
      ]));
      expect(jobs, hasLength(1));
      expect(jobs.single.id, 'j1');
      expect(jobs.single.name, 'job one');
    });

    test('decodeAutomationRuns decodes a list payload', () {
      final runs = decodeAutomationRuns(jsonEncode([
        {
          'runId': 'r1',
          'jobId': 'j1',
          'status': 'completed',
          'triggerSource': 'manual',
          'startedAt': 1,
          'deliveryStatus': 'delivered',
        },
      ]));
      expect(runs, hasLength(1));
      expect(runs.single.runId, 'r1');
    });
  });
}
