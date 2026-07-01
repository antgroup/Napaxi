import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/config.dart';

/// Persisted LLM profile metadata.
///
/// Sensitive values such as API keys are intentionally excluded from this
/// object and are stored separately by [NapaxiConfigStore].
class NapaxiConfigProfile {
  const NapaxiConfigProfile({
    required this.id,
    required this.name,
    required this.provider,
    required this.model,
    this.baseUrl,
    this.systemPrompt = '',
    this.maxTokens = defaultMaxTokens,
    this.maxToolIterations = 50,
    this.extraHeaders,
    this.userTimezone,
    this.allowedModels,
    this.imageModel,
    this.imageAnalysisModel,
    this.videoModel,
    this.audioModel,
    this.contextEngine = const ContextEngineConfig(),
    this.shellSecurity = const ShellSecurityConfig(),
    this.metadata = const {},
  });

  final String id;
  final String name;
  final String provider;
  final String? baseUrl;
  final String model;
  final String systemPrompt;
  final int maxTokens;
  final int maxToolIterations;
  final String? extraHeaders;
  final String? userTimezone;
  final List<Map<String, String>>? allowedModels;
  final String? imageModel;
  final String? imageAnalysisModel;
  final String? videoModel;
  final String? audioModel;
  final ContextEngineConfig contextEngine;
  final ShellSecurityConfig shellSecurity;
  final Map<String, Object?> metadata;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'provider': provider,
        'base_url': baseUrl,
        'model': model,
        'max_tokens': maxTokens,
        'max_tool_iterations': maxToolIterations,
        'extra_headers': extraHeaders,
        if (userTimezone != null && userTimezone!.trim().isNotEmpty)
          'user_timezone': userTimezone,
        if (systemPrompt.trim().isNotEmpty) 'system_prompt': systemPrompt,
        if (allowedModels != null) 'allowed_models': allowedModels,
        if (imageModel != null) 'image_model': imageModel,
        if (imageAnalysisModel != null)
          'image_analysis_model': imageAnalysisModel,
        if (videoModel != null) 'video_model': videoModel,
        if (audioModel != null) 'audio_model': audioModel,
        'context_engine': contextEngine.toMap(),
        'shell_security': shellSecurity.toMap(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory NapaxiConfigProfile.fromMap(Map<String, Object?> map) {
    return NapaxiConfigProfile(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      provider: map['provider'] as String? ?? '',
      baseUrl: map['base_url'] as String?,
      model: map['model'] as String? ?? '',
      systemPrompt: map['system_prompt'] as String? ?? '',
      maxTokens: map['max_tokens'] as int? ?? defaultMaxTokens,
      maxToolIterations: map['max_tool_iterations'] as int? ?? 50,
      extraHeaders: map['extra_headers'] as String?,
      userTimezone: map['user_timezone'] as String? ??
          map['userTimeZone'] as String? ??
          map['timeZoneId'] as String?,
      allowedModels: (map['allowed_models'] as List?)
          ?.map((e) => Map<String, String>.from(e as Map))
          .toList(),
      imageModel: map['image_model'] as String?,
      imageAnalysisModel: map['image_analysis_model'] as String?,
      videoModel: map['video_model'] as String?,
      audioModel: map['audio_model'] as String?,
      contextEngine: map['context_engine'] is Map
          ? ContextEngineConfig.fromMap(
              Map<String, dynamic>.from(map['context_engine'] as Map),
            )
          : const ContextEngineConfig(),
      shellSecurity: map['shell_security'] is Map
          ? ShellSecurityConfig.fromMap(
              Map<String, dynamic>.from(map['shell_security'] as Map),
            )
          : const ShellSecurityConfig(),
      metadata: Map<String, Object?>.from(
        map['metadata'] as Map? ?? const {},
      ),
    );
  }

  LlmConfig toConfig({required String apiKey}) {
    return LlmConfig(
      provider: provider,
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: model,
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
      maxToolIterations: maxToolIterations,
      extraHeaders: extraHeaders,
      userTimezone: userTimezone,
      allowedModels: allowedModels,
      imageModel: imageModel,
      imageAnalysisModel: imageAnalysisModel,
      videoModel: videoModel,
      audioModel: audioModel,
      contextEngine: contextEngine,
      shellSecurity: shellSecurity,
    );
  }
}

/// The user's active configuration selection: chosen profile(s), system
/// prompt, and tool-iteration limit.
class NapaxiConfigSelection {
  const NapaxiConfigSelection({
    this.selectedProfileId,
    this.selectedProfileIdByCapability = const {},
    this.systemPrompt = '',
    this.maxToolIterations = 50,
  });

  final String? selectedProfileId;
  final Map<String, String> selectedProfileIdByCapability;
  final String systemPrompt;
  final int maxToolIterations;

  Map<String, Object?> toMap() => {
        'selected_profile_id': selectedProfileId,
        'selected_profile_id_by_capability': selectedProfileIdByCapability,
        'system_prompt': systemPrompt,
        'max_tool_iterations': maxToolIterations,
      };

  factory NapaxiConfigSelection.fromMap(Map<String, Object?> map) {
    return NapaxiConfigSelection(
      selectedProfileId: map['selected_profile_id'] as String?,
      selectedProfileIdByCapability: Map<String, String>.from(
        map['selected_profile_id_by_capability'] as Map? ?? const {},
      ),
      systemPrompt: map['system_prompt'] as String? ?? '',
      maxToolIterations: map['max_tool_iterations'] as int? ?? 50,
    );
  }
}

/// Storage seam for non-secret config values (profiles, selection).
abstract class NapaxiConfigKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Secure-storage seam for sensitive config values such as API keys.
abstract class NapaxiConfigSecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Persists LLM config profiles and the active selection, splitting non-secret
/// values and secrets (API keys) across separate backing stores.
class NapaxiConfigStore {
  NapaxiConfigStore({
    required NapaxiConfigKeyValueStore keyValueStore,
    required NapaxiConfigSecretStore secretStore,
  })  : _keyValueStore = keyValueStore,
        _secretStore = secretStore;

