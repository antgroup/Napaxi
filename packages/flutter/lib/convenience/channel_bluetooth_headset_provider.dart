import 'dart:async';

import 'package:flutter/services.dart';

import '../api/channel_provider_host.dart';
import '../engine.dart';
import '../models/channel.dart';
import '../models/channel_provider.dart';

typedef BluetoothHeadsetStateProbe = Future<BluetoothHeadsetDeviceState>
    Function();
typedef BluetoothHeadsetTranscriptCapture = Future<BluetoothHeadsetTranscript?>
    Function(
  BluetoothHeadsetCaptureRequest request,
);
typedef BluetoothHeadsetSpeechSink = Future<BluetoothHeadsetSpeechReceipt>
    Function(
  BluetoothHeadsetSpeechRequest request,
);

class BluetoothHeadsetChannelCredentials {
  static const configVersionKey = 'config_version';
  static const deviceIdKey = 'device_id';
  static const deviceNameKey = 'device_name';
  static const accountIdKey = 'account_id';
  static const agentIdKey = 'agent_id';
  static const ttsEnabledKey = 'tts_enabled';

  static const configVersion = 1;
  static const defaultDeviceId = 'default_headset';
  static const defaultDeviceName = 'Bluetooth Device';
  static const defaultAccountId = 'headset';

  const BluetoothHeadsetChannelCredentials({
    this.deviceId = defaultDeviceId,
    this.deviceName = defaultDeviceName,
    this.accountId = defaultAccountId,
    this.agentId = NapaxiEngine.defaultAgentId,
    this.ttsEnabled = true,
  });

  factory BluetoothHeadsetChannelCredentials.fromMaps({
    Map<String, String> secrets = const {},
    Map<String, dynamic> config = const {},
  }) {
    return BluetoothHeadsetChannelCredentials(
      deviceId: _firstString([
        config[deviceIdKey],
        secrets[deviceIdKey],
        defaultDeviceId,
      ]),
      deviceName: _firstString([
        config[deviceNameKey],
        secrets[deviceNameKey],
        defaultDeviceName,
      ]),
      accountId: _firstString([
        config[accountIdKey],
        secrets[accountIdKey],
        defaultAccountId,
      ]),
      agentId: _firstString([config[agentIdKey], NapaxiEngine.defaultAgentId]),
      ttsEnabled: _asBool(config[ttsEnabledKey], fallback: true),
    );
  }

  final String deviceId;
  final String deviceName;
  final String accountId;
  final String agentId;
  final bool ttsEnabled;

  bool get isConfigured => deviceId.trim().isNotEmpty;

  Map<String, String> toSecretMap() => const {};

  Map<String, dynamic> toConfigMap() => {
        configVersionKey: configVersion,
        deviceIdKey:
            deviceId.trim().isEmpty ? defaultDeviceId : deviceId.trim(),
        deviceNameKey:
            deviceName.trim().isEmpty ? defaultDeviceName : deviceName.trim(),
        accountIdKey:
            accountId.trim().isEmpty ? defaultAccountId : accountId.trim(),
        agentIdKey: agentId.trim().isEmpty
            ? NapaxiEngine.defaultAgentId
            : agentId.trim(),
        ttsEnabledKey: ttsEnabled,
      };
}

class BluetoothDeviceKind {
  static const headset = 'headset';
  static const speaker = 'speaker';
  static const carAudio = 'car_audio';
  static const phone = 'phone';
  static const computer = 'computer';
  static const wearable = 'wearable';
  static const sensor = 'sensor';
  static const input = 'input';
  static const unknown = 'unknown';
}

class BluetoothDeviceProfile {
  static const a2dp = 'a2dp';
  static const headset = 'headset';
  static const hearingAid = 'hearing_aid';
  static const gatt = 'gatt';
  static const hid = 'hid';
  static const pan = 'pan';
  static const unknown = 'unknown';
}

class BluetoothDeviceCapability {
  static const audioInput = 'audio_input';
  static const audioOutput = 'audio_output';
  static const mediaControl = 'media_control';
  static const pushToTalk = 'push_to_talk';
  static const carContext = 'car_context';
}

