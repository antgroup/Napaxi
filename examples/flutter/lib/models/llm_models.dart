part of '../main.dart';

enum ModelCapability {
  chat,
  imageAnalysis,
  imageGeneration,
  videoGeneration,
  audioAnalysis,
}

const List<ModelCapability> _modelCapabilities = [
  ModelCapability.imageAnalysis,
  ModelCapability.imageGeneration,
  ModelCapability.videoGeneration,
  ModelCapability.audioAnalysis,
];

String _capabilityLabel(BuildContext context, ModelCapability capability) {
  final strings = AppStrings.of(context);
  return switch (capability) {
    ModelCapability.chat => strings.capabilityChat,
    ModelCapability.imageAnalysis => strings.capabilityImageAnalysis,
    ModelCapability.imageGeneration => strings.capabilityImageGeneration,
    ModelCapability.videoGeneration => strings.capabilityVideoGeneration,
    ModelCapability.audioAnalysis => strings.capabilityAudioAnalysis,
  };
}

class ModelEntry {
  const ModelEntry({
    required this.id,
    this.displayName = '',
    this.capabilities = const [ModelCapability.chat],
  });

  final String id;
  final String displayName;
  final List<ModelCapability> capabilities;

  String get label {
    final trimmed = displayName.trim();
    return trimmed.isEmpty ? id.trim() : trimmed;
  }

  bool supports(ModelCapability capability) {
    return capabilities.contains(capability);
  }

  ModelEntry copyWith({
    String? id,
    String? displayName,
    List<ModelCapability>? capabilities,
  }) {
    return ModelEntry(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      capabilities: capabilities ?? this.capabilities,
    );
  }
}

class LlmModelProfile {
  const LlmModelProfile({
    required this.id,
    required this.name,
    this.provider = '',
    this.baseUrl = '',
    this.apiKey = '',
    String model = '',
    this.models = const [],
    this.selectedModelByCapability = const {},
    this.selectedProfileByCapability = const {},
    this.systemPrompt = '',
    this.maxTokens = sdk.defaultMaxTokens,
    this.contextWindowTokens,
    this.nativeContextWindowTokens,
    this.responseReserveTokens,
    this.compactionModel = '',
    this.preCompactionMemoryFlush = false,
  }) : _defaultChatModel = model;

  final String id;
  final String name;
  final String provider;
  final String baseUrl;
  final String apiKey;
  final String _defaultChatModel;
  final List<ModelEntry> models;
  final Map<ModelCapability, String> selectedModelByCapability;
  final Map<ModelCapability, LlmModelProfile> selectedProfileByCapability;
  final String systemPrompt;
  final int maxTokens;
  final int? contextWindowTokens;
  final int? nativeContextWindowTokens;
  final int? responseReserveTokens;
  final String compactionModel;
  final bool preCompactionMemoryFlush;

  String get model => selectedModel(ModelCapability.chat) ?? _defaultChatModel;

  bool get hasModel => model.trim().isNotEmpty;

  bool supports(ModelCapability capability) {
    if (capability == ModelCapability.chat) return hasModel;
    return models.any((entry) => entry.supports(capability));
  }

  String? selectedModel(ModelCapability capability) {
    final selected = selectedModelByCapability[capability]?.trim();
    if (selected != null && selected.isNotEmpty) return selected;
    if (capability == ModelCapability.chat &&
        _defaultChatModel.trim().isNotEmpty) {
      return _defaultChatModel.trim();
    }
    for (final entry in models) {
      if (entry.supports(capability) && entry.id.trim().isNotEmpty) {
        return entry.id.trim();
      }
    }
    return null;
  }

  String get displayName {
    final trimmedName = name.trim();
    if (trimmedName.isNotEmpty) return trimmedName;
    final trimmedModel = model.trim();
    if (trimmedModel.isNotEmpty) return trimmedModel;
    return 'Untitled model';
  }

  String get subtitle {
    final parts = [
      provider.trim(),
      model.trim(),
    ].where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? baseUrl.trim() : parts.join(' · ');
  }
}

