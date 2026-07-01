part of '../main.dart';

enum _FileSource { memory, workspace, journal, repository }

enum _SkillsInitialTab { installed, store, organize }

class _FileBrowserItem {
  const _FileBrowserItem({
    required this.source,
    required this.path,
    required this.name,
    required this.isDirectory,
    this.browsePath,
    this.deletePath,
    this.realPath,
    this.mimeType,
    this.sizeBytes,
    this.modified,
  });

  final _FileSource source;
  final String path;
  final String name;
  final bool isDirectory;
  final String? browsePath;
  final String? deletePath;
  final String? realPath;
  final String? mimeType;
  final int? sizeBytes;
  final DateTime? modified;

  bool get isImage => (mimeType ?? '').startsWith('image/');
  String get extension {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == name.length - 1) return '';
    return name.substring(dotIndex + 1).toLowerCase();
  }

  bool get isHtml =>
      (mimeType ?? '').toLowerCase() == 'text/html' ||
      const {'html', 'htm'}.contains(extension);
  bool get isTextPreviewable {
    if (source == _FileSource.memory || source == _FileSource.journal) {
      return true;
    }
    final type = (mimeType ?? '').toLowerCase();
    if (type.startsWith('text/')) return true;
    if (const {
      'application/json',
      'application/javascript',
      'application/x-javascript',
      'application/xml',
      'application/x-yaml',
      'application/toml',
    }.contains(type)) {
      return true;
    }
    return const {
      'cfg',
      'conf',
      'css',
      'csv',
      'dart',
      'html',
      'htm',
      'js',
      'json',
      'kt',
      'log',
      'md',
      'rs',
      'sh',
      'swift',
      'toml',
      'txt',
      'xml',
      'yaml',
      'yml',
    }.contains(extension);
  }

  bool get canPreview =>
      isHtml || isTextPreviewable || (isImage && realPath != null);

  bool get isProtectedMemoryFile =>
      source == _FileSource.memory && _isProtectedMemoryPath(path);
  bool get canDelete =>
      source != _FileSource.journal &&
      source != _FileSource.repository &&
      !isProtectedMemoryFile;
  bool get canSelect => canDelete;
}

const Set<String> _protectedMemoryFilePaths = {
  sdk.WorkspacePaths.soul,
  sdk.WorkspacePaths.identity,
  sdk.WorkspacePaths.agents,
  sdk.WorkspacePaths.user,
  sdk.WorkspacePaths.memory,
  sdk.WorkspacePaths.project,
  sdk.WorkspacePaths.heartbeat,
  sdk.WorkspacePaths.tools,
  sdk.WorkspacePaths.bootstrap,
  sdk.WorkspacePaths.profile,
};

bool _isProtectedMemoryPath(String path) {
  return _protectedMemoryFilePaths.contains(_normalizeFilePath(path));
}

class _SkillsPage extends StatelessWidget {
  const _SkillsPage({
    required this.clientFuture,
    required this.agentId,
    this.initialTab = _SkillsInitialTab.installed,
    this.onPendingEvolutionChanged,
    this.onBack,
  });

  final Future<NapaxiChatClient> clientFuture;
  final String agentId;
  final _SkillsInitialTab initialTab;
  final Future<void> Function()? onPendingEvolutionChanged;
  final Future<bool> Function()? onBack;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Scaffold(
      backgroundColor: _configPageBackground,
      appBar: AppBar(
        title: Text(strings.skillsTitle),
        backgroundColor: _configPageBackground,
        foregroundColor: _configTextPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(
          onPressed: () async {
            final handled = await onBack?.call();
            if (handled != false && context.mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: FutureBuilder<NapaxiChatClient>(
        future: clientFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: _SkillLoadingIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return _FilesMessage(
              icon: Icons.extension_off_rounded,
              title: strings.skillSearchFailed(
                _friendlyDisplayError(snapshot.error),
              ),
              description: null,
            );
          }
          return _SkillsBrowser(
            client: snapshot.data!,
            agentId: agentId,
            initialTab: initialTab,
            onPendingEvolutionChanged: onPendingEvolutionChanged,
          );
        },
      ),
    );
  }
}

class _SkillsBrowser extends StatefulWidget {
  const _SkillsBrowser({
    required this.client,
    required this.agentId,
    required this.initialTab,
    this.onPendingEvolutionChanged,
  });

  final NapaxiChatClient client;
  final String agentId;
  final _SkillsInitialTab initialTab;
  final Future<void> Function()? onPendingEvolutionChanged;

  @override
  State<_SkillsBrowser> createState() => _SkillsBrowserState();
}

class _SkillsBrowserState extends State<_SkillsBrowser> {
  static const _slugMapPrefsKey = 'skill_slug_to_name';

  late Future<List<sdk.SkillInfo>> _installedFuture;
  late Future<sdk.SkillStatusReport> _statusFuture;
  late Future<_SkillGovernanceSnapshot> _organizeFuture;
  List<sdk.SkillInfo> _installedSkills = const [];
  // Maps catalog slug (lowercased) → manifest name (lowercased) recorded at
  // install time, persisted to SharedPreferences so the store tab can
  // reliably detect already-installed skills across sessions even when the
  // manifest name differs from the catalog slug.
  Map<String, String> _slugToInstalledName = {};

  @override
  void initState() {
    super.initState();
    _loadSlugMap();
    _installedFuture = _loadInstalledSkills();
    _statusFuture = _loadSkillStatus();
    _organizeFuture = _loadOrganizeSnapshot();
  }

