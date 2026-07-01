import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/models/evolution.dart';

void main() {
  group('EvolutionRunStatus.fromString', () {
    test('maps known values', () {
      expect(EvolutionRunStatus.fromString('queued'), EvolutionRunStatus.queued);
      expect(
        EvolutionRunStatus.fromString('running'),
        EvolutionRunStatus.running,
      );
      expect(
        EvolutionRunStatus.fromString('completed'),
        EvolutionRunStatus.completed,
      );
      expect(EvolutionRunStatus.fromString('failed'), EvolutionRunStatus.failed);
    });

    test('falls back to unknown for unrecognized or empty values', () {
      expect(
        EvolutionRunStatus.fromString('something-else'),
        EvolutionRunStatus.unknown,
      );
      expect(EvolutionRunStatus.fromString(''), EvolutionRunStatus.unknown);
    });
  });

  group('EvolutionRun.fromMap', () {
    test('decodes a full map with snake_case keys', () {
      final run = EvolutionRun.fromMap({
        'id': 'run-1',
        'agent_id': 'agent.a',
        'thread_id': 'thread-1',
        'review_type': 'memory',
        'status': 'completed',
        'queued_at': '2026-06-03T00:00:00Z',
        'started_at': '2026-06-03T00:00:01Z',
        'completed_at': '2026-06-03T00:00:05Z',
        'suggestions_count': 3,
        'auto_applied_count': 1,
        'pending_count': 2,
      });

      expect(run.id, 'run-1');
      expect(run.agentId, 'agent.a');
      expect(run.threadId, 'thread-1');
      expect(run.reviewType, 'memory');
      expect(run.status, EvolutionRunStatus.completed);
      expect(run.queuedAt, DateTime.parse('2026-06-03T00:00:00Z'));
      expect(run.startedAt, DateTime.parse('2026-06-03T00:00:01Z'));
      expect(run.completedAt, DateTime.parse('2026-06-03T00:00:05Z'));
      expect(run.suggestionsCount, 3);
      expect(run.autoAppliedCount, 1);
      expect(run.pendingCount, 2);
    });

    test('defaults counts and leaves optional dates null when absent', () {
      final run = EvolutionRun.fromMap({
        'id': 'run-2',
        'agent_id': 'agent.a',
        'thread_id': 'thread-1',
        'review_type': 'skill',
        'status': 'queued',
        'queued_at': '2026-06-03T00:00:00Z',
      });

      expect(run.startedAt, isNull);
      expect(run.completedAt, isNull);
      expect(run.suggestionsCount, 0);
      expect(run.autoAppliedCount, 0);
      expect(run.pendingCount, 0);
      expect(run.error, isNull);
    });

    test('blank optional date strings parse to null', () {
      final run = EvolutionRun.fromMap({
        'id': 'run-3',
        'agent_id': 'agent.a',
        'thread_id': 'thread-1',
        'review_type': 'memory',
        'status': 'running',
        'queued_at': '2026-06-03T00:00:00Z',
        'started_at': '   ',
        'completed_at': '',
      });

      expect(run.startedAt, isNull);
      expect(run.completedAt, isNull);
    });

    test('isFinished only for completed or failed', () {
      EvolutionRun runWith(String status) => EvolutionRun.fromMap({
            'id': 'r',
            'agent_id': 'a',
            'thread_id': 't',
            'review_type': 'memory',
            'status': status,
            'queued_at': '2026-06-03T00:00:00Z',
          });

      expect(runWith('completed').isFinished, isTrue);
      expect(runWith('failed').isFinished, isTrue);
      expect(runWith('queued').isFinished, isFalse);
      expect(runWith('running').isFinished, isFalse);
    });
  });

  group('EvolutionDiagnostic.fromMap', () {
    test('decodes input_summary map and tool_calls list', () {
      final diag = EvolutionDiagnostic.fromMap({
        'id': 'diag-1',
        'created_at': '2026-06-03T00:00:00Z',
        'agent_id': 'agent.a',
        'thread_id': 'thread-1',
        'review_type': 'memory',
        'trigger_reason': 'after_turn',
        'input_summary': {'messages': 4},
        'tool_calls': ['memory_write', 'memory_read'],
        'suggestions_count': 2,
        'pending_count': 1,
        'auto_applied_count': 1,
        'apply_result': 'ok',
      });

      expect(diag.id, 'diag-1');
      expect(diag.triggerReason, 'after_turn');
      expect(diag.inputSummary, {'messages': 4});
      expect(diag.toolCalls, ['memory_write', 'memory_read']);
      expect(diag.applyResult, 'ok');
      expect(diag.failureReason, isNull);
    });

    test('applies empty defaults for collections and missing fields', () {
      final diag = EvolutionDiagnostic.fromMap({
        'created_at': '2026-06-03T00:00:00Z',
      });

      expect(diag.id, '');
      expect(diag.agentId, '');
      expect(diag.inputSummary, isEmpty);
      expect(diag.toolCalls, isEmpty);
      expect(diag.suggestionsCount, 0);
    });
  });

  group('SkillConsolidationReviewResult.fromMap', () {
    test('decodes actions, warnings, and pending id', () {
      final result = SkillConsolidationReviewResult.fromMap({
        'reviewed': true,
        'dry_run': false,
        'suggestions_count': 2,
        'pending_count': 1,
        'pending_id': 'pending-1',
        'actions': [
          {'kind': 'merge', 'skills': 2},
          'not-a-map',
        ],
        'warnings': ['overlap detected'],
      });

      expect(result.reviewed, isTrue);
      expect(result.dryRun, isFalse);
      expect(result.pendingId, 'pending-1');
      // Non-map entries are filtered out by whereType<Map>().
      expect(result.actions, [
        {'kind': 'merge', 'skills': 2},
      ]);
      expect(result.warnings, ['overlap detected']);
    });

    test('dryRun defaults to true and collections default empty', () {
      final result = SkillConsolidationReviewResult.fromMap({'reviewed': false});

      expect(result.dryRun, isTrue);
      expect(result.suggestionsCount, 0);
      expect(result.pendingId, isNull);
      expect(result.actions, isEmpty);
      expect(result.warnings, isEmpty);
      expect(result.error, isNull);
    });
  });
}