extension LlmModelProfileSdkConfig on LlmModelProfile {
  sdk.LlmConfig toSdkConfig({
    String responseLanguage = 'en',
    String? userTimezone,
  }) {
    final imageAnalysisModel = selectedModel(ModelCapability.imageAnalysis);
    final imageModel = selectedModel(ModelCapability.imageGeneration);
    final videoModel = selectedModel(ModelCapability.videoGeneration);
    final audioModel = selectedModel(ModelCapability.audioAnalysis);
    final capabilityConfigs = <String, sdk.LlmCapabilityConfig>{};
    for (final capability in _modelCapabilities) {
      final capabilityProfile = selectedProfileByCapability[capability] ?? this;
      final modelId =
          capabilityProfile.selectedModel(capability) ??
          selectedModel(capability);
      if (modelId == null || modelId.trim().isEmpty) continue;
      capabilityConfigs[capability.name] = sdk.LlmCapabilityConfig(
        provider: capabilityProfile._sdkProvider,
        apiKey: capabilityProfile.apiKey.trim(),
        baseUrl: capabilityProfile.baseUrl.trim().isEmpty
            ? null
            : capabilityProfile.baseUrl.trim(),
        model: modelId.trim(),
        maxTokens: capabilityProfile.maxTokens,
      );
    }
    return sdk.LlmConfig(
      provider: _sdkProvider,
      apiKey: apiKey.trim(),
      baseUrl: baseUrl.trim().isEmpty ? null : baseUrl.trim(),
      model: model.trim(),
      systemPrompt: systemPrompt.trim().isEmpty
          ? _defaultSystemPrompt(responseLanguage)
          : systemPrompt.trim(),
      responseLanguage: _normalizedResponseLanguage(responseLanguage),
      maxTokens: maxTokens,
      userTimezone: userTimezone?.trim().isEmpty == true
          ? null
          : userTimezone?.trim(),
      imageAnalysisModel:
          imageAnalysisModel == null || imageAnalysisModel.trim().isEmpty
          ? null
          : imageAnalysisModel.trim(),
      imageModel: imageModel == null || imageModel.trim().isEmpty
          ? null
          : imageModel.trim(),
      videoModel: videoModel == null || videoModel.trim().isEmpty
          ? null
          : videoModel.trim(),
      audioModel: audioModel == null || audioModel.trim().isEmpty
          ? null
          : audioModel.trim(),
      capabilityConfigs: capabilityConfigs.isEmpty ? null : capabilityConfigs,
      contextEngine: sdk.ContextEngineConfig(
        contextWindowTokens: contextWindowTokens,
        nativeContextWindowTokens: nativeContextWindowTokens,
        responseReserveTokens: responseReserveTokens,
        compactionModel: compactionModel.trim().isEmpty
            ? null
            : compactionModel.trim(),
        preCompactionMemoryFlush: preCompactionMemoryFlush,
      ),
      // Demo posture: only the hard gate is in play, everything else runs
      // without an approval prompt (the demo workspace is the blast radius).
      shellSecurity: const sdk.ShellSecurityConfig(
        approvalMode: sdk.ShellApprovalMode.trustedAllow,
      ),
    );
  }

  String _defaultSystemPrompt(String responseLanguage) {
    final normalized = _normalizedResponseLanguage(responseLanguage);
    return switch (normalized) {
      'zh' => '你是 napaxi，一个有帮助的 AI 助手。',
      _ => 'You are napaxi, a helpful AI assistant.',
    };
  }

  String get _sdkProvider {
    final normalized = provider.trim().toLowerCase();
    return switch (normalized) {
      'openai-compatible' ||
      'deepseek' ||
      'qwen' ||
      'moonshot' => 'openai_compatible',
      _ => normalized,
    };
  }
}

String _normalizedResponseLanguage(String language) {
  final normalized = language.trim().toLowerCase();
  return normalized == 'zh' || normalized == 'zh-cn' || normalized == 'chinese'
      ? 'zh'
      : 'en';
}

class LlmProviderOption {
  const LlmProviderOption({
    required this.id,
    required this.name,
    required this.provider,
    required this.baseUrl,
    required this.defaultModel,
    required this.models,
  });

  final String id;
  final String name;
  final String provider;
  final String baseUrl;
  final String defaultModel;
  final List<String> models;
}

