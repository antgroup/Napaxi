part of '../main.dart';

class _LlmConfigPage extends StatefulWidget {
  const _LlmConfigPage({
    required this.initialConfig,
    required this.language,
    required this.onConfigChanged,
    required this.onLanguageChanged,
    this.embedded = false,
  });

  final LlmConfigState initialConfig;
  final AppLanguage language;
  final ValueChanged<LlmConfigState> onConfigChanged;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final bool embedded;

  @override
  State<_LlmConfigPage> createState() => _LlmConfigPageState();
}

const _configPageBackground = Color(0xFFF5F5F5);
const _configSurface = Color(0xFFFFFFFF);
const _configSurfaceMuted = Color(0xFFFAFAFA);
const _configSelectedSurface = Color(0xFFEDEDED);
const _configTextPrimary = Color(0xFF333333);
const _configTextSecondary = Color(0xFF666666);
const _configTextTertiary = Color(0xFF858585);
const _configBorder = Color(0xFFD4D4D4);
const _configBorderFaint = Color(0xFFE5E5E5);
const _tokenPresetAuto = 'auto';
const _tokenPreset128k = '128k';
const _tokenPreset200k = '200k';
const _tokenPreset1m = '1m';
const _tokenPreset4k = '4k';
const _tokenPreset8k = '8k';
const _tokenPresetCustom = 'custom';

const Map<String, int> _contextWindowPresetTokens = {
  _tokenPreset128k: 128000,
  _tokenPreset200k: 200000,
  _tokenPreset1m: 1000000,
};

const Map<String, int> _responseReservePresetTokens = {
  _tokenPreset4k: 4096,
  _tokenPreset8k: 8192,
};

InputDecoration _configInputDecoration({
  required String labelText,
  String? hintText,
  String? helperText,
  Widget? suffixIcon,
}) {
  final borderRadius = BorderRadius.circular(10);
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    helperText: helperText,
    filled: true,
    fillColor: _configSurfaceMuted,
    labelStyle: const TextStyle(color: _configTextSecondary),
    hintStyle: const TextStyle(color: _configTextTertiary),
    helperStyle: const TextStyle(
      color: _configTextSecondary,
      fontSize: 12,
      height: 1.3,
    ),
    helperMaxLines: 3,
    suffixIcon: suffixIcon,
    enabledBorder: OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: const BorderSide(color: _configBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: const BorderSide(color: _configTextPrimary, width: 1.2),
    ),
    border: OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: const BorderSide(color: _configBorder),
    ),
  );
}

String _presetForTokens(int? tokens, Map<String, int> presets) {
  if (tokens == null || tokens <= 0) return _tokenPresetAuto;
  for (final entry in presets.entries) {
    if (entry.value == tokens) return entry.key;
  }
  return _tokenPresetCustom;
}

int? _tokensForPreset(
  String preset,
  String customValue,
  Map<String, int> presets,
) {
  if (preset == _tokenPresetAuto) return null;
  if (preset == _tokenPresetCustom) {
    final parsed = int.tryParse(customValue.trim());
    return parsed == null || parsed <= 0 ? null : parsed;
  }
  return presets[preset];
}

String _tokenPresetLabel(String preset) {
  return switch (preset) {
    _tokenPresetAuto => 'Auto',
    _tokenPresetCustom => 'Custom',
    _tokenPreset1m => '1M',
    _ => preset.toUpperCase(),
  };
}

class _LlmConfigPageState extends State<_LlmConfigPage> {
  late List<LlmModelProfile> _profiles;
  late String? _selectedProfileId;
  late Map<ModelCapability, String> _selectedProfileIdByCapability;
  late final TextEditingController _systemPromptController;
  late final TextEditingController _maxToolIterationsController;

  @override
  void initState() {
    super.initState();
    _profiles = List.of(widget.initialConfig.profiles);
    _selectedProfileId = widget.initialConfig.selectedProfileId;
    _selectedProfileIdByCapability = Map.of(
      widget.initialConfig.selectedProfileIdByCapability,
    );
    _systemPromptController = TextEditingController(
      text: widget.initialConfig.systemPrompt,
    );
    _maxToolIterationsController = TextEditingController(
      text: widget.initialConfig.maxToolIterations.toString(),
    );
  }

  @override
  void dispose() {
    _systemPromptController.dispose();
    _maxToolIterationsController.dispose();
    super.dispose();
  }

  void _emitConfigChanged() {
    widget.onConfigChanged(
      LlmConfigState(
        profiles: List.unmodifiable(_profiles),
        selectedProfileId: _normalizedSelectedProfileId,
        selectedProfileIdByCapability: Map.unmodifiable(
          _normalizedSelectedProfileIdByCapability,
        ),
        systemPrompt: _systemPromptController.text.trim(),
        maxToolIterations: _configuredMaxToolIterations,
      ),
    );
  }

  int get _configuredMaxToolIterations {
    final parsed = int.tryParse(_maxToolIterationsController.text.trim());
    if (parsed == null) return 50;
    if (parsed < 0) return -1;
    if (parsed == 0) return 0;
    return parsed < 2 ? 2 : parsed;
  }

  String? get _normalizedSelectedProfileId {
    if (_profiles.isEmpty) return null;
    final selectedId = _selectedProfileId;
    final hasSelected = _profiles.any((profile) => profile.id == selectedId);
    return hasSelected ? selectedId : _profiles.first.id;
  }

