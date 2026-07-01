import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/napaxi_flutter.dart';

/// The agent- and group-delegation events are the Dart side of the multi-agent
/// streaming contract: the Rust runtime emits one JSON object per event over
/// the FFI callback, and these `ChatEvent.fromMap` arms must keep decoding the
/// exact `type` discriminants and snake_case field names the runtime produces.
/// `chat_event_test.dart` covers the single-agent core events; this file pins
/// the delegation chain so a field rename on either side fails loudly here
/// rather than silently dropping a delegation event on a user's device.
void main() {
  group('agent delegation events', () {
    test('agent_delegation decodes from/to/message', () {
      final event = ChatEvent.fromMap({
        'type': 'agent_delegation',
        'from_agent': 'planner',
        'to_agent': 'coder',
        'message': 'implement the parser',
      });
      expect(event, isA<AgentDelegationEvent>());
      final e = event as AgentDelegationEvent;
      expect(e.fromAgent, 'planner');
      expect(e.toAgent, 'coder');
      expect(e.message, 'implement the parser');
    });

    test('agent_delegation_result carries the is_error flag', () {
      final event = ChatEvent.fromMap({
        'type': 'agent_delegation_result',
        'from_agent': 'coder',
        'to_agent': 'planner',
        'content': 'done',
        'is_error': false,
      });
      expect(event, isA<AgentDelegationResultEvent>());
      final e = event as AgentDelegationResultEvent;
      expect(e.fromAgent, 'coder');
      expect(e.toAgent, 'planner');
      expect(e.content, 'done');
      expect(e.isError, isFalse);
    });

    test('agent_tool_call attributes the call to its agent', () {
      final event = ChatEvent.fromMap({
        'type': 'agent_tool_call',
        'call_id': 'c1',
        'name': 'shell',
        'arguments': '{"cmd":"ls"}',
        'agent_id': 'coder',
      });
      expect(event, isA<AgentToolCallEvent>());
      final e = event as AgentToolCallEvent;
      expect(e.callId, 'c1');
      expect(e.name, 'shell');
      expect(e.arguments, '{"cmd":"ls"}');
      expect(e.agentId, 'coder');
    });

    test('agent_tool_result carries the is_error flag and agent id', () {
      final event = ChatEvent.fromMap({
        'type': 'agent_tool_result',
        'call_id': 'c1',
        'name': 'shell',
        'output': 'permission denied',
        'is_error': true,
        'agent_id': 'coder',
      });
      expect(event, isA<AgentToolResultEvent>());
      final e = event as AgentToolResultEvent;
      expect(e.isError, isTrue);
      expect(e.agentId, 'coder');
      expect(e.output, 'permission denied');
    });
  });

  group('group delegation events', () {
    test('group_delegation decodes group id and task', () {
      final event = ChatEvent.fromMap({
        'type': 'group_delegation',
        'group_id': 'g1',
        'from_agent': 'lead',
        'to_agent': 'helper',
        'task': 'summarize the thread',
      });
      expect(event, isA<GroupDelegationEvent>());
      final e = event as GroupDelegationEvent;
      expect(e.groupId, 'g1');
      expect(e.fromAgent, 'lead');
      expect(e.toAgent, 'helper');
      expect(e.task, 'summarize the thread');
    });

    test('group_delegation_result carries the is_error flag', () {
      final event = ChatEvent.fromMap({
        'type': 'group_delegation_result',
        'group_id': 'g1',
        'from_agent': 'helper',
        'to_agent': 'lead',
        'result': 'summary text',
        'is_error': false,
      });
      expect(event, isA<GroupDelegationResultEvent>());
      final e = event as GroupDelegationResultEvent;
      expect(e.groupId, 'g1');
      expect(e.result, 'summary text');
      expect(e.isError, isFalse);
    });
  });
}
