import 'package:napaxi_flutter/models/automation.dart';
import 'package:napaxi_flutter/models/capability.dart';
import 'package:napaxi_flutter/models/session_run.dart';
import 'package:test/test.dart';

import 'support/contract_fixtures.dart';

// Cross-adapter wire contract for high-frequency runtime payloads. The fixtures
// under packages/api_contract/fixtures/{capability,session_run,automation}/ are
// the single source of truth; the Android (RuntimeContractTest.kt) and iOS
// (RuntimeContractTests.swift) tests mirror the same field values. If a fixture
// changes, all three codecs must change together.
//
// contract-fixture: fixtures/capability/capability_status.json
// contract-fixture: fixtures/session_run/session_run_record.json
// contract-fixture: fixtures/automation/automation_job.json
void main() {
  group('runtime payload API contract fixtures', () {
    test('decode capability status with nested definition', () {
      final payload = contractFixtureObject('capability/capability_status.json');
      final status = NapaxiCapabilityStatus.fromJson(payload);

      expect(status.registered, isTrue);
      expect(status.available, isTrue);
      expect(status.enabled, isTrue);
      expect(status.definition.id, 'napaxi.tool.custom_host');
      expect(status.definition.kind, 'tool');
      expect(status.definition.risk, 'medium');
      expect(status.definition.activation, 'host');
      expect(status.definition.defaultEnabled, isFalse);
    });

    test('decode session run record with camelCase wire fields', () {
      final payload =
          contractFixtureObject('session_run/session_run_record.json');
      final run = SessionRunRecord.fromJson(payload);

      expect(run.runId, 'run-fixture-001');
      expect(run.status, SessionRunRecordStatus.succeeded);
      expect(run.agentId, 'napaxi');
      expect(run.threadId, 'thread-fixture-001');
      expect(run.evidenceKind, RunEvidenceKind.toolObserved);
      expect(run.verification, RunVerification.verified);
      expect(run.toolCallCount, 1);
      expect(run.evidence, hasLength(1));
      expect(run.evidence.first.source, 'home_light_set');
      expect(run.evidence.first.isError, isFalse);
    });

    test('decode automation job with localTime trigger and agentTurn payload', () {
      final payload = contractFixtureObject('automation/automation_job.json');
      final job = AutomationJob.fromJson(payload);

      expect(job.id, 'job-fixture-001');
      expect(job.enabled, isTrue);
      expect(job.agentId, 'napaxi');
      expect(job.trigger.kind, 'localTime');
      expect(job.trigger.hour, 8);
      expect(job.trigger.minute, 30);
      expect(job.trigger.daysOfWeek, [1, 2, 3, 4, 5]);
      expect(job.payload.kind, 'agentTurn');
      expect(job.payload.message, 'Give me my morning briefing.');
      expect(job.policy.requiresUserVisibleNotification, isTrue);
      expect(job.policy.maxRetries, 2);
    });
  });
}
