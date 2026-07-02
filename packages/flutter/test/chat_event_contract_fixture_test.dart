import 'package:napaxi_flutter/models/chat_event.dart';
import 'package:test/test.dart';

import 'support/contract_fixtures.dart';

// Cross-adapter wire contract for the highest-frequency ChatEvent variants.
// The fixtures under packages/api_contract/fixtures/chat_event/ are the single
// source of truth for these wire shapes; the Android (ChatEventContractTest.kt)
// and iOS (ChatEventContractTests.swift) tests mirror the same field values.
// If a fixture changes, all three codecs must change together.
//
// contract-fixture: fixtures/chat_event/tool_call.json
// contract-fixture: fixtures/chat_event/tool_result.json
// contract-fixture: fixtures/chat_event/response_delta.json
// contract-fixture: fixtures/chat_event/run_started.json
void main() {
  group('chat event API contract fixtures', () {
    test('decode tool_call with canonical snake_case wire fields', () {
      final payload = contractFixtureObject('chat_event/tool_call.json');
      final event = ChatEvent.fromMap(payload);

      expect(event, isA<ToolCallEvent>());
      final toolCall = event as ToolCallEvent;
      expect(toolCall.callId, 'call-fixture-001');
      expect(toolCall.name, 'home_light_set');
      expect(toolCall.arguments, '{"room":"kitchen","on":true}');
    });

    test('decode tool_result with output and is_error', () {
      final payload = contractFixtureObject('chat_event/tool_result.json');
      final event = ChatEvent.fromMap(payload);

      expect(event, isA<ToolResultEvent>());
      final result = event as ToolResultEvent;
      expect(result.callId, 'call-fixture-001');
      expect(result.name, 'home_light_set');
      expect(result.output, '{"ok":true}');
      expect(result.isError, isFalse);
    });

    test('decode response_delta', () {
      final payload = contractFixtureObject('chat_event/response_delta.json');
      final event = ChatEvent.fromMap(payload);

      expect(event, isA<ResponseDeltaEvent>());
      expect((event as ResponseDeltaEvent).content, 'Turning on the kitchen light.');
    });

    test('decode run_started with run_id/session_key/agent_id', () {
      final payload = contractFixtureObject('chat_event/run_started.json');
      final event = ChatEvent.fromMap(payload);

      expect(event, isA<RunStartedEvent>());
      final started = event as RunStartedEvent;
      expect(started.runId, 'run-fixture-001');
      expect(started.agentId, 'napaxi');
      expect(started.sessionKey, contains('thread-fixture-001'));
    });
  });
}
