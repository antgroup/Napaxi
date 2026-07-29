part of '../main.dart';

const _contactEmail = 'tommi.m886@gmail.com';
const _contactAdminWeChat = 'shu_wentao';
const _defaultContactConfigUrl =
    'https://napa-feedback-ztddnpduxt.cn-shanghai.fcapp.run';
const _contactConfigUrl = String.fromEnvironment(
  'CONTACT_URL',
  defaultValue: _defaultContactConfigUrl,
);
const _dingtalkGroupQrAsset = 'assets/contact/dingtalk_group.png';
const _wechatGroupQrAsset = 'assets/contact/wechat_group.jpg';
const _nearbyPeerRemarksKey = 'agent_demo.a2a_local.peer_remarks.v1';
const _sessionMenuText = Color(0xFF171717);
const _sessionMenuMuted = Color(0xFF707070);

enum _SessionAction { open, pinToggle, rename, delete }

class _ContactConfig {
  const _ContactConfig({
    required this.email,
    required this.wechatAdminId,
    this.dingtalkQrBytes,
    this.wechatQrBytes,
  });

  final String email;
  final String wechatAdminId;
  final Uint8List? dingtalkQrBytes;
  final Uint8List? wechatQrBytes;

  static const fallback = _ContactConfig(
    email: _contactEmail,
    wechatAdminId: _contactAdminWeChat,
  );

  factory _ContactConfig.fromJson(Map<String, Object?> json) {
    return _ContactConfig(
      email: _jsonString(json['email']) ?? _contactEmail,
      wechatAdminId:
          _jsonString(json['wechatAdminId']) ??
          _jsonString(json['adminWeChat']) ??
          _contactAdminWeChat,
      dingtalkQrBytes: _bytesFromDataUrl(
        _jsonString(json['dingtalkQrDataUrl']),
      ),
      wechatQrBytes: _bytesFromDataUrl(_jsonString(json['wechatQrDataUrl'])),
    );
  }
}

String? _jsonString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