  Future<void> _loadSlugMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_slugMapPrefsKey);
    if (raw == null || raw.isEmpty) return;
    final map = <String, String>{};
    for (final entry in raw) {
      final sep = entry.indexOf('=');
      if (sep > 0) map[entry.substring(0, sep)] = entry.substring(sep + 1);
    }
    if (mounted) setState(() => _slugToInstalledName = map);
  }

  Future<void> _persistSlugMap() async {
    final prefs = await SharedPreferences.getInstance();
    final entries =
        _slugToInstalledName.entries.map((e) => '${e.key}=${e.value}').toList();
    await prefs.setStringList(_slugMapPrefsKey, entries);
  }

  Future<List<sdk.SkillInfo>> _loadInstalledSkills() async {
    final skills = [...await widget.client.listSkills(agentId: widget.agentId)];
    skills.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _installedSkills = List.unmodifiable(skills);
    // Rebuild so the Store tab's `installedNames` (read synchronously from
    // `_installedSkills` in build) reflects the freshly loaded set; without
    // this the initial load leaves it empty and catalog tiles show Install
    // instead of Update for already-installed skills.
    if (mounted) setState(() {});
    return _installedSkills;
  }

  Future<sdk.SkillStatusReport> _loadSkillStatus() {
    return widget.client.listSkillStatus(agentId: widget.agentId);
  }

  Future<_SkillGovernanceSnapshot> _loadOrganizeSnapshot() {
    return _SkillGovernanceSnapshot.load(widget.client, widget.agentId);
  }

  Future<void> _refreshInstalledSkills() async {
    final future = _loadInstalledSkills();
    final statusFuture = _loadSkillStatus();
    final organizeFuture = _loadOrganizeSnapshot();
    setState(() {
      _installedFuture = future;
      _statusFuture = statusFuture;
      _organizeFuture = organizeFuture;
    });
    await future;
    await statusFuture;
    await organizeFuture;
    if (mounted) setState(() {});
  }

  Future<void> _reloadInstalledSkills() async {
    await widget.client.reloadSkills(agentId: widget.agentId);
    await _refreshInstalledSkills();
  }

  Future<void> _removeSkill(sdk.SkillInfo skill) async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.removeSkillConfirmationTitle),
        content: Text(strings.removeSkillConfirmationMessage(skill.name)),
        actions: [
          TextButton(
            style: _skillTextButtonStyle(),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          OutlinedButton(
            style: _skillOutlinedButtonStyle(),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.removeSkill),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final removed = await widget.client.removeSkill(
        skill.name,
        agentId: widget.agentId,
      );
      if (!removed) throw StateError('Skill was not removed');
      // Remove any slug mapping that pointed to this skill's manifest name.
      final nameLower = skill.name.toLowerCase();
      _slugToInstalledName.removeWhere((_, value) => value == nameLower);
      unawaited(_persistSlugMap());
      await _refreshInstalledSkills();
      if (mounted) {
        _showSkillSnackBar(context, strings.skillRemoved(skill.name));
      }
    } catch (error) {
      if (!mounted) return;
      _showSkillSnackBar(
        context,
        strings.skillActionFailed(_friendlyDisplayError(error)),
      );
    }
  }

  // Single source of truth for "is this catalog skill already installed".
  // Combines the live installed-skills list with the persisted slug→name map
  // so the Store tab's Update affordance and the install snackbar agree.
  Set<String> _installedSkillKeys() {
    return <String>{..._slugToInstalledName.keys}..remove('');
  }

  bool _isCatalogSkillInstalled(sdk.CatalogSkillInfo skill) {
    final keys = _installedSkillKeys();
    return keys.contains(skill.slug.toLowerCase());
  }

  Future<void> _installSkill(sdk.CatalogSkillInfo skill) async {
    final strings = AppStrings.of(context);
    final target = (skill.slug.trim().isNotEmpty ? skill.slug : skill.name)
        .trim();
    if (target.isEmpty) return;

    final wasInstalled = _isCatalogSkillInstalled(skill);
    try {
      final result = await widget.client.installFromCatalog(
        target,
        agentId: widget.agentId,
      );
      if (!result.success) {
        throw StateError(result.error ?? 'Skill install failed');
      }
      // Record the slug → manifest name mapping so the store tab can match.
      final installedName = result.name?.toLowerCase().trim() ?? '';
      if (installedName.isNotEmpty) {
        _slugToInstalledName[skill.slug.toLowerCase()] = installedName;
        unawaited(_persistSlugMap());
      }
      await _refreshInstalledSkills();
      if (!mounted) return;
      _showSkillSnackBar(
        context,
        wasInstalled
            ? strings.skillUpdated(result.name ?? skill.name)
            : strings.skillInstalled(result.name ?? skill.name),
      );
    } catch (error) {
      if (!mounted) return;
      _showSkillSnackBar(
        context,
        strings.skillActionFailed(_friendlyDisplayError(error)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final installedNames = _installedSkillKeys();
    final initialIndex = switch (widget.initialTab) {
      _SkillsInitialTab.installed => 0,
      _SkillsInitialTab.store => 1,
      _SkillsInitialTab.organize => 2,
    };

    return DefaultTabController(
      length: 3,
      initialIndex: initialIndex,
      child: Column(
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              color: _configPageBackground,
              border: Border(bottom: BorderSide(color: _configBorderFaint)),
            ),
            child: TabBar(
              indicatorColor: _configTextPrimary,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: _configTextPrimary,
              unselectedLabelColor: _configTextSecondary,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              tabs: [
                Tab(text: strings.installedSkillsTitle),
                Tab(text: strings.skillStoreTitle),
                FutureBuilder<_SkillGovernanceSnapshot>(
                  future: _organizeFuture,
                  builder: (context, snapshot) {
                    final labels = _SkillGovernanceLabels.of(context);
                    final pendingCount = snapshot.data?.pending.length ?? 0;
                    return Tab(
                      text: pendingCount > 0
                          ? labels.tabTitleWithCount(pendingCount)
                          : labels.tabTitle,
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _InstalledSkillsView(
                  client: widget.client,
                  agentId: widget.agentId,
                  skillsFuture: _installedFuture,
                  statusFuture: _statusFuture,
                  onRefresh: _reloadInstalledSkills,
                  onRemove: _removeSkill,
                ),
                _SkillStoreView(
                  client: widget.client,
                  installedNames: installedNames,
                  onInstall: _installSkill,
                ),
                _SkillGovernanceView(
                  client: widget.client,
                  agentId: widget.agentId,
                  snapshotFuture: _organizeFuture,
                  onSkillsChanged: _refreshInstalledSkills,
                  onSnapshotChanged: (future) {
                    setState(() {
                      _organizeFuture = future;
                    });
                  },
                  onPendingEvolutionChanged: widget.onPendingEvolutionChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkillGovernanceLabels {
  const _SkillGovernanceLabels({
    required this.tabTitle,
    required this.tabTitleWithCount,
    required this.title,
    required this.subtitle,
    required this.pendingSummaryTitle,
    required this.pendingSummaryDescription,
    required this.unusedSummaryTitle,
    required this.unusedSummaryDescription,
    required this.emptySummaryTitle,
    required this.emptySummaryDescription,
    required this.pending,
    required this.pendingDescription,
    required this.stale,
    required this.staleDescription,
    required this.archived,
    required this.archivedDescription,
    required this.noPending,
    required this.noStale,
    required this.noArchived,
    required this.organizeUnused,
    required this.organizeUnusedPreviewTitle,
    required this.organizeUnusedPreviewEmpty,
    required this.organizeUnusedPreviewConfirm,
    required this.apply,
    required this.reject,
    required this.viewDetails,
    required this.detailsTitle,
    required this.keep,
    required this.archive,
    required this.restore,
    required this.pin,
    required this.unpin,
    required this.unusedActions,
    required this.unusedApplied,
    required this.partiallyApplied,
    required this.actionFailed,
    required this.absorbedInto,
    required this.actionCount,
    required this.lastActivityNever,
  });

  final String tabTitle;
  final String Function(int count) tabTitleWithCount;
  final String title;
  final String subtitle;
  final String Function(int count) pendingSummaryTitle;
  final String pendingSummaryDescription;
  final String unusedSummaryTitle;
  final String unusedSummaryDescription;
  final String emptySummaryTitle;
  final String emptySummaryDescription;
  final String pending;
  final String pendingDescription;
  final String stale;
  final String staleDescription;
  final String archived;
  final String archivedDescription;
  final String noPending;
  final String noStale;
  final String noArchived;
  final String organizeUnused;
  final String organizeUnusedPreviewTitle;
  final String organizeUnusedPreviewEmpty;
  final String organizeUnusedPreviewConfirm;
  final String apply;
  final String reject;
  final String viewDetails;
  final String detailsTitle;
  final String keep;
  final String archive;
  final String restore;
  final String pin;
  final String unpin;
  final String Function(int count) unusedActions;
  final String Function(int stale, int archived) unusedApplied;
  final String partiallyApplied;
  final String Function(String message) actionFailed;
  final String Function(String skillName) absorbedInto;
  final String Function(int count) actionCount;
  final String lastActivityNever;

  static _SkillGovernanceLabels of(BuildContext context) {
    final isChinese =
        _AppLanguageScope.languageOf(context) == AppLanguage.chinese;
    if (isChinese) {
      return _SkillGovernanceLabels(
        tabTitle: '整理',
        tabTitleWithCount: (count) => '整理 $count',
        title: '技能整理',
        subtitle: '处理聊天生成的技能建议，也可以收起长期未用的技能。',
        pendingSummaryTitle: (count) => '有 $count 个技能建议待确认',
        pendingSummaryDescription: '聊天过程中生成的技能变更，需要确认后才会生效。',
        unusedSummaryTitle: '可以整理长期未用技能',
        unusedSummaryDescription: '这些技能最近没有被调用，可以先收起，之后还能恢复。',
        emptySummaryTitle: '暂无需要处理的技能',
        emptySummaryDescription: '有新的技能建议或长期未用技能时，会显示在这里。',
        pending: '待确认建议',
        pendingDescription: '确认后才会修改技能；不确定时可以先忽略。',
        stale: '长期未用',
        staleDescription: '这些技能最近没有被调用，可以收起或继续保留。',
        archived: '已收起',
        archivedDescription: '收起的技能不会优先出现在可用列表里，需要时可以恢复。',
        noPending: '暂无待确认建议。',
        noStale: '暂无长期未用技能。',
        noArchived: '暂无已收起技能。',
        organizeUnused: '整理未用技能',
        organizeUnusedPreviewTitle: '整理未用技能',
        organizeUnusedPreviewEmpty: '没有需要收起的长期未用技能。',
        organizeUnusedPreviewConfirm: '确认整理',
        apply: '确认应用',
        reject: '忽略',
        viewDetails: '查看详情',
        detailsTitle: '建议详情',
        keep: '保留',
        archive: '收起',
        restore: '恢复',
        pin: '固定',
        unpin: '取消固定',
        unusedActions: (count) => '将整理 $count 个技能',
        unusedApplied: (stale, archived) =>
            '整理完成：$stale 个标记为长期未用，$archived 个已收起',
        partiallyApplied: '已应用已完成的变更，少量后续动作未完成。',
        actionFailed: (message) => '技能整理失败：$message',
        absorbedInto: (skillName) => '已并入 $skillName',
        actionCount: (count) => '$count 个动作',
        lastActivityNever: '暂无使用记录',
      );
    }
    return _SkillGovernanceLabels(
      tabTitle: 'Organize',
      tabTitleWithCount: (count) => 'Organize $count',
      title: 'Organize skills',
      subtitle:
          'Review skill suggestions from chats and tuck away unused skills.',
      pendingSummaryTitle: (count) =>
          '$count skill suggestion${count == 1 ? '' : 's'} pending',
      pendingSummaryDescription:
          'Skill changes from chats only take effect after you confirm them.',
      unusedSummaryTitle: 'Unused skills can be organized',
      unusedSummaryDescription:
          'These skills have not been called recently. You can tuck them away and restore them later.',
      emptySummaryTitle: 'No skill tasks right now',
      emptySummaryDescription:
          'New skill suggestions and unused skills will appear here.',
      pending: 'Suggestions',
      pendingDescription:
          'Confirm to change skills, or ignore suggestions you do not want.',
      stale: 'Unused',
      staleDescription:
          'These skills have not been called recently. Keep or tuck them away.',
      archived: 'Tucked away',
      archivedDescription:
          'Tucked away skills stay recoverable when you need them again.',
      noPending: 'No pending suggestions.',
      noStale: 'No unused skills.',
      noArchived: 'No tucked away skills.',
      organizeUnused: 'Organize unused',
      organizeUnusedPreviewTitle: 'Organize unused skills',
      organizeUnusedPreviewEmpty: 'No unused skills need to be tucked away.',
      organizeUnusedPreviewConfirm: 'Organize',
      apply: 'Confirm',
      reject: 'Ignore',
      viewDetails: 'Details',
      detailsTitle: 'Suggestion details',
      keep: 'Keep',
      archive: 'Tuck away',
      restore: 'Restore',
      pin: 'Pin',
      unpin: 'Unpin',
      unusedActions: (count) =>
          '$count skill${count == 1 ? '' : 's'} will be organized',
      unusedApplied: (stale, archived) =>
          'Organized: $stale marked unused, $archived tucked away',
      partiallyApplied:
          'Applied the completed changes. A later step did not finish.',
      actionFailed: (message) => 'Skill organizing failed: $message',
      absorbedInto: (skillName) => 'Absorbed into $skillName',
      actionCount: (count) => '$count action${count == 1 ? '' : 's'}',
      lastActivityNever: 'No activity yet',
    );
  }
}

class _SkillGovernanceSnapshot {
  const _SkillGovernanceSnapshot({
    required this.pending,
    required this.stale,
    required this.archived,
  });

  final List<_PendingEvolutionItem> pending;
  final List<sdk.SkillUsageRecord> stale;
  final List<sdk.SkillUsageRecord> archived;

  static Future<_SkillGovernanceSnapshot> load(
    NapaxiChatClient client,
    String agentId,
  ) async {
    final pendingRaw = await client.listPendingEvolution();
    final usage = await client.listSkillUsage(agentId: agentId);
    final normalizedAgentId = _normalizeSkillGovernanceAgentId(agentId);
    final pending = pendingRaw
        .where(
          (item) =>
              _normalizeSkillGovernanceAgentId(
                item['agent_id'] as String? ?? '',
              ) ==
              normalizedAgentId,
        )
        .map(_PendingEvolutionItem.fromMap)
        .where((item) => item.id.isNotEmpty)
        .toList();
    pending.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final stale = usage.where((record) => record.state == 'stale').toList()
      ..sort((a, b) => a.skillName.compareTo(b.skillName));
    final archived =
        usage.where((record) => record.state == 'archived').toList()
          ..sort((a, b) => a.skillName.compareTo(b.skillName));

    return _SkillGovernanceSnapshot(
      pending: List.unmodifiable(pending),
      stale: List.unmodifiable(stale),
      archived: List.unmodifiable(archived),
    );
  }
}

class _PendingEvolutionItem {
  const _PendingEvolutionItem({
    required this.id,
    required this.actionType,
    required this.reasoning,
    required this.skillNames,
    required this.actions,
    required this.actionCount,
    required this.createdAt,
  });

  final String id;
  final String actionType;
  final String reasoning;
  final List<String> skillNames;
  final List<_PendingEvolutionAction> actions;
  final int actionCount;
  final DateTime createdAt;

  factory _PendingEvolutionItem.fromMap(Map<String, dynamic> map) {
    final action = map['action'];
    final aggregated = (map['aggregated_actions'] as List?) ?? const [];
    final actions = aggregated.isNotEmpty
        ? aggregated
        : (action == null ? const [] : [action]);
    final parsedActions = actions
        .whereType<Map>()
        .map((item) => _PendingEvolutionAction.fromMap(item))
        .toList(growable: false);
    final skillNames = <String>{};
    for (final item in parsedActions) {
      if (item.skillName.trim().isNotEmpty) {
        skillNames.add(item.skillName.trim());
      }
    }

    return _PendingEvolutionItem(
      id: map['id'] as String? ?? '',
      actionType: map['action_type'] as String? ?? _pendingActionType(action),
      reasoning: map['reasoning'] as String? ?? '',
      skillNames: List.unmodifiable(skillNames),
      actions: List.unmodifiable(parsedActions),
      actionCount: parsedActions.isEmpty ? 1 : parsedActions.length,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class _PendingEvolutionAction {
  const _PendingEvolutionAction({
    required this.actionType,
    required this.params,
  });

  final String actionType;
  final Map<String, dynamic> params;

  String get skillName => _stringParam('skill_name');
  String get filePath => _stringParam('file_path');
  String get absorbedInto => _stringParam('absorbed_into');
  String get oldString => _stringParam('old_string');
  String get newString => _stringParam('new_string');
  String get newContent => _stringParam('new_content');
  String get content => _stringParam('content');
  String get fileContent => _stringParam('file_content');

  factory _PendingEvolutionAction.fromMap(Map<dynamic, dynamic> map) {
    final params = map['params'];
    return _PendingEvolutionAction(
      actionType: (map['type'] as String? ?? '').trim(),
      params: params is Map ? Map<String, dynamic>.from(params) : const {},
    );
  }

  String _stringParam(String key) {
    final value = params[key];
    return value is String ? value.trim() : '';
  }
}

class _SkillGovernanceView extends StatefulWidget {
  const _SkillGovernanceView({
    required this.client,
    required this.agentId,
    required this.snapshotFuture,
    required this.onSkillsChanged,
    required this.onSnapshotChanged,
    this.onPendingEvolutionChanged,
  });

  final NapaxiChatClient client;
  final String agentId;
  final Future<_SkillGovernanceSnapshot> snapshotFuture;
  final Future<void> Function() onSkillsChanged;
  final ValueChanged<Future<_SkillGovernanceSnapshot>> onSnapshotChanged;
  final Future<void> Function()? onPendingEvolutionChanged;

  @override
  State<_SkillGovernanceView> createState() => _SkillGovernanceViewState();
}

class _SkillGovernanceViewState extends State<_SkillGovernanceView> {
  late Future<_SkillGovernanceSnapshot> _snapshotFuture;
  String? _busyKey;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = widget.snapshotFuture;
  }

  @override
  void didUpdateWidget(covariant _SkillGovernanceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshotFuture != widget.snapshotFuture) {
      _snapshotFuture = widget.snapshotFuture;
    }
  }

  Future<_SkillGovernanceSnapshot> _loadSnapshot() {
    return _SkillGovernanceSnapshot.load(widget.client, widget.agentId);
  }

  Future<void> _refresh() async {
    final future = _loadSnapshot();
    widget.onSnapshotChanged(future);
    setState(() {
      _snapshotFuture = future;
    });
    await future;
    if (mounted) setState(() {});
  }

  Future<void> _runAction(
    String busyKey,
    Future<void> Function() action,
  ) async {
    if (_busyKey != null) return;
    setState(() => _busyKey = busyKey);
    final labels = _SkillGovernanceLabels.of(context);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        _showSkillSnackBar(
          context,
          labels.actionFailed(_friendlyDisplayError(error)),
        );
      }
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _applyPending(_PendingEvolutionItem item) {
    return _runAction('apply:${item.id}', () async {
      final result = await widget.client.applyPendingEvolution(item.id);
      _throwIfActionError(result);
      if (mounted && result['partial'] == true) {
        _showSkillSnackBar(
          context,
          _SkillGovernanceLabels.of(context).partiallyApplied,
        );
      }
      await widget.onSkillsChanged();
      await widget.onPendingEvolutionChanged?.call();
      await _refresh();
    });
  }

  Future<void> _rejectPending(_PendingEvolutionItem item) {
    return _runAction('reject:${item.id}', () async {
      final result = await widget.client.rejectPendingEvolution(item.id);
      _throwIfActionError(result);
      await widget.onPendingEvolutionChanged?.call();
      await _refresh();
    });
  }

  Future<void> _togglePin(sdk.SkillUsageRecord record) {
    return _runAction('pin:${record.skillName}', () async {
      _throwIfJsonError(
        await widget.client.pinSkill(
          record.skillName,
          agentId: widget.agentId,
          pinned: !record.pinned,
        ),
      );
      await _refresh();
    });
  }

  Future<void> _archiveSkill(sdk.SkillUsageRecord record) {
    return _runAction('archive:${record.skillName}', () async {
      _throwIfJsonError(
        await widget.client.archiveSkill(
          record.skillName,
          agentId: widget.agentId,
        ),
      );
      await widget.onSkillsChanged();
      await _refresh();
    });
  }

  Future<void> _restoreSkill(sdk.SkillUsageRecord record) {
    return _runAction('restore:${record.skillName}', () async {
      _throwIfJsonError(
        await widget.client.restoreSkill(
          record.skillName,
          agentId: widget.agentId,
        ),
      );
      await widget.onSkillsChanged();
      await _refresh();
    });
  }

  Future<void> _organizeUnusedSkills() {
    return _runAction('organize-unused', () async {
      final labels = _SkillGovernanceLabels.of(context);
      final preview = await widget.client.runSkillCurator(
        agentId: widget.agentId,
        dryRun: true,
      );
      if (!mounted) return;
      final confirmed = await _confirmOrganizeUnused(preview, labels);
      if (confirmed != true || !mounted) return;
      final summary = await widget.client.runSkillCurator(
        agentId: widget.agentId,
        dryRun: false,
      );
      if (!mounted) return;
      _showSkillSnackBar(
        context,
        labels.unusedApplied(summary.markedStale, summary.archived),
      );
      await widget.onSkillsChanged();
      await _refresh();
    });
  }

  Future<bool?> _confirmOrganizeUnused(
    sdk.CuratorRunSummary summary,
    _SkillGovernanceLabels labels,
  ) async {
    final actions = summary.actions;
    if (actions.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(labels.organizeUnusedPreviewTitle),
          content: Text(labels.organizeUnusedPreviewEmpty),
          actions: [
            TextButton(
              style: _skillTextButtonStyle(),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(MaterialLocalizations.of(context).okButtonLabel),
            ),
          ],
        ),
      );
      return false;
    }
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(labels.unusedActions(actions.length)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: actions.length,
            separatorBuilder: (_, _) => const Divider(height: 16),
            itemBuilder: (context, index) => Text(actions[index]),
          ),
        ),
        actions: [
          TextButton(
            style: _skillTextButtonStyle(),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppStrings.of(context).cancel),
          ),
          OutlinedButton(
            style: _skillOutlinedButtonStyle(),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(labels.organizeUnusedPreviewConfirm),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labels = _SkillGovernanceLabels.of(context);

    return FutureBuilder<_SkillGovernanceSnapshot>(
      future: _snapshotFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: _SkillLoadingIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _FilesMessage(
            icon: Icons.manage_history_rounded,
            title: labels.actionFailed(_friendlyDisplayError(snapshot.error)),
            description: null,
            action: IconButton(
              tooltip: MaterialLocalizations.of(
                context,
              ).refreshIndicatorSemanticLabel,
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          );
        }

        final data = snapshot.data!;
        final isEmpty =
            data.pending.isEmpty && data.stale.isEmpty && data.archived.isEmpty;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            key: const Key('skill_governance_list'),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              _SkillOrganizeSummary(
                labels: labels,
                snapshot: data,
                busyKey: _busyKey,
                onOrganizeUnused: _organizeUnusedSkills,
              ),
              const SizedBox(height: 12),
              if (!isEmpty) ...[
                _SkillGovernanceSection(
                  title: labels.pending,
                  description: labels.pendingDescription,
                  count: data.pending.length,
                  emptyText: labels.noPending,
                  children: [
                    for (final item in data.pending)
                      _PendingEvolutionTile(
                        item: item,
                        labels: labels,
                        busyKey: _busyKey,
                        onApply: () => _applyPending(item),
                        onReject: () => _rejectPending(item),
                      ),
                  ],
                ),
                _SkillGovernanceSection(
                  title: labels.stale,
                  description: labels.staleDescription,
                  count: data.stale.length,
                  emptyText: labels.noStale,
                  children: [
                    for (final record in data.stale)
                      _SkillUsageTile(
                        record: record,
                        labels: labels,
                        busyKey: _busyKey,
                        archived: false,
                        onPin: () => _togglePin(record),
                        onArchive: () => _archiveSkill(record),
                      ),
                  ],
                ),
                _SkillGovernanceSection(
                  title: labels.archived,
                  description: labels.archivedDescription,
                  count: data.archived.length,
                  emptyText: labels.noArchived,
                  children: [
                    for (final record in data.archived)
                      _SkillUsageTile(
                        record: record,
                        labels: labels,
                        busyKey: _busyKey,
                        archived: true,
                        onRestore: () => _restoreSkill(record),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SkillOrganizeSummary extends StatelessWidget {
  const _SkillOrganizeSummary({
    required this.labels,
    required this.snapshot,
    required this.busyKey,
    required this.onOrganizeUnused,
  });

  final _SkillGovernanceLabels labels;
  final _SkillGovernanceSnapshot snapshot;
  final String? busyKey;
  final VoidCallback onOrganizeUnused;

  @override
  Widget build(BuildContext context) {
    final title = snapshot.pending.isNotEmpty
        ? labels.pendingSummaryTitle(snapshot.pending.length)
        : snapshot.stale.isNotEmpty
        ? labels.unusedSummaryTitle
        : labels.emptySummaryTitle;
    final description = snapshot.pending.isNotEmpty
        ? labels.pendingSummaryDescription
        : snapshot.stale.isNotEmpty
        ? labels.unusedSummaryDescription
        : labels.emptySummaryDescription;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: const TextStyle(
                color: Color(0xFF4B5563),
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('skill_organize_unused'),
                  onPressed: busyKey == null ? onOrganizeUnused : null,
                  style: _skillOutlinedButtonStyle(),
                  icon: _buttonIcon(
                    busyKey == 'organize-unused',
                    Icons.inventory_2_outlined,
                  ),
                  label: Text(labels.organizeUnused),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillGovernanceSection extends StatelessWidget {
  const _SkillGovernanceSection({
    required this.title,
    required this.description,
    required this.count,
    required this.emptyText,
    required this.children,
  });

  final String title;
  final String description;
  final int count;
  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SkillCountBadge(count),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (children.isEmpty)
            _SkillGovernanceEmpty(text: emptyText)
          else
            ...children.expand((child) sync* {
              yield child;
              yield const SizedBox(height: 6);
            }),
        ],
      ),
    );
  }
}

class _SkillCountBadge extends StatelessWidget {
  const _SkillCountBadge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Text(
          '$count',
          style: const TextStyle(
            color: Color(0xFF374151),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SkillGovernanceEmpty extends StatelessWidget {
  const _SkillGovernanceEmpty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              color: Color(0xFF6B7280),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Color(0xFF4B5563), fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingEvolutionTile extends StatelessWidget {
  const _PendingEvolutionTile({
    required this.item,
    required this.labels,
    required this.busyKey,
    required this.onApply,
    required this.onReject,
  });

  final _PendingEvolutionItem item;
  final _SkillGovernanceLabels labels;
  final String? busyKey;
  final VoidCallback onApply;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final names = item.skillNames.isEmpty
        ? item.actionType
        : item.skillNames.join(', ');
    final meta = [
      _humanizePendingActionType(item.actionType),
      if (item.actionCount > 1) '${item.actionCount} actions',
      _formatGovernanceTime(context, item.createdAt),
    ].where((part) => part.trim().isNotEmpty).join(' · ');

    return _SkillGovernanceTile(
      icon: Icons.pending_actions_rounded,
      title: names,
      subtitle: item.reasoning,
      meta: meta,
      onTap: () => _showPendingEvolutionDetails(context, item, labels),
      actions: [
        TextButton.icon(
          onPressed: busyKey == null
              ? () => _showPendingEvolutionDetails(context, item, labels)
              : null,
          style: _skillTextButtonStyle(),
          icon: const Icon(Icons.info_outline_rounded, size: 18),
          label: Text(labels.viewDetails),
        ),
        TextButton.icon(
          onPressed: busyKey == null ? onReject : null,
          style: _skillTextButtonStyle(),
          icon: _buttonIcon(
            busyKey == 'reject:${item.id}',
            Icons.close_rounded,
          ),
          label: Text(labels.reject),
        ),
        OutlinedButton.icon(
          onPressed: busyKey == null ? onApply : null,
          style: _skillOutlinedButtonStyle(),
          icon: _buttonIcon(busyKey == 'apply:${item.id}', Icons.check_rounded),
          label: Text(labels.apply),
        ),
      ],
    );
  }
}

Future<void> _showPendingEvolutionDetails(
  BuildContext context,
  _PendingEvolutionItem item,
  _SkillGovernanceLabels labels,
) {
  final actionLines = item.actions.isEmpty
      ? [_humanizePendingActionType(item.actionType)]
      : item.actions
            .map((action) => _describePendingEvolutionAction(context, action))
            .toList(growable: false);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(labels.detailsTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.reasoning.trim().isNotEmpty) ...[
                Text(
                  item.reasoning,
                  style: const TextStyle(
                    color: Color(0xFF374151),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              for (var index = 0; index < actionLines.length; index++) ...[
                Text(
                  actionLines[index],
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                if (index != actionLines.length - 1) const Divider(height: 18),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          style: _skillTextButtonStyle(),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    ),
  );
}

String _describePendingEvolutionAction(
  BuildContext context,
  _PendingEvolutionAction action,
) {
  final isChinese =
      _AppLanguageScope.languageOf(context) == AppLanguage.chinese;
  final lines = <String>[
    '${isChinese ? '动作' : 'Action'}: ${_humanizePendingActionType(action.actionType)}',
    if (action.skillName.isNotEmpty)
      '${isChinese ? '技能' : 'Skill'}: ${action.skillName}',
    if (action.filePath.isNotEmpty)
      '${isChinese ? '文件' : 'File'}: ${action.filePath}',
    if (action.absorbedInto.isNotEmpty)
      '${isChinese ? '并入' : 'Absorbed into'}: ${action.absorbedInto}',
    if (action.oldString.isNotEmpty)
      '${isChinese ? '原内容' : 'Find'}: ${_previewPendingText(action.oldString)}',
    if (action.newString.isNotEmpty)
      '${isChinese ? '新内容' : 'Replace with'}: ${_previewPendingText(action.newString)}',
    if (action.newContent.isNotEmpty)
      '${isChinese ? '新内容' : 'New content'}: ${_previewPendingText(action.newContent)}',
    if (action.content.isNotEmpty)
      '${isChinese ? '内容' : 'Content'}: ${_previewPendingText(action.content)}',
    if (action.fileContent.isNotEmpty)
      '${isChinese ? '文件内容' : 'File content'}: ${_previewPendingText(action.fileContent)}',
  ];
  return lines.join('\n');
}

String _previewPendingText(String value) {
  final compact = value
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .join(' ');
  if (compact.length <= 180) return compact;
  return '${compact.substring(0, 180)}...';
}

class _SkillUsageTile extends StatelessWidget {
  const _SkillUsageTile({
    required this.record,
    required this.labels,
    required this.busyKey,
    required this.archived,
    this.onPin,
    this.onArchive,
    this.onRestore,
  });

  final sdk.SkillUsageRecord record;
  final _SkillGovernanceLabels labels;
  final String? busyKey;
  final bool archived;
  final VoidCallback? onPin;
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final meta = [
      '${record.useCount} use',
      '${record.viewCount} view',
      '${record.patchCount} patch',
      _lastSkillActivity(context, record),
      if (record.absorbedInto != null)
        labels.absorbedInto(record.absorbedInto!),
    ].where((part) => part.trim().isNotEmpty).join(' · ');

    return _SkillGovernanceTile(
      icon: archived
          ? Icons.archive_outlined
          : Icons.history_toggle_off_rounded,
      title: record.skillName,
      subtitle: record.createdBy == null
          ? ''
          : 'created by ${record.createdBy}',
      meta: meta,
      actions: [
        if (!archived && onPin != null)
          TextButton.icon(
            onPressed: busyKey == null ? onPin : null,
            style: _skillTextButtonStyle(),
            icon: _buttonIcon(
              busyKey == 'pin:${record.skillName}',
              record.pinned ? Icons.push_pin : Icons.push_pin_outlined,
            ),
            label: Text(record.pinned ? labels.unpin : labels.keep),
          ),
        if (!archived && onArchive != null)
          OutlinedButton.icon(
            onPressed: busyKey == null && !record.pinned ? onArchive : null,
            style: _skillOutlinedButtonStyle(),
            icon: _buttonIcon(
              busyKey == 'archive:${record.skillName}',
              Icons.archive_outlined,
            ),
            label: Text(labels.archive),
          ),
        if (archived && onRestore != null)
          OutlinedButton.icon(
            onPressed: busyKey == null ? onRestore : null,
            style: _skillOutlinedButtonStyle(),
            icon: _buttonIcon(
              busyKey == 'restore:${record.skillName}',
              Icons.restore_rounded,
            ),
            label: Text(labels.restore),
          ),
      ],
    );
  }
}

class _SkillGovernanceTile extends StatelessWidget {
  const _SkillGovernanceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.actions,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String meta;
  final List<Widget> actions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: const Color(0xFF4B5563), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (subtitle.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF4B5563),
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (meta.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            meta,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(spacing: 8, runSpacing: 8, children: actions),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _InstalledSkillFilter { all, ready, needsSetup, disabled, issues }

class _InstalledSkillsView extends StatefulWidget {
  const _InstalledSkillsView({
    required this.client,
    required this.agentId,
    required this.skillsFuture,
    required this.statusFuture,
    required this.onRefresh,
    required this.onRemove,
  });

  final NapaxiChatClient client;
  final String agentId;
  final Future<List<sdk.SkillInfo>> skillsFuture;
  final Future<sdk.SkillStatusReport> statusFuture;
  final Future<void> Function() onRefresh;
  final Future<void> Function(sdk.SkillInfo skill) onRemove;

  @override
  State<_InstalledSkillsView> createState() => _InstalledSkillsViewState();
}

class _InstalledSkillsViewState extends State<_InstalledSkillsView> {
  var _filter = _InstalledSkillFilter.all;
  var _query = '';

  Future<void> _runRemediationAction(
    BuildContext context,
    sdk.SkillStatusEntry entry,
    sdk.SkillRemediationAction action,
  ) async {
    final labels = _SkillStatusLabels.of(context);
    final skillKey = _skillStatusConfigKey(entry);
    try {
      final run = await widget.client.requestSkillRemediation(
        entry.name,
        action.id,
        agentId: widget.agentId,
      );
      if (!context.mounted) return;
      switch (action.kind) {
        case 'enable':
          _throwIfJsonError(
            await widget.client.setSkillEnabled(
              entry.name,
              agentId: widget.agentId,
              enabled: true,
            ),
          );
        case 'env':
          final confirmed = await _confirmSkillRemediation(
            context,
            labels.markEnvTitle,
            labels.markEnvMessage(action.requirement),
          );
          if (confirmed != true) return;
          _throwIfJsonError(
            await widget.client.updateSkillConfig(skillKey, {
              'env_keys': [action.requirement],
            }, agentId: widget.agentId),
          );
        case 'config':
          final confirmed = await _confirmSkillRemediation(
            context,
            labels.markConfigTitle,
            labels.markConfigMessage(action.requirement),
          );
          if (confirmed != true) return;
          _throwIfJsonError(
            await widget.client.updateSkillConfig(skillKey, {
              'config_flags': [action.requirement],
            }, agentId: widget.agentId),
          );
        default:
          await _showSkillRemediationInfo(context, labels, action);
          _throwIfJsonError(
            await widget.client
                .recordSkillRequirementResolution(entry.name, action.id, {
                  'acknowledged': true,
                  'kind': action.kind,
                  'requirement': action.requirement,
                  'run_id': run.runId,
                }, agentId: widget.agentId),
          );
      }
      await widget.onRefresh();
      if (context.mounted) {
        _showSkillSnackBar(context, labels.actionRecorded);
      }
    } catch (error) {
      if (!context.mounted) return;
      _showSkillSnackBar(
        context,
        labels.actionFailed(_friendlyDisplayError(error)),
      );
    }
  }

  void _openSkillDetails(
    BuildContext context,
    sdk.SkillInfo skill,
    sdk.SkillStatusEntry? status,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _SkillDetailPage(
          client: widget.client,
          agentId: widget.agentId,
          initialSkill: skill,
          initialStatus: status,
          onRefresh: widget.onRefresh,
          onRemove: () async {
            await widget.onRemove(skill);
            if (context.mounted) Navigator.of(context).pop();
          },
          onRemediationAction: _runRemediationAction,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return FutureBuilder<List<sdk.SkillInfo>>(
      future: widget.skillsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: _SkillLoadingIndicator());
        }
        if (snapshot.hasError) {
          return _FilesMessage(
            icon: Icons.error_outline_rounded,
            title: strings.skillSearchFailed(
              _friendlyDisplayError(snapshot.error),
            ),
            description: null,
            action: IconButton(
              tooltip: MaterialLocalizations.of(
                context,
              ).refreshIndicatorSemanticLabel,
              onPressed: widget.onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          );
        }
        final skills = snapshot.data ?? const [];
        return FutureBuilder<sdk.SkillStatusReport>(
          future: widget.statusFuture,
          builder: (context, statusSnapshot) {
            final report = statusSnapshot.data;
            final statusByName = {
              for (final entry
                  in report?.entries ?? const <sdk.SkillStatusEntry>[])
                entry.name.toLowerCase(): entry,
            };
            if (skills.isEmpty) {
              return RefreshIndicator(
                onRefresh: widget.onRefresh,
                child: ListView(
                  key: const Key('installed_skills_empty_list'),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  children: [
                    SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
                    _FilesMessage(
                      icon: Icons.extension_rounded,
                      title: strings.noSkillsTitle,
                      description: strings.noSkillsDescription,
                    ),
                  ],
                ),
              );
            }
            final filteredSkills = skills
                .where((skill) {
                  final status = statusByName[skill.name.toLowerCase()];
                  return _skillMatchesQuery(skill, _query) &&
                      _skillMatchesFilter(status, _filter);
                })
                .toList(growable: false);
            final filterCounts = {
              for (final filter in _InstalledSkillFilter.values)
                filter: skills
                    .where(
                      (skill) => _skillMatchesFilter(
                        statusByName[skill.name.toLowerCase()],
                        filter,
                      ),
                    )
                    .length,
            };
            return RefreshIndicator(
              onRefresh: widget.onRefresh,
              child: ListView(
                key: const Key('installed_skills_list'),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  _InstalledSkillFilterBar(
                    query: _query,
                    selected: _filter,
                    counts: filterCounts,
                    onQueryChanged: (value) {
                      setState(() {
                        _query = value;
                      });
                    },
                    onFilterChanged: (value) {
                      setState(() {
                        _filter = value;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  if (filteredSkills.isEmpty)
                    _FilesMessage(
                      icon: Icons.search_rounded,
                      title: _SkillListFilterLabels.of(context).noMatches,
                      description: null,
                    ),
                  for (final skill in filteredSkills) ...[
                    _InstalledSkillTile(
                      skill: skill,
                      status: statusByName[skill.name.toLowerCase()],
                      onTap: () => _openSkillDetails(
                        context,
                        skill,
                        statusByName[skill.name.toLowerCase()],
                      ),
                      onRemove: () => widget.onRemove(skill),
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _InstalledSkillFilterBar extends StatelessWidget {
  const _InstalledSkillFilterBar({
    required this.query,
    required this.selected,
    required this.counts,
    required this.onQueryChanged,
    required this.onFilterChanged,
  });

  final String query;
  final _InstalledSkillFilter selected;
  final Map<_InstalledSkillFilter, int> counts;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_InstalledSkillFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final labels = _SkillListFilterLabels.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SkillSearchField(
          key: const Key('installed_skill_search_field'),
          hintText: labels.searchHint,
          onChanged: onQueryChanged,
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final filter in _InstalledSkillFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    key: Key('installed_skill_filter_${filter.name}'),
                    label: Text(
                      '${labels.labelFor(filter)} ${counts[filter] ?? 0}',
                    ),
                    selected: selected == filter,
                    onSelected: (_) => onFilterChanged(filter),
                    showCheckmark: false,
                    backgroundColor: Colors.white,
                    selectedColor: const Color(0xFFF3F4F6),
                    side: BorderSide(
                      color: selected == filter
                          ? const Color(0xFF111827)
                          : const Color(0xFFE5E7EB),
                    ),
                    labelStyle: TextStyle(
                      color: selected == filter
                          ? const Color(0xFF111827)
                          : const Color(0xFF4B5563),
                      fontWeight: selected == filter
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SkillSearchField extends StatelessWidget {
  const _SkillSearchField({
    required this.hintText,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  final String hintText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF333333), width: 1.2),
        ),
      ),
    );
  }
}

class _SkillListFilterLabels {
  const _SkillListFilterLabels({
    required this.searchHint,
    required this.noMatches,
    required this.all,
    required this.ready,
    required this.needsSetup,
    required this.disabled,
    required this.issues,
  });

  final String searchHint;
  final String noMatches;
  final String all;
  final String ready;
  final String needsSetup;
  final String disabled;
  final String issues;

  String labelFor(_InstalledSkillFilter filter) {
    switch (filter) {
      case _InstalledSkillFilter.all:
        return all;
      case _InstalledSkillFilter.ready:
        return ready;
      case _InstalledSkillFilter.needsSetup:
        return needsSetup;
      case _InstalledSkillFilter.disabled:
        return disabled;
      case _InstalledSkillFilter.issues:
        return issues;
    }
  }

  static _SkillListFilterLabels of(BuildContext context) {
    final isChinese =
        _AppLanguageScope.languageOf(context) == AppLanguage.chinese;
    if (isChinese) {
      return const _SkillListFilterLabels(
        searchHint: '搜索',
        noMatches: '没有匹配的技能',
        all: '全部',
        ready: '可用',
        needsSetup: '需配置',
        disabled: '已禁用',
        issues: '有问题',
      );
    }
    return const _SkillListFilterLabels(
      searchHint: 'Search',
      noMatches: 'No matching skills',
      all: 'All',
      ready: 'Ready',
      needsSetup: 'Needs setup',
      disabled: 'Disabled',
      issues: 'Issues',
    );
  }
}

bool _skillMatchesQuery(sdk.SkillInfo skill, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return true;
  return skill.name.toLowerCase().contains(normalized) ||
      skill.description.toLowerCase().contains(normalized) ||
      skill.tags.any((tag) => tag.toLowerCase().contains(normalized)) ||
      skill.keywords.any(
        (keyword) => keyword.toLowerCase().contains(normalized),
      );
}

bool _skillMatchesFilter(
  sdk.SkillStatusEntry? status,
  _InstalledSkillFilter filter,
) {
  switch (filter) {
    case _InstalledSkillFilter.all:
      return true;
    case _InstalledSkillFilter.ready:
      return status != null && status.enabled && status.status == 'ready';
    case _InstalledSkillFilter.needsSetup:
      return status?.status == 'missing_requirements';
    case _InstalledSkillFilter.disabled:
      return status != null && (!status.enabled || status.status == 'disabled');
    case _InstalledSkillFilter.issues:
      return status != null &&
          status.isBlocked &&
          status.status != 'missing_requirements';
  }
}

class _SkillRemediationChip extends StatelessWidget {
  const _SkillRemediationChip({required this.action, this.onPressed});

  final sdk.SkillRemediationAction action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      tooltip: action.requirement,
      onPressed: onPressed,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFFD1D5DB)),
      avatar: Icon(
        action.kind == 'enable'
            ? Icons.toggle_on_outlined
            : Icons.build_circle_outlined,
        size: 14,
        color: const Color(0xFF4B5563),
      ),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Text(
          action.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: const Color(0xFF374151)),
        ),
      ),
    );
  }
}

class _SkillStatusLabels {
  const _SkillStatusLabels({
    required this.markEnvTitle,
    required this.markEnvMessage,
    required this.markConfigTitle,
    required this.markConfigMessage,
    required this.actionRecorded,
    required this.actionFailed,
    required this.actionDetailsTitle,
    required this.actionDetailsMessage,
    required this.actionDetailsConfirm,
  });

  final String markEnvTitle;
  final String Function(String key) markEnvMessage;
  final String markConfigTitle;
  final String Function(String key) markConfigMessage;
  final String actionRecorded;
  final String Function(String message) actionFailed;
  final String actionDetailsTitle;
  final String Function(String label, String requirement) actionDetailsMessage;
  final String actionDetailsConfirm;

  static _SkillStatusLabels of(BuildContext context) {
    final isChinese =
        _AppLanguageScope.languageOf(context) == AppLanguage.chinese;
    if (isChinese) {
      return _SkillStatusLabels(
        markEnvTitle: '标记环境已满足',
        markEnvMessage: (key) => '确认宿主已提供 $key。这里不会保存密钥值，只记录该环境要求已满足。',
        markConfigTitle: '启用配置项',
        markConfigMessage: (key) => '确认启用配置 $key。配置值由宿主负责管理，core 只记录可用性状态。',
        actionRecorded: '技能修复状态已更新',
        actionFailed: (message) => '技能修复失败：$message',
        actionDetailsTitle: '修复动作',
        actionDetailsMessage: (label, requirement) =>
            '$label\n\n需要宿主或用户完成：$requirement',
        actionDetailsConfirm: '已知晓',
      );
    }
    return _SkillStatusLabels(
      markEnvTitle: 'Mark environment ready',
      markEnvMessage: (key) =>
          'Confirm the host provides $key. Secret values are not stored; only readiness is recorded.',
      markConfigTitle: 'Enable config',
      markConfigMessage: (key) =>
          'Confirm config $key is enabled. The host owns actual config values; core records readiness only.',
      actionRecorded: 'Skill remediation updated',
      actionFailed: (message) => 'Skill remediation failed: $message',
      actionDetailsTitle: 'Remediation action',
      actionDetailsMessage: (label, requirement) =>
          '$label\n\nHost or user action required: $requirement',
      actionDetailsConfirm: 'Got it',
    );
  }
}

class _SkillDetailPage extends StatefulWidget {
  const _SkillDetailPage({
    required this.client,
    required this.agentId,
    required this.initialSkill,
    required this.initialStatus,
    required this.onRefresh,
    required this.onRemove,
    required this.onRemediationAction,
  });

  final NapaxiChatClient client;
  final String agentId;
  final sdk.SkillInfo initialSkill;
  final sdk.SkillStatusEntry? initialStatus;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onRemove;
  final Future<void> Function(
    BuildContext context,
    sdk.SkillStatusEntry entry,
    sdk.SkillRemediationAction action,
  )
  onRemediationAction;

  @override
  State<_SkillDetailPage> createState() => _SkillDetailPageState();
}

class _SkillDetailPageState extends State<_SkillDetailPage> {
  late Future<_SkillDetailSnapshot> _snapshotFuture;
  late _SkillDetailSnapshot _initialSnapshot;
  var _toggleBusy = false;

  @override
  void initState() {
    super.initState();
    _initialSnapshot = _SkillDetailSnapshot.initial(
      widget.initialSkill,
      widget.initialStatus,
    );
    _snapshotFuture = _loadSnapshot();
  }

  Future<_SkillDetailSnapshot> _loadSnapshot() {
    return _SkillDetailSnapshot.load(
      widget.client,
      widget.agentId,
      widget.initialSkill,
    );
  }

  Future<void> _refresh() async {
    final future = _loadSnapshot();
    setState(() {
      _snapshotFuture = future;
    });
    await future;
    await widget.onRefresh();
    if (mounted) setState(() {});
  }

  Future<void> _runAction(
    sdk.SkillStatusEntry entry,
    sdk.SkillRemediationAction action,
  ) async {
    await widget.onRemediationAction(context, entry, action);
    await _refresh();
  }

  Future<void> _toggleSkill(sdk.SkillStatusEntry status) async {
    final labels = _SkillDetailLabels.of(context);
    final nextEnabled = !status.enabled;
    if (!nextEnabled) {
      final confirmed = await _confirmSkillRemediation(
        context,
        labels.disableSkillTitle,
        labels.disableSkillMessage(status.name),
      );
      if (confirmed != true) return;
    }

    setState(() => _toggleBusy = true);
    try {
      _throwIfJsonError(
        await widget.client.setSkillEnabled(
          status.name,
          agentId: widget.agentId,
          enabled: nextEnabled,
        ),
      );
      await _refresh();
      if (!mounted) return;
      _showSkillSnackBar(
        context,
        nextEnabled ? labels.skillEnabled : labels.skillDisabled,
      );
    } catch (error) {
      if (!mounted) return;
      _showSkillSnackBar(
        context,
        labels.skillToggleFailed(_friendlyDisplayError(error)),
      );
    } finally {
      if (mounted) setState(() => _toggleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = _SkillDetailLabels.of(context);
    return FutureBuilder<_SkillDetailSnapshot>(
      future: _snapshotFuture,
      initialData: _initialSnapshot,
      builder: (context, snapshot) {
        final data = snapshot.data ?? _initialSnapshot;
        final skill = data.skill;
        final status = data.status;
        final visibleRemediationActions =
            status?.remediationActions
                .where((action) => action.kind != 'enable')
                .toList(growable: false) ??
            const <sdk.SkillRemediationAction>[];
        final displayVersion = _skillDisplayVersion(skill.version);
        final meta = [
          if (displayVersion != null) 'v$displayVersion',
        ].where((part) => part.trim().isNotEmpty).join(' · ');
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(skill.name),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: AppStrings.of(context).removeSkill,
                onPressed: widget.onRemove,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              key: Key('skill_detail_${skill.name}'),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                if (snapshot.connectionState != ConnectionState.done)
                  const _SkillLinearLoadingIndicator(),
                _SkillDetailSection(
                  title: labels.overview,
                  icon: Icons.extension_rounded,
                  children: [
                    if (skill.description.trim().isNotEmpty)
                      _SkillDetailText(skill.description),
                    _SkillDetailKeyValues(
                      rows: [
                        if (displayVersion != null)
                          MapEntry(labels.version, displayVersion),
                        MapEntry(
                          labels.usage,
                          labels.usageValue(
                            skill.lifecycle.useCount,
                            skill.lifecycle.viewCount,
                            skill.lifecycle.patchCount,
                          ),
                        ),
                        if (_lastSkillActivity(
                          context,
                          skill.lifecycle,
                        ).trim().isNotEmpty)
                          MapEntry(
                            labels.recentActivity,
                            _lastSkillActivity(context, skill.lifecycle),
                          ),
                      ],
                    ),
                    _SkillTokenWrap(
                      labels: [
                        ...skill.tags,
                        ...skill.keywords.where(
                          (keyword) => !skill.tags.contains(keyword),
                        ),
                      ],
                    ),
                  ],
                ),
                _SkillDetailSection(
                  title: labels.status,
                  icon: Icons.health_and_safety_outlined,
                  children: [
                    if (status == null)
                      _SkillDetailText(_skillStatusReason(context, status))
                    else ...[
                      Semantics(
                        label: labels.skillToggleSemantics,
                        toggled: status.enabled,
                        child: Switch(
                          key: Key('toggle_skill_${skill.name}'),
                          value: status.enabled,
                          activeThumbColor: const Color(0xFF111827),
                          activeTrackColor: const Color(0xFFD1D5DB),
                          inactiveThumbColor: const Color(0xFF6B7280),
                          inactiveTrackColor: const Color(0xFFE5E7EB),
                          onChanged: _toggleBusy
                              ? null
                              : (_) => _toggleSkill(status),
                        ),
                      ),
                      if (_shouldShowSkillStatusReason(status)) ...[
                        const SizedBox(height: 4),
                        _SkillDetailText(_skillStatusReason(context, status)),
                      ],
                      _SkillDetailKeyValues(
                        rows: [
                          if (status.error != null)
                            MapEntry(labels.error, status.error!),
                          if (status.warnings.isNotEmpty)
                            MapEntry(
                              labels.warnings,
                              status.warnings.join(', '),
                            ),
                        ],
                      ),
                      if (visibleRemediationActions.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final action in visibleRemediationActions)
                              _SkillRemediationChip(
                                action: action,
                                onPressed: () => _runAction(status, action),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
                _SkillDetailSection(
                  title: labels.files,
                  icon: Icons.description_outlined,
                  children: [
                    _SkillFilesPanel(
                      client: widget.client,
                      agentId: widget.agentId,
                      skill: skill,
                      labels: labels,
                    ),
                  ],
                ),
                if (_hasSkillSetupDetails(status, data.secretRequirements))
                  _SkillDetailSection(
                    title: labels.requirements,
                    icon: Icons.tune_rounded,
                    children: [
                      if (status != null && !status.missing.isEmpty)
                        _SkillRequirementList(
                          title: labels.missingRequirements,
                          summary: status.missing,
                          emptyText: labels.noMissingRequirements,
                        ),
                      if (_missingSkillSecrets(
                        data.secretRequirements,
                      ).isNotEmpty) ...[
                        if (status != null && !status.missing.isEmpty)
                          const SizedBox(height: 10),
                        _SkillSecretRequirementList(
                          requirements: data.secretRequirements.requirements,
                          labels: labels,
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SkillDetailSnapshot {
  const _SkillDetailSnapshot({
    required this.skill,
    required this.status,
    required this.secretRequirements,
    required this.remediationRuns,
  });

  final sdk.SkillInfo skill;
  final sdk.SkillStatusEntry? status;
  final sdk.SkillSecretRequirementReport secretRequirements;
  final sdk.SkillRemediationRunList remediationRuns;

  factory _SkillDetailSnapshot.initial(
    sdk.SkillInfo skill,
    sdk.SkillStatusEntry? status,
  ) {
    return _SkillDetailSnapshot(
      skill: skill,
      status: status,
      secretRequirements: const sdk.SkillSecretRequirementReport(),
      remediationRuns: const sdk.SkillRemediationRunList(),
    );
  }

  static Future<_SkillDetailSnapshot> load(
    NapaxiChatClient client,
    String agentId,
    sdk.SkillInfo initialSkill,
  ) async {
    final detail = await client.getSkill(initialSkill.name, agentId: agentId);
    final skill = detail ?? initialSkill;
    final statusReport = await client.listSkillStatus(agentId: agentId);
    final status = statusReport.entries
        .where((entry) => entry.name == skill.name)
        .cast<sdk.SkillStatusEntry?>()
        .firstWhere((entry) => entry != null, orElse: () => null);
    final secrets = await client.listSkillSecretRequirements(
      agentId: agentId,
      skillName: skill.name,
    );
    final runs = await client.listSkillRemediationRuns(
      agentId: agentId,
      skillName: skill.name,
    );
    return _SkillDetailSnapshot(
      skill: skill,
      status: status,
      secretRequirements: secrets,
      remediationRuns: runs,
    );
  }
}

class _SkillDetailLabels {
  const _SkillDetailLabels({
    required this.overview,
    required this.status,
    required this.requirements,
    required this.files,
    required this.version,
    required this.usage,
    required this.recentActivity,
    required this.error,
    required this.warnings,
    required this.missingRequirements,
    required this.noMissingRequirements,
    required this.missingSecrets,
    required this.noMissingSecrets,
    required this.noSupportFiles,
    required this.fileCount,
    required this.skillToggleSemantics,
    required this.disableSkillTitle,
    required this.disableSkillMessage,
    required this.skillEnabled,
    required this.skillDisabled,
    required this.skillToggleFailed,
    required this.usageValue,
  });

  final String overview;
  final String status;
  final String requirements;
  final String files;
  final String version;
  final String usage;
  final String recentActivity;
  final String error;
  final String warnings;
  final String missingRequirements;
  final String noMissingRequirements;
  final String missingSecrets;
  final String noMissingSecrets;
  final String noSupportFiles;
  final String Function(int count) fileCount;
  final String skillToggleSemantics;
  final String disableSkillTitle;
  final String Function(String name) disableSkillMessage;
  final String skillEnabled;
  final String skillDisabled;
  final String Function(String message) skillToggleFailed;
  final String Function(int uses, int views, int patches) usageValue;

  static _SkillDetailLabels of(BuildContext context) {
    final isChinese =
        _AppLanguageScope.languageOf(context) == AppLanguage.chinese;
    if (isChinese) {
      return _SkillDetailLabels(
        overview: '概览',
        status: '启用状态',
        requirements: '需要配置',
        files: '文件',
        version: '版本',
        usage: '使用记录',
        recentActivity: '最近活动',
        error: '错误',
        warnings: '警告',
        missingRequirements: '缺失项',
        noMissingRequirements: '没有缺失的依赖。',
        missingSecrets: '缺少密钥',
        noMissingSecrets: '没有缺失的密钥。',
        noSupportFiles: '没有辅助文件。',
        fileCount: (count) => '$count 个文件',
        skillToggleSemantics: '启用技能',
        disableSkillTitle: '禁用技能？',
        disableSkillMessage: (name) => '禁用后，$name 不会被模型自动调用，也不会出现在可用命令里。',
        skillEnabled: '技能已启用',
        skillDisabled: '技能已禁用',
        skillToggleFailed: (message) => '技能状态更新失败：$message',
        usageValue: (uses, views, patches) =>
            '$uses 次使用 · $views 次查看 · $patches 次优化',
      );
    }
    return _SkillDetailLabels(
      overview: 'Overview',
      status: 'Enablement',
      requirements: 'Setup needed',
      files: 'Files',
      version: 'Version',
      usage: 'Usage',
      recentActivity: 'Recent activity',
      error: 'Error',
      warnings: 'Warnings',
      missingRequirements: 'Missing requirements',
      noMissingRequirements: 'No missing requirements.',
      missingSecrets: 'Missing secrets',
      noMissingSecrets: 'No missing secrets.',
      noSupportFiles: 'No support files.',
      fileCount: (count) => '$count files',
      skillToggleSemantics: 'Enable skill',
      disableSkillTitle: 'Disable skill?',
      disableSkillMessage: (name) =>
          '$name will not be called automatically by the model and will not appear in available commands.',
      skillEnabled: 'Skill enabled',
      skillDisabled: 'Skill disabled',
      skillToggleFailed: (message) => 'Skill status update failed: $message',
      usageValue: (uses, views, patches) =>
          '$uses uses · $views views · $patches patches',
    );
  }
}

class _SkillDetailSection extends StatelessWidget {
  const _SkillDetailSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: const Color(0xFF4B5563)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillDetailText extends StatelessWidget {
  const _SkillDetailText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF4B5563),
          fontSize: 13,
          height: 1.35,
        ),
      ),
    );
  }
}

class _SkillDetailKeyValues extends StatelessWidget {
  const _SkillDetailKeyValues({required this.rows});

  final List<MapEntry<String, String>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    row.key,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.value,
                    style: const TextStyle(
                      color: Color(0xFF374151),
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SkillTokenWrap extends StatelessWidget {
  const _SkillTokenWrap({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final cleaned = labels
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toSet()
        .take(8)
        .toList();
    if (cleaned.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [for (final label in cleaned) _SkillTagChip(label)],
      ),
    );
  }
}

class _SkillRequirementList extends StatelessWidget {
  const _SkillRequirementList({
    required this.title,
    required this.summary,
    required this.emptyText,
  });

  final String title;
  final sdk.SkillRequirementSummary? summary;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final items = _skillRequirementItems(summary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF111827),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        if (items.isEmpty)
          _SkillDetailText(emptyText)
        else
          _SkillTokenWrap(labels: items),
      ],
    );
  }
}

class _SkillSecretRequirementList extends StatelessWidget {
  const _SkillSecretRequirementList({
    required this.requirements,
    required this.labels,
  });

  final List<sdk.SkillSecretRequirement> requirements;
  final _SkillDetailLabels labels;

  @override
  Widget build(BuildContext context) {
    final missing = requirements.where((item) => !item.available).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labels.missingSecrets,
          style: const TextStyle(
            color: Color(0xFF111827),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        if (missing.isEmpty)
          _SkillDetailText(labels.noMissingSecrets)
        else
          for (final item in missing)
            _SkillDetailText('${item.key} · ${item.source}'),
      ],
    );
  }
}

class _SkillFilesPanel extends StatefulWidget {
  const _SkillFilesPanel({
    required this.client,
    required this.agentId,
    required this.skill,
    required this.labels,
  });

  final NapaxiChatClient client;
  final String agentId;
  final sdk.SkillInfo skill;
  final _SkillDetailLabels labels;

  @override
  State<_SkillFilesPanel> createState() => _SkillFilesPanelState();
}

class _SkillFilesPanelState extends State<_SkillFilesPanel> {
  final _collapsedDirectories = <String>{};

  @override
  Widget build(BuildContext context) {
    final hasPrompt = (widget.skill.promptContent ?? '').trim().isNotEmpty;
    final supportFiles = widget.skill.supportFiles
        .where((path) => path.trim() != '_meta.json')
        .toList(growable: false);
    final fileCount = supportFiles.length + (hasPrompt ? 1 : 0);
    if (fileCount == 0) return _SkillDetailText(widget.labels.noSupportFiles);
    final tree = _buildSkillFileTree([
      if (hasPrompt) 'SKILL.md',
      ...supportFiles,
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.labels.fileCount(fileCount),
          style: const TextStyle(
            color: Color(0xFF4B5563),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final node in tree)
                  _SkillFileTreeRow(
                    node: node,
                    depth: 0,
                    onOpenFile: _openFilePreview,
                    collapsedDirectories: _collapsedDirectories,
                    onToggleDirectory: _toggleDirectory,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _toggleDirectory(String path) {
    setState(() {
      if (!_collapsedDirectories.add(path)) {
        _collapsedDirectories.remove(path);
      }
    });
  }

  void _openFilePreview(String filePath) {
    final contentFuture = filePath == 'SKILL.md'
        ? Future<String>.value(widget.skill.promptContent ?? '')
        : widget.client
              .readSkillSupportFile(
                widget.skill.name,
                filePath,
                agentId: widget.agentId,
              )
              .then((result) {
                if (result.success) return result.content ?? '';
                throw StateError(result.error ?? 'Could not read file');
              });
    _showSkillFilePreviewSheet(
      context,
      filePath: filePath,
      contentFuture: contentFuture,
    );
  }
}

class _SkillFileTreeNode {
  _SkillFileTreeNode.directory(this.name, this.path)
    : isDirectory = true,
      children = [];

  _SkillFileTreeNode.file(this.name, this.path)
    : isDirectory = false,
      children = [];

  final String name;
  final String path;
  final bool isDirectory;
  final List<_SkillFileTreeNode> children;
}

List<_SkillFileTreeNode> _buildSkillFileTree(List<String> paths) {
  final roots = <_SkillFileTreeNode>[];
  for (final rawPath in paths) {
    final normalized = rawPath.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) continue;
    final parts = normalized
        .split('/')
        .where((part) => part.trim().isNotEmpty)
        .toList(growable: false);
    var siblings = roots;
    var currentPath = '';
    for (var index = 0; index < parts.length; index += 1) {
      final part = parts[index];
      currentPath = currentPath.isEmpty ? part : '$currentPath/$part';
      final isLast = index == parts.length - 1;
      if (isLast) {
        if (!siblings.any((node) => !node.isDirectory && node.name == part)) {
          siblings.add(_SkillFileTreeNode.file(part, currentPath));
        }
      } else {
        var directory = siblings
            .where((node) => node.isDirectory && node.name == part)
            .cast<_SkillFileTreeNode?>()
            .firstWhere((node) => node != null, orElse: () => null);
        if (directory == null) {
          directory = _SkillFileTreeNode.directory(part, currentPath);
          siblings.add(directory);
        }
        siblings = directory.children;
      }
    }
  }
  _sortSkillFileTree(roots);
  return roots;
}

void _sortSkillFileTree(List<_SkillFileTreeNode> nodes) {
  nodes.sort((a, b) {
    if (a.name == 'SKILL.md') return -1;
    if (b.name == 'SKILL.md') return 1;
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  for (final node in nodes) {
    if (node.isDirectory) _sortSkillFileTree(node.children);
  }
}

class _SkillFileTreeRow extends StatelessWidget {
  const _SkillFileTreeRow({
    required this.node,
    required this.depth,
    required this.onOpenFile,
    required this.collapsedDirectories,
    required this.onToggleDirectory,
  });

  final _SkillFileTreeNode node;
  final int depth;
  final ValueChanged<String> onOpenFile;
  final Set<String> collapsedDirectories;
  final ValueChanged<String> onToggleDirectory;

  @override
  Widget build(BuildContext context) {
    final left = 10.0 + depth * 18.0;
    if (node.isDirectory) {
      final collapsed = collapsedDirectories.contains(node.path);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => onToggleDirectory(node.path),
            child: Padding(
              padding: EdgeInsets.fromLTRB(left, 8, 10, 4),
              child: Row(
                children: [
                  Icon(
                    collapsed
                        ? Icons.folder_rounded
                        : Icons.folder_open_outlined,
                    color: const Color(0xFF4B5563),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      node.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    collapsed
                        ? Icons.keyboard_arrow_right_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF9CA3AF),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (!collapsed)
            for (final child in node.children)
              _SkillFileTreeRow(
                node: child,
                depth: depth + 1,
                onOpenFile: onOpenFile,
                collapsedDirectories: collapsedDirectories,
                onToggleDirectory: onToggleDirectory,
              ),
        ],
      );
    }

    return InkWell(
      onTap: () => onOpenFile(node.path),
      child: Padding(
        padding: EdgeInsets.fromLTRB(left, 7, 10, 7),
        child: Row(
          children: [
            Icon(
              _skillFileIcon(node.path),
              color: const Color(0xFF4B5563),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF9CA3AF),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

void _showSkillFilePreviewSheet(
  BuildContext context, {
  required String filePath,
  required Future<String> contentFuture,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return SafeArea(
        child: Container(
          height: MediaQuery.of(context).size.height * 0.78,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
                child: Row(
                  children: [
                    Icon(
                      _skillFileIcon(filePath),
                      color: const Color(0xFF4B5563),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        filePath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              Expanded(
                child: FutureBuilder<String>(
                  future: contentFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: _SkillLoadingIndicator());
                    }
                    final content = snapshot.hasError
                        ? _friendlyDisplayError(snapshot.error)
                        : snapshot.data ?? '';
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: _SkillFilePreview(content: content),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _SkillFilePreview extends StatelessWidget {
  const _SkillFilePreview({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(
            content,
            style: const TextStyle(
              color: Color(0xFF374151),
              fontSize: 12,
              height: 1.35,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}

String _skillFileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? normalized : normalized.substring(slash + 1);
}

IconData _skillFileIcon(String path) {
  final name = _skillFileName(path).toLowerCase();
  if (name == 'skill.md' || name.endsWith('.md')) {
    return Icons.notes_rounded;
  }
  if (name.endsWith('.sh') ||
      name.endsWith('.py') ||
      name.endsWith('.js') ||
      name.endsWith('.ts') ||
      name.endsWith('.rb') ||
      name.endsWith('.rs') ||
      name.endsWith('.kt') ||
      name.endsWith('.swift')) {
    return Icons.terminal_rounded;
  }
  if (name.endsWith('.json') ||
      name.endsWith('.yaml') ||
      name.endsWith('.yml') ||
      name.endsWith('.toml')) {
    return Icons.data_object_rounded;
  }
  return Icons.insert_drive_file_outlined;
}

String _skillStatusConfigKey(sdk.SkillStatusEntry entry) {
  final skillKey = entry.metadata.skillKey?.trim();
  return skillKey == null || skillKey.isEmpty ? entry.name : skillKey;
}

Future<bool?> _confirmSkillRemediation(
  BuildContext context,
  String title,
  String message,
) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          style: _skillTextButtonStyle(),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(AppStrings.of(context).cancel),
        ),
        OutlinedButton(
          style: _skillOutlinedButtonStyle(),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    ),
  );
}

Future<void> _showSkillRemediationInfo(
  BuildContext context,
  _SkillStatusLabels labels,
  sdk.SkillRemediationAction action,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(labels.actionDetailsTitle),
      content: Text(
        labels.actionDetailsMessage(action.label, action.requirement),
      ),
      actions: [
        TextButton(
          style: _skillTextButtonStyle(),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(labels.actionDetailsConfirm),
        ),
      ],
    ),
  );
}

class _SkillStoreView extends StatefulWidget {
  const _SkillStoreView({
    required this.client,
    required this.installedNames,
    required this.onInstall,
  });

  final NapaxiChatClient client;
  final Set<String> installedNames;
  final Future<void> Function(sdk.CatalogSkillInfo skill) onInstall;

  @override
  State<_SkillStoreView> createState() => _SkillStoreViewState();
}

class _SkillStoreViewState extends State<_SkillStoreView> {
  final TextEditingController _searchController = TextEditingController();
  late Future<sdk.CatalogSearchResult> _searchFuture;
  String _query = '';
  String? _installingSlug;

  @override
  void initState() {
    super.initState();
    _searchFuture = _loadStoreSkills(_query);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search() {
    final query = _searchController.text.trim();
    setState(() {
      _query = query;
      _searchFuture = _loadStoreSkills(query);
    });
  }

  Future<sdk.CatalogSearchResult> _loadStoreSkills(String query) async {
    if (query.trim().isNotEmpty) {
      return widget.client.searchCatalog(query.trim());
    }
    return widget.client.listCatalogPackages(limit: 50);
  }

  Future<void> _install(sdk.CatalogSkillInfo skill) async {
    if (_installingSlug != null) return;
    setState(() => _installingSlug = skill.slug);
    await widget.onInstall(skill);
    if (mounted) setState(() => _installingSlug = null);
  }

  void _showCatalogSkillDetails(
    BuildContext context,
    sdk.CatalogSkillInfo skill,
    bool installed,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => _CatalogSkillDetailSheet(
          skill: skill,
          installed: installed,
          installing: _installingSlug == skill.slug,
          onInstall: () async {
            await _install(skill);
            if (context.mounted) Navigator.of(context).pop();
          },
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Column(
      children: [
        Material(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: _SkillSearchField(
              key: const Key('skill_store_search_field'),
              hintText: strings.searchSkillsHint,
              controller: _searchController,
              onSubmitted: (_) => _search(),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<sdk.CatalogSearchResult>(
            future: _searchFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: _SkillLoadingIndicator());
              }
              if (snapshot.hasError || snapshot.data?.error != null) {
                return _FilesMessage(
                  icon: Icons.error_outline_rounded,
                  title: strings.skillSearchFailed(
                    snapshot.data?.error ??
                        _friendlyDisplayError(snapshot.error),
                  ),
                  description: null,
                );
              }
              final results = snapshot.data?.results ?? const [];
              if (results.isEmpty) {
                return _FilesMessage(
                  icon: Icons.manage_search_rounded,
                  title: strings.noSkillStoreResultsTitle,
                  description: strings.noSkillStoreResultsDescription,
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _search(),
                child: ListView.separated(
                  key: const Key('skill_store_results_list'),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final skill = results[index];
                    final installed =
                        widget.installedNames.contains(skill.slug.toLowerCase());
                    return _CatalogSkillTile(
                      skill: skill,
                      installed: installed,
                      installing: _installingSlug == skill.slug,
                      onInstall: () => _install(skill),
                      onTap: () => _showCatalogSkillDetails(
                        context,
                        skill,
                        installed,
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _InstalledSkillTile extends StatelessWidget {
  const _InstalledSkillTile({
    required this.skill,
    required this.status,
    required this.onTap,
    required this.onRemove,
  });

  final sdk.SkillInfo skill;
  final sdk.SkillStatusEntry? status;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final displayVersion = _skillDisplayVersion(skill.version);
    final meta = [if (displayVersion != null) 'v$displayVersion'].join(' · ');

    return _SkillTileFrame(
      leading: Icons.extension_rounded,
      title: skill.name,
      subtitle: skill.description,
      meta: meta,
      tags: skill.tags,
      onTap: onTap,
      statusBadge: _SkillStateBadge(status: status),
      trailing: IconButton(
        key: Key('remove_skill_${skill.name}'),
        tooltip: strings.removeSkill,
        onPressed: onRemove,
        icon: const Icon(Icons.delete_outline_rounded),
      ),
    );
  }
}

class _CatalogSkillTile extends StatelessWidget {
  const _CatalogSkillTile({
    required this.skill,
    required this.installed,
    required this.installing,
    required this.onInstall,
    this.onTap,
  });

  final sdk.CatalogSkillInfo skill;
  final bool installed;
  final bool installing;
  final VoidCallback? onInstall;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final meta = [
      if (skill.version.trim().isNotEmpty) 'v${skill.version}',
      if ((skill.ownerName ?? skill.owner)?.trim().isNotEmpty == true)
        (skill.ownerName ?? skill.owner)!.trim(),
      if (skill.stars != null) '${skill.stars} stars',
      if (skill.downloads != null) '${skill.downloads} downloads',
    ].join(' · ');

    return _SkillTileFrame(
      leading: Icons.storefront_rounded,
      title: skill.name.isEmpty ? skill.slug : skill.name,
      subtitle: skill.description,
      meta: meta,
      tags: skill.tags,
      onTap: onTap,
      trailing: TextButton.icon(
        key: Key('install_skill_${skill.slug}'),
        onPressed: installing ? null : onInstall,
        style: _skillTextButtonStyle(),
        icon: installing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF111827),
                ),
              )
            : Icon(installed ? Icons.sync_rounded : Icons.add_rounded),
        label: Text(
          installed ? strings.updateSkill : strings.installSkill,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _CatalogSkillDetailSheet extends StatelessWidget {
  const _CatalogSkillDetailSheet({
    required this.skill,
    required this.installed,
    required this.installing,
    required this.onInstall,
    required this.scrollController,
  });

  final sdk.CatalogSkillInfo skill;
  final bool installed;
  final bool installing;
  final VoidCallback onInstall;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final displayName = skill.name.isEmpty ? skill.slug : skill.name;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          children: [
            const Icon(
              Icons.storefront_rounded,
              color: Color(0xFF4B5563),
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ),
          ],
        ),
        if (skill.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            skill.description,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF4B5563),
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (skill.version.isNotEmpty)
          _CatalogDetailRow(
            label: 'Version',
            value: 'v${skill.version}',
          ),
        if ((skill.ownerName ?? skill.owner)?.isNotEmpty == true)
          _CatalogDetailRow(
            label: 'Author',
            value: (skill.ownerName ?? skill.owner)!,
          ),
        if (skill.downloads != null)
          _CatalogDetailRow(
            label: 'Downloads',
            value: '${skill.downloads}',
          ),
        if (skill.stars != null)
          _CatalogDetailRow(
            label: 'Stars',
            value: '${skill.stars}',
          ),
        if (skill.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in skill.tags)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    tag,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: installing ? null : onInstall,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF111827),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(44),
          ),
          icon: installing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(installed ? Icons.sync_rounded : Icons.download_rounded),
          label: Text(installed ? strings.updateSkill : strings.installSkill),
        ),
      ],
    );
  }
}

class _CatalogDetailRow extends StatelessWidget {
  const _CatalogDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF9CA3AF),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF374151),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkillTileFrame extends StatelessWidget {
  const _SkillTileFrame({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.tags,
    required this.trailing,
    this.onTap,
    this.statusBadge,
  });

  final IconData leading;
  final String title;
  final String subtitle;
  final String meta;
  final List<String> tags;
  final Widget trailing;
  final VoidCallback? onTap;
  final Widget? statusBadge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(leading, color: const Color(0xFF4B5563), size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF1F2937),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (statusBadge != null) ...[
                          const SizedBox(width: 8),
                          statusBadge!,
                        ],
                      ],
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF4B5563),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tag in tags.take(4)) _SkillTagChip(tag),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillStateBadge extends StatelessWidget {
  const _SkillStateBadge({required this.status});

  final sdk.SkillStatusEntry? status;

  @override
  Widget build(BuildContext context) {
    final label = _skillStatusBadgeLabel(context, status);
    final tone = _skillStatusBadgeTone(status);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tone.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            color: tone.foreground,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SkillTagChip extends StatelessWidget {
  const _SkillTagChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          label,
          style: const TextStyle(color: Color(0xFF4B5563), fontSize: 11),
        ),
      ),
    );
  }
}

Widget _buttonIcon(bool busy, IconData icon) {
  if (!busy) return Icon(icon);
  return const SizedBox(
    width: 16,
    height: 16,
    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF111827)),
  );
}

class _SkillLoadingIndicator extends StatelessWidget {
  const _SkillLoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Color(0xFF111827),
      ),
    );
  }
}

class _SkillLinearLoadingIndicator extends StatelessWidget {
  const _SkillLinearLoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const LinearProgressIndicator(
      minHeight: 2,
      color: Color(0xFF111827),
      backgroundColor: Color(0xFFE5E7EB),
    );
  }
}

ButtonStyle _skillOutlinedButtonStyle() {
  return OutlinedButton.styleFrom(
    foregroundColor: const Color(0xFF111827),
    disabledForegroundColor: const Color(0xFF9CA3AF),
    side: const BorderSide(color: Color(0xFFD1D5DB)),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    minimumSize: const Size(0, 32),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}

ButtonStyle _skillTextButtonStyle() {
  return TextButton.styleFrom(
    foregroundColor: const Color(0xFF111827),
    disabledForegroundColor: const Color(0xFF9CA3AF),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    minimumSize: const Size(0, 32),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}

String _normalizeSkillGovernanceAgentId(String agentId) {
  final trimmed = agentId.trim();
  return trimmed.isEmpty ? sdk.NapaxiEngine.defaultAgentId : trimmed;
}

String? _skillDisplayVersion(String version) {
  final value = version.trim();
  if (value.isEmpty || value == '0.0.0') return null;
  return value;
}

String _pendingActionType(Object? action) {
  if (action is Map) {
    final type = action['type'];
    if (type is String && type.trim().isNotEmpty) return type.trim();
  }
  return 'pending';
}

String _humanizePendingActionType(String value) {
  final spaced = value
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match[1]} ${match[2]}',
      )
      .replaceAll('_', ' ')
      .trim();
  if (spaced.isEmpty) return value;
  return spaced[0].toUpperCase() + spaced.substring(1);
}

void _throwIfActionError(Map<String, dynamic> result) {
  if (result['success'] == true || result['partial'] == true) return;
  final error = result['error'];
  if (error is String && error.trim().isNotEmpty) {
    throw StateError(error);
  }
}

void _throwIfJsonError(String jsonResult) {
  final decoded = jsonDecode(jsonResult);
  if (decoded is Map) {
    final error = decoded['error'];
    if (error is String && error.trim().isNotEmpty) {
      throw StateError(error);
    }
  }
}

String _formatGovernanceTime(BuildContext context, DateTime value) {
  if (value.millisecondsSinceEpoch == 0) return '';
  final local = value.toLocal();
  final now = DateTime.now();
  final elapsed = now.difference(local);
  final isChinese =
      _AppLanguageScope.languageOf(context) == AppLanguage.chinese;
  if (elapsed.inMinutes < 1) return isChinese ? '刚刚' : 'just now';
  if (elapsed.inHours < 1) {
    return isChinese ? '${elapsed.inMinutes}分钟前' : '${elapsed.inMinutes}m ago';
  }
  if (elapsed.inDays < 1) {
    return isChinese ? '${elapsed.inHours}小时前' : '${elapsed.inHours}h ago';
  }
  if (elapsed.inDays < 7) {
    return isChinese ? '${elapsed.inDays}天前' : '${elapsed.inDays}d ago';
  }
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

String _skillStatusBadgeLabel(
  BuildContext context,
  sdk.SkillStatusEntry? status,
) {
  final isChinese =
      _AppLanguageScope.languageOf(context) == AppLanguage.chinese;
  if (status != null && !status.enabled) {
    return isChinese ? '已禁用' : 'Disabled';
  }
  switch (status?.status) {
    case 'ready':
      return isChinese ? '可用' : 'Ready';
    case 'disabled':
      return isChinese ? '已禁用' : 'Disabled';
    case 'missing_requirements':
      return isChinese ? '需配置' : 'Needs setup';
    case 'parse_error':
      return isChinese ? '解析失败' : 'Parse error';
    case 'security_blocked':
      return isChinese ? '安全阻止' : 'Blocked';
    case 'too_large':
      return isChinese ? '过大' : 'Too large';
    case 'blocked':
      return isChinese ? '有问题' : 'Issue';
    default:
      return isChinese ? '检查中' : 'Checking';
  }
}

({Color background, Color border, Color foreground}) _skillStatusBadgeTone(
  sdk.SkillStatusEntry? status,
) {
  if (status != null && !status.enabled) {
    return (
      background: const Color(0xFFF9FAFB),
      border: const Color(0xFFD1D5DB),
      foreground: const Color(0xFF6B7280),
    );
  }
  switch (status?.status) {
    case 'ready':
      return (
        background: Colors.white,
        border: const Color(0xFFE5E7EB),
        foreground: const Color(0xFF111827),
      );
    case 'disabled':
      return (
        background: const Color(0xFFF9FAFB),
        border: const Color(0xFFD1D5DB),
        foreground: const Color(0xFF6B7280),
      );
    case 'missing_requirements':
      return (
        background: const Color(0xFFF3F4F6),
        border: const Color(0xFFD1D5DB),
        foreground: const Color(0xFF374151),
      );
    case 'parse_error':
    case 'security_blocked':
    case 'too_large':
    case 'blocked':
      return (
        background: const Color(0xFFE5E7EB),
        border: const Color(0xFF9CA3AF),
        foreground: const Color(0xFF111827),
      );
    default:
      return (
        background: Colors.white,
        border: const Color(0xFFE5E7EB),
        foreground: const Color(0xFF4B5563),
      );
  }
}

String _skillStatusReason(BuildContext context, sdk.SkillStatusEntry? status) {
  final isChinese =
      _AppLanguageScope.languageOf(context) == AppLanguage.chinese;
  if (status == null) {
    return isChinese ? '正在检查技能状态。' : 'Checking skill status.';
  }
  if (!status.enabled) {
    return isChinese ? '当前已禁用。' : 'Currently disabled.';
  }
  if ((status.error ?? '').trim().isNotEmpty) return status.error!;
  switch (status.status) {
    case 'ready':
      return isChinese ? '可以正常使用。' : 'Ready to use.';
    case 'disabled':
      return isChinese ? '当前已禁用。' : 'Currently disabled.';
    case 'missing_requirements':
      return isChinese ? '需要补充配置或依赖。' : 'Needs configuration or dependencies.';
    case 'parse_error':
      return isChinese ? '技能文件解析失败。' : 'The skill file could not be parsed.';
    case 'security_blocked':
      return isChinese ? '被安全策略阻止。' : 'Blocked by security policy.';
    case 'too_large':
      return isChinese ? '技能内容超过大小限制。' : 'The skill content is too large.';
    case 'blocked':
      return isChinese ? '当前存在阻塞问题。' : 'This skill has a blocking issue.';
    default:
      return status.status;
  }
}

bool _shouldShowSkillStatusReason(sdk.SkillStatusEntry status) {
  return status.isBlocked && (status.error ?? '').trim().isEmpty;
}

bool _hasSkillSetupDetails(
  sdk.SkillStatusEntry? status,
  sdk.SkillSecretRequirementReport secrets,
) {
  return (status != null && !status.missing.isEmpty) ||
      _missingSkillSecrets(secrets).isNotEmpty;
}

List<sdk.SkillSecretRequirement> _missingSkillSecrets(
  sdk.SkillSecretRequirementReport report,
) {
  return report.requirements
      .where((requirement) => !requirement.available)
      .toList(growable: false);
}

List<String> _skillRequirementItems(sdk.SkillRequirementSummary? summary) {
  if (summary == null || summary.isEmpty) return const [];
  return [
    for (final item in summary.env) 'env: $item',
    for (final item in summary.config) 'config: $item',
    for (final item in summary.bins) 'bin: $item',
    for (final item in summary.anyBins) 'any bin: $item',
    for (final item in summary.os) 'os: $item',
    for (final item in summary.capabilities) 'capability: $item',
    for (final item in summary.skills) 'skill: $item',
  ];
}

String _lastSkillActivity(
  BuildContext context,
  sdk.SkillLifecycleSummary record,
) {
  final candidates = [
    record.lastUsedAt,
    record.lastPatchedAt,
    record.lastViewedAt,
    if (record is sdk.SkillUsageRecord) record.createdAt,
  ];
  for (final value in candidates) {
    final parsed = DateTime.tryParse(value ?? '');
    if (parsed != null) return _formatGovernanceTime(context, parsed);
  }
  return '';
}

void _showSkillSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