class BluetoothDeviceRecommendedChannelKind {
  static const bluetoothAudio = 'bluetooth_audio';
  static const bluetoothCar = 'bluetooth_car';
  static const bluetoothControl = 'bluetooth_control';
  static const bluetoothSensor = 'bluetooth_sensor';
  static const a2a = 'a2a';
}

class BluetoothHeadsetDeviceInfo {
  const BluetoothHeadsetDeviceInfo({
    required this.id,
    required this.name,
    this.bonded = true,
    this.connected = false,
    this.deviceKind = BluetoothDeviceKind.unknown,
    this.profiles = const [],
    this.capabilities = const [],
    this.recommendedChannelKinds = const [],
    this.confidence = 0,
    this.warning,
    this.audioInputAvailable = true,
    this.audioOutputAvailable = true,
  });

  factory BluetoothHeadsetDeviceInfo.fromMap(Map<dynamic, dynamic> map) {
    final id = map['id']?.toString().trim() ?? '';
    final name = map['name']?.toString().trim() ?? '';
    final capabilities = _stringList(map['capabilities']);
    return BluetoothHeadsetDeviceInfo(
      id: id,
      name: name.isEmpty ? id : name,
      bonded: map['bonded'] != false,
      connected: map['connected'] == true,
      deviceKind:
          _firstString([map['device_kind'], BluetoothDeviceKind.unknown]),
      profiles: _stringList(map['profiles']),
      capabilities: capabilities,
      recommendedChannelKinds: _stringList(map['recommended_channel_kinds']),
      confidence: _asDouble(map['confidence']),
      warning: map['warning']?.toString(),
      audioInputAvailable:
          capabilities.contains(BluetoothDeviceCapability.audioInput) ||
              map['audio_input_available'] == true,
      audioOutputAvailable:
          capabilities.contains(BluetoothDeviceCapability.audioOutput) ||
              map['audio_output_available'] != false,
    );
  }

  final String id;
  final String name;
  final bool bonded;
  final bool connected;
  final String deviceKind;
  final List<String> profiles;
  final List<String> capabilities;
  final List<String> recommendedChannelKinds;
  final double confidence;
  final String? warning;
  final bool audioInputAvailable;
  final bool audioOutputAvailable;

  bool get canUseBluetoothAudioChannel {
    return recommendedChannelKinds.contains(
      BluetoothDeviceRecommendedChannelKind.bluetoothAudio,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bonded': bonded,
        'connected': connected,
        'device_kind': deviceKind,
        'profiles': profiles,
        'capabilities': capabilities,
        'recommended_channel_kinds': recommendedChannelKinds,
        'confidence': confidence,
        if (warning?.trim().isNotEmpty == true) 'warning': warning,
        'audio_input_available': audioInputAvailable,
        'audio_output_available': audioOutputAvailable,
      };
}

class BluetoothHeadsetDeviceDiscoveryResult {
  const BluetoothHeadsetDeviceDiscoveryResult({
    required this.supported,
    required this.permissionGranted,
    required this.devices,
    this.otherDevices = const [],
    this.error,
  });

  factory BluetoothHeadsetDeviceDiscoveryResult.fromMap(
    Map<dynamic, dynamic> map,
  ) {
    final rawDevices = map['devices'];
    final devices = rawDevices is Iterable
        ? rawDevices
            .whereType<Map>()
            .map(BluetoothHeadsetDeviceInfo.fromMap)
            .where((device) => device.id.trim().isNotEmpty)
            .toList(growable: false)
        : const <BluetoothHeadsetDeviceInfo>[];
    final rawOtherDevices = map['other_devices'];
    final otherDevices = rawOtherDevices is Iterable
        ? rawOtherDevices
            .whereType<Map>()
            .map(BluetoothHeadsetDeviceInfo.fromMap)
            .where((device) => device.id.trim().isNotEmpty)
            .toList(growable: false)
        : const <BluetoothHeadsetDeviceInfo>[];
    return BluetoothHeadsetDeviceDiscoveryResult(
      supported: map['supported'] != false,
      permissionGranted: map['permission_granted'] == true,
      devices: devices,
      otherDevices: otherDevices,
      error: map['error']?.toString(),
    );
  }

  final bool supported;
  final bool permissionGranted;

