import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('qqbot defaults target production c2c and group gateway', () {
    final source = File(
      '../../packages/flutter/lib/convenience/channel_qqbot_provider.dart',
    ).readAsStringSync();

    expect(source, contains('static const defaultIntents = 1 << 25'));
    expect(source, contains('static const legacyDefaultIntents'));
    expect(source, contains("static const agentIdKey = 'agent_id'"));
    expect(source, contains('fallback: false'));
    expect(source, contains('_gatewayReadyWaiter!.future.timeout'));
    expect(source, contains(r"'READY'"));
    expect(source, contains('invalid_session'));
    expect(
      source,
      contains("static const providerId = 'napaxi.qqbot.provider'"),
    );
  });

  test('channel setup keeps qqbot credentials pasteable', () {
    final source = File(
      'lib/screens/chat_screen_channel.dart',
    ).readAsStringSync();

    expect(source, contains('`/channel qqbot setup`'));
    expect(source, contains(r"key: const Key('qqbot_app_secret_field')"));
    expect(source, contains(r"key: const Key('qqbot_agent_picker')"));
    expect(
      source,
      contains(r"key: const Key('qqbot_app_secret_paste_button')"),
    );
    expect(source, contains('_showQqChannelSetupSheet'));
    expect(source, contains('showModalBottomSheet<DemoChannelCredentials>'));
    expect(source, contains('_ChannelAgentPicker'));
    expect(source, contains('Clipboard.getData(Clipboard.kTextPlain)'));
    expect(source, contains('enableInteractiveSelection: true'));
    expect(source, contains('TextInputType.visiblePassword'));
    expect(source, contains('_sandbox = existing?.sandbox ?? false'));
    expect(source, contains('_ChannelAdvancedTile'));
    expect(source, isNot(contains('_intentsController')));
    expect(source, isNot(contains("labelText: 'Intents'")));
    expect(
      source,
      contains("sessionAccountId: existing?.sessionAccountId ?? ''"),
    );
    expect(source, isNot(contains('/qq recv')));
    expect(source, isNot(contains('/qq send')));
  });

  test(
    'channel setup exposes bluetooth devices through generic channel path',
    () {
      final screenSource = File(
        'lib/screens/chat_screen_channel.dart',
      ).readAsStringSync();
      final clientSource = File(
        'lib/demo_client/napaxi_chat_client.dart',
      ).readAsStringSync();
      final providerSource = File(
        '../../packages/flutter/lib/convenience/channel_bluetooth_headset_provider.dart',
      ).readAsStringSync();

      expect(screenSource, contains('`/channel headset setup`'));
      expect(screenSource, contains('`/channel headset ptt`'));
      expect(screenSource, contains('_HeadsetChannelSetupDialog'));
      expect(
        screenSource,
        contains("key: const Key('headset_device_id_field')"),
      );
      expect(screenSource, contains("key: const Key('headset_agent_picker')"));
      expect(screenSource, contains('_showHeadsetChannelSetupSheet'));
      expect(screenSource, contains('BluetoothHeadsetDeviceDiscovery'));
      expect(screenSource, contains('_HeadsetDeviceOption'));
      expect(screenSource, contains('_BluetoothOtherDevicesTile'));
      expect(screenSource, contains('_bluetoothDeviceKindLabel'));
      expect(screenSource, contains('BluetoothDeviceKind.phone'));
      expect(screenSource, contains('_ChannelAdvancedTile'));
      expect(screenSource, contains('_captureHeadsetTranscriptCommand'));
      expect(clientSource, contains('_startDemoHeadsetChannelBridge'));
      expect(clientSource, contains('_registerDemoHeadsetChannelRoute'));
      expect(clientSource, contains('captureHeadsetTranscript'));
      expect(
        clientSource,
        contains('_autoConnectConfiguredDemoHeadsetChannel'),
      );
      expect(clientSource, contains('submitVoiceTranscript'));
      expect(clientSource, contains('withPlatformAudio'));
      expect(clientSource, contains('sdk.NapaxiChannelCapability.device'));
      expect(
        providerSource,
        contains(
          "static const providerId = 'napaxi.bluetooth_headset.provider'",
        ),
      );
      expect(providerSource, contains('NapaxiChannelSurfaceKind.device'));
      expect(providerSource, contains('NapaxiChannelEndpointKind.device'));
      expect(providerSource, contains('voice_transcript_final'));
      expect(providerSource, contains('BluetoothHeadsetPlatformAudio'));
      expect(providerSource, contains('BluetoothHeadsetSpeechSink'));
    },
  );

  test('settings menu exposes first-party channels before nearby', () {
    final source = File('lib/panels/session_history.dart').readAsStringSync();

    expect(source, contains('_SettingsSection.channels'));
    expect(source, contains('_ChannelSettingsPage'));
    expect(source, isNot(contains("key: const Key('channels_menu_item')")));
    expect(source, contains("key: const Key('settings_menu_button')"));
    expect(source, contains('_settingsInitialSection ='));
    expect(source, contains('_SettingsSection.menu;'));
    expect(source, contains("key: const Key('settings_channels_item')"));
    expect(source, contains("key: const Key('channel_settings_page')"));
    expect(
      source.indexOf("key: const Key('settings_channels_item')"),
      lessThan(source.indexOf("key: const Key('settings_nearby_item')")),
    );
    expect(source, contains('sdk.QqBotChannelProvider.channelName'));
    expect(source, contains('sdk.BluetoothHeadsetChannelProvider.channelName'));
    expect(source, contains("key: const Key('channel_add_button')"));
    expect(source, contains('_ChannelTypePickerDialog'));
    expect(source, contains('showModalBottomSheet<String>'));
    expect(source, contains('_ChannelSetupSheetFrame'));
    expect(source, contains('listChannelStatuses()'));
    expect(source, contains('listAgents()'));
    expect(source, contains('_channelStatusAccountId(status)'));
    expect(source, contains('_QqChannelSetupDialog'));
    expect(source, contains('_HeadsetChannelSetupDialog'));
    expect(source, contains('connectChannel('));
    expect(source, contains('_refreshConnectedChannel'));
    expect(source, contains('status.connected'));
    expect(source, contains("_channelText(context, zh: '刷新', en: 'Refresh')"));
    expect(
      source,
      contains('required Future<bool> Function(NapaxiChatClient client) run'),
    );
    expect(source, contains('if (credentials == null) return false;'));
  });

  test('demo scenarios keep provider action capability enabled', () {
    final source = File('lib/panels/scenarios_panel.dart').readAsStringSync();

    expect(source, contains("'napaxi.tool.agent_app_action'"));
  });

  test('qqbot bridge routes inbound through an agent reply loop', () {
    final bridgeSource = File(
      '../../packages/flutter/lib/api/channel_agent_bridge.dart',
    ).readAsStringSync();
    final demoSource = File(
      'lib/demo_client/napaxi_chat_client.dart',
    ).readAsStringSync();

    expect(demoSource, contains('_startDemoQqChannelBridge'));
    expect(demoSource, contains('sdk.NapaxiChannelAgentBridge'));
    expect(demoSource, contains('reconnectProvider:'));
    expect(demoSource, contains('ensureAgent: _ensureAgent'));
    expect(demoSource, contains('_channelBridgeEvents.add(event)'));
    expect(demoSource, contains('_loadDemoQqCredentials'));
    expect(demoSource, contains('_loadDemoQqCredentialList'));
    expect(
      demoSource,
      contains('final existingProvider = _demoQqChannelProviders[qqAccountId]'),
    );
    expect(demoSource, contains('_demoQqChannelBridges[qqAccountId]'));
    expect(
      demoSource,
      contains('_channelCredentialsKey(normalized, accountId)'),
    );
    expect(demoSource, contains('if (existingStatus.connected)'));
    expect(demoSource, contains('_ensureDemoQqChannelRuntimeConfig'));
    expect(demoSource, contains('_loadStoredChannelRuntimeConfig'));
    expect(demoSource, contains('_restorePersistedDemoRuntimeSelection'));
    expect(demoSource, contains('_ChatScreenState._activeScenarioKey'));
    expect(demoSource, contains('_removeStaleDemoQqChannelRoutes'));
    expect(demoSource, contains('_demoQqSessionAccountId'));
    expect(demoSource, contains('_demoQqCredentialsWithSessionAccountId'));
    expect(
      demoSource,
      contains('DemoQqChannelCredentials.sessionAccountIdKey'),
    );
    expect(demoSource, contains('autoConnectChannels: false'));
    expect(demoSource, contains('_isChannelRuntimeConfigReady'));
    expect(demoSource, contains("throw StateError('Failed to update Napaxi"));
    expect(demoSource, contains('_channelResponseLanguageCode'));
    expect(
      demoSource,
      contains(
        "'QQBot is connected, but agent \${credentials.agentId} has no ready '",
      ),
    );
    expect(
      demoSource,
      contains(
        "'LLM model profile. Configure a model before sending QQ messages.'",
      ),
    );
    expect(
      demoSource,
      contains(
        "_demoQqChannelAutoConnectErrors[accountId] =\n            'QQBot auto-connect failed: \$error'",
      ),
    );
    expect(demoSource, contains('QQBot provider reconnect failed'));
    expect(bridgeSource, contains('engine.channelAgents.registerRoute'));
    expect(bridgeSource, contains('NapaxiChannelAgentRoute.channelDefault'));
    expect(bridgeSource, contains('engine.channelAgents.streamPump'));
    expect(bridgeSource, contains('engine.channelProviders.pump'));
    expect(bridgeSource, contains('accountId: channelAccountId'));
    expect(bridgeSource, contains('agentId: agentId'));
    expect(bridgeSource, contains('inboundBatchSize'));
    expect(bridgeSource, contains('_channelRuntimeConfigIssue'));
    expect(
      bridgeSource,
      contains('Channel runtime LLM API key is not configured'),
    );
    expect(bridgeSource, contains('waiting_runtime'));
    expect(bridgeSource, contains('reconnecting_provider'));
    expect(
      bridgeSource,
      contains(
        "_phase = 'waiting_provider';\n        unawaited(_ensureBackgroundKeepAlive());",
      ),
    );
    expect(bridgeSource, contains('keepAliveInBackground'));
    expect(
      bridgeSource,
      isNot(
        contains(
          'if (isProviderConnected != null && !isProviderConnected!()) return;',
        ),
      ),
    );
    expect(bridgeSource, isNot(contains('engine.sendToSession')));
    expect(bridgeSource, isNot(contains('stableSessionThreadId')));
    expect(bridgeSource, isNot(contains('AskingHumanEvent')));
    expect(bridgeSource, isNot(contains('engine.answerHumanRequest')));
    expect(demoSource, contains('ensureConfiguredChannelsConnected'));
    expect(demoSource, contains('reconnectDisconnected: true'));
    expect(demoSource, contains('unregisterProvider'));
    expect(demoSource, contains('_withDemoBaselineCapabilities'));
    expect(demoSource, contains('sdk.NapaxiChannelCapability.im'));

    final demoProviderSource = File(
      'lib/demo_client/demo_qq_channel_provider.dart',
    ).readAsStringSync();
    expect(
      demoProviderSource,
      contains("sessionAccountIdKey = 'session_account_id'"),
    );
    expect(demoProviderSource, contains('final String sessionAccountId'));
    expect(demoProviderSource, contains('config[sessionAccountIdKey]'));
  });

  test('chat screen subscribes to channel bridge sessions', () {
    final source = File('lib/screens/chat_screen.dart').readAsStringSync();

    expect(source, contains('_listenForChannelBridgeEvents(client)'));
    expect(source, contains('_handleChannelBridgeEvent'));
    expect(source, contains('_applyChannelBridgeChatEvent'));
    expect(source, contains('client.onChannelBridgeEvent.listen'));
    expect(source, contains('_sdkSessions[cacheKey] = event.session'));
    expect(source, contains('event.humanRequestId'));
    expect(source, contains('HumanRequest('));
    expect(source, contains('event.humanResponseRequestId'));
    expect(source, contains('_ensureConfiguredChannelsConnected'));
    expect(source, contains('AppLifecycleState.resumed'));
    expect(source, contains('AppLifecycleState.paused'));
    expect(source, contains('client.ensureConfiguredChannelsConnected()'));
  });
}
