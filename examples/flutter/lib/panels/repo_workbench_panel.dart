part of '../main.dart';

/// Page size used when listing repository children (both the workbench drawer
/// tree and the full-screen file browser). Kept in sync with the upstream cap
/// in `NapaxiChatClient.listGitRepositoryChildren` (`limit.clamp(20, 500)`):
/// the UI must not request more than the client returns, and the
/// "list may be truncated" hint is driven off this same value.
const int _kRepoListLimit = 200;

const sdk.NapaxiScenarioUiContribution _fallbackRepoWorkbenchContribution =
    sdk.NapaxiScenarioUiContribution(
      id: 'ui.repo_workbench',
      capabilityId: 'napaxi.tool.git',
      placement: 'left_menu',
      title: 'Projects',
      icon: 'folder_git',
      renderer: 'repo_workbench',
    );

/// Resolves the `repo_workbench` scenario UI contribution for [activeScenarioId].
///
/// Shared by the session-history menu and the dev-workbench right drawer so
/// both surface the same contribution (or `null`) from the scenario packs.
/// [createScenariosClientFuture] may cache the underlying client future.
Future<sdk.NapaxiScenarioUiContribution?> loadRepoWorkbenchContribution({
  required Future<NapaxiChatClient> Function() createScenariosClientFuture,
  required String? activeScenarioId,
}) async {
  final normalizedScenarioId = _normalizeDemoScenarioId(activeScenarioId);
  final client = await createScenariosClientFuture();
  final packs = _demoScenarioPacks(await client.listScenarioPacks());
  for (final pack in packs) {
    if (pack.id != normalizedScenarioId) continue;
    for (final contribution in pack.uiContributions) {
      final placement = contribution.placement.trim().toLowerCase();
      final renderer = contribution.renderer.trim().toLowerCase();
      if ((placement.isEmpty || placement == 'left_menu') &&
          renderer == 'repo_workbench') {
        return contribution;
      }
    }
  }
  return null;
}

class DemoRepositoryInfo {
  const DemoRepositoryInfo({
    required this.name,
    required this.directory,
    required this.displayDirectory,
    required this.absolutePath,
    required this.modified,
    this.locationLabel = '',
  });

  final String name;
  final String directory;
  final String displayDirectory;
  final String absolutePath;
  final DateTime modified;
  final String locationLabel;
}

class DemoGitRepositoryStatus {
  const DemoGitRepositoryStatus({
    required this.success,
    required this.branch,
    required this.changedFiles,
    this.detached = false,
    this.noCommits = false,
    this.error,
  });

  final bool success;
  final String branch;
  final List<String> changedFiles;
  final bool detached;
  final bool noCommits;
  final String? error;
}

class DemoGitBranchInfo {
  const DemoGitBranchInfo({
    required this.name,
    required this.remote,
    required this.current,
    this.upstream = '',
  });

  final String name;
  final bool remote;
  final bool current;
  final String upstream;
}

class DemoGitCommitInfo {
  const DemoGitCommitInfo({
    required this.hash,
    required this.shortHash,
    required this.subject,
    this.graph = '',
    this.parents = const [],
    this.authorName = '',
    this.authorEmail = '',
    this.authoredAt,
    this.refs = '',
  });

  final String graph;
  final String hash;
  final String shortHash;
  final List<String> parents;
  final String authorName;
  final String authorEmail;
  final DateTime? authoredAt;
  final String refs;
  final String subject;
}

class DemoGitCommitFileChange {
  const DemoGitCommitFileChange({
    required this.path,
    this.additions,
    this.deletions,
  });

  final String path;
  final int? additions;
  final int? deletions;
}

class DemoGitCommitDiff {
  const DemoGitCommitDiff({
    required this.success,
    this.files = const [],
    this.hunks = const [],
    this.tooLarge = false,
    this.error,
  });

  final bool success;
  final List<DemoGitCommitFileChange> files;
  final List<DemoDiffHunk> hunks;
  final bool tooLarge;
  final String? error;
}

class DemoGitRemoteInfo {
  const DemoGitRemoteInfo({
    required this.name,
    this.fetchUrl = '',
    this.pushUrl = '',
  });

  final String name;
  final String fetchUrl;
  final String pushUrl;
}

class DemoGitOperationResult {
  const DemoGitOperationResult({
    required this.success,
    this.message = '',
    this.error,
    this.branch,
    this.changedFiles = const [],
  });

  final bool success;
  final String message;
  final String? error;
  final String? branch;
  final List<String> changedFiles;
}

typedef _GitBranchSwitchCallback =
    Future<DemoGitOperationResult> Function(DemoGitBranchInfo branch);

class DemoRepositoryFileItem {
  const DemoRepositoryFileItem({
    required this.name,
    required this.relativePath,
    required this.absolutePath,
    required this.isDirectory,
    this.sizeBytes,
    this.modified,
    this.mimeType,
  });

  final String name;
  final String relativePath;
  final String absolutePath;
  final bool isDirectory;
  final int? sizeBytes;
  final DateTime? modified;
  final String? mimeType;
}

/// Where a changed path currently lives in the index/working tree.
enum DemoGitChangeArea { staged, unstaged, untracked }

/// High-level kind of change derived from the porcelain status codes.
enum DemoGitChangeCategory {
  modified,
  added,
  deleted,
  renamed,
  unmerged,
  untracked,
}

/// A single changed path resolved from `git status` + `git diff --numstat`.
class DemoGitChangeEntry {
  const DemoGitChangeEntry({
    required this.path,
    required this.indexCode,
    required this.workCode,
    required this.area,
    required this.category,
    this.additions,
    this.deletions,
    this.oldPath,
  });

  final String path;
  final String indexCode;
  final String workCode;
  final DemoGitChangeArea area;
  final DemoGitChangeCategory category;
  final int? additions;
  final int? deletions;
  final String? oldPath;

  /// Display glyph + tint are derived from [category]; this is just a stable
  /// badge label (M/A/D/U/R).
  String get badgeLabel => switch (category) {
    DemoGitChangeCategory.modified => 'M',
    DemoGitChangeCategory.added => 'A',
    DemoGitChangeCategory.deleted => 'D',
    DemoGitChangeCategory.renamed => 'R',
    DemoGitChangeCategory.unmerged => 'U',
    DemoGitChangeCategory.untracked => 'U',
  };
}

/// Aggregated source-control state for a repository: branch + all changed
/// entries (a path with both staged and working-tree changes appears twice,
/// once per [DemoGitChangeArea], mirroring VS Code's source-control view).
class DemoGitChangeSet {
  const DemoGitChangeSet({
    required this.success,
    this.branch = '',
    this.detached = false,
    this.noCommits = false,
    this.entries = const [],
    this.error,
  });

  final bool success;
  final String branch;
  final bool detached;
  final bool noCommits;
  final List<DemoGitChangeEntry> entries;
  final String? error;
}

/// Visual class of a single unified-diff line.
enum DemoDiffLineType { context, added, removed, meta }

/// One line of a parsed unified diff, with its old/new line numbers when known.
class DemoDiffLine {
  const DemoDiffLine({
    required this.type,
    required this.text,
    this.oldLine,
    this.newLine,
  });

  final DemoDiffLineType type;
  final String text;
  final int? oldLine;
  final int? newLine;
}

/// A `@@ -a,b +c,d @@` hunk and its parsed lines.
class DemoDiffHunk {
  const DemoDiffHunk({required this.header, required this.lines});

  final String header;
  final List<DemoDiffLine> lines;
}

/// Result of fetching a single file's diff for inline display. When
/// [tooLarge] the UI shows a placeholder; when [empty] there is nothing on the
/// requested side (e.g. an untracked file has no git diff).
class DemoGitFileDiff {
  const DemoGitFileDiff({
    required this.success,
    this.hunks = const [],
    this.tooLarge = false,
    this.empty = false,
    this.error,
  });

  final bool success;
  final List<DemoDiffHunk> hunks;
  final bool tooLarge;
  final bool empty;
  final String? error;
}

/// Parses unified-diff text (`git diff`) into structured hunks with line
/// numbers. File header lines (diff --git / index / --- / +++) before the first
/// `@@` are dropped; `\ No newline at end of file` markers are skipped.
List<DemoDiffHunk> _parseUnifiedDiff(String text) {
  final hunks = <DemoDiffHunk>[];
  final hunkHeader = RegExp(r'@@\s+-(\d+)(?:,\d+)?\s+\+(\d+)(?:,\d+)?\s*@@');
  DemoDiffHunk? current;
  // Tracks whether the current hunk's `@@ ... @@` header parsed cleanly. A
  // truncated diff can end mid-header (e.g. `@@ -10,5 +10,5` with no closing
  // `@@`); in that case the line counters would otherwise keep the previous
  // hunk's residue and label every line with wrong numbers. We still keep the
  // hunk for its text, but stop assigning line numbers to its body.
  var hunkHeaderOk = false;
  var oldLine = 0;
  var newLine = 0;
  for (final raw in text.split('\n')) {
    if (raw.startsWith('@@')) {
      final match = hunkHeader.firstMatch(raw);
      hunkHeaderOk = match != null;
      if (match != null) {
        oldLine = (int.tryParse(match.group(1)!) ?? 1) - 1;
        newLine = (int.tryParse(match.group(2)!) ?? 1) - 1;
      }
      if (current != null) hunks.add(current);
      current = DemoDiffHunk(header: raw, lines: []);
      continue;
    }
    final hunk = current;
    if (hunk == null) continue; // file header before first hunk
    if (raw.startsWith('\\')) continue; // "No newline at end of file"
    if (raw.startsWith('+')) {
      if (hunkHeaderOk) newLine += 1;
      hunk.lines.add(
        DemoDiffLine(
          type: DemoDiffLineType.added,
          text: raw.substring(1),
          newLine: hunkHeaderOk ? newLine : null,
        ),
      );
    } else if (raw.startsWith('-')) {
      if (hunkHeaderOk) oldLine += 1;
      hunk.lines.add(
        DemoDiffLine(
          type: DemoDiffLineType.removed,
          text: raw.substring(1),
          oldLine: hunkHeaderOk ? oldLine : null,
        ),
      );
    } else if (raw.startsWith(' ') || raw.isEmpty) {
      if (hunkHeaderOk) {
        oldLine += 1;
        newLine += 1;
      }
      hunk.lines.add(
        DemoDiffLine(
          type: DemoDiffLineType.context,
          text: raw.isEmpty ? '' : raw.substring(1),
          oldLine: hunkHeaderOk ? oldLine : null,
          newLine: hunkHeaderOk ? newLine : null,
        ),
      );
    } else {
      hunk.lines.add(DemoDiffLine(type: DemoDiffLineType.meta, text: raw));
    }
  }
  if (current != null) hunks.add(current);
  return hunks;
}

class _ResolvedRepositoryRoot {
  const _ResolvedRepositoryRoot({
    required this.id,
    required this.relativePath,
    required this.displayRelativePath,
    required this.directory,
    required this.workspaceRoot,
    required this.sourceLabel,
  });

  final String id;
  final String relativePath;
  final String displayRelativePath;
  final Directory directory;
  final Directory workspaceRoot;
  final String sourceLabel;
}

class _RepoWorkbenchPage extends StatelessWidget {
  const _RepoWorkbenchPage({
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _configPageBackground,
      appBar: AppBar(
        title: Text(_repoWorkbenchTitle(context, contribution)),
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
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return _FilesMessage(
              icon: Icons.folder_off_rounded,
              title: _repoWorkbenchLoadFailed(context, snapshot.error),
              description: null,
            );
          }
          return _RepoWorkbenchBrowser(
            client: snapshot.data!,
            agentId: agentId,
            contribution: contribution,
          );
        },
      ),
    );
  }
}

class _RepoWorkbenchBrowser extends StatefulWidget {
  const _RepoWorkbenchBrowser({
    required this.client,
    required this.agentId,
    required this.contribution,
  });

  final NapaxiChatClient client;
  final String agentId;
  final sdk.NapaxiScenarioUiContribution contribution;

  @override
  State<_RepoWorkbenchBrowser> createState() => _RepoWorkbenchBrowserState();
}