  /// Bluetooth audio devices suitable for the current audio channel provider.
  final List<BluetoothHeadsetDeviceInfo> devices;

  /// Paired Bluetooth devices that were discovered but should not default into
  /// the audio channel, such as phones, computers, car kits, or unknown devices.
  final List<BluetoothHeadsetDeviceInfo> otherDevices;
  final String? error;
}

class BluetoothHeadsetDeviceDiscovery {
  BluetoothHeadsetDeviceDiscovery({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('com.napaxi.flutter/bluetooth_headset');

  final MethodChannel _channel;

  Future<BluetoothHeadsetDeviceDiscoveryResult> listAudioDevices() async {
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'listAudioDevices',
      );
      if (response == null) {
        return const BluetoothHeadsetDeviceDiscoveryResult(
          supported: false,
          permissionGranted: false,
          devices: [],
          error: 'Bluetooth device discovery returned no response.',
        );
      }
      return BluetoothHeadsetDeviceDiscoveryResult.fromMap(response);
    } on MissingPluginException {
      return const BluetoothHeadsetDeviceDiscoveryResult(
        supported: false,
        permissionGranted: false,
        devices: [],
        error: 'Bluetooth device discovery is not available on this platform.',
      );
    } on PlatformException catch (error) {
      return BluetoothHeadsetDeviceDiscoveryResult(
        supported: true,
        permissionGranted: false,
        devices: const [],
        error: error.message ?? error.code,
      );
    }
  }
}

class BluetoothHeadsetPlatformAudio {
  BluetoothHeadsetPlatformAudio({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('com.napaxi.flutter/bluetooth_headset');

  final MethodChannel _channel;

  Future<bool> checkMicrophonePermission() async {
    try {
      return await _channel.invokeMethod<bool>('checkMicrophonePermission') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> requestMicrophonePermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestMicrophonePermission') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<BluetoothHeadsetTranscript?> captureTranscript(
    BluetoothHeadsetCaptureRequest request,
  ) async {
    var granted = await checkMicrophonePermission();
    if (!granted) granted = await requestMicrophonePermission();
    if (!granted) {
      throw StateError('Microphone permission is not granted.');
    }
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'captureSpeechTranscript',
        {
          'deviceId': request.deviceId,
          'deviceName': request.deviceName,
          'maxDurationMs': request.maxDuration.inMilliseconds,
        },
      );
      if (response == null) return null;
      final text = response['text']?.toString().trim() ?? '';
      if (text.isEmpty) return null;
      return BluetoothHeadsetTranscript(
        text: text,
        confidence: _asNullableDouble(response['confidence']),
        platformMessageId: response['platform_message_id']?.toString(),
        duration: _durationFromMillis(response['duration_ms']),
        raw: Map<String, dynamic>.from(response),
      );
    } on MissingPluginException {
      throw StateError(
        'Bluetooth device speech capture is not available on this platform.',
      );
    } on PlatformException catch (error) {
      throw StateError(error.message ?? error.code);
    }
  }

  Future<BluetoothHeadsetSpeechReceipt> speak(
    BluetoothHeadsetSpeechRequest request,
  ) async {
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'speakBluetoothReply',
        {
          'text': request.text,
          'spokenText': request.spokenText,
          'format': request.format,
          'deviceId': request.deviceId,
          'deviceName': request.deviceName,
          'outboundId': request.message.id,
        },
      );
      if (response == null) {
        return const BluetoothHeadsetSpeechReceipt.failed(
          'Bluetooth device speech output returned no response.',
        );
      }
      if (response['delivered'] == true) {
        final receipt = response['receipt'];
        return BluetoothHeadsetSpeechReceipt.delivered(
          receipt: receipt is Map
              ? Map<String, dynamic>.from(receipt)
              : Map<String, dynamic>.from(response),
        );
      }
      return BluetoothHeadsetSpeechReceipt.failed(
        response['error']?.toString() ?? 'Bluetooth device speech failed.',
      );
    } on MissingPluginException {
      return const BluetoothHeadsetSpeechReceipt.failed(
        'Bluetooth device speech output is not available on this platform.',
      );
    } on PlatformException catch (error) {
      return BluetoothHeadsetSpeechReceipt.failed(
        error.message ?? error.code,
      );
    }
  }
}