Uint8List? _bytesFromDataUrl(String? dataUrl) {
  if (dataUrl == null) return null;
  final comma = dataUrl.indexOf(',');
  if (!dataUrl.startsWith('data:image') || comma < 0) return null;
  try {
    return base64Decode(dataUrl.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

Future<_ContactConfig> _loadContactConfig() async {
  if (_contactConfigUrl.isEmpty) return _ContactConfig.fallback;
  try {
    final baseUri = Uri.parse(_contactConfigUrl);
    final uri = baseUri.replace(
      queryParameters: {
        ...baseUri.queryParameters,
        'format': 'json',
        '_ts': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    final response = await http
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return _ContactConfig.fallback;
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map) {
      return _ContactConfig.fromJson(Map<String, Object?>.from(decoded));
    }
  } catch (_) {
    // Keep the contact page usable even when the config service is unreachable.
  }
  return _ContactConfig.fallback;
}

class _SessionMenuAction extends StatelessWidget {
  const _SessionMenuAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.selectedKey,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final Key? selectedKey;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: selected ? selectedKey : null,
      color: selected ? const Color(0xFFE7E7E7) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        hoverColor: const Color(0xFFF4F4F4),
        highlightColor: const Color(0xFFECECEC),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 26,
                  child: Center(
                    child: Icon(icon, color: _sessionMenuText, size: 24),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _sessionMenuText,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
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

class _SessionSheetAction extends StatelessWidget {
  const _SessionSheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
    this.showIconSlash = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;
  final bool showIconSlash;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = isDestructive
        ? const Color(0xFFDC2626)
        : _sessionMenuText;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        highlightColor: const Color(0xFFE7E8EA),
        splashColor: const Color(0xFFD4D4D4).withValues(alpha: 0.2),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 22,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, color: foregroundColor, size: 22),
                    if (showIconSlash)
                      Transform.rotate(
                        angle: -0.785398,
                        child: Container(
                          key: const Key('session_action_icon_slash'),
                          width: 25,
                          height: 5,
                          color: _appSurfaceColor,
                          alignment: Alignment.center,
                          child: Container(
                            width: 25,
                            height: 2,
                            decoration: BoxDecoration(
                              color: foregroundColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _friendlyDisplayError(Object? error) {
  if (error == null) return 'Unknown error';
  final text = error.toString();
  const exceptionPrefix = 'Exception: ';
  if (text.startsWith(exceptionPrefix)) {
    return text.substring(exceptionPrefix.length);
  }
  return text;
}

String _sessionHistoryDisplayTitle(ChatSession session) {
  final sanitized = _sanitizeA2AProtocolText(session.displayTitle).trim();
  if (sanitized.isEmpty) return session.displayTitle;
  return sanitized;
}

String _sessionHistoryPreview(ChatSession session) {
  final sanitized = _sanitizeA2AProtocolText(session.preview).trim();
  if (sanitized.isEmpty) return session.preview;
  return sanitized;
}

List<String> _sessionHistoryExpandedPreview(
  BuildContext context,
  ChatSession session,
) {
  final isChinese =
      _AppLanguageScope.languageOf(context) == AppLanguage.chinese;
  final entries = <String>[];

  for (final message in session.messages.reversed) {
    if (message.id == 'welcome') continue;

    var content = _sanitizeA2AProtocolText(message.content).trim();
    if (content.isEmpty && message.attachments.isNotEmpty) {
      final attachmentNames = message.attachments
          .map((attachment) => attachment.name)
          .where((name) => name.trim().isNotEmpty)
          .take(2)
          .join(isChinese ? '、' : ', ');
      content = attachmentNames.isEmpty
          ? (isChinese ? '附件' : 'Attachment')
          : (isChinese
                ? '附件：$attachmentNames'
                : 'Attachment: $attachmentNames');
    }
    if (content.isEmpty) continue;

    final speaker = message.isUser ? (isChinese ? '你' : 'You') : 'napaxi';
    entries.add('$speaker${isChinese ? '：' : ': '}$content');
    if (entries.length == 3) break;
  }

  if (entries.isEmpty) {
    return <String>[_sessionHistoryPreview(session)];
  }
  return entries;
}

String _fileNameFromPath(String path) {
  final normalized = path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  if (normalized.isEmpty) return path;
  return normalized.split('/').last;
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
}

String _formatFileDate(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

class _SessionHistorySheet extends StatefulWidget {
  const _SessionHistorySheet({
    required this.activeAgent,
    required this.sessions,
    required this.sessionRuns,
    required this.a2aUnreadSessionIds,
    required this.activeSessionId,
    required this.projects,
    required this.projectSessionIds,
    required this.initialView,
    required this.initialSettingsSection,
    required this.initialSkillsTab,
    required this.createFilesClientFuture,
    required this.createSkillsClientFuture,
    required this.createScenariosClientFuture,
    required this.createNearbyClientFuture,
    required this.activeScenarioId,
    required this.gitSettings,
    required this.onScenarioApplied,
    required this.onGitSettingsChanged,
    required this.onGitSettingsCleared,
    required this.updateService,
    required this.feedbackService,
    required this.config,
    required this.onConfigChanged,
    required this.onLanguageChanged,
    required this.onEngineConfigChanged,
    required this.onCheckForUpdates,
    required this.onNearbyStart,
    required this.onNearbyStop,
    required this.onNearbyInvite,
    required this.onNearbyScan,
    required this.onNearbyDeletePeer,
    required this.getNearbyPairingDiagnostic,
    required this.onNewSession,
    required this.onProjectCreated,
    required this.onProjectChatStarted,
    required this.onProjectPinToggle,
    required this.onProjectSettings,
    required this.onProjectDelete,
    required this.onProjectSessionRemove,
    required this.onFilesSelected,
    required this.onSkillsSelected,
    required this.onProjectsSelected,
    required this.onSettingsSelected,
    required this.primaryView,
    required this.onSessionSelected,
    required this.onSessionPinToggle,
    required this.onSessionRename,
    required this.onSessionRenameEditingChanged,
    required this.onSearchModeChanged,
    required this.onSessionDelete,
    this.onPendingEvolutionChanged,
  });

  final DemoAgent activeAgent;
  final List<ChatSession> sessions;
  final Map<String, ChatSessionRunState> sessionRuns;
  final Set<String> a2aUnreadSessionIds;
  final String activeSessionId;
  final List<_ChatProject> projects;
  final Map<String, String> projectSessionIds;
  final _SessionHistoryView initialView;
  final _SettingsSection initialSettingsSection;
  final _SkillsInitialTab initialSkillsTab;
  final Future<NapaxiChatClient> Function() createFilesClientFuture;
  final Future<NapaxiChatClient> Function() createSkillsClientFuture;
  final Future<NapaxiChatClient> Function() createScenariosClientFuture;
  final Future<NapaxiChatClient> Function() createNearbyClientFuture;
  final String activeScenarioId;
  final DemoGitSettings gitSettings;
  final Future<void> Function(String scenarioId) onScenarioApplied;
  final Future<void> Function(DemoGitSettings settings) onGitSettingsChanged;
  final Future<void> Function() onGitSettingsCleared;
  final DemoUpdateService updateService;
  final DemoFeedbackService feedbackService;
  final LlmConfigState config;
  final ValueChanged<LlmConfigState> onConfigChanged;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final VoidCallback onEngineConfigChanged;
  final VoidCallback onCheckForUpdates;
  final Future<void> Function() onNearbyStart;
  final Future<void> Function() onNearbyStop;
  final Future<void> Function() onNearbyInvite;
  final Future<void> Function() onNearbyScan;
  final Future<void> Function(sdk.A2APeer peer) onNearbyDeletePeer;
  final Future<String?> Function() getNearbyPairingDiagnostic;
  final VoidCallback onNewSession;
  final ValueChanged<_NewProjectDraft> onProjectCreated;
  final Future<void> Function(String projectId, String message)
  onProjectChatStarted;
  final ValueChanged<_ChatProject> onProjectPinToggle;
  final ValueChanged<_ChatProject> onProjectSettings;
  final ValueChanged<_ChatProject> onProjectDelete;
  final ValueChanged<String> onProjectSessionRemove;
  final VoidCallback onFilesSelected;
  final VoidCallback onSkillsSelected;
  final VoidCallback onProjectsSelected;
  final VoidCallback onSettingsSelected;
  final _ChatPrimaryView primaryView;
  final ValueChanged<String> onSessionSelected;
  final ValueChanged<String> onSessionPinToggle;
  final void Function(String sessionId, String title) onSessionRename;
  final ValueChanged<bool> onSessionRenameEditingChanged;
  final ValueChanged<bool> onSearchModeChanged;
  final ValueChanged<String> onSessionDelete;
  final Future<void> Function()? onPendingEvolutionChanged;

  @override
  State<_SessionHistorySheet> createState() => _SessionHistorySheetState();
}

class _SessionHistorySheetState extends State<_SessionHistorySheet> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _isSearching = false;
  bool _showSearchClose = false;
  String _searchQuery = '';
  late _SessionHistoryView _view;
  final List<_SessionHistoryView> _viewStack = [];
  _SettingsSection _settingsInitialSection = _SettingsSection.menu;
  late _SkillsInitialTab _skillsInitialTab;
  Future<NapaxiChatClient>? _filesClientFuture;
  Future<NapaxiChatClient>? _skillsClientFuture;
  Future<NapaxiChatClient>? _scenariosClientFuture;
  Future<NapaxiChatClient>? _repoWorkbenchClientFuture;
  Future<sdk.NapaxiScenarioUiContribution?>? _repoWorkbenchContributionFuture;
  sdk.NapaxiScenarioUiContribution? _repoWorkbenchContribution;
  Future<sdk.NapaxiScenarioUiContribution?>? _environmentContributionFuture;
  sdk.NapaxiScenarioUiContribution? _environmentContribution;
  String? _selectedProjectId;

  @override
  void initState() {
    super.initState();
    _view = widget.initialView;
    _settingsInitialSection = widget.initialSettingsSection;
    _skillsInitialTab = widget.initialSkillsTab;
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void didUpdateWidget(covariant _SessionHistorySheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialView != widget.initialView ||
        oldWidget.initialSettingsSection != widget.initialSettingsSection ||
        oldWidget.initialSkillsTab != widget.initialSkillsTab) {
      _view = widget.initialView;
      _viewStack.clear();
      _settingsInitialSection = widget.initialSettingsSection;
      _skillsInitialTab = widget.initialSkillsTab;
    }
    if (oldWidget.config != widget.config ||
        oldWidget.activeAgent.id != widget.activeAgent.id) {
      _filesClientFuture = null;
      _skillsClientFuture = null;
    }
    if (oldWidget.activeScenarioId != widget.activeScenarioId) {
      _repoWorkbenchContributionFuture = null;
      _repoWorkbenchContribution = null;
      _environmentContributionFuture = null;
      _environmentContribution = null;
      if (_view == _SessionHistoryView.repositories ||
          _view == _SessionHistoryView.environment) {
        _view = _SessionHistoryView.menu;
        _viewStack.clear();
      }
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final query = _searchController.text.trim();
    if (query == _searchQuery) return;
    setState(() => _searchQuery = query);
  }

  void _toggleSearch() {
    final opening = !_isSearching;
    setState(() {
      _isSearching = opening;
      _showSearchClose = false;
      if (!opening) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
    widget.onSearchModeChanged(opening);
    if (opening) {
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        if (!mounted || !_isSearching) return;
        setState(() => _showSearchClose = true);
      });
      Future<void>.delayed(const Duration(milliseconds: 180), () {
        if (mounted && _isSearching) _searchFocusNode.requestFocus();
      });
    } else {
      _searchFocusNode.unfocus();
    }
  }

  void _navigateTo(_SessionHistoryView target) {
    setState(() {
      _viewStack.add(_view);
      _view = target;
    });
  }

  Future<sdk.NapaxiScenarioUiContribution?> _loadRepoWorkbenchContribution() {
    return loadRepoWorkbenchContribution(
      createScenariosClientFuture: () =>
          _scenariosClientFuture ??= widget.createScenariosClientFuture(),
      activeScenarioId: widget.activeScenarioId,
    );
  }

  Future<sdk.NapaxiScenarioUiContribution?>
  _loadEnvironmentContribution() async {
    final activeScenarioId = _normalizeDemoScenarioId(widget.activeScenarioId);
    final client = await (_scenariosClientFuture ??= widget
        .createScenariosClientFuture());
    final packs = _demoScenarioPacks(await client.listScenarioPacks());
    for (final pack in packs) {
      if (pack.id != activeScenarioId) continue;
      for (final contribution in pack.uiContributions) {
        final placement = contribution.placement.trim().toLowerCase();
        final renderer = contribution.renderer.trim().toLowerCase();
        if ((placement.isEmpty || placement == 'left_menu') &&
            renderer == 'environment') {
          return contribution;
        }
      }
    }
    return null;
  }

  Widget _buildRepoWorkbenchMenuAction() {
    final fallback =
        _normalizeDemoScenarioId(widget.activeScenarioId) ==
            _mobileDevelopmentScenarioId
        ? _fallbackRepoWorkbenchContribution
        : null;
    _repoWorkbenchContributionFuture ??= _loadRepoWorkbenchContribution();
    return FutureBuilder<sdk.NapaxiScenarioUiContribution?>(
      future: _repoWorkbenchContributionFuture,
      builder: (context, snapshot) {
        final contribution = snapshot.data ?? fallback;
        if (contribution == null) return const SizedBox.shrink();
        return Column(
          children: [
            const SizedBox(height: 6),
            _SessionMenuAction(
              key: const Key('repo_workbench_menu_item'),
              icon: _repoContributionIcon(contribution),
              label: _repoWorkbenchTitle(context, contribution),
              onTap: () {
                _repoWorkbenchContribution = contribution;
                _navigateTo(_SessionHistoryView.repositories);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildEnvironmentMenuAction() {
    final fallback =
        _normalizeDemoScenarioId(widget.activeScenarioId) ==
            _mobileDevelopmentScenarioId
        ? _fallbackEnvironmentContribution
        : null;
    _environmentContributionFuture ??= _loadEnvironmentContribution();
    return FutureBuilder<sdk.NapaxiScenarioUiContribution?>(
      future: _environmentContributionFuture,
      builder: (context, snapshot) {
        final contribution = snapshot.data ?? fallback;
        if (contribution == null) return const SizedBox.shrink();
        return Column(
          children: [
            const SizedBox(height: 6),
            _SessionMenuAction(
              key: const Key('environment_menu_item'),
              icon: _environmentContributionIcon(contribution),
              label: _environmentMenuTitle(context),
              onTap: () {
                _environmentContribution = contribution;
                _navigateTo(_SessionHistoryView.environment);
              },
            ),
          ],
        );
      },
    );
  }

  Future<bool> _handleBack() async {
    if (_view == _SessionHistoryView.menu) return true;
    setState(() {
      _view = _viewStack.isNotEmpty
          ? _viewStack.removeLast()
          : _SessionHistoryView.menu;
    });
    return false;
  }

  void _openProject(_ChatProject project) {
    _selectedProjectId = project.id;
    _navigateTo(_SessionHistoryView.projectDetail);
  }

  Future<void> _showCreateProjectDialog() async {
    final appView = View.of(context);
    widget.onSessionRenameEditingChanged(true);
    _NewProjectDraft? draft;
    try {
      draft = await showModalBottomSheet<_NewProjectDraft>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        enableDrag: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.22),
        builder: (_) => const _CreateProjectSheet(),
      );
      await _waitForKeyboardToHide(appView);
    } finally {
      if (mounted) widget.onSessionRenameEditingChanged(false);
    }
    if (!mounted || draft == null) return;
    widget.onProjectCreated(draft);
  }

  Widget _buildProjectsPage(BuildContext context) {
    final sessionCounts = <String, int>{};
    for (final projectId in widget.projectSessionIds.values) {
      sessionCounts[projectId] = (sessionCounts[projectId] ?? 0) + 1;
    }
    return _ProjectsPage(
      projects: widget.projects,
      sessionCounts: sessionCounts,
      onMenu: () => unawaited(_handleBack()),
      onAdd: () => unawaited(_showCreateProjectDialog()),
      onProjectTap: _openProject,
      onProjectPinToggle: widget.onProjectPinToggle,
      onProjectSettings: widget.onProjectSettings,
      onProjectDelete: widget.onProjectDelete,
    );
  }

  Widget _buildProjectDetailPage(BuildContext context) {
    _ChatProject? selectedProject;
    for (final project in widget.projects) {
      if (project.id == _selectedProjectId) {
        selectedProject = project;
        break;
      }
    }
    if (selectedProject == null) return _buildProjectsPage(context);

    final project = selectedProject;
    final projectSessions = widget.sessions
        .where((session) => widget.projectSessionIds[session.id] == project.id)
        .toList(growable: false);
    return _ProjectDetailPage(
      project: project,
      sessions: projectSessions,
      onBack: () => unawaited(_handleBack()),
      onSessionTap: widget.onSessionSelected,
      onSessionPinToggle: widget.onSessionPinToggle,
      onSessionRename: (session) =>
          unawaited(_showRenameSessionDialog(session)),
      onSessionRemove: widget.onProjectSessionRemove,
      onSessionDelete: widget.onSessionDelete,
      onStartChat: (message, attachments, pinnedSkillNames) =>
          widget.onProjectChatStarted(project.id, message),
      agentId: widget.activeAgent.id,
    );
  }

  bool _matchesSearch(ChatSession session, String normalizedQuery) {
    if (normalizedQuery.isEmpty) return true;
    final searchableText = [
      _sessionHistoryDisplayTitle(session),
      _sessionHistoryPreview(session),
      for (final message in session.messages)
        _sanitizeA2AProtocolText(message.content),
      for (final message in session.messages)
        for (final attachment in message.attachments) attachment.name,
    ].join(' ').toLowerCase();
    return searchableText.contains(normalizedQuery);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final normalizedQuery = _searchQuery.toLowerCase();
    final sortedSessions = [...widget.sessions]
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    final visibleSessions = sortedSessions
        .where((session) => _matchesSearch(session, normalizedQuery))
        .toList();
    final hasSearchResults = visibleSessions.isNotEmpty;
    final hasAnyContent = widget.sessions.isNotEmpty;

    return PopScope(
      canPop: _view == _SessionHistoryView.menu,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _view != _SessionHistoryView.menu) {
          setState(() {
            _view = _viewStack.isNotEmpty
                ? _viewStack.removeLast()
                : _SessionHistoryView.menu;
          });
        }
      },
      child: Material(
        key: const Key('session_history_sheet'),
        color: _appSurfaceColor,
        child: SafeArea(
          child: _buildCurrentView(
            context: context,
            strings: strings,
            visibleSessions: visibleSessions,
            hasSearchResults: hasSearchResults,
            hasAnyContent: hasAnyContent,
          ),
        ),
      ),
    );
  }

  Widget _buildSessionMenuHeader(BuildContext context, AppStrings strings) {
    final headerActions = Container(
      key: const Key('session_header_action_group'),
      width: 94,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.94),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.055),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.transparent,
          child: Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: strings.searchHistoryTooltip,
                  child: InkWell(
                    key: const Key('session_history_search_button'),
                    onTap: _toggleSearch,
                    customBorder: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(24),
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.search_rounded,
                        color: _sessionMenuText,
                        size: 23,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Tooltip(
                  message: strings.settingsTooltip,
                  child: InkWell(
                    key: const Key('settings_menu_button'),
                    onTap: widget.onSettingsSelected,
                    customBorder: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(24),
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.settings_outlined,
                        color: _sessionMenuText,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final header = SizedBox(
      height: 88,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        reverseDuration: const Duration(milliseconds: 210),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.topRight,
          children: [...previousChildren, ?currentChild],
        ),
        transitionBuilder: (child, animation) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          if (child.key == const ValueKey('session_search_header')) {
            return FadeTransition(
              opacity: curvedAnimation,
              child: SizeTransition(
                axis: Axis.horizontal,
                axisAlignment: 1,
                sizeFactor: curvedAnimation,
                child: child,
              ),
            );
          }
          return FadeTransition(opacity: curvedAnimation, child: child);
        },
        child: _isSearching
            ? Padding(
                key: const ValueKey('session_search_header'),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
                child: _buildSessionSearchBar(context, strings),
              )
            : Padding(
                key: const ValueKey('session_title_header'),
                padding: const EdgeInsets.fromLTRB(24, 24, 20, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.activeAgent.label(
                          _AppLanguageScope.languageOf(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _sessionMenuText,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    headerActions,
                  ],
                ),
              ),
      ),
    );

    return SizedBox(
      key: const Key('session_history_frosted_header'),
      child: SizedBox(
        key: const Key('session_history_frosted_header_surface'),
        child: header,
      ),
    );
  }

  Widget _buildSessionSearchBar(BuildContext context, AppStrings strings) {
    final surfaceDecoration = BoxDecoration(
      color: Colors.white.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: 0.94), width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 18,
          offset: const Offset(0, 5),
        ),
      ],
    );

    return Row(
      key: const Key('session_history_search_bar'),
      children: [
        Expanded(
          child: Container(
            key: const Key('session_history_search_input_surface'),
            height: 46,
            decoration: surfaceDecoration,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Material(
                color: Colors.transparent,
                child: TextField(
                  key: const Key('session_history_search_field'),
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  textInputAction: TextInputAction.search,
                  cursorColor: _sessionMenuText,
                  style: const TextStyle(
                    color: _sessionMenuText,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                  decoration: InputDecoration(
                    hintText: strings.searchHistoryHint,
                    hintStyle: TextStyle(
                      color: _sessionMenuMuted.withValues(alpha: 0.62),
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 2),
                      child: Icon(
                        Icons.search_rounded,
                        color: _sessionMenuText,
                        size: 22,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 46,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(0, 13, 16, 12),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IgnorePointer(
          ignoring: !_showSearchClose,
          child: AnimatedOpacity(
            opacity: _showSearchClose ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: AnimatedScale(
              scale: _showSearchClose ? 1 : 0.82,
              duration: const Duration(milliseconds: 190),
              curve: Curves.easeOutBack,
              child: Container(
                key: const Key('session_history_search_close_surface'),
                width: 46,
                height: 46,
                decoration: surfaceDecoration,
                child: ClipOval(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: const Key('session_history_search_close'),
                      onTap: _toggleSearch,
                      child: const Center(
                        child: Icon(
                          Icons.close_rounded,
                          color: _sessionMenuText,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionMenuNavigation(BuildContext context, AppStrings strings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
      child: Column(
        children: [
          _SessionMenuAction(
            key: const Key('files_menu_item'),
            icon: Icons.folder_open_rounded,
            label: strings.filesTitle,
            selected: widget.primaryView == _ChatPrimaryView.files,
            selectedKey: const Key('files_menu_selected'),
            onTap: widget.onFilesSelected,
          ),
          _buildRepoWorkbenchMenuAction(),
          _buildEnvironmentMenuAction(),
          _SessionMenuAction(
            key: const Key('skills_menu_item'),
            icon: Icons.extension_outlined,
            label: strings.skillsTitle,
            selected: widget.primaryView == _ChatPrimaryView.skills,
            selectedKey: const Key('skills_menu_selected'),
            onTap: () {
              _skillsInitialTab = _SkillsInitialTab.installed;
              widget.onSkillsSelected();
            },
          ),
          _SessionMenuAction(
            key: const Key('projects_menu_item'),
            icon: Icons.folder_copy_outlined,
            label: _projectCopy(context, english: 'Projects', chinese: '项目'),
            selected:
                widget.primaryView == _ChatPrimaryView.projects ||
                widget.primaryView == _ChatPrimaryView.projectDetail,
            selectedKey: const Key('projects_menu_selected'),
            onTap: widget.onProjectsSelected,
          ),
        ],
      ),
    );
  }

  void _handleEngineConfigChanged() {
    _filesClientFuture = null;
    _skillsClientFuture = null;
    widget.onEngineConfigChanged();
  }

  Widget _buildCurrentView({
    required BuildContext context,
    required AppStrings strings,
    required List<ChatSession> visibleSessions,
    required bool hasSearchResults,
    required bool hasAnyContent,
  }) {
    switch (_view) {
      case _SessionHistoryView.projects:
        return _buildProjectsPage(context);
      case _SessionHistoryView.projectDetail:
        return _buildProjectDetailPage(context);
      case _SessionHistoryView.files:
        _filesClientFuture ??= widget.createFilesClientFuture();
        return _FilesPage(
          clientFuture: _filesClientFuture!,
          agentId: widget.activeAgent.id,
          onBack: _handleBack,
        );
      case _SessionHistoryView.repositories:
        _repoWorkbenchClientFuture ??= widget.createScenariosClientFuture();
        return _RepoWorkbenchPage(
          clientFuture: _repoWorkbenchClientFuture!,
          agentId: widget.activeAgent.id,
          contribution:
              _repoWorkbenchContribution ?? _fallbackRepoWorkbenchContribution,
          onBack: _handleBack,
        );
      case _SessionHistoryView.environment:
        _scenariosClientFuture ??= widget.createScenariosClientFuture();
        return _DevelopmentEnvironmentPage(
          clientFuture: _scenariosClientFuture!,
          agentId: widget.activeAgent.id,
          contribution:
              _environmentContribution ?? _fallbackEnvironmentContribution,
          onBack: _handleBack,
        );
      case _SessionHistoryView.skills:
        _skillsClientFuture ??= widget.createSkillsClientFuture();
        return _SkillsPage(
          clientFuture: _skillsClientFuture!,
          agentId: widget.activeAgent.id,
          initialTab: _skillsInitialTab,
          onPendingEvolutionChanged: widget.onPendingEvolutionChanged,
          onBack: _handleBack,
        );
      case _SessionHistoryView.scenarios:
        _scenariosClientFuture ??= widget.createScenariosClientFuture();
        return ScenariosPanel(
          clientFuture: _scenariosClientFuture!,
          activeScenarioId: widget.activeScenarioId,
          gitSettings: widget.gitSettings,
          onScenarioApplied: widget.onScenarioApplied,
          onGitSettingsChanged: widget.onGitSettingsChanged,
          onGitSettingsCleared: widget.onGitSettingsCleared,
          onBack: _handleBack,
        );
      case _SessionHistoryView.settings:
        return _SettingsPage(
          key: ValueKey('settings_section_$_settingsInitialSection'),
          initialConfig: widget.config,
          language: _AppLanguageScope.languageOf(context),
          onConfigChanged: widget.onConfigChanged,
          onLanguageChanged: widget.onLanguageChanged,
          onEngineConfigChanged: _handleEngineConfigChanged,
          createScenariosClientFuture: widget.createScenariosClientFuture,
          createNearbyClientFuture: widget.createNearbyClientFuture,
          activeScenarioId: widget.activeScenarioId,
          gitSettings: widget.gitSettings,
          onScenarioApplied: widget.onScenarioApplied,
          onGitSettingsChanged: widget.onGitSettingsChanged,
          onGitSettingsCleared: widget.onGitSettingsCleared,
          updateService: widget.updateService,
          feedbackService: widget.feedbackService,
          onCheckForUpdates: widget.onCheckForUpdates,
          onNearbyStart: widget.onNearbyStart,
          onNearbyStop: widget.onNearbyStop,
          onNearbyInvite: widget.onNearbyInvite,
          onNearbyScan: widget.onNearbyScan,
          onNearbyDeletePeer: widget.onNearbyDeletePeer,
          getNearbyPairingDiagnostic: widget.getNearbyPairingDiagnostic,
          onBack: () async {
            _settingsInitialSection = _SettingsSection.menu;
            return _handleBack();
          },
          initialSection: _settingsInitialSection,
        );
      case _SessionHistoryView.feedback:
        return _FeedbackPage(
          updateService: widget.updateService,
          feedbackService: widget.feedbackService,
          onBack: _handleBack,
          onOpenContact: () => _navigateTo(_SessionHistoryView.contact),
        );
      case _SessionHistoryView.contact:
        return _ContactPage(onBack: _handleBack);
      case _SessionHistoryView.menu:
        return Stack(
          children: [
            Positioned.fill(
              child: ShaderMask(
                key: const Key('session_history_scroll_fade'),
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) {
                  final height = math.max(bounds.height, 1.0);
                  final earlyStop = (60 / height).clamp(0.0, 1.0).toDouble();
                  final middleStop = (96 / height).clamp(0.0, 1.0).toDouble();
                  final endStop = (160 / height)
                      .clamp(middleStop, 1.0)
                      .toDouble();
                  return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, earlyStop, middleStop, endStop],
                    colors: const [
                      Color(0x08FFFFFF),
                      Color(0x24FFFFFF),
                      Color(0x98FFFFFF),
                      Colors.white,
                    ],
                  ).createShader(bounds);
                },
                child: ListView(
                  key: const Key('session_history_list'),
                  padding: EdgeInsets.fromLTRB(
                    0,
                    92,
                    0,
                    _isSearching ? 20 : 104,
                  ),
                  children: [
                    if (!_isSearching)
                      _buildSessionMenuNavigation(context, strings),
                    if (!hasAnyContent && !_isSearching)
                      const SizedBox(height: 260, child: _EmptySessionHistory())
                    else if (_isSearching && !hasSearchResults)
                      const SizedBox(
                        height: 260,
                        child: _EmptySessionSearchResults(),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Column(
                          children: [
                            if (!_isSearching)
                              if (visibleSessions.any(
                                (session) => session.isPinned,
                              ))
                                _SessionSectionHeader(
                                  label: strings.pinned,
                                  fontWeight: FontWeight.w600,
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    4,
                                    10,
                                    10,
                                  ),
                                )
                              else
                                _SessionSectionHeader(
                                  label: strings.recent,
                                  fontWeight: FontWeight.w600,
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    4,
                                    10,
                                    10,
                                  ),
                                ),
                            for (final session in visibleSessions) ...[
                              if (!_isSearching &&
                                  session.isPinned == false &&
                                  visibleSessions.any(
                                    (item) => item.isPinned,
                                  ) &&
                                  visibleSessions.indexOf(session) ==
                                      visibleSessions.indexWhere(
                                        (item) => !item.isPinned,
                                      ))
                                _SessionSectionHeader(
                                  label: strings.recent,
                                  fontWeight: FontWeight.w600,
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    10,
                                    10,
                                    10,
                                  ),
                                ),
                              _SessionHistoryTile(
                                session: session,
                                runState: widget.sessionRuns[session.id],
                                hasA2AUnread: widget.a2aUnreadSessionIds
                                    .contains(session.id),
                                isActive: session.id == widget.activeSessionId,
                                onTap: () =>
                                    widget.onSessionSelected(session.id),
                                onLongPress: () {
                                  unawaited(
                                    _showSessionActions(context, session),
                                  );
                                },
                              ),
                              const SizedBox(height: 4),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 160,
              child: IgnorePointer(
                key: const Key('session_history_progressive_blur'),
                child: Column(
                  children: [
                    for (final band in const [
                      (height: 34.0, sigma: 34.0),
                      (height: 28.0, sigma: 24.0),
                      (height: 28.0, sigma: 18.0),
                      (height: 26.0, sigma: 12.0),
                      (height: 24.0, sigma: 7.0),
                      (height: 20.0, sigma: 3.0),
                    ])
                      SizedBox(
                        height: band.height,
                        child: ClipRect(
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(
                              sigmaX: band.sigma,
                              sigmaY: band.sigma,
                            ),
                            child: ColoredBox(
                              color: _appSurfaceColor.withValues(alpha: 0.01),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildSessionMenuHeader(context, strings),
            ),
            if (!_isSearching)
              Positioned(
                right: 20,
                bottom: 20,
                child: FloatingActionButton.extended(
                  key: const Key('new_session_button'),
                  onPressed: widget.onNewSession,
                  backgroundColor: const Color(0xFF333333),
                  foregroundColor: const Color(0xFFFFFFFF),
                  elevation: 0,
                  shape: const StadiumBorder(),
                  icon: const Icon(Icons.add_comment_rounded),
                  label: Text(strings.newChat),
                ),
              ),
          ],
        );
    }
  }

  Future<void> _showSessionActions(
    BuildContext context,
    ChatSession session,
  ) async {
    final strings = AppStrings.of(context);
    final isTerminalSession = session.id.startsWith('terminal-');
    final previewEntries = isTerminalSession
        ? <String>[strings.terminalSessionPreview]
        : _sessionHistoryExpandedPreview(context, session);
    ModalRoute<dynamic>? bottomSheetRoute;
    final action = await showModalBottomSheet<_SessionAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        bottomSheetRoute ??= ModalRoute.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: _appSurfaceColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: _appSurfaceBorderColor),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: Key('session_preview_action_${session.id}'),
                    onTap: () =>
                        Navigator.of(sheetContext).pop(_SessionAction.open),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 14, 20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  strings.latestMessage,
                                  style: const TextStyle(
                                    color: _sessionMenuMuted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  _sessionHistoryDisplayTitle(session),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _sessionMenuText,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: 72,
                                  ),
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (
                                          var index = 0;
                                          index < previewEntries.length;
                                          index++
                                        ) ...[
                                          if (index > 0)
                                            const SizedBox(height: 5),
                                          Text(
                                            previewEntries[index],
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF5F5F5F),
                                              fontSize: 14,
                                              height: 1.45,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Color(0xFF989898),
                            size: 17,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Material(
                  color: _appSurfaceColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: _appSurfaceBorderColor),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SessionSheetAction(
                          key: Key('session_pin_action_${session.id}'),
                          icon: Icons.push_pin_outlined,
                          showIconSlash: session.isPinned,
                          label: session.isPinned
                              ? strings.unpinChat
                              : strings.pinChat,
                          onTap: () => Navigator.of(
                            sheetContext,
                          ).pop(_SessionAction.pinToggle),
                        ),
                        const SizedBox(height: 2),
                        _SessionSheetAction(
                          key: Key('session_rename_action_${session.id}'),
                          icon: Icons.edit_outlined,
                          label: strings.renameChat,
                          onTap: () => Navigator.of(
                            sheetContext,
                          ).pop(_SessionAction.rename),
                        ),
                        const SizedBox(height: 2),
                        _SessionSheetAction(
                          key: Key('session_delete_action_${session.id}'),
                          icon: Icons.delete_outline_rounded,
                          label: strings.deleteChat,
                          isDestructive: true,
                          onTap: () => Navigator.of(
                            sheetContext,
                          ).pop(_SessionAction.delete),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _SessionAction.open:
        // Opening a chat removes the history panel that owns this route, so
        // wait until the action sheet is fully detached first.
        await bottomSheetRoute?.completed;
        if (!mounted) return;
        widget.onSessionSelected(session.id);
        return;
      case _SessionAction.pinToggle:
        widget.onSessionPinToggle(session.id);
        return;
      case _SessionAction.rename:
        // Keep the history panel mounted and let the two route transitions
        // overlap, avoiding a visible pause before the rename field appears.
        await _showRenameSessionDialog(session);
        return;
      case _SessionAction.delete:
        widget.onSessionDelete(session.id);
        return;
    }
  }

  Future<void> _showRenameSessionDialog(ChatSession session) async {
    final strings = AppStrings.of(context);
    final appView = View.of(context);
    final controller = TextEditingController(
      text: _sessionHistoryDisplayTitle(session),
    );
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    widget.onSessionRenameEditingChanged(true);
    ModalRoute<dynamic>? renameSheetRoute;
    String? renamedTitle;
    try {
      renamedTitle = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.22),
        isScrollControlled: true,
        sheetAnimationStyle: AnimationStyle.noAnimation,
        builder: (sheetContext) {
          renameSheetRoute ??= ModalRoute.of(sheetContext);
          var canSave = controller.text.trim().isNotEmpty;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              void closeSheet([String? result]) {
                FocusScope.of(sheetContext).unfocus();
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop(result);
                }
              }

              void submit() {
                final title = controller.text.trim();
                if (title.isNotEmpty) closeSheet(title);
              }

              final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
              return SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + keyboardInset),
                  child: Material(
                    color: _appSurfaceColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: const BorderSide(color: _appSurfaceBorderColor),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  strings.renameChatTitle,
                                  style: const TextStyle(
                                    color: _sessionMenuText,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: strings.cancel,
                                onPressed: closeSheet,
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFFEDEEF0),
                                  foregroundColor: const Color(0xFF525252),
                                ),
                                icon: const Icon(Icons.close_rounded, size: 20),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            key: Key('session_rename_field_${session.id}'),
                            controller: controller,
                            autofocus: true,
                            maxLength: 80,
                            textInputAction: TextInputAction.done,
                            style: const TextStyle(
                              color: _sessionMenuText,
                              fontSize: 16,
                            ),
                            decoration: InputDecoration(
                              hintText: strings.renameChatHint,
                              hintStyle: const TextStyle(
                                color: Color(0xFF9CA3AF),
                              ),
                              counterText: '',
                              filled: true,
                              fillColor: _appSurfaceColor,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 15,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: const BorderSide(
                                  color: _appSurfaceBorderColor,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: const BorderSide(
                                  color: Color(0xFF9CA3AF),
                                  width: 1.2,
                                ),
                              ),
                            ),
                            onChanged: (value) {
                              final nextCanSave = value.trim().isNotEmpty;
                              if (nextCanSave != canSave) {
                                setDialogState(() => canSave = nextCanSave);
                              }
                            },
                            onSubmitted: (_) => submit(),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: OutlinedButton(
                                    onPressed: closeSheet,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _sessionMenuText,
                                      side: const BorderSide(
                                        color: _appSurfaceBorderColor,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: Text(strings.cancel),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: FilledButton(
                                    key: Key(
                                      'confirm_rename_session_${session.id}',
                                    ),
                                    onPressed: canSave ? submit : null,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF111827),
                                      disabledBackgroundColor: const Color(
                                        0xFFD1D5DB,
                                      ),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: Text(strings.save),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
      await renameSheetRoute?.completed;
      await _waitForKeyboardToHide(appView);
    } finally {
      controller.dispose();
      if (mounted) widget.onSessionRenameEditingChanged(false);
    }
    if (!mounted || renamedTitle == null) return;
    widget.onSessionRename(session.id, renamedTitle);
  }

  Future<void> _waitForKeyboardToHide(ui.FlutterView view) async {
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    while (view.viewInsets.bottom > 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }
}

enum _SessionHistoryView {
  menu,
  files,
  repositories,
  environment,
  scenarios,
  skills,
  projects,
  projectDetail,
  settings,
  feedback,
  contact,
}

enum _SettingsSection {
  menu,
  agent,
  modelManagement,
  modelEditor,
  feedback,
  contact,
  licenses,
  configuration,
  channels,
  nearby,
  scenarios,
  engines,
  about,
}

class _AboutPage extends StatelessWidget {
  const _AboutPage({
    required this.updateService,
    required this.onCheckForUpdates,
    required this.onOpenContact,
    required this.onOpenLicenses,
    this.embedded = false,
  });

  final DemoUpdateService updateService;
  final VoidCallback onCheckForUpdates;
  final VoidCallback onOpenContact;
  final VoidCallback onOpenLicenses;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final body = _buildBody(strings);
    if (embedded) return body;
    return Scaffold(
      backgroundColor: _configPageBackground,
      appBar: AppBar(
        title: Text(strings.aboutTitle),
        backgroundColor: _configPageBackground,
        foregroundColor: _configTextPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: body,
    );
  }

  Widget _buildBody(AppStrings strings) {
    return FutureBuilder<DemoAppVersion>(
      future: updateService.currentVersion(),
      builder: (context, snapshot) {
        final version = snapshot.data?.display ?? strings.versionLoading;
        return ListView(
          key: const Key('about_page_list'),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
          children: [
            Center(
              child: Text(
                version,
                key: const Key('about_current_version'),
                style: const TextStyle(
                  color: _configTextSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _SettingsGroupCard(
              children: [
                _SettingsActionRow(
                  key: const Key('about_check_update_button'),
                  icon: Icons.system_update_alt_rounded,
                  title: strings.checkForUpdates,
                  onTap: onCheckForUpdates,
                ),
                _SettingsActionRow(
                  key: const Key('about_contact_button'),
                  icon: Icons.contact_support_outlined,
                  title: strings.contactUs,
                  onTap: onOpenContact,
                ),
                _SettingsActionRow(
                  key: const Key('open_source_licenses_button'),
                  icon: Icons.article_outlined,
                  title: strings.openSourceLicensesTitle,
                  onTap: onOpenLicenses,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SettingsLicensesPage extends StatefulWidget {
  const _SettingsLicensesPage();

  @override
  State<_SettingsLicensesPage> createState() => _SettingsLicensesPageState();
}

class _SettingsLicensesPageState extends State<_SettingsLicensesPage> {
  late final Future<List<_SettingsLicenseRecord>> _licenses = _loadLicenses();

  Future<List<_SettingsLicenseRecord>> _loadLicenses() async {
    final displayTitles = <String, String>{};
    final textsByTitle = <String, Set<String>>{};
    await for (final entry in LicenseRegistry.licenses) {
      final text = entry.paragraphs
          .map((paragraph) => paragraph.text.trim())
          .where((paragraph) => paragraph.isNotEmpty)
          .join('\n\n');
      final packages = entry.packages
          .map((package) => package.trim())
          .where((package) => package.isNotEmpty)
          .toSet();
      if (packages.isEmpty) packages.add('Other');
      for (final package in packages) {
        final key = package.toLowerCase();
        displayTitles.putIfAbsent(key, () => package);
        if (text.isNotEmpty) {
          textsByTitle.putIfAbsent(key, () => <String>{}).add(text);
        }
      }
    }
    final records = [
      for (final entry in displayTitles.entries)
        _SettingsLicenseRecord(
          title: entry.value,
          text: (textsByTitle[entry.key] ?? const <String>{}).join(
            '\n\n────────\n\n',
          ),
        ),
    ];
    records.sort(
      (left, right) =>
          left.title.toLowerCase().compareTo(right.title.toLowerCase()),
    );
    return records;
  }

  @override
  Widget build(BuildContext context) {
    final chinese =
        _AppLanguageScope.languageOf(context) == AppLanguage.chinese;
    return FutureBuilder<List<_SettingsLicenseRecord>>(
      future: _licenses,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: _configTextPrimary),
          );
        }
        final records = snapshot.data!;
        if (records.isEmpty) {
          return Center(
            child: Text(
              chinese ? '暂无许可信息' : 'No license information',
              style: const TextStyle(color: _configTextSecondary),
            ),
          );
        }
        return ListView.separated(
          key: const Key('settings_licenses_page'),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
          itemCount: records.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final record = records[index];
            return Material(
              color: _configSurface,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                iconColor: _configTextSecondary,
                collapsedIconColor: _configTextTertiary,
                shape: const Border(),
                collapsedShape: const Border(),
                title: Text(
                  record.title,
                  style: const TextStyle(
                    color: _configTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SelectableText(
                      record.text,
                      style: const TextStyle(
                        color: _configTextSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SettingsLicenseRecord {
  const _SettingsLicenseRecord({required this.title, required this.text});

  final String title;
  final String text;
}

class _SettingsGroupCard extends StatelessWidget {
  const _SettingsGroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _configSurface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              const Padding(
                padding: EdgeInsets.only(left: 54),
                child: Divider(height: 1, color: _configBorderFaint),
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingsGroupTitle extends StatelessWidget {
  const _SettingsGroupTitle({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _configTextSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: _configTextPrimary, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _configTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: _configTextTertiary,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutActionButton extends StatelessWidget {
  const _AboutActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.filled = false,
    this.loading = false,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final bool filled;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final foreground = !enabled
        ? _configTextTertiary
        : filled
        ? _configSurface
        : _configTextPrimary;
    final background = !enabled
        ? _configBorderFaint
        : filled
        ? _configTextPrimary
        : _configSurface;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        highlightColor: _configSelectedSurface,
        hoverColor: _configSelectedSurface,
        splashColor: _configBorder.withValues(alpha: 0.18),
        onTap: enabled ? onPressed : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: !enabled
                  ? _configBorderFaint
                  : filled
                  ? _configTextPrimary
                  : _configBorder,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              else
                Icon(icon, color: foreground, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    super.key,
    required this.initialConfig,
    required this.language,
    required this.onConfigChanged,
    required this.onLanguageChanged,
    required this.onEngineConfigChanged,
    required this.createScenariosClientFuture,
    required this.createNearbyClientFuture,
    required this.activeScenarioId,
    required this.gitSettings,
    required this.onScenarioApplied,
    required this.onGitSettingsChanged,
    required this.onGitSettingsCleared,
    required this.updateService,
    required this.feedbackService,
    required this.onCheckForUpdates,
    required this.onNearbyStart,
    required this.onNearbyStop,
    required this.onNearbyInvite,
    required this.onNearbyScan,
    required this.onNearbyDeletePeer,
    required this.getNearbyPairingDiagnostic,
    required this.onBack,
    this.onClose,
    this.initialSection = _SettingsSection.menu,
    this.initiallyFocusAgentContext = false,
  });

  final LlmConfigState initialConfig;
  final AppLanguage language;
  final ValueChanged<LlmConfigState> onConfigChanged;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final VoidCallback onEngineConfigChanged;
  final Future<NapaxiChatClient> Function() createScenariosClientFuture;
  final Future<NapaxiChatClient> Function() createNearbyClientFuture;
  final String activeScenarioId;
  final DemoGitSettings gitSettings;
  final Future<void> Function(String scenarioId) onScenarioApplied;
  final Future<void> Function(DemoGitSettings settings) onGitSettingsChanged;
  final Future<void> Function() onGitSettingsCleared;
  final DemoUpdateService updateService;
  final DemoFeedbackService feedbackService;
  final VoidCallback onCheckForUpdates;
  final Future<void> Function() onNearbyStart;
  final Future<void> Function() onNearbyStop;
  final Future<void> Function() onNearbyInvite;
  final Future<void> Function() onNearbyScan;
  final Future<void> Function(sdk.A2APeer peer) onNearbyDeletePeer;
  final Future<String?> Function() getNearbyPairingDiagnostic;
  final Future<bool> Function() onBack;
  final VoidCallback? onClose;
  final _SettingsSection initialSection;
  final bool initiallyFocusAgentContext;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage>
    with SingleTickerProviderStateMixin {
  static const double _backFlingVelocity = 700;
  late _SettingsSection _section;
  late LlmConfigState _config;
  late AppLanguage _language;
  late bool _focusAgentContext;
  late final AnimationController _sectionController;
  final List<_SettingsSection> _sectionStack = [];
  final GlobalKey<_LlmModelProfilePageState> _modelEditorKey = GlobalKey();
  final GlobalKey<_FeedbackPageState> _feedbackPageKey = GlobalKey();
  LlmModelProfile? _editingProfile;
  ModelCapability? _editingCapability;
  bool _editingNewModel = false;
  Future<NapaxiChatClient>? _scenariosClientFuture;
  int? _backSwipePointer;
  Offset? _backSwipeOrigin;
  VelocityTracker? _backSwipeVelocityTracker;
  bool _backSwipeActive = false;
  bool _backTransitionInFlight = false;
  final Map<_SettingsSection, bool> _sectionScrollAtTop = {};

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
    _config = widget.initialConfig;
    _language = widget.language;
    _focusAgentContext = widget.initiallyFocusAgentContext;
    if (_section == _SettingsSection.engines && !_showsEngineSettings) {
      _section = _SettingsSection.menu;
    }
    if (_section != _SettingsSection.menu) {
      _sectionStack.add(_SettingsSection.menu);
    }
    _sectionScrollAtTop[_section] = true;
    _sectionController = AnimationController(
      vsync: this,
      value: _section == _SettingsSection.menu ? 0 : 1,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 240),
    );
  }

  @override
  void didUpdateWidget(_SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialConfig != widget.initialConfig) {
      _config = widget.initialConfig;
    }
    if (oldWidget.language != widget.language) {
      _language = widget.language;
    }
    if (!oldWidget.initiallyFocusAgentContext &&
        widget.initiallyFocusAgentContext) {
      _focusAgentContext = true;
    }
    if (_section == _SettingsSection.engines && !_showsEngineSettings) {
      _section = _SettingsSection.menu;
      _sectionStack.clear();
      _sectionScrollAtTop[_SettingsSection.menu] = true;
      _sectionController.value = 0;
    }
  }

  @override
  void dispose() {
    _sectionController.dispose();
    super.dispose();
  }

  bool get _showsEngineSettings =>
      _normalizeDemoScenarioId(widget.activeScenarioId) ==
      _mobileDevelopmentScenarioId;

  bool get isMenu => _section == _SettingsSection.menu;

  bool get canPullSheetDownFromCurrentContent =>
      _sectionScrollAtTop[_section] ?? true;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.forLanguage(_language);
    final backSection = _sectionStack.isEmpty
        ? _SettingsSection.menu
        : _sectionStack.last;
    final backPage = _buildSectionPage(backSection, strings);
    final detailPage = isMenu ? null : _buildSectionPage(_section, strings);
    return _AppLanguageScope(
      language: _language,
      strings: strings,
      child: Listener(
        key: const Key('settings_subpage_gesture_surface'),
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handleBackSwipeDown,
        onPointerMove: _handleBackSwipeMove,
        onPointerUp: _handleBackSwipeEnd,
        onPointerCancel: _handleBackSwipeCancel,
        child: AnimatedBuilder(
          animation: _sectionController,
          builder: (context, _) {
            final progress = _sectionController.value;
            return Stack(
              fit: StackFit.expand,
              children: [
                Transform.translate(
                  key: const Key('settings_menu_back_transition'),
                  offset: Offset(
                    -MediaQuery.sizeOf(context).width * 0.18 * progress,
                    0,
                  ),
                  child: Opacity(
                    opacity: 1 - (0.16 * progress),
                    child: IgnorePointer(
                      ignoring: progress > 0,
                      child: backPage,
                    ),
                  ),
                ),
                if (detailPage != null)
                  Transform.translate(
                    key: const Key('settings_detail_back_transition'),
                    offset: Offset(
                      MediaQuery.sizeOf(context).width * (1 - progress),
                      0,
                    ),
                    child: PhysicalModel(
                      color: _configPageBackground,
                      elevation: 16 * (1 - progress),
                      shadowColor: Colors.black.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(24 * (1 - progress)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: detailPage,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionPage(_SettingsSection section, AppStrings strings) {
    final body = _buildBody(strings, section);
    return KeyedSubtree(
      key: ValueKey<_SettingsSection>(section),
      child: Scaffold(
        backgroundColor: _configPageBackground,
        appBar: AppBar(
          title: Text(_sectionTitle(strings, section)),
          backgroundColor: _configPageBackground,
          foregroundColor: _configTextPrimary,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: section == _SettingsSection.menu
              ? widget.onClose == null
                    ? BackButton(onPressed: _handleBack)
                    : null
              : BackButton(onPressed: _handleBack),
          actions: [
            if (section == _SettingsSection.menu && widget.onClose != null)
              IconButton(
                key: const Key('settings_bottom_sheet_close_button'),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            if (section == _SettingsSection.modelManagement)
              IconButton(
                key: const Key('settings_model_management_add_button'),
                tooltip: strings.addModel,
                onPressed: _addModel,
                icon: const Icon(Icons.add_rounded),
              ),
            if (section == _SettingsSection.modelEditor)
              TextButton(
                key: const Key('save_model_button'),
                onPressed: () => _modelEditorKey.currentState?.save(),
                style: TextButton.styleFrom(
                  foregroundColor: _configTextPrimary,
                ),
                child: Text(strings.save),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: NotificationListener<ScrollNotification>(
          onNotification: (notification) =>
              _handleSectionScrollNotification(section, notification),
          child: body,
        ),
      ),
    );
  }

  bool _handleSectionScrollNotification(
    _SettingsSection section,
    ScrollNotification notification,
  ) {
    if (notification.metrics.axis != Axis.vertical) return false;
    _sectionScrollAtTop[section] =
        notification.metrics.pixels <=
        notification.metrics.minScrollExtent + 0.5;
    return false;
  }

  String _sectionTitle(AppStrings strings, _SettingsSection section) {
    return switch (section) {
      _SettingsSection.menu => strings.settingsTitle,
      _SettingsSection.agent =>
        _language == AppLanguage.chinese ? '智能体' : 'Agent',
      _SettingsSection.modelManagement =>
        _language == AppLanguage.chinese ? '模型管理' : 'Model management',
      _SettingsSection.modelEditor =>
        _editingNewModel ? strings.addModel : strings.editModel,
      _SettingsSection.feedback => strings.feedbackTitle,
      _SettingsSection.contact => strings.contactUs,
      _SettingsSection.licenses => strings.openSourceLicensesTitle,
      _SettingsSection.configuration => strings.llmConfigurationTitle,
      _SettingsSection.channels => _settingsChannelsTitle(context),
      _SettingsSection.nearby =>
        _language == AppLanguage.chinese ? '附近' : 'Nearby',
      _SettingsSection.scenarios => strings.scenariosTitle,
      _SettingsSection.engines => strings.engineSettingsTitle,
      _SettingsSection.about => strings.aboutTitle,
    };
  }

  void _handleConfigChanged(LlmConfigState config) {
    setState(() => _config = config);
    widget.onConfigChanged(config);
  }

  void _handleLanguageChanged(AppLanguage language) {
    if (_language == language) return;
    setState(() => _language = language);
    widget.onLanguageChanged(language);
  }

  void _selectModelProfile(ModelCapability capability, String profileId) {
    final profile = _config.profileById(profileId);
    if (profile == null || !profile.supports(capability)) return;
    final selectedByCapability = Map<ModelCapability, String>.of(
      _config.selectedProfileIdByCapability,
    );
    String? selectedProfileId = _config.selectedProfileId;
    if (capability == ModelCapability.chat) {
      selectedProfileId = profileId;
    } else {
      selectedByCapability[capability] = profileId;
    }
    _handleConfigChanged(
      LlmConfigState(
        profiles: _config.profiles,
        selectedProfileId: selectedProfileId,
        selectedProfileIdByCapability: Map.unmodifiable(selectedByCapability),
        systemPrompt: _config.systemPrompt,
        maxToolIterations: _config.maxToolIterations,
        contextEngine: _config.contextEngine,
      ),
    );
  }

  Future<void> _addModel({ModelCapability? capability}) async {
    _editingProfile = LlmModelProfile(
      id: 'model-${DateTime.now().microsecondsSinceEpoch}',
      name: '',
    );
    _editingCapability = capability;
    _editingNewModel = true;
    _setSection(_SettingsSection.modelEditor);
  }

  void _editModel(LlmModelProfile profile) {
    if (!profile.isUserEditable) return;
    _editingProfile = profile;
    _editingCapability = null;
    _editingNewModel = false;
    _setSection(_SettingsSection.modelEditor);
  }

  Future<void> _deleteModel(LlmModelProfile profile) async {
    if (!profile.isUserEditable) return;
    final selectedCapabilities = <ModelCapability>[
      for (final capability in _visibleModelCapabilities)
        if (_config.selectedProfileFor(capability)?.id == profile.id)
          capability,
    ];
    final chinese = _language == AppLanguage.chinese;
    final isInUse = selectedCapabilities.isNotEmpty;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _configPageBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(chinese ? '删除模型？' : 'Delete model?'),
        content: Text(
          isInUse
              ? chinese
                    ? '“${profile.displayName}”当前正在使用。删除后，相关能力会自动切换到其他可用模型；如果没有可用模型，将变为未配置。'
                    : '“${profile.displayName}” is currently in use. Its capabilities will switch to another available model, or become unconfigured if none is available.'
              : chinese
              ? '确定删除“${profile.displayName}”吗？此操作不会删除聊天记录。'
              : 'Delete “${profile.displayName}”? This will not delete any chats.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(chinese ? '取消' : 'Cancel'),
          ),
          TextButton(
            key: const Key('confirm_delete_model_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFB42318),
            ),
            child: Text(chinese ? '删除' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final profiles = [
      for (final existing in _config.profiles)
        if (existing.id != profile.id) existing,
    ];
    final selectedByCapability = Map<ModelCapability, String>.of(
      _config.selectedProfileIdByCapability,
    )..removeWhere((_, profileId) => profileId == profile.id);
    var selectedProfileId = _config.selectedProfileId;
    if (selectedProfileId == profile.id) {
      selectedProfileId = profiles
          .where((item) => item.supports(ModelCapability.chat))
          .firstOrNull
          ?.id;
    }
    _handleConfigChanged(
      LlmConfigState(
        profiles: List.unmodifiable(profiles),
        selectedProfileId: selectedProfileId,
        selectedProfileIdByCapability: Map.unmodifiable(selectedByCapability),
        systemPrompt: _config.systemPrompt,
        maxToolIterations: _config.maxToolIterations,
        contextEngine: _config.contextEngine,
      ),
    );
  }

  void _saveModelEditor(LlmModelProfile profile) {
    if (!_editingNewModel && _editingProfile?.isUserEditable == false) {
      unawaited(_animateBackToMenu());
      return;
    }
    final profiles = _editingNewModel
        ? [..._config.profiles, profile]
        : [
            for (final existing in _config.profiles)
              existing.id == profile.id ? profile : existing,
          ];
    final selectedByCapability = Map<ModelCapability, String>.of(
      _config.selectedProfileIdByCapability,
    );
    var selectedProfileId = _config.selectedProfileId;
    if (_editingNewModel) {
      final targetCapability = _editingCapability ?? ModelCapability.chat;
      if (profile.supports(targetCapability)) {
        if (targetCapability == ModelCapability.chat) {
          selectedProfileId = profile.id;
        } else {
          selectedByCapability[targetCapability] = profile.id;
        }
      }
    } else {
      selectedByCapability.removeWhere((capability, profileId) {
        return profileId == profile.id && !profile.supports(capability);
      });
      if (selectedProfileId == profile.id &&
          !profile.supports(ModelCapability.chat)) {
        selectedProfileId = profiles
            .where((item) => item.supports(ModelCapability.chat))
            .firstOrNull
            ?.id;
      }
    }
    _handleConfigChanged(
      LlmConfigState(
        profiles: List.unmodifiable(profiles),
        selectedProfileId: selectedProfileId,
        selectedProfileIdByCapability: Map.unmodifiable(selectedByCapability),
        systemPrompt: _config.systemPrompt,
        maxToolIterations: _config.maxToolIterations,
        contextEngine: _config.contextEngine,
      ),
    );
    unawaited(_animateBackToMenu());
  }

  void _setSection(_SettingsSection section) {
    if (_section == section) return;
    if (section == _SettingsSection.menu) {
      unawaited(_animateBackToMenu());
      return;
    }
    setState(() {
      _sectionStack.add(_section);
      _section = section;
      _sectionScrollAtTop.putIfAbsent(section, () => true);
    });
    _sectionController.forward(from: 0);
  }

  void _handleBackSwipeDown(PointerDownEvent event) {
    if (isMenu ||
        _backSwipePointer != null ||
        _backTransitionInFlight ||
        _sectionController.isAnimating) {
      return;
    }
    _backSwipePointer = event.pointer;
    _backSwipeOrigin = event.position;
    _backSwipeActive = false;
    _backSwipeVelocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _handleBackSwipeMove(PointerMoveEvent event) {
    if (event.pointer != _backSwipePointer || isMenu) {
      return;
    }
    _backSwipeVelocityTracker?.addPosition(event.timeStamp, event.position);
    final origin = _backSwipeOrigin;
    if (origin == null) return;
    final delta = event.position - origin;
    if (!_backSwipeActive) {
      if (delta.dx <= 8 || delta.dx <= delta.dy.abs() * 1.15) return;
      _backSwipeActive = true;
    }
    final width = MediaQuery.sizeOf(context).width;
    _sectionController.value = (1 - delta.dx / width).clamp(0.0, 1.0);
  }

  void _handleBackSwipeEnd(PointerEvent event) {
    if (event.pointer != _backSwipePointer) return;
    _backSwipeVelocityTracker?.addPosition(event.timeStamp, event.position);
    final velocity =
        _backSwipeVelocityTracker?.getVelocity().pixelsPerSecond.dx ?? 0.0;
    final wasDragging = _backSwipeActive;
    _resetBackSwipe();
    if (!wasDragging) return;
    if (velocity > _backFlingVelocity || _sectionController.value <= 0.5) {
      unawaited(_animateBackToMenu());
    } else {
      unawaited(_sectionController.animateTo(1, curve: Curves.easeOutCubic));
    }
  }

  void _handleBackSwipeCancel(PointerEvent event) {
    if (event.pointer != _backSwipePointer) return;
    final wasDragging = _backSwipeActive;
    _resetBackSwipe();
    if (wasDragging) {
      unawaited(_sectionController.animateTo(1, curve: Curves.easeOutCubic));
    }
  }

  void _resetBackSwipe() {
    _backSwipePointer = null;
    _backSwipeOrigin = null;
    _backSwipeVelocityTracker = null;
    _backSwipeActive = false;
  }

  Future<void> _animateBackToMenu() async {
    if (isMenu || _backTransitionInFlight) return;
    if (_section == _SettingsSection.agent) {
      _focusAgentContext = false;
    }
    _backTransitionInFlight = true;
    await _sectionController.animateBack(0, curve: Curves.easeOutCubic);
    if (mounted && _sectionController.isDismissed) {
      final target = _sectionStack.isEmpty
          ? _SettingsSection.menu
          : _sectionStack.removeLast();
      setState(() {
        _section = target;
      });
      _sectionController.value = target == _SettingsSection.menu ? 0 : 1;
    }
    _backTransitionInFlight = false;
  }

  Future<void> _handleBack() async {
    if (_section != _SettingsSection.menu) {
      await _animateBackToMenu();
      return;
    }
    final handled = await widget.onBack();
    if (handled != false && mounted) {
      Navigator.of(context).pop();
    }
  }

  Widget _buildBody(AppStrings strings, _SettingsSection section) {
    return switch (section) {
      _SettingsSection.menu => _SettingsListPage(
        config: _config,
        language: _language,
        onSelectModel: _selectModelProfile,
        onAddModel: (capability) =>
            unawaited(_addModel(capability: capability)),
        onOpenModelManagement: () =>
            _setSection(_SettingsSection.modelManagement),
        onOpenAgent: () => _setSection(_SettingsSection.agent),
        onLanguageChanged: _handleLanguageChanged,
        onOpenFeedback: () => _setSection(_SettingsSection.feedback),
        onOpenAbout: () => _setSection(_SettingsSection.about),
      ),
      _SettingsSection.agent => _AgentSettingsPage(
        config: _config,
        onConfigChanged: _handleConfigChanged,
        initiallyFocusContext: _focusAgentContext,
      ),
      _SettingsSection.modelManagement => _ModelManagementPage(
        config: _config,
        language: _language,
        onEditModel: _editModel,
        onDeleteModel: _deleteModel,
      ),
      _SettingsSection.modelEditor =>
        _editingProfile == null
            ? const SizedBox.shrink()
            : _LlmModelProfilePage(
                key: _modelEditorKey,
                initialProfile: _editingProfile!,
                initialCapability: _editingCapability,
                embedded: true,
                onSaved: _saveModelEditor,
              ),
      _SettingsSection.feedback => _FeedbackPage(
        key: _feedbackPageKey,
        updateService: widget.updateService,
        feedbackService: widget.feedbackService,
        onOpenContact: () => _setSection(_SettingsSection.contact),
        embedded: true,
      ),
      _SettingsSection.contact => const _ContactPage(embedded: true),
      _SettingsSection.licenses => const _SettingsLicensesPage(),
      _SettingsSection.configuration => _LlmConfigPage(
        initialConfig: _config,
        language: _language,
        onConfigChanged: _handleConfigChanged,
        onLanguageChanged: _handleLanguageChanged,
        embedded: true,
      ),
      _SettingsSection.channels => _ChannelSettingsPage(
        clientFuture: widget.createNearbyClientFuture(),
      ),
      _SettingsSection.nearby => _NearbySettingsPage(
        clientFuture: widget.createNearbyClientFuture(),
        onStart: widget.onNearbyStart,
        onStop: widget.onNearbyStop,
        onInvite: widget.onNearbyInvite,
        onScan: widget.onNearbyScan,
        onDeletePeer: widget.onNearbyDeletePeer,
        getPairingDiagnostic: widget.getNearbyPairingDiagnostic,
      ),
      _SettingsSection.scenarios => ScenariosPanel(
        clientFuture: _scenariosClientFuture ??= widget
            .createScenariosClientFuture(),
        activeScenarioId: widget.activeScenarioId,
        gitSettings: widget.gitSettings,
        onScenarioApplied: widget.onScenarioApplied,
        onGitSettingsChanged: widget.onGitSettingsChanged,
        onGitSettingsCleared: widget.onGitSettingsCleared,
        embedded: true,
        onBack: () async {
          _setSection(_SettingsSection.menu);
          return false;
        },
      ),
      _SettingsSection.engines => _EngineSettingsPage(
        clientFuture: widget.createScenariosClientFuture(),
        onEngineConfigChanged: widget.onEngineConfigChanged,
        embedded: true,
        onBack: () async {
          _setSection(_SettingsSection.menu);
          return false;
        },
      ),
      _SettingsSection.about => _AboutPage(
        updateService: widget.updateService,
        onCheckForUpdates: widget.onCheckForUpdates,
        onOpenContact: () => _setSection(_SettingsSection.contact),
        onOpenLicenses: () => _setSection(_SettingsSection.licenses),
        embedded: true,
      ),
    };
  }
}

class _ChannelSettingsPage extends StatefulWidget {
  const _ChannelSettingsPage({required this.clientFuture});

  final Future<NapaxiChatClient> clientFuture;

  @override
  State<_ChannelSettingsPage> createState() => _ChannelSettingsPageState();
}

class _ChannelSettingsPageState extends State<_ChannelSettingsPage> {
  late Future<_ChannelSettingsSnapshot> _snapshotFuture;
  String? _busyKey;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = _loadSnapshot();
  }

  Future<_ChannelSettingsSnapshot> _loadSnapshot() async {
    final client = await widget.clientFuture;
    final statuses = await client.listChannelStatuses();
    final agents = await client.listAgents();
    return _ChannelSettingsSnapshot(
      statuses: statuses.where((status) => status.configured).toList(),
      agents: agents,
    );
  }

  void _refresh() {
    final nextSnapshot = _loadSnapshot();
    setState(() {
      _snapshotFuture = nextSnapshot;
    });
  }

  void _refreshConnectedChannel() => _refresh();

  bool _isStatusBusy(DemoChannelStatus status, String action) {
    return _busyKey ==
        _channelBusyKey(
          status.manifest.channelName,
          action,
          accountId: _channelStatusAccountId(status),
        );
  }

  Future<void> _runChannelAction({
    required String channelName,
    required String action,
    String? accountId,
    required Future<bool> Function(NapaxiChatClient client) run,
  }) async {
    if (_busyKey != null) return;
    setState(
      () =>
          _busyKey = _channelBusyKey(channelName, action, accountId: accountId),
    );
    try {
      final client = await widget.clientFuture;
      final shouldRefresh = await run(client);
      if (mounted && shouldRefresh) _refreshConnectedChannel();
    } catch (error) {
      if (mounted) {
        _showChannelSnack(_friendlyChannelError(error), error: true);
      }
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _setupChannel(
    String channelName, {
    String? accountId,
    bool createNew = false,
  }) {
    return _runChannelAction(
      channelName: channelName,
      accountId: accountId,
      action: 'setup',
      run: (client) async {
        final current = createNew
            ? null
            : await client.loadChannelCredentials(
                channelName,
                accountId: accountId,
              );
        final agents = await client.listAgents();
        if (!mounted) return false;
        final credentials = await _showSetupDialog(
          channelName,
          current,
          agents,
        );
        if (credentials == null) return false;
        await client.saveChannelCredentials(credentials);
        final status = await client.connectChannel(
          channelName,
          accountId: _channelCredentialAccountId(credentials),
        );
        if (!mounted) return true;
        final title = _channelDisplayName(context, status.manifest);
        final failed = status.configured && !status.connected;
        _showChannelSnack(
          failed
              ? _channelText(
                  context,
                  zh: '$title 已保存，连接未完成',
                  en: '$title saved, connection is not ready',
                )
              : _channelText(
                  context,
                  zh: '$title 已保存并连接',
                  en: '$title saved and connected',
                ),
          error: failed && (status.lastError?.trim().isNotEmpty == true),
        );
        return true;
      },
    );
  }

  Future<void> _addChannel() async {
    if (_busyKey != null) return;
    final channelName = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ChannelTypePickerDialog(),
    );
    if (channelName == null || !mounted) return;
    await _setupChannel(channelName, createNew: true);
  }

  Future<DemoChannelCredentials?> _showSetupDialog(
    String channelName,
    DemoChannelCredentials? current,
    List<DemoAgent> agents,
  ) {
    if (channelName == sdk.QqBotChannelProvider.channelName) {
      final existing = current == null
          ? null
          : DemoQqChannelCredentials.fromChannelCredentials(current);
      // Shared setup sheet renders _QqChannelSetupDialog from chat_screen_channel.dart.
      return _showQqChannelSetupSheet(
        context,
        existing: existing,
        agents: agents,
      );
    }
    if (channelName == sdk.BluetoothHeadsetChannelProvider.channelName) {
      final existing = current == null
          ? null
          : DemoBluetoothHeadsetChannelCredentials.fromChannelCredentials(
              current,
            );
      // Shared setup sheet renders _HeadsetChannelSetupDialog from chat_screen_channel.dart.
      return _showHeadsetChannelSetupSheet(
        context,
        existing: existing,
        agents: agents,
      );
    }
    return Future.value(null);
  }

  Future<void> _connectChannel(String channelName, {String? accountId}) {
    return _runChannelAction(
      channelName: channelName,
      accountId: accountId,
      action: 'connect',
      run: (client) async {
        final status = await client.connectChannel(
          channelName,
          accountId: accountId,
        );
        if (!mounted) return true;
        final title = _channelDisplayName(context, status.manifest);
        _showChannelSnack(
          status.connected
              ? _channelText(context, zh: '$title 已连接', en: '$title online')
              : _channelText(
                  context,
                  zh: '$title 暂未连接',
                  en: '$title is offline',
                ),
          error:
              !status.connected &&
              (status.lastError?.trim().isNotEmpty == true),
        );
        return true;
      },
    );
  }

  Future<void> _captureHeadsetChannel({String? accountId}) {
    return _runChannelAction(
      channelName: sdk.BluetoothHeadsetChannelProvider.channelName,
      accountId: accountId,
      action: 'voice',
      run: (client) async {
        if (mounted) {
          _showChannelSnack(
            _channelText(
              context,
              zh: '正在听，请对蓝牙设备说话',
              en: 'Listening. Speak to the Bluetooth device.',
            ),
          );
        }
        final result = await client.captureHeadsetTranscript(
          accountId: accountId,
        );
        if (!mounted) return true;
        final transcript = result.transcript?.trim() ?? '';
        final failed =
            !result.accepted || (result.error?.trim().isNotEmpty == true);
        _showChannelSnack(
          failed
              ? (result.error?.trim().isNotEmpty == true
                    ? result.error!.trim()
                    : _channelText(
                        context,
                        zh: '语音输入未完成',
                        en: 'Voice input did not complete',
                      ))
              : transcript.isEmpty
              ? _channelText(
                  context,
                  zh: '语音已发送，回复会从蓝牙设备播放',
                  en: 'Voice sent. The reply will play on the Bluetooth device.',
                )
              : _channelText(
                  context,
                  zh: '已识别：$transcript',
                  en: 'Heard: $transcript',
                ),
          error: failed,
        );
        return true;
      },
    );
  }

  Future<void> _clearChannel(String channelName, {String? accountId}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ChannelClearDialog(
        title: _channelDisplayName(
          context,
          _fallbackChannelManifest(channelName),
        ),
      ),
    );
    if (confirmed != true) return;
    return _runChannelAction(
      channelName: channelName,
      accountId: accountId,
      action: 'clear',
      run: (client) async {
        await client.clearChannelCredentials(channelName, accountId: accountId);
        if (mounted) {
          final title = _channelDisplayName(
            context,
            _fallbackChannelManifest(channelName),
          );
          _showChannelSnack(
            _channelText(context, zh: '$title 已清除', en: '$title removed'),
          );
        }
        return true;
      },
    );
  }

  void _showChannelSnack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(
              color: error ? const Color(0xFF991B1B) : _configTextPrimary,
            ),
          ),
          backgroundColor: error ? const Color(0xFFFEF2F2) : _configSurface,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ChannelSettingsSnapshot>(
      future: _snapshotFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final loading = snapshot.connectionState != ConnectionState.done;
        return ListView(
          key: const Key('channel_settings_page'),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Row(
              children: [
                Expanded(
                  child: _EmbeddedSettingsHeader(
                    title: _channelSettingsPageTitle(context),
                  ),
                ),
                const SizedBox(width: 12),
                _ChannelAddButton(
                  label: _channelText(context, zh: '新增', en: 'Add'),
                  onPressed: _busyKey == null ? _addChannel : null,
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (snapshot.hasError)
              _NearbyDiagnosticCard(
                text: _friendlyChannelError(snapshot.error!),
              )
            else if (data == null || loading)
              _NearbyEmptyCard(text: _channelSettingsLoadingText(context))
            else if (data.statuses.isEmpty)
              _NearbyEmptyCard(text: _channelSettingsEmptyText(context))
            else
              for (final status in data.statuses) ...[
                _ChannelProviderCard(
                  status: status,
                  agents: data.agents,
                  setupBusy: _isStatusBusy(status, 'setup'),
                  connectBusy: _isStatusBusy(status, 'connect'),
                  voiceBusy: _isStatusBusy(status, 'voice'),
                  clearBusy: _isStatusBusy(status, 'clear'),
                  anyBusy: _busyKey != null,
                  onSetup: () => _setupChannel(
                    status.manifest.channelName,
                    accountId: _channelStatusAccountId(status),
                  ),
                  onConnect: status.configured
                      ? () => _connectChannel(
                          status.manifest.channelName,
                          accountId: _channelStatusAccountId(status),
                        )
                      : null,
                  onVoiceInput:
                      status.manifest.channelName ==
                              sdk.BluetoothHeadsetChannelProvider.channelName &&
                          status.connected
                      ? () => _captureHeadsetChannel(
                          accountId: _channelStatusAccountId(status),
                        )
                      : null,
                  onClear: status.configured
                      ? () => _clearChannel(
                          status.manifest.channelName,
                          accountId: _channelStatusAccountId(status),
                        )
                      : null,
                ),
                const SizedBox(height: 12),
              ],
          ],
        );
      },
    );
  }
}

class _ChannelSettingsSnapshot {
  const _ChannelSettingsSnapshot({
    required this.statuses,
    required this.agents,
  });

  final List<DemoChannelStatus> statuses;
  final List<DemoAgent> agents;
}

class _ChannelAddButton extends StatelessWidget {
  const _ChannelAddButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const Key('channel_add_button'),
      onPressed: onPressed,
      icon: const Icon(Icons.add_rounded, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: _configTextPrimary,
        side: const BorderSide(color: _configBorderFaint),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        minimumSize: const Size(0, 38),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ChannelTypePickerDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _ChannelSetupSheetFrame(
      title: _channelText(context, zh: '选择 Channel 类型', en: 'Choose Channel'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ChannelTypeOption(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'QQ',
            onTap: () =>
                Navigator.of(context).pop(sdk.QqBotChannelProvider.channelName),
          ),
          const SizedBox(height: 8),
          _ChannelTypeOption(
            icon: Icons.headphones_rounded,
            title: _channelText(context, zh: '蓝牙设备', en: 'Bluetooth Devices'),
            onTap: () => Navigator.of(
              context,
            ).pop(sdk.BluetoothHeadsetChannelProvider.channelName),
          ),
        ],
      ),
    );
  }
}

class _ChannelTypeOption extends StatelessWidget {
  const _ChannelTypeOption({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF7F7F7),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: _configTextSecondary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _configTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
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

enum _ChannelCardAction { edit, connect, refresh, voice, clear }

class _ChannelProviderCard extends StatelessWidget {
  const _ChannelProviderCard({
    required this.status,
    required this.agents,
    required this.setupBusy,
    required this.connectBusy,
    required this.voiceBusy,
    required this.clearBusy,
    required this.anyBusy,
    required this.onSetup,
    required this.onConnect,
    required this.onVoiceInput,
    required this.onClear,
  });

  final DemoChannelStatus status;
  final List<DemoAgent> agents;
  final bool setupBusy;
  final bool connectBusy;
  final bool voiceBusy;
  final bool clearBusy;
  final bool anyBusy;
  final VoidCallback onSetup;
  final VoidCallback? onConnect;
  final VoidCallback? onVoiceInput;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final manifest = status.manifest;
    final channelName = manifest.channelName;
    final configured = status.configured;
    final connected = status.connected;
    final error = _channelLastError(status);
    final busy = setupBusy || connectBusy || voiceBusy || clearBusy;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: _configSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _configSelectedSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _configBorderFaint),
                ),
                child: Icon(
                  _channelIcon(channelName),
                  color: _configTextSecondary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _channelCardTitle(context, status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _configTextPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _channelDescription(context, status, agents),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _configTextSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _ChannelStatusPill(
                label: _channelConnectionLabel(context, status),
                connected: connected,
                configured: configured,
              ),
              const SizedBox(width: 4),
              if (busy)
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _configTextSecondary,
                      ),
                    ),
                  ),
                )
              else
                PopupMenuButton<_ChannelCardAction>(
                  tooltip: _channelText(context, zh: '操作', en: 'Actions'),
                  enabled: !anyBusy,
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: _configTextSecondary,
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case _ChannelCardAction.edit:
                        onSetup();
                      case _ChannelCardAction.connect:
                        onConnect?.call();
                      case _ChannelCardAction.refresh:
                        onConnect?.call();
                      case _ChannelCardAction.voice:
                        onVoiceInput?.call();
                      case _ChannelCardAction.clear:
                        onClear?.call();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _ChannelCardAction.edit,
                      child: Text(_channelText(context, zh: '设置', en: 'Edit')),
                    ),
                    PopupMenuItem(
                      value: connected
                          ? _ChannelCardAction.refresh
                          : _ChannelCardAction.connect,
                      enabled: onConnect != null,
                      child: Text(
                        connected
                            ? channelName ==
                                      sdk
                                          .BluetoothHeadsetChannelProvider
                                          .channelName
                                  ? _channelText(
                                      context,
                                      zh: '检测连接',
                                      en: 'Check connection',
                                    )
                                  : _channelText(
                                      context,
                                      zh: '刷新',
                                      en: 'Refresh',
                                    )
                            : _channelText(context, zh: '连接', en: 'Connect'),
                      ),
                    ),
                    if (channelName ==
                        sdk.BluetoothHeadsetChannelProvider.channelName)
                      PopupMenuItem(
                        value: _ChannelCardAction.voice,
                        enabled: onVoiceInput != null,
                        child: Text(
                          _channelText(context, zh: '语音输入', en: 'Voice input'),
                        ),
                      ),
                    PopupMenuItem(
                      value: _ChannelCardAction.clear,
                      enabled: onClear != null,
                      child: Text(
                        _channelText(context, zh: '移除', en: 'Remove'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (error.isNotEmpty) ...[
            const SizedBox(height: 10),
            _NearbyDiagnosticCard(text: error),
          ],
        ],
      ),
    );
  }
}

class _ChannelStatusPill extends StatelessWidget {
  const _ChannelStatusPill({
    required this.label,
    required this.connected,
    required this.configured,
  });

  final String label;
  final bool connected;
  final bool configured;

  @override
  Widget build(BuildContext context) {
    final foreground = connected
        ? const Color(0xFF047857)
        : configured
        ? _configTextSecondary
        : _configTextTertiary;
    final background = connected
        ? const Color(0xFFF0FDF4)
        : configured
        ? const Color(0xFFF4F4F4)
        : _configSurface;
    final border = connected
        ? const Color(0xFFBBF7D0)
        : configured
        ? _configBorderFaint
        : _configBorder;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ChannelClearDialog extends StatelessWidget {
  const _ChannelClearDialog({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _configSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        _channelText(context, zh: '清除 Channel', en: 'Clear Channel'),
        style: const TextStyle(
          color: _configTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: Text(
        _channelText(
          context,
          zh: '清除 $title 的配置后，需要重新设置才能连接。',
          en: 'Clearing $title removes its saved setup. You can set it up again later.',
        ),
        style: const TextStyle(
          color: _configTextSecondary,
          fontSize: 13,
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: _configTextSecondary),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(_channelText(context, zh: '取消', en: 'Cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _configTextPrimary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(_channelText(context, zh: '清除', en: 'Clear')),
        ),
      ],
    );
  }
}

sdk.NapaxiChannelProviderManifest _fallbackChannelManifest(String channelName) {
  if (channelName == sdk.BluetoothHeadsetChannelProvider.channelName) {
    return sdk.BluetoothHeadsetChannelProvider.manifestFor(null);
  }
  return sdk.QqBotChannelProvider.manifestFor(null);
}

String _channelBusyKey(String channelName, String action, {String? accountId}) {
  final normalizedAccount = accountId?.trim();
  return '$channelName:${normalizedAccount?.isEmpty == false ? normalizedAccount : 'default'}:$action';
}

String? _channelStatusAccountId(DemoChannelStatus status) {
  final account = status.manifest.accountId.trim();
  if (account.isEmpty || account == 'unconfigured') return null;
  return account;
}

String? _channelCredentialAccountId(DemoChannelCredentials credentials) {
  if (credentials.channelName == sdk.QqBotChannelProvider.channelName) {
    final appId = DemoQqChannelCredentials.fromChannelCredentials(
      credentials,
    ).appId.trim();
    return appId.isEmpty ? null : appId;
  }
  if (credentials.channelName ==
      sdk.BluetoothHeadsetChannelProvider.channelName) {
    final account =
        DemoBluetoothHeadsetChannelCredentials.fromChannelCredentials(
          credentials,
        ).accountId.trim();
    return account.isEmpty ? null : account;
  }
  return null;
}

String _channelSettingsPageTitle(BuildContext context) {
  return _channelText(context, zh: 'Channel', en: 'Channels');
}

String _channelSettingsLoadingText(BuildContext context) {
  return _channelText(
    context,
    zh: '正在读取 Channel 状态...',
    en: 'Loading channels...',
  );
}

String _channelSettingsEmptyText(BuildContext context) {
  return _channelText(
    context,
    zh: '还没有添加 Channel',
    en: 'No channels added yet',
  );
}

String _channelDisplayName(
  BuildContext context,
  sdk.NapaxiChannelProviderManifest manifest,
) {
  if (manifest.channelName == sdk.QqBotChannelProvider.channelName) {
    return 'QQ Channel';
  }
  if (manifest.channelName == sdk.BluetoothHeadsetChannelProvider.channelName) {
    return _channelText(context, zh: '蓝牙设备', en: 'Bluetooth Devices');
  }
  return manifest.displayName.trim().isNotEmpty
      ? manifest.displayName.trim()
      : manifest.channelName;
}

String _channelCardTitle(BuildContext context, DemoChannelStatus status) {
  final base = _channelDisplayName(context, status.manifest);
  if (status.manifest.channelName != sdk.QqBotChannelProvider.channelName) {
    return base;
  }
  final account = _channelStatusAccountId(status);
  if (account == null) return base;
  final suffix = account.length > 4
      ? account.substring(account.length - 4)
      : account;
  return '$base · $suffix';
}

String _channelDescription(
  BuildContext context,
  DemoChannelStatus status,
  List<DemoAgent> agents,
) {
  final channelName = status.manifest.channelName;
  if (channelName == sdk.QqBotChannelProvider.channelName) {
    final appId = _channelStatusAccountId(status) ?? 'QQ';
    return 'AppID $appId · ${_channelAgentLabel(context, status, agents)}';
  }
  if (channelName == sdk.BluetoothHeadsetChannelProvider.channelName) {
    return '${_channelHeadsetLabel(context, status)} · ${_channelAgentLabel(context, status, agents)}';
  }
  return status.manifest.description.trim().isNotEmpty
      ? status.manifest.description.trim()
      : _channelText(context, zh: 'Channel 已注册', en: 'Channel registered');
}

String _channelAgentLabel(
  BuildContext context,
  DemoChannelStatus status,
  List<DemoAgent> agents,
) {
  final value = status.manifest.config['agent_id']?.toString().trim();
  final agentId = value?.isNotEmpty == true
      ? value!
      : sdk.NapaxiEngine.defaultAgentId;
  DemoAgent? agent;
  for (final candidate in _channelAgentOptions(agents)) {
    if (candidate.id == agentId) {
      agent = candidate;
      break;
    }
  }
  final label = agent == null
      ? agentId
      : _channelAgentOptionLabel(context, agent);
  return _channelText(context, zh: 'Agent $label', en: 'Agent $label');
}

String _channelHeadsetLabel(BuildContext context, DemoChannelStatus status) {
  final name = status.deviceName?.trim();
  if (name?.isNotEmpty == true) return name!;
  final id = status.deviceId?.trim();
  if (id?.isNotEmpty == true) return id!;
  return _channelText(context, zh: '蓝牙设备', en: 'Bluetooth device');
}

String _channelConnectionLabel(BuildContext context, DemoChannelStatus status) {
  if (status.connected) {
    return _channelText(context, zh: '已连接', en: 'Online');
  }
  if (status.configured) {
    return _channelText(context, zh: '未连接', en: 'Offline');
  }
  return _channelText(context, zh: '未设置', en: 'Setup');
}

String _channelLastError(DemoChannelStatus status) {
  final bridgeError = status.bridgeLastError?.trim() ?? '';
  if (bridgeError.isNotEmpty) return bridgeError;
  return status.lastError?.trim() ?? '';
}

IconData _channelIcon(String channelName) {
  if (channelName == sdk.BluetoothHeadsetChannelProvider.channelName) {
    return Icons.headphones_rounded;
  }
  return Icons.chat_bubble_outline_rounded;
}

String _friendlyChannelError(Object error) {
  final text = error.toString();
  const prefix = 'Exception: ';
  if (text.startsWith(prefix)) return text.substring(prefix.length);
  return text;
}

String _channelText(
  BuildContext context, {
  required String zh,
  required String en,
}) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese ? zh : en;
}

class _NearbySettingsPage extends StatefulWidget {
  const _NearbySettingsPage({
    required this.clientFuture,
    required this.onStart,
    required this.onStop,
    required this.onInvite,
    required this.onScan,
    required this.onDeletePeer,
    required this.getPairingDiagnostic,
  });

  final Future<NapaxiChatClient> clientFuture;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;
  final Future<void> Function() onInvite;
  final Future<void> Function() onScan;
  final Future<void> Function(sdk.A2APeer peer) onDeletePeer;
  final Future<String?> Function() getPairingDiagnostic;

  @override
  State<_NearbySettingsPage> createState() => _NearbySettingsPageState();
}

class _NearbySettingsPageState extends State<_NearbySettingsPage> {
  late Future<_NearbySnapshot> _snapshotFuture;
  String? _busyAction;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = _loadSnapshot();
  }

  Future<_NearbySnapshot> _loadSnapshot() async {
    final client = await widget.clientFuture;
    final status = await client.localA2AStatus();
    final permissionGranted = await client.checkLocalA2APermission();
    final peers = await client.listLocalA2APeers();
    final remarks = await _loadPeerRemarks();
    final diagnostic = await widget.getPairingDiagnostic();
    return _NearbySnapshot(
      status: status,
      permissionGranted: permissionGranted,
      peers: peers.where(_isNearbyTrustedPeer).toList(growable: false),
      remarks: remarks,
      pairingDiagnostic: diagnostic?.trim() ?? '',
    );
  }

  void _refresh() {
    final nextSnapshot = _loadSnapshot();
    setState(() {
      _snapshotFuture = nextSnapshot;
    });
  }

  Future<void> _runAction(String action, Future<void> Function() run) async {
    if (_busyAction != null) return;
    setState(() => _busyAction = action);
    try {
      await run();
      if (mounted) _refresh();
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _setConnectionAllowed(bool allowed) {
    return _runAction('connection', allowed ? widget.onStart : widget.onStop);
  }

  Future<Map<String, String>> _loadPeerRemarks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_nearbyPeerRemarksKey);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      )..removeWhere(
        (key, value) => key.trim().isEmpty || value.trim().isEmpty,
      );
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _savePeerRemark(String peerId, String remark) async {
    final trimmed = remark.trim();
    final prefs = await SharedPreferences.getInstance();
    final remarks = await _loadPeerRemarks();
    if (trimmed.isEmpty) {
      remarks.remove(peerId);
    } else {
      remarks[peerId] = trimmed;
    }
    await prefs.setString(_nearbyPeerRemarksKey, jsonEncode(remarks));
  }

  Future<void> _editPeerRemark(sdk.A2APeer peer) async {
    final remarks = await _loadPeerRemarks();
    if (!mounted) return;
    final current = remarks[peer.peerId] ?? '';
    final next = await showDialog<String?>(
      context: context,
      builder: (context) =>
          _NearbyPeerRemarkDialog(peer: peer, initialValue: current),
    );
    if (next == null) return;
    await _savePeerRemark(peer.peerId, next);
    if (mounted) _refresh();
  }

  Future<void> _deletePeer(sdk.A2APeer peer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFAFAFA),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('删除设备'),
        content: Text('删除 ${_nearbyPeerDisplayName(peer)} 后，需要重新扫码配对。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              '取消',
              style: TextStyle(color: _configTextSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              '删除',
              style: TextStyle(color: _configTextPrimary),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runAction('delete-${peer.peerId}', () async {
      await widget.onDeletePeer(peer);
      await _savePeerRemark(peer.peerId, '');
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_NearbySnapshot>(
      future: _snapshotFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return ListView(
          key: const Key('nearby_settings_page'),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            const _EmbeddedSettingsHeader(title: '附近'),
            const SizedBox(height: 12),
            const _SettingsSectionHeader(
              title: '连接',
              description: '允许同一网络下的已配对设备连接本机。',
            ),
            const SizedBox(height: 12),
            _NearbyStatusCard(
              loading: snapshot.connectionState != ConnectionState.done,
              busy: _busyAction == 'connection',
              snapshot: data,
              onConnectionChanged: _busyAction == null
                  ? _setConnectionAllowed
                  : null,
            ),
            if (data != null && data.pairingDiagnostic.isNotEmpty) ...[
              const SizedBox(height: 10),
              _NearbyDiagnosticCard(text: data.pairingDiagnostic),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _NearbyActionButton(
                    key: const Key('nearby_invite_button'),
                    label: '邀请',
                    loading: _busyAction == 'invite',
                    filled: true,
                    onPressed: _busyAction == null
                        ? () => _runAction('invite', widget.onInvite)
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _NearbyActionButton(
                    key: const Key('nearby_scan_button'),
                    label: '扫码',
                    loading: _busyAction == 'scan',
                    onPressed: _busyAction == null
                        ? () => _runAction('scan', widget.onScan)
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _SettingsSectionHeader(
              title: '已信任设备',
              description: '完成确认配对后，设备会出现在这里。',
            ),
            const SizedBox(height: 12),
            if (data == null)
              const _NearbyEmptyCard(text: '正在读取附近设备状态...')
            else if (data.peers.isEmpty)
              const _NearbyEmptyCard(text: '还没有已信任设备。扫码或出示邀请码完成配对。')
            else
              for (final peer in data.peers) ...[
                _NearbyPeerTile(
                  peer: peer,
                  remark: data.remarks[peer.peerId] ?? '',
                  onTap: () => _editPeerRemark(peer),
                  onDelete: () => _deletePeer(peer),
                ),
                const SizedBox(height: 8),
              ],
          ],
        );
      },
    );
  }
}

class _NearbySnapshot {
  const _NearbySnapshot({
    required this.status,
    required this.permissionGranted,
    required this.peers,
    required this.remarks,
    required this.pairingDiagnostic,
  });

  final sdk.A2ALocalTransportStatus status;
  final bool permissionGranted;
  final List<sdk.A2APeer> peers;
  final Map<String, String> remarks;
  final String pairingDiagnostic;
}

class _NearbyStatusCard extends StatelessWidget {
  const _NearbyStatusCard({
    required this.loading,
    required this.busy,
    required this.snapshot,
    required this.onConnectionChanged,
  });

  final bool loading;
  final bool busy;
  final _NearbySnapshot? snapshot;
  final ValueChanged<bool>? onConnectionChanged;

  @override
  Widget build(BuildContext context) {
    final status = snapshot?.status;
    final running = status?.running ?? false;
    final supported = status?.supported ?? true;
    final canToggle =
        !loading && !busy && supported && onConnectionChanged != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _configSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '允许连接和被发现',
                      style: TextStyle(
                        color: _configTextPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      status == null
                          ? '正在读取状态'
                          : !supported
                          ? '当前设备暂不可用'
                          : running
                          ? '附近设备可以看到并连接本机'
                          : '关闭后不会被附近设备发现',
                      style: const TextStyle(
                        color: _configTextSecondary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: _ButtonProgress(),
                )
              else
                Switch.adaptive(
                  value: running,
                  onChanged: canToggle ? onConnectionChanged : null,
                  activeThumbColor: _configTextPrimary,
                  activeTrackColor: _configTextPrimary,
                  inactiveThumbColor: _configSurface,
                  inactiveTrackColor: _configBorder,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: _configBorderFaint),
          const SizedBox(height: 6),
          _NearbyMetricRow(
            label: '状态',
            value: status == null
                ? '-'
                : running
                ? '已允许'
                : '未允许',
          ),
          _NearbyMetricRow(
            label: '权限',
            value: snapshot == null
                ? '-'
                : snapshot!.permissionGranted
                ? '可用'
                : '未授权',
          ),
          _NearbyMetricRow(
            label: '可信设备',
            value: snapshot?.peers.length.toString() ?? '-',
          ),
          if (status != null &&
              !status.running &&
              (status.reason.isNotEmpty || status.lastError.isNotEmpty)) ...[
            const SizedBox(height: 8),
            Text(
              status.reason.isNotEmpty ? status.reason : status.lastError,
              style: const TextStyle(
                color: _configTextSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NearbyMetricRow extends StatelessWidget {
  const _NearbyMetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: _configTextSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _configTextPrimary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbyActionButton extends StatelessWidget {
  const _NearbyActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final foreground = filled ? Colors.white : _configTextPrimary;
    final background = filled ? _configTextPrimary : _configSurface;
    return SizedBox(
      height: 42,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: background,
          disabledForegroundColor: _configTextTertiary,
          side: BorderSide(color: filled ? _configTextPrimary : _configBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: loading ? const _ButtonProgress() : Text(label),
      ),
    );
  }
}

class _NearbyEmptyCard extends StatelessWidget {
  const _NearbyEmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _configSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _configTextSecondary,
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }
}

class _NearbyDiagnosticCard extends StatelessWidget {
  const _NearbyDiagnosticCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _configTextSecondary,
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }
}

class _NearbyPeerTile extends StatelessWidget {
  const _NearbyPeerTile({
    required this.peer,
    required this.remark,
    required this.onTap,
    required this.onDelete,
  });

  final sdk.A2APeer peer;
  final String remark;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final title = _nearbyPeerDisplayName(peer, remark: remark);
    return Material(
      color: _configSurface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _configBorderFaint),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _configTextPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      remark.trim().isEmpty ? '已配对' : '已配对 · 已备注',
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
              TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  foregroundColor: _configTextSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(44, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  '备注',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: '删除',
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: _configTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NearbyPeerRemarkDialog extends StatefulWidget {
  const _NearbyPeerRemarkDialog({
    required this.peer,
    required this.initialValue,
  });

  final sdk.A2APeer peer;
  final String initialValue;

  @override
  State<_NearbyPeerRemarkDialog> createState() =>
      _NearbyPeerRemarkDialogState();
}

class _NearbyPeerRemarkDialogState extends State<_NearbyPeerRemarkDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = _nearbyPeerDisplayName(widget.peer);
    return AlertDialog(
      backgroundColor: _configSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text(
        '设备备注',
        style: TextStyle(
          color: _configTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fallback,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _configTextSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 24,
            decoration: InputDecoration(
              hintText: '例如：我的 iPhone',
              counterText: '',
              filled: true,
              fillColor: const Color(0xFFF4F4F4),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _configBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _configTextPrimary),
              ),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: _configTextSecondary),
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: _configTextSecondary),
          onPressed: () => Navigator.of(context).pop(''),
          child: const Text('清除'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _configTextPrimary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

String _nearbyPeerDisplayName(sdk.A2APeer peer, {String remark = ''}) {
  final savedRemark = remark.trim();
  if (savedRemark.isNotEmpty) return savedRemark;
  final raw = peer.displayName.trim();
  if (raw.isNotEmpty && raw.toLowerCase() != 'napaxi') return raw;
  final id = peer.peerId.trim();
  if (id.isEmpty) return '设备';
  final suffix = id.length <= 6 ? id : id.substring(id.length - 6);
  return '设备 ${suffix.toUpperCase()}';
}

bool _isNearbyTrustedPeer(sdk.A2APeer peer) {
  final trust = peer.trustLevel.trim().toLowerCase();
  return trust == 'user_confirmed' ||
      trust == 'trusted' ||
      peer.sharedSecret.trim().isNotEmpty;
}

class _SettingsListPage extends StatelessWidget {
  const _SettingsListPage({
    required this.config,
    required this.language,
    required this.onSelectModel,
    required this.onAddModel,
    required this.onOpenModelManagement,
    required this.onOpenAgent,
    required this.onLanguageChanged,
    required this.onOpenFeedback,
    required this.onOpenAbout,
  });

  final LlmConfigState config;
  final AppLanguage language;
  final void Function(ModelCapability capability, String profileId)
  onSelectModel;
  final ValueChanged<ModelCapability> onAddModel;
  final VoidCallback onOpenModelManagement;
  final VoidCallback onOpenAgent;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final VoidCallback onOpenFeedback;
  final VoidCallback onOpenAbout;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final chinese = language == AppLanguage.chinese;
    return ListView(
      key: const Key('settings_list_page'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
      children: [
        _SettingsGroupTitle(title: chinese ? '模型' : 'Models'),
        _SettingsGroupCard(
          children: [
            _ModelSlotRow(
              capability: ModelCapability.chat,
              icon: Icons.chat_bubble_outline_rounded,
              title: chinese ? '主力推理' : 'Primary reasoning',
              config: config,
              onSelected: onSelectModel,
              onAddModel: onAddModel,
            ),
            _ModelSlotRow(
              capability: ModelCapability.imageAnalysis,
              icon: Icons.image_search_outlined,
              title: chinese ? '图片理解' : 'Image understanding',
              config: config,
              onSelected: onSelectModel,
              onAddModel: onAddModel,
            ),
            _ModelSlotRow(
              capability: ModelCapability.imageGeneration,
              icon: Icons.brush_outlined,
              title: chinese ? '图片生成' : 'Image generation',
              config: config,
              onSelected: onSelectModel,
              onAddModel: onAddModel,
            ),
            _ModelSlotRow(
              capability: ModelCapability.videoGeneration,
              icon: Icons.video_camera_back_outlined,
              title: chinese ? '视频生成' : 'Video generation',
              config: config,
              onSelected: onSelectModel,
              onAddModel: onAddModel,
            ),
            _SettingsActionRow(
              key: const Key('settings_model_management_item'),
              icon: Icons.tune_rounded,
              title: chinese ? '模型管理' : 'Model management',
              onTap: onOpenModelManagement,
            ),
          ],
        ),
        const SizedBox(height: 26),
        _SettingsGroupTitle(title: chinese ? '应用设置' : 'App settings'),
        _SettingsGroupCard(
          children: [
            _SettingsActionRow(
              key: const Key('settings_agent_item'),
              icon: Icons.smart_toy_outlined,
              title: chinese ? '智能体' : 'Agent',
              onTap: onOpenAgent,
            ),
            _SettingsLanguageRow(
              language: language,
              onChanged: onLanguageChanged,
            ),
          ],
        ),
        const SizedBox(height: 26),
        _SettingsGroupTitle(title: chinese ? '获取帮助' : 'Get help'),
        _SettingsGroupCard(
          children: [
            _SettingsActionRow(
              key: const Key('settings_feedback_item'),
              icon: Icons.feedback_outlined,
              title: strings.feedbackTitle,
              onTap: onOpenFeedback,
            ),
            _SettingsActionRow(
              key: const Key('settings_about_item'),
              icon: Icons.info_outline_rounded,
              title: strings.aboutTitle,
              onTap: onOpenAbout,
            ),
          ],
        ),
      ],
    );
  }
}

enum _ModelManagementAction { edit, delete }

class _ModelManagementPage extends StatelessWidget {
  const _ModelManagementPage({
    required this.config,
    required this.language,
    required this.onEditModel,
    required this.onDeleteModel,
  });

  final LlmConfigState config;
  final AppLanguage language;
  final ValueChanged<LlmModelProfile> onEditModel;
  final Future<void> Function(LlmModelProfile profile) onDeleteModel;

  @override
  Widget build(BuildContext context) {
    final chinese = language == AppLanguage.chinese;
    final profiles = config.profiles;
    return ListView(
      key: const Key('settings_model_management_page'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
      children: [
        if (profiles.isEmpty)
          Padding(
            key: const Key('settings_model_management_empty'),
            padding: const EdgeInsets.fromLTRB(24, 72, 24, 0),
            child: Column(
              children: [
                const Icon(
                  Icons.tune_rounded,
                  size: 34,
                  color: _configTextTertiary,
                ),
                const SizedBox(height: 14),
                Text(
                  chinese ? '还没有配置模型' : 'No models configured',
                  style: const TextStyle(
                    color: _configTextPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  chinese
                      ? '点击右上角的加号新增模型'
                      : 'Tap the plus button to add a model.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _configTextSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          )
        else ...[
          _SettingsGroupTitle(title: chinese ? '已配置模型' : 'Configured models'),
          _SettingsGroupCard(
            children: [
              for (final profile in profiles)
                _ModelManagementRow(
                  profile: profile,
                  language: language,
                  inUse: _visibleModelCapabilities.any(
                    (capability) =>
                        config.selectedProfileFor(capability)?.id == profile.id,
                  ),
                  onEdit: () => onEditModel(profile),
                  onDelete: () => unawaited(onDeleteModel(profile)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ModelManagementRow extends StatelessWidget {
  const _ModelManagementRow({
    required this.profile,
    required this.language,
    required this.inUse,
    required this.onEdit,
    required this.onDelete,
  });

  final LlmModelProfile profile;
  final AppLanguage language;
  final bool inUse;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final chinese = language == AppLanguage.chinese;
    final subtitle = profile.subtitle;
    return InkWell(
      key: Key('settings_model_profile_${profile.id}'),
      onTap: profile.isUserEditable ? onEdit : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 66),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 8, 9),
          child: Row(
            children: [
              const Icon(
                Icons.memory_outlined,
                color: _configTextPrimary,
                size: 22,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _configTextPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (inUse) ...[
                          const SizedBox(width: 8),
                          Text(
                            chinese ? '使用中' : 'In use',
                            style: const TextStyle(
                              color: _configTextSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
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
              if (!profile.isUserEditable)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    color: _configTextSecondary,
                  ),
                )
              else
                PopupMenuButton<_ModelManagementAction>(
                  key: Key('settings_model_profile_menu_${profile.id}'),
                  tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                  color: _configSurface,
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: _configTextSecondary,
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case _ModelManagementAction.edit:
                        onEdit();
                      case _ModelManagementAction.delete:
                        onDelete();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _ModelManagementAction.edit,
                      child: Row(
                        children: [
                          const Icon(Icons.edit_outlined, size: 20),
                          const SizedBox(width: 12),
                          Text(chinese ? '编辑' : 'Edit'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: _ModelManagementAction.delete,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                            color: Color(0xFFB42318),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            chinese ? '删除' : 'Delete',
                            style: const TextStyle(color: Color(0xFFB42318)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelSlotRow extends StatelessWidget {
  const _ModelSlotRow({
    required this.capability,
    required this.icon,
    required this.title,
    required this.config,
    required this.onSelected,
    required this.onAddModel,
  });

  final ModelCapability capability;
  final IconData icon;
  final String title;
  final LlmConfigState config;
  final void Function(ModelCapability capability, String profileId) onSelected;
  final ValueChanged<ModelCapability> onAddModel;

  @override
  Widget build(BuildContext context) {
    final chinese =
        _AppLanguageScope.languageOf(context) == AppLanguage.chinese;
    final addModelLabel = AppStrings.of(context).addModel;
    final profiles = config.profiles
        .where((profile) => profile.supports(capability))
        .toList(growable: false);
    final selectedProfile = config.selectedProfileFor(capability);
    final selectedId =
        profiles.any((profile) => profile.id == selectedProfile?.id)
        ? selectedProfile?.id
        : null;
    final dropdownWidth = math.min(
      MediaQuery.sizeOf(context).width * 0.42,
      184.0,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 58),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
        child: Row(
          children: [
            Icon(icon, color: _configTextPrimary, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: _configTextPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SizedBox(
              width: dropdownWidth,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: Key('settings_model_slot_${capability.name}'),
                  value: selectedId,
                  isExpanded: true,
                  isDense: true,
                  alignment: AlignmentDirectional.centerEnd,
                  borderRadius: BorderRadius.circular(16),
                  icon: const Icon(
                    Icons.expand_more_rounded,
                    color: _configTextTertiary,
                  ),
                  hint: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      chinese ? '未配置' : 'Not configured',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _configTextTertiary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  selectedItemBuilder: (context) => [
                    for (final profile in profiles)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(
                          profile.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _configTextSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        addModelLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _configTextSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                  items: [
                    for (final profile in profiles)
                      DropdownMenuItem<String>(
                        value: profile.id,
                        child: Text(
                          profile.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    DropdownMenuItem<String>(
                      key: Key(
                        'settings_model_slot_${capability.name}_add_model',
                      ),
                      value: '',
                      child: Row(
                        children: [
                          const Icon(Icons.add_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(addModelLabel),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    if (value.isEmpty) {
                      onAddModel(capability);
                      return;
                    }
                    onSelected(capability, value);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsLanguageRow extends StatelessWidget {
  const _SettingsLanguageRow({required this.language, required this.onChanged});

  final AppLanguage language;
  final ValueChanged<AppLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    final chinese =
        _AppLanguageScope.languageOf(context) == AppLanguage.chinese;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 58),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
        child: Row(
          children: [
            const Icon(
              Icons.language_rounded,
              color: _configTextPrimary,
              size: 22,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                chinese ? '语言' : 'Language',
                style: const TextStyle(
                  color: _configTextPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<AppLanguage>(
                key: const Key('settings_language_dropdown'),
                value: language,
                isDense: true,
                borderRadius: BorderRadius.circular(16),
                icon: const Icon(
                  Icons.expand_more_rounded,
                  color: _configTextTertiary,
                ),
                items: const [
                  DropdownMenuItem(
                    value: AppLanguage.chinese,
                    child: Text('简体中文'),
                  ),
                  DropdownMenuItem(
                    value: AppLanguage.english,
                    child: Text('English'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) onChanged(value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentSettingsPage extends StatefulWidget {
  const _AgentSettingsPage({
    required this.config,
    required this.onConfigChanged,
    this.initiallyFocusContext = false,
  });

  final LlmConfigState config;
  final ValueChanged<LlmConfigState> onConfigChanged;
  final bool initiallyFocusContext;

  @override
  State<_AgentSettingsPage> createState() => _AgentSettingsPageState();
}

class _AgentSettingsPageState extends State<_AgentSettingsPage> {
  late final TextEditingController _maxRoundsController;
  late final TextEditingController _userPromptController;
  late final TextEditingController _contextWindowController;
  late final TextEditingController _responseReserveController;
  final GlobalKey _contextSectionKey = GlobalKey();
  late String _contextWindowPreset;
  late String _responseReservePreset;

  @override
  void initState() {
    super.initState();
    _maxRoundsController = TextEditingController(
      text: widget.config.maxToolIterations.toString(),
    );
    _userPromptController = TextEditingController(
      text: widget.config.systemPrompt,
    );
    final contextEngine = widget.config.contextEngine;
    _contextWindowPreset = _presetForTokens(
      contextEngine.contextWindowTokens,
      _contextWindowPresetTokens,
    );
    _responseReservePreset = _presetForTokens(
      contextEngine.responseReserveTokens,
      _responseReservePresetTokens,
    );
    _contextWindowController = TextEditingController(
      text: _contextWindowPreset == _tokenPresetCustom
          ? contextEngine.contextWindowTokens?.toString() ?? ''
          : '',
    );
    _responseReserveController = TextEditingController(
      text: _responseReservePreset == _tokenPresetCustom
          ? contextEngine.responseReserveTokens?.toString() ?? ''
          : '',
    );
    if (widget.initiallyFocusContext) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final sectionContext = _contextSectionKey.currentContext;
        if (!mounted || sectionContext == null) return;
        Scrollable.ensureVisible(
          sectionContext,
          alignment: 0.06,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _maxRoundsController.dispose();
    _userPromptController.dispose();
    _contextWindowController.dispose();
    _responseReserveController.dispose();
    super.dispose();
  }

  int get _maxRounds {
    final parsed = int.tryParse(_maxRoundsController.text.trim());
    if (parsed == null) return 50;
    if (parsed < 0) return -1;
    if (parsed == 0) return 0;
    return parsed < 2 ? 2 : parsed;
  }

  int? get _contextWindowTokens => _tokensForPreset(
    _contextWindowPreset,
    _contextWindowController.text,
    _contextWindowPresetTokens,
  );

  int? get _responseReserveTokens => _tokensForPreset(
    _responseReservePreset,
    _responseReserveController.text,
    _responseReservePresetTokens,
  );

  sdk.ContextEngineConfig get _contextEngine {
    final current = widget.config.contextEngine;
    return sdk.ContextEngineConfig(
      enabled: current.enabled,
      engine: current.engine,
      triggerRatio: current.triggerRatio,
      targetRatio: current.targetRatio,
      protectHeadMessages: current.protectHeadMessages,
      protectTailMessages: current.protectTailMessages,
      contextWindowTokens: _contextWindowTokens,
      responseReserveTokens: _responseReserveTokens,
      compactionStrategy: current.compactionStrategy,
      compactionModel: current.compactionModel,
      compactionTimeoutMs: current.compactionTimeoutMs,
      preCompactionMemoryFlush: current.preCompactionMemoryFlush,
    );
  }

  void _emitChanged() {
    widget.onConfigChanged(
      LlmConfigState(
        profiles: widget.config.profiles,
        selectedProfileId: widget.config.selectedProfileId,
        selectedProfileIdByCapability:
            widget.config.selectedProfileIdByCapability,
        systemPrompt: _userPromptController.text.trim(),
        maxToolIterations: _maxRounds,
        contextEngine: _contextEngine,
      ),
    );
  }

  Future<void> _showContextHelp(bool chinese) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: _configPageBackground,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        key: const Key('context_settings_help_sheet'),
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              chinese ? '上下文设置' : 'Context settings',
              style: const TextStyle(
                color: _configTextPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            _ContextSettingsHelpItem(
              title: chinese ? '自动' : 'Auto',
              description: chinese
                  ? '跟随当前主力推理模型；无法识别模型上限时使用 128K。'
                  : 'Follows the active reasoning model and uses 128K when its limit cannot be identified.',
            ),
            const SizedBox(height: 18),
            _ContextSettingsHelpItem(
              title: chinese ? '上下文长度' : 'Context length',
              description: chinese
                  ? '控制系统提示词、聊天记录和工具内容可共同使用的上下文预算。'
                  : 'Controls the shared context budget for system prompts, chat history, and tool content.',
            ),
            const SizedBox(height: 18),
            _ContextSettingsHelpItem(
              title: chinese ? '回复预留' : 'Response reserve',
              description: chinese
                  ? '提前为模型回复保留的 Token；预留越多，可用于输入内容的空间越少。'
                  : 'Tokens reserved for the model response. A larger reserve leaves less room for input.',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final chinese =
        _AppLanguageScope.languageOf(context) == AppLanguage.chinese;
    return ListView(
      key: const Key('agent_settings_page'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _SettingsGroupCard(
          children: [
            _AgentSettingsField(
              key: const Key('max_execution_rounds_field'),
              label: chinese ? '最大执行轮次' : 'Maximum execution rounds',
              controller: _maxRoundsController,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              onChanged: (_) => _emitChanged(),
            ),
            _AgentSettingsField(
              key: const Key('user_prompt_field'),
              label: chinese ? '用户提示词' : 'User prompt',
              hintText: chinese
                  ? '输入希望智能体始终遵循的提示词'
                  : 'Instructions the agent should always follow',
              controller: _userPromptController,
              minLines: 4,
              maxLines: 8,
              onChanged: (_) => _emitChanged(),
            ),
          ],
        ),
        const SizedBox(height: 26),
        _SettingsGroupTitle(
          key: _contextSectionKey,
          title: strings.contextAdvancedTitle,
          trailing: IconButton(
            key: const Key('context_settings_help_button'),
            tooltip: chinese ? '查看上下文说明' : 'About context settings',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            onPressed: () => _showContextHelp(chinese),
            icon: const Icon(
              Icons.help_outline_rounded,
              size: 19,
              color: _configTextSecondary,
            ),
          ),
        ),
        _SettingsGroupCard(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    key: const Key('context_window_preset_field'),
                    initialValue: _contextWindowPreset,
                    decoration: _configInputDecoration(
                      labelText: strings.contextWindowLabel,
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
                          child: Text(_tokenPresetLabel(context, value)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _contextWindowPreset = value);
                      _emitChanged();
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
                      onChanged: (_) => _emitChanged(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('response_reserve_preset_field'),
                    initialValue: _responseReservePreset,
                    decoration: _configInputDecoration(
                      labelText: strings.responseReserveLabel,
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
                          child: Text(_tokenPresetLabel(context, value)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _responseReservePreset = value);
                      _emitChanged();
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
                      onChanged: (_) => _emitChanged(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ContextSettingsHelpItem extends StatelessWidget {
  const _ContextSettingsHelpItem({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _configTextPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          description,
          style: const TextStyle(
            color: _configTextSecondary,
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _AgentSettingsField extends StatelessWidget {
  const _AgentSettingsField({
    super.key,
    required this.label,
    required this.controller,
    required this.onChanged,
    this.hintText,
    this.keyboardType,
    this.minLines,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? hintText;
  final TextInputType? keyboardType;
  final int? minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _configTextPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            minLines: minLines,
            maxLines: maxLines,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hintText,
              filled: true,
              fillColor: _configPageBackground,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 12,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _configBorder),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EngineSettingsPage extends StatefulWidget {
  const _EngineSettingsPage({
    required this.clientFuture,
    required this.onEngineConfigChanged,
    this.embedded = false,
    this.onBack,
  });

  final Future<NapaxiChatClient> clientFuture;
  final VoidCallback onEngineConfigChanged;
  final bool embedded;
  final Future<bool> Function()? onBack;

  @override
  State<_EngineSettingsPage> createState() => _EngineSettingsPageState();
}

class _EngineSettingsPageState extends State<_EngineSettingsPage> {
  final _store = const FlutterSecureStorage();
  final _ccKeyCtrl = TextEditingController();
  final _ccBaseUrlCtrl = TextEditingController();
  final _ccModelCtrl = TextEditingController();
  bool _ccKeyObscured = true;

  List<String> _ccModels = const [];
  bool _ccTesting = false;
  bool _ccFetching = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    const ccSpec = _CliEngineSpec.cc;
    final results = await Future.wait([
      _store.read(key: ccSpec.apiKeyStorageKey),
      _store.read(key: ccSpec.baseUrlStorageKey),
      _store.read(key: ccSpec.modelStorageKey),
    ]);
    if (!mounted) return;
    setState(() {
      if (results[0] != null) _ccKeyCtrl.text = results[0]!;
      if (results[1] != null) _ccBaseUrlCtrl.text = results[1]!;
      if (results[2] != null) _ccModelCtrl.text = results[2]!;
    });
  }

  Future<void> _save(String key, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _store.delete(key: key);
    } else {
      await _store.write(key: key, value: trimmed);
    }
  }

  Future<void> _saveEngine(
    _CliEngineSpec spec, {
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    await Future.wait([
      _save(spec.apiKeyStorageKey, apiKey),
      _save(spec.baseUrlStorageKey, baseUrl),
      _save(spec.modelStorageKey, model),
    ]);
    // Write CC config into sandbox so Claude Code picks it up.
    if (spec.id == 'cc' && apiKey.trim().isNotEmpty) {
      try {
        await _CliEngineBridge.writeCcConfig(
          apiKey: apiKey.trim(),
          baseUrl: baseUrl,
          model: model,
        );
      } catch (_) {}
    }
    widget.onEngineConfigChanged();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).engineApiKeySaved),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  bool _isBusy(String _) => _ccTesting || _ccFetching;

  void _setBusy(
    String engineId, {
    bool testing = false,
    bool fetching = false,
  }) {
    setState(() {
      _ccTesting = testing;
      _ccFetching = fetching;
    });
  }

  void _setModels(String engineId, List<String> models) {
    setState(() => _ccModels = models);
  }

  String _normalizedKey(TextEditingController ctrl) =>
      ctrl.text.replaceAll(RegExp(r'\s+'), '').trim();

  bool _isHeaderSafe(String apiKey) {
    if (apiKey.isEmpty) return false;
    for (final codeUnit in apiKey.codeUnits) {
      if (codeUnit < 0x21 || codeUnit > 0x7e) return false;
    }
    return true;
  }

  Future<void> _testConnection({
    required _CliEngineSpec spec,
    required TextEditingController keyCtrl,
    required TextEditingController baseUrlCtrl,
  }) async {
    final strings = AppStrings.of(context);
    final baseUrl = baseUrlCtrl.text.trim();
    final apiKey = _normalizedKey(keyCtrl);
    if (baseUrl.isEmpty) {
      _showResult(strings.baseUrlRequiredForTest, error: true);
      return;
    }
    if (apiKey.isEmpty) {
      _showResult(strings.apiKeyRequiredForTest, error: true);
      return;
    }
    if (!_isHeaderSafe(apiKey)) {
      _showResult(strings.apiKeyInvalidForHeader, error: true);
      return;
    }
    _setBusy(spec.id, testing: true);
    try {
      final models = await _EngineModelClient.fetchModels(
        spec: spec,
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
      if (!mounted) return;
      _showResult(
        models.isEmpty ? strings.noModelsFound : strings.connectionOk,
      );
    } catch (e) {
      if (!mounted) return;
      _showResult(strings.connectionFailed(_friendlyError(e)), error: true);
    } finally {
      if (mounted) _setBusy(spec.id);
    }
  }

  Future<void> _fetchModelsForEngine({
    required _CliEngineSpec spec,
    required TextEditingController keyCtrl,
    required TextEditingController baseUrlCtrl,
    required TextEditingController modelCtrl,
  }) async {
    final strings = AppStrings.of(context);
    final baseUrl = baseUrlCtrl.text.trim();
    final apiKey = _normalizedKey(keyCtrl);
    if (baseUrl.isEmpty) {
      _showResult(strings.baseUrlRequiredForTest, error: true);
      return;
    }
    if (apiKey.isEmpty) {
      _showResult(strings.apiKeyRequiredForTest, error: true);
      return;
    }
    if (!_isHeaderSafe(apiKey)) {
      _showResult(strings.apiKeyInvalidForHeader, error: true);
      return;
    }
    _setBusy(spec.id, fetching: true);
    try {
      final models = await _EngineModelClient.fetchModels(
        spec: spec,
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
      if (!mounted) return;
      final current = modelCtrl.text.trim();
      final merged = <String>{
        ...models,
        if (current.isNotEmpty) current,
      }.toList()..sort();
      _setModels(spec.id, merged);
      _showResult(
        models.isEmpty
            ? strings.noModelsFound
            : strings.modelsLoaded(models.length),
      );
    } catch (e) {
      if (!mounted) return;
      _showResult(strings.connectionFailed(_friendlyError(e)), error: true);
    } finally {
      if (mounted) _setBusy(spec.id);
    }
  }

  void _showResult(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(
              color: error ? const Color(0xFF991B1B) : const Color(0xFF374151),
            ),
          ),
          backgroundColor: error
              ? const Color(0xFFFEF2F2)
              : const Color(0xFFF0FDF4),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    const prefix = 'Exception: ';
    if (text.startsWith(prefix)) return text.substring(prefix.length);
    return text;
  }

  @override
  void dispose() {
    _ccKeyCtrl.dispose();
    _ccBaseUrlCtrl.dispose();
    _ccModelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const SizedBox(height: 8),
        Text(
          strings.engineSettingsTitle,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          strings.engineSettingsDescription,
          style: const TextStyle(fontSize: 13, color: Color(0xFF737373)),
        ),
        const SizedBox(height: 24),
        _buildEngineSection(
          title: 'Claude Code (CC)',
          spec: _CliEngineSpec.cc,
          keyCtrl: _ccKeyCtrl,
          baseUrlCtrl: _ccBaseUrlCtrl,
          modelCtrl: _ccModelCtrl,
          keyLabel: strings.anthropicApiKeyLabel,
          keyHint: strings.anthropicApiKeyHint,
          obscured: _ccKeyObscured,
          onToggleObscure: () =>
              setState(() => _ccKeyObscured = !_ccKeyObscured),
          models: _ccModels,
          busy: _isBusy('cc'),
          strings: strings,
        ),
      ],
    );
  }

  Widget _buildEngineSection({
    required String title,
    required _CliEngineSpec spec,
    required TextEditingController keyCtrl,
    required TextEditingController baseUrlCtrl,
    required TextEditingController modelCtrl,
    required String keyLabel,
    required String keyHint,
    required bool obscured,
    required VoidCallback onToggleObscure,
    required List<String> models,
    required bool busy,
    required AppStrings strings,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: keyCtrl,
          obscureText: obscured,
          decoration:
              _configInputDecoration(
                labelText: keyLabel,
                hintText: keyHint,
              ).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    obscured
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                  onPressed: onToggleObscure,
                ),
              ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: baseUrlCtrl,
          decoration: _configInputDecoration(
            labelText: strings.apiBaseUrlLabel,
            hintText: strings.apiBaseUrlHint,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: modelCtrl,
          decoration: _configInputDecoration(
            labelText: strings.modelLabel,
            hintText: strings.engineModelHint,
            suffixIcon: models.isEmpty
                ? null
                : PopupMenuButton<String>(
                    tooltip: strings.modelLabel,
                    icon: const Icon(
                      Icons.expand_more_rounded,
                      color: _configTextSecondary,
                    ),
                    onSelected: (model) =>
                        setState(() => modelCtrl.text = model),
                    itemBuilder: (context) => [
                      for (final model in models)
                        PopupMenuItem<String>(value: model, child: Text(model)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _EngineActionButton(
              label: strings.testConnection,
              icon: Icons.link_rounded,
              busy: busy,
              onPressed: () => _testConnection(
                spec: spec,
                keyCtrl: keyCtrl,
                baseUrlCtrl: baseUrlCtrl,
              ),
            ),
            const SizedBox(width: 8),
            _EngineActionButton(
              label: strings.fetchModels,
              icon: Icons.cloud_download_rounded,
              busy: busy,
              onPressed: () => _fetchModelsForEngine(
                spec: spec,
                keyCtrl: keyCtrl,
                baseUrlCtrl: baseUrlCtrl,
                modelCtrl: modelCtrl,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _saveEngine(
                spec,
                apiKey: keyCtrl.text,
                baseUrl: baseUrlCtrl.text,
                model: modelCtrl.text,
              ),
              child: Text(strings.save),
            ),
          ],
        ),
      ],
    );
  }
}

class _EngineActionButton extends StatelessWidget {
  const _EngineActionButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}

class _EngineModelClient {
  const _EngineModelClient._();

  static Future<List<String>> fetchModels({
    required _CliEngineSpec spec,
    required String baseUrl,
    required String apiKey,
  }) {
    return switch (spec.id) {
      'cc' => _CcAnthropicModelClient.fetchModels(
        baseUrl: baseUrl,
        apiKey: apiKey,
      ),
      _ => _OpenAiCompatibleModelClient.fetchModels(
        baseUrl: baseUrl,
        apiKey: apiKey,
      ),
    };
  }
}

class _CcAnthropicModelClient {
  const _CcAnthropicModelClient._();

  static const String _anthropicVersion = '2023-06-01';

  static Future<List<String>> fetchModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final uri = _modelsUri(baseUrl);
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.getUrl(uri);
      request.headers.set('x-api-key', apiKey);
      request.headers.set('anthropic-version', _anthropicVersion);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await utf8.decodeStream(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}: ${_compactBody(body)}');
      }

      return _parseModelIds(body);
    } finally {
      client.close(force: true);
    }
  }

  static Uri _modelsUri(String baseUrl) {
    final normalized = baseUrl.trim().isEmpty
        ? 'https://api.anthropic.com'
        : baseUrl.trim();
    final baseUri = Uri.parse(normalized);
    final segments = <String>[
      for (final segment in baseUri.pathSegments)
        if (segment.trim().isNotEmpty) segment,
    ];
    if (segments.isNotEmpty && segments.last == 'models') {
      return baseUri.replace(pathSegments: segments);
    }
    if (segments.isEmpty || segments.last != 'v1') {
      segments.add('v1');
    }
    segments.add('models');
    return baseUri.replace(pathSegments: segments);
  }
}

List<String> _parseModelIds(String body) {
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
}

String _compactBody(String body) {
  final normalized = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return 'empty response';
  return normalized.length <= 160
      ? normalized
      : '${normalized.substring(0, 160)}...';
}

class _EmbeddedSettingsHeader extends StatelessWidget {
  const _EmbeddedSettingsHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _configTextPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

String _settingsChannelsTitle(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? 'Channel'
      : 'Channels';
}

class _FeedbackPage extends StatefulWidget {
  const _FeedbackPage({
    super.key,
    required this.updateService,
    required this.feedbackService,
    required this.onOpenContact,
    this.onBack,
    this.embedded = false,
  });

  final DemoUpdateService updateService;
  final DemoFeedbackService feedbackService;
  final VoidCallback onOpenContact;
  final Future<bool> Function()? onBack;
  final bool embedded;

  @override
  State<_FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<_FeedbackPage> {
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  bool _submitting = false;
  String? _submitMessage;
  bool _submitSucceeded = false;

  @override
  void dispose() {
    _contentController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final body = FutureBuilder<DemoAppVersion>(
      future: widget.updateService.currentVersion(),
      builder: (context, snapshot) {
        final version =
            snapshot.data ??
            const DemoAppVersion(version: 'unknown', buildNumber: '');
        return ListView(
          key: const Key('feedback_page_list'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
          children: [
            TextField(
              key: const Key('feedback_content_field'),
              controller: _contentController,
              enabled: !_submitting,
              minLines: 6,
              maxLines: 10,
              textInputAction: TextInputAction.newline,
              decoration: _configInputDecoration(
                labelText: strings.feedbackContentLabel,
                hintText: strings.feedbackContentHint,
              ).copyWith(alignLabelWithHint: true),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('feedback_contact_field'),
              controller: _contactController,
              enabled: !_submitting,
              textInputAction: TextInputAction.done,
              decoration: _configInputDecoration(
                labelText: strings.feedbackContactLabel,
                hintText: strings.feedbackContactHint,
              ),
            ),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: _configSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _configBorderFaint),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.feedbackContactUsPrompt,
                      style: const TextStyle(
                        color: _configTextSecondary,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _AboutActionButton(
                      key: const Key('feedback_contact_button'),
                      onPressed: _submitting ? null : widget.onOpenContact,
                      icon: Icons.contact_support_outlined,
                      label: strings.contactUs,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_submitMessage != null) ...[
              _FeedbackStatusMessage(
                key: const Key('feedback_submit_message'),
                message: _submitMessage!,
                succeeded: _submitSucceeded,
              ),
              const SizedBox(height: 12),
            ],
            _AboutActionButton(
              key: const Key('submit_feedback_button'),
              onPressed: _submitting ? null : () => _submit(version),
              icon: Icons.send_rounded,
              label: _submitting ? strings.feedbackSubmitting : strings.submit,
              filled: true,
              loading: _submitting,
            ),
          ],
        );
      },
    );
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: _configPageBackground,
      appBar: AppBar(
        title: Text(strings.feedbackTitle),
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

  Future<void> _submit(DemoAppVersion version) async {
    final strings = AppStrings.of(context);
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      _showFeedbackSnackBar(strings.feedbackContentRequired);
      return;
    }

    setState(() {
      _submitting = true;
      _submitMessage = null;
      _submitSucceeded = false;
    });
    try {
      final result = await widget.feedbackService.submit(
        DemoFeedbackRequest(
          content: content,
          contact: _contactController.text.trim(),
          appVersion: version,
          language: _AppLanguageScope.languageOf(context),
        ),
        strings,
      );
      if (!mounted) return;
      if (result.success) {
        _contentController.clear();
        _contactController.clear();
        setState(() {
          _submitSucceeded = true;
          _submitMessage = strings.feedbackSubmitted;
        });
      } else {
        setState(() {
          _submitSucceeded = false;
          _submitMessage = strings.feedbackSubmitFailed(
            result.message ?? strings.updateUnknownError,
          );
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitSucceeded = false;
        _submitMessage = strings.feedbackSubmitFailed(
          _friendlyDisplayError(error),
        );
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showFeedbackSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FeedbackStatusMessage extends StatelessWidget {
  const _FeedbackStatusMessage({
    super.key,
    required this.message,
    required this.succeeded,
  });

  final String message;
  final bool succeeded;

  @override
  Widget build(BuildContext context) {
    final color = succeeded ? const Color(0xFF047857) : const Color(0xFFB91C1C);
    final background = succeeded
        ? const Color(0xFFF0FDF4)
        : const Color(0xFFFEF2F2);
    final border = succeeded
        ? const Color(0xFFBBF7D0)
        : const Color(0xFFFECACA);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(
            succeeded
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
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
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactPage extends StatefulWidget {
  const _ContactPage({this.onBack, this.embedded = false});

  final Future<bool> Function()? onBack;
  final bool embedded;

  @override
  State<_ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<_ContactPage> {
  late Future<_ContactConfig> _configFuture;

  @override
  void initState() {
    super.initState();
    _configFuture = _loadContactConfig();
  }

  void _refreshContactConfig() {
    final nextConfig = _loadContactConfig();
    setState(() {
      _configFuture = nextConfig;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final body = FutureBuilder<_ContactConfig>(
      future: _configFuture,
      initialData: _ContactConfig.fallback,
      builder: (context, snapshot) {
        final config = snapshot.data ?? _ContactConfig.fallback;
        return ListView(
          key: const Key('contact_page_list'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
          children: [
            if (snapshot.connectionState == ConnectionState.waiting) ...[
              const LinearProgressIndicator(
                minHeight: 2,
                color: _configTextPrimary,
                backgroundColor: _configBorderFaint,
              ),
              const SizedBox(height: 12),
            ],
            _ContactInfoCard(
              icon: Icons.alternate_email_rounded,
              title: strings.contactEmail,
              value: config.email,
              buttonLabel: strings.copyEmail,
              onCopy: () => _copyContactValue(context, config.email),
            ),
            const SizedBox(height: 12),
            _ContactQrCard(
              title: strings.contactDingTalkGroup,
              imageBytes: config.dingtalkQrBytes,
              fallbackAssetName: _dingtalkGroupQrAsset,
              icon: Icons.groups_2_outlined,
              onSave: () => _shareContactQr(
                context,
                title: strings.contactDingTalkGroup,
                imageBytes: config.dingtalkQrBytes,
                fallbackAssetName: _dingtalkGroupQrAsset,
              ),
            ),
            const SizedBox(height: 12),
            _ContactQrCard(
              title: strings.contactWeChatGroup,
              imageBytes: config.wechatQrBytes,
              fallbackAssetName: _wechatGroupQrAsset,
              icon: Icons.chat_bubble_outline_rounded,
              hint: strings.contactWeChatExpiredHint,
              onSave: () => _shareContactQr(
                context,
                title: strings.contactWeChatGroup,
                imageBytes: config.wechatQrBytes,
                fallbackAssetName: _wechatGroupQrAsset,
              ),
            ),
            const SizedBox(height: 12),
            _ContactInfoCard(
              icon: Icons.person_add_alt_1_rounded,
              title: strings.contactAdminWeChat,
              value: config.wechatAdminId,
              buttonLabel: strings.copyWeChatId,
              onCopy: () => _copyContactValue(context, config.wechatAdminId),
            ),
          ],
        );
      },
    );
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: _configPageBackground,
      appBar: AppBar(
        title: Text(strings.contactUs),
        backgroundColor: _configPageBackground,
        foregroundColor: _configTextPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _refreshContactConfig,
            tooltip: MaterialLocalizations.of(
              context,
            ).refreshIndicatorSemanticLabel,
            icon: const Icon(Icons.refresh_rounded, color: _configTextPrimary),
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
      body: body,
    );
  }
}

class _ContactInfoCard extends StatelessWidget {
  const _ContactInfoCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.buttonLabel,
    required this.onCopy,
  });

  final IconData icon;
  final String title;
  final String value;
  final String buttonLabel;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _configSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 22, color: _configTextSecondary),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: _configTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              value,
              style: const TextStyle(
                color: _configTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            _AboutActionButton(
              onPressed: onCopy,
              icon: Icons.copy_rounded,
              label: buttonLabel,
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactQrCard extends StatelessWidget {
  const _ContactQrCard({
    required this.title,
    required this.imageBytes,
    required this.fallbackAssetName,
    required this.icon,
    required this.onSave,
    this.hint,
  });

  final String title;
  final Uint8List? imageBytes;
  final String fallbackAssetName;
  final IconData icon;
  final VoidCallback onSave;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final remoteKey = imageBytes == null
        ? null
        : ValueKey(
            'contact_qr_remote_${fallbackAssetName}_${_contactQrFingerprint(imageBytes!)}',
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _configSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 22, color: _configTextSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: _configTextPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Center(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onSave,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _configSurfaceMuted,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _configBorderFaint),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: imageBytes == null
                        ? Image.asset(
                            fallbackAssetName,
                            key: Key('contact_qr_$fallbackAssetName'),
                            width: 260,
                            fit: BoxFit.contain,
                          )
                        : Image.memory(
                            imageBytes!,
                            key: remoteKey,
                            width: 260,
                            fit: BoxFit.contain,
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _AboutActionButton(
              onPressed: onSave,
              icon: Icons.save_alt_rounded,
              label: AppStrings.of(context).saveQrCode,
            ),
            if (hint != null) ...[
              const SizedBox(height: 12),
              Text(
                hint!,
                style: const TextStyle(
                  color: _configTextSecondary,
                  height: 1.5,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _contactQrFingerprint(Uint8List bytes) {
  var hash = 0;
  for (final byte in bytes) {
    hash = 0x1fffffff & (hash + byte);
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    hash ^= hash >> 6;
  }
  hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
  hash ^= hash >> 11;
  hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  return '${bytes.length}-$hash';
}

Future<void> _shareContactQr(
  BuildContext context, {
  required String title,
  required Uint8List? imageBytes,
  required String fallbackAssetName,
}) async {
  final strings = AppStrings.of(context);
  try {
    final bytes =
        imageBytes ??
        (await rootBundle.load(fallbackAssetName)).buffer.asUint8List();
    final directory = await getTemporaryDirectory();
    final safeTitle = title.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final file = File(
      '${directory.path}/napaxi_${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    await share.Share.shareXFiles([
      share.XFile(file.path, mimeType: 'image/png', name: '$safeTitle.png'),
    ], subject: title);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.qrCodeSaveFailed(error.toString()))),
    );
  }
}

Future<void> _copyContactValue(BuildContext context, String value) async {
  final strings = AppStrings.of(context);
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(strings.contactCopied(value))));
}

class _SessionSectionHeader extends StatelessWidget {
  const _SessionSectionHeader({
    required this.label,
    required this.padding,
    this.fontWeight = FontWeight.w800,
  });

  final String label;
  final EdgeInsetsGeometry padding;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: _sessionMenuText,
              fontSize: 15,
              fontWeight: fontWeight,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySessionHistory extends StatelessWidget {
  const _EmptySessionHistory();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.forum_outlined,
              color: Color(0xFF9CA3AF),
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              strings.emptyHistoryTitle,
              style: const TextStyle(
                color: Color(0xFF333333),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              strings.emptyHistoryDescription,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF666666),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySessionSearchResults extends StatelessWidget {
  const _EmptySessionSearchResults();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.manage_search_rounded,
              color: Color(0xFF9CA3AF),
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              strings.searchHistoryNoResultsTitle,
              style: const TextStyle(
                color: Color(0xFF333333),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              strings.searchHistoryNoResultsDescription,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF666666),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionHistoryTile extends StatelessWidget {
  const _SessionHistoryTile({
    required this.session,
    required this.runState,
    required this.hasA2AUnread,
    required this.isActive,
    required this.onTap,
    required this.onLongPress,
  });

  final ChatSession session;
  final ChatSessionRunState? runState;
  final bool hasA2AUnread;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final runState = this.runState;
    final isTerminalSession = session.id.startsWith('terminal-');
    final tileBackground = isActive
        ? isTerminalSession
              ? const Color(0xFFF4F4F4)
              : const Color(0xFFF0F0F0)
        : Colors.transparent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('session_tile_${session.id}'),
        borderRadius: BorderRadius.circular(10),
        hoverColor: const Color(0xFFEDEDED),
        highlightColor: const Color(0xFFE5E5E5),
        splashColor: const Color(0xFFD4D4D4).withValues(alpha: 0.24),
        onTap: onTap,
        onLongPress: onLongPress,
        child: DecoratedBox(
          key: Key('session_tile_background_${session.id}'),
          decoration: BoxDecoration(
            color: tileBackground,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (isTerminalSession) ...[
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    child: const Icon(
                      Icons.terminal_rounded,
                      color: Color(0xFF666666),
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    _sessionHistoryDisplayTitle(session),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _sessionMenuText,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (runState != null &&
                    (!runState.isTerminal || runState.needsAttention)) ...[
                  _SessionRunBadge(runState: runState),
                  const SizedBox(width: 8),
                ] else if (hasA2AUnread && !isActive) ...[
                  const _A2AUnreadBadge(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _A2AUnreadBadge extends StatelessWidget {
  const _A2AUnreadBadge();

  @override
  Widget build(BuildContext context) {
    return const Tooltip(
      message: '附近对话有新消息',
      child: SizedBox(
        key: Key('a2a_unread_badge'),
        width: 10,
        height: 10,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFF333333),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _SessionRunBadge extends StatelessWidget {
  const _SessionRunBadge({required this.runState});

  final ChatSessionRunState runState;

  @override
  Widget build(BuildContext context) {
    if (runState.status == sdk.SessionRunStatus.running) {
      return const SizedBox(
        key: Key('session_run_spinner'),
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Color(0xFF2563EB),
        ),
      );
    }
    final (icon, color) = switch (runState.status) {
      sdk.SessionRunStatus.waitingForInput => (
        Icons.help_outline_rounded,
        const Color(0xFF7C3AED),
      ),
      sdk.SessionRunStatus.cancelling => (
        Icons.stop_circle_outlined,
        const Color(0xFFF97316),
      ),
      sdk.SessionRunStatus.failed => (
        Icons.error_outline_rounded,
        const Color(0xFFDC2626),
      ),
      sdk.SessionRunStatus.cancelled => (
        Icons.stop_circle_outlined,
        const Color(0xFF6B7280),
      ),
      sdk.SessionRunStatus.completed => (
        Icons.mark_chat_unread_outlined,
        const Color(0xFF059669),
      ),
      sdk.SessionRunStatus.running => (
        Icons.autorenew_rounded,
        const Color(0xFF2563EB),
      ),
    };
    return Icon(
      icon,
      key: Key('session_run_badge_${runState.sessionKey.threadId}'),
      color: color,
      size: 18,
    );
  }
}
