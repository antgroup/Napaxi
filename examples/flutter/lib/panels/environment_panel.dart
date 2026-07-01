part of '../main.dart';

const sdk.NapaxiScenarioUiContribution
_fallbackEnvironmentContribution = sdk.NapaxiScenarioUiContribution(
  id: 'ui.developer_environment',
  capabilityId: 'napaxi.service.developer_workbench',
  placement: 'left_menu',
  title: 'Environment',
  icon: 'terminal',
  renderer: 'environment',
  dataSources: {'tools': 'environment.tools', 'status': 'environment.status'},
  actions: ['install_tool', 'check_tools', 'change_tool_version', 'add_tool'],
);

const String _developmentEnvironmentToolsKey =
    'scenario.environment.tools.android_apk_skill.v1';

const MethodChannel _environmentPlatformChannel = MethodChannel(
  'com.napaxi.flutter/platform_context',
);

enum DemoEnvironmentToolStatus {
  unknown,
  missing,
  installing,
  installed,
  updateAvailable,
  installFailed,
}

class DemoEnvironmentTool {
  const DemoEnvironmentTool({
    required this.id,
    required this.name,
    required this.category,
    required this.targetVersion,
    this.installedVersion = '',
    this.status = DemoEnvironmentToolStatus.unknown,
    this.checkCommand = '',
    this.installCommand = '',
    this.timeoutSeconds = 120,
    this.custom = false,
  });

  final String id;
  final String name;
  final String category;
  final String targetVersion;
  final String installedVersion;
  final DemoEnvironmentToolStatus status;
  final String checkCommand;
  final String installCommand;
  final int timeoutSeconds;
  final bool custom;

  bool get hasInstalledVersion => installedVersion.trim().isNotEmpty;

  DemoEnvironmentTool copyWith({
    String? id,
    String? name,
    String? category,
    String? targetVersion,
    String? installedVersion,
    DemoEnvironmentToolStatus? status,
    String? checkCommand,
    String? installCommand,
    int? timeoutSeconds,
    bool? custom,
  }) {
    return DemoEnvironmentTool(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      targetVersion: targetVersion ?? this.targetVersion,
      installedVersion: installedVersion ?? this.installedVersion,
      status: status ?? this.status,
      checkCommand: checkCommand ?? this.checkCommand,
      installCommand: installCommand ?? this.installCommand,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      custom: custom ?? this.custom,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'target_version': targetVersion,
      'installed_version': installedVersion,
      'status': _persistentEnvironmentStatus(status).name,
      'check_command': checkCommand,
      'install_command': installCommand,
      'timeout_seconds': timeoutSeconds,
      'custom': custom,
    };
  }

  factory DemoEnvironmentTool.fromJson(Map<String, dynamic> json) {
    final statusName = (json['status'] as String? ?? '').trim();
    final status = DemoEnvironmentToolStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => DemoEnvironmentToolStatus.unknown,
    );
    final persistentStatus = _persistentEnvironmentStatus(status);
    return DemoEnvironmentTool(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      category: (json['category'] as String? ?? '').trim(),
      targetVersion: (json['target_version'] as String? ?? '').trim(),
      installedVersion: (json['installed_version'] as String? ?? '').trim(),
      status: persistentStatus,
      checkCommand: (json['check_command'] as String? ?? '').trim(),
      installCommand: (json['install_command'] as String? ?? '').trim(),
      timeoutSeconds: json['timeout_seconds'] as int? ?? 120,
      custom: json['custom'] as bool? ?? false,
    );
  }
}

class DemoPresetSkill {
  const DemoPresetSkill({
    required this.name,
    required this.title,
    required this.description,
    required this.skillContent,
  });

  final String name;
  final String title;
  final String description;
  final String skillContent;
}

class _EnvironmentCommandResult {
  const _EnvironmentCommandResult({
    required this.success,
    required this.output,
    this.error = '',
  });

  final bool success;
  final String output;
  final String error;
}

DemoEnvironmentToolStatus _persistentEnvironmentStatus(
  DemoEnvironmentToolStatus status,
) {
  return switch (status) {
    DemoEnvironmentToolStatus.installing ||
    DemoEnvironmentToolStatus.installFailed =>
      DemoEnvironmentToolStatus.unknown,
    _ => status,
  };
}

class _DevelopmentEnvironmentPage extends StatefulWidget {
  const _DevelopmentEnvironmentPage({
    required this.clientFuture,
    required this.agentId,
    required this.contribution,
    this.onBack,
  });

  final Future<NapaxiChatClient> clientFuture;
  final String agentId;
  final sdk.NapaxiScenarioUiContribution contribution;
  final Future<bool> Function()? onBack;

  @override
  State<_DevelopmentEnvironmentPage> createState() =>
      _DevelopmentEnvironmentPageState();
}