const List<LlmProviderOption> _providerOptions = [
  LlmProviderOption(
    id: 'openai-compatible',
    name: 'OpenAI-compatible',
    provider: 'openai-compatible',
    baseUrl: '',
    defaultModel: '',
    models: [],
  ),
  LlmProviderOption(
    id: 'openai',
    name: 'OpenAI',
    provider: 'openai',
    baseUrl: 'https://api.openai.com/v1',
    defaultModel: '',
    models: [],
  ),
  LlmProviderOption(
    id: 'qwen',
    name: 'Qwen',
    provider: 'qwen',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    defaultModel: '',
    models: [],
  ),
  LlmProviderOption(
    id: 'deepseek',
    name: 'DeepSeek',
    provider: 'deepseek',
    baseUrl: 'https://api.deepseek.com/v1',
    defaultModel: 'deepseek-chat',
    models: ['deepseek-chat', 'deepseek-reasoner'],
  ),
  LlmProviderOption(
    id: 'moonshot',
    name: 'Moonshot',
    provider: 'moonshot',
    baseUrl: 'https://api.moonshot.cn/v1',
    defaultModel: '',
    models: [],
  ),
  LlmProviderOption(
    id: 'custom',
    name: 'Custom',
    provider: '',
    baseUrl: '',
    defaultModel: '',
    models: [],
  ),
];

LlmProviderOption? _optionForProvider(String provider) {
  final normalizedProvider = provider.trim().toLowerCase();
  if (normalizedProvider.isEmpty) return null;
  for (final option in _providerOptions) {
    if (option.provider == normalizedProvider ||
        option.id == normalizedProvider) {
      return option;
    }
  }
  return null;
}

class LlmConfigState {
  const LlmConfigState({
    this.profiles = const [],
    this.selectedProfileId,
    this.selectedProfileIdByCapability = const {},
    this.systemPrompt = '',
    this.maxToolIterations = 50,
  });

  final List<LlmModelProfile> profiles;
  final String? selectedProfileId;
  final Map<ModelCapability, String> selectedProfileIdByCapability;
  final String systemPrompt;
  final int maxToolIterations;

