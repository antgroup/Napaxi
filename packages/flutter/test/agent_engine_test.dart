import 'dart:convert';

import 'package:napaxi_flutter/agent_engine.dart';
import 'package:napaxi_flutter/models/agent.dart';
import 'package:napaxi_flutter/models/chat_event.dart';
import 'package:test/test.dart';

class _DefaultAgentEngineExecutor extends AgentEngineExecutor {
  @override
  Future<AgentEngineTurnResult> startTurn(
    AgentEngineTurnRequest request,
    AgentEngineToolBroker tools,
  ) async {
    return AgentEngineTurnResult.response('ok');
  }
}

void main() {
  test('agent engine defaults and turn codecs use core wire shape', () async {
    final executor = _DefaultAgentEngineExecutor();
    final request = AgentEngineTurnRequest(
      engineId: externalHostAgentEngineId,
      engineProfileId: 'dev-loop',
      engineConfig: const {'binary': 'custom-agent'},
      runId: 'run-1',
      filesDir: '/files',
      workspaceFilesDir: '/files/workspaces/default',
      accountId: 'acct',
      agentId: 'builder',
      sessionKeyJson: '{"thread_id":"t1"}',
      message: 'implement this',
      attachmentsJson: '[]',
      configJson: '{"provider":"openai"}',
    );

    expect(
      await executor.cancel(
        runId: 'run-1',
        sessionKeyJson: '{"thread_id":"t1"}',
      ),
      isFalse,
    );
    final unsupportedResume = await executor.resume(
      request,
      AgentEngineToolBroker(() => 1),
    );
    expect(unsupportedResume.events.single['type'], 'error');
    expect(request.toMap()['workspace_files_dir'], '/files/workspaces/default');

    final response = AgentEngineTurnResult.response('done');
    expect(response.events.single, {'type': 'response', 'content': 'done'});
    final fromEvents = AgentEngineTurnResult.fromEvents(const [
      ResponseEvent(content: 'hello'),
      ThinkingEvent(content: 'planning'),
    ]);
    expect(fromEvents.events.first, {'type': 'response', 'content': 'hello'});
    expect(fromEvents.events.last, {'type': 'thinking', 'content': 'planning'});
  });

  test('agent engine turn request decodes core wire shape', () {
    final request = AgentEngineTurnRequest.fromMap({
      'engine_id': 'external_host',
      'engine_profile_id': 'dev-loop',
      'engine_config': {'binary': 'custom-agent'},
      'run_id': 'run-1',
      'files_dir': '/files',
      'workspace_files_dir': '/files/workspaces/default',
      'account_id': 'acct',
      'agent_id': 'builder',
      'session_key_json': '{"thread_id":"t1"}',
      'message': 'implement this',
      'attachments_json': '[]',
      'config_json': '{"provider":"openai"}',
    });

    expect(request.engineId, externalHostAgentEngineId);
    expect(request.engineProfileId, 'dev-loop');
    expect(request.engineConfig['binary'], 'custom-agent');
    expect(request.workspaceFilesDir, '/files/workspaces/default');
  });

  test('agent engine turn result encodes core event envelope', () {
    final result = AgentEngineTurnResult(
      events: [
        {'type': 'thinking', 'content': 'planning'},
        {'type': 'response_delta', 'content': 'done'},
      ],
    );

    final encoded = jsonDecode(result.toJsonString()) as Map;
    expect(encoded['events'], hasLength(2));
    expect((encoded['events'] as List).last['type'], 'response_delta');
  });

  test('agent engine run event request and result use core protocol shape', () {
    final request = AgentEngineRunEventRequest(
      runId: 'run-1',
      sessionKeyJson: '{"thread_id":"t1"}',
      event: {'type': 'completed', 'tool_call_count': 1},
    );

    final encoded = jsonDecode(request.toJsonString()) as Map;
    expect(encoded['run_id'], 'run-1');
    expect(encoded['event']['type'], 'completed');

    final result = AgentEngineRunEventResult.fromJsonString(
      jsonEncode({
        'event': {
          'type': 'run_completed',
          'run_id': 'run-1',
          'status': 'completed',
          'evidence_kind': 'agent_engine',
          'verification': 'host_reported',
          'tool_call_count': 1,
        },
        'final_content': '',
        'is_error': false,
        'completed': true,
      }),
    );
    expect(result.completed, isTrue);
    expect(result.isError, isFalse);
    expect(result.event['type'], 'run_completed');
  });

  test('tool broker call result decodes events and errors', () {
    final result = AgentEngineToolCallResult.fromJsonString(
      jsonEncode({
        'output': 'ok',
        'is_error': false,
        'effect': 'read',
        'events': [
          {
            'type': 'tool_call',
            'call_id': 'c1',
            'name': 'shell',
            'arguments': '{}',
          },
          {
            'type': 'tool_result',
            'call_id': 'c1',
            'name': 'shell',
            'output': 'ok',
            'is_error': false,
          },
        ],
      }),
    );

    expect(result.output, 'ok');
    expect(result.isError, isFalse);
    expect(result.events, hasLength(2));
    expect(result.effect, 'read');

    final error = AgentEngineToolCallResult.fromJsonString(
      jsonEncode({'error': 'policy denied'}),
    );
    expect(error.isError, isTrue);
    expect(error.output, 'policy denied');
  });

  test(
    'agent definition engine fields preserve old default and new config',
    () {
      final legacy = AgentDefinition.fromMap({
        'id': 'napaxi',
        'name': 'Napaxi',
      });
      expect(legacy.engineId, napaxiCoreAgentEngineId);
      expect(legacy.engineProfileId, isEmpty);
      expect(legacy.engineConfig, isEmpty);

      const external = AgentDefinition(
        id: 'builder',
        name: 'Builder',
        engineId: externalHostAgentEngineId,
        engineProfileId: 'dev-loop',
        engineConfig: {'binary': 'custom-agent'},
      );
      final map = external.toMap();
      expect(map['engine_id'], externalHostAgentEngineId);
      expect(map['engine_profile_id'], 'dev-loop');
      expect(map['engine_config'], {'binary': 'custom-agent'});

      final decoded = AgentDefinition.fromMap(map);
      expect(decoded.engineId, externalHostAgentEngineId);
      expect(decoded.engineProfileId, 'dev-loop');
      expect(decoded.engineConfig['binary'], 'custom-agent');
    },
  );

  test('Codex model sync result decodes validation and write status', () {
    final result = CodexAgentEngineConfigResult.fromMap({
      'success': true,
      'providerAvailable': true,
      'modelUsable': true,
      'errorCode': null,
      'model': 'gpt-5',
      'configChanged': true,
    });

    expect(result.success, isTrue);
    expect(result.providerAvailable, isTrue);
    expect(result.modelUsable, isTrue);
    expect(result.errorCode, isNull);
    expect(result.model, 'gpt-5');
    expect(result.configChanged, isTrue);

    final unsupported = CodexAgentEngineConfigResult.fromMap({
      'success': false,
      'providerAvailable': false,
      'modelUsable': false,
      'errorCode': 'unsupported_platform',
      'error': 'unsupported',
    });
    expect(unsupported.errorCode, 'unsupported_platform');
    expect(unsupported.model, isEmpty);
    expect(unsupported.configChanged, isFalse);
  });

  test('Codex native history result decodes threads and messages', () {
    final result = CodexAgentEngineHistoryResult.fromMap({
      'success': true,
      'providerAvailable': true,
      'nativeThreadId': 'thread-1',
      'threads': [
        {
          'id': 'thread-1',
          'name': 'Greeting',
          'preview': 'hello',
          'createdAt': 1700000000000,
          'updatedAt': 1700000001000,
        },
      ],
      'messages': [
        {'id': 'message-1', 'role': 'user', 'content': 'hello'},
        {'id': 'message-2', 'role': 'assistant', 'content': 'world'},
      ],
    });

    expect(result.success, isTrue);
    expect(result.threads.single.id, 'thread-1');
    expect(result.threads.single.updatedAtMs, 1700000001000);
    expect(result.messages.map((message) => message.role), [
      'user',
      'assistant',
    ]);
    expect(result.nativeThreadId, 'thread-1');
  });
}
