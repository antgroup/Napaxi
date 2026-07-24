import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('developer Codex runtime routes through core external host engine', () {
    final clientSource = File(
      'lib/demo_client/napaxi_chat_client.dart',
    ).readAsStringSync();
    final bridgeSource = File(
      'lib/demo_client/cli_engine_bridge.dart',
    ).readAsStringSync();
    final scenariosSource = File(
      'lib/panels/scenarios_panel.dart',
    ).readAsStringSync();
    final chatScreenSource = File(
      'lib/screens/chat_screen.dart',
    ).readAsStringSync();

    expect(
      clientSource,
      contains('agentEngineExecutor: _CliAgentEngineExecutor'),
    );
    expect(clientSource, contains("runtimeProfile.agentId == 'engine.codex'"));
    expect(clientSource, contains('sdk.externalHostAgentEngineId'));
    expect(clientSource, contains("engineProfileId: isCodex ? 'codex' : ''"));
    expect(
      clientSource,
      contains("engineConfig: isCodex ? const {'kind': 'codex'}"),
    );
    expect(clientSource, contains('napaxi.agent_engine.external_host'));
    expect(clientSource, contains('_runtimeAgentDefinitionNeedsUpdate'));
    expect(clientSource, contains('existing.engineId'));
    expect(clientSource, contains('existing.engineProfileId'));
    expect(clientSource, contains('existing.engineConfig'));
    expect(clientSource, contains("agentId == 'engine.cc'"));
    expect(clientSource, contains("_getOrCreateBridge('codex')"));
    expect(clientSource, contains('recordNativeThreadId'));

    expect(
      clientSource,
      isNot(contains("return _sendToCliBridge(\n        'codex'")),
    );
    expect(
      clientSource,
      isNot(
        contains(
          "if (agentId == 'engine.codex') {\n      _codexBridge?.sendInterrupt();",
        ),
      ),
    );

    expect(bridgeSource, contains('class _CliAgentEngineExecutor'));
    expect(bridgeSource, contains('implements sdk.AgentEngineExecutor'));
    expect(bridgeSource, contains("kind == 'codex' || profile == 'codex'"));
    expect(
      bridgeSource,
      contains('sdk.AgentEngineTurnResult.fromEvents(events)'),
    );
    expect(bridgeSource, contains('isAttachedToThread'));
    expect(bridgeSource, contains('recordNativeThreadId'));
    expect(
      bridgeSource,
      contains(r'export HOME=/root PATH="/root/.local/bin:\$PATH";'),
    );

    expect(scenariosSource, contains('napaxi.agent_engine.external_host'));
    expect(chatScreenSource, contains("if (agentId == 'engine.cc')"));
    expect(chatScreenSource, contains('Codex now routes through Rust core'));
    expect(chatScreenSource, contains('Do not migrate'));
    expect(
      chatScreenSource,
      isNot(contains('if (isCliEngine) {\n        // CLI bridges (CC/Codex)')),
    );
  });
}
