import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/napaxi_flutter.dart';

/// `ChatEvent.fromMap` is the Dart side of the streaming FFI contract: the
/// Rust bridge emits a JSON object per event over the C ABI / JNI callback,
/// and this decoder must keep parsing the exact `type` discriminants and field
/// names the runtime produces. These tests pin that contract so a rename on
/// either side fails loudly here rather than silently dropping events at
/// runtime on a user's device.
void main() {
  group('ChatEvent.fromJsonString', () {
    test('decodes a run_started event from a raw JSON string', () {
      final event = ChatEvent.fromJsonString(
        jsonEncode({
          'type': 'run_started',
          'run_id': 'r1',
          'session_key': 's1',
          'agent_id': 'a1',
        }),
      );
      expect(event, isA<RunStartedEvent>());
      final started = event as RunStartedEvent;
      expect(started.runId, 'r1');
      expect(started.sessionKey, 's1');
      expect(started.agentId, 'a1');
    });
  });

  group('ChatEvent.fromMap discriminants', () {
    test('error event matches the Rust bridge error envelope shape', () {
      // Mirrors the Rust `stream_error_event_matches_dart_chat_event_contract`
      // test: `{ "type": "error", "message": ... }`.
      final event = ChatEvent.fromMap({
        'type': 'error',
        'message': 'engine handle 0 is not live',
      });
      expect(event, isA<ErrorEvent>());
      expect((event as ErrorEvent).message, 'engine handle 0 is not live');
    });

    test('tool_result carries the is_error flag through', () {
      final event = ChatEvent.fromMap({
        'type': 'tool_result',
        'call_id': 'c1',
        'name': 'shell',
        'output': 'done',
        'is_error': true,
      });
      expect(event, isA<ToolResultEvent>());
      final result = event as ToolResultEvent;
      expect(result.callId, 'c1');
      expect(result.name, 'shell');
      expect(result.output, 'done');
      expect(result.isError, isTrue);
    });

    test('run_completed defaults missing tool_call_count to zero', () {
      final event = ChatEvent.fromMap({
        'type': 'run_completed',
        'run_id': 'r1',
        'status': 'ok',
        'evidence_kind': 'none',
        'verification': 'skipped',
        // tool_call_count intentionally omitted
      });
      expect(event, isA<RunCompletedEvent>());
      expect((event as RunCompletedEvent).toolCallCount, 0);
    });

    test('asking_human tolerates a missing options list', () {
      final event = ChatEvent.fromMap({
        'type': 'asking_human',
        'question': 'proceed?',
        'request_id': 'req1',
      });
      expect(event, isA<AskingHumanEvent>());
      final asking = event as AskingHumanEvent;
      expect(asking.options, isEmpty);
      expect(asking.context, isNull);
    });

    test('context_compacting coerces an integer usage_percent to double', () {
      // The runtime may serialize a whole-number percent as an int; the
      // `as num).toDouble()` path must accept it without a cast error.
      final event = ChatEvent.fromMap({
        'type': 'context_compacting',
        'usage_percent': 80,
        'strategy': 'summarize',
      });
      expect(event, isA<ContextCompactingEvent>());
      expect((event as ContextCompactingEvent).usagePercent, 80.0);
    });

    test('interrupted decodes as a const singleton-style event', () {
      expect(ChatEvent.fromMap({'type': 'interrupted'}), isA<InterruptedEvent>());
    });

    test('stream_reset carries the reconnect reason through', () {
      final event = ChatEvent.fromMap({
        'type': 'stream_reset',
        'reason': 'connection reset by peer',
      });
      expect(event, isA<StreamResetEvent>());
      expect((event as StreamResetEvent).reason, 'connection reset by peer');
    });

    test('stream_reset tolerates a missing reason', () {
      final event = ChatEvent.fromMap({'type': 'stream_reset'});
      expect(event, isA<StreamResetEvent>());
      expect((event as StreamResetEvent).reason, '');
    });

    test('unknown event type degrades to an ErrorEvent instead of throwing', () {
      final event = ChatEvent.fromMap({'type': 'totally_new_event'});
      expect(event, isA<ErrorEvent>());
      expect((event as ErrorEvent).message, contains('totally_new_event'));
    });
  });
}