class _DevelopmentEnvironmentPageState
    extends State<_DevelopmentEnvironmentPage> {
  List<DemoEnvironmentTool> _tools = const [];
  Set<String> _installedPresetSkills = const {};
  bool _loading = true;
  bool _presetSkillsLoading = true;
  bool _checking = false;
  String _lastMessage = '';
  String _presetSkillMessage = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadTools());
    unawaited(_loadPresetSkills());
  }

  Future<void> _loadTools() async {
    final tools = await _loadDemoEnvironmentTools();
    if (!mounted) return;
    setState(() {
      _tools = tools;
      _loading = false;
    });
  }

  Future<void> _loadPresetSkills() async {
    try {
      final client = await widget.clientFuture;
      final skills = await client.listSkills(agentId: widget.agentId);
      if (!mounted) return;
      setState(() {
        _installedPresetSkills = {
          for (final skill in skills) skill.name.trim().toLowerCase(),
        };
        _presetSkillsLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _presetSkillsLoading = false;
        _presetSkillMessage = _presetSkillLoadFailed(context, error);
      });
    }
  }

  Future<void> _saveTools(
    List<DemoEnvironmentTool> tools, {
    String message = '',
  }) async {
    await _saveDemoEnvironmentTools(tools);
    if (!mounted) return;
    setState(() {
      _tools = List.unmodifiable(tools);
      _lastMessage = message;
    });
    if (message.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _installTool(DemoEnvironmentTool tool) async {
    final command = tool.installCommand.trim();
    if (command.isEmpty) {
      await _saveTools(_tools, message: _toolInstallUnavailable(context, tool));
      return;
    }
    await _saveTools(
      _replaceTool(
        tool.id,
        (item) => item.copyWith(status: DemoEnvironmentToolStatus.installing),
      ),
      message: _toolInstallStarted(context, tool),
    );
    final result = await _runEnvironmentShell(
      command,
      timeoutSeconds: tool.timeoutSeconds,
    );
    if (!mounted) return;
    final checked = result.success
        ? await _checkedTool(tool)
        : tool.copyWith(status: DemoEnvironmentToolStatus.installFailed);
    if (!mounted) return;
    await _saveTools(
      _replaceTool(tool.id, (_) => checked),
      message: result.success
          ? _toolInstallSucceeded(context, checked)
          : _toolInstallFailed(context, tool, result),
    );
  }

  Future<void> _markInstalled(DemoEnvironmentTool tool) async {
    final version = tool.installedVersion.trim().isEmpty
        ? tool.targetVersion
        : tool.installedVersion.trim();
    final next = _tools
        .map(
          (item) => item.id == tool.id
              ? item.copyWith(
                  status: DemoEnvironmentToolStatus.installed,
                  installedVersion: version,
                )
              : item,
        )
        .toList(growable: false);
    await _saveTools(next, message: _toolMarkedInstalled(context, tool));
  }

  Future<void> _checkTools() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _lastMessage = _toolCheckStarted(context);
    });
    final next = <DemoEnvironmentTool>[];
    for (final tool in _tools) {
      next.add(await _checkedTool(tool));
    }
    if (!mounted) return;
    setState(() => _checking = false);
    await _saveTools(next, message: _toolCheckFinished(context, next));
  }

  Future<DemoEnvironmentTool> _checkedTool(DemoEnvironmentTool tool) async {
    final checkCommand = tool.checkCommand.trim();
    if (checkCommand.isEmpty) {
      return tool.copyWith(
        status: _statusForVersions(
          targetVersion: tool.targetVersion,
          installedVersion: tool.installedVersion,
        ),
      );
    }
    final result = await _runEnvironmentShell(
      checkCommand,
      timeoutSeconds: tool.timeoutSeconds.clamp(1, 120).toInt(),
    );
    if (!result.success) {
      return tool.copyWith(status: DemoEnvironmentToolStatus.missing);
    }
    final detectedVersion = _firstOutputLine(result.output);
    final installedVersion = detectedVersion.isEmpty
        ? tool.targetVersion
        : detectedVersion;
    return tool.copyWith(
      installedVersion: installedVersion,
      status: _statusForVersions(
        targetVersion: tool.targetVersion,
        installedVersion: installedVersion,
      ),
    );
  }

  List<DemoEnvironmentTool> _replaceTool(
    String toolId,
    DemoEnvironmentTool Function(DemoEnvironmentTool item) replace,
  ) {
    return _tools
        .map((item) => item.id == toolId ? replace(item) : item)
        .toList(growable: false);
  }

  Future<_EnvironmentCommandResult> _runEnvironmentShell(
    String command, {
    required int timeoutSeconds,
  }) async {
    if (!Platform.isAndroid) {
      return const _EnvironmentCommandResult(
        success: false,
        output: '',
        error: 'Android Linux environment is only available on Android.',
      );
    }
    try {
      final supportDir = await getApplicationSupportDirectory();
      final workspaceDir = Directory(
        '${supportDir.path}/environment-workspace',
      );
      if (!workspaceDir.existsSync()) {
        workspaceDir.createSync(recursive: true);
      }
      final response = await _environmentPlatformChannel
          .invokeMethod<String>('executeLinuxProgram', {
            'workspaceDir': workspaceDir.path,
            'argv': ['/bin/sh', '-lc', command],
            'workdir': '/workspace',
            'timeout': timeoutSeconds.clamp(1, 600).toInt(),
          })
          .timeout(Duration(seconds: timeoutSeconds.clamp(1, 600).toInt() + 5));
      final decoded = jsonDecode(response ?? '{}');
      if (decoded is! Map) {
        return const _EnvironmentCommandResult(
          success: false,
          output: '',
          error: 'Invalid command response.',
        );
      }
      final map = Map<String, dynamic>.from(decoded);
      final stdout = (map['stdout'] ?? '').toString().trim();
      final stderr = (map['stderr'] ?? '').toString().trim();
      final error = (map['error'] ?? '').toString().trim();
      final success =
          (map['success'] as bool? ?? false) &&
          (map['exitCode'] as int? ?? -1) == 0;
      return _EnvironmentCommandResult(
        success: success,
        output: stdout.isNotEmpty ? stdout : stderr,
        error: error.isNotEmpty ? error : stderr,
      );
    } on TimeoutException {
      return _EnvironmentCommandResult(
        success: false,
        output: '',
        error: 'Command timed out after ${timeoutSeconds}s.',
      );
    } on MissingPluginException {
      return const _EnvironmentCommandResult(
        success: false,
        output: '',
        error: 'Android Linux bridge is not available.',
      );
    } on PlatformException catch (error) {
      return _EnvironmentCommandResult(
        success: false,
        output: '',
        error: error.message ?? error.code,
      );
    } catch (error) {
      return _EnvironmentCommandResult(
        success: false,
        output: '',
        error: error.toString(),
      );
    }
  }

  Future<void> _editVersion(DemoEnvironmentTool tool) async {
    final result = await showModalBottomSheet<_ToolVersionEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ToolVersionSheet(tool: tool),
    );
    if (result == null) return;
    if (!mounted) return;
    final next = _tools
        .map(
          (item) => item.id == tool.id
              ? item.copyWith(
                  targetVersion: result.targetVersion,
                  installedVersion: result.installedVersion,
                  status: _statusForVersions(
                    targetVersion: result.targetVersion,
                    installedVersion: result.installedVersion,
                  ),
                )
              : item,
        )
        .toList(growable: false);
    await _saveTools(next, message: _toolVersionSaved(context, tool));
  }

  Future<void> _addTool() async {
    final tool = await showModalBottomSheet<DemoEnvironmentTool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AddToolSheet(),
    );
    if (tool == null) return;
    if (!mounted) return;
    final normalizedId = tool.id.trim().isEmpty
        ? _toolIdFromName(tool.name)
        : tool.id.trim();
    final normalizedName = tool.name.trim().toLowerCase();
    if (_tools.any(
      (item) =>
          item.id == normalizedId ||
          item.name.trim().toLowerCase() == normalizedName,
    )) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_toolAlreadyExists(context))));
      return;
    }
    await _saveTools(
      List.unmodifiable([..._tools, tool.copyWith(id: normalizedId)]),
      message: _toolAdded(context, tool),
    );
  }

  Future<void> _resetDefaults() async {
    await _saveTools(
      _defaultEnvironmentTools(),
      message: _environmentDefaultsRestored(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupTools(_tools);
    return Scaffold(
      backgroundColor: _configPageBackground,
      appBar: AppBar(
        title: Text(
          _environmentContributionTitle(context, widget.contribution),
        ),
        backgroundColor: _configPageBackground,
        foregroundColor: _configTextPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            key: const Key('environment_add_tool_button'),
            onPressed: _loading ? null : _addTool,
            child: Text(_addToolLabel(context)),
          ),
        ],
        leading: BackButton(
          onPressed: () async {
            final handled = await widget.onBack?.call();
            if (handled != false && context.mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              key: const Key('environment_page'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                _EnvironmentOverviewCard(
                  tools: _tools,
                  checking: _checking,
                  lastMessage: _lastMessage,
                  onCheck: _checkTools,
                  onResetDefaults: _resetDefaults,
                ),
                const SizedBox(height: 12),
                _PresetSkillsCard(
                  skills: _defaultPresetSkills(),
                  installedSkillNames: _installedPresetSkills,
                  loading: _presetSkillsLoading,
                  message: _presetSkillMessage,
                  onRefresh: _loadPresetSkills,
                ),
                const SizedBox(height: 12),
                for (final entry in grouped.entries) ...[
                  _EnvironmentToolGroup(
                    title: entry.key,
                    tools: entry.value,
                    onInstall: _installTool,
                    onMarkInstalled: _markInstalled,
                    onEditVersion: _editVersion,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }
}

class _EnvironmentOverviewCard extends StatelessWidget {
  const _EnvironmentOverviewCard({
    required this.tools,
    required this.checking,
    required this.lastMessage,
    required this.onCheck,
    required this.onResetDefaults,
  });

  final List<DemoEnvironmentTool> tools;
  final bool checking;
  final String lastMessage;
  final VoidCallback onCheck;
  final VoidCallback onResetDefaults;

  @override
  Widget build(BuildContext context) {
    final missing = tools
        .where(
          (tool) =>
              tool.status == DemoEnvironmentToolStatus.missing ||
              tool.status == DemoEnvironmentToolStatus.unknown,
        )
        .length;
    final installing = tools
        .where((tool) => tool.status == DemoEnvironmentToolStatus.installing)
        .length;
    final failed = tools
        .where((tool) => tool.status == DemoEnvironmentToolStatus.installFailed)
        .length;
    final installed = tools
        .where((tool) => tool.status == DemoEnvironmentToolStatus.installed)
        .length;
    final update = tools
        .where(
          (tool) => tool.status == DemoEnvironmentToolStatus.updateAvailable,
        )
        .length;
    return _EnvironmentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _environmentToolListTitle(context),
            style: const TextStyle(
              color: _configTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _environmentToolListDescription(context),
            style: const TextStyle(
              color: _configTextSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _EnvironmentPlainPill(
                label: _toolCountLabel(context, tools.length),
              ),
              _EnvironmentPlainPill(
                label: _installedCountLabel(context, installed),
              ),
              _EnvironmentPlainPill(
                label: _missingCountLabel(context, missing),
              ),
              if (installing > 0)
                _EnvironmentPlainPill(
                  label: _installingCountLabel(context, installing),
                ),
              if (failed > 0)
                _EnvironmentPlainPill(
                  label: _failedCountLabel(context, failed),
                ),
              if (update > 0)
                _EnvironmentPlainPill(
                  label: _updateCountLabel(context, update),
                ),
            ],
          ),
          if (lastMessage.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              lastMessage.trim(),
              style: const TextStyle(
                color: _configTextPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const Key('environment_check_button'),
                  onPressed: checking ? null : onCheck,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF333333),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    checking
                        ? _checkingToolsLabel(context)
                        : _checkToolsLabel(context),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: const Key('environment_reset_defaults_button'),
                  onPressed: onResetDefaults,
                  child: Text(_resetDefaultsLabel(context)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PresetSkillsCard extends StatelessWidget {
  const _PresetSkillsCard({
    required this.skills,
    required this.installedSkillNames,
    required this.loading,
    required this.message,
    required this.onRefresh,
  });

  final List<DemoPresetSkill> skills;
  final Set<String> installedSkillNames;
  final bool loading;
  final String message;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return _EnvironmentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _presetSkillsTitle(context),
                  style: const TextStyle(
                    color: _configTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                key: const Key('preset_skills_refresh_button'),
                onPressed: loading ? null : onRefresh,
                child: Text(_refreshPresetSkillsLabel(context)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _presetSkillsDescription(context),
            style: const TextStyle(
              color: _configTextSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          if (message.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              message.trim(),
              style: const TextStyle(
                color: _configTextPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (loading)
            const LinearProgressIndicator(minHeight: 2)
          else
            for (final skill in skills) ...[
              _PresetSkillTile(
                skill: skill,
                installed: installedSkillNames.contains(
                  skill.name.trim().toLowerCase(),
                ),
              ),
              if (skill != skills.last)
                const Divider(height: 18, color: _configBorderFaint),
            ],
        ],
      ),
    );
  }
}

class _PresetSkillTile extends StatelessWidget {
  const _PresetSkillTile({required this.skill, required this.installed});

  final DemoPresetSkill skill;
  final bool installed;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                skill.title,
                style: const TextStyle(
                  color: _configTextPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                skill.description,
                style: const TextStyle(
                  color: _configTextSecondary,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _PresetSkillStatusPill(
          label: installed
              ? _presetSkillBuiltInLabel(context)
              : _presetSkillMissingLabel(context),
          ready: installed,
        ),
      ],
    );
  }
}

class _PresetSkillStatusPill extends StatelessWidget {
  const _PresetSkillStatusPill({required this.label, required this.ready});

  final String label;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final color = ready ? const Color(0xFF047857) : const Color(0xFFB45309);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _EnvironmentToolGroup extends StatelessWidget {
  const _EnvironmentToolGroup({
    required this.title,
    required this.tools,
    required this.onInstall,
    required this.onMarkInstalled,
    required this.onEditVersion,
  });

  final String title;
  final List<DemoEnvironmentTool> tools;
  final ValueChanged<DemoEnvironmentTool> onInstall;
  final ValueChanged<DemoEnvironmentTool> onMarkInstalled;
  final ValueChanged<DemoEnvironmentTool> onEditVersion;

  @override
  Widget build(BuildContext context) {
    return _EnvironmentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _configTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          for (final tool in tools) ...[
            _EnvironmentToolTile(
              tool: tool,
              onInstall: () => onInstall(tool),
              onMarkInstalled: () => onMarkInstalled(tool),
              onEditVersion: () => onEditVersion(tool),
            ),
            if (tool != tools.last)
              const Divider(height: 18, color: _configBorderFaint),
          ],
        ],
      ),
    );
  }
}

class _EnvironmentToolTile extends StatelessWidget {
  const _EnvironmentToolTile({
    required this.tool,
    required this.onInstall,
    required this.onMarkInstalled,
    required this.onEditVersion,
  });

  final DemoEnvironmentTool tool;
  final VoidCallback onInstall;
  final VoidCallback onMarkInstalled;
  final VoidCallback onEditVersion;

  @override
  Widget build(BuildContext context) {
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
                    tool.name,
                    style: const TextStyle(
                      color: _configTextPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _toolVersionLine(context, tool),
                    style: const TextStyle(
                      color: _configTextSecondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                  if (tool.installCommand.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      tool.installCommand.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _configTextTertiary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _EnvironmentStatusPill(tool.status),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              key: Key('environment_install_${tool.id}'),
              onPressed:
                  tool.status == DemoEnvironmentToolStatus.installing ||
                      tool.installCommand.trim().isEmpty
                  ? null
                  : onInstall,
              child: Text(_installToolLabel(context, tool)),
            ),
            OutlinedButton(
              key: Key('environment_version_${tool.id}'),
              onPressed: onEditVersion,
              child: Text(_changeVersionLabel(context)),
            ),
            TextButton(
              key: Key('environment_mark_installed_${tool.id}'),
              onPressed: onMarkInstalled,
              child: Text(_markInstalledLabel(context)),
            ),
          ],
        ),
      ],
    );
  }
}

class _EnvironmentCard extends StatelessWidget {
  const _EnvironmentCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _configSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _EnvironmentStatusPill extends StatelessWidget {
  const _EnvironmentStatusPill(this.status);

  final DemoEnvironmentToolStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _toolStatusColor(status);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          _toolStatusLabel(context, status),
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _EnvironmentPlainPill extends StatelessWidget {
  const _EnvironmentPlainPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _configSurfaceMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: const TextStyle(
            color: _configTextSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ToolVersionEditResult {
  const _ToolVersionEditResult({
    required this.targetVersion,
    required this.installedVersion,
  });

  final String targetVersion;
  final String installedVersion;
}

class _ToolVersionSheet extends StatefulWidget {
  const _ToolVersionSheet({required this.tool});

  final DemoEnvironmentTool tool;

  @override
  State<_ToolVersionSheet> createState() => _ToolVersionSheetState();
}

class _ToolVersionSheetState extends State<_ToolVersionSheet> {
  late final TextEditingController _targetController;
  late final TextEditingController _installedController;

  @override
  void initState() {
    super.initState();
    _targetController = TextEditingController(text: widget.tool.targetVersion);
    _installedController = TextEditingController(
      text: widget.tool.installedVersion,
    );
  }

  @override
  void dispose() {
    _targetController.dispose();
    _installedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _EnvironmentBottomSheet(
      title: _changeVersionTitle(context, widget.tool),
      children: [
        _EnvironmentSheetTextField(
          controller: _targetController,
          label: _targetVersionLabel(context),
          hint: widget.tool.targetVersion,
        ),
        const SizedBox(height: 12),
        _EnvironmentSheetTextField(
          controller: _installedController,
          label: _installedVersionLabel(context),
          hint: _notInstalledHint(context),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('environment_version_save_button'),
          onPressed: () {
            Navigator.of(context).pop(
              _ToolVersionEditResult(
                targetVersion: _targetController.text.trim(),
                installedVersion: _installedController.text.trim(),
              ),
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF333333),
            foregroundColor: Colors.white,
          ),
          child: Text(_saveLabel(context)),
        ),
      ],
    );
  }
}

class _AddToolSheet extends StatefulWidget {
  const _AddToolSheet();

  @override
  State<_AddToolSheet> createState() => _AddToolSheetState();
}

class _AddToolSheetState extends State<_AddToolSheet> {
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _versionController = TextEditingController();
  final _checkController = TextEditingController();
  final _commandController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _versionController.dispose();
    _checkController.dispose();
    _commandController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      DemoEnvironmentTool(
        id: _toolIdFromName(name),
        name: name,
        category: _categoryController.text.trim().isEmpty
            ? _customToolCategory(context)
            : _categoryController.text.trim(),
        targetVersion: _versionController.text.trim(),
        checkCommand: _checkController.text.trim(),
        installCommand: _commandController.text.trim(),
        custom: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _EnvironmentBottomSheet(
      title: _addToolTitle(context),
      children: [
        _EnvironmentSheetTextField(
          key: const Key('environment_new_tool_name'),
          controller: _nameController,
          label: _toolNameLabel(context),
          hint: 'sdkmanager',
        ),
        const SizedBox(height: 12),
        _EnvironmentSheetTextField(
          controller: _categoryController,
          label: _categoryLabel(context),
          hint: _customToolCategory(context),
        ),
        const SizedBox(height: 12),
        _EnvironmentSheetTextField(
          controller: _versionController,
          label: _targetVersionLabel(context),
          hint: 'latest',
        ),
        const SizedBox(height: 12),
        _EnvironmentSheetTextField(
          controller: _checkController,
          label: _checkCommandLabel(context),
          hint: 'tool --version',
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        _EnvironmentSheetTextField(
          controller: _commandController,
          label: _installCommandLabel(context),
          hint: 'apk add --no-cache ...',
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('environment_add_tool_submit'),
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF333333),
            foregroundColor: Colors.white,
          ),
          child: Text(_addToolLabel(context)),
        ),
      ],
    );
  }
}

class _EnvironmentBottomSheet extends StatelessWidget {
  const _EnvironmentBottomSheet({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: 12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Material(
          color: _configSurface,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _configTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _EnvironmentSheetTextField extends StatelessWidget {
  const _EnvironmentSheetTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: _configSurfaceMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _configBorderFaint),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _configBorderFaint),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _configBorder),
        ),
      ),
    );
  }
}

List<DemoPresetSkill> _defaultPresetSkills() {
  return const [
    DemoPresetSkill(
      name: 'android-project-template',
      title: 'Android Project Template',
      description:
          'Creates a Git-managed Android project instead of HTML when the user asks for an app or APK.',
      skillContent: _androidProjectTemplateSkill,
    ),
    DemoPresetSkill(
      name: 'android-apk-build',
      title: 'Android APK Build',
      description:
          'Builds, signs, verifies, and optionally installs a small Android APK with the lightweight toolchain.',
      skillContent: _androidApkBuildSkill,
    ),
  ];
}

const String _androidProjectTemplateSkill = r'''---
name: android-project-template
description: Create Git-managed Android application projects in the mobile development scenario. Use when the user asks to develop an Android app, APK, tool, demo, or interactive mobile experience and did not explicitly request web, H5, or HTML.
keywords:
  - android
  - apk
  - app
  - project
  - template
  - git
version: 1.0.0
---

# Android Project Template

Use this skill when the user asks to create or develop a mobile app, Android app,
APK, utility, demo, or interactive mobile experience in the mobile development
scenario.

Default behavior:

- Create a real Android project, not an HTML/H5 page, unless the user explicitly
  asks for web output.
- Use `android_create_project` first. Provide a clear `appName`; choose
  `template: "simple"` for ordinary utilities and `template: "canvas"` for
  simple interactive visual apps.
- The created project is a Git repository and should appear in the Projects
  workbench as `git/<project>`.
- After creating the project, edit project files directly when the user asks for
  behavior, UI, package name, version, or text changes.
- Use Git tools for repository work rather than shelling out to discover basic
  Git capability.

When reporting back, mention the project directory, package name, and the next
useful action such as building the APK.
''';

const String _androidApkBuildSkill = r'''---
name: android-apk-build
description: Build and sign a small Android APK in the mobile Linux environment using the lightweight aapt2, javac, d8, zipalign, and apksigner pipeline. Use after an Android project exists.
keywords:
  - android
  - apk
  - build
  - sign
  - install
  - aapt2
  - d8
  - apksigner
version: 1.0.0
---

# Android APK Build

Use this skill when the user asks to build, package, sign, verify, or install an
Android APK for a project created in the mobile development scenario.

Default behavior:

- Prefer `android_build_apk` over ad-hoc shell commands when the project has a
  `.mobile/build-profile.json` file.
- Build from the project shown in the Projects workbench, usually `git/<name>`.
- Reuse `.mobile/debug.keystore` for stable debug signing across builds in this
  workspace.
- Let `android_build_apk` update `versionCode` by default. Pass an explicit
  `versionName` only when the user asks.
- If the user wants to try the result on the phone, call `android_build_apk`
  with `install: true`.
- If the build fails, fix source or environment issues first, then rebuild. Do
  not replace the Android project with an HTML fallback.

The lightweight build pipeline expects OpenJDK 17, bash, zip/unzip, curl,
qemu-x86_64, the Android 33 platform jar, Android build-tools 33.0.2, and the
Ubuntu x86_64 sysroot listed on the Environment page.
''';

Future<List<DemoEnvironmentTool>> _loadDemoEnvironmentTools() async {
  final preferences = await SharedPreferences.getInstance();
  final raw = preferences.getString(_developmentEnvironmentToolsKey);
  if (raw == null || raw.trim().isEmpty) {
    return _defaultEnvironmentTools();
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      final tools = decoded
          .whereType<Map>()
          .map(
            (item) =>
                DemoEnvironmentTool.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((tool) => tool.id.isNotEmpty && tool.name.isNotEmpty)
          .toList(growable: false);
      if (tools.isNotEmpty) {
        return List.unmodifiable(_mergeEnvironmentToolDefaults(tools));
      }
    }
  } catch (_) {
    // Fall back to defaults if user-edited state becomes unreadable.
  }
  return _defaultEnvironmentTools();
}

List<DemoEnvironmentTool> _mergeEnvironmentToolDefaults(
  List<DemoEnvironmentTool> savedTools,
) {
  final savedById = {for (final tool in savedTools) tool.id: tool};
  final defaultIds = _defaultEnvironmentTools().map((tool) => tool.id).toSet();
  const retiredBuiltInIds = {'keytool'};
  final merged = <DemoEnvironmentTool>[
    for (final defaultTool in _defaultEnvironmentTools())
      if (savedById[defaultTool.id] case final saved?)
        saved.copyWith(
          category: saved.category.trim().isEmpty
              ? defaultTool.category
              : saved.category,
          targetVersion: saved.custom
              ? (saved.targetVersion.trim().isEmpty
                    ? defaultTool.targetVersion
                    : saved.targetVersion)
              : defaultTool.targetVersion,
          checkCommand: saved.custom
              ? (saved.checkCommand.trim().isEmpty
                    ? defaultTool.checkCommand
                    : saved.checkCommand)
              : defaultTool.checkCommand,
          installCommand: saved.custom
              ? saved.installCommand
              : defaultTool.installCommand,
          timeoutSeconds:
              saved.timeoutSeconds == 120 && defaultTool.timeoutSeconds > 120
              ? defaultTool.timeoutSeconds
              : saved.timeoutSeconds,
        )
      else
        defaultTool,
  ];
  merged.addAll(
    savedTools.where(
      (tool) =>
          !defaultIds.contains(tool.id) && !retiredBuiltInIds.contains(tool.id),
    ),
  );
  return merged;
}

Future<void> _saveDemoEnvironmentTools(List<DemoEnvironmentTool> tools) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(
    _developmentEnvironmentToolsKey,
    jsonEncode(tools.map((tool) => tool.toJson()).toList(growable: false)),
  );
}

const String _installAndroidBuildToolsCommand = '''
set -e
mkdir -p /opt/android
cd /opt/android
if [ ! -d /opt/android/sdk/build-tools/33.0.2 ]; then
  curl -sSL -o bt.zip "https://dl.google.com/android/repository/build-tools_r33.0.2-linux.zip"
  unzip -q bt.zip -d bt_dir
  mkdir -p sdk/build-tools
  rm -rf sdk/build-tools/33.0.2
  mv bt_dir/android-13 sdk/build-tools/33.0.2
  rm -rf bt_dir bt.zip
fi
/opt/android/sdk/build-tools/33.0.2/d8 --version
''';

const String _installAndroidPlatformCommand = '''
set -e
mkdir -p /opt/android
cd /opt/android
if [ ! -f /opt/android/sdk/platforms/android-33/android.jar ]; then
  curl -sSL -o plat.zip "https://dl.google.com/android/repository/platform-33_r02.zip"
  unzip -q plat.zip -d plat_dir
  mkdir -p sdk/platforms
  rm -rf sdk/platforms/android-33
  mv plat_dir/android-13 sdk/platforms/android-33
  rm -rf plat_dir plat.zip
fi
test -f /opt/android/sdk/platforms/android-33/android.jar
echo android-33
''';

const String _installUbuntuSysrootCommand = '''
set -e
mkdir -p /opt/x86root
cd /opt/x86root
if [ ! -f /opt/x86root/sysroot/lib64/ld-linux-x86-64.so.2 ]; then
  curl -sSL -o ubuntu.tar.gz "https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04-base-amd64.tar.gz"
  rm -rf sysroot
  mkdir -p sysroot
  tar -xzf ubuntu.tar.gz -C sysroot 2>/dev/null || true
  rm ubuntu.tar.gz
  mkdir -p sysroot/lib64
  cp sysroot/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 sysroot/lib64/
fi
test -f /opt/x86root/sysroot/lib64/ld-linux-x86-64.so.2
echo 22.04
''';

// Installs Node.js + npm via apk, then installs the Codex CLI globally through
// npm. Both steps run under `set -e`, so a failure in either aborts the run.
const String _installCodexCliCommand = '''
set -e
apk add --no-cache nodejs npm
npm install -g @openai/codex
''';

// Installs Node.js + npm via apk, then installs the Claude Agent SDK globally
// through npm. The SDK package was split out of @anthropic-ai/claude-code.
const String _installClaudeAgentSdkCommand = '''
set -e
apk add --no-cache nodejs npm
npm install -g @anthropic-ai/claude-agent-sdk
''';

/// Check commands MUST exit non-zero when the tool is missing, so the panel can
/// detect absence from the real proot exit code. Never pipe them through
/// `head`/`cat` — that masks the tool's exit code (the pipe returns the last
/// command's status) and a missing tool would look installed. [_firstOutputLine]
/// already trims the captured output to the version line. Keep `2>&1` when a
/// tool prints its version to stderr (e.g. `java -version`).
List<DemoEnvironmentTool> _defaultEnvironmentTools() {
  return const [
    DemoEnvironmentTool(
      id: 'codex',
      name: 'Codex',
      category: 'Coding agents',
      targetVersion: 'latest',
      checkCommand: 'codex --version 2>&1',
      installCommand: _installCodexCliCommand,
      timeoutSeconds: 600,
    ),
    DemoEnvironmentTool(
      id: 'claude-agent-sdk',
      name: 'Claude Agent SDK',
      category: 'Coding agents',
      targetVersion: 'latest',
      checkCommand:
          r'''node -e "console.log(require('$(npm root -g)/@anthropic-ai/claude-agent-sdk/package.json').version)" 2>/dev/null''',
      installCommand: _installClaudeAgentSdkCommand,
      timeoutSeconds: 600,
    ),
    DemoEnvironmentTool(
      id: 'openjdk',
      name: 'OpenJDK',
      category: 'System packages',
      targetVersion: '17',
      checkCommand: 'java -version 2>&1 && keytool -help >/dev/null 2>&1',
      installCommand: 'apk add --no-cache openjdk17',
    ),
    DemoEnvironmentTool(
      id: 'bash',
      name: 'bash',
      category: 'System packages',
      targetVersion: 'repo',
      checkCommand: 'bash --version 2>&1',
      installCommand: 'apk add --no-cache bash',
    ),
    DemoEnvironmentTool(
      id: 'zip',
      name: 'zip / unzip',
      category: 'System packages',
      targetVersion: 'repo',
      checkCommand: 'zip -v 2>&1 && unzip -v 2>&1',
      installCommand: 'apk add --no-cache zip unzip',
    ),
    DemoEnvironmentTool(
      id: 'curl',
      name: 'curl',
      category: 'System packages',
      targetVersion: 'repo',
      checkCommand: 'curl --version 2>&1',
      installCommand: 'apk add --no-cache curl',
    ),
    DemoEnvironmentTool(
      id: 'git',
      name: 'git',
      category: 'System packages',
      targetVersion: 'repo',
      checkCommand: 'git --version 2>&1',
      installCommand: 'apk add --no-cache git',
    ),
    DemoEnvironmentTool(
      id: 'qemu',
      name: 'qemu-x86_64',
      category: 'System packages',
      targetVersion: 'repo',
      checkCommand: 'qemu-x86_64 --version 2>&1',
      installCommand: 'apk add --no-cache qemu-x86_64',
    ),
    DemoEnvironmentTool(
      id: 'npm',
      name: 'npm',
      category: 'System packages',
      targetVersion: 'repo',
      checkCommand: 'npm --version 2>&1',
      installCommand: 'apk add --no-cache nodejs npm',
    ),
    DemoEnvironmentTool(
      id: 'alpine-libs',
      name: 'gcompat / libstdc++ / libgcc / zlib / zopfli',
      category: 'System packages',
      targetVersion: 'repo',
      checkCommand:
          '/sbin/apk info -e gcompat libstdc++ libgcc zlib zopfli >/dev/null && echo repo',
      installCommand: 'apk add --no-cache gcompat libstdc++ libgcc zlib zopfli',
    ),
    DemoEnvironmentTool(
      id: 'android-build-tools',
      name: 'Android build-tools',
      category: 'Android SDK',
      targetVersion: '33.0.2',
      checkCommand:
          'test -d /opt/android/sdk/build-tools/33.0.2 && echo 33.0.2',
      installCommand: _installAndroidBuildToolsCommand,
      timeoutSeconds: 600,
    ),
    DemoEnvironmentTool(
      id: 'android-platform',
      name: 'Android platform jar',
      category: 'Android SDK',
      targetVersion: 'android-33',
      checkCommand:
          'test -f /opt/android/sdk/platforms/android-33/android.jar && echo android-33',
      installCommand: _installAndroidPlatformCommand,
      timeoutSeconds: 600,
    ),
    DemoEnvironmentTool(
      id: 'aapt2',
      name: 'aapt2',
      category: 'Build tools',
      targetVersion: '33.0.2',
      checkCommand:
          'qemu-x86_64 -L /opt/x86root/sysroot /opt/android/sdk/build-tools/33.0.2/aapt2 version >/dev/null && echo 33.0.2',
      installCommand: _installAndroidBuildToolsCommand,
      timeoutSeconds: 600,
    ),
    DemoEnvironmentTool(
      id: 'd8',
      name: 'd8',
      category: 'Build tools',
      targetVersion: '33.0.2',
      checkCommand:
          '/opt/android/sdk/build-tools/33.0.2/d8 --version >/dev/null 2>&1 && echo 33.0.2',
      installCommand: _installAndroidBuildToolsCommand,
      timeoutSeconds: 600,
    ),
    DemoEnvironmentTool(
      id: 'apksigner',
      name: 'apksigner',
      category: 'Build tools',
      targetVersion: '33.0.2',
      checkCommand:
          '/opt/android/sdk/build-tools/33.0.2/apksigner --version >/dev/null 2>&1 && echo 33.0.2',
      installCommand: _installAndroidBuildToolsCommand,
      timeoutSeconds: 600,
    ),
    DemoEnvironmentTool(
      id: 'zipalign',
      name: 'zipalign',
      category: 'Build tools',
      targetVersion: '33.0.2',
      checkCommand:
          'test -x /opt/android/sdk/build-tools/33.0.2/zipalign && echo 33.0.2',
      installCommand: _installAndroidBuildToolsCommand,
      timeoutSeconds: 600,
    ),
    DemoEnvironmentTool(
      id: 'ubuntu-x86-root',
      name: 'Ubuntu x86_64 sysroot',
      category: 'Runtime',
      targetVersion: '22.04',
      checkCommand:
          'test -f /opt/x86root/sysroot/lib64/ld-linux-x86-64.so.2 && echo 22.04',
      installCommand: _installUbuntuSysrootCommand,
      timeoutSeconds: 600,
    ),
  ];
}

Map<String, List<DemoEnvironmentTool>> _groupTools(
  List<DemoEnvironmentTool> tools,
) {
  final grouped = <String, List<DemoEnvironmentTool>>{};
  for (final tool in tools) {
    grouped.putIfAbsent(tool.category, () => []).add(tool);
  }
  return grouped;
}

DemoEnvironmentToolStatus _statusForVersions({
  required String targetVersion,
  required String installedVersion,
}) {
  if (installedVersion.trim().isEmpty) return DemoEnvironmentToolStatus.missing;
  if (_environmentVersionMatches(
    targetVersion: targetVersion,
    installedVersion: installedVersion,
  )) {
    return DemoEnvironmentToolStatus.installed;
  }
  return DemoEnvironmentToolStatus.updateAvailable;
}

bool _environmentVersionMatches({
  required String targetVersion,
  required String installedVersion,
}) {
  final target = targetVersion.trim().toLowerCase();
  final installed = installedVersion.trim().toLowerCase();
  if (installed.isEmpty) return false;
  if (target.isEmpty ||
      target == 'repo' ||
      target == 'latest' ||
      target == 'from jdk') {
    return true;
  }
  return installed == target || installed.contains(target);
}

String _firstOutputLine(String output) {
  return output
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
}

String _shortEnvironmentMessage(String message) {
  final line = _firstOutputLine(message);
  if (line.length <= 120) return line;
  return '${line.substring(0, 120)}...';
}

String _toolIdFromName(String name) {
  final normalized = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (normalized.isNotEmpty) return 'custom-$normalized';
  return 'custom-${DateTime.now().millisecondsSinceEpoch}';
}

String _environmentContributionTitle(
  BuildContext context,
  sdk.NapaxiScenarioUiContribution contribution,
) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '环境'
      : contribution.title.trim().isEmpty
      ? 'Environment'
      : contribution.title.trim();
}

String _environmentMenuTitle(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '环境'
      : 'Environment';
}

String _environmentToolListTitle(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '工具清单'
      : 'Tools';
}

String _environmentToolListDescription(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '这里列出当前 Android APK 构建技能需要的工具。你可以安装缺失工具、更换目标版本，或者新增自己项目需要的工具。'
      : 'Tools required by the current Android APK build skill. Install missing tools, change target versions, or add project-specific tools.';
}

String _presetSkillsTitle(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '预设技能'
      : 'Preset skills';
}

String _presetSkillsDescription(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '移动开发场景默认推荐的技能。安装后会进入当前开发引擎的技能列表，并参与后续对话。'
      : 'Recommended skills for the mobile development scenario. Installed skills are scoped to the current developer engine and participate in later turns.';
}

String _refreshPresetSkillsLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '刷新'
      : 'Refresh';
}

String _presetSkillBuiltInLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '已内置'
      : 'Built in';
}

String _presetSkillMissingLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '待同步'
      : 'Syncing';
}

String _presetSkillLoadFailed(BuildContext context, Object error) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '读取预设技能状态失败：$error'
      : 'Failed to read preset skill status: $error';
}

String _toolCountLabel(BuildContext context, int count) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '$count 个工具'
      : '$count tools';
}