class BluetoothHeadsetDeviceState {
  const BluetoothHeadsetDeviceState({
    required this.connected,
    this.deviceId = BluetoothHeadsetChannelCredentials.defaultDeviceId,
    this.displayName = BluetoothHeadsetChannelCredentials.defaultDeviceName,
    this.audioInputAvailable = true,
    this.audioOutputAvailable = true,
    this.bluetoothPermissionGranted = true,
    this.microphonePermissionGranted = true,
    this.backgroundReady = false,
    this.raw = const {},
  });

  final bool connected;
  final String deviceId;
  final String displayName;
  final bool audioInputAvailable;
  final bool audioOutputAvailable;
  final bool bluetoothPermissionGranted;
  final bool microphonePermissionGranted;
  final bool backgroundReady;
  final Map<String, dynamic> raw;

  Map<String, dynamic> toJson() => {
        'connected': connected,
        'device_id': deviceId,
        'display_name': displayName,
        'audio_input_available': audioInputAvailable,
        'audio_output_available': audioOutputAvailable,
        'bluetooth_permission_granted': bluetoothPermissionGranted,
        'microphone_permission_granted': microphonePermissionGranted,
        'background_ready': backgroundReady,
        if (raw.isNotEmpty) 'raw': raw,
      };
}

class BluetoothHeadsetTranscript {
  const BluetoothHeadsetTranscript({
    required this.text,
    this.confidence,
    this.platformMessageId,
    this.duration,
    this.raw = const {},
  });

  final String text;
  final double? confidence;
  final String? platformMessageId;
  final Duration? duration;
  final Map<String, dynamic> raw;
}

class BluetoothHeadsetCaptureRequest {
  const BluetoothHeadsetCaptureRequest({
    required this.deviceId,
    required this.deviceName,
    required this.maxDuration,
  });

  final String deviceId;
  final String deviceName;
  final Duration maxDuration;
}

class BluetoothHeadsetSpeechRequest {
  const BluetoothHeadsetSpeechRequest({
    required this.text,
    required this.spokenText,
    required this.format,
    required this.deviceId,
    required this.deviceName,
    required this.message,
  });

  final String text;
  final String spokenText;
  final String format;
  final String deviceId;
  final String deviceName;
  final NapaxiChannelOutboundMessage message;
}

class BluetoothHeadsetSpeechReceipt {
  const BluetoothHeadsetSpeechReceipt.delivered({this.receipt = const {}})
      : delivered = true,
        error = null;

  const BluetoothHeadsetSpeechReceipt.failed(this.error)
      : delivered = false,
        receipt = const {};

  final bool delivered;
  final Map<String, dynamic> receipt;
  final String? error;
}

class BluetoothHeadsetPushToTalkResult {
  const BluetoothHeadsetPushToTalkResult({
    required this.submitted,
    this.receipt,
    this.transcript,
    this.error,
  });

  final bool submitted;
  final NapaxiChannelAcceptedReceipt? receipt;
  final BluetoothHeadsetTranscript? transcript;
  final String? error;
}

class BluetoothHeadsetChannelStatus {
  const BluetoothHeadsetChannelStatus({
    required this.connected,
    required this.configured,
    required this.manifest,
    this.channels = const [],
    this.deviceState,
    this.listening = false,
    this.mode = '',
    this.lastTranscript,
    this.lastSpokenText,
    this.lastError,
    this.inboundCount = 0,
    this.deliveredCount = 0,
  });

  final bool connected;
  final bool configured;
  final NapaxiChannelProviderManifest manifest;
  final List<NapaxiChannelRecord> channels;
  final BluetoothHeadsetDeviceState? deviceState;
  final bool listening;
  final String mode;
  final String? lastTranscript;
  final String? lastSpokenText;
  final String? lastError;
  final int inboundCount;
  final int deliveredCount;
}

class BluetoothHeadsetChannelProvider implements NapaxiChannelProvider {
  static const providerId = 'napaxi.bluetooth_headset.provider';
  static const channelName = 'bluetooth_headset';
  static const _defaultCaptureDuration = Duration(seconds: 20);

