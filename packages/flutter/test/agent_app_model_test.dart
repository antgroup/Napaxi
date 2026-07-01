import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/models/chat_event.dart';
import 'package:napaxi_flutter/models/agent_app.dart';

void main() {
  test('Agent App package json round trips', () {
    const package = AgentAppPackage(
      providerId: 'provider',
      agentId: 'provider.agent',
      displayName: 'Provider Agent',
      description: 'Provider-backed agent',
      actions: [
        AgentAppActionManifest(
          actionId: 'provider.order.create',
          toolName: 'app_action_order_create',
          description: 'Create order proposal.',
          parameters: {
            'type': 'object',
            'properties': {
              'amount': {'type': 'number'}
            },
            'required': ['amount']
          },
          executionModes: ['app_handoff'],
        ),
      ],
      handoff: {'mode': 'app_handoff'},
      result: {'mode': 'callback'},
    );

    final decoded = AgentAppPackage.fromMap(
      jsonDecode(package.toJsonString()) as Map,
    );

    expect(decoded.providerId, 'provider');
    expect(decoded.actions.single.toolName, 'app_action_order_create');
    expect(decoded.actions.single.parameters['properties'], isA<Map>());
    expect(decoded.handoff['mode'], 'app_handoff');
  });

  test('agent app action request decodes proposal and manifest', () {
    final request = AgentAppActionRequest.fromMap({
      'proposal': {
        'request_id': 'req',
        'provider_id': 'provider',
        'agent_id': 'provider.agent',
        'action_id': 'provider.order.create',
        'tool_name': 'app_action_order_create',
        'arguments': {'amount': 12},
        'user_intent_summary': '',
        'created_at': '2026-05-25T00:00:00Z',
        'expires_at': '2026-05-25T00:10:00Z',
        'nonce': 'nonce',
        'idempotency_key': 'req',
        'callback': {'type': 'napaxi_action_result'},
        'risk': 'high',
        'confirmation_policy': 'provider_required',
      },
      'action': {
        'action_id': 'provider.order.create',
        'tool_name': 'app_action_order_create',
        'description': 'Create order proposal.',
      },
      'package': {'provider_id': 'provider'}
    });

    expect(request.proposal.requestId, 'req');
    expect(request.proposal.arguments['amount'], 12);
    expect(request.action.confirmationPolicy, 'provider_required');
    expect(request.package['provider_id'], 'provider');
  });

  test('agent app action events decode', () {
    final event = ChatEvent.fromMap({
      'type': 'action_result_received',
      'request_id': 'req',
      'status': 'succeeded',
      'provider_trace_id': 'trace',
    });

    expect(event, isA<ActionResultReceivedEvent>());
    expect((event as ActionResultReceivedEvent).providerTraceId, 'trace');
  });
}
