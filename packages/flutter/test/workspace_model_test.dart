import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/napaxi_flutter.dart';

void main() {
  test('parses memory search result payloads', () {
    final result = MemorySearchResult.fromMap({
      'source': 'journal',
      'path': 'napaxi/journal/turns/2026-05-20.jsonl#turn-1',
      'content': 'bounded snippet',
      'score': 2,
      'is_hybrid_match': false,
      'updated_at': '2026-05-20T05:00:00Z',
    });

    expect(result.source, 'journal');
    expect(result.score, 2);
    expect(result.isHybridMatch, isFalse);
    expect(result.updatedAt, isNotNull);
  });

  test('parses journal day and turn record payloads', () {
    final day = JournalDay.fromMap({
      'date': '2026-05-20',
      'path': 'napaxi/journal/turns/2026-05-20.jsonl',
      'turn_count': 3,
      'updated_at': '2026-05-20T05:00:00Z',
      'legacy': true,
    });
    final record = JournalTurnRecord.fromMap({
      'turn_id': 'turn-1',
      'created_at': '2026-05-20T05:00:00Z',
      'agent_id': 'default',
      'thread_id': 'thread-1',
      'user': 'hi',
      'assistant': 'hello',
      'kind': 'turn',
    });

    expect(day.turnCount, 3);
    expect(day.legacy, isTrue);
    expect(record.turnId, 'turn-1');
    expect(record.threadId, 'thread-1');
    expect(record.createdAt, isNotNull);
  });
}