  static NapaxiChannelProviderManifest manifestFor(
    BluetoothHeadsetChannelCredentials? credentials,
  ) {
    final deviceId = credentials?.deviceId.trim().isNotEmpty == true
        ? credentials!.deviceId.trim()
        : BluetoothHeadsetChannelCredentials.defaultDeviceId;
    final deviceName = credentials?.deviceName.trim().isNotEmpty == true
        ? credentials!.deviceName.trim()
        : BluetoothHeadsetChannelCredentials.defaultDeviceName;
    return NapaxiChannelProviderManifest(
      providerId: providerId,
      channelName: channelName,
      displayName: 'Bluetooth Device Channel',
      description:
          'Push-to-talk Bluetooth audio device channel over the Napaxi provider contract.',
      accountId: credentials?.accountId.trim().isNotEmpty == true
          ? credentials!.accountId.trim()
          : BluetoothHeadsetChannelCredentials.defaultAccountId,
      surfaceKind: NapaxiChannelSurfaceKind.device,
      endpointKinds: const [NapaxiChannelEndpointKind.device],
      modalities: const [
        NapaxiChannelModality.audio,
        NapaxiChannelModality.text,
        NapaxiChannelModality.control,
        NapaxiChannelModality.presence,
      ],
      contentFormats: const [
        NapaxiChannelContentFormat.plainText,
        NapaxiChannelContentFormat.markdown,
      ],
      transport: 'bluetooth_headset_host_audio',
      authRequirements: const [
        'android_bluetooth_connect',
        'microphone_permission',
        'user_visible_push_to_talk',
      ],
      backgroundRequirements: const [
        'foreground_service_connected_device_optional',
        'foreground_service_microphone_optional',
        'foreground_service_media_playback_optional',
      ],
      config: {
        'device_id': deviceId,
        'device_name': deviceName,
        'agent_id': credentials?.agentId.trim().isNotEmpty == true
            ? credentials!.agentId.trim()
            : NapaxiEngine.defaultAgentId,
        'tts_enabled': credentials?.ttsEnabled ?? true,
        'ingress': 'voice_transcript_final',
        'outbound': 'tts_or_host_visible_reply',
      },
    );
  }

  BluetoothHeadsetChannelProvider(
    this.credentials, {
    this.stateProbe,
    BluetoothHeadsetDeviceDiscovery? deviceDiscovery,
    this.captureTranscript,
    this.speechSink,
  }) : _deviceDiscovery = deviceDiscovery ?? BluetoothHeadsetDeviceDiscovery();

  factory BluetoothHeadsetChannelProvider.withPlatformAudio(
    BluetoothHeadsetChannelCredentials credentials, {
    BluetoothHeadsetStateProbe? stateProbe,
    BluetoothHeadsetDeviceDiscovery? deviceDiscovery,
    BluetoothHeadsetPlatformAudio? platformAudio,
  }) {
    final audio = platformAudio ?? BluetoothHeadsetPlatformAudio();
    return BluetoothHeadsetChannelProvider(
      credentials,
      stateProbe: stateProbe,
      deviceDiscovery: deviceDiscovery,
      captureTranscript: audio.captureTranscript,
      speechSink: audio.speak,
    );
  }

  final BluetoothHeadsetChannelCredentials credentials;
  final BluetoothHeadsetStateProbe? stateProbe;
  final BluetoothHeadsetDeviceDiscovery _deviceDiscovery;
  final BluetoothHeadsetTranscriptCapture? captureTranscript;
  final BluetoothHeadsetSpeechSink? speechSink;

  @override
  NapaxiChannelProviderManifest get manifest => manifestFor(credentials);

  NapaxiChannelProviderContext? _context;
  BluetoothHeadsetDeviceState? _deviceState;
  bool _started = false;
  bool _listening = false;
  String? _lastTranscript;
  String? _lastSpokenText;
  String? _lastError;
  int _inboundCount = 0;
  int _deliveredCount = 0;

