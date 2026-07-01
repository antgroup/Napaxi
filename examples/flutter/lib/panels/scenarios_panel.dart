part of '../main.dart';

const String _generalScenarioId = 'napaxi.scenario.general';
const String _mobileDevelopmentScenarioId = 'napaxi.scenario.mobile_development';
const Set<String> _demoScenarioIds = {
  _generalScenarioId,
  _mobileDevelopmentScenarioId,
};

class ScenariosPanel extends StatefulWidget {
  const ScenariosPanel({
    super.key,
    required this.clientFuture,
    required this.activeScenarioId,
    required this.gitSettings,
    required this.onScenarioApplied,
    required this.onGitSettingsChanged,
    required this.onGitSettingsCleared,
    this.embedded = false,
    this.onBack,
  });

  final Future<NapaxiChatClient> clientFuture;
  final String activeScenarioId;
  final DemoGitSettings gitSettings;
  final Future<void> Function(String scenarioId) onScenarioApplied;
  final Future<void> Function(DemoGitSettings settings) onGitSettingsChanged;
  final Future<void> Function() onGitSettingsCleared;
  final bool embedded;
  final Future<bool> Function()? onBack;

  @override
  State<ScenariosPanel> createState() => _ScenariosPanelState();
}

class _ScenariosPanelState extends State<ScenariosPanel> {
  List<sdk.NapaxiScenarioPack> _packs = const [];
  List<sdk.NapaxiScenarioStatus> _statuses = const [];
  String? _selectedScenarioId;
  String? _applyingScenarioId;
  Object? _error;
  bool _loading = true;
  NapaxiChatClient? _client;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<NapaxiChatClient> _getClient() async {
    return _client ??= await widget.clientFuture;
  }