String _installedCountLabel(BuildContext context, int count) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '$count 已安装'
      : '$count installed';
}

String _missingCountLabel(BuildContext context, int count) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '$count 缺失/未检测'
      : '$count missing/unknown';
}

String _installingCountLabel(BuildContext context, int count) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '$count 安装中'
      : '$count installing';
}

String _failedCountLabel(BuildContext context, int count) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '$count 安装失败'
      : '$count failed';
}

String _updateCountLabel(BuildContext context, int count) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '$count 需换版本'
      : '$count version mismatch';
}

String _checkToolsLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '自检'
      : 'Check';
}

String _checkingToolsLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '自检中'
      : 'Checking';
}

String _resetDefaultsLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '恢复默认'
      : 'Defaults';
}

String _addToolLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '新增工具'
      : 'Add tool';
}

String _installToolLabel(BuildContext context, DemoEnvironmentTool tool) {
  if (tool.installCommand.trim().isEmpty) {
    return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
        ? '未配置安装'
        : 'No install';
  }
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '安装'
      : 'Install';
}

String _changeVersionLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '版本'
      : 'Version';
}

String _markInstalledLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '标记已安装'
      : 'Mark installed';
}

String _toolVersionLine(BuildContext context, DemoEnvironmentTool tool) {
  final zh = _AppLanguageScope.languageOf(context) == AppLanguage.chinese;
  final installed = tool.installedVersion.trim().isEmpty
      ? (zh ? '未记录' : 'not recorded')
      : tool.installedVersion.trim();
  final target = tool.targetVersion.trim().isEmpty
      ? (zh ? '未指定' : 'unspecified')
      : tool.targetVersion.trim();
  return zh
      ? '目标 $target · 已安装 $installed'
      : 'Target $target · Installed $installed';
}