  NapaxiConfigStore.memory()
      : this(
          keyValueStore: _MemoryConfigStore(),
          secretStore: _MemoryConfigStore(),
        );

  static final NapaxiConfigStore instance = NapaxiConfigStore(
    keyValueStore: _SharedPreferencesConfigStore(),
    secretStore: _FlutterSecureConfigStore(),
  );

  static const _profilesKey = 'napaxi.config.profiles.v1';
  static const _selectionKey = 'napaxi.config.selection.v1';
  static const _apiKeyPrefix = 'napaxi.config.api_key.';

  final NapaxiConfigKeyValueStore _keyValueStore;
  final NapaxiConfigSecretStore _secretStore;

  Future<List<NapaxiConfigProfile>> loadProfiles() async {
    final raw = await _keyValueStore.read(_profilesKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => NapaxiConfigProfile.fromMap(
              Map<String, Object?>.from(item),
            ))
        .where((profile) => profile.id.trim().isNotEmpty)
        .toList();
  }

  Future<void> saveProfile(
    NapaxiConfigProfile profile, {
    String? apiKey,
  }) async {
    final profiles = await loadProfiles();
    final nextProfiles = [
      for (final item in profiles)
        if (item.id != profile.id) item,
      profile,
    ];
    await _saveProfiles(nextProfiles);
    if (apiKey != null) {
      if (apiKey.isEmpty) {
        await _secretStore.delete(_apiKeyKey(profile.id));
      } else {
        await _secretStore.write(_apiKeyKey(profile.id), apiKey);
      }
    }
  }

  Future<void> deleteProfile(String profileId) async {
    final profiles = await loadProfiles();
    await _saveProfiles(
      profiles.where((profile) => profile.id != profileId).toList(),
    );
    await _secretStore.delete(_apiKeyKey(profileId));
    final selection = await loadSelection();
    final nextCapabilitySelection =
        Map<String, String>.from(selection.selectedProfileIdByCapability)
          ..removeWhere((_, selectedId) => selectedId == profileId);
    await saveSelection(NapaxiConfigSelection(
      selectedProfileId: selection.selectedProfileId == profileId
          ? null
          : selection.selectedProfileId,
      selectedProfileIdByCapability: nextCapabilitySelection,
      systemPrompt: selection.systemPrompt,
      maxToolIterations: selection.maxToolIterations,
    ));
  }

  Future<NapaxiConfigSelection> loadSelection() async {
    final profiles = await loadProfiles();
    final profileIds = profiles.map((profile) => profile.id).toSet();
    final raw = await _keyValueStore.read(_selectionKey);
    if (raw == null || raw.trim().isEmpty) {
      return const NapaxiConfigSelection();
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const NapaxiConfigSelection();
    final selection = NapaxiConfigSelection.fromMap(
      Map<String, Object?>.from(decoded),
    );
    return _normalizeSelection(selection, profileIds);
  }

  Future<void> saveSelection(NapaxiConfigSelection selection) async {
    final profiles = await loadProfiles();
    final profileIds = profiles.map((profile) => profile.id).toSet();
    final normalized = _normalizeSelection(selection, profileIds);
    await _keyValueStore.write(_selectionKey, jsonEncode(normalized.toMap()));
  }

  Future<LlmConfig?> resolveConfig(String profileId) async {
    final profiles = await loadProfiles();
    NapaxiConfigProfile? selectedProfile;
    for (final profile in profiles) {
      if (profile.id == profileId) {
        selectedProfile = profile;
        break;
      }
    }
    if (selectedProfile == null) return null;
    String apiKey;
    try {
      apiKey = await _secretStore.read(_apiKeyKey(profileId)) ?? '';
    } catch (_) {
      apiKey = '';
    }
    return selectedProfile.toConfig(apiKey: apiKey);
  }

  Future<String> readApiKey(String profileId) async {
    try {
      return await _secretStore.read(_apiKeyKey(profileId)) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _saveProfiles(List<NapaxiConfigProfile> profiles) {
    return _keyValueStore.write(
      _profilesKey,
      jsonEncode(profiles.map((profile) => profile.toMap()).toList()),
    );
  }

  NapaxiConfigSelection _normalizeSelection(
    NapaxiConfigSelection selection,
    Set<String> profileIds,
  ) {
    final selectedProfileId = profileIds.contains(selection.selectedProfileId)
        ? selection.selectedProfileId
        : null;
    final capabilitySelection =
        Map<String, String>.from(selection.selectedProfileIdByCapability)
          ..removeWhere((_, profileId) => !profileIds.contains(profileId));
    return NapaxiConfigSelection(
      selectedProfileId: selectedProfileId,
      selectedProfileIdByCapability: capabilitySelection,
      systemPrompt: selection.systemPrompt,
      maxToolIterations: selection.maxToolIterations,
    );
  }

  String _apiKeyKey(String profileId) => '$_apiKeyPrefix$profileId';
}

class _SharedPreferencesConfigStore implements NapaxiConfigKeyValueStore {
  @override
  Future<String?> read(String key) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(key);
  }

  @override
  Future<void> write(String key, String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, value);
  }

  @override
  Future<void> delete(String key) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(key);
  }
}

class _FlutterSecureConfigStore implements NapaxiConfigSecretStore {
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class _MemoryConfigStore
    implements NapaxiConfigKeyValueStore, NapaxiConfigSecretStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