  Future<void> _refresh({String? selectScenarioId}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = await _getClient();
      final packs = _demoScenarioPacks(await client.listScenarioPacks());
      final statuses = _demoScenarioStatuses(
        await client.listScenarioStatuses(),
      );
      final selected = _selectScenarioId(packs, selectScenarioId);
      if (!mounted) return;
      setState(() {
        _packs = packs;
        _statuses = statuses;
        _selectedScenarioId = selected;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  String? _selectScenarioId(
    List<sdk.NapaxiScenarioPack> packs,
    String? requested,
  ) {
    bool has(String id) => packs.any((pack) => pack.id == id);
    if (requested != null && has(requested)) return requested;
    final current = _selectedScenarioId;
    if (current != null && has(current)) return current;
    final normalized = _normalizeDemoScenarioId(widget.activeScenarioId);
    if (has(normalized)) return normalized;
    if (has(_generalScenarioId)) return _generalScenarioId;
    if (has(_mobileDevelopmentScenarioId)) return _mobileDevelopmentScenarioId;
    return packs.isEmpty ? null : packs.first.id;
  }

  Future<void> _applySelectedScenario() async {
    final scenarioId = _selectedScenarioId;
    if (scenarioId == null || _applyingScenarioId != null) return;
    setState(() {
      _applyingScenarioId = scenarioId;
      _error = null;
    });
    try {
      await widget.onScenarioApplied(scenarioId);
      await _refresh(selectScenarioId: scenarioId);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() => _applyingScenarioId = null);
      }
    }
  }

  void _selectScenario(String id) {
    setState(() {
      _selectedScenarioId = id;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final selected = _packs
        .where((pack) => pack.id == _selectedScenarioId)
        .firstOrNull;
    final selectedStatus = _statuses
        .where((status) => status.definition.id == _selectedScenarioId)
        .firstOrNull;
    final activeScenarioId = _normalizeDemoScenarioId(widget.activeScenarioId);

    final body = SafeArea(
      child: _loading && _packs.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  if (widget.embedded) ...[
                    _EmbeddedSettingsHeader(title: strings.scenariosTitle),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    strings.scenarioCurrentLabel(
                      _scenarioLabelForId(strings, activeScenarioId),
                    ),
                    style: const TextStyle(
                      color: _configTextSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final pack in _packs)
                        ChoiceChip(
                          label: Text(_scenarioLabel(strings, pack)),
                          selected: pack.id == _selectedScenarioId,
                          onSelected: (_) => _selectScenario(pack.id),
                          showCheckmark: false,
                          selectedColor: _configSelectedSurface,
                          backgroundColor: _configSurface,
                          disabledColor: _configSurfaceMuted,
                          side: BorderSide(
                            color: pack.id == _selectedScenarioId
                                ? _configTextPrimary
                                : _configBorderFaint,
                          ),
                          labelStyle: TextStyle(
                            color: pack.id == _selectedScenarioId
                                ? _configTextPrimary
                                : _configTextSecondary,
                            fontSize: 13,
                            fontWeight: pack.id == _selectedScenarioId
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _ScenarioNotice(error: _error),
                  ],
                  const SizedBox(height: 14),
                  if (selected == null)
                    Text(
                      strings.noScenariosTitle,
                      style: const TextStyle(
                        color: _configTextSecondary,
                        fontSize: 14,
                      ),
                    )
                  else ...[
                    _ScenarioPackCard(pack: selected, status: selectedStatus),
                    const SizedBox(height: 12),
                    _ScenarioApplyCard(
                      pack: selected,
                      isActive: selected.id == activeScenarioId,
                      isApplying: _applyingScenarioId == selected.id,
                      onApply: _applySelectedScenario,
                    ),
                    if (selected.settingsContributions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _ScenarioSettingsContributionsCard(
                        pack: selected,
                        gitSettings: widget.gitSettings,
                        onGitSettingsChanged: widget.onGitSettingsChanged,
                        onGitSettingsCleared: widget.onGitSettingsCleared,
                      ),
                    ],
                  ],
                ],
              ),
            ),
    );

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: _configPageBackground,
      appBar: AppBar(
        title: Text(strings.scenariosTitle),
        backgroundColor: _configPageBackground,
        foregroundColor: _configTextPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(
          onPressed: () async {
            final handled = await widget.onBack?.call();
            if (handled != false && context.mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: body,
    );
  }
}

class _ScenarioNotice extends StatelessWidget {
  const _ScenarioNotice({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _configSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: _configTextSecondary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _friendlyDisplayError(error),
                    style: const TextStyle(
                      color: _configTextSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScenarioRuntimeBar extends StatelessWidget {
  const _ScenarioRuntimeBar({required this.scenarioId, required this.onTap});

  final String scenarioId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Material(
      color: _configSurface,
      child: InkWell(
        key: const Key('active_scenario_bar'),
        onTap: onTap,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _configBorderFaint)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.tune_rounded,
                  size: 16,
                  color: _configTextSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strings.scenarioCurrentLabel(
                      _scenarioLabelForId(strings, scenarioId),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _configTextSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: _configTextTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScenarioApplyCard extends StatelessWidget {
  const _ScenarioApplyCard({
    required this.pack,
    required this.isActive,
    required this.isApplying,
    required this.onApply,
  });

  final sdk.NapaxiScenarioPack pack;
  final bool isActive;
  final bool isApplying;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final buttonLabel = isActive
        ? strings.scenarioAppliedButton
        : isApplying
        ? strings.scenarioApplyingButton
        : strings.scenarioApplyButton;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _configSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                strings.scenarioApplyHint(_scenarioLabel(strings, pack)),
                style: const TextStyle(
                  color: _configTextSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              key: const Key('scenario_apply_button'),
              onPressed: isActive || isApplying ? null : onApply,
              style: FilledButton.styleFrom(
                backgroundColor: _configTextPrimary,
                disabledBackgroundColor: _configSurfaceMuted,
                disabledForegroundColor: _configTextTertiary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                minimumSize: const Size(92, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: isApplying
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _configTextTertiary,
                      ),
                    )
                  : Text(
                      buttonLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScenarioSettingsContributionsCard extends StatelessWidget {
  const _ScenarioSettingsContributionsCard({
    required this.pack,
    required this.gitSettings,
    required this.onGitSettingsChanged,
    required this.onGitSettingsCleared,
  });

  final sdk.NapaxiScenarioPack pack;
  final DemoGitSettings gitSettings;
  final Future<void> Function(DemoGitSettings settings) onGitSettingsChanged;
  final Future<void> Function() onGitSettingsCleared;

  @override
  Widget build(BuildContext context) {
    final contributions = pack.settingsContributions
        .where((contribution) {
          final placement = contribution.placement.trim().toLowerCase();
          return placement.isEmpty || placement == 'scenario_settings';
        })
        .toList(growable: false);
    if (contributions.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      color: _configSurface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: _configBorderFaint),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.extension_rounded,
                  color: _configTextSecondary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _scenarioSettingsTitle(context),
                    style: const TextStyle(
                      color: _configTextPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final contribution in contributions) ...[
              if (_isGitSettingsContribution(contribution))
                _GitSettingsContributionForm(
                  contribution: contribution,
                  settings: gitSettings,
                  onChanged: onGitSettingsChanged,
                  onCleared: onGitSettingsCleared,
                )
              else
                const _UnsupportedScenarioSetting(),
              if (contribution != contributions.last) const Divider(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}

class _GitSettingsContributionForm extends StatefulWidget {
  const _GitSettingsContributionForm({
    required this.contribution,
    required this.settings,
    required this.onChanged,
    required this.onCleared,
  });

  final sdk.NapaxiScenarioSettingsContribution contribution;
  final DemoGitSettings settings;
  final Future<void> Function(DemoGitSettings settings) onChanged;
  final Future<void> Function() onCleared;

  @override
  State<_GitSettingsContributionForm> createState() =>
      _GitSettingsContributionFormState();
}

class _GitSettingsContributionFormState
    extends State<_GitSettingsContributionForm> {
  late final TextEditingController _serverController;
  late final TextEditingController _usernameController;
  late final TextEditingController _secretController;
  late final TextEditingController _commitNameController;
  late final TextEditingController _commitEmailController;
  String _authMethod = 'token';
  bool _secretVisible = false;
  bool _saving = false;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController();
    _usernameController = TextEditingController();
    _secretController = TextEditingController();
    _commitNameController = TextEditingController();
    _commitEmailController = TextEditingController();
    _syncControllers(widget.settings);
  }

  @override
  void didUpdateWidget(covariant _GitSettingsContributionForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _syncControllers(widget.settings);
    }
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _secretController.dispose();
    _commitNameController.dispose();
    _commitEmailController.dispose();
    super.dispose();
  }

  void _syncControllers(DemoGitSettings settings) {
    final serverDefault = _schemaDefault(widget.contribution, 'server', '');
    _serverController.text = settings.server.trim().isEmpty
        ? serverDefault
        : settings.server;
    _usernameController.text = settings.username;
    _secretController.clear();
    _commitNameController.text = settings.commitName;
    _commitEmailController.text = settings.commitEmail;
    _authMethod = settings.normalizedAuthMethod;
  }

  Future<void> _save() async {
    if (_saving || _clearing) return;
    final savedLabel = _gitSettingsSavedLabel(context);
    final server = _serverController.text.trim();
    final username = _usernameController.text.trim();
    final secret = _secretController.text.trim();
    if (server.isEmpty && (username.isNotEmpty || secret.isNotEmpty)) {
      _showScenarioSnackBar(context, _gitSettingsServerRequiredLabel(context));
      return;
    }
    setState(() => _saving = true);
    try {
      final next = DemoGitSettings.fromForm(
        server: server,
        authMethod: _authMethod,
        username: username,
        secret: secret,
        previous: widget.settings,
        commitName: _commitNameController.text,
        commitEmail: _commitEmailController.text,
      );
      await widget.onChanged(next);
      _secretController.clear();
      if (mounted) _showScenarioSnackBar(context, savedLabel);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    if (_saving || _clearing) return;
    final clearedLabel = _gitSettingsClearedLabel(context);
    setState(() => _clearing = true);
    try {
      await widget.onCleared();
      _secretController.clear();
      if (mounted) _showScenarioSnackBar(context, clearedLabel);
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = _AppLanguageScope.languageOf(context);
    final settings = widget.settings;
    final canClear = settings.configured || settings.credentialRef.isNotEmpty;
    final isBusy = _saving || _clearing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _gitSettingsTitle(context, widget.contribution),
                    style: const TextStyle(
                      color: _configTextPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (widget.contribution.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _gitSettingsDescription(context),
                      style: const TextStyle(
                        color: _configTextSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            _GitSettingsStatusPill(settings: settings),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('git_settings_server_field'),
          controller: _serverController,
          enabled: !isBusy,
          textInputAction: TextInputAction.next,
          decoration: _configInputDecoration(
            labelText: language == AppLanguage.chinese
                ? '平台地址'
                : _schemaTitle(widget.contribution, 'server', 'Git host'),
            hintText: language == AppLanguage.chinese
                ? 'github.com、gitlab.com 或公司 Git 地址'
                : 'github.com, gitlab.com, or your company Git host',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('git_settings_auth_method_field'),
          initialValue: _authMethod,
          decoration: _configInputDecoration(
            labelText: language == AppLanguage.chinese
                ? '认证方式'
                : _schemaTitle(
                    widget.contribution,
                    'auth_method',
                    'Auth method',
                  ),
          ),
          items: [
            DropdownMenuItem(
              value: 'token',
              child: Text(language == AppLanguage.chinese ? 'Token' : 'Token'),
            ),
            DropdownMenuItem(
              value: 'ssh',
              child: Text(language == AppLanguage.chinese ? 'SSH' : 'SSH'),
            ),
          ],
          onChanged: isBusy
              ? null
              : (value) => setState(() => _authMethod = value ?? 'token'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('git_settings_username_field'),
          controller: _usernameController,
          enabled: !isBusy,
          textInputAction: TextInputAction.next,
          decoration: _configInputDecoration(
            labelText: language == AppLanguage.chinese
                ? '用户名'
                : _schemaTitle(widget.contribution, 'username', 'Username'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('git_settings_token_field'),
          controller: _secretController,
          enabled: !isBusy,
          obscureText: !_secretVisible,
          textInputAction: TextInputAction.done,
          decoration: _configInputDecoration(
            labelText: language == AppLanguage.chinese
                ? 'Token'
                : _schemaTitle(widget.contribution, 'token', 'Token'),
            helperText: settings.credentialRef.isEmpty
                ? null
                : (language == AppLanguage.chinese
                      ? '已保存凭证，留空会沿用现有凭证。'
                      : 'A credential is saved. Leave blank to keep it.'),
            suffixIcon: IconButton(
              tooltip: _secretVisible
                  ? (language == AppLanguage.chinese ? '隐藏' : 'Hide')
                  : (language == AppLanguage.chinese ? '显示' : 'Show'),
              onPressed: () => setState(() => _secretVisible = !_secretVisible),
              icon: Icon(
                _secretVisible
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
            ),
          ),
          onSubmitted: (_) => unawaited(_save()),
        ),
        const SizedBox(height: 14),
        Text(
          language == AppLanguage.chinese ? '提交身份' : 'Commit identity',
          style: const TextStyle(
            color: _configTextSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('git_settings_commit_name_field'),
          controller: _commitNameController,
          enabled: !isBusy,
          textInputAction: TextInputAction.next,
          decoration: _configInputDecoration(
            labelText: language == AppLanguage.chinese
                ? '提交名称'
                : _schemaTitle(
                    widget.contribution,
                    'commit_name',
                    'Commit name',
                  ),
            helperText: language == AppLanguage.chinese
                ? '写入沙箱 ~/.gitconfig，用作 git commit 作者。'
                : 'Written to the sandbox ~/.gitconfig as the commit author.',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('git_settings_commit_email_field'),
          controller: _commitEmailController,
          enabled: !isBusy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: _configInputDecoration(
            labelText: language == AppLanguage.chinese
                ? '提交邮箱'
                : _schemaTitle(
                    widget.contribution,
                    'commit_email',
                    'Commit email',
                  ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('git_settings_save_button'),
                onPressed: isBusy ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _configTextTertiary,
                        ),
                      )
                    : const Icon(Icons.save_rounded, size: 18),
                label: Text(
                  language == AppLanguage.chinese ? '保存' : 'Save',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _configTextPrimary,
                  disabledBackgroundColor: _configSurfaceMuted,
                  disabledForegroundColor: _configTextTertiary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  minimumSize: const Size(92, 42),
                ),
              ),
            ),
            if (canClear) ...[
              const SizedBox(width: 10),
              OutlinedButton.icon(
                key: const Key('git_settings_clear_button'),
                onPressed: isBusy ? null : _clear,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text(
                  language == AppLanguage.chinese ? '清除' : 'Clear',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _configTextPrimary,
                  side: const BorderSide(color: _configBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  minimumSize: const Size(88, 42),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _GitSettingsStatusPill extends StatelessWidget {
  const _GitSettingsStatusPill({required this.settings});

  final DemoGitSettings settings;

  @override
  Widget build(BuildContext context) {
    final language = _AppLanguageScope.languageOf(context);
    final label = settings.isReady
        ? (language == AppLanguage.chinese ? '就绪' : 'Ready')
        : settings.configured
        ? (language == AppLanguage.chinese ? '待验证' : 'Pending')
        : (language == AppLanguage.chinese ? '未配置' : 'Not set');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: settings.isReady ? _configSelectedSurface : _configSurfaceMuted,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            color: _configTextSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _UnsupportedScenarioSetting extends StatelessWidget {
  const _UnsupportedScenarioSetting();

  @override
  Widget build(BuildContext context) {
    final language = _AppLanguageScope.languageOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _configSurfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          language == AppLanguage.chinese
              ? '这个设置暂时不能在当前版本中显示。'
              : 'This setting is not available in this version.',
          style: const TextStyle(
            color: _configTextSecondary,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class _ScenarioPackCard extends StatelessWidget {
  const _ScenarioPackCard({required this.pack, required this.status});

  final sdk.NapaxiScenarioPack pack;
  final sdk.NapaxiScenarioStatus? status;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Card(
      elevation: 0,
      color: _configSurface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: _configBorderFaint),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ScenarioStatusDot(status: status),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _scenarioLabel(strings, pack),
                    style: const TextStyle(
                      color: _configTextPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_scenarioDescription(strings, pack).isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _scenarioDescription(strings, pack),
                style: const TextStyle(
                  color: _configTextSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              _scenarioSimpleStatus(context, status),
              style: const TextStyle(
                color: _configTextSecondary,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScenarioStatusDot extends StatelessWidget {
  const _ScenarioStatusDot({required this.status});

  final sdk.NapaxiScenarioStatus? status;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final color = status?.enabled == true
        ? _configTextPrimary
        : status?.available == true
        ? _configTextSecondary
        : _configTextTertiary;
    return Tooltip(
      message: status?.enabled == true
          ? strings.scenarioEnabledStatus
          : status?.available == true
          ? strings.scenarioAvailableStatus
          : strings.scenarioUnavailableStatus,
      child: Icon(Icons.radio_button_checked_rounded, size: 14, color: color),
    );
  }
}

String _scenarioSimpleStatus(
  BuildContext context,
  sdk.NapaxiScenarioStatus? status,
) {
  final language = _AppLanguageScope.languageOf(context);
  if (status == null) {
    return language == AppLanguage.chinese ? '正在读取状态' : 'Reading status';
  }
  if (status.enabled) {
    return language == AppLanguage.chinese ? '当前正在使用' : 'Currently active';
  }
  if (status.available || status.registered) {
    return language == AppLanguage.chinese ? '可以切换使用' : 'Available to switch';
  }
  return language == AppLanguage.chinese ? '暂时不能切换' : 'Not available right now';
}

bool _isGitSettingsContribution(
  sdk.NapaxiScenarioSettingsContribution contribution,
) {
  return contribution.id.trim().toLowerCase() == _gitSettingsContributionId ||
      contribution.capabilityId.trim().toLowerCase() ==
          _DemoAutomationToolExecutor.gitCapabilityId;
}

String _scenarioSettingsTitle(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? 'Git 凭证'
      : 'Git credentials';
}

String _gitSettingsTitle(
  BuildContext context,
  sdk.NapaxiScenarioSettingsContribution contribution,
) {
  final title = contribution.title.trim();
  if (title.isNotEmpty &&
      _AppLanguageScope.languageOf(context) != AppLanguage.chinese) {
    return title;
  }
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '默认账号'
      : 'Default account';
}

String _gitSettingsDescription(BuildContext context) {
  final language = _AppLanguageScope.languageOf(context);
  return language == AppLanguage.chinese
      ? '可填 GitHub、GitLab、Gitee 或公司 Git 地址。当前保存一组默认凭证；公开仓库无需配置。'
      : 'Use GitHub, GitLab, Gitee, or a company Git host. One default credential is saved; public repositories need no setup.';
}

String _gitSettingsSavedLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? 'Git 配置已保存'
      : 'Git settings saved';
}

String _gitSettingsClearedLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? 'Git 配置已清除'
      : 'Git settings cleared';
}

String _gitSettingsServerRequiredLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '请先填写平台地址'
      : 'Enter a Git host first';
}

void _showScenarioSnackBar(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

String _schemaTitle(
  sdk.NapaxiScenarioSettingsContribution contribution,
  String field,
  String fallback,
) {
  final fieldSchema = _schemaField(contribution, field);
  final title = fieldSchema?['title'] as String?;
  return title == null || title.trim().isEmpty ? fallback : title.trim();
}

String _schemaDefault(
  sdk.NapaxiScenarioSettingsContribution contribution,
  String field,
  String fallback,
) {
  final fieldSchema = _schemaField(contribution, field);
  final value = fieldSchema?['default'];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return fallback;
}

Map<String, dynamic>? _schemaField(
  sdk.NapaxiScenarioSettingsContribution contribution,
  String field,
) {
  final properties = contribution.schema['properties'];
  if (properties is! Map) return null;
  final value = properties[field];
  if (value is! Map) return null;
  return Map<String, dynamic>.from(value);
}

List<sdk.NapaxiScenarioPack> _demoScenarioPacks(
  List<sdk.NapaxiScenarioPack> packs,
) {
  final filtered = [
    for (final pack in packs)
      if (_demoScenarioIds.contains(pack.id)) pack,
  ];
  filtered.sort(
    (a, b) => _demoScenarioSortKey(a.id) - _demoScenarioSortKey(b.id),
  );
  return filtered;
}

List<sdk.NapaxiScenarioStatus> _demoScenarioStatuses(
  List<sdk.NapaxiScenarioStatus> statuses,
) {
  return [
    for (final status in statuses)
      if (_demoScenarioIds.contains(status.definition.id)) status,
  ];
}

int _demoScenarioSortKey(String id) {
  return switch (id) {
    _generalScenarioId => 0,
    _mobileDevelopmentScenarioId => 1,
    _ => 99,
  };
}

String _normalizeDemoScenarioId(String? id) {
  final normalized = (id ?? '').trim().toLowerCase();
  return _demoScenarioIds.contains(normalized)
      ? normalized
      : _generalScenarioId;
}

sdk.NapaxiCapabilitySelection _scenarioCapabilitySelection(
  String scenarioId, {
  DemoGitSettings? gitSettings,
  String? developerEngineId,
}) {
  final normalized = _normalizeDemoScenarioId(scenarioId);
  final runtimeProfile = _scenarioRuntimeProfileFor(
    normalized,
    developerEngineId: developerEngineId,
  );
  final config = <String, dynamic>{
    'scenario_id': normalized,
    'account_id': runtimeProfile.accountId,
    'agent_id': runtimeProfile.agentId,
    if (runtimeProfile.isDeveloper)
      'developer_engine_id': runtimeProfile.activeEngineId,
  };
  if (normalized == _mobileDevelopmentScenarioId && gitSettings != null) {
    config.addAll(gitSettings.toJson());
  }
  return sdk.NapaxiCapabilitySelection(
    enabledCapabilities: _scenarioEnabledCapabilities(normalized),
    config: config,
  );
}

List<String> _scenarioEnabledCapabilities(String scenarioId) {
  final capabilities = switch (_normalizeDemoScenarioId(scenarioId)) {
    _mobileDevelopmentScenarioId => <String>[
      'napaxi.service.scenario_registry',
      'napaxi.agent_engine.napaxi_core',
      'napaxi.service.developer_workbench',
      'napaxi.tool.file',
      'napaxi.tool.ask_human',
      'napaxi.tool.agent_app_action',
      'napaxi.tool.git',
      'napaxi.tool.shell_remote',
      'napaxi.policy.approval',
      'napaxi.policy.runtime_gate',
      'napaxi.service.context_engine',
      'napaxi.tool.skill',
      'napaxi.mcp.runtime',
      'napaxi.tool.custom_host',
      'napaxi.tool.browser',
    ],
    _ => <String>[
      'napaxi.service.scenario_registry',
      'napaxi.agent_engine.napaxi_core',
      'napaxi.tool.ask_human',
      'napaxi.tool.agent_app_action',
      'napaxi.tool.memory',
      'napaxi.tool.file',
      'napaxi.policy.runtime_gate',
      'napaxi.tool.web_search',
      'napaxi.tool.web_fetch',
      'napaxi.tool.skill',
      'napaxi.service.context_engine',
    ],
  };
  return List.unmodifiable({...capabilities}.toList()..sort());
}

String _scenarioLabelForId(AppStrings strings, String scenarioId) {
  final normalized = _normalizeDemoScenarioId(scenarioId);
  return strings.scenarioPackLabel(normalized, normalized);
}

String _compactLabel(String label, String fallback) {
  final trimmed = label.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

String _scenarioLabel(AppStrings strings, sdk.NapaxiScenarioPack pack) {
  return strings.scenarioPackLabel(pack.id, _compactLabel(pack.label, pack.id));
}

String _scenarioDescription(AppStrings strings, sdk.NapaxiScenarioPack pack) {
  return strings.scenarioPackDescription(pack.id, pack.description.trim());
}