  Map<ModelCapability, String> get _normalizedSelectedProfileIdByCapability {
    final selection = <ModelCapability, String>{};
    for (final capability in _modelCapabilities) {
      final selectedId = _selectedProfileIdByCapability[capability];
      final selectedProfile = _profiles.where((profile) {
        return profile.id == selectedId && profile.supports(capability);
      }).firstOrNull;
      if (selectedProfile != null) {
        selection[capability] = selectedProfile.id;
        continue;
      }
      final fallbackProfile = _profiles
          .where((profile) => profile.supports(capability))
          .firstOrNull;
      if (fallbackProfile != null) selection[capability] = fallbackProfile.id;
    }
    return selection;
  }

  Future<void> _addProfile() async {
    final profile = await Navigator.of(context).push<LlmModelProfile>(
      MaterialPageRoute(
        builder: (context) => _LlmModelProfilePage(
          initialProfile: LlmModelProfile(id: _newProfileId(), name: ''),
        ),
      ),
    );
    if (profile == null) return;
    setState(() {
      _profiles = [..._profiles, profile];
      _selectedProfileId = profile.id;
    });
    _emitConfigChanged();
  }

  Future<void> _editProfile(LlmModelProfile profile) async {
    final updatedProfile = await Navigator.of(context).push<LlmModelProfile>(
      MaterialPageRoute(
        builder: (context) => _LlmModelProfilePage(initialProfile: profile),
      ),
    );
    if (updatedProfile == null) return;
    setState(() {
      _profiles = _profiles
          .map((item) => item.id == updatedProfile.id ? updatedProfile : item)
          .toList();
      _selectedProfileIdByCapability.removeWhere((capability, profileId) {
        return profileId == updatedProfile.id &&
            !updatedProfile.supports(capability);
      });
    });
    _emitConfigChanged();
  }

  void _selectProfile(String profileId) {
    setState(() {
      _selectedProfileId = profileId;
    });
    _emitConfigChanged();
  }

  void _deleteProfile(String profileId) {
    setState(() {
      _profiles = _profiles
          .where((profile) => profile.id != profileId)
          .toList();
      _selectedProfileIdByCapability.removeWhere(
        (_, selectedProfileId) => selectedProfileId == profileId,
      );
      if (_selectedProfileId == profileId) {
        _selectedProfileId = _profiles.isEmpty ? null : _profiles.first.id;
      }
    });
    _emitConfigChanged();
  }

  void _selectCapabilityProfile(ModelCapability capability, String? profileId) {
    setState(() {
      if (profileId == null || profileId.trim().isEmpty) {
        _selectedProfileIdByCapability.remove(capability);
      } else {
        _selectedProfileIdByCapability[capability] = profileId.trim();
      }
    });
    _emitConfigChanged();
  }

  List<LlmModelProfile> _profilesForCapability(ModelCapability capability) {
    return _profiles.where((profile) => profile.supports(capability)).toList();
  }

