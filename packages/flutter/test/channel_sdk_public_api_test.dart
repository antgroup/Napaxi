import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:napaxi_flutter/napaxi_flutter.dart' as sdk;

void main() {
  test('qqbot provider is exposed as an SDK channel provider', () {
    const credentials = sdk.QqBotChannelCredentials(
      appId: 'bot-app',
      appSecret: 'secret',
      agentId: 'agent.qq',
    );

    final manifest = sdk.QqBotChannelProvider.manifestFor(credentials);

    expect(manifest.providerId, 'napaxi.qqbot.provider');
    expect(manifest.channelName, sdk.QqBotChannelProvider.channelName);
    expect(manifest.surfaceKind, sdk.NapaxiChannelSurfaceKind.im);
    expect(
      manifest.endpointKinds,
      contains(sdk.NapaxiChannelEndpointKind.group),
    );
    expect(manifest.modalities, contains(sdk.NapaxiChannelModality.text));
    expect(
      manifest.contentFormats,
      contains(sdk.NapaxiChannelContentFormat.markdown),
    );
    expect(manifest.transport, 'qqbot_gateway_openapi');
    expect(manifest.accountId, 'bot-app');
    expect(manifest.config['agent_id'], 'agent.qq');
    expect(
      manifest.config['markdown_endpoint_kinds'],
      contains(sdk.NapaxiChannelEndpointKind.direct),
    );
    expect(
      manifest.config['markdown_endpoint_kinds'],
      contains(sdk.NapaxiChannelEndpointKind.group),
    );
  });

  // NOTE: the QQ outbound payload shaping and markdown 4xx fallback rule moved
  // to core (napaxi_core::api::channel_qqbot) and are verified there against the
  // shared fixture (channel::qqbot::protocol_matches_shared_contract_fixture).
  // They are no longer Dart-testable: the bridged functions require the native
  // library, which Flutter unit tests do not load. The adapter is now a thin
  // transport shell over the core protocol.

  test('qqbot credentials round trip through generic secret/config maps', () {
    final credentials = sdk.QqBotChannelCredentials.fromMaps(
      secrets: const {
        sdk.QqBotChannelCredentials.appIdKey: ' bot-app ',
        sdk.QqBotChannelCredentials.appSecretKey: ' secret ',
      },
      config: const {
        sdk.QqBotChannelCredentials.configVersionKey:
            sdk.QqBotChannelCredentials.configVersion,
        sdk.QqBotChannelCredentials.sandboxKey: true,
        sdk.QqBotChannelCredentials.intentsKey:
            sdk.QqBotChannelCredentials.legacyDefaultIntents,
        sdk.QqBotChannelCredentials.agentIdKey: 'agent.qq',
      },
    );

    expect(credentials.appId, 'bot-app');
    expect(credentials.appSecret, 'secret');
    expect(credentials.sandbox, isTrue);
    expect(credentials.intents, sdk.QqBotChannelCredentials.defaultIntents);
    expect(credentials.agentId, 'agent.qq');
    expect(
      credentials.toSecretMap()[sdk.QqBotChannelCredentials.appIdKey],
      'bot-app',
    );
    expect(
      credentials.toConfigMap()[sdk.QqBotChannelCredentials.agentIdKey],
      'agent.qq',
    );
  });

  test(
    'bluetooth audio device provider is exposed as a device channel provider',
    () {
      const credentials = sdk.BluetoothHeadsetChannelCredentials(
        deviceId: 'headset-1',
        deviceName: 'Test Headset',
        accountId: 'audio-account',
        agentId: 'agent.headset',
      );

      final manifest = sdk.BluetoothHeadsetChannelProvider.manifestFor(
        credentials,
      );

      expect(manifest.providerId, 'napaxi.bluetooth_headset.provider');
      expect(
        manifest.channelName,
        sdk.BluetoothHeadsetChannelProvider.channelName,
      );
      expect(manifest.surfaceKind, sdk.NapaxiChannelSurfaceKind.device);
      expect(manifest.endpointKinds, [sdk.NapaxiChannelEndpointKind.device]);
      expect(manifest.modalities, contains(sdk.NapaxiChannelModality.audio));
      expect(manifest.modalities, contains(sdk.NapaxiChannelModality.control));
      expect(manifest.modalities, contains(sdk.NapaxiChannelModality.presence));
      expect(
        manifest.contentFormats,
        contains(sdk.NapaxiChannelContentFormat.markdown),
      );
      expect(manifest.transport, 'bluetooth_headset_host_audio');
      expect(manifest.accountId, 'audio-account');
      expect(manifest.config['device_id'], 'headset-1');
      expect(manifest.config['agent_id'], 'agent.headset');
      expect(sdk.NapaxiChannelCapability.device, 'napaxi.channel.device');
    },
  );

  test('bluetooth headset credentials round trip through config maps', () {
    final credentials = sdk.BluetoothHeadsetChannelCredentials.fromMaps(
      config: const {
        sdk.BluetoothHeadsetChannelCredentials.deviceIdKey: ' headset-1 ',
        sdk.BluetoothHeadsetChannelCredentials.deviceNameKey: ' Headset ',
        sdk.BluetoothHeadsetChannelCredentials.accountIdKey: ' audio ',
        sdk.BluetoothHeadsetChannelCredentials.agentIdKey: 'agent.headset',
        sdk.BluetoothHeadsetChannelCredentials.ttsEnabledKey: false,
      },
    );

    expect(credentials.deviceId, 'headset-1');
    expect(credentials.deviceName, 'Headset');
    expect(credentials.accountId, 'audio');
    expect(credentials.agentId, 'agent.headset');
    expect(credentials.ttsEnabled, isFalse);
    expect(
      credentials
          .toConfigMap()[sdk.BluetoothHeadsetChannelCredentials.deviceIdKey],
      'headset-1',
    );
  });

  test('bluetooth device discovery decodes classification fields', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('com.napaxi.flutter/bluetooth_headset');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'listAudioDevices');
      return {
        'supported': true,
        'permission_granted': true,
        'devices': [
          {
            'id': 'AA:BB:CC:DD:EE:FF',
            'name': 'Test Headset',
            'bonded': true,
            'connected': true,
            'device_kind': 'headset',
            'profiles': ['a2dp', 'headset'],
            'capabilities': ['audio_input', 'audio_output'],
            'recommended_channel_kinds': ['bluetooth_audio'],
            'confidence': 0.92,
          },
        ],
        'other_devices': [
          {
            'id': '11:22:33:44:55:66',
            'name': 'Other Phone',
            'bonded': true,
            'connected': false,
            'device_kind': 'phone',
            'profiles': [],
            'capabilities': [],
            'recommended_channel_kinds': ['a2a'],
            'confidence': 0.9,
          },
        ],
      };
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final result =
        await sdk.BluetoothHeadsetDeviceDiscovery().listAudioDevices();

    expect(result.supported, isTrue);
    expect(result.permissionGranted, isTrue);
    expect(result.devices.single.id, 'AA:BB:CC:DD:EE:FF');
    expect(result.devices.single.name, 'Test Headset');
    expect(result.devices.single.connected, isTrue);
    expect(result.devices.single.deviceKind, sdk.BluetoothDeviceKind.headset);
    expect(
      result.devices.single.recommendedChannelKinds,
      contains(sdk.BluetoothDeviceRecommendedChannelKind.bluetoothAudio),
    );
    expect(result.devices.single.audioInputAvailable, isTrue);
    expect(result.devices.single.audioOutputAvailable, isTrue);
    expect(result.devices.single.confidence, 0.92);
    expect(
        result.otherDevices.single.deviceKind, sdk.BluetoothDeviceKind.phone);
    expect(
      result.otherDevices.single.recommendedChannelKinds,
      contains(sdk.BluetoothDeviceRecommendedChannelKind.a2a),
    );
  });

  test(
    'bluetooth audio device provider submits transcript and acks tts outbound',
    () async {
      final queue = _FakeChannelQueue();
      final host = sdk.NapaxiChannelProviderHost(queue);
      final provider = sdk.BluetoothHeadsetChannelProvider(
        const sdk.BluetoothHeadsetChannelCredentials(
          deviceId: 'headset-1',
          deviceName: 'Headset',
        ),
      );

      await host.registerProvider(provider);
      final receipt = provider.submitVoiceTranscript(
        const sdk.BluetoothHeadsetTranscript(
          text: '帮我看一下今天的日程',
          confidence: 0.91,
        ),
      );
      expect(receipt.accepted, isTrue);
      expect(
        queue.inbound.single.peer.kind,
        sdk.NapaxiChannelEndpointKind.device,
      );
      expect(queue.inbound.single.raw?['type'], 'voice_transcript_final');

      queue.outbound.add(
        const sdk.NapaxiChannelOutboundMessage(
          id: 'out-1',
          channelName: sdk.BluetoothHeadsetChannelProvider.channelName,
          accountId: sdk.BluetoothHeadsetChannelCredentials.defaultAccountId,
          peer: sdk.NapaxiChannelPeer(
            kind: sdk.NapaxiChannelEndpointKind.device,
            id: 'headset-1',
          ),
          text: '**好的**，我来看一下。',
          format: sdk.NapaxiChannelContentFormat.markdown,
        ),
      );
      final pump = await host.pump(
        sdk.BluetoothHeadsetChannelProvider.channelName,
      );

      expect(pump.delivered, 1);
      expect(queue.acked.single['id'], 'out-1');
      expect(queue.acked.single['receipt']['spoken_text'], '好的，我来看一下。');
    },
  );

  test(
    'bluetooth platform audio captures transcript and speaks outbound reply',
    () async {
      const channel = MethodChannel('com.napaxi.flutter/bluetooth_headset');
      final calls = <String>[];
      Map<dynamic, dynamic>? captureArgs;
      Map<dynamic, dynamic>? speakArgs;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'listAudioDevices':
            return {
              'supported': true,
              'permission_granted': true,
              'devices': [
                {
                  'id': 'headset-1',
                  'name': 'Test Headset',
                  'connected': true,
                  'device_kind': sdk.BluetoothDeviceKind.headset,
                  'profiles': [sdk.BluetoothDeviceProfile.headset],
                  'capabilities': [
                    sdk.BluetoothDeviceCapability.audioInput,
                    sdk.BluetoothDeviceCapability.audioOutput,
                  ],
                  'recommended_channel_kinds': [
                    sdk.BluetoothDeviceRecommendedChannelKind.bluetoothAudio,
                  ],
                },
              ],
            };
          case 'checkMicrophonePermission':
            return true;
          case 'captureSpeechTranscript':
            captureArgs = Map<dynamic, dynamic>.from(
              call.arguments as Map<dynamic, dynamic>,
            );
            return {
              'text': '帮我看看今天的日程',
              'confidence': 0.86,
              'duration_ms': 1200,
              'platform_message_id': 'speech-1',
            };
          case 'speakBluetoothReply':
            speakArgs = Map<dynamic, dynamic>.from(
              call.arguments as Map<dynamic, dynamic>,
            );
            return {
              'delivered': true,
              'receipt': {'tts_engine': 'test'},
            };
          default:
            fail('unexpected method ${call.method}');
        }
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final queue = _FakeChannelQueue();
      final host = sdk.NapaxiChannelProviderHost(queue);
      final provider = sdk.BluetoothHeadsetChannelProvider.withPlatformAudio(
        const sdk.BluetoothHeadsetChannelCredentials(
          deviceId: 'headset-1',
          deviceName: 'Test Headset',
        ),
      );

      await host.registerProvider(provider);
      final capture = await provider.captureAndSubmit();

      expect(capture.submitted, isTrue);
      expect(capture.transcript?.text, '帮我看看今天的日程');
      expect(captureArgs?['deviceId'], 'headset-1');
      expect(captureArgs?['maxDurationMs'], 20000);
      expect(queue.inbound.single.platformMessageId, 'speech-1');
      expect(queue.inbound.single.text, '帮我看看今天的日程');

      queue.outbound.add(
        const sdk.NapaxiChannelOutboundMessage(
          id: 'out-platform-audio',
          channelName: sdk.BluetoothHeadsetChannelProvider.channelName,
          accountId: sdk.BluetoothHeadsetChannelCredentials.defaultAccountId,
          peer: sdk.NapaxiChannelPeer(
            kind: sdk.NapaxiChannelEndpointKind.device,
            id: 'headset-1',
          ),
          text: '**好的**，我来看。',
          format: sdk.NapaxiChannelContentFormat.markdown,
        ),
      );
      final pump = await host.pump(
        sdk.BluetoothHeadsetChannelProvider.channelName,
      );

      expect(pump.delivered, 1);
      expect(speakArgs?['spokenText'], '好的，我来看。');
      expect(speakArgs?['outboundId'], 'out-platform-audio');
      expect(queue.acked.single['receipt']['tts_engine'], 'test');
      expect(
          calls,
          containsAllInOrder([
            'listAudioDevices',
            'checkMicrophonePermission',
            'captureSpeechTranscript',
            'speakBluetoothReply',
          ]));
    },
  );

  test('bluetooth audio device provider probes selected platform device',
      () async {
    const channel = MethodChannel('com.napaxi.flutter/bluetooth_headset');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'listAudioDevices');
      return {
        'supported': true,
        'permission_granted': true,
        'devices': [
          {
            'id': 'headset-1',
            'name': 'Test Headset',
            'connected': true,
            'device_kind': sdk.BluetoothDeviceKind.headset,
            'profiles': [sdk.BluetoothDeviceProfile.headset],
            'capabilities': [
              sdk.BluetoothDeviceCapability.audioInput,
              sdk.BluetoothDeviceCapability.audioOutput,
            ],
            'recommended_channel_kinds': [
              sdk.BluetoothDeviceRecommendedChannelKind.bluetoothAudio,
            ],
          },
        ],
      };
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final queue = _FakeChannelQueue();
    final host = sdk.NapaxiChannelProviderHost(queue);
    final provider = sdk.BluetoothHeadsetChannelProvider(
      const sdk.BluetoothHeadsetChannelCredentials(
        deviceId: 'headset-1',
        deviceName: 'Test Headset',
      ),
    );

    await host.registerProvider(provider);

    final status = provider.status();
    expect(status.connected, isTrue);
    expect(status.deviceState?.deviceId, 'headset-1');
    expect(status.lastError, isNull);
  });

  test('channel agent route exposes sdk-owned routing config', () {
    final route = sdk.NapaxiChannelAgentRoute.channelDefault(
      channelName: 'qqbot',
      channelAccountId: 'bot-app',
      sessionAccountId: 'demo-account',
      agentId: 'agent.qq',
    );

    expect(route.channelName, 'qqbot');
    expect(route.channelAccountId, 'bot-app');
    expect(route.sessionAccountId, 'demo-account');
    expect(route.agentId, 'agent.qq');
    expect(route.sessionPolicy, 'stable_by_peer_or_thread');
    expect(route.toJson()['channel_account_id'], 'bot-app');
  });

  test('channel bridge event hides raw qq peer ids in default title', () {
    final event = sdk.NapaxiChannelAgentBridgeEvent(
      channelName: 'qqbot',
      agentId: 'agent.qq',
      session: const sdk.SessionKey(
        channelType: 'qqbot',
        accountId: 'demo',
        threadId: 'thread',
      ),
      inboundId: 'in-1',
      peerKind: sdk.NapaxiChannelEndpointKind.direct,
      peerId: 'long-openid',
      senderId: 'sender-openid',
      inboundText: 'hello',
      responseText: '',
      createdAt: DateTime.utc(2026),
      type: 'inbound_received',
      channelDisplayName: 'QQBot Channel',
    );

    expect(event.displayTitle, 'QQBot Channel 私聊');
  });
}

