import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/napaxi_flutter.dart';

/// Action-proposal events are the App-to-Agent handoff contract: when an agent
/// proposes a side-effecting action, the runtime streams this family of events
/// so the host UI can drive the approval/handoff flow. A renamed field here
/// would silently break the host's ability to surface a proposal, so these
/// tests pin the `type` discriminants and field names to the Rust wire shape.
void main() {
  test('action_proposal_created decodes the full proposal envelope', () {
    final event = ChatEvent.fromMap({
      'type': 'action_proposal_created',
      'request_id': 'req-1',
      'provider_id': 'provider.bank',
      'agent_id': 'coder',
      'action_id': 'transfer',
      'tool_name': 'bank.transfer',
      'risk': 'high',
      'expires_at': '2026-06-02T12:00:00Z',
    });
    expect(event, isA<ActionProposalCreatedEvent>());
    final e = event as ActionProposalCreatedEvent;
    expect(e.requestId, 'req-1');
    expect(e.providerId, 'provider.bank');
    expect(e.agentId, 'coder');
    expect(e.actionId, 'transfer');
    expect(e.toolName, 'bank.transfer');
    expect(e.risk, 'high');
    expect(e.expiresAt, '2026-06-02T12:00:00Z');
  });

  test('action_handoff_started decodes the handoff mode', () {
    final event = ChatEvent.fromMap({
      'type': 'action_handoff_started',
      'request_id': 'req-1',
      'mode': 'deep_link',
    });
    expect(event, isA<ActionHandoffStartedEvent>());
    final e = event as ActionHandoffStartedEvent;
    expect(e.requestId, 'req-1');
    expect(e.mode, 'deep_link');
  });

  test('action_result_received keeps an optional provider trace id', () {
    final withTrace = ChatEvent.fromMap({
      'type': 'action_result_received',
      'request_id': 'req-1',
      'status': 'approved',
      'provider_trace_id': 'trace-9',
    }) as ActionResultReceivedEvent;
    expect(withTrace.status, 'approved');
    expect(withTrace.providerTraceId, 'trace-9');

    final withoutTrace = ChatEvent.fromMap({
      'type': 'action_result_received',
      'request_id': 'req-1',
      'status': 'approved',
    }) as ActionResultReceivedEvent;
    expect(withoutTrace.providerTraceId, isNull);
  });

  test('action_failed surfaces the failure message', () {
    final event = ChatEvent.fromMap({
      'type': 'action_failed',
      'request_id': 'req-1',
      'message': 'provider rejected the action',
    });
    expect(event, isA<ActionFailedEvent>());
    expect((event as ActionFailedEvent).message, 'provider rejected the action');
  });

  test('unknown event type degrades to an ErrorEvent rather than throwing', () {
    final event = ChatEvent.fromMap({'type': 'action_from_the_future'});
    expect(event, isA<ErrorEvent>());
    expect((event as ErrorEvent).message, contains('action_from_the_future'));
  });
}