  String _newProfileId() {
    return 'model-${DateTime.now().microsecondsSinceEpoch}';
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    if (widget.embedded) {
      return _buildBody(strings);
    }

    return Scaffold(
      backgroundColor: _configPageBackground,
      appBar: AppBar(
        title: Text(strings.llmConfigurationTitle),
        backgroundColor: _configPageBackground,
        foregroundColor: _configTextPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: _buildBody(strings),
    );
  }

  Widget _buildBody(AppStrings strings) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _dismissKeyboard,
      child: ListView(
        key: const Key('config_page_list'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          if (widget.embedded) ...[
            _EmbeddedSettingsHeader(title: strings.llmConfigurationTitle),
            const SizedBox(height: 12),
          ],
          _SettingsSectionHeader(title: strings.savedModelsTitle),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('add_model_button'),
              onPressed: _addProfile,
              icon: const Icon(Icons.add_rounded),
              label: Text(strings.addModel),
              style: TextButton.styleFrom(foregroundColor: _configTextPrimary),
            ),
          ),
          const SizedBox(height: 16),
          if (_profiles.isEmpty)
            const _EmptyModelList()
          else
            ..._profiles.map((profile) {
              return _ModelProfileTile(
                profile: profile,
                isSelected: profile.id == _normalizedSelectedProfileId,
                onSelect: () => _selectProfile(profile.id),
                onEdit: () => _editProfile(profile),
                onDelete: () => _deleteProfile(profile.id),
              );
            }),
          const SizedBox(height: 24),
          _SettingsSectionHeader(title: strings.capabilitySlotsTitle),
          const SizedBox(height: 12),
          for (final capability in _modelCapabilities) ...[
            _CapabilityProfileSlotSelector(
              capability: capability,
              selectedProfileId:
                  _normalizedSelectedProfileIdByCapability[capability],
              profiles: _profilesForCapability(capability),
              onSelected: (profileId) =>
                  _selectCapabilityProfile(capability, profileId),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 24),
          _SettingsSectionHeader(
            title: strings.runtimeTitle,
            description: strings.runtimeDescription,
          ),
          const SizedBox(height: 12),
          _ConfigField(
            key: const Key('max_tool_iterations_field'),
            controller: _maxToolIterationsController,
            label: strings.maxToolIterationsLabel,
            hintText: strings.maxToolIterationsHint,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            onChanged: (_) => _emitConfigChanged(),
          ),
          const SizedBox(height: 24),
          _SettingsSectionHeader(
            title: strings.promptingTitle,
            description: strings.promptingDescription,
          ),
          const SizedBox(height: 12),
          _ConfigField(
            key: const Key('system_prompt_field'),
            controller: _systemPromptController,
            label: strings.systemPromptLabel,
            hintText: strings.systemPromptHint,
            maxLines: 5,
            onChanged: (_) => _emitConfigChanged(),
          ),
          const SizedBox(height: 24),
          _SettingsSectionHeader(
            title: strings.languageTitle,
            description: strings.languageDescription,
          ),
          const SizedBox(height: 12),
          _LanguageSelector(
            selectedLanguage: widget.language,
            onLanguageChanged: widget.onLanguageChanged,
          ),
          const SizedBox(height: 24),
          _LicenseListTile(strings: strings),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _EmptyModelList extends StatelessWidget {
  const _EmptyModelList();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Container(
      key: const Key('empty_model_list'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _configSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.noSavedModelsTitle,
            style: const TextStyle(
              color: _configTextPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({
    required this.selectedLanguage,
    required this.onLanguageChanged,
  });

  final AppLanguage selectedLanguage;
  final ValueChanged<AppLanguage> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('language_selector'),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _configSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Row(
        children: [
          for (final language in AppLanguage.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: _LanguageOptionButton(
                  language: language,
                  selected: language == selectedLanguage,
                  onTap: () => onLanguageChanged(language),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LanguageOptionButton extends StatelessWidget {
  const _LanguageOptionButton({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final AppLanguage language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _configSelectedSurface : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: Key('language_option_${language.code}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          child: Text(
            language.label,
            style: TextStyle(
              color: selected ? _configTextPrimary : _configTextSecondary,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _LicenseListTile extends StatelessWidget {
  const _LicenseListTile({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('open_source_licenses_button'),
      color: _configSurface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          showLicensePage(context: context, applicationName: strings.appTitle);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _configBorderFaint),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.article_outlined,
                color: _configTextSecondary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.openSourceLicensesTitle,
                      style: const TextStyle(
                        color: _configTextPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      strings.openSourceLicensesDescription,
                      style: const TextStyle(
                        color: _configTextSecondary,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: _configTextTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelProfileTile extends StatelessWidget {
  const _ModelProfileTile({
    required this.profile,
    required this.isSelected,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  final LlmModelProfile profile;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final subtitle = profile.subtitle;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('model_profile_${profile.id}'),
        onTap: onSelect,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: _configBorderFaint, width: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Icon(
                    isSelected ? Icons.check_rounded : null,
                    size: 20,
                    color: _configTextPrimary,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _configTextPrimary,
                          fontSize: 15,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _configTextSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  key: Key('edit_model_${profile.id}'),
                  tooltip: strings.editModel,
                  onPressed: onEdit,
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: _configTextSecondary,
                    size: 20,
                  ),
                ),
                IconButton(
                  key: Key('delete_model_${profile.id}'),
                  tooltip: strings.deleteModel,
                  onPressed: onDelete,
                  icon: const Icon(
                    Icons.delete_outline,
                    color: _configTextSecondary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LlmModelProfilePage extends StatefulWidget {
  const _LlmModelProfilePage({required this.initialProfile});

  final LlmModelProfile initialProfile;

  @override
  State<_LlmModelProfilePage> createState() => _LlmModelProfilePageState();
}

class _LlmModelProfilePageState extends State<_LlmModelProfilePage> {
  late final TextEditingController _nameController;
  late final TextEditingController _providerController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late final TextEditingController _maxTokensController;
  late final TextEditingController _nativeContextWindowController;
  late final TextEditingController _contextWindowController;
  late final TextEditingController _responseReserveController;
  late final TextEditingController _compactionModelController;
  late String _selectedProviderOptionId;
  late String _nativeContextWindowPreset;
  late String _contextWindowPreset;
  late String _responseReservePreset;
  late bool _preCompactionMemoryFlush;
  late List<String> _availableModels;
  late Set<ModelCapability> _selectedCapabilities;
  bool _isFetchingModels = false;
  bool _isTestingConnection = false;
  bool _isApiKeyObscured = true;
  String? _statusMessage;
  bool _statusIsError = false;
  // null = idle, true = success, false = error
  bool? _connectionTestResult;
  bool? _fetchModelsResult;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialProfile.name);
    _providerController = TextEditingController(
      text: widget.initialProfile.provider,
    );
    _baseUrlController = TextEditingController(
      text: widget.initialProfile.baseUrl,
    );
    _apiKeyController = TextEditingController(
      text: widget.initialProfile.apiKey,
    );
    _modelController = TextEditingController(text: widget.initialProfile.model);
    _maxTokensController = TextEditingController(
      text: widget.initialProfile.maxTokens.toString(),
    );
    _nativeContextWindowPreset = _presetForTokens(
      widget.initialProfile.nativeContextWindowTokens,
      _contextWindowPresetTokens,
    );
    _contextWindowPreset = _presetForTokens(
      widget.initialProfile.contextWindowTokens,
      _contextWindowPresetTokens,
    );
    _responseReservePreset = _presetForTokens(
      widget.initialProfile.responseReserveTokens,
      _responseReservePresetTokens,
    );
    _contextWindowController = TextEditingController(
      text: _contextWindowPreset == _tokenPresetCustom
          ? widget.initialProfile.contextWindowTokens?.toString() ?? ''
          : '',
    );
    _nativeContextWindowController = TextEditingController(
      text: _nativeContextWindowPreset == _tokenPresetCustom
          ? widget.initialProfile.nativeContextWindowTokens?.toString() ?? ''
          : '',
    );
    _responseReserveController = TextEditingController(
      text: _responseReservePreset == _tokenPresetCustom
          ? widget.initialProfile.responseReserveTokens?.toString() ?? ''
          : '',
    );
    _compactionModelController = TextEditingController(
      text: widget.initialProfile.compactionModel,
    );
    _preCompactionMemoryFlush = widget.initialProfile.preCompactionMemoryFlush;
    _selectedCapabilities = _initialCapabilities();
    final initialOption = _optionForProvider(widget.initialProfile.provider);
    _selectedProviderOptionId = initialOption?.id ?? 'openai-compatible';
    if (widget.initialProfile.provider.trim().isEmpty) {
      _providerController.text = 'openai-compatible';
    }
    _availableModels = _initialAvailableModels();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_maybeFetchModelsOnOpen());
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _providerController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _maxTokensController.dispose();
    _nativeContextWindowController.dispose();
    _contextWindowController.dispose();
    _responseReserveController.dispose();
    _compactionModelController.dispose();
    super.dispose();
  }

  void _save() {
    final primaryModelId = _modelController.text.trim();
    final models = primaryModelId.isEmpty
        ? const <ModelEntry>[]
        : [
            ModelEntry(
              id: primaryModelId,
              capabilities: List.unmodifiable(_selectedCapabilities),
            ),
          ];

    Navigator.of(context).pop(
      LlmModelProfile(
        id: widget.initialProfile.id,
        name: _nameController.text.trim(),
        provider: _providerController.text.trim(),
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _normalizedApiKey,
        model: primaryModelId,
        models: List.unmodifiable(models),
        selectedModelByCapability: const {},
        systemPrompt: widget.initialProfile.systemPrompt,
        maxTokens: _configuredMaxTokens,
        contextWindowTokens: _configuredContextWindowTokens,
        nativeContextWindowTokens: _configuredNativeContextWindowTokens,
        responseReserveTokens: _configuredResponseReserveTokens,
        compactionModel: _compactionModelController.text.trim(),
        preCompactionMemoryFlush: _preCompactionMemoryFlush,
      ),
    );
  }

  int get _configuredMaxTokens {
    final parsed = int.tryParse(_maxTokensController.text.trim());
    if (parsed == null || parsed <= 0) return sdk.defaultMaxTokens;
    return parsed;
  }

  int? get _configuredContextWindowTokens => _tokensForPreset(
    _contextWindowPreset,
    _contextWindowController.text,
    _contextWindowPresetTokens,
  );

  int? get _configuredNativeContextWindowTokens => _tokensForPreset(
    _nativeContextWindowPreset,
    _nativeContextWindowController.text,
    _contextWindowPresetTokens,
  );

  int? get _configuredResponseReserveTokens => _tokensForPreset(
    _responseReservePreset,
    _responseReserveController.text,
    _responseReservePresetTokens,
  );

  Set<ModelCapability> _initialCapabilities() {
    final modelId = widget.initialProfile.model.trim();
    for (final entry in widget.initialProfile.models) {
      if (entry.id.trim() == modelId) {
        return entry.capabilities
            .where((capability) => capability != ModelCapability.chat)
            .toSet();
      }
    }
    final capabilities = <ModelCapability>{};
    for (final entry in widget.initialProfile.models) {
      capabilities.addAll(
        entry.capabilities.where(
          (capability) => capability != ModelCapability.chat,
        ),
      );
    }
    return capabilities;
  }

  List<String> _initialAvailableModels() {
    final currentModel = widget.initialProfile.model.trim();
    final option = _optionForProvider(_providerController.text);
    return _mergeModels([
      if (option != null) ...option.models,
      if (currentModel.isNotEmpty) currentModel,
    ]);
  }

  List<String> _mergeModels(Iterable<String> models) {
    final seen = <String>{};
    final merged = <String>[];
    for (final model in models) {
      final trimmed = model.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      merged.add(trimmed);
    }
    return merged;
  }

  void _applyProviderOption(LlmProviderOption option) {
    setState(() {
      _selectedProviderOptionId = option.id;
      _providerController.text = option.provider;
      _baseUrlController.text = option.baseUrl;
      if (_nameController.text.trim().isEmpty &&
          option.id != 'custom' &&
          option.id != 'openai-compatible') {
        _nameController.text = option.name;
      }
      if (_modelController.text.trim().isEmpty &&
          option.defaultModel.isNotEmpty) {
        _modelController.text = option.defaultModel;
      }
      _availableModels = _mergeModels([
        ...option.models,
        _modelController.text,
      ]);
      _statusMessage = null;
      _statusIsError = false;
    });
  }

  void _selectModel(String model) {
    setState(() => _modelController.text = model);
  }

  void _selectCompactionModel(String model) {
    setState(() => _compactionModelController.text = model);
  }

  List<String> get _compactionModelOptions => _mergeModels([
    ..._availableModels,
    for (final entry in widget.initialProfile.models) entry.id,
    _modelController.text,
    _compactionModelController.text,
  ]);

  void _toggleCapability(ModelCapability capability) {
    setState(() {
      if (_selectedCapabilities.contains(capability)) {
        _selectedCapabilities = {..._selectedCapabilities}..remove(capability);
      } else {
        _selectedCapabilities = {..._selectedCapabilities, capability};
      }
    });
  }

  Future<void> _maybeFetchModelsOnOpen() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    if (_isFetchingModels || _isTestingConnection) return;
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _normalizedApiKey;
    if (baseUrl.isEmpty || apiKey.isEmpty || !_isHeaderSafeApiKey(apiKey)) {
      return;
    }
    await _runModelRequest(
      testOnly: false,
      silent: true,
      preserveCurrentModel: true,
    );
  }

  Future<void> _fetchModels() async {
    await _runModelRequest(testOnly: false);
    if (!mounted) return;
    final success = !_statusIsError;
    final message = _statusMessage ?? '';
    setState(() {
      _fetchModelsResult = success;
      _statusMessage = null;
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(
              color: success
                  ? const Color(0xFF14532D)
                  : const Color(0xFF991B1B),
            ),
          ),
          backgroundColor: success
              ? const Color(0xFFF0FDF4)
              : const Color(0xFFFEF2F2),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _fetchModelsResult = null);
    });
  }

  Future<void> _testConnection() async {
    await _runModelRequest(testOnly: true);
    if (!mounted) return;
    final success = !_statusIsError;
    final message = _statusMessage ?? '';
    setState(() {
      _connectionTestResult = success;
      _statusMessage = null;
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(
              color: success
                  ? const Color(0xFF374151)
                  : const Color(0xFF991B1B),
            ),
          ),
          backgroundColor: success
              ? const Color(0xFFF0FDF4)
              : const Color(0xFFFEF2F2),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _connectionTestResult = null);
    });
  }

  Future<void> _runModelRequest({
    required bool testOnly,
    bool silent = false,
    bool preserveCurrentModel = false,
  }) async {
    final strings = AppStrings.of(context);
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _normalizedApiKey;
    if (baseUrl.isEmpty) {
      if (!silent) {
        setState(() {
          _statusMessage = strings.baseUrlRequiredForTest;
          _statusIsError = true;
        });
      }
      return;
    }
    if (apiKey.isEmpty) {
      if (!silent) {
        setState(() {
          _statusMessage = strings.apiKeyRequiredForTest;
          _statusIsError = true;
        });
      }
      return;
    }
    if (!_isHeaderSafeApiKey(apiKey)) {
      if (!silent) {
        setState(() {
          _statusMessage = strings.apiKeyInvalidForHeader;
          _statusIsError = true;
        });
      }
      return;
    }

    setState(() {
      if (testOnly) {
        _isTestingConnection = true;
      } else {
        _isFetchingModels = true;
      }
      if (!silent) {
        _statusMessage = null;
        _statusIsError = false;
      }
    });

    try {
      final models = await _OpenAiCompatibleModelClient.fetchModels(
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
      if (!mounted) return;
      setState(() {
        if (!testOnly) {
          final currentModel = _modelController.text.trim();
          final compactionModel = _compactionModelController.text.trim();
          _availableModels = _mergeModels([
            ...models,
            currentModel,
            compactionModel,
          ]);
          if (!preserveCurrentModel && _availableModels.isEmpty) {
            _modelController.clear();
          } else if (!preserveCurrentModel &&
              (currentModel.isEmpty ||
                  !_availableModels.contains(currentModel))) {
            _modelController.text = _availableModels.first;
          }
        }
        if (!silent) {
          _statusMessage = models.isEmpty
              ? strings.noModelsFound
              : testOnly
              ? strings.connectionOk
              : strings.modelsLoaded(models.length);
          _statusIsError = false;
        }
      });
    } catch (error) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _statusMessage = strings.connectionFailed(_friendlyError(error));
          _statusIsError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingModels = false;
          _isTestingConnection = false;
        });
      }
    }
  }

  String get _normalizedApiKey =>
      _apiKeyController.text.replaceAll(RegExp(r'\s+'), '').trim();

  bool _isHeaderSafeApiKey(String apiKey) {
    if (apiKey.isEmpty) return false;
    for (final codeUnit in apiKey.codeUnits) {
      if (codeUnit < 0x21 || codeUnit > 0x7e) return false;
    }
    return true;
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    const exceptionPrefix = 'Exception: ';
    if (text.startsWith(exceptionPrefix)) {
      return text.substring(exceptionPrefix.length);
    }
    return text;
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.editModel),
        backgroundColor: _configPageBackground,
        foregroundColor: _configTextPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            key: const Key('save_model_button'),
            onPressed: _save,
            style: TextButton.styleFrom(foregroundColor: _configTextPrimary),
            child: Text(strings.save),
          ),
        ],
      ),
      backgroundColor: _configPageBackground,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dismissKeyboard,
        child: ListView(
          key: const Key('model_profile_form'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            _ConfigField(
              key: const Key('model_name_field'),
              controller: _nameController,
              label: strings.modelNameLabel,
              hintText: strings.modelNameHint,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            _ProviderSelector(
              selectedOptionId: _selectedProviderOptionId,
              onProviderSelected: _applyProviderOption,
            ),
            if (_selectedProviderOptionId == 'custom') ...[
              const SizedBox(height: 12),
              _ConfigField(
                key: const Key('provider_field'),
                controller: _providerController,
                label: strings.customProviderLabel,
                hintText: strings.providerHint,
                textInputAction: TextInputAction.next,
              ),
            ],
            const SizedBox(height: 24),
            _SettingsSectionHeader(title: strings.connectionTitle),
            const SizedBox(height: 12),
            _ConfigField(
              key: const Key('base_url_field'),
              controller: _baseUrlController,
              label: strings.baseUrlLabel,
              hintText: 'https://api.example.com/v1',
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            _ConfigField(
              key: const Key('api_key_field'),
              controller: _apiKeyController,
              label: strings.apiKeyLabel,
              hintText: 'sk-...',
              obscureText: _isApiKeyObscured,
              suffixIcon: IconButton(
                tooltip: _isApiKeyObscured ? 'Show API Key' : 'Hide API Key',
                icon: Icon(
                  _isApiKeyObscured
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
                onPressed: () {
                  setState(() => _isApiKeyObscured = !_isApiKeyObscured);
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('test_connection_button'),
                    onPressed: _isTestingConnection ? null : _testConnection,
                    icon: _isTestingConnection
                        ? const _ButtonProgress()
                        : _connectionTestResult == true
                        ? const Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: Color(0xFF4B5563),
                          )
                        : _connectionTestResult == false
                        ? const Icon(
                            Icons.cancel_rounded,
                            size: 18,
                            color: Color(0xFF991B1B),
                          )
                        : const Icon(Icons.network_check_rounded, size: 18),
                    label: Text(strings.testConnection),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _connectionTestResult == true
                          ? const Color(0xFF4B5563)
                          : _connectionTestResult == false
                          ? const Color(0xFF991B1B)
                          : _configTextPrimary,
                      side: BorderSide(
                        color: _connectionTestResult == true
                            ? const Color(0xFF9CA3AF)
                            : _connectionTestResult == false
                            ? const Color(0xFFFCA5A5)
                            : _configBorder,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('fetch_models_button'),
                    onPressed: _isFetchingModels ? null : _fetchModels,
                    icon: _isFetchingModels
                        ? const _ButtonProgress()
                        : _fetchModelsResult == true
                        ? const Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: Color(0xFF4B5563),
                          )
                        : _fetchModelsResult == false
                        ? const Icon(
                            Icons.cancel_rounded,
                            size: 18,
                            color: Color(0xFF991B1B),
                          )
                        : const Icon(Icons.cloud_download_outlined, size: 18),
                    label: Text(strings.fetchModels),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _fetchModelsResult == true
                          ? const Color(0xFF4B5563)
                          : _fetchModelsResult == false
                          ? const Color(0xFF991B1B)
                          : _configTextPrimary,
                      side: BorderSide(
                        color: _fetchModelsResult == true
                            ? const Color(0xFF9CA3AF)
                            : _fetchModelsResult == false
                            ? const Color(0xFFFCA5A5)
                            : _configBorder,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ModelSelectorField(
              controller: _modelController,
              models: _availableModels,
              label: strings.addModelIdLabel,
              onSelected: _selectModel,
            ),
            const SizedBox(height: 12),
            _ConfigField(
              key: const Key('max_tokens_field'),
              controller: _maxTokensController,
              label: strings.maxTokensLabel,
              hintText: strings.maxTokensHint,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 24),
            _SettingsSectionHeader(
              title: strings.contextAdvancedTitle,
              description: strings.contextAdvancedDescription,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('native_context_window_preset_field'),
              initialValue: _nativeContextWindowPreset,
              decoration: _configInputDecoration(
                labelText: strings.nativeContextWindowLabel,
                helperText: strings.nativeContextWindowHelp,
              ),
              items: [
                for (final value in const [
                  _tokenPresetAuto,
                  _tokenPreset128k,
                  _tokenPreset200k,
                  _tokenPreset1m,
                  _tokenPresetCustom,
                ])
                  DropdownMenuItem<String>(
                    value: value,
                    child: Text(_tokenPresetLabel(value)),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _nativeContextWindowPreset = value);
              },
            ),
            if (_nativeContextWindowPreset == _tokenPresetCustom) ...[
              const SizedBox(height: 12),
              _ConfigField(
                key: const Key('native_context_window_custom_field'),
                controller: _nativeContextWindowController,
                label: strings.nativeContextWindowCustomLabel,
                hintText: strings.nativeContextWindowCustomHint,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('context_window_preset_field'),
              initialValue: _contextWindowPreset,
              decoration: _configInputDecoration(
                labelText: strings.contextWindowLabel,
                helperText: strings.contextWindowHelp,
              ),
              items: [
                for (final value in const [
                  _tokenPresetAuto,
                  _tokenPreset128k,
                  _tokenPreset200k,
                  _tokenPreset1m,
                  _tokenPresetCustom,
                ])
                  DropdownMenuItem<String>(
                    value: value,
                    child: Text(_tokenPresetLabel(value)),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _contextWindowPreset = value);
              },
            ),
            if (_contextWindowPreset == _tokenPresetCustom) ...[
              const SizedBox(height: 12),
              _ConfigField(
                key: const Key('context_window_custom_field'),
                controller: _contextWindowController,
                label: strings.contextWindowCustomLabel,
                hintText: strings.contextWindowCustomHint,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('response_reserve_preset_field'),
              initialValue: _responseReservePreset,
              decoration: _configInputDecoration(
                labelText: strings.responseReserveLabel,
                helperText: strings.responseReserveHelp,
              ),
              items: [
                for (final value in const [
                  _tokenPresetAuto,
                  _tokenPreset4k,
                  _tokenPreset8k,
                  _tokenPresetCustom,
                ])
                  DropdownMenuItem<String>(
                    value: value,
                    child: Text(_tokenPresetLabel(value)),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _responseReservePreset = value);
              },
            ),
            if (_responseReservePreset == _tokenPresetCustom) ...[
              const SizedBox(height: 12),
              _ConfigField(
                key: const Key('response_reserve_custom_field'),
                controller: _responseReserveController,
                label: strings.responseReserveCustomLabel,
                hintText: strings.responseReserveCustomHint,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
              ),
            ],
            const SizedBox(height: 12),
            _CompactionModelSelectorField(
              key: const Key('compaction_model_field'),
              controller: _compactionModelController,
              models: _compactionModelOptions,
              label: strings.compactionModelLabel,
              followChatLabel: strings.compactionModelFollowChat,
              hintText: strings.compactionModelHint,
              helperText: strings.compactionModelHelp,
              onSelected: _selectCompactionModel,
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              key: const Key('pre_compaction_memory_flush_switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                strings.preCompactionMemoryFlushLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(strings.preCompactionMemoryFlushDescription),
              value: _preCompactionMemoryFlush,
              onChanged: (value) {
                setState(() => _preCompactionMemoryFlush = value);
              },
            ),
            const SizedBox(height: 24),
            _SettingsSectionHeader(title: strings.modelCapabilitiesTitle),
            const SizedBox(height: 8),
            _ModelCapabilitiesSelector(
              selectedCapabilities: _selectedCapabilities,
              onCapabilityChanged: _toggleCapability,
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 10),
              _ConnectionStatusMessage(
                message: _statusMessage!,
                isError: _statusIsError,
              ),
            ],
            const SizedBox(height: 28),
            FilledButton(
              key: const Key('save_model_primary_button'),
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: _configTextPrimary,
                foregroundColor: Colors.white,
              ),
              child: Text(strings.save),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderSelector extends StatelessWidget {
  const _ProviderSelector({
    required this.selectedOptionId,
    required this.onProviderSelected,
  });

  final String selectedOptionId;
  final ValueChanged<LlmProviderOption> onProviderSelected;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return DropdownButtonFormField<String>(
      key: const Key('provider_preset_field'),
      initialValue: selectedOptionId,
      decoration: _configInputDecoration(labelText: strings.providerLabel),
      items: [
        for (final option in _providerOptions)
          DropdownMenuItem<String>(
            value: option.id,
            child: Text(_providerOptionLabel(context, option)),
          ),
      ],
      onChanged: (id) {
        if (id == null) return;
        final option = _providerOptions.firstWhere((option) => option.id == id);
        onProviderSelected(option);
      },
    );
  }
}

String _providerOptionLabel(BuildContext context, LlmProviderOption option) {
  final language = _AppLanguageScope.languageOf(context);
  if (language != AppLanguage.chinese) return option.name;
  return switch (option.id) {
    'openai-compatible' => 'OpenAI 兼容接口',
    'custom' => '自定义',
    _ => option.name,
  };
}

class _ModelSelectorField extends StatelessWidget {
  const _ModelSelectorField({
    required this.controller,
    required this.models,
    required this.label,
    required this.onSelected,
  });

  final TextEditingController controller;
  final List<String> models;
  final String label;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('model_field'),
      controller: controller,
      textInputAction: TextInputAction.next,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: _configInputDecoration(
        labelText: label,
        hintText: 'model-id',
        suffixIcon: models.isEmpty
            ? null
            : PopupMenuButton<String>(
                key: const Key('model_picker_button'),
                tooltip: label,
                icon: const Icon(
                  Icons.expand_more_rounded,
                  color: _configTextSecondary,
                ),
                onSelected: onSelected,
                itemBuilder: (context) => [
                  for (final model in models)
                    PopupMenuItem<String>(value: model, child: Text(model)),
                ],
              ),
      ),
    );
  }
}

class _CompactionModelSelectorField extends StatelessWidget {
  const _CompactionModelSelectorField({
    super.key,
    required this.controller,
    required this.models,
    required this.label,
    required this.followChatLabel,
    required this.hintText,
    required this.helperText,
    required this.onSelected,
  });

  final TextEditingController controller;
  final List<String> models;
  final String label;
  final String followChatLabel;
  final String hintText;
  final String helperText;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.next,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: _configInputDecoration(
        labelText: label,
        hintText: hintText,
        helperText: helperText,
        suffixIcon: PopupMenuButton<String>(
          key: const Key('compaction_model_picker_button'),
          tooltip: label,
          icon: const Icon(
            Icons.expand_more_rounded,
            color: _configTextSecondary,
          ),
          onSelected: onSelected,
          itemBuilder: (context) => [
            PopupMenuItem<String>(value: '', child: Text(followChatLabel)),
            if (models.isNotEmpty) const PopupMenuDivider(),
            for (final model in models)
              PopupMenuItem<String>(value: model, child: Text(model)),
          ],
        ),
      ),
    );
  }
}

class _ModelCapabilitiesSelector extends StatelessWidget {
  const _ModelCapabilitiesSelector({
    required this.selectedCapabilities,
    required this.onCapabilityChanged,
  });

  final Set<ModelCapability> selectedCapabilities;
  final ValueChanged<ModelCapability> onCapabilityChanged;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 4.4,
      mainAxisSpacing: 2,
      crossAxisSpacing: 12,
      children: [
        for (final capability in _modelCapabilities)
          _CapabilityCheckbox(
            key: Key('capability_${capability.name}'),
            label: _capabilityLabel(context, capability),
            value: selectedCapabilities.contains(capability),
            onChanged: () => onCapabilityChanged(capability),
          ),
      ],
    );
  }
}

class _CapabilityCheckbox extends StatelessWidget {
  const _CapabilityCheckbox({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged,
      child: Row(
        children: [
          IgnorePointer(
            child: Checkbox(
              value: value,
              activeColor: _configTextPrimary,
              checkColor: Colors.white,
              visualDensity: VisualDensity.compact,
              onChanged: (_) {},
            ),
          ),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _configTextSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilityProfileSlotSelector extends StatelessWidget {
  const _CapabilityProfileSlotSelector({
    required this.capability,
    required this.selectedProfileId,
    required this.profiles,
    required this.onSelected,
  });

  final ModelCapability capability;
  final String? selectedProfileId;
  final List<LlmModelProfile> profiles;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final label = _capabilityLabel(context, capability);
    final effectiveValue =
        profiles.any((profile) {
          return profile.id == selectedProfileId;
        })
        ? selectedProfileId
        : null;

    if (profiles.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _configTextPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          _ModelCapabilityHint(message: strings.noCapabilityModels(label)),
        ],
      );
    }

    return DropdownButtonFormField<String>(
      key: Key('capability_slot_${capability.name}'),
      initialValue: effectiveValue,
      decoration: _configInputDecoration(labelText: label),
      items: [
        const DropdownMenuItem<String>(value: '', child: Text('-')),
        for (final profile in profiles)
          DropdownMenuItem<String>(
            value: profile.id,
            child: Text(profile.displayName),
          ),
      ],
      onChanged: (value) => onSelected(value == '' ? null : value),
    );
  }
}

class _ModelCapabilityHint extends StatelessWidget {
  const _ModelCapabilityHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: const TextStyle(
        color: _configTextSecondary,
        fontSize: 13,
        height: 1.35,
      ),
    );
  }
}

class _ButtonProgress extends StatelessWidget {
  const _ButtonProgress();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

class _ConnectionStatusMessage extends StatelessWidget {
  const _ConnectionStatusMessage({
    required this.message,
    required this.isError,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? const Color(0xFFB91C1C) : const Color(0xFF047857);
    final backgroundColor = isError
        ? const Color(0xFFFEF2F2)
        : const Color(0xFFECFDF5);
    final borderColor = isError
        ? const Color(0xFFFECACA)
        : const Color(0xFFA7F3D0);

    return Container(
      key: const Key('connection_status_message'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_outline,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenAiCompatibleModelClient {
  const _OpenAiCompatibleModelClient._();

  static Future<List<String>> fetchModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final uri = _modelsUri(baseUrl);
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await utf8.decodeStream(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}: ${_compactBody(body)}');
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?>) return const [];
      final data = decoded['data'];
      if (data is! List) return const [];

      final models = <String>[];
      for (final item in data) {
        if (item is Map<String, Object?>) {
          final id = item['id'];
          if (id is String && id.trim().isNotEmpty) models.add(id.trim());
        }
      }
      models.sort();
      return models;
    } finally {
      client.close(force: true);
    }
  }

  static Uri _modelsUri(String baseUrl) {
    final normalized = baseUrl.trim().isEmpty
        ? 'https://api.openai.com/v1'
        : baseUrl.trim();
    final baseUri = Uri.parse(normalized);
    final path = baseUri.path.endsWith('/')
        ? '${baseUri.path}models'
        : '${baseUri.path}/models';
    return baseUri.replace(path: path);
  }

  static String _compactBody(String body) {
    final normalized = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return 'empty response';
    return normalized.length <= 160
        ? normalized
        : '${normalized.substring(0, 160)}...';
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader({required this.title, this.description});

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _configTextPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(
            description!,
            style: const TextStyle(
              color: _configTextSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class _ConfigField extends StatelessWidget {
  const _ConfigField({
    super.key,
    required this.controller,
    required this.label,
    required this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.maxLines = 1,
    this.onChanged,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      maxLines: maxLines,
      onChanged: onChanged,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: _configInputDecoration(
        labelText: label,
        hintText: hintText,
      ).copyWith(suffixIcon: suffixIcon),
    );
  }
}
