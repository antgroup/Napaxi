import 'package:napaxi_flutter/models/workspace.dart';

import 'support/contract_fixtures.dart';
import 'package:test/test.dart';

// contract-fixture: fixtures/workspace/workspace_file.json
// contract-fixture: fixtures/workspace/list_files_result.json
// contract-fixture: fixtures/workspace/search_memory_result.json
// contract-fixture: fixtures/workspace/recall_sessions_result.json
// contract-fixture: fixtures/workspace/recall_index_stats.json
// contract-fixture: fixtures/workspace/journal_result.json
// contract-fixture: fixtures/workspace/result_envelope_success.json
// contract-fixture: fixtures/workspace/result_envelope_error.json

void main() {
  group('workspace API contract fixtures', () {
    test('decode WorkspaceFile and preserve unknown fields', () {
      final payload = contractFixtureObject('workspace/workspace_file.json');
      final file = WorkspaceFile.fromMap(payload);

      expect(file.path, 'MEMORY.md');
      expect(file.content, isNotEmpty);
      expect(file.updatedAt, isNotNull);
      _expectPreserved(file.raw, file.toMap(), 'adapter_unknown');
    });

    test('decode list_files entries with camelCase and snake_case aliases', () {
      final payload = contractFixtureObject('workspace/list_files_result.json');
      final entries = contractObjectList(
        payload['entries'],
      ).map(WorkspaceEntry.fromMap).toList();

      expect(entries, hasLength(2));
      expect(entries.first.path, 'MEMORY.md');
      expect(entries.first.isDirectory, isFalse);
      expect(entries.first.preview, isNotEmpty);
      expect(entries.first.updatedAt, isNotNull);
      expect(entries.last.path, 'daily');
      expect(entries.last.isDirectory, isTrue);
      expect(entries.last.updatedAt, isNotNull);
      _expectPreserved(
        entries.first.raw,
        entries.first.toMap(),
        'adapter_unknown',
      );
      _expectPreserved(
        entries.last.raw,
        entries.last.toMap(),
        'adapter_unknown',
      );
    });

    test('decode search_memory results and preserve aliases', () {
      final payload = contractFixtureObject(
        'workspace/search_memory_result.json',
      );
      final results = contractObjectList(
        payload['results'],
      ).map(MemorySearchResult.fromMap).toList();

      expect(results, hasLength(1));
      final result = results.single;
      expect(result.source, 'memory');
      expect(result.path, 'MEMORY.md');
      expect(result.score, 0.92);
      expect(result.isHybridMatch, isTrue);
      expect(result.threadId, 'thread-123');
      expect(result.turnId, 'turn-456');
      expect(result.createdAt, isNotNull);
      _expectPreserved(result.raw, result.toMap(), 'adapter_unknown');
    });

    test('decode recall_sessions with nested snippets', () {
      final payload = contractFixtureObject(
        'workspace/recall_sessions_result.json',
      );
      final sessions = contractObjectList(
        payload['sessions'],
      ).map(MemoryRecallSession.fromMap).toList();

      expect(sessions, hasLength(1));
      final session = sessions.single;
      expect(session.threadId, 'thread-123');
      expect(session.title, 'SDK adapter planning');
      expect(session.snippets, hasLength(1));
      expect(session.sourceDocIds, ['daily/2026-06-04.md']);
      expect(session.systemNote, isNotEmpty);
      expect(session.startedAt, isNotNull);
      expect(session.lastActiveAt, isNotNull);
      _expectPreserved(session.raw, session.toMap(), 'adapter_unknown');

      final snippet = session.snippets.single;
      expect(snippet.source, 'journal');
      expect(snippet.turnId, 'turn-456');
      expect(snippet.createdAt, isNotNull);
      _expectPreserved(snippet.raw, snippet.toMap(), 'adapter_unknown');
      expect(
        (session.toMap()['snippets'] as List).single,
        containsPair('adapter_unknown', 'preserve-snippet'),
      );
    });

    test('decode recall index stats', () {
      final payload = contractFixtureObject(
        'workspace/recall_index_stats.json',
      );
      final stats = RecallIndexStats.fromMap(payload);

      expect(stats.status, 'ready');
      expect(stats.dbPath, '/workspace/.napaxi/recall.db');
      expect(stats.schemaVersion, 1);
      expect(stats.indexedDocs, 12);
      expect(stats.memoryDocs, 3);
      expect(stats.journalDocs, 8);
      expect(stats.legacyDailyDocs, 1);
      expect(stats.cachedSummaries, 2);
      expect(stats.lastRebuildAt, isNotNull);
      _expectPreserved(stats.raw, stats.toMap(), 'adapter_unknown');
    });

    test('decode journal day and turn composite fixture', () {
      final payload = contractFixtureObject('workspace/journal_result.json');
      final days = contractObjectList(
        payload['days'],
      ).map(JournalDay.fromMap).toList();
      final turns = contractObjectList(
        payload['turns'],
      ).map(JournalTurnRecord.fromMap).toList();

      expect(days, hasLength(1));
      final day = days.single;
      expect(day.date, '2026-06-04');
      expect(day.turnCount, 4);
      expect(day.updatedAt, isNotNull);
      expect(day.legacy, isFalse);
      _expectPreserved(day.raw, day.toMap(), 'adapter_unknown');

      expect(turns, hasLength(1));
      final turn = turns.single;
      expect(turn.turnId, 'turn-456');
      expect(turn.agentId, 'napaxi');
      expect(turn.threadId, 'thread-123');
      expect(turn.kind, 'turn');
      expect(turn.createdAt, isNotNull);
      _expectPreserved(turn.raw, turn.toMap(), 'adapter_unknown');
    });

    test('decode standard result envelopes', () {
      final success = contractFixtureObject(
        'workspace/result_envelope_success.json',
      );
      expect(success['ok'], isTrue);
      expect(success['data'], isA<Map<String, dynamic>>());

      final error = contractFixtureObject(
        'workspace/result_envelope_error.json',
      );
      expect(error['ok'], isFalse);
      expect(error['error'], isA<Map<String, dynamic>>());
      expect((error['error'] as Map<String, dynamic>)['code'], isNotEmpty);
      expect((error['error'] as Map<String, dynamic>)['message'], isNotEmpty);
    });
  });
}

void _expectPreserved(
  Map<String, dynamic> raw,
  Map<String, dynamic> encoded,
  String key,
) {
  expect(raw, contains(key));
  expect(encoded, containsPair(key, raw[key]));
}