class _FakeChannelQueue implements sdk.NapaxiChannelQueue {
  final records = <sdk.NapaxiChannelRecord>[];
  final inbound = <sdk.NapaxiChannelInboundMessage>[];
  final outbound = <sdk.NapaxiChannelOutboundMessage>[];
  final acked = <Map<String, dynamic>>[];
  final failed = <Map<String, dynamic>>[];

  @override
  List<sdk.NapaxiChannelRecord> list() => records;

  @override
  bool register(sdk.NapaxiChannelRegistration registration) {
    records.add(
      sdk.NapaxiChannelRecord(
        name: registration.name,
        type: registration.type,
        surfaceKind: registration.surfaceKind,
        endpointKind: registration.endpointKind,
        modalities: registration.modalities,
        contentFormats: registration.contentFormats,
        transport: registration.transport,
        capabilityId:
            registration.surfaceKind == sdk.NapaxiChannelSurfaceKind.device
                ? sdk.NapaxiChannelCapability.device
                : sdk.NapaxiChannelCapability.im,
        config: registration.config,
      ),
    );
    return true;
  }

  @override
  bool registerJson(String configJson) => true;

  @override
  bool unregister(String channelName) {
    records.removeWhere((record) => record.name == channelName);
    return true;
  }

  @override
  sdk.NapaxiChannelAcceptedReceipt submitInbound(
    sdk.NapaxiChannelInboundMessage message,
  ) {
    inbound.add(message);
    return sdk.NapaxiChannelAcceptedReceipt(
      accepted: true,
      id: message.platformMessageId ?? 'in-${inbound.length}',
    );
  }

