import 'dart:io';

void main() {
  final root = Directory.current;
  final repo = root.parent.parent;
  final sdkProvider = _read(
    repo,
    'packages/flutter/lib/convenience/channel_bluetooth_headset_provider.dart',
  );
  final androidPlugin = _read(
    repo,
    'packages/flutter/android/src/main/kotlin/com/napaxi/flutter/NapaxiFlutterPlugin.kt',
  );
  final androidManifest = _read(
    repo,
    'packages/flutter/android/AndroidManifest.xml',
  );
  final demoClient = _read(root, 'lib/demo_client/napaxi_chat_client.dart');
  final chatScreen = _read(root, 'lib/screens/chat_screen.dart');
  final chatInput = _read(root, 'lib/widgets/chat_input.dart');
  final settings = _read(root, 'lib/panels/session_history.dart');
  final slash = _read(root, 'lib/screens/chat_screen_channel.dart');
  final docs = [
    _read(repo, 'docs/channel-provider-architecture.md'),
    _read(repo, 'docs/channel-capabilities.md'),
    _read(repo, 'docs/mobile-capabilities.md'),
  ].join('\n');

  final failures = <String>[];

  void has(String name, String source, String needle) {
    if (!source.contains(needle)) {
      failures.add('$name should contain: $needle');
    }
  }

  void lacks(String name, String source, String needle) {
    if (source.contains(needle)) {
      failures.add('$name should not contain: $needle');
    }
  }

  has('SDK platform audio', sdkProvider, 'class BluetoothHeadsetPlatformAudio');
  has('SDK microphone check', sdkProvider, 'checkMicrophonePermission');
  has('SDK speech capture method', sdkProvider, 'captureSpeechTranscript');
  has('SDK TTS method', sdkProvider, 'speakBluetoothReply');
  has('SDK provider factory', sdkProvider, 'withPlatformAudio');
  has(
    'SDK capture hook',
    sdkProvider,
    'captureTranscript: audio.captureTranscript',
  );
  has('SDK speech sink hook', sdkProvider, 'speechSink: audio.speak');
  has('SDK inbound normalization', sdkProvider, "'voice_transcript_final'");
  has('SDK speech markdown stripping', sdkProvider, '_spokenTextForOutbound');
  has(
    'SDK device surface',
    sdkProvider,
    'surfaceKind: NapaxiChannelSurfaceKind.device',
  );
  has('SDK device endpoint', sdkProvider, 'NapaxiChannelEndpointKind.device');
  has('SDK audio modality', sdkProvider, 'NapaxiChannelModality.audio');

  has(
    'Android microphone permission const',
    androidPlugin,
    'METHOD_CHECK_MICROPHONE_PERMISSION',
  );
  has(
    'Android capture method const',
    androidPlugin,
    'METHOD_CAPTURE_BLUETOOTH_TRANSCRIPT',
  );
  has(
    'Android speak method const',
    androidPlugin,
    'METHOD_SPEAK_BLUETOOTH_REPLY',
  );
  has(
    'Android permission request',
    androidPlugin,
    'Manifest.permission.RECORD_AUDIO',
  );
  has(
    'Android recognizer',
    androidPlugin,
    'SpeechRecognizer.createSpeechRecognizer',
  );
  has(
    'Android recognizer intent',
    androidPlugin,
    'RecognizerIntent.ACTION_RECOGNIZE_SPEECH',
  );
  has(
    'Android bluetooth route',
    androidPlugin,
    'prepareBluetoothSpeechInputRoute',
  );
  has(
    'Android route restore',
    androidPlugin,
    'restoreBluetoothSpeechInputRoute',
  );
  has('Android TTS', androidPlugin, 'TextToSpeech');
  has('Android TTS progress', androidPlugin, 'UtteranceProgressListener');
  has(
    'Android manifest record audio',
    androidManifest,
    'android.permission.RECORD_AUDIO',
  );
  has(
    'Android manifest bluetooth connect',
    androidManifest,
    'android.permission.BLUETOOTH_CONNECT',
  );
  has(
    'Android manifest speech query',
    androidManifest,
    'android.speech.RecognitionService',
  );

  has(
    'Demo provider factory use',
    demoClient,
    'BluetoothHeadsetChannelProvider.withPlatformAudio',
  );
  has(
    'Demo capture API',
    demoClient,
    'Future<DemoHeadsetTranscriptResult> captureHeadsetTranscript',
  );
  has(
    'Demo active input API',
    demoClient,
    'Future<List<DemoChannelInputSource>> listChannelInputSources',
  );
  has(
    'Demo active input agent filter',
    demoClient,
    '_demoStatusBelongsToAgent(status, normalizedAgentId)',
  );
  has(
    'Demo capture agent filter',
    demoClient,
    '_demoHeadsetCredentialsBelongsToAgent',
  );
  has('Demo captures via provider', demoClient, 'provider.captureAndSubmit()');
  has('Demo pumps core bridge', demoClient, 'await bridge?.pump()');
  has(
    'Demo pumps outbound delivery',
    demoClient,
    'await engine.channelProviders.pump(\n      sdk.BluetoothHeadsetChannelProvider.channelName',
  );
  has(
    'Demo route registration',
    demoClient,
    '_registerDemoHeadsetChannelRoute',
  );
  has(
    'Demo runtime config guard',
    demoClient,
    '_ensureDemoHeadsetChannelRuntimeConfig',
  );

  has('Settings voice action enum', settings, '_ChannelCardAction.voice');
  has('Settings voice action label', settings, "zh: '语音输入', en: 'Voice input'");
  has('Settings voice handler', settings, '_captureHeadsetChannel');
  has(
    'Settings calls capture API',
    settings,
    'client.captureHeadsetTranscript',
  );
  has('Settings connected gate', settings, 'status.connected');

  has('Chat screen input refresh', chatScreen, '_refreshChannelInputSources');
  has('Chat screen capture action', chatScreen, '_captureChannelInput');
  has(
    'Chat screen passes current agent',
    chatScreen,
    'agentId: _activeAgentId',
  );
  has(
    'Chat input voice button',
    chatInput,
    "Key('channel_voice_input_button')",
  );
  has('Chat input source picker', chatInput, 'class _ChannelInputPickerSheet');

  has('Slash ptt command', slash, "'ptt'");
  has('Slash help ptt', slash, '`/channel headset ptt`');
  has('Slash ptt implementation', slash, '_captureHeadsetTranscriptCommand');
  has(
    'Slash calls capture API with agent',
    slash,
    'client.captureHeadsetTranscript(\n      agentId: _activeAgentId,',
  );
  lacks(
    'Slash help should not advertise manual headset say',
    slash,
    '`/channel headset say <文本>`',
  );

  has(
    'Docs platform audio',
    docs,
    'first official platform-audio implementation',
  );
  has(
    'Docs full path',
    docs,
    'Android speech capture -> normalized channel inbound',
  );
  has('Docs core ownership', docs, 'core channel-agent');
  has('Docs host ownership', docs, 'adapter/host code rather than Rust core');

  if (failures.isNotEmpty) {
    stderr.writeln('Bluetooth device channel contract check failed:');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('Bluetooth device channel contract check passed.');
}

String _read(Directory root, String path) {
  final file = File('${root.path}/$path');
  if (!file.existsSync()) {
    throw StateError('Missing required file: ${file.path}');
  }
  return file.readAsStringSync();
}