class _RepoWorkbenchBrowserState extends State<_RepoWorkbenchBrowser>
    with _GitOpSerializer<_RepoWorkbenchBrowser> {
  final TextEditingController _searchController = TextEditingController();
  Future<List<DemoRepositoryInfo>>? _repositoriesFuture;
  Future<DemoGitRepositoryStatus>? _statusFuture;
  Future<List<DemoGitBranchInfo>>? _branchesFuture;
  Future<List<DemoGitRemoteInfo>>? _remotesFuture;
  Future<List<DemoRepositoryFileItem>>? _childrenFuture;
  DemoRepositoryInfo? _selectedRepository;
  DemoGitOperationResult? _lastGitOperation;
  String _currentDirectory = '';
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _repositoriesFuture = widget.client.listGitRepositories();
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final nextQuery = _searchController.text.trim();
    if (nextQuery == _searchQuery) return;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted || nextQuery == _searchQuery) return;
      setState(() {
        _searchQuery = nextQuery;
        _childrenFuture = _loadChildren();
      });
    });
  }

  void _refreshRepositories() {
    setState(() {
      _repositoriesFuture = widget.client.listGitRepositories();
      _statusFuture = _selectedRepository == null
          ? null
          : widget.client.gitRepositoryStatus(_selectedRepository!.directory);
      _branchesFuture = _selectedRepository == null
          ? null
          : widget.client.listGitBranches(_selectedRepository!.directory);
      _remotesFuture = _selectedRepository == null
          ? null
          : widget.client.listGitRemotes(_selectedRepository!.directory);
      _childrenFuture = _selectedRepository == null ? null : _loadChildren();
    });
  }

  void _selectRepository(DemoRepositoryInfo repository) {
    _searchController.clear();
    setState(() {
      _selectedRepository = repository;
      _lastGitOperation = null;
      _currentDirectory = '';
      _searchQuery = '';
      _statusFuture = widget.client.gitRepositoryStatus(repository.directory);
      _branchesFuture = widget.client.listGitBranches(repository.directory);
      _remotesFuture = widget.client.listGitRemotes(repository.directory);
      _childrenFuture = _loadChildren(repository: repository);
    });
  }

  Future<List<DemoRepositoryFileItem>> _loadChildren({
    DemoRepositoryInfo? repository,
  }) {
    final selected = repository ?? _selectedRepository;
    if (selected == null) return Future.value(const []);
    return widget.client.listGitRepositoryChildren(
      selected.directory,
      subdir: _searchQuery.isEmpty ? _currentDirectory : '',
      query: _searchQuery,
      limit: _kRepoListLimit,
    );
  }

  void _refreshStatus() {
    final repository = _selectedRepository;
    if (repository == null) return;
    setState(() {
      _statusFuture = widget.client.gitRepositoryStatus(repository.directory);
      _branchesFuture = widget.client.listGitBranches(repository.directory);
      _remotesFuture = widget.client.listGitRemotes(repository.directory);
    });
  }

  Future<DemoGitOperationResult> _switchBranch(DemoGitBranchInfo branch) async {
    final repository = _selectedRepository;
    if (repository == null) {
      return const DemoGitOperationResult(
        success: false,
        error: 'repository directory is invalid',
      );
    }
    return await runGitOp(() async {
          final result = await widget.client.switchGitBranch(
            repository.directory,
            branch.name,
            remote: branch.remote,
            allowDirty: false,
          );
          if (!mounted) return result;
          if (result.success) _showGitSnack(result);
          setState(() {
            _lastGitOperation = result.success ? null : result;
            _statusFuture = widget.client.gitRepositoryStatus(
              repository.directory,
            );
            _branchesFuture = widget.client.listGitBranches(
              repository.directory,
            );
            _childrenFuture = _loadChildren();
          });
          return result;
        }) ??
        const DemoGitOperationResult(
          success: false,
          error: 'repository directory is invalid',
        );
  }

  Future<void> _fetchRemote([String? remote]) async {
    await runGitOp(() async {
      final repository = _selectedRepository;
      if (repository == null) return;
      final result = await widget.client.fetchGitRemote(
        repository.directory,
        remote: remote,
      );
      if (!mounted) return;
      _showGitSnack(result);
      setState(() {
        _lastGitOperation = result.success ? null : result;
        _statusFuture = widget.client.gitRepositoryStatus(repository.directory);
        _branchesFuture = widget.client.listGitBranches(repository.directory);
        _remotesFuture = widget.client.listGitRemotes(repository.directory);
      });
    });
  }

  Future<void> _openRemoteEditor({DemoGitRemoteInfo? remote}) async {
    await runGitOp(() async {
      final repository = _selectedRepository;
      if (repository == null) return;
      final result = await Navigator.of(context).push<DemoGitOperationResult>(
        MaterialPageRoute(
          builder: (context) => _RemoteEditorPage(
            initialRemote: remote,
            onSave: (name, url) => widget.client.setGitRemote(
              repository.directory,
              name: name,
              url: url,
            ),
            onRemove: remote == null
                ? null
                : () => widget.client.removeGitRemote(
                    repository.directory,
                    name: remote.name,
                  ),
          ),
        ),
      );
      if (!mounted || result == null) return;
      _showGitSnack(result);
      setState(() {
        _lastGitOperation = result.success ? null : result;
        _remotesFuture = widget.client.listGitRemotes(repository.directory);
        _branchesFuture = widget.client.listGitBranches(repository.directory);
      });
    });
  }

  void _showGitSnack(DemoGitOperationResult result) {
    final text = result.success
        ? (result.message.isEmpty
              ? _gitOperationSuccessMessage(context)
              : result.message)
        : (result.error ?? _gitOperationFailedMessage(context));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _refreshChildren() {
    setState(() {
      _childrenFuture = _loadChildren();
    });
  }

  Future<void> _openProjectPicker(List<DemoRepositoryInfo> repositories) async {
    final selected = _selectedRepository;
    if (selected == null) return;
    final next = await Navigator.of(context).push<DemoRepositoryInfo>(
      MaterialPageRoute(
        builder: (context) => _ProjectPickerPage(
          repositories: repositories,
          selectedDirectory: selected.directory,
        ),
      ),
    );
    if (!mounted || next == null || next.directory == selected.directory) {
      return;
    }
    _selectRepository(next);
  }

  void _openDirectory(DemoRepositoryFileItem item) {
    if (!item.isDirectory) return;
    _searchController.clear();
    setState(() {
      _currentDirectory = item.relativePath;
      _searchQuery = '';
      _childrenFuture = _loadChildren();
    });
  }

  void _openParentDirectory() {
    setState(() {
      _currentDirectory = _parentDirectory(_currentDirectory);
      _childrenFuture = _loadChildren();
    });
  }

  Future<void> _openFile(DemoRepositoryFileItem item) async {
    if (item.isDirectory) {
      _openDirectory(item);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _FilePreviewPage(
          client: widget.client,
          agentId: widget.agentId,
          item: _FileBrowserItem(
            source: _FileSource.repository,
            path: item.relativePath,
            name: item.name,
            isDirectory: false,
            realPath: item.absolutePath,
            mimeType: item.mimeType,
            sizeBytes: item.sizeBytes,
            modified: item.modified,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DemoRepositoryInfo>>(
      future: _repositoriesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done &&
            _selectedRepository == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _FilesMessage(
            icon: Icons.error_outline_rounded,
            title: _repoWorkbenchLoadFailed(context, snapshot.error),
            description: null,
            action: IconButton(
              tooltip: MaterialLocalizations.of(
                context,
              ).refreshIndicatorSemanticLabel,
              onPressed: _refreshRepositories,
              icon: const Icon(Icons.refresh_rounded),
            ),
          );
        }

        final repositories = snapshot.data ?? const <DemoRepositoryInfo>[];
        if (repositories.isEmpty) {
          return _FilesMessage(
            icon: Icons.folder_off_rounded,
            title: _repoWorkbenchEmptyTitle(context),
            description: _repoWorkbenchEmptyDescription(context),
            action: IconButton(
              tooltip: MaterialLocalizations.of(
                context,
              ).refreshIndicatorSemanticLabel,
              onPressed: _refreshRepositories,
              icon: const Icon(Icons.refresh_rounded),
            ),
          );
        }

        final selected = _selectedRepository;
        final selectedExists =
            selected != null &&
            repositories.any((repo) => repo.directory == selected.directory);
        if (!selectedExists) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _selectRepository(repositories.first);
          });
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: _RepoWorkbenchHeader(
                repositories: repositories,
                selected: selected,
                contribution: widget.contribution,
                onChooseProject: () => _openProjectPicker(repositories),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _RepoStatusPanel(
                future: _statusFuture,
                branchesFuture: _branchesFuture,
                remotesFuture: _remotesFuture,
                lastOperation: _lastGitOperation,
                onSwitchBranch: _switchBranch,
                onRefresh: _refreshStatus,
                onFetch: _fetchRemote,
                onEditRemote: (remote) => _openRemoteEditor(remote: remote),
                onAddRemote: () => _openRemoteEditor(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                key: const Key('repo_workbench_search_field'),
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: _configInputDecoration(
                  labelText: _repoWorkbenchSearchLabel(context),
                  hintText: _repoWorkbenchSearchHint(context),
                  suffixIcon: _searchController.text.trim().isEmpty
                      ? const Icon(Icons.search_rounded)
                      : IconButton(
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).deleteButtonTooltip,
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _childrenFuture = _loadChildren();
                            });
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
            ),
            if (_currentDirectory.isNotEmpty || _searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  _repoWorkbenchLocationLabel(
                    context,
                    directory: _currentDirectory,
                    query: _searchQuery,
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
            Expanded(
              child: _RepoChildrenView(
                future: _childrenFuture,
                currentDirectory: _currentDirectory,
                searchQuery: _searchQuery,
                onParent: _openParentDirectory,
                onOpen: _openFile,
                onRefresh: _refreshChildren,
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _SourceControlTab { files, changes }

enum _RepoTreeSort { name, modified }

/// Serializes mutating git operations (stage / commit / switch / fetch / …) so
/// that two ops landing in quick succession can't race the post-op refresh and
/// let a stale `setState` clobber the tree or branch list. Both workbench entry
/// points — the right-drawer [_SourceControlWorkbench] and the full-screen
/// [_RepoWorkbenchBrowser] — mix this in so neither path is left unguarded.
///
/// `gitOpBusy` is exposed for the UI to disable inline buttons while an op is
/// in flight; [runGitOp] returns the op's result for callers that need it
/// (e.g. the branch picker's switch callback).
mixin _GitOpSerializer<T extends StatefulWidget> on State<T> {
  Future<void> _gitOpChain = Future<void>.value();
  bool _gitOpBusy = false;

  bool get gitOpBusy => _gitOpBusy;

  Future<R?> runGitOp<R>(Future<R> Function() op) async {
    final completer = Completer<void>();
    final previous = _gitOpChain;
    _gitOpChain = previous.then((_) => completer.future);
    await previous;
    if (!mounted) {
      completer.complete();
      return null;
    }
    setState(() => _gitOpBusy = true);
    try {
      return await op();
    } finally {
      if (mounted) setState(() => _gitOpBusy = false);
      completer.complete();
    }
  }
}

/// Tabbed source-control workbench rendered in the dev-workbench right drawer:
/// a recursive **Files** tree (with git status badges) and a **Changes** view
/// (staged / unstaged groups with `+X/-Y` diff stats, stage / unstage / discard
/// / commit). The full-screen page keeps using [_RepoWorkbenchBrowser]; this is
/// a separate widget so the two stay decoupled.
class _SourceControlWorkbench extends StatefulWidget {
  const _SourceControlWorkbench({
    required this.client,
    required this.agentId,
    required this.contribution,
  });

  final NapaxiChatClient client;
  final String agentId;
  final sdk.NapaxiScenarioUiContribution contribution;

  @override
  State<_SourceControlWorkbench> createState() =>
      _SourceControlWorkbenchState();
}

class _SourceControlWorkbenchState extends State<_SourceControlWorkbench>
    with _GitOpSerializer<_SourceControlWorkbench> {
  Future<List<DemoRepositoryInfo>>? _reposFuture;
  DemoRepositoryInfo? _selectedRepository;
  _SourceControlTab _tab = _SourceControlTab.files;
  _RepoTreeSort _sort = _RepoTreeSort.name;
  bool _showHidden = true;

  Future<DemoGitChangeSet>? _changesFuture;
  Future<List<DemoGitBranchInfo>>? _branchesFuture;
  DemoGitOperationResult? _lastOperation;
  bool _hasRemote = false;

  // Mutating ops (stage/unstage/discard/commit) are serialized + guarded by
  // `_GitOpSerializer` (mixed in above); `gitOpBusy` drives inline button
  // disabling so the UI can't queue a burst.

  // Tree state: loaded children keyed by relative path ('' = repo root).
  final Map<String, List<DemoRepositoryFileItem>> _loadedChildren = {};
  final Set<String> _expandedPaths = {};
  String? _loadingPath;

  @override
  void initState() {
    super.initState();
    _reposFuture = widget.client.listGitRepositories();
  }

  void _selectRepository(DemoRepositoryInfo repository) {
    setState(() {
      _selectedRepository = repository;
      _loadedChildren.clear();
      _expandedPaths.clear();
      _loadingPath = null;
      _lastOperation = null;
      _changesFuture = widget.client.gitChanges(repository.directory);
      _branchesFuture = widget.client.listGitBranches(repository.directory);
    });
    _ensureRootChildren(repository);
    _refreshHasRemote(repository);
  }

  Future<void> _refreshHasRemote(DemoRepositoryInfo repository) async {
    try {
      final remotes = await widget.client.listGitRemotes(repository.directory);
      if (!mounted) return;
      setState(() => _hasRemote = remotes.isNotEmpty);
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasRemote = false);
    }
  }

  Future<void> _pushRepo() {
    final repo = _selectedRepository;
    if (repo == null) return Future.value();
    return _runChangeOp(() => widget.client.pushGitRemote(repo.directory));
  }

  Future<void> _pullRepo() {
    final repo = _selectedRepository;
    if (repo == null) return Future.value();
    return _runChangeOp(() => widget.client.pullGitRemote(repo.directory));
  }

  Future<void> _syncRepo() async {
    final repo = _selectedRepository;
    if (repo == null) return;
    await _runChangeOp(() => widget.client.pullGitRemote(repo.directory));
    await _runChangeOp(() => widget.client.pushGitRemote(repo.directory));
  }

  Future<void> _ensureRootChildren(DemoRepositoryInfo repository) async {
    try {
      final children = await widget.client.listGitRepositoryChildren(
        repository.directory,
        limit: _kRepoListLimit,
      );
      if (!mounted) return;
      setState(() {
        _loadedChildren[''] = _sorted(children);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadedChildren[''] = const [];
        _lastOperation = DemoGitOperationResult(
          success: false,
          error: _friendlyDisplayError(error),
        );
      });
    }
  }

  List<DemoRepositoryFileItem> _sorted(List<DemoRepositoryFileItem> items) {
    final copy = [...items];
    copy.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      if (_sort == _RepoTreeSort.modified) {
        final am = a.modified;
        final bm = b.modified;
        if (am != null && bm != null && am != bm) return bm.compareTo(am);
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return copy;
  }

  Future<void> _toggleExpand(DemoRepositoryFileItem item) async {
    final repo = _selectedRepository;
    if (repo == null) return;
    final path = item.relativePath;
    if (_expandedPaths.contains(path)) {
      setState(() => _expandedPaths.remove(path));
      return;
    }
    if (!_loadedChildren.containsKey(path)) {
      setState(() => _loadingPath = path);
      try {
        final children = await widget.client.listGitRepositoryChildren(
          repo.directory,
          subdir: path,
          limit: _kRepoListLimit,
        );
        if (!mounted) return;
        setState(() {
          _loadedChildren[path] = _sorted(children);
          _loadingPath = null;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _loadedChildren[path] = const [];
          _loadingPath = null;
        });
      }
    }
    setState(() => _expandedPaths.add(path));
  }

  Future<void> _openFile(DemoRepositoryFileItem item) async {
    if (item.isDirectory) {
      await _toggleExpand(item);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _FilePreviewPage(
          client: widget.client,
          agentId: widget.agentId,
          item: _FileBrowserItem(
            source: _FileSource.repository,
            path: item.relativePath,
            name: item.name,
            isDirectory: false,
            realPath: item.absolutePath,
            mimeType: item.mimeType,
            sizeBytes: item.sizeBytes,
            modified: item.modified,
          ),
        ),
      ),
    );
  }

  Future<void> _openProjectPicker(List<DemoRepositoryInfo> repositories) async {
    final selected = _selectedRepository;
    if (selected == null) return;
    final next = await Navigator.of(context).push<DemoRepositoryInfo>(
      MaterialPageRoute(
        builder: (context) => _ProjectPickerPage(
          repositories: repositories,
          selectedDirectory: selected.directory,
        ),
      ),
    );
    if (!mounted || next == null || next.directory == selected.directory) {
      return;
    }
    _selectRepository(next);
  }

  void _refreshChanges() {
    final repo = _selectedRepository;
    if (repo == null) return;
    setState(() {
      _changesFuture = widget.client.gitChanges(repo.directory);
      _branchesFuture = widget.client.listGitBranches(repo.directory);
    });
  }

  void _refreshAll() {
    final repo = _selectedRepository;
    if (repo == null) return;
    setState(() {
      _loadedChildren.clear();
      _expandedPaths.clear();
      _changesFuture = widget.client.gitChanges(repo.directory);
      _branchesFuture = widget.client.listGitBranches(repo.directory);
    });
    _ensureRootChildren(repo);
  }

  Future<DemoGitOperationResult> _switchBranch(DemoGitBranchInfo branch) async {
    final repo = _selectedRepository;
    if (repo == null) {
      return const DemoGitOperationResult(
        success: false,
        error: 'repository directory is invalid',
      );
    }
    return await runGitOp(() async {
          final result = await widget.client.switchGitBranch(
            repo.directory,
            branch.name,
            remote: branch.remote,
            allowDirty: false,
          );
          if (!mounted) return result;
          _showSnack(result);
          setState(() {
            _lastOperation = result.success ? null : result;
            _changesFuture = widget.client.gitChanges(repo.directory);
            _branchesFuture = widget.client.listGitBranches(repo.directory);
            if (result.success) {
              _loadedChildren.clear();
              _expandedPaths.clear();
            }
          });
          if (result.success) await _ensureRootChildren(repo);
          return result;
        }) ??
        const DemoGitOperationResult(
          success: false,
          error: 'repository directory is invalid',
        );
  }

  Future<void> _runChangeOp(
    Future<DemoGitOperationResult> Function() op,
  ) async {
    // Serialized via `_GitOpSerializer.runGitOp` so ops run strictly in arrival
    // order; a concurrent refresh from an earlier op would otherwise land out
    // of order and clobber state.
    await runGitOp(() async {
      final result = await op();
      if (!mounted) return;
      _showSnack(result);
      final repo = _selectedRepository;
      setState(() {
        _lastOperation = result.success ? null : result;
        if (repo != null) {
          _changesFuture = widget.client.gitChanges(repo.directory);
          _branchesFuture = widget.client.listGitBranches(repo.directory);
          _loadedChildren.clear(); // refresh badges in the tree
        }
      });
      if (repo != null) await _ensureRootChildren(repo);
    });
  }

  void _showSnack(DemoGitOperationResult result) {
    final text = result.success
        ? (result.message.isEmpty
              ? _sourceControlOpSuccess(context)
              : result.message)
        : (result.error ?? _sourceControlOpFailed(context));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DemoRepositoryInfo>>(
      future: _reposFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done &&
            _selectedRepository == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _FilesMessage(
            icon: Icons.error_outline_rounded,
            title: _repoWorkbenchLoadFailed(context, snapshot.error),
            description: null,
            action: IconButton(
              tooltip: MaterialLocalizations.of(
                context,
              ).refreshIndicatorSemanticLabel,
              onPressed: () {
                setState(() {
                  _reposFuture = widget.client.listGitRepositories();
                });
              },
              icon: const Icon(Icons.refresh_rounded),
            ),
          );
        }
        final repositories = snapshot.data ?? const <DemoRepositoryInfo>[];
        if (repositories.isEmpty) {
          return _FilesMessage(
            icon: Icons.folder_off_rounded,
            title: _repoWorkbenchEmptyTitle(context),
            description: _repoWorkbenchEmptyDescription(context),
            action: IconButton(
              tooltip: MaterialLocalizations.of(
                context,
              ).refreshIndicatorSemanticLabel,
              onPressed: () {
                setState(() {
                  _reposFuture = widget.client.listGitRepositories();
                });
              },
              icon: const Icon(Icons.refresh_rounded),
            ),
          );
        }
        final selected = _selectedRepository;
        final selectedExists =
            selected != null &&
            repositories.any((repo) => repo.directory == selected.directory);
        if (!selectedExists) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _selectRepository(repositories.first);
          });
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: _RepoWorkbenchHeader(
                repositories: repositories,
                selected: selected,
                contribution: widget.contribution,
                onChooseProject: () => _openProjectPicker(repositories),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _SourceControlTabBar(
                tab: _tab,
                onChanged: (tab) => setState(() => _tab = tab),
              ),
            ),
            Expanded(
              child: _tab == _SourceControlTab.files
                  ? _buildFilesTab(selected)
                  : _buildChangesTab(selected),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilesTab(DemoRepositoryInfo repo) {
    return FutureBuilder<DemoGitChangeSet>(
      future: _changesFuture,
      builder: (context, snapshot) {
        final statusByPath = <String, DemoGitChangeEntry>{};
        final changes = snapshot.data;
        if (changes?.success == true) {
          for (final entry in changes!.entries) {
            statusByPath[entry.path] = entry;
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FilesTreeToolbar(
              sort: _sort,
              showHidden: _showHidden,
              loading: _loadingPath != null,
              onToggleSort: () => setState(() {
                _sort = _sort == _RepoTreeSort.name
                    ? _RepoTreeSort.modified
                    : _RepoTreeSort.name;
                _loadedChildren.updateAll((_, items) => _sorted(items));
              }),
              onToggleHidden: () => setState(() => _showHidden = !_showHidden),
              onRefresh: _refreshAll,
            ),
            Expanded(child: _buildTree(statusByPath)),
          ],
        );
      },
    );
  }

  Widget _buildTree(Map<String, DemoGitChangeEntry> statusByPath) {
    final root = _loadedChildren[''];
    if (root == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final visible = _filterHidden(root);
    if (visible.isEmpty) {
      return _FilesMessage(
        icon: Icons.folder_open_rounded,
        title: _repoWorkbenchNoFilesTitle(context),
        description: _repoWorkbenchNoFilesDescription(context),
      );
    }
    final rows = <Widget>[];
    void visit(List<DemoRepositoryFileItem> nodes, int depth) {
      for (final item in _filterHidden(nodes)) {
        final expanded = _expandedPaths.contains(item.relativePath);
        rows.add(
          _RepoFileTreeNodeTile(
            item: item,
            depth: depth,
            expanded: expanded,
            loading: _loadingPath == item.relativePath,
            status: statusByPath[item.relativePath],
            onToggle: () => _toggleExpand(item),
            onTap: () => _openFile(item),
          ),
        );
        if (item.isDirectory && expanded) {
          final children = _loadedChildren[item.relativePath] ?? const [];
          visit(children, depth + 1);
        }
      }
    }

    visit(visible, 0);
    return RefreshIndicator(
      onRefresh: () async => _refreshAll(),
      child: ListView.separated(
        key: const Key('source_control_file_tree'),
        padding: const EdgeInsets.fromLTRB(8, 4, 12, 24),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 2),
        itemBuilder: (_, index) => rows[index],
      ),
    );
  }

  List<DemoRepositoryFileItem> _filterHidden(
    List<DemoRepositoryFileItem> items,
  ) {
    if (_showHidden) return items;
    return items
        .where((item) => !item.name.startsWith('.'))
        .toList(growable: false);
  }

  Widget _buildChangesTab(DemoRepositoryInfo repo) {
    return FutureBuilder<DemoGitChangeSet>(
      future: _changesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done &&
            snapshot.data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _FilesMessage(
            icon: Icons.error_outline_rounded,
            title: _repoWorkbenchLoadFailed(context, snapshot.error),
            description: null,
          );
        }
        final set = snapshot.data;
        if (set == null || set.success != true) {
          return _FilesMessage(
            icon: Icons.cloud_off_rounded,
            title: _sourceControlChangesLoadFailed(context, set?.error),
            description: null,
          );
        }
        final staged = set.entries
            .where((entry) => entry.area == DemoGitChangeArea.staged)
            .toList(growable: false);
        final unstaged = set.entries
            .where(
              (entry) =>
                  entry.area == DemoGitChangeArea.unstaged ||
                  entry.area == DemoGitChangeArea.untracked,
            )
            .toList(growable: false);
        return _RepoChangesView(
          repo: repo,
          branch: set.branch,
          branchesFuture: _branchesFuture,
          staged: staged,
          unstaged: unstaged,
          lastOperation: _lastOperation,
          busy: gitOpBusy,
          onSwitchBranch: _switchBranch,
          onOpenCommitGraph: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (context) =>
                  _GitGraphPage(repo: repo, client: widget.client),
            ),
          ),
          onStage: (paths) => _runChangeOp(
            () => widget.client.stageGitPaths(repo.directory, paths),
          ),
          onUnstage: (paths) => _runChangeOp(
            () => widget.client.unstageGitPaths(repo.directory, paths),
          ),
          onDiscard: (paths) => _runChangeOp(
            () => widget.client.discardGitPaths(repo.directory, paths),
          ),
          onCommit: (message) => _runChangeOp(
            () => widget.client.commitGit(repo.directory, message),
          ),
          canPush: _hasRemote,
          onPush: _pushRepo,
          onPull: _pullRepo,
          onSync: _syncRepo,
          onRefresh: _refreshChanges,
          loadDiff: (entry) => widget.client.gitFileDiff(
            repo.directory,
            entry.path,
            cached: entry.area == DemoGitChangeArea.staged,
          ),
        );
      },
    );
  }
}

class _SourceControlTabBar extends StatelessWidget {
  const _SourceControlTabBar({required this.tab, required this.onChanged});

  final _SourceControlTab tab;
  final ValueChanged<_SourceControlTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _configSurfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            Expanded(
              child: _segment(
                context,
                _SourceControlTab.files,
                Icons.folder_open_rounded,
                _sourceControlFilesLabel(context),
              ),
            ),
            Expanded(
              child: _segment(
                context,
                _SourceControlTab.changes,
                Icons.difference_rounded,
                _sourceControlChangesLabel(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    _SourceControlTab value,
    IconData icon,
    String label,
  ) {
    final active = tab == value;
    return InkWell(
      key: Key('source_control_tab_${value.name}'),
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: active ? _configSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: active
              ? Border.all(color: _configBorderFaint)
              : Border.all(color: Colors.transparent),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: active ? _configTextPrimary : _configTextSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: active ? _configTextPrimary : _configTextSecondary,
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilesTreeToolbar extends StatelessWidget {
  const _FilesTreeToolbar({
    required this.sort,
    required this.showHidden,
    required this.loading,
    required this.onToggleSort,
    required this.onToggleHidden,
    required this.onRefresh,
  });

  final _RepoTreeSort sort;
  final bool showHidden;
  final bool loading;
  final VoidCallback onToggleSort;
  final VoidCallback onToggleHidden;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Row(
        children: [
          IconButton(
            tooltip: sort == _RepoTreeSort.name
                ? _sourceControlSortByNameTooltip(context)
                : _sourceControlSortByModifiedTooltip(context),
            onPressed: onToggleSort,
            icon: Icon(
              sort == _RepoTreeSort.name
                  ? Icons.sort_by_alpha_rounded
                  : Icons.access_time_rounded,
              size: 20,
            ),
          ),
          IconButton(
            tooltip: showHidden
                ? _sourceControlHideHiddenTooltip(context)
                : _sourceControlShowHiddenTooltip(context),
            onPressed: onToggleHidden,
            icon: Icon(
              showHidden
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              size: 20,
            ),
          ),
          const Spacer(),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            tooltip: MaterialLocalizations.of(
              context,
            ).refreshIndicatorSemanticLabel,
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _RepoFileTreeNodeTile extends StatelessWidget {
  const _RepoFileTreeNodeTile({
    required this.item,
    required this.depth,
    required this.expanded,
    required this.loading,
    required this.status,
    required this.onToggle,
    required this.onTap,
  });

  final DemoRepositoryFileItem item;
  final int depth;
  final bool expanded;
  final bool loading;
  final DemoGitChangeEntry? status;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDirectory = item.isDirectory;
    return InkWell(
      key: Key('repo_file_row_${item.relativePath}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          children: [
            SizedBox(width: 12.0 * depth),
            if (isDirectory)
              _ExpandChevron(
                expanded: expanded,
                loading: loading,
                onTap: onToggle,
              )
            else
              const SizedBox(width: 20),
            const SizedBox(width: 4),
            Icon(
              isDirectory
                  ? Icons.folder_rounded
                  : _repoFileIcon(item.name, item.mimeType),
              size: 18,
              color: _configTextSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _configTextPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (status != null) ...[
              const SizedBox(width: 6),
              _GitStatusBadge(category: status!.category),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExpandChevron extends StatelessWidget {
  const _ExpandChevron({
    required this.expanded,
    required this.loading,
    required this.onTap,
  });

  final bool expanded;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 20,
        height: 20,
        child: loading
            ? const Padding(
                padding: EdgeInsets.all(3),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                expanded
                    ? Icons.expand_more_rounded
                    : Icons.chevron_right_rounded,
                size: 20,
                color: _configTextTertiary,
              ),
      ),
    );
  }
}

class _GitStatusBadge extends StatelessWidget {
  const _GitStatusBadge({required this.category});

  final DemoGitChangeCategory category;

  @override
  Widget build(BuildContext context) {
    final color = _changeBadgeColor(category);
    final label = switch (category) {
      DemoGitChangeCategory.modified => 'M',
      DemoGitChangeCategory.added => 'A',
      DemoGitChangeCategory.deleted => 'D',
      DemoGitChangeCategory.renamed => 'R',
      DemoGitChangeCategory.unmerged => 'U',
      DemoGitChangeCategory.untracked => 'U',
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

Color _changeBadgeColor(DemoGitChangeCategory category) {
  return switch (category) {
    DemoGitChangeCategory.modified => const Color(0xFFB7791F),
    DemoGitChangeCategory.added ||
    DemoGitChangeCategory.untracked => const Color(0xFF2E7D32),
    DemoGitChangeCategory.deleted => const Color(0xFFC62828),
    DemoGitChangeCategory.renamed => const Color(0xFF1565C0),
    DemoGitChangeCategory.unmerged => const Color(0xFF6A1B9A),
  };
}

class _RepoChangesView extends StatelessWidget {
  const _RepoChangesView({
    required this.repo,
    required this.branch,
    required this.branchesFuture,
    required this.staged,
    required this.unstaged,
    required this.lastOperation,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
    required this.onCommit,
    required this.onSwitchBranch,
    required this.onOpenCommitGraph,
    required this.onRefresh,
    required this.loadDiff,
    this.busy = false,
    this.canPush = false,
    required this.onPush,
    required this.onPull,
    required this.onSync,
  });

  final DemoRepositoryInfo repo;
  final String branch;
  final Future<List<DemoGitBranchInfo>>? branchesFuture;
  final List<DemoGitChangeEntry> staged;
  final List<DemoGitChangeEntry> unstaged;
  final DemoGitOperationResult? lastOperation;
  final bool busy;
  final Future<void> Function(List<String> paths) onStage;
  final Future<void> Function(List<String> paths) onUnstage;
  final Future<void> Function(List<String> paths) onDiscard;
  final Future<void> Function(String message) onCommit;
  final _GitBranchSwitchCallback onSwitchBranch;
  final VoidCallback onOpenCommitGraph;
  final VoidCallback onRefresh;
  final Future<DemoGitFileDiff> Function(DemoGitChangeEntry entry) loadDiff;
  final bool canPush;
  final Future<void> Function() onPush;
  final Future<void> Function() onPull;
  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context) {
    final clean = staged.isEmpty && unstaged.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChangesHeader(
          repo: repo,
          branch: branch,
          branchesFuture: branchesFuture,
          changedCount: staged.length + unstaged.length,
          canCommit: staged.isNotEmpty,
          canPush: canPush,
          onSwitchBranch: onSwitchBranch,
          onOpenCommitGraph: onOpenCommitGraph,
          onCommit: () => _openCommitDialog(context),
          onCommitAndPush: () =>
              _openCommitDialog(context, afterCommit: onPush),
          onPush: onPush,
          onPull: onPull,
          onSync: onSync,
          onRefresh: onRefresh,
        ),
        if (lastOperation != null && !lastOperation!.success) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _GitOperationErrorRow(result: lastOperation!),
          ),
        ],
        Expanded(
          child: clean
              ? _FilesMessage(
                  icon: Icons.check_circle_outline_rounded,
                  title: _sourceControlEmptyTitle(context),
                  description: null,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  children: [
                    if (staged.isNotEmpty) ...[
                      _ChangeGroupHeader(
                        key: const Key('source_control_staged_group'),
                        title: _sourceControlStagedLabel(context),
                        count: staged.length,
                        actionLabel: _sourceControlUnstageAllLabel(context),
                        onAction: () => onUnstage(const ['.']),
                        busy: busy,
                      ),
                      for (final entry in staged)
                        _ChangeRow(
                          key: Key(
                            'source_control_change_staged_${entry.path}',
                          ),
                          entry: entry,
                          busy: busy,
                          onUnstage: () => onUnstage([entry.path]),
                          loadDiff: () => loadDiff(entry),
                        ),
                      const SizedBox(height: 10),
                    ],
                    if (unstaged.isNotEmpty) ...[
                      _ChangeGroupHeader(
                        key: const Key('source_control_unstaged_group'),
                        title: _sourceControlUnstagedLabel(context),
                        count: unstaged.length,
                        actionLabel: _sourceControlStageAllLabel(context),
                        onAction: () => onStage(const ['.']),
                        busy: busy,
                      ),
                      for (final entry in unstaged)
                        _ChangeRow(
                          key: Key(
                            'source_control_change_unstaged_${entry.path}',
                          ),
                          entry: entry,
                          busy: busy,
                          onStage: () => onStage([entry.path]),
                          onDiscard: () => _confirmDiscard(context, entry),
                          loadDiff: () => loadDiff(entry),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _openCommitDialog(
    BuildContext context, {
    Future<void> Function()? afterCommit,
  }) async {
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_sourceControlCommitLabel(context)),
        content: TextField(
          key: const Key('commit_message_field'),
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          textInputAction: TextInputAction.newline,
          decoration: _configInputDecoration(
            labelText: _sourceControlCommitMessageLabel(context),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            key: const Key('commit_confirm_button'),
            onPressed: () {
              final value = controller.text.trim();
              Navigator.of(dialogContext).pop(value.isEmpty ? null : value);
            },
            child: Text(_sourceControlCommitLabel(context)),
          ),
        ],
      ),
    );
    if (message != null) await onCommit(message);
    if (afterCommit != null) await afterCommit();
  }

  Future<void> _confirmDiscard(
    BuildContext context,
    DemoGitChangeEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('discard_confirm_dialog'),
        title: Text(_sourceControlDiscardConfirmTitle(context)),
        content: Text(_sourceControlDiscardConfirmMessage(context, entry.path)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_sourceControlDiscardLabel(context)),
          ),
        ],
      ),
    );
    if (confirmed == true) await onDiscard([entry.path]);
  }
}

class _ChangesHeader extends StatelessWidget {
  const _ChangesHeader({
    required this.repo,
    required this.branch,
    required this.branchesFuture,
    required this.changedCount,
    required this.canCommit,
    required this.canPush,
    required this.onSwitchBranch,
    required this.onOpenCommitGraph,
    required this.onCommit,
    required this.onCommitAndPush,
    required this.onPush,
    required this.onPull,
    required this.onSync,
    required this.onRefresh,
  });

  final DemoRepositoryInfo repo;
  final String branch;
  final Future<List<DemoGitBranchInfo>>? branchesFuture;
  final int changedCount;
  final bool canCommit;
  final bool canPush;
  final _GitBranchSwitchCallback onSwitchBranch;
  final VoidCallback onOpenCommitGraph;
  final VoidCallback onCommit;
  final VoidCallback onCommitAndPush;
  final Future<void> Function() onPush;
  final Future<void> Function() onPull;
  final Future<void> Function() onSync;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final path = repo.displayDirectory.trim().isNotEmpty
        ? repo.displayDirectory
        : repo.name;
    final hasChanges = changedCount > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _ChangesBranchSelector(
                  fallbackLabel: path,
                  branch: branch,
                  branchesFuture: branchesFuture,
                  onSwitchBranch: onSwitchBranch,
                ),
              ),
              _CommitSplitButton(
                canCommit: canCommit,
                canPush: canPush,
                onCommit: onCommit,
                onCommitAndPush: onCommitAndPush,
                onPush: onPush,
                onPull: onPull,
                onSync: onSync,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.circle,
                size: 8,
                color: hasChanges
                    ? const Color(0xFFB7791F)
                    : const Color(0xFF2E7D32),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _GitGraphStatusButton(
                  changedCount: changedCount,
                  onTap: onOpenCommitGraph,
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(
                  context,
                ).refreshIndicatorSemanticLabel,
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChangesBranchSelector extends StatelessWidget {
  const _ChangesBranchSelector({
    required this.fallbackLabel,
    required this.branch,
    required this.branchesFuture,
    required this.onSwitchBranch,
  });

  final String fallbackLabel;
  final String branch;
  final Future<List<DemoGitBranchInfo>>? branchesFuture;
  final _GitBranchSwitchCallback onSwitchBranch;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DemoGitBranchInfo>>(
      future: branchesFuture,
      builder: (context, snapshot) {
        final branches = snapshot.data ?? const <DemoGitBranchInfo>[];
        final current = branches
            .where((candidate) => candidate.current && !candidate.remote)
            .firstOrNull;
        final displayBranch = (current?.name ?? branch).trim();
        final label = displayBranch.isEmpty ? fallbackLabel : displayBranch;
        final canSwitch = branches.isNotEmpty;
        final content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.account_tree_rounded,
              size: 18,
              color: _configTextSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _configTextPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (canSwitch) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: _configTextTertiary,
                size: 20,
              ),
            ],
          ],
        );
        return Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('source_control_branch_selector_button'),
              borderRadius: BorderRadius.circular(8),
              onTap: canSwitch
                  ? () async {
                      await Navigator.of(context).push<DemoGitOperationResult>(
                        MaterialPageRoute(
                          builder: (context) => _BranchPickerPage(
                            branches: branches,
                            selectedName: current?.name ?? displayBranch,
                            onSwitchBranch: onSwitchBranch,
                          ),
                        ),
                      );
                    }
                  : null,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: canSwitch ? _configSurface : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: canSwitch ? _configBorderFaint : Colors.transparent,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  child: content,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GitGraphStatusButton extends StatelessWidget {
  const _GitGraphStatusButton({
    required this.changedCount,
    required this.onTap,
  });

  final int changedCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tooltip = _gitGraphOpenTooltip(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: Tooltip(
          message: tooltip,
          child: Semantics(
            button: true,
            label: tooltip,
            child: InkWell(
              key: const Key('source_control_git_graph_button'),
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _configSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _configBorderFaint),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.account_tree_rounded,
                        size: 16,
                        color: _configTextSecondary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _sourceControlStatusLine(context, changedCount),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _configTextSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _gitGraphActionLabel(context),
                        style: const TextStyle(
                          color: _configTextPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 2),
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
          ),
        ),
      ),
    );
  }
}

class _GitGraphPage extends StatefulWidget {
  const _GitGraphPage({required this.repo, required this.client});

  final DemoRepositoryInfo repo;
  final NapaxiChatClient client;

  @override
  State<_GitGraphPage> createState() => _GitGraphPageState();
}

class _GitGraphPageState extends State<_GitGraphPage> {
  late Future<List<DemoGitCommitInfo>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = widget.client.listGitCommitHistory(widget.repo.directory);
  }

  void _refresh() {
    setState(() {
      _historyFuture = widget.client.listGitCommitHistory(
        widget.repo.directory,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _configPageBackground,
      appBar: AppBar(
        title: Text(_gitGraphTitle(context)),
        backgroundColor: _configPageBackground,
        foregroundColor: _configTextPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: MaterialLocalizations.of(
              context,
            ).refreshIndicatorSemanticLabel,
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<DemoGitCommitInfo>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done &&
              snapshot.data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _FilesMessage(
              icon: Icons.error_outline_rounded,
              title: _gitGraphLoadFailed(context),
              description: _friendlyDisplayError(snapshot.error),
            );
          }
          final commits = snapshot.data ?? const <DemoGitCommitInfo>[];
          if (commits.isEmpty) {
            return _FilesMessage(
              icon: Icons.account_tree_rounded,
              title: _gitGraphEmptyTitle(context),
              description: null,
            );
          }
          return ListView.separated(
            key: const Key('git_graph_commit_list'),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: commits.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) => _GitCommitTile(
              commit: commits[index],
              isFirst: index == 0,
              isLast: index == commits.length - 1,
              loadDiff: () => widget.client.gitCommitDiff(
                widget.repo.directory,
                commits[index].hash,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GitCommitTile extends StatefulWidget {
  const _GitCommitTile({
    required this.commit,
    required this.isFirst,
    required this.isLast,
    required this.loadDiff,
  });

  final DemoGitCommitInfo commit;
  final bool isFirst;
  final bool isLast;
  final Future<DemoGitCommitDiff> Function() loadDiff;

  @override
  State<_GitCommitTile> createState() => _GitCommitTileState();
}

class _GitCommitTileState extends State<_GitCommitTile> {
  bool _expanded = false;
  bool _loading = false;
  DemoGitCommitDiff? _diff;
  String? _error;

  Future<void> _toggle() async {
    setState(() => _expanded = !_expanded);
    if (!_expanded || _diff != null || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final diff = await widget.loadDiff();
      if (!mounted) return;
      setState(() {
        _diff = diff;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyDisplayError(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final commit = widget.commit;
    return Material(
      color: _configSurface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: Key(
          'git_graph_commit_${commit.shortHash.isEmpty ? commit.hash : commit.shortHash}',
        ),
        borderRadius: BorderRadius.circular(8),
        onTap: _toggle,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _configBorderFaint),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _GitGraphNode(
                      graph: commit.graph,
                      isFirst: widget.isFirst,
                      isLast: widget.isLast,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _GitCommitSummary(commit: commit)),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.chevron_right_rounded,
                      color: _configTextTertiary,
                    ),
                  ],
                ),
                if (_expanded)
                  Padding(
                    padding: const EdgeInsets.only(left: 38, top: 2),
                    child: _GitCommitDiffPanel(
                      loading: _loading,
                      diff: _diff,
                      error: _error,
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

class _GitCommitSummary extends StatelessWidget {
  const _GitCommitSummary({required this.commit});

  final DemoGitCommitInfo commit;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (commit.shortHash.isNotEmpty) commit.shortHash,
      if (commit.authorName.isNotEmpty) commit.authorName,
      if (commit.authoredAt != null) _formatFileDate(commit.authoredAt!),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            commit.subject.isEmpty ? commit.hash : commit.subject,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _configTextPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _configTextSecondary, fontSize: 12),
          ),
          if (commit.refs.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              commit.refs,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _configTextTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GitGraphNode extends StatelessWidget {
  const _GitGraphNode({
    required this.graph,
    required this.isFirst,
    required this.isLast,
  });

  final String graph;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 74,
      child: CustomPaint(
        painter: _GitGraphNodePainter(isFirst: isFirst, isLast: isLast),
      ),
    );
  }
}

class _GitGraphNodePainter extends CustomPainter {
  const _GitGraphNodePainter({required this.isFirst, required this.isLast});

  final bool isFirst;
  final bool isLast;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final linePaint = Paint()
      ..color = _configBorder
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (!isFirst) {
      canvas.drawLine(Offset(centerX, 0), Offset(centerX, 26), linePaint);
    }
    if (!isLast) {
      canvas.drawLine(
        Offset(centerX, 42),
        Offset(centerX, size.height),
        linePaint,
      );
    }
    canvas.drawCircle(
      Offset(centerX, 34),
      7,
      Paint()..color = const Color(0xFF2E7D32),
    );
    canvas.drawCircle(Offset(centerX, 34), 4, Paint()..color = _configSurface);
  }

  @override
  bool shouldRepaint(covariant _GitGraphNodePainter oldDelegate) {
    return oldDelegate.isFirst != isFirst || oldDelegate.isLast != isLast;
  }
}

class _GitCommitDiffPanel extends StatelessWidget {
  const _GitCommitDiffPanel({
    required this.loading,
    required this.diff,
    required this.error,
  });

  final bool loading;
  final DemoGitCommitDiff? diff;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (error != null) {
      return _DiffHint(icon: Icons.error_outline_rounded, text: error!);
    }
    final value = diff;
    if (value == null) return const SizedBox.shrink();
    if (!value.success) {
      return _DiffHint(
        icon: Icons.error_outline_rounded,
        text: value.error ?? _sourceControlDiffFailed(context),
      );
    }
    if (value.tooLarge) {
      return _DiffHint(
        icon: Icons.unfold_less_rounded,
        text: _sourceControlDiffTooLarge(context),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (value.files.isNotEmpty) _GitCommitFilesSummary(files: value.files),
        if (value.files.isNotEmpty && value.hunks.isNotEmpty)
          const SizedBox(height: 8),
        if (value.hunks.isEmpty)
          _DiffHint(
            icon: Icons.do_not_disturb_on_outlined,
            text: _sourceControlDiffEmptyHint(context),
          )
        else
          DecoratedBox(
            decoration: BoxDecoration(
              color: _configSurfaceMuted,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _configBorderFaint),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final hunk in value.hunks) _DiffHunkView(hunk: hunk),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _GitCommitFilesSummary extends StatelessWidget {
  const _GitCommitFilesSummary({required this.files});

  final List<DemoGitCommitFileChange> files;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _configSurfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (final file in files.take(12))
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.insert_drive_file_outlined,
                      size: 15,
                      color: _configTextSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        file.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _configTextPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _commitFileStat(file),
                      style: const TextStyle(
                        color: _configTextSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Actions surfaced by the [_CommitSplitButton]: the dropdown picks which one
/// the primary button performs, and tapping the primary button runs it.
enum _CommitAction { commit, commitAndPush, push, pull, sync }

/// A split button. The trailing chevron opens a menu that *selects* the active
/// action (shown on the button, with a checkmark); tapping the main body runs
/// the currently-selected action rather than triggering on dropdown pick.
class _CommitSplitButton extends StatefulWidget {
  const _CommitSplitButton({
    required this.canCommit,
    required this.canPush,
    required this.onCommit,
    required this.onCommitAndPush,
    required this.onPush,
    required this.onPull,
    required this.onSync,
  });

  final bool canCommit;
  final bool canPush;
  final VoidCallback onCommit;
  final VoidCallback onCommitAndPush;
  final Future<void> Function() onPush;
  final Future<void> Function() onPull;
  final Future<void> Function() onSync;

  @override
  State<_CommitSplitButton> createState() => _CommitSplitButtonState();
}

class _CommitSplitButtonState extends State<_CommitSplitButton> {
  _CommitAction _current = _CommitAction.commit;

  IconData _iconFor(_CommitAction action) {
    switch (action) {
      case _CommitAction.commit:
        return Icons.commit_rounded;
      case _CommitAction.commitAndPush:
        return Icons.cloud_upload_outlined;
      case _CommitAction.push:
        return Icons.upload_rounded;
      case _CommitAction.pull:
        return Icons.download_rounded;
      case _CommitAction.sync:
        return Icons.sync_rounded;
    }
  }

  String _labelFor(BuildContext context, _CommitAction action) {
    switch (action) {
      case _CommitAction.commit:
        return _sourceControlCommitLabel(context);
      case _CommitAction.commitAndPush:
        return _sourceControlCommitAndPushLabel(context);
      case _CommitAction.push:
        return _sourceControlPushLabel(context);
      case _CommitAction.pull:
        return _sourceControlPullLabel(context);
      case _CommitAction.sync:
        return _sourceControlSyncLabel(context);
    }
  }

  bool _canRun(_CommitAction action) {
    switch (action) {
      case _CommitAction.commit:
      case _CommitAction.commitAndPush:
        return widget.canCommit;
      case _CommitAction.push:
      case _CommitAction.pull:
      case _CommitAction.sync:
        return widget.canPush;
    }
  }

  void _run(_CommitAction action) {
    switch (action) {
      case _CommitAction.commit:
        widget.onCommit();
      case _CommitAction.commitAndPush:
        widget.onCommitAndPush();
      case _CommitAction.push:
        widget.onPush();
      case _CommitAction.pull:
        widget.onPull();
      case _CommitAction.sync:
        widget.onSync();
    }
  }

  PopupMenuItem<_CommitAction> _menuItem(
    BuildContext context, {
    required Key key,
    required _CommitAction value,
  }) {
    return PopupMenuItem<_CommitAction>(
      key: key,
      value: value,
      child: Row(
        children: [
          Icon(_iconFor(value), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _labelFor(context, value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (value == _current)
            const Icon(
              Icons.check_rounded,
              size: 18,
              color: _configTextSecondary,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final runnable = _canRun(_current);
    final background = runnable ? _configTextPrimary : _configSurfaceMuted;
    final foreground = runnable ? Colors.white : _configTextTertiary;
    final divider = runnable
        ? Colors.white.withValues(alpha: 0.35)
        : _configBorderFaint;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              key: const Key('commit_button'),
              onTap: runnable ? () => _run(_current) : null,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_iconFor(_current), size: 18, color: foreground),
                    const SizedBox(width: 6),
                    Text(
                      _labelFor(context, _current),
                      style: TextStyle(
                        color: foreground,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(height: 18, width: 1, color: divider),
            PopupMenuButton<_CommitAction>(
              key: const Key('commit_actions_menu'),
              tooltip: _sourceControlMoreActionsTooltip(context),
              position: PopupMenuPosition.under,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              // Selecting only changes the active action shown on the button;
              // the action runs when the main body is tapped.
              onSelected: (value) => setState(() => _current = value),
              itemBuilder: (context) => <PopupMenuItem<_CommitAction>>[
                _menuItem(
                  context,
                  key: const Key('commit_action_commit'),
                  value: _CommitAction.commit,
                ),
                _menuItem(
                  context,
                  key: const Key('commit_action_commit_and_push'),
                  value: _CommitAction.commitAndPush,
                ),
                _menuItem(
                  context,
                  key: const Key('commit_action_push'),
                  value: _CommitAction.push,
                ),
                _menuItem(
                  context,
                  key: const Key('commit_action_pull'),
                  value: _CommitAction.pull,
                ),
                _menuItem(
                  context,
                  key: const Key('commit_action_sync'),
                  value: _CommitAction.sync,
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 22,
                  color: foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangeGroupHeader extends StatelessWidget {
  const _ChangeGroupHeader({
    super.key,
    required this.title,
    required this.count,
    required this.actionLabel,
    required this.onAction,
    this.busy = false,
  });

  final String title;
  final int count;
  final String actionLabel;
  final VoidCallback onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _configTextSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: const TextStyle(
              color: _configTextTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: busy ? null : onAction,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _ChangeRow extends StatefulWidget {
  const _ChangeRow({
    super.key,
    required this.entry,
    required this.loadDiff,
    this.busy = false,
    this.onStage,
    this.onUnstage,
    this.onDiscard,
  });

  final DemoGitChangeEntry entry;
  final Future<DemoGitFileDiff> Function() loadDiff;
  final bool busy;
  final Future<void> Function()? onStage;
  final Future<void> Function()? onUnstage;
  final Future<void> Function()? onDiscard;

  @override
  State<_ChangeRow> createState() => _ChangeRowState();
}

class _ChangeRowState extends State<_ChangeRow> {
  bool _expanded = false;
  bool _loading = false;
  DemoGitFileDiff? _diff;
  String? _error;

  DemoGitChangeEntry get _entry => widget.entry;

  Future<void> _toggle() async {
    if (_expanded && _diff != null) {
      setState(() => _expanded = false);
      return;
    }
    if (_diff == null && !_loading) {
      setState(() {
        _expanded = true;
        _loading = true;
        // Clear any stale error from a previous failed load so the inline diff
        // panel (which checks `error != null` before `diff`) doesn't keep
        // showing the old error after a successful reload.
        _error = null;
      });
      try {
        final diff = await widget.loadDiff();
        if (!mounted) return;
        setState(() {
          _diff = diff;
          _loading = false;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = _friendlyDisplayError(error);
        });
      }
    } else {
      setState(() => _expanded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _entry.oldPath != null && _entry.oldPath!.isNotEmpty
        ? '${_entry.oldPath} → ${_entry.path}'
        : _entry.path;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: _configSurface,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 2, 5),
              child: Row(
                children: [
                  _GitStatusBadge(category: _entry.category),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _pathName(_entry.path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _configTextPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _configTextSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            _DiffStat(entry: _entry),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (widget.onStage != null)
                    IconButton(
                      key: Key('source_control_stage_${_entry.path}'),
                      tooltip: _sourceControlStageTooltip(context),
                      onPressed: widget.busy ? null : widget.onStage,
                      icon: const Icon(Icons.add_rounded, size: 20),
                    ),
                  if (widget.onUnstage != null)
                    IconButton(
                      key: Key('source_control_unstage_${_entry.path}'),
                      tooltip: _sourceControlUnstageTooltip(context),
                      onPressed: widget.busy ? null : widget.onUnstage,
                      icon: const Icon(Icons.remove_rounded, size: 20),
                    ),
                  if (widget.onDiscard != null)
                    IconButton(
                      key: Key('source_control_discard_${_entry.path}'),
                      tooltip: _sourceControlDiscardTooltip(context),
                      onPressed: widget.busy ? null : widget.onDiscard,
                      icon: const Icon(
                        Icons.undo_rounded,
                        size: 20,
                        color: Color(0xFFC62828),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(left: 2, right: 4),
                    child: Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.chevron_right_rounded,
                      size: 20,
                      color: _configTextTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: _ChangeDiffPanel(
              entry: _entry,
              loading: _loading,
              diff: _diff,
              error: _error,
            ),
          ),
      ],
    );
  }
}

/// Inline unified-diff panel rendered under an expanded [_ChangeRow].
class _ChangeDiffPanel extends StatelessWidget {
  const _ChangeDiffPanel({
    required this.entry,
    required this.loading,
    required this.diff,
    required this.error,
  });

  final DemoGitChangeEntry entry;
  final bool loading;
  final DemoGitFileDiff? diff;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (error != null) {
      return _DiffHint(icon: Icons.error_outline_rounded, text: error!);
    }
    final d = diff;
    if (d == null) return const SizedBox.shrink();
    if (d.tooLarge) {
      return _DiffHint(
        icon: Icons.unfold_less_rounded,
        text: _sourceControlDiffTooLarge(context),
      );
    }
    if (!d.success) {
      return _DiffHint(
        icon: Icons.error_outline_rounded,
        text: d.error ?? _sourceControlDiffFailed(context),
      );
    }
    if (d.empty || d.hunks.isEmpty) {
      if (entry.area == DemoGitChangeArea.untracked) {
        return _DiffHint(
          icon: Icons.note_add_outlined,
          text: _sourceControlUntrackedDiffHint(context),
        );
      }
      return _DiffHint(
        icon: Icons.do_not_disturb_on_outlined,
        text: _sourceControlDiffEmptyHint(context),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _configSurfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _configBorderFaint),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final hunk in d.hunks) _DiffHunkView(hunk: hunk)],
        ),
      ),
    );
  }
}

class _DiffHint extends StatelessWidget {
  const _DiffHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _configSurfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 16, color: _configTextSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: _configTextSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiffHunkView extends StatelessWidget {
  const _DiffHunkView({required this.hunk});

  final DemoDiffHunk hunk;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: _configSelectedSurface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
            child: Text(
              hunk.header,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: _configTextSecondary,
              ),
            ),
          ),
        ),
        // Lazy-build the hunk body: a large diff (>500 lines is capped, but a
        // few hundred-line hunks still cost a frame each when eagerly built).
        // shrinkWrap + NeverScrollable lets the outer changes ListView drive
        // the viewport while only materializing the visible lines.
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: hunk.lines.length,
          itemBuilder: (context, index) =>
              _DiffLineView(line: hunk.lines[index]),
        ),
      ],
    );
  }
}

class _DiffLineView extends StatelessWidget {
  const _DiffLineView({required this.line});

  final DemoDiffLine line;

  @override
  Widget build(BuildContext context) {
    final isAdd = line.type == DemoDiffLineType.added;
    final isDel = line.type == DemoDiffLineType.removed;
    final Color bg;
    final Color accent;
    final String prefix;
    if (isAdd) {
      bg = const Color(0xFFE6FFEC);
      accent = const Color(0xFF1A7F37);
      prefix = '+';
    } else if (isDel) {
      bg = const Color(0xFFFFEBE9);
      accent = const Color(0xFFC62828);
      prefix = '-';
    } else if (line.type == DemoDiffLineType.meta) {
      bg = Colors.transparent;
      accent = _configTextTertiary;
      prefix = '';
    } else {
      bg = Colors.transparent;
      accent = _configTextTertiary;
      prefix = ' ';
    }
    return ColoredBox(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 30,
              child: Text(
                line.oldLine == null ? '' : '${line.oldLine}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  height: 1.45,
                  color: isDel ? accent : _configTextTertiary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 30,
              child: Text(
                line.newLine == null ? '' : '${line.newLine}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  height: 1.45,
                  color: isAdd ? accent : _configTextTertiary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 10,
              child: Text(
                prefix,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.45,
                  color: accent,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                line.text.isEmpty ? ' ' : line.text,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.45,
                  color: line.type == DemoDiffLineType.meta
                      ? _configTextTertiary
                      : _configTextPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiffStat extends StatelessWidget {
  const _DiffStat({required this.entry});

  final DemoGitChangeEntry entry;

  @override
  Widget build(BuildContext context) {
    if (entry.area == DemoGitChangeArea.untracked) {
      return Text(
        _sourceControlUntrackedLabel(context),
        style: const TextStyle(
          color: _configTextTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    if (entry.additions == null && entry.deletions == null) {
      return Text(
        _sourceControlBinaryLabel(context),
        style: const TextStyle(
          color: _configTextTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '+${entry.additions ?? 0}',
          style: const TextStyle(
            color: Color(0xFF2E7D32),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '−${entry.deletions ?? 0}',
          style: const TextStyle(
            color: Color(0xFFC62828),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _RepoWorkbenchHeader extends StatelessWidget {
  const _RepoWorkbenchHeader({
    required this.repositories,
    required this.selected,
    required this.contribution,
    required this.onChooseProject,
  });

  final List<DemoRepositoryInfo> repositories;
  final DemoRepositoryInfo selected;
  final sdk.NapaxiScenarioUiContribution contribution;
  final VoidCallback onChooseProject;

  @override
  Widget build(BuildContext context) {
    final projectMeta = _projectMetaLabel(selected);
    return Material(
      color: _configSurface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: const Key('project_selector_button'),
        borderRadius: BorderRadius.circular(8),
        onTap: onChooseProject,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _configBorderFaint),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(
                  _repoContributionIcon(contribution),
                  color: _configTextSecondary,
                  size: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          selected.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _configTextPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (projectMeta.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            projectMeta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _configTextSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _projectCountLabel(context, repositories.length),
                  style: const TextStyle(
                    color: _configTextTertiary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right_rounded,
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

class _ProjectPickerPage extends StatefulWidget {
  const _ProjectPickerPage({
    required this.repositories,
    required this.selectedDirectory,
  });

  final List<DemoRepositoryInfo> repositories;
  final String selectedDirectory;

  @override
  State<_ProjectPickerPage> createState() => _ProjectPickerPageState();
}

class _ProjectPickerPageState extends State<_ProjectPickerPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleQueryChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleQueryChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleQueryChanged() {
    final next = _searchController.text.trim();
    if (next == _query) return;
    setState(() => _query = next);
  }

  bool _matches(DemoRepositoryInfo repository, String normalizedQuery) {
    if (normalizedQuery.isEmpty) return true;
    final searchable = [
      repository.name,
      repository.directory,
      repository.absolutePath,
      repository.locationLabel,
    ].join('\n').toLowerCase();
    return searchable.contains(normalizedQuery);
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.toLowerCase();
    final filtered = widget.repositories
        .where((repository) => _matches(repository, normalizedQuery))
        .toList(growable: false);
    return Scaffold(
      backgroundColor: _configPageBackground,
      appBar: AppBar(
        title: Text(_projectPickerTitle(context)),
        backgroundColor: _configPageBackground,
        foregroundColor: _configTextPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: TextField(
              key: const Key('project_picker_search_field'),
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: _configInputDecoration(
                labelText: _projectPickerSearchLabel(context),
                hintText: _projectPickerSearchHint(context),
                suffixIcon: _query.isEmpty
                    ? const Icon(Icons.search_rounded)
                    : IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).deleteButtonTooltip,
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              itemCount: filtered.isEmpty ? 1 : filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                if (filtered.isEmpty) {
                  return _EmptyDirectoryTile(
                    title: _projectPickerEmptyTitle(context),
                    description: _projectPickerEmptyDescription(context),
                  );
                }
                final repository = filtered[index];
                return _ProjectPickerTile(
                  repository: repository,
                  selected: repository.directory == widget.selectedDirectory,
                  onTap: () => Navigator.of(context).pop(repository),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectPickerTile extends StatelessWidget {
  const _ProjectPickerTile({
    required this.repository,
    required this.selected,
    required this.onTap,
  });

  final DemoRepositoryInfo repository;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = _projectMetaLabel(repository);
    return Material(
      color: selected ? _configSelectedSurface : _configSurface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: Key('project_picker_item_${repository.directory}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? _configBorder : _configBorderFaint,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.account_tree_rounded,
                  color: _configTextSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        repository.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _configTextPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _configTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.chevron_right_rounded,
                  color: selected ? _configTextPrimary : _configTextTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RepoStatusPanel extends StatelessWidget {
  const _RepoStatusPanel({
    required this.future,
    required this.branchesFuture,
    required this.remotesFuture,
    required this.lastOperation,
    required this.onSwitchBranch,
    required this.onRefresh,
    required this.onFetch,
    required this.onEditRemote,
    required this.onAddRemote,
  });

  final Future<DemoGitRepositoryStatus>? future;
  final Future<List<DemoGitBranchInfo>>? branchesFuture;
  final Future<List<DemoGitRemoteInfo>>? remotesFuture;
  final DemoGitOperationResult? lastOperation;
  final _GitBranchSwitchCallback onSwitchBranch;
  final VoidCallback onRefresh;
  final ValueChanged<String?> onFetch;
  final ValueChanged<DemoGitRemoteInfo> onEditRemote;
  final VoidCallback onAddRemote;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _configSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: FutureBuilder<DemoGitRepositoryStatus>(
          future: future,
          builder: (context, snapshot) {
            final status = snapshot.data;
            final loading = snapshot.connectionState != ConnectionState.done;
            final changedFiles = status?.changedFiles ?? const <String>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.commit_rounded,
                      color: _configTextSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatusBranchTitle(
                        status: status,
                        loading: loading,
                        branchesFuture: branchesFuture,
                        onSwitchBranch: onSwitchBranch,
                      ),
                    ),
                    IconButton(
                      key: const Key('repo_workbench_status_refresh'),
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).refreshIndicatorSemanticLabel,
                      onPressed: loading ? null : onRefresh,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                if (loading) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 2),
                ] else if (snapshot.hasError || status?.success == false) ...[
                  const SizedBox(height: 6),
                  Text(
                    _repoStatusError(context, snapshot.error, status),
                    style: const TextStyle(
                      color: _configTextSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  _ChangedFilesSummary(count: changedFiles.length),
                ],
                if (lastOperation != null && !lastOperation!.success) ...[
                  const SizedBox(height: 8),
                  _GitOperationErrorRow(result: lastOperation!),
                ],
                const SizedBox(height: 10),
                _RemoteSelector(
                  future: remotesFuture,
                  onFetch: onFetch,
                  onEditRemote: onEditRemote,
                  onAddRemote: onAddRemote,
                  compact: true,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatusBranchTitle extends StatelessWidget {
  const _StatusBranchTitle({
    required this.status,
    required this.loading,
    required this.branchesFuture,
    required this.onSwitchBranch,
  });

  final DemoGitRepositoryStatus? status;
  final bool loading;
  final Future<List<DemoGitBranchInfo>>? branchesFuture;
  final _GitBranchSwitchCallback onSwitchBranch;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DemoGitBranchInfo>>(
      future: branchesFuture,
      builder: (context, snapshot) {
        final branches = snapshot.data ?? const <DemoGitBranchInfo>[];
        final currentBranch = branches
            .where((branch) => branch.current && !branch.remote)
            .firstOrNull;
        final canSwitch = !loading && branches.isNotEmpty;
        final title = loading
            ? _repoStatusTitle(context, status, loading)
            : _branchStatusTitle(context, currentBranch?.name, status);
        if (!canSwitch) {
          return Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _configTextPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          );
        }
        return InkWell(
          key: const Key('git_branch_selector_button'),
          borderRadius: BorderRadius.circular(6),
          onTap: () async {
            // Detached HEAD (or a remote-only branch list) has no `current`
            // local branch; prefer no preselection over highlighting an
            // arbitrary (often remote) branch as "current".
            final current = branches
                .where((branch) => branch.current && !branch.remote)
                .firstOrNull;
            await Navigator.of(context).push<DemoGitOperationResult>(
              MaterialPageRoute(
                builder: (context) => _BranchPickerPage(
                  branches: branches,
                  selectedName: current?.name ?? '',
                  onSwitchBranch: onSwitchBranch,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                const SizedBox(width: 4),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: _configTextTertiary,
                  size: 20,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChangedFilesSummary extends StatelessWidget {
  const _ChangedFilesSummary({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.edit_note_rounded,
          color: _configTextTertiary,
          size: 18,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _repoChangedFilesLabel(context, count),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _configTextSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _GitOperationErrorRow extends StatelessWidget {
  const _GitOperationErrorRow({required this.result});

  final DemoGitOperationResult result;

  @override
  Widget build(BuildContext context) {
    final message = result.error ?? _gitOperationFailedMessage(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _configSurfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: _configTextSecondary,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _configTextSecondary,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteSelector extends StatelessWidget {
  const _RemoteSelector({
    required this.future,
    required this.onFetch,
    required this.onEditRemote,
    required this.onAddRemote,
    this.compact = false,
  });

  final Future<List<DemoGitRemoteInfo>>? future;
  final ValueChanged<String?> onFetch;
  final ValueChanged<DemoGitRemoteInfo> onEditRemote;
  final VoidCallback onAddRemote;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DemoGitRemoteInfo>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _GitControlLoadingRow();
        }
        final remotes = snapshot.data ?? const <DemoGitRemoteInfo>[];
        if (snapshot.hasError) {
          return _GitControlMessageRow(
            icon: Icons.cloud_off_rounded,
            text: _gitRemotesLoadFailed(context, snapshot.error),
            action: IconButton(
              tooltip: _gitAddRemoteTooltip(context),
              onPressed: onAddRemote,
              icon: const Icon(Icons.add_rounded),
            ),
          );
        }
        if (compact) {
          return _CompactRemoteRow(
            remotes: remotes,
            onFetch: onFetch,
            onEditRemote: onEditRemote,
            onAddRemote: onAddRemote,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact) const Divider(height: 1, color: _configBorderFaint),
            if (compact) const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _gitRemotesTitle(context),
                    style: const TextStyle(
                      color: _configTextSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('git_fetch_button'),
                  tooltip: _gitFetchTooltip(context),
                  onPressed: () => onFetch(null),
                  icon: const Icon(Icons.cloud_sync_rounded),
                ),
                IconButton(
                  key: const Key('git_add_remote_button'),
                  tooltip: _gitAddRemoteTooltip(context),
                  onPressed: onAddRemote,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            if (remotes.isEmpty)
              _GitControlMessageRow(
                icon: Icons.cloud_queue_rounded,
                text: _gitNoRemotesLabel(context),
              )
            else
              for (final remote in remotes.take(3)) ...[
                const SizedBox(height: 6),
                _RemoteTile(
                  remote: remote,
                  onTap: () => onEditRemote(remote),
                  onFetch: () => onFetch(remote.name),
                ),
              ],
          ],
        );
      },
    );
  }
}

class _CompactRemoteRow extends StatelessWidget {
  const _CompactRemoteRow({
    required this.remotes,
    required this.onFetch,
    required this.onEditRemote,
    required this.onAddRemote,
  });

  final List<DemoGitRemoteInfo> remotes;
  final ValueChanged<String?> onFetch;
  final ValueChanged<DemoGitRemoteInfo> onEditRemote;
  final VoidCallback onAddRemote;

  @override
  Widget build(BuildContext context) {
    final remote = remotes.isEmpty ? null : remotes.first;
    final url = remote == null
        ? ''
        : remote.fetchUrl.isNotEmpty
        ? remote.fetchUrl
        : remote.pushUrl;
    return Column(
      children: [
        const Divider(height: 1, color: _configBorderFaint),
        SizedBox(
          height: 42,
          child: Row(
            children: [
              const Icon(
                Icons.cloud_queue_rounded,
                color: _configTextSecondary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: remote == null
                    ? Text(
                        _gitNoRemotesLabel(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _configTextSecondary,
                          fontSize: 12,
                        ),
                      )
                    : InkWell(
                        key: Key('git_remote_${remote.name}'),
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => onEditRemote(remote),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Text(
                                remote.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _configTextPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (url.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    url,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _configTextSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
              ),
              IconButton(
                key: const Key('git_fetch_button'),
                tooltip: remote == null
                    ? _gitFetchTooltip(context)
                    : _gitFetchRemoteTooltip(context, remote.name),
                onPressed: () => onFetch(remote?.name),
                icon: const Icon(Icons.sync_rounded, size: 20),
              ),
              IconButton(
                key: const Key('git_add_remote_button'),
                tooltip: _gitAddRemoteTooltip(context),
                onPressed: onAddRemote,
                icon: const Icon(Icons.add_rounded, size: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RemoteTile extends StatelessWidget {
  const _RemoteTile({
    required this.remote,
    required this.onTap,
    required this.onFetch,
  });

  final DemoGitRemoteInfo remote;
  final VoidCallback onTap;
  final VoidCallback onFetch;

  @override
  Widget build(BuildContext context) {
    final url = remote.fetchUrl.isNotEmpty ? remote.fetchUrl : remote.pushUrl;
    return Material(
      color: _configSurfaceMuted,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: Key('git_remote_${remote.name}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              const Icon(
                Icons.cloud_queue_rounded,
                color: _configTextSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      remote.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _configTextPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (url.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _configTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: _gitFetchRemoteTooltip(context, remote.name),
                onPressed: onFetch,
                icon: const Icon(Icons.sync_rounded),
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

class _GitControlLoadingRow extends StatelessWidget {
  const _GitControlLoadingRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: LinearProgressIndicator(minHeight: 2),
    );
  }
}

class _GitControlMessageRow extends StatelessWidget {
  const _GitControlMessageRow({
    required this.icon,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _configSurfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            Icon(icon, color: _configTextSecondary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _configTextSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

class _BranchPickerPage extends StatefulWidget {
  const _BranchPickerPage({
    required this.branches,
    required this.selectedName,
    required this.onSwitchBranch,
  });

  final List<DemoGitBranchInfo> branches;
  final String selectedName;
  final _GitBranchSwitchCallback onSwitchBranch;

  @override
  State<_BranchPickerPage> createState() => _BranchPickerPageState();
}

class _BranchPickerPageState extends State<_BranchPickerPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _switchingBranchName;
  DemoGitOperationResult? _lastSwitchError;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleQueryChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleQueryChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleQueryChanged() {
    final next = _searchController.text.trim();
    if (next == _query) return;
    setState(() => _query = next);
  }

  Future<void> _switchBranch(DemoGitBranchInfo branch) async {
    if (_switchingBranchName != null) return;
    if (branch.current) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _switchingBranchName = branch.name;
      _lastSwitchError = null;
    });
    final result = await widget.onSwitchBranch(branch);
    if (!mounted) return;
    if (result.success) {
      Navigator.of(context).pop(result);
      return;
    }
    setState(() {
      _switchingBranchName = null;
      _lastSwitchError = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final filtered = widget.branches
        .where(
          (branch) =>
              query.isEmpty ||
              branch.name.toLowerCase().contains(query) ||
              branch.upstream.toLowerCase().contains(query),
        )
        .toList(growable: false);
    return Scaffold(
      backgroundColor: _configPageBackground,
      appBar: AppBar(
        title: Text(_branchPickerTitle(context)),
        backgroundColor: _configPageBackground,
        foregroundColor: _configTextPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: TextField(
              key: const Key('git_branch_search_field'),
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: _configInputDecoration(
                labelText: _branchPickerSearchLabel(context),
                hintText: _branchPickerSearchHint(context),
                suffixIcon: _query.isEmpty
                    ? const Icon(Icons.search_rounded)
                    : IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).deleteButtonTooltip,
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          if (_lastSwitchError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: _GitOperationErrorRow(result: _lastSwitchError!),
            ),
          if (_switchingBranchName != null)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              itemCount: filtered.isEmpty ? 1 : filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                if (filtered.isEmpty) {
                  return _EmptyDirectoryTile(
                    title: _branchPickerEmptyTitle(context),
                    description: _branchPickerEmptyDescription(context),
                  );
                }
                final branch = filtered[index];
                final switching = _switchingBranchName == branch.name;
                return _BranchPickerTile(
                  branch: branch,
                  selected: branch.name == widget.selectedName,
                  switching: switching,
                  onTap: _switchingBranchName == null
                      ? () => _switchBranch(branch)
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchPickerTile extends StatelessWidget {
  const _BranchPickerTile({
    required this.branch,
    required this.selected,
    required this.switching,
    required this.onTap,
  });

  final DemoGitBranchInfo branch;
  final bool selected;
  final bool switching;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      branch.remote
          ? _gitRemoteBranchLabel(context)
          : _gitLocalBranchLabel(context),
      if (branch.upstream.isNotEmpty) branch.upstream,
    ].join(' · ');
    return Material(
      color: selected ? _configSelectedSurface : _configSurface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: Key('git_branch_${branch.name}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? _configBorder : _configBorderFaint,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  branch.remote
                      ? Icons.cloud_queue_rounded
                      : Icons.call_split_rounded,
                  color: _configTextSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        branch.name,
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
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _configTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (switching)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.chevron_right_rounded,
                    color: selected ? _configTextPrimary : _configTextTertiary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RemoteEditorPage extends StatefulWidget {
  const _RemoteEditorPage({
    required this.initialRemote,
    required this.onSave,
    required this.onRemove,
  });

  final DemoGitRemoteInfo? initialRemote;
  final Future<DemoGitOperationResult> Function(String name, String url) onSave;
  final Future<DemoGitOperationResult> Function()? onRemove;

  @override
  State<_RemoteEditorPage> createState() => _RemoteEditorPageState();
}

class _RemoteEditorPageState extends State<_RemoteEditorPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final remote = widget.initialRemote;
    _nameController = TextEditingController(text: remote?.name ?? 'origin');
    _urlController = TextEditingController(
      text: remote?.fetchUrl.isNotEmpty == true
          ? remote!.fetchUrl
          : remote?.pushUrl ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await widget.onSave(
      _nameController.text.trim(),
      _urlController.text.trim(),
    );
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  Future<void> _remove() async {
    final onRemove = widget.onRemove;
    if (_busy || onRemove == null) return;
    setState(() => _busy = true);
    final result = await onRemove();
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initialRemote != null;
    return Scaffold(
      backgroundColor: _configPageBackground,
      appBar: AppBar(
        title: Text(_remoteEditorTitle(context, editing)),
        backgroundColor: _configPageBackground,
        foregroundColor: _configTextPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            key: const Key('git_remote_save_button'),
            tooltip: _remoteEditorSaveTooltip(context),
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.check_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
        children: [
          TextField(
            key: const Key('git_remote_name_field'),
            controller: _nameController,
            enabled: !editing && !_busy,
            textInputAction: TextInputAction.next,
            decoration: _configInputDecoration(
              labelText: _remoteEditorNameLabel(context),
              hintText: 'origin',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('git_remote_url_field'),
            controller: _urlController,
            enabled: !_busy,
            textInputAction: TextInputAction.done,
            decoration: _configInputDecoration(
              labelText: _remoteEditorUrlLabel(context),
              hintText: 'https://github.com/example/project.git',
            ),
            onSubmitted: (_) => _save(),
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (editing) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const Key('git_remote_remove_button'),
              style: FilledButton.styleFrom(
                backgroundColor: _configTextPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _busy ? null : _remove,
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(_remoteEditorRemoveLabel(context)),
            ),
          ],
        ],
      ),
    );
  }
}

class _RepoChildrenView extends StatelessWidget {
  const _RepoChildrenView({
    required this.future,
    required this.currentDirectory,
    required this.searchQuery,
    required this.onParent,
    required this.onOpen,
    required this.onRefresh,
  });

  final Future<List<DemoRepositoryFileItem>>? future;
  final String currentDirectory;
  final String searchQuery;
  final VoidCallback onParent;
  final ValueChanged<DemoRepositoryFileItem> onOpen;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DemoRepositoryFileItem>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _FilesMessage(
            icon: Icons.error_outline_rounded,
            title: _repoWorkbenchLoadFailed(context, snapshot.error),
            description: null,
            action: IconButton(
              tooltip: MaterialLocalizations.of(
                context,
              ).refreshIndicatorSemanticLabel,
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          );
        }

        final files = snapshot.data ?? const <DemoRepositoryFileItem>[];
        final hasParent = currentDirectory.isNotEmpty && searchQuery.isEmpty;
        final showEmpty = files.isEmpty;
        // The client caps the listing at [_kRepoListLimit]; filling the whole
        // page means the directory likely has more entries than were returned.
        final showLimitHint = files.length >= _kRepoListLimit;
        final count =
            files.length +
            (hasParent ? 1 : 0) +
            (showEmpty ? 1 : 0) +
            (showLimitHint ? 1 : 0);

        return RefreshIndicator(
          onRefresh: () async => onRefresh(),
          child: ListView.separated(
            key: const Key('repo_workbench_file_list'),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              var cursor = index;
              if (hasParent) {
                if (cursor == 0) {
                  return _ParentDirectoryTile(
                    directory: currentDirectory,
                    onTap: onParent,
                  );
                }
                cursor -= 1;
              }
              if (showEmpty) {
                return _EmptyDirectoryTile(
                  title: _repoWorkbenchNoFilesTitle(context),
                  description: _repoWorkbenchNoFilesDescription(context),
                );
              }
              if (cursor < files.length) {
                final item = files[cursor];
                return _RepoFileTile(item: item, onTap: () => onOpen(item));
              }
              return _RepoLimitHintTile(searching: searchQuery.isNotEmpty);
            },
          ),
        );
      },
    );
  }
}

class _RepoFileTile extends StatelessWidget {
  const _RepoFileTile({required this.item, required this.onTap});

  final DemoRepositoryFileItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (item.relativePath != item.name) item.relativePath,
      if (!item.isDirectory && item.sizeBytes != null)
        _formatFileSize(item.sizeBytes!),
      if (item.modified != null) _formatFileDate(item.modified!),
    ].join(' · ');

    return Material(
      color: _configSurface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: Key('repo_file_${item.relativePath}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                item.isDirectory
                    ? Icons.folder_rounded
                    : _repoFileIcon(item.name, item.mimeType),
                color: _configTextSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _configTextPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _configTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
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

class _RepoLimitHintTile extends StatelessWidget {
  const _RepoLimitHintTile({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _configSurfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          _repoLimitHint(context, searching),
          textAlign: TextAlign.center,
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

String _pathName(String path) {
  final normalized = path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  if (normalized.isEmpty) return path;
  return normalized.split('/').last;
}

bool _isIgnoredRepoBrowserName(String name) {
  const ignored = {
    '.git',
    '.dart_tool',
    '.gradle',
    '.idea',
    '.pub-cache',
    '.swiftpm',
    '.vscode',
    '.build',
    'DerivedData',
    'Pods',
    'build',
    'coverage',
    'node_modules',
    'target',
  };
  return ignored.contains(name);
}

Future<DateTime> _entityModified(FileSystemEntity entity) async {
  try {
    return (await entity.stat()).modified;
  } catch (_) {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

String? _safeRepoRelativePath(String value) {
  final normalized = value.trim().replaceAll('\\', '/');
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      normalized.contains('://') ||
      normalized.contains('\u0000')) {
    return null;
  }
  final parts = <String>[];
  for (final rawPart in normalized.split('/')) {
    final part = rawPart.trim();
    if (part.isEmpty || part == '.') continue;
    if (part == '..') return null;
    parts.add(part);
  }
  return parts.isEmpty ? null : parts.join('/');
}

String _relativePath(String root, String path) {
  final normalizedRoot = root
      .replaceAll('\\', '/')
      .replaceAll(RegExp(r'/+$'), '');
  final normalizedPath = path.replaceAll('\\', '/');
  if (normalizedPath == normalizedRoot) return '';
  final prefix = '$normalizedRoot/';
  if (normalizedPath.startsWith(prefix)) {
    return normalizedPath.substring(prefix.length);
  }
  return _pathName(path);
}

String _repoMimeType(String name) {
  final lower = name.toLowerCase();
  final extension = lower.contains('.') ? lower.split('.').last : '';
  if (const {'jpg', 'jpeg'}.contains(extension)) return 'image/jpeg';
  if (const {'png', 'gif', 'webp', 'bmp'}.contains(extension)) {
    return 'image/$extension';
  }
  if (const {'svg'}.contains(extension)) return 'image/svg+xml';
  if (const {'html', 'htm'}.contains(extension)) return 'text/html';
  if (const {'json'}.contains(extension)) return 'application/json';
  if (const {'yaml', 'yml'}.contains(extension)) return 'application/x-yaml';
  if (const {'toml'}.contains(extension)) return 'application/toml';
  if (const {
        'cfg',
        'conf',
        'css',
        'csv',
        'dart',
        'gradle',
        'java',
        'js',
        'kt',
        'kts',
        'log',
        'md',
        'plist',
        'properties',
        'rs',
        'sh',
        'swift',
        'ts',
        'txt',
        'xml',
      }.contains(extension) ||
      const {
        'dockerfile',
        'gemfile',
        'makefile',
        'podfile',
        'settings.gradle',
      }.contains(lower)) {
    return 'text/plain';
  }
  return 'application/octet-stream';
}

IconData _repoContributionIcon(sdk.NapaxiScenarioUiContribution contribution) {
  return switch (contribution.icon.trim().toLowerCase()) {
    'folder_git' || 'git' => Icons.account_tree_rounded,
    'code' => Icons.code_rounded,
    _ => Icons.folder_open_rounded,
  };
}

IconData _repoFileIcon(String name, String? mimeType) {
  final type = (mimeType ?? '').toLowerCase();
  if (type.startsWith('image/')) return Icons.image_rounded;
  if (type == 'text/html') return Icons.web_asset_rounded;
  final extension = name.contains('.')
      ? name.split('.').last.toLowerCase()
      : '';
  if (const {
    'dart',
    'kt',
    'java',
    'swift',
    'rs',
    'js',
    'ts',
  }.contains(extension)) {
    return Icons.code_rounded;
  }
  return Icons.description_rounded;
}

String _repoWorkbenchTitle(
  BuildContext context,
  sdk.NapaxiScenarioUiContribution contribution,
) {
  if (_AppLanguageScope.languageOf(context) == AppLanguage.chinese) {
    return '项目';
  }
  final title = contribution.title.trim();
  if (title.isEmpty || title.toLowerCase() == 'repositories') {
    return 'Projects';
  }
  return title;
}

String _gitRemotesTitle(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? 'Remote'
      : 'Remotes';
}

String _gitRemotesLoadFailed(BuildContext context, Object? error) {
  final message = _friendlyDisplayError(error);
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? 'Remote 加载失败：$message'
      : 'Remote load failed: $message';
}

String _gitNoRemotesLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '还没有 remote'
      : 'No remotes configured';
}

String _gitFetchTooltip(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '拉取 remote'
      : 'Fetch remotes';
}

String _gitFetchRemoteTooltip(BuildContext context, String remote) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '拉取 $remote'
      : 'Fetch $remote';
}

String _gitAddRemoteTooltip(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '添加 remote'
      : 'Add remote';
}

String _branchPickerTitle(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '选择分支'
      : 'Select Branch';
}

String _branchPickerSearchLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '搜索分支'
      : 'Search branches';
}

String _branchPickerSearchHint(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '分支名或 upstream'
      : 'Branch name or upstream';
}

String _branchPickerEmptyTitle(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '没有匹配分支'
      : 'No matching branches';
}

String _branchPickerEmptyDescription(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '换个关键词再试。'
      : 'Try another keyword.';
}

String _gitLocalBranchLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '本地'
      : 'Local';
}

String _gitRemoteBranchLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '远程'
      : 'Remote';
}

String _remoteEditorTitle(BuildContext context, bool editing) {
  if (_AppLanguageScope.languageOf(context) == AppLanguage.chinese) {
    return editing ? '编辑 Remote' : '添加 Remote';
  }
  return editing ? 'Edit Remote' : 'Add Remote';
}

String _remoteEditorNameLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? 'Remote 名称'
      : 'Remote name';
}

String _remoteEditorUrlLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? 'Remote URL'
      : 'Remote URL';
}

String _remoteEditorSaveTooltip(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '保存 remote'
      : 'Save remote';
}

String _remoteEditorRemoveLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '删除 Remote'
      : 'Remove Remote';
}

String _gitOperationSuccessMessage(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? 'Git 操作完成'
      : 'Git operation completed';
}

String _gitOperationFailedMessage(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? 'Git 操作失败'
      : 'Git operation failed';
}

String _projectPickerTitle(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '选择项目'
      : 'Select Project';
}

String _projectPickerSearchLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '搜索项目'
      : 'Search projects';
}

String _projectPickerSearchHint(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '项目名、目录或位置'
      : 'Project name, directory, or location';
}

String _projectPickerEmptyTitle(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '没有匹配项目'
      : 'No matching projects';
}

String _projectPickerEmptyDescription(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '换个关键词再试。'
      : 'Try another keyword.';
}

String _projectCountLabel(BuildContext context, int count) {
  if (_AppLanguageScope.languageOf(context) == AppLanguage.chinese) {
    return '$count 个';
  }
  return count == 1 ? '1 project' : '$count projects';
}

String _projectMetaLabel(DemoRepositoryInfo repository) {
  final parts = <String>[
    if (repository.locationLabel.trim().isNotEmpty)
      repository.locationLabel.trim(),
    repository.displayDirectory,
  ];
  return parts.join(' · ');
}

String _repoWorkbenchSearchLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '搜索文件'
      : 'Search files';
}

String _repoWorkbenchSearchHint(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '输入文件名或路径'
      : 'File name or path';
}

String _repoWorkbenchEmptyTitle(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '还没有项目'
      : 'No projects';
}

String _repoWorkbenchEmptyDescription(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '这里只显示 workspace 里的仓库，包括 cc/ 和 codex/ 子目录；宿主机其他目录里手动 clone 的项目不会出现在这里。'
      : 'Only repositories inside workspace, including the cc/ and codex/ subdirectories, appear here; projects cloned manually elsewhere on the host do not show up.';
}

String _repoWorkbenchNoFilesTitle(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '没有文件'
      : 'No files';
}

String _repoWorkbenchNoFilesDescription(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '当前目录或搜索结果为空。'
      : 'The current directory or search result is empty.';
}

String _repoWorkbenchLoadFailed(BuildContext context, Object? error) {
  final message = _friendlyDisplayError(error);
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '项目加载失败：$message'
      : 'Project load failed: $message';
}

String _repoWorkbenchLocationLabel(
  BuildContext context, {
  required String directory,
  required String query,
}) {
  if (query.isNotEmpty) {
    return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
        ? '搜索：$query'
        : 'Search: $query';
  }
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '目录：$directory'
      : 'Directory: $directory';
}

String _repoStatusTitle(
  BuildContext context,
  DemoGitRepositoryStatus? status,
  bool loading,
) {
  if (loading) {
    return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
        ? '正在读取 Git 状态'
        : 'Loading Git status';
  }
  final branch = status?.branch.trim() ?? '';
  final isZh = _AppLanguageScope.languageOf(context) == AppLanguage.chinese;
  if (status?.detached == true && branch.isEmpty) {
    return isZh ? '分离头指针' : 'Detached HEAD';
  }
  if (branch.isEmpty) {
    return isZh ? 'Git 状态' : 'Git status';
  }
  return isZh ? '分支：$branch' : 'Branch: $branch';
}

String _branchStatusTitle(
  BuildContext context,
  String? branch,
  DemoGitRepositoryStatus? status,
) {
  final current = (branch ?? '').trim();
  if (current.isNotEmpty) {
    return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
        ? '分支：$current'
        : 'Branch: $current';
  }
  return _repoStatusTitle(context, status, false);
}

String _repoStatusError(
  BuildContext context,
  Object? error,
  DemoGitRepositoryStatus? status,
) {
  final message = status?.error?.trim().isNotEmpty == true
      ? status!.error!.trim()
      : _friendlyDisplayError(error);
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? 'Git 状态不可用：$message'
      : 'Git status unavailable: $message';
}

String _repoChangedFilesLabel(BuildContext context, int count) {
  if (_AppLanguageScope.languageOf(context) == AppLanguage.chinese) {
    return count == 0 ? '工作区干净' : '变更文件 $count 个';
  }
  return count == 0 ? 'Working tree clean' : '$count changed files';
}

String _repoLimitHint(BuildContext context, bool searching) {
  if (_AppLanguageScope.languageOf(context) == AppLanguage.chinese) {
    return searching ? '已显示前 200 个匹配项，请缩小搜索范围。' : '已显示前 200 项，请进入子目录继续浏览。';
  }
  return searching
      ? 'Showing the first 200 matches. Refine the search to narrow results.'
      : 'Showing the first 200 items. Open a subdirectory to continue browsing.';
}

String _sourceControlFilesLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '文件'
      : 'Files';
}

String _sourceControlChangesLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '变更'
      : 'Changes';
}

String _sourceControlCommitLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '提交'
      : 'Commit';
}

String _sourceControlCommitAndPushLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '提交并推送'
      : 'Commit & Push';
}

String _sourceControlPushLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '推送'
      : 'Push';
}

String _sourceControlPullLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '拉取'
      : 'Pull';
}

String _sourceControlSyncLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '同步（拉取并推送）'
      : 'Sync (Pull & Push)';
}

String _sourceControlMoreActionsTooltip(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '更多 Git 操作'
      : 'More Git actions';
}

String _sourceControlCommitMessageLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '提交信息'
      : 'Commit message';
}

String _sourceControlStagedLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '已暂存'
      : 'Staged';
}

String _sourceControlUnstagedLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '未暂存'
      : 'Unstaged';
}

String _sourceControlUntrackedLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '未跟踪'
      : 'Untracked';
}

String _sourceControlBinaryLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '二进制'
      : 'Binary';
}

String _sourceControlStageTooltip(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '暂存'
      : 'Stage';
}

String _sourceControlUnstageTooltip(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '取消暂存'
      : 'Unstage';
}

String _sourceControlDiscardTooltip(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '放弃更改'
      : 'Discard changes';
}

String _sourceControlDiscardLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '放弃'
      : 'Discard';
}

String _sourceControlDiscardConfirmTitle(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '放弃更改？'
      : 'Discard changes?';
}

String _sourceControlDiscardConfirmMessage(BuildContext context, String path) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '这将永久放弃 $path 的工作区更改，且无法撤销。'
      : 'This will permanently discard working-tree changes to $path. This cannot be undone.';
}

String _sourceControlStageAllLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '全部暂存'
      : 'Stage all';
}

String _sourceControlUnstageAllLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '全部取消暂存'
      : 'Unstage all';
}

String _sourceControlEmptyTitle(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '没有变更'
      : 'No changes';
}

String _sourceControlChangesLoadFailed(BuildContext context, String? error) {
  final detail = (error ?? '').trim().isNotEmpty
      ? error!.trim()
      : _friendlyDisplayError(error);
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? (detail.isEmpty ? '变更加载失败' : '变更加载失败：$detail')
      : (detail.isEmpty
            ? 'Changes load failed'
            : 'Changes load failed: $detail');
}

String _sourceControlStatusLine(BuildContext context, int changedCount) {
  final zh = _AppLanguageScope.languageOf(context) == AppLanguage.chinese;
  return zh ? '$changedCount 个文件已更改' : '$changedCount changed';
}

String _gitGraphTitle(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '提交图'
      : 'Git Graph';
}

String _gitGraphActionLabel(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '提交图'
      : 'Graph';
}

String _gitGraphOpenTooltip(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '查看当前分支的提交图'
      : 'View commit graph for the current branch';
}

String _gitGraphLoadFailed(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '提交历史加载失败'
      : 'Commit history failed to load';
}

String _gitGraphEmptyTitle(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '没有提交'
      : 'No commits';
}

String _commitFileStat(DemoGitCommitFileChange file) {
  final additions = file.additions;
  final deletions = file.deletions;
  if (additions == null && deletions == null) return 'BIN';
  return '+${additions ?? 0} -${deletions ?? 0}';
}

String _sourceControlOpSuccess(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '操作完成'
      : 'Operation completed';
}

String _sourceControlOpFailed(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '操作失败'
      : 'Operation failed';
}

String _sourceControlSortByNameTooltip(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '按名称排序'
      : 'Sort by name';
}

String _sourceControlSortByModifiedTooltip(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '按修改时间排序'
      : 'Sort by modified';
}

String _sourceControlShowHiddenTooltip(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '显示隐藏文件'
      : 'Show hidden files';
}

String _sourceControlHideHiddenTooltip(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '隐藏隐藏文件'
      : 'Hide hidden files';
}

String _sourceControlDiffTooLarge(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? 'Diff 过大，不展示'
      : 'Diff too large to display';
}

String _sourceControlDiffFailed(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? 'Diff 加载失败'
      : 'Diff failed to load';
}

String _sourceControlDiffEmptyHint(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '当前侧没有可显示的变更'
      : 'Nothing to show on this side';
}

String _sourceControlUntrackedDiffHint(BuildContext context) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? '未跟踪文件，暂无 diff'
      : 'Untracked file — no diff yet';
}