  @override
  sdk.NapaxiChannelAcceptedReceipt submitInboundJson(String envelopeJson) {
    throw UnimplementedError();
  }

  @override
  List<sdk.NapaxiChannelInboundMessage> takeInbound(
    String channelName, {
    int limit = 20,
  }) =>
      inbound.take(limit).toList(growable: false);

  @override
  bool ackInbound(String inboundId) => true;

  @override
  bool failInbound(String inboundId, String error) => true;

  @override
  bool releaseInbound(String inboundId) => true;

  @override
  sdk.NapaxiChannelAcceptedReceipt enqueueOutbound(
    sdk.NapaxiChannelOutboundMessage message,
  ) {
    outbound.add(message);
    return sdk.NapaxiChannelAcceptedReceipt(
      accepted: true,
      id: message.id.isEmpty ? 'out-${outbound.length}' : message.id,
    );
  }

  @override
  sdk.NapaxiChannelAcceptedReceipt enqueueOutboundJson(String outboundJson) {
    throw UnimplementedError();
  }

  @override
  sdk.NapaxiChannelAcceptedReceipt replyInbound(
    String inboundId,
    sdk.NapaxiChannelOutboundMessage message,
  ) =>
      enqueueOutbound(message);

  @override
  sdk.NapaxiChannelAcceptedReceipt replyInboundJson(
    String inboundId,
    String replyJson,
  ) {
    throw UnimplementedError();
  }

  @override
  List<sdk.NapaxiChannelOutboundMessage> leaseOutbound(
    String channelName, {
    String? accountId,
    int limit = 20,
  }) {
    final selected = outbound
        .where(
          (message) =>
              message.channelName == channelName &&
              (accountId == null || message.accountId == accountId),
        )
        .take(limit)
        .toList(growable: false);
    outbound.removeWhere((message) => selected.contains(message));
    return selected;
  }

  @override
  bool ackOutbound(
    String outboundId, {
    Map<String, dynamic> receipt = const {},
  }) {
    acked.add({'id': outboundId, 'receipt': receipt});
    return true;
  }

  @override
  bool ackOutboundJson(String outboundId, String receiptJson) {
    throw UnimplementedError();
  }

  @override
  bool failOutbound(String outboundId, String error) {
    failed.add({'id': outboundId, 'error': error});
    return true;
  }
}