String _toolStatusLabel(
  BuildContext context,
  DemoEnvironmentToolStatus status,
) {
  final zh = _AppLanguageScope.languageOf(context) == AppLanguage.chinese;
  return switch (status) {
    DemoEnvironmentToolStatus.unknown => zh ? '未检测' : 'Unknown',
    DemoEnvironmentToolStatus.missing => zh ? '缺失' : 'Missing',
    DemoEnvironmentToolStatus.installing => zh ? '安装中' : 'Installing',
    DemoEnvironmentToolStatus.installed => zh ? '已安装' : 'Installed',
    DemoEnvironmentToolStatus.updateAvailable => zh ? '需换版本' : 'Version',
    DemoEnvironmentToolStatus.installFailed => zh ? '安装失败' : 'Failed',
  };
}

Color _toolStatusColor(DemoEnvironmentToolStatus status) {
  return switch (status) {
    DemoEnvironmentToolStatus.unknown => const Color(0xFF737373),
    DemoEnvironmentToolStatus.missing => const Color(0xFFB45309),
    DemoEnvironmentToolStatus.installing => const Color(0xFF2563EB),
    DemoEnvironmentToolStatus.installed => const Color(0xFF047857),
    DemoEnvironmentToolStatus.updateAvailable => const Color(0xFF7C3AED),
    DemoEnvironmentToolStatus.installFailed => const Color(0xFFB91C1C),
  };
}