  BluetoothHeadsetChannelStatus status({
    List<NapaxiChannelRecord> channels = const [],
  }) {
    final state = _deviceState;
    return BluetoothHeadsetChannelStatus(
      connected: _started && (state?.connected ?? false),
      configured: credentials.isConfigured,
      manifest: manifest,
      channels: channels,
      deviceState: state,
      listening: _listening,
      mode: manifest.transport,
      lastTranscript: _lastTranscript,
      lastSpokenText: _lastSpokenText,
      lastError: _lastError,
      inboundCount: _inboundCount,
      deliveredCount: _deliveredCount,
    );
  }

  @override
  Future<void> start(NapaxiChannelProviderContext context) async {
    _context = context;
    _started = true;
    _lastError = null;
    if (!credentials.isConfigured) {
      _lastError = 'Bluetooth device id is not configured.';
      return;
    }
    await refreshDeviceState();
  }

  @override
  Future<void> stop() async {
    _started = false;
    _listening = false;
  }

  Future<BluetoothHeadsetDeviceState?> refreshDeviceState() async {
    final probe = stateProbe;
    try {
      _deviceState =
          probe == null ? await _probeBluetoothAudioState() : await probe();
      if (_deviceState?.connected == true) {
        _lastError = null;
      } else if (probe != null) {
        _lastError ??= 'Bluetooth device is not connected.';
      }
    } catch (error) {
      _lastError = 'Bluetooth device state probe failed: $error';
    }
    return _deviceState;
  }

  Future<BluetoothHeadsetDeviceState> _probeBluetoothAudioState() async {
    final result = await _deviceDiscovery.listAudioDevices();
    final selectedId = credentials.deviceId.trim();
    final selectedAudioDevice = _selectBluetoothAudioDevice(
      result.devices,
      selectedId,
    );
    final selectedOtherDevice = selectedAudioDevice == null
        ? _findBluetoothDevice(result.otherDevices, selectedId)
        : null;
    final selectedDevice = selectedAudioDevice ?? selectedOtherDevice;
    final connected = result.supported &&
        result.permissionGranted &&
        selectedAudioDevice != null &&
        selectedAudioDevice.connected &&
        selectedAudioDevice.canUseBluetoothAudioChannel;

    _lastError = connected
        ? null
        : _bluetoothAudioProbeError(
            result: result,
            selectedAudioDevice: selectedAudioDevice,
            selectedOtherDevice: selectedOtherDevice,
          );

    return BluetoothHeadsetDeviceState(
      connected: connected,
      deviceId: selectedDevice?.id.trim().isNotEmpty == true
          ? selectedDevice!.id
          : credentials.deviceId,
      displayName: selectedDevice?.name.trim().isNotEmpty == true
          ? selectedDevice!.name
          : credentials.deviceName,
      audioInputAvailable: selectedDevice?.audioInputAvailable ?? false,
      audioOutputAvailable: selectedDevice?.audioOutputAvailable ?? false,
      bluetoothPermissionGranted: result.permissionGranted,
      raw: {
        'supported': result.supported,
        'permission_granted': result.permissionGranted,
        'audio_device_count': result.devices.length,
        'other_device_count': result.otherDevices.length,
        if (result.error?.trim().isNotEmpty == true) 'error': result.error,
        if (selectedAudioDevice != null)
          'selected_audio_device': selectedAudioDevice.toJson(),
        if (selectedOtherDevice != null)
          'selected_other_device': selectedOtherDevice.toJson(),
      },
    );
  }

  BluetoothHeadsetDeviceInfo? _selectBluetoothAudioDevice(
    List<BluetoothHeadsetDeviceInfo> devices,
    String selectedId,
  ) {
    final explicit = selectedId.isNotEmpty &&
        selectedId != BluetoothHeadsetChannelCredentials.defaultDeviceId;
    if (explicit) {
      return _findBluetoothDevice(devices, selectedId);
    }
    for (final device in devices) {
      if (device.connected && device.canUseBluetoothAudioChannel) {
        return device;
      }
    }
    return devices.isEmpty ? null : devices.first;
  }

  BluetoothHeadsetDeviceInfo? _findBluetoothDevice(
    List<BluetoothHeadsetDeviceInfo> devices,
    String selectedId,
  ) {
    if (selectedId.trim().isEmpty) return null;
    final normalized = selectedId.trim().toLowerCase();
    for (final device in devices) {
      if (device.id.trim().toLowerCase() == normalized) return device;
    }
    return null;
  }

