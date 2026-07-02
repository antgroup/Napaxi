import 'dart:convert';

import 'package:test/test.dart';
import 'package:napaxi_flutter/models/capability.dart';

void main() {
  test('capability definition json round trips', () {
    const definition = NapaxiCapabilityDefinition(
      id: 'napaxi.llm.openai',
      kind: 'llm_provider',
      version: '1',
      platforms: ['all'],
      configSchema: {
        'type': 'object',
        'properties': {
          'model': {'type': 'string'},
        },
      },
      risk: 'medium',
      requirements: ['api_key', 'model'],
      defaultEnabled: true,
      activation: 'config',
    );

    final decoded = NapaxiCapabilityDefinition.fromJson(definition.toJson());

    expect(decoded.id, definition.id);
    expect(decoded.kind, 'llm_provider');
    expect(decoded.configSchema['properties'], isA<Map>());
    expect(decoded.requirements, ['api_key', 'model']);
  });

  test('capability status decodes unavailable reason', () {
    final jsonStr = jsonEncode([
      {
        'definition': const NapaxiCapabilityDefinition(
          id: 'napaxi.platform_tool.open_url',
          kind: 'platform_tool',
          version: '1',
          platforms: ['android', 'ios'],
          configSchema: {'type': 'object'},
          risk: 'low',
          requirements: ['host_bridge'],
          defaultEnabled: true,
          activation: 'host',
        ).toJson(),
        'registered': true,
        'available': false,
        'enabled': false,
        'unavailable_reason': 'requires host support',
      },
    ]);

    final statuses = decodeCapabilityStatuses(jsonStr);

    expect(statuses, hasLength(1));
    expect(statuses.single.definition.id, 'napaxi.platform_tool.open_url');
    expect(statuses.single.available, isFalse);
    expect(statuses.single.unavailableReason, 'requires host support');
  });

  test('profile and selection use core json field names', () {
    const profile = NapaxiCapabilityProfile(
      platform: 'ios',
      supportedCapabilities: ['napaxi.platform_tool.*'],
      disabledCapabilities: ['napaxi.platform_tool.install_apk'],
    );
    const selection = NapaxiCapabilitySelection(
      enabledCapabilities: ['napaxi.tool.image_analysis'],
      disabledCapabilities: ['napaxi.tool.shell'],
      config: {
        'napaxi.tool.image_analysis': {'model': 'vision-model'},
      },
    );

    final profileJson = jsonDecode(profile.toJsonString()) as Map;
    final selectionJson = jsonDecode(selection.toJsonString()) as Map;

    expect(profileJson['supported_capabilities'], ['napaxi.platform_tool.*']);
    expect(selectionJson['enabled_capabilities'], [
      'napaxi.tool.image_analysis',
    ]);
    expect(selectionJson['config'], contains('napaxi.tool.image_analysis'));
  });

  test('scenario pack json round trips with extension fields', () {
    const pack = NapaxiScenarioPack(
      id: 'napaxi.scenario.mobile_development',
      version: '1',
      label: 'Developer Workbench',
      description: 'Developer scene',
      risk: 'critical',
      activation: 'host_policy',
      executionPlanes: ['core', 'host_bridge', 'remote_workspace'],
      requiredCapabilities: ['napaxi.service.remote_workspace'],
      recommendedCapabilities: ['napaxi.mcp.runtime'],
      optionalCapabilities: ['napaxi.service.automation'],
      uiSurfaces: ['chat', 'diff_view'],
      settingsContributions: [
        NapaxiScenarioSettingsContribution(
          id: 'settings.git',
          capabilityId: 'napaxi.tool.git',
          placement: 'scenario_settings',
          title: 'Git',
          schema: {
            'type': 'object',
            'properties': {
              'token': {'type': 'secret'},
            },
          },
          actions: ['save', 'clear_credentials'],
        ),
      ],
      uiContributions: [
        NapaxiScenarioUiContribution(
          id: 'ui.repo_workbench',
          capabilityId: 'napaxi.tool.git',
          placement: 'left_menu',
          title: 'Projects',
          icon: 'folder_git',
          renderer: 'repo_workbench',
          dataSources: {'repositories': 'git.repositories'},
          actions: ['open_repository', 'search_files'],
        ),
      ],
      memoryScopes: ['project'],
      tags: ['developer'],
    );

    final decoded = NapaxiScenarioPack.fromJson(pack.toJson());

    expect(decoded.id, 'napaxi.scenario.mobile_development');
    expect(decoded.activation, 'host_policy');
    expect(decoded.executionPlanes, contains('remote_workspace'));
    expect(decoded.requiredCapabilities, ['napaxi.service.remote_workspace']);
    expect(decoded.uiSurfaces, contains('diff_view'));
    expect(decoded.settingsContributions.single.id, 'settings.git');
    expect(
        decoded.settingsContributions.single.schema['properties']['token']
            ['type'],
        'secret');
    expect(decoded.settingsContributions.single.actions,
        contains('clear_credentials'));
    expect(decoded.uiContributions.single.id, 'ui.repo_workbench');
    expect(decoded.uiContributions.single.renderer, 'repo_workbench');
    expect(decoded.uiContributions.single.dataSources['repositories'],
        'git.repositories');
    expect(decoded.uiContributions.single.actions, contains('search_files'));
  });

  test('scenario status decodes missing and unavailable capabilities', () {
    final jsonStr = jsonEncode([
      {
        'definition': const NapaxiScenarioPack(
          id: 'napaxi.scenario.mobile_development',
          version: '1',
          label: 'Developer Workbench',
          description: 'Developer scene',
          risk: 'critical',
          activation: 'host_policy',
          requiredCapabilities: ['napaxi.service.remote_workspace'],
        ).toJson(),
        'registered': true,
        'available': false,
        'enabled': false,
        'missing_required_capabilities': ['napaxi.tool.git'],
        'disabled_required_capabilities': ['napaxi.policy.approval'],
        'unavailable_reasons': ['requires host support'],
      },
    ]);

    final statuses = decodeScenarioStatuses(jsonStr);

    expect(statuses, hasLength(1));
    expect(statuses.single.definition.id, 'napaxi.scenario.mobile_development');
    expect(statuses.single.available, isFalse);
    expect(statuses.single.missingRequiredCapabilities, ['napaxi.tool.git']);
    expect(statuses.single.disabledRequiredCapabilities, [
      'napaxi.policy.approval',
    ]);
    expect(statuses.single.unavailableReasons, ['requires host support']);
  });

  test('scenario resolution decodes activation plan', () {
    final jsonStr = jsonEncode({
      'status': {
        'definition': const NapaxiScenarioPack(
          id: 'napaxi.scenario.mobile_development',
          version: '1',
          label: 'Developer Workbench',
          description: 'Developer scene',
          risk: 'critical',
          activation: 'host_policy',
        ).toJson(),
        'registered': true,
        'available': false,
        'enabled': false,
      },
      'activation_plan': {
        'supported_capabilities': ['napaxi.service.remote_workspace'],
        'enabled_capabilities': ['napaxi.tool.shell_remote'],
        'disabled_capabilities': [],
        'host_required_capabilities': ['napaxi.policy.approval'],
        'remote_required_capabilities': ['napaxi.tool.shell_remote'],
        'policy_required_capabilities': ['napaxi.policy.approval'],
        'warnings': ['critical risk'],
      },
    });

    final resolution = decodeScenarioResolution(jsonStr);

    expect(resolution, isNotNull);
    expect(
      resolution!.status.definition.id,
      'napaxi.scenario.mobile_development',
    );
    expect(resolution.activationPlan.supportedCapabilities, [
      'napaxi.service.remote_workspace',
    ]);
    expect(resolution.activationPlan.remoteRequiredCapabilities, [
      'napaxi.tool.shell_remote',
    ]);
    expect(
      decodeScenarioResolution('{"error":{"code":"unknown_scenario"}}'),
      isNull,
    );
  });

  test('scenario install and removal results decode', () {
    final pack = const NapaxiScenarioPack(
      id: 'napaxi.scenario.experimental_hidden',
      version: '1',
      label: 'Experimental Hidden Scenario',
      description: 'Generic installable scenario fixture',
      risk: 'high',
      activation: 'host_policy',
      requiredCapabilities: ['napaxi.service.scenario_registry'],
    );
    final installJson = jsonEncode({
      'definition': pack.toJson(),
      'installed': true,
      'replaced': false,
      'warnings': ['core execution plane was added'],
    });
    final removalJson = jsonEncode({
      'scenario_id': 'napaxi.scenario.experimental_hidden',
      'removed': true,
    });

    final install = decodeScenarioPackInstallResult(installJson);
    final removal = decodeScenarioPackRemovalResult(removalJson);

    expect(install, isNotNull);
    expect(install!.definition.id, 'napaxi.scenario.experimental_hidden');
    expect(install.installed, isTrue);
    expect(install.replaced, isFalse);
    expect(install.warnings.single, contains('core execution'));
    expect(removal, isNotNull);
    expect(removal!.scenarioId, 'napaxi.scenario.experimental_hidden');
    expect(removal.removed, isTrue);
    expect(decodeScenarioPackInstallResult('{"error":{"code":"invalid"}}'),
        isNull);
    expect(decodeScenarioPackRemovalResult('{"error":{"code":"invalid"}}'),
        isNull);
  });
}