  LlmModelProfile? profileById(String? profileId) {
    final id = profileId?.trim();
    if (id == null || id.isEmpty) return null;
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  LlmModelProfile? selectedProfileFor(ModelCapability capability) {
    final selectedCapabilityProfileId =
        selectedProfileIdByCapability[capability]?.trim();
    if (selectedCapabilityProfileId != null &&
        selectedCapabilityProfileId.isNotEmpty) {
      for (final profile in profiles) {
        if (profile.id == selectedCapabilityProfileId &&
            profile.supports(capability)) {
          return profile;
        }
      }
    }
    if (capability == ModelCapability.chat && selectedProfileId != null) {
      for (final profile in profiles) {
        if (profile.id == selectedProfileId &&
            profile.supports(ModelCapability.chat)) {
          return profile;
        }
      }
    }
    for (final profile in profiles) {
      if (profile.supports(capability)) return profile;
    }
    return null;
  }

  LlmModelProfile? get selectedProfile {
    final chatProfile = selectedProfileFor(ModelCapability.chat);
    if (chatProfile != null) return chatProfile;
    for (final profile in profiles) {
      if (profile.id == selectedProfileId) return profile;
    }
    return profiles.isEmpty ? null : profiles.first;
  }

  LlmModelProfile? runtimeProfileFor({String? chatProfileId}) {
    final overrideProfile = profileById(chatProfileId);
    final chatProfile =
        overrideProfile != null &&
            overrideProfile.supports(ModelCapability.chat)
        ? overrideProfile
        : selectedProfileFor(ModelCapability.chat);
    if (chatProfile == null) return null;
    final selectedModels = <ModelCapability, String>{};
    final selectedProfiles = <ModelCapability, LlmModelProfile>{};
    for (final capability in _modelCapabilities) {
      final profile = capability == ModelCapability.chat
          ? chatProfile
          : selectedProfileFor(capability);
      final model = profile?.selectedModel(capability)?.trim();
      if (model != null && model.isNotEmpty) {
        selectedModels[capability] = model;
      }
      if (profile != null) {
        selectedProfiles[capability] = profile;
      }
    }
    return LlmModelProfile(
      id: chatProfile.id,
      name: chatProfile.name,
      provider: chatProfile.provider,
      baseUrl: chatProfile.baseUrl,
      apiKey: chatProfile.apiKey,
      model: chatProfile.model,
      models: chatProfile.models,
      selectedModelByCapability: Map.unmodifiable(selectedModels),
      selectedProfileByCapability: Map.unmodifiable(selectedProfiles),
      systemPrompt: systemPrompt,
      maxTokens: chatProfile.maxTokens,
      contextWindowTokens: chatProfile.contextWindowTokens,
      nativeContextWindowTokens: chatProfile.nativeContextWindowTokens,
      responseReserveTokens: chatProfile.responseReserveTokens,
      compactionModel: chatProfile.compactionModel,
      preCompactionMemoryFlush: chatProfile.preCompactionMemoryFlush,
    );
  }

  LlmModelProfile? get selectedRuntimeProfile => runtimeProfileFor();

  bool get hasSelectedModel => selectedProfile?.hasModel ?? false;
}

const _storedModelEntriesKey = 'model_entries';
const _storedSelectedModelByCapabilityKey = 'selected_model_by_capability';

sdk.NapaxiConfigProfile _storedProfileFromProfile(LlmModelProfile profile) {
  final allowedModels = profile.models
      .map(
        (entry) => {
          'id': entry.id,
          'name': entry.displayName.trim().isEmpty
              ? entry.id
              : entry.displayName.trim(),
        },
      )
      .toList();
  return sdk.NapaxiConfigProfile(
    id: profile.id,
    name: profile.name,
    provider: profile.provider,
    baseUrl: profile.baseUrl.trim().isEmpty ? null : profile.baseUrl,
    model: profile.model,
    maxTokens: profile.maxTokens,
    allowedModels: allowedModels.isEmpty ? null : allowedModels,
    imageAnalysisModel: profile.selectedModel(ModelCapability.imageAnalysis),
    imageModel: profile.selectedModel(ModelCapability.imageGeneration),
    videoModel: profile.selectedModel(ModelCapability.videoGeneration),
    audioModel: profile.selectedModel(ModelCapability.audioAnalysis),
    contextEngine: sdk.ContextEngineConfig(
      contextWindowTokens: profile.contextWindowTokens,
      nativeContextWindowTokens: profile.nativeContextWindowTokens,
      responseReserveTokens: profile.responseReserveTokens,
      compactionModel: profile.compactionModel.trim().isEmpty
          ? null
          : profile.compactionModel.trim(),
      preCompactionMemoryFlush: profile.preCompactionMemoryFlush,
    ),
    metadata: {
      _storedModelEntriesKey: [
        for (final entry in profile.models)
          {
            'id': entry.id,
            'display_name': entry.displayName,
            'capabilities': entry.capabilities.map((c) => c.name).toList(),
          },
      ],
      _storedSelectedModelByCapabilityKey: {
        for (final entry in profile.selectedModelByCapability.entries)
          entry.key.name: entry.value,
      },
    },
  );
}

LlmModelProfile _profileFromStoredProfile(
  sdk.NapaxiConfigProfile profile,
  String apiKey,
) {
  final modelEntries = _modelEntriesFromMetadata(profile);
  final selectedModels = _selectedModelsFromMetadata(profile);
  return LlmModelProfile(
    id: profile.id,
    name: profile.name,
    provider: profile.provider,
    baseUrl: profile.baseUrl ?? '',
    apiKey: apiKey,
    model: profile.model,
    models: modelEntries,
    selectedModelByCapability: selectedModels,
    systemPrompt: profile.systemPrompt,
    maxTokens: profile.maxTokens,
    contextWindowTokens: profile.contextEngine.contextWindowTokens,
    nativeContextWindowTokens: profile.contextEngine.nativeContextWindowTokens,
    responseReserveTokens: profile.contextEngine.responseReserveTokens,
    compactionModel: profile.contextEngine.compactionModel ?? '',
    preCompactionMemoryFlush: profile.contextEngine.preCompactionMemoryFlush,
  );
}

List<ModelEntry> _modelEntriesFromMetadata(sdk.NapaxiConfigProfile profile) {
  final rawEntries = profile.metadata[_storedModelEntriesKey];
  if (rawEntries is List) {
    return rawEntries
        .whereType<Map>()
        .map((item) {
          final map = Map<String, Object?>.from(item);
          final capabilities =
              (map['capabilities'] as List?)
                  ?.whereType<String>()
                  .map(_capabilityFromName)
                  .whereType<ModelCapability>()
                  .toList() ??
              const [ModelCapability.chat];
          return ModelEntry(
            id: map['id'] as String? ?? '',
            displayName: map['display_name'] as String? ?? '',
            capabilities: capabilities.isEmpty
                ? const [ModelCapability.chat]
                : List.unmodifiable(capabilities),
          );
        })
        .where((entry) => entry.id.trim().isNotEmpty)
        .toList();
  }

  final entries = <ModelEntry>[];
  void addEntry(String? id, ModelCapability capability) {
    final trimmed = id?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    final index = entries.indexWhere((entry) => entry.id == trimmed);
    if (index == -1) {
      entries.add(ModelEntry(id: trimmed, capabilities: [capability]));
      return;
    }
    final capabilities = {...entries[index].capabilities, capability}.toList();
    entries[index] = entries[index].copyWith(capabilities: capabilities);
  }

  addEntry(profile.model, ModelCapability.chat);
  addEntry(profile.imageAnalysisModel, ModelCapability.imageAnalysis);
  addEntry(profile.imageModel, ModelCapability.imageGeneration);
  addEntry(profile.videoModel, ModelCapability.videoGeneration);
  addEntry(profile.audioModel, ModelCapability.audioAnalysis);
  for (final allowedModel in profile.allowedModels ?? const []) {
    addEntry(allowedModel['id'], ModelCapability.chat);
  }
  return entries;
}

Map<ModelCapability, String> _selectedModelsFromMetadata(
  sdk.NapaxiConfigProfile profile,
) {
  final rawSelection = profile.metadata[_storedSelectedModelByCapabilityKey];
  final selection = <ModelCapability, String>{};
  if (rawSelection is Map) {
    for (final entry in rawSelection.entries) {
      final capability = _capabilityFromName(entry.key.toString());
      final model = entry.value?.toString().trim();
      if (capability != null && model != null && model.isNotEmpty) {
        selection[capability] = model;
      }
    }
  }
  selection.putIfAbsent(ModelCapability.chat, () => profile.model);
  if (profile.imageAnalysisModel != null) {
    selection.putIfAbsent(
      ModelCapability.imageAnalysis,
      () => profile.imageAnalysisModel!,
    );
  }
  if (profile.imageModel != null) {
    selection.putIfAbsent(
      ModelCapability.imageGeneration,
      () => profile.imageModel!,
    );
  }
  if (profile.videoModel != null) {
    selection.putIfAbsent(
      ModelCapability.videoGeneration,
      () => profile.videoModel!,
    );
  }
  if (profile.audioModel != null) {
    selection.putIfAbsent(
      ModelCapability.audioAnalysis,
      () => profile.audioModel!,
    );
  }
  return selection;
}

sdk.NapaxiConfigSelection _storedSelectionFromConfig(LlmConfigState config) {
  return sdk.NapaxiConfigSelection(
    selectedProfileId: config.selectedProfileId,
    selectedProfileIdByCapability: {
      for (final entry in config.selectedProfileIdByCapability.entries)
        entry.key.name: entry.value,
    },
    systemPrompt: config.systemPrompt,
    maxToolIterations: config.maxToolIterations,
  );
}

Map<ModelCapability, String> _capabilitySelectionFromStored(
  sdk.NapaxiConfigSelection selection,
) {
  final result = <ModelCapability, String>{};
  for (final entry in selection.selectedProfileIdByCapability.entries) {
    final capability = _capabilityFromName(entry.key);
    if (capability != null && entry.value.trim().isNotEmpty) {
      result[capability] = entry.value;
    }
  }
  return result;
}

ModelCapability? _capabilityFromName(String name) {
  for (final capability in ModelCapability.values) {
    if (capability.name == name) return capability;
  }
  return null;
}