  String _bluetoothAudioProbeError({
    required BluetoothHeadsetDeviceDiscoveryResult result,
    required BluetoothHeadsetDeviceInfo? selectedAudioDevice,
    required BluetoothHeadsetDeviceInfo? selectedOtherDevice,
  }) {
    if (!result.supported) {
      return result.error?.trim().isNotEmpty == true
          ? 'Bluetooth device discovery is unavailable: ${result.error}'
          : 'Bluetooth device discovery is unavailable on this platform.';
    }
    if (!result.permissionGranted) {
      return result.error?.trim().isNotEmpty == true
          ? 'Bluetooth permission is not granted: ${result.error}'
          : 'Bluetooth permission is not granted.';
    }
    if (selectedOtherDevice != null) {
      return 'Selected Bluetooth device is paired, but it is not currently '
          'connected as an audio channel.';
    }
    if (selectedAudioDevice == null) {
      return 'Selected Bluetooth device is not currently connected as an '
          'audio device.';
    }
    if (!selectedAudioDevice.connected) {
      return 'Selected Bluetooth device is not connected.';
    }
    return 'Selected Bluetooth device is not suitable for the Bluetooth audio '
        'channel.';
  }

  Future<BluetoothHeadsetPushToTalkResult> captureAndSubmit({
    Duration maxDuration = _defaultCaptureDuration,
  }) async {
    final capture = captureTranscript;
    if (capture == null) {
      const error = 'Bluetooth device transcript capture is not configured.';
      _lastError = error;
      return const BluetoothHeadsetPushToTalkResult(
        submitted: false,
        error: error,
      );
    }
    _listening = true;
    try {
      final state = await refreshDeviceState();
      final transcript = await capture(
        BluetoothHeadsetCaptureRequest(
          deviceId: (state?.deviceId.trim().isNotEmpty == true)
              ? state!.deviceId.trim()
              : credentials.deviceId.trim(),
          deviceName: (state?.displayName.trim().isNotEmpty == true)
              ? state!.displayName.trim()
              : credentials.deviceName.trim(),
          maxDuration: maxDuration,
        ),
      );
      if (transcript == null || transcript.text.trim().isEmpty) {
        const error = 'Bluetooth device transcript was empty.';
        _lastError = error;
        return const BluetoothHeadsetPushToTalkResult(
          submitted: false,
          error: error,
        );
      }
      final receipt = submitVoiceTranscript(transcript);
      return BluetoothHeadsetPushToTalkResult(
        submitted: receipt.accepted,
        receipt: receipt,
        transcript: transcript,
        error: receipt.error,
      );
    } catch (error) {
      _lastError = 'Bluetooth device capture failed: $error';
      return BluetoothHeadsetPushToTalkResult(
        submitted: false,
        error: _lastError,
      );
    } finally {
      _listening = false;
    }
  }

  NapaxiChannelAcceptedReceipt submitVoiceTranscript(
    BluetoothHeadsetTranscript transcript,
  ) {
    final text = transcript.text.trim();
    if (text.isEmpty) {
      throw ArgumentError.value(transcript.text, 'transcript.text');
    }
    final context = _requireContext();
    final state = _deviceState;
    final deviceId = (state?.deviceId.trim().isNotEmpty == true)
        ? state!.deviceId.trim()
        : credentials.deviceId.trim();
    final deviceName = (state?.displayName.trim().isNotEmpty == true)
        ? state!.displayName.trim()
        : credentials.deviceName.trim();
    final messageId = transcript.platformMessageId?.trim().isNotEmpty == true
        ? transcript.platformMessageId!.trim()
        : 'headset-${DateTime.now().microsecondsSinceEpoch}';
    final receipt = context.submitTextInbound(
      peer: NapaxiChannelPeer(
        kind: NapaxiChannelEndpointKind.device,
        id: deviceId,
        displayName: deviceName,
      ),
      sender: NapaxiChannelActor(
        id: '$deviceId:user',
        displayName: 'Headset user',
      ),
      platformMessageId: messageId,
      threadId: deviceId,
      text: text,
      raw: {
        'type': 'voice_transcript_final',
        'source': 'bluetooth_headset',
        'device_id': deviceId,
        'device_name': deviceName,
        if (transcript.confidence != null) 'confidence': transcript.confidence,
        if (transcript.duration != null)
          'duration_ms': transcript.duration!.inMilliseconds,
        if (transcript.raw.isNotEmpty) 'host': transcript.raw,
      },
    );
    if (receipt.accepted) {
      _inboundCount += 1;
      _lastTranscript = text;
      _lastError = null;
    } else {
      _lastError = receipt.error ?? 'Bluetooth device inbound was rejected.';
    }
    return receipt;
  }