String _toolInstallUnavailable(BuildContext context, DemoEnvironmentTool tool) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '${tool.name} 没有配置安装命令'
      : '${tool.name} has no install command';
}

String _toolInstallStarted(BuildContext context, DemoEnvironmentTool tool) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '正在安装 ${tool.name}'
      : 'Installing ${tool.name}';
}

String _toolInstallSucceeded(BuildContext context, DemoEnvironmentTool tool) {
  final version = tool.installedVersion.trim();
  final suffix = version.isEmpty ? '' : '：$version';
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '${tool.name} 安装完成$suffix'
      : '${tool.name} installed${version.isEmpty ? '' : ': $version'}';
}

String _toolInstallFailed(
  BuildContext context,
  DemoEnvironmentTool tool,
  _EnvironmentCommandResult result,
) {
  final reason = _shortEnvironmentMessage(result.error);
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '${tool.name} 安装失败${reason.isEmpty ? '' : '：$reason'}'
      : '${tool.name} install failed${reason.isEmpty ? '' : ': $reason'}';
}

String _toolMarkedInstalled(BuildContext context, DemoEnvironmentTool tool) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '${tool.name} 已标记为已安装'
      : '${tool.name} marked installed';
}

String _toolCheckFinished(
  BuildContext context,
  List<DemoEnvironmentTool> tools,
) {
  final missing = tools
      .where((tool) => tool.status == DemoEnvironmentToolStatus.missing)
      .length;
  final failed = tools
      .where((tool) => tool.status == DemoEnvironmentToolStatus.installFailed)
      .length;
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '自检完成，$missing 个工具缺失，$failed 个安装失败'
      : 'Check finished, $missing missing, $failed failed';
}

String _toolCheckStarted(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '正在检测工具状态'
      : 'Checking tool status';
}

String _toolVersionSaved(BuildContext context, DemoEnvironmentTool tool) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '${tool.name} 版本已更新'
      : '${tool.name} version saved';
}

String _toolAdded(BuildContext context, DemoEnvironmentTool tool) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '已新增 ${tool.name}'
      : '${tool.name} added';
}

String _toolAlreadyExists(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '这个工具已经存在'
      : 'This tool already exists';
}

String _environmentDefaultsRestored(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '已恢复默认工具清单'
      : 'Default tools restored';
}

String _changeVersionTitle(BuildContext context, DemoEnvironmentTool tool) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '调整 ${tool.name} 版本'
      : 'Change ${tool.name} version';
}

String _targetVersionLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '目标版本'
      : 'Target version';
}

String _installedVersionLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '已安装版本'
      : 'Installed version';
}

String _notInstalledHint(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '未安装可留空'
      : 'Leave blank if missing';
}

String _saveLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '保存'
      : 'Save';
}

String _addToolTitle(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '新增工具'
      : 'Add tool';
}

String _toolNameLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '工具名'
      : 'Tool name';
}

String _categoryLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '分组'
      : 'Category';
}

String _installCommandLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '安装命令'
      : 'Install command';
}

String _checkCommandLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '检测命令'
      : 'Check command';
}

String _customToolCategory(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '自定义'
      : 'Custom';
}

IconData _environmentContributionIcon(
  sdk.NapaxiScenarioUiContribution contribution,
) {
  return switch (contribution.icon.trim().toLowerCase()) {
    'terminal' => Icons.terminal_rounded,
    'build' => Icons.handyman_outlined,
    'android' => Icons.android_rounded,
    _ => Icons.tune_rounded,
  };
}