  @override
  Future<NapaxiChannelOutboundDeliveryResult> deliverOutbound(
    NapaxiChannelOutboundMessage message,
  ) async {
    final text = message.text?.trim() ?? '';
    if (text.isEmpty) {
      return const NapaxiChannelOutboundDeliveryResult.failed(
        'Bluetooth device outbound requires text.',
      );
    }
    if (!credentials.ttsEnabled) {
      _deliveredCount += 1;
      _lastSpokenText = text;
      return const NapaxiChannelOutboundDeliveryResult.delivered(
        receipt: {'tts_skipped': true},
      );
    }
    final spokenText = _spokenTextForOutbound(text, message.format);
    final state = _deviceState;
    final deviceId = (state?.deviceId.trim().isNotEmpty == true)
        ? state!.deviceId.trim()
        : credentials.deviceId.trim();
    final deviceName = (state?.displayName.trim().isNotEmpty == true)
        ? state!.displayName.trim()
        : credentials.deviceName.trim();
    final sink = speechSink;
    if (sink == null) {
      _deliveredCount += 1;
      _lastSpokenText = spokenText;
      return NapaxiChannelOutboundDeliveryResult.delivered(
        receipt: {
          'tts_sink': 'not_configured',
          'device_id': deviceId,
          'device_name': deviceName,
          'spoken_text': spokenText,
        },
      );
    }
    final receipt = await sink(
      BluetoothHeadsetSpeechRequest(
        text: text,
        spokenText: spokenText,
        format: message.format?.trim().isNotEmpty == true
            ? message.format!.trim()
            : NapaxiChannelContentFormat.plainText,
        deviceId: deviceId,
        deviceName: deviceName,
        message: message,
      ),
    );
    if (!receipt.delivered) {
      _lastError = receipt.error ?? 'Bluetooth device speech failed.';
      return NapaxiChannelOutboundDeliveryResult.failed(_lastError!);
    }
    _deliveredCount += 1;
    _lastSpokenText = spokenText;
    _lastError = null;
    return NapaxiChannelOutboundDeliveryResult.delivered(
      receipt: {
        'device_id': deviceId,
        'device_name': deviceName,
        'spoken_text': spokenText,
        ...receipt.receipt,
      },
    );
  }

  NapaxiChannelProviderContext _requireContext() {
    final context = _context;
    if (context == null || !_started) {
      throw StateError('Bluetooth device provider is not started.');
    }
    return context;
  }
}

String _spokenTextForOutbound(String text, String? format) {
  if (format != NapaxiChannelContentFormat.markdown) return text;
  return text
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' code block ')
      .replaceAllMapped(RegExp(r'`([^`]+)`'), (match) => match.group(1) ?? '')
      .replaceAllMapped(
        RegExp(r'(\*\*|__)(.*?)\1'),
        (match) => match.group(2) ?? '',
      )
      .replaceAllMapped(
        RegExp(r'(\*|_)(.*?)\1'),
        (match) => match.group(2) ?? '',
      )
      .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
      .replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^)]+\)'),
        (match) => match.group(1) ?? '',
      )
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String _firstString(List<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
  }
  return '';
}

bool _asBool(Object? value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
  }
  return fallback;
}

List<String> _stringList(Object? value) {
  if (value is Iterable) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? const [] : [text];
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? 0;
  return 0;
}

double? _asNullableDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

Duration? _durationFromMillis(Object? value) {
  if (value is int) return Duration(milliseconds: value);
  if (value is num) return Duration(milliseconds: value.toInt());
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) return Duration(milliseconds: parsed);
  }
  return null;
}
