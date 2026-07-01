import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DemoGitProvider {
  DemoGitProvider({required this.workspaceDirectory, DemoGitRunner? runner})
    : _runner = runner ?? DemoGitRunner.defaultFor(workspaceDirectory);

  final Directory workspaceDirectory;
  final DemoGitRunner _runner;

  /// Parses the `## ...` branch line emitted by `git status --branch`.
  ///
  /// Real-world branch lines carry far more than a name:
  ///   `## main...origin/main [ahead 2, behind 1]`  (tracking, divergence)
  ///   `## main...origin/main [gone]`               (upstream deleted)
  ///   `## HEAD (no branch)`                        (detached HEAD)
  ///   `## No commits yet on main`                  (fresh repo, unborn)
  /// Previously the whole remainder was stored verbatim, leaking `[ahead 2]`
  /// / `(no branch)` into UI titles and downstream branch-switch logic. This
  /// extracts the bare local branch name (or the short SHA for detached HEAD)
  /// and flags detached/unborn states.
  static Map<String, dynamic> parseBranchLine(String line) {
    // `line` is the content after `## `.
    final rest = line.trim();
    if (rest.isEmpty) {
      return const {'branch': '', 'detached': false, 'noCommits': false};
    }
    // Detached HEAD: `HEAD (no branch)` (optionally with a SHA on older git).
    if (rest.startsWith('HEAD (no branch)') ||
        rest == 'HEAD' ||
        rest.startsWith('No commits yet on ') && rest.contains('(no branch)')) {
      return const {'branch': '', 'detached': true, 'noCommits': false};
    }
    // Unborn branch: `No commits yet on main`. Still carries a real branch name.
    if (rest.startsWith('No commits yet on ')) {
      final name = rest.substring('No commits yet on '.length).trim();
      return {'branch': name, 'detached': false, 'noCommits': true};
    }
    // `main...origin/main [ahead 2]` → strip upstream (`...`) and flags (`[`).
    var name = rest;
    final dotDot = name.indexOf('...');
    if (dotDot > 0) {
      name = name.substring(0, dotDot);
    }
    final bracket = name.indexOf(' [');
    if (bracket > 0) {
      name = name.substring(0, bracket);
    }
    return {'branch': name.trim(), 'detached': false, 'noCommits': false};
  }

  Future<Map<String, dynamic>> clone(Map<String, dynamic> params) async {
    final url = (params['url'] as String? ?? '').trim();
    if (url.isEmpty) {
      return {'success': false, 'error': 'url is required'};
    }
    if (!_isAllowedGitUrl(url)) {
      return {
        'success': false,
        'error': 'Only https:// and file:// Git repository URLs are supported.',
      };
    }

    final requestedDirectory = (params['directory'] as String? ?? '').trim();
    final defaultDirectory = _repositoryNameFromUrl(url);
    final relativeDirectory = requestedDirectory.isEmpty
        ? await _availableDefaultDirectory(defaultDirectory)
        : _safeRelativePath(requestedDirectory);
    if (relativeDirectory == null) {
      return {
        'success': false,
        'error': 'directory must be a relative path inside the Git workspace',
      };
    }

    final target = Directory('${workspaceDirectory.path}/$relativeDirectory');
    await workspaceDirectory.create(recursive: true);
    final targetExists = await target.exists();
    if (targetExists && !(await target.list().isEmpty)) {
      return {
        'success': false,
        'error': 'target directory is not empty',
        'path': target.path,
      };
    }
    await target.parent.create(recursive: true);

    final args = <String>['clone'];
    final branch = (params['branch'] as String? ?? '').trim();
    if (branch.isNotEmpty) {
      if (branch.startsWith('-')) {
        return {'success': false, 'error': 'branch/ref must not start with -'};
      }
      args.addAll(['--branch', branch]);
    }
    final depth = _int(params['depth']);
    if (depth == null || depth <= 0) {
      args.addAll(['--depth', '1']);
    } else {
      args.addAll(['--depth', depth.toString()]);
    }
    if (branch.isEmpty) {
      args.add('--no-single-branch');
    }
    args.addAll([url, _runner.repositoryPath(relativeDirectory, target.path)]);

    final result = await _runner.runGit(
      args,
      workingDirectory: _runner.workspacePath(workspaceDirectory.path),
      timeout: const Duration(minutes: 2),
    );
    final success = result['exitCode'] == 0;
    if (!success &&
        !targetExists &&
        await target.exists() &&
        !await Directory('${target.path}/.git').exists()) {
      try {
        await target.delete(recursive: true);
      } catch (_) {}
    }
    return {
      ...result,
      'tool': 'git_clone',
      'success': success,
      'url': url,
      'directory': relativeDirectory,
      'path': target.path,
      if (branch.isNotEmpty) 'branch': branch,
      if (!success) 'error': result['error'] ?? 'git clone failed',
    };
  }

  Future<Map<String, dynamic>> initRepository({
    required String directory,
    String commitMessage = 'Initial Android project',
  }) async {
    final relativeDirectory = _safeRelativePath(directory);
    if (relativeDirectory == null) {
      return {
        'success': false,
        'error': 'directory must be a relative path inside the Git workspace',
      };
    }
    final target = Directory('${workspaceDirectory.path}/$relativeDirectory');
    if (!await target.exists()) {
      return {
        'success': false,
        'error': 'project directory does not exist',
        'directory': relativeDirectory,
        'path': target.path,
      };
    }
    final gitDirectory = _runner.repositoryPath(relativeDirectory, target.path);
    final init = await _runner.runGit([
      'init',
      gitDirectory,
    ], workingDirectory: _runner.workspacePath(workspaceDirectory.path));
    if (init['exitCode'] != 0) {
      return {
        ...init,
        'success': false,
        'directory': relativeDirectory,
        'path': target.path,
        'error': init['error'] ?? 'git init failed',
      };
    }
    await _runner.runGit([
      '-C',
      gitDirectory,
      'checkout',
      '-B',
      'main',
    ], timeout: const Duration(seconds: 30));
    await _runner.runGit([
      '-C',
      gitDirectory,
      'config',
      'user.name',
      'Developer Workbench',
    ], timeout: const Duration(seconds: 30));
    await _runner.runGit([
      '-C',
      gitDirectory,
      'config',
      'user.email',
      'mobile-developer@example.local',
    ], timeout: const Duration(seconds: 30));
    final add = await _runner.runGit([
      '-C',
      gitDirectory,
      'add',
      '.',
    ], timeout: const Duration(seconds: 30));
    if (add['exitCode'] != 0) {
      return {
        ...add,
        'success': false,
        'directory': relativeDirectory,
        'path': target.path,
        'error': add['error'] ?? 'git add failed',
      };
    }
    final commit = await _runner.runGit([
      '-C',
      gitDirectory,
      'commit',
      '-m',
      commitMessage.trim().isEmpty ? 'Initial Android project' : commitMessage,
    ], timeout: const Duration(seconds: 30));
    final commitStdout = commit['stdout'] as String? ?? '';
    final commitStderr = commit['stderr'] as String? ?? '';
    final nothingToCommit =
        commitStdout.contains('nothing to commit') ||
        commitStderr.contains('nothing to commit');
    if (commit['exitCode'] != 0 && !nothingToCommit) {
      return {
        ...commit,
        'success': false,
        'directory': relativeDirectory,
        'path': target.path,
        'error': commit['error'] ?? 'git commit failed',
      };
    }
    return {
      ...commit,
      'success': true,
      'directory': relativeDirectory,
      'path': target.path,
      'message': nothingToCommit
          ? 'repository initialized'
          : 'initial commit created',
    };
  }

  Future<Map<String, dynamic>> status(Map<String, dynamic> params) async {
    final repo = await _repositoryFromParams(params);
    if (repo.error != null) {
      return {'success': false, 'error': repo.error};
    }
    return _statusRepository(repo);
  }

  Future<Map<String, dynamic>> statusDirectory(
    Directory directory, {
    String relativePath = '',
  }) async {
    final repo = await _repositoryRefForDirectory(directory, relativePath);
    if (repo.error != null) {
      return {'success': false, 'error': repo.error};
    }
    return _statusRepository(repo);
  }

  Future<Map<String, dynamic>> _statusRepository(_GitRepositoryRef repo) async {
    final directory = repo.directory!;
    final relativePath = repo.relativePath ?? '';
    if (!await directory.exists()) {
      return {
        'success': false,
        'error': 'repository directory does not exist: $relativePath',
      };
    }
    if (!await _isGitRepository(repo)) {
      return {
        'success': false,
        'error': 'directory is not a Git repository: $relativePath',
      };
    }
    final gitDirectory = _repositoryPath(repo);
    final result = await _runner.runGit([
      '-C',
      gitDirectory,
      'status',
      '--short',
      '--branch',
    ], timeout: const Duration(seconds: 30));
    final success = result['exitCode'] == 0;
    return {
      ...result,
      'tool': 'git_status',
      'success': success,
      'directory': relativePath,
      'path': directory.path,
      if (!success) 'error': result['error'] ?? 'git status failed',
    };
  }

  /// Resolves the source-control change set: branch plus per-path entries
  /// (staged / unstaged / untracked) with `+X/-Y` numstat. Uses porcelain
  /// `-z` so paths with spaces, quotes, or unicode are handled verbatim and
  /// renames surface their old path as a separate NUL record.
  Future<Map<String, dynamic>> changes(Map<String, dynamic> params) async {
    final repo = await _repositoryFromParams(params);
    if (repo.error != null) {
      return {'success': false, 'error': repo.error, 'entries': const []};
    }
    final directory = repo.directory!;
    final relativePath = repo.relativePath ?? '';
    if (!await directory.exists()) {
      return {
        'success': false,
        'error': 'repository directory does not exist: $relativePath',
        'entries': const [],
      };
    }
    if (!await _isGitRepository(repo)) {
      return {
        'success': false,
        'error': 'directory is not a Git repository: $relativePath',
        'entries': const [],
      };
    }
    final gitDirectory = _repositoryPath(repo);
    final statusResult = await _runner.runGit([
      '-C',
      gitDirectory,
      'status',
      '--short',
      '--branch',
      '-z',
    ], timeout: const Duration(seconds: 30));
    if (statusResult['exitCode'] != 0) {
      return {
        ...statusResult,
        'tool': 'git_changes',
        'success': false,
        'directory': relativePath,
        'path': directory.path,
        'entries': const [],
        'error': statusResult['error'] ?? 'git status failed',
      };
    }
    final stagedStat = await _numstat(gitDirectory, cached: true);
    final unstagedStat = await _numstat(gitDirectory, cached: false);

    var branch = '';
    var detached = false;
    var noCommits = false;
    final entries = <Map<String, dynamic>>[];
    final records = (statusResult['stdout'] as String? ?? '').split('\x00');
    var index = 0;
    while (index < records.length) {
      final record = records[index];
      if (record.isEmpty) {
        index += 1;
        continue;
      }
      if (record.startsWith('## ')) {
        final parsed = parseBranchLine(record.substring(3));
        branch = parsed['branch'] as String? ?? '';
        detached = parsed['detached'] as bool? ?? false;
        noCommits = parsed['noCommits'] as bool? ?? false;
        index += 1;
        continue;
      }
      if (record.length < 4) {
        index += 1;
        continue;
      }
      final xy = record.substring(0, 2);
      final path = record.substring(3);
      if (path.isEmpty) {
        index += 1;
        continue;
      }
      String? oldPath;
      final indexCode = xy[0];
      if (indexCode == 'R' || indexCode == 'C') {
        if (index + 1 < records.length) {
          index += 1;
          oldPath = records[index];
        }
      }
      entries.addAll(
        _changeEntries(xy, path, oldPath, stagedStat, unstagedStat),
      );
      index += 1;
    }
    return {
      ...statusResult,
      'tool': 'git_changes',
      'success': true,
      'directory': relativePath,
      'path': directory.path,
      'branch': branch,
      'detached': detached,
      'noCommits': noCommits,
      'entries': entries,
    };
  }

  /// `git diff --numstat` (optionally `--cached`) → `{path: [additions, deletions]}`.
  /// Binary files report `-`/`-` and become `null`. Paths may contain spaces
  /// (numstat tab-separates the stats from the rest of the path).
  ///
  /// `core.quotePath=false` is forced so non-ASCII paths are emitted verbatim —
  /// otherwise numstat quotes them (`"中文.txt"`) while `status -z` does not,
  /// and the two maps would never align, dropping all stats for unicode files.
  /// A non-zero exit (corrupt index, lock, permissions) is treated as "no
  /// stats available" rather than a silent partial success.
  Future<Map<String, List<int?>>> _numstat(
    String gitDirectory, {
    required bool cached,
  }) async {
    final args = <String>[
      '-c',
      'core.quotePath=false',
      '-C',
      gitDirectory,
      'diff',
      '--numstat',
    ];
    if (cached) args.add('--cached');
    final result = await _runner.runGit(
      args,
      timeout: const Duration(seconds: 30),
    );
    if (result['exitCode'] != 0) {
      debugPrint(
        'demo_git_provider: numstat failed (exit ${result['exitCode']}): '
        '${result['error'] ?? result['stderr']}',
      );
      return const {};
    }
    final out = result['stdout'] as String? ?? '';
    final map = <String, List<int?>>{};
    for (final line in out.split('\n')) {
      if (line.trim().isEmpty) continue;
      final parts = line.split('\t');
      if (parts.length < 3) continue;
      final add = parts[0] == '-' ? null : int.tryParse(parts[0]);
      final del = parts[1] == '-' ? null : int.tryParse(parts[1]);
      final path = parts.sublist(2).join('\t');
      map[path] = [add, del];
    }
    return map;
  }

  List<Map<String, dynamic>> _changeEntries(
    String xy,
    String path,
    String? oldPath,
    Map<String, List<int?>> stagedStat,
    Map<String, List<int?>> unstagedStat,
  ) {
    const unmerged = {'DD', 'AU', 'UD', 'UA', 'DU', 'AA', 'UU'};
    if (unmerged.contains(xy)) {
      return [
        _changeEntryMap(
          path,
          xy[0],
          xy[1],
          'unmerged',
          'unmerged',
          null,
          null,
          oldPath,
        ),
      ];
    }
    final x = xy[0];
    final y = xy[1];
    if (x == '?' && y == '?') {
      return [
        _changeEntryMap(path, x, y, 'untracked', 'untracked', null, null, null),
      ];
    }
    final out = <Map<String, dynamic>>[];
    if (x != ' ' && x != '?') {
      final stat = stagedStat[path] ?? const [null, null];
      out.add(
        _changeEntryMap(
          path,
          x,
          y,
          'staged',
          _indexCategory(x),
          stat[0],
          stat[1],
          oldPath,
        ),
      );
    }
    if (y != ' ' && y != '?') {
      final stat = unstagedStat[path] ?? const [null, null];
      out.add(
        _changeEntryMap(
          path,
          x,
          y,
          'unstaged',
          _workCategory(y),
          stat[0],
          stat[1],
          oldPath,
        ),
      );
    }
    return out;
  }

  Map<String, dynamic> _changeEntryMap(
    String path,
    String indexCode,
    String workCode,
    String area,
    String category,
    int? additions,
    int? deletions,
    String? oldPath,
  ) {
    return <String, dynamic>{
      'path': path,
      'indexCode': indexCode,
      'workCode': workCode,
      'area': area,
      'category': category,
      'additions': additions,
      'deletions': deletions,
      if (oldPath != null) 'oldPath': oldPath,
    };
  }

  String _indexCategory(String code) => switch (code) {
    'M' || 'T' => 'modified',
    'A' => 'added',
    'D' => 'deleted',
    'R' || 'C' => 'renamed',
    _ => 'modified',
  };

  String _workCategory(String code) => switch (code) {
    'M' || 'T' => 'modified',
    'D' => 'deleted',
    _ => 'modified',
  };

  /// Stages paths (`git add -- <paths>`); empty/`.` paths stage everything.
  Future<Map<String, dynamic>> stage(Map<String, dynamic> params) async {
    final repo = await _repositoryFromParams(params);
    if (repo.error != null) return {'success': false, 'error': repo.error};
    final gitDirectory = _repositoryPath(repo);
    final rawPaths = params['paths'];
    final stageAll = _isStageAllRequest(rawPaths);
    final args = <String>['-C', gitDirectory, 'add', '--'];
    if (stageAll) {
      args.add('.');
    } else {
      final paths = _normalizeRepoPaths(rawPaths);
      if (paths == null) {
        return {'success': false, 'error': 'invalid path in stage request'};
      }
      args.addAll(paths);
    }
    final result = await _runner.runGit(
      args,
      timeout: const Duration(seconds: 30),
    );
    final success = result['exitCode'] == 0;
    return {
      ...result,
      'tool': 'git_stage',
      'success': success,
      'directory': repo.relativePath,
      'path': repo.directory!.path,
      if (success)
        'message': stageAll ? 'staged all changes' : 'changes staged',
      if (!success) 'error': result['error'] ?? 'git add failed',
    };
  }

  /// Unstages paths (`git reset -q -- <paths>`); empty/`.` resets the index.
  Future<Map<String, dynamic>> unstage(Map<String, dynamic> params) async {
    final repo = await _repositoryFromParams(params);
    if (repo.error != null) return {'success': false, 'error': repo.error};
    final gitDirectory = _repositoryPath(repo);
    final rawPaths = params['paths'];
    final all = _isStageAllRequest(rawPaths);
    final args = <String>['-C', gitDirectory, 'reset', '-q'];
    if (all) {
      args.add('HEAD');
    } else {
      final paths = _normalizeRepoPaths(rawPaths);
      if (paths == null) {
        return {'success': false, 'error': 'invalid path in unstage request'};
      }
      args.add('--');
      args.addAll(paths);
    }
    final result = await _runner.runGit(
      args,
      timeout: const Duration(seconds: 30),
    );
    final success = result['exitCode'] == 0;
    return {
      ...result,
      'tool': 'git_unstage',
      'success': success,
      'directory': repo.relativePath,
      'path': repo.directory!.path,
      if (success) 'message': all ? 'unstaged all changes' : 'changes unstaged',
      if (!success) 'error': result['error'] ?? 'git reset failed',
    };
  }

  /// Discards working-tree changes: `git restore -- <tracked>` and
  /// `git clean -f -- <untracked>` (path-scoped, never bare `clean`). The UI
  /// must confirm before calling — this is irreversible.
  Future<Map<String, dynamic>> discard(Map<String, dynamic> params) async {
    final repo = await _repositoryFromParams(params);
    if (repo.error != null) return {'success': false, 'error': repo.error};
    final gitDirectory = _repositoryPath(repo);
    final paths = _normalizeRepoPaths(params['paths']);
    if (paths == null || paths.isEmpty) {
      return {'success': false, 'error': 'paths are required for discard'};
    }
    final untracked = await _untrackedPaths(gitDirectory);
    final tracked = <String>[];
    final untrackedOnly = <String>[];
    for (final path in paths) {
      if (untracked.contains(path)) {
        untrackedOnly.add(path);
      } else {
        tracked.add(path);
      }
    }
    Map<String, dynamic>? trackedFailed;
    Map<String, dynamic>? cleanFailed;
    if (tracked.isNotEmpty) {
      final result = await _runner.runGit([
        '-C',
        gitDirectory,
        'restore',
        '--',
        ...tracked,
      ], timeout: const Duration(seconds: 30));
      if (result['exitCode'] != 0) trackedFailed = result;
    }
    // Always attempt the clean even if restore failed: the two operate on
    // disjoint path sets, so a restore failure shouldn't skip discarding the
    // untracked files the user also asked to remove. `-d` lets clean remove
    // untracked *directories` (porcelain lists them as `dir/`), which bare
    // `clean -f -- <dir>` refuses without `-d`.
    if (untrackedOnly.isNotEmpty) {
      final result = await _runner.runGit([
        '-C',
        gitDirectory,
        'clean',
        '-f',
        '-d',
        '--',
        ...untrackedOnly,
      ], timeout: const Duration(seconds: 30));
      if (result['exitCode'] != 0) cleanFailed = result;
    }
    final failed = trackedFailed ?? cleanFailed;
    final partial = trackedFailed == null && cleanFailed != null;
    final success = failed == null;
    return {
      ...(failed ?? const <String, dynamic>{}),
      'providerAvailable': true,
      'tool': 'git_discard',
      'success': success,
      'partial': partial,
      'directory': repo.relativePath,
      'path': repo.directory!.path,
      if (success) 'message': 'changes discarded',
      if (!success) 'error': failed['error'] ?? 'git discard failed',
    };
  }

  /// Commits the staged index (`git commit -m <message>`). `nothing to commit`
  /// is treated as success (mirrors [initRepository]).
  Future<Map<String, dynamic>> commit(Map<String, dynamic> params) async {
    final repo = await _repositoryFromParams(params);
    if (repo.error != null) return {'success': false, 'error': repo.error};
    final message = (params['message'] as String? ?? '').trim();
    if (message.isEmpty) {
      return {'success': false, 'error': 'commit message is required'};
    }
    final gitDirectory = _repositoryPath(repo);
    final result = await _runner.runGit([
      '-C',
      gitDirectory,
      'commit',
      '-m',
      message,
    ], timeout: const Duration(seconds: 30));
    final stdout = result['stdout'] as String? ?? '';
    final stderr = result['stderr'] as String? ?? '';
    final nothingToCommit =
        stdout.contains('nothing to commit') ||
        stderr.contains('nothing to commit');
    final success = result['exitCode'] == 0 || nothingToCommit;
    return {
      ...result,
      'tool': 'git_commit',
      'success': success,
      'directory': repo.relativePath,
      'path': repo.directory!.path,
      if (success)
        'message': nothingToCommit ? 'nothing to commit' : 'commit created',
      if (!success) 'error': result['error'] ?? 'git commit failed',
    };
  }

  /// Fetches the unified diff for a single path (`git diff [--cached] -- <path>`).
  /// A cheap `--numstat` pre-check bails with `{tooLarge: true}` once the change
  /// exceeds [_kMaxDiffLines] lines, so the UI can show a "diff too large"
  /// placeholder instead of pulling a giant diff. An empty numstat (nothing
  /// changed on this side, e.g. a fully-staged file viewed as unstaged) returns
  /// `{empty: true}`.
  Future<Map<String, dynamic>> fileDiff(Map<String, dynamic> params) async {
    final repo = await _repositoryFromParams(params);
    if (repo.error != null) return {'success': false, 'error': repo.error};
    final gitDirectory = _repositoryPath(repo);
    final paths = _normalizeRepoPaths([params['path']]);
    if (paths == null || paths.isEmpty) {
      return {'success': false, 'error': 'path is required for file diff'};
    }
    final path = paths.first;
    final cached = params['cached'] as bool? ?? false;

    final statArgs = <String>[
      '-c',
      'core.quotePath=false',
      '-C',
      gitDirectory,
      'diff',
      '--numstat',
    ];
    if (cached) statArgs.add('--cached');
    statArgs.addAll(['--', path]);
    final stat = await _runner.runGit(
      statArgs,
      timeout: const Duration(seconds: 30),
    );
    // Non-zero numstat here means we cannot trust the line-count gate; fall
    // through to a real diff so the UI surfaces the underlying error instead
    // of silently treating the file as empty.
    final statOk = stat['exitCode'] == 0;
    final statLine = statOk ? (stat['stdout'] as String? ?? '').trim() : '';
    if (statLine.isEmpty) {
      return {
        'success': true,
        'directory': repo.relativePath,
        'path': path,
        'cached': cached,
        'empty': true,
      };
    }
    final statParts = statLine.split('\t');
    final add = statParts.isNotEmpty && statParts[0] != '-'
        ? int.tryParse(statParts[0])
        : null;
    final del = statParts.length > 1 && statParts[1] != '-'
        ? int.tryParse(statParts[1])
        : null;
    final changed = (add ?? 0) + (del ?? 0);
    if (changed > _kMaxDiffLines) {
      return {
        'success': true,
        'directory': repo.relativePath,
        'path': path,
        'cached': cached,
        'tooLarge': true,
        'additions': add,
        'deletions': del,
      };
    }

    final args = <String>['-C', gitDirectory, 'diff', '--no-color'];
    if (cached) args.add('--cached');
    args.addAll(['--', path]);
    final result = await _runner.runGit(
      args,
      timeout: const Duration(seconds: 30),
      outputLimit: 200000,
    );
    final success = result['exitCode'] == 0;
    return {
      ...result,
      'success': success,
      'directory': repo.relativePath,
      'path': path,
      'cached': cached,
      'additions': add,
      'deletions': del,
      if (!success) 'error': result['error'] ?? 'git diff failed',
    };
  }

  Future<Set<String>> _untrackedPaths(String gitDirectory) async {
    final result = await _runner.runGit([
      '-C',
      gitDirectory,
      'status',
      '--short',
      '-z',
    ], timeout: const Duration(seconds: 30));
    final out = result['stdout'] as String? ?? '';
    final set = <String>{};
    for (final record in out.split('\x00')) {
      if (record.length >= 4 && record.substring(0, 2) == '??') {
        final path = record.substring(3);
        if (path.isNotEmpty) set.add(path);
      }
    }
    return set;
  }

  /// True when the request stages/unstages the whole repo (no paths, or a
  /// sole `.`).
  bool _isStageAllRequest(Object? rawPaths) {
    if (rawPaths is! List || rawPaths.isEmpty) return true;
    if (rawPaths.length != 1) return false;
    return (rawPaths[0]?.toString() ?? '').trim() == '.';
  }

  /// Validates repo-relative paths WITHOUT mangling (unlike [_safeRelativePath],
  /// which normalizes segments and would corrupt paths containing spaces or
  /// unicode). Rejects empty, absolute, traversal (`..`), and `://` forms.
  /// Returns the cleaned paths, or `null` if any path is invalid.
  List<String>? _normalizeRepoPaths(Object? rawPaths) {
    if (rawPaths is! List) return null;
    final out = <String>[];
    for (final entry in rawPaths) {
      final value = (entry?.toString() ?? '').trim();
      if (value.isEmpty) return null;
      var normalized = value.replaceAll('\\', '/');
      // Porcelain emits untracked *directories* with a trailing slash (`?? dir/`).
      // Strip it so the path validates and matches `git clean -- <dir>`, which
      // rejects the trailing-slash form for pathspecs.
      while (normalized.length > 1 && normalized.endsWith('/')) {
        normalized = normalized.substring(0, normalized.length - 1);
      }
      if (normalized.isEmpty ||
          normalized.startsWith('/') ||
          normalized.contains('://')) {
        return null;
      }
      for (final part in normalized.split('/')) {
        if (part.isEmpty || part == '.' || part == '..') return null;
      }
      out.add(normalized);
    }
    return out;
  }

  Future<Map<String, dynamic>> diff(Map<String, dynamic> params) async {
    final repo = await _repositoryFromParams(params);
    if (repo.error != null) {
      return {'success': false, 'error': repo.error};
    }
    final gitDirectory = _repositoryPath(repo);
    final args = ['-C', gitDirectory, 'diff'];
    if (params['stat'] as bool? ?? false) {
      args.add('--stat');
    }
    final result = await _runner.runGit(
      args,
      timeout: const Duration(seconds: 30),
    );
    final success = result['exitCode'] == 0;
    return {
      ...result,
      'tool': 'git_diff',
      'success': success,
      'directory': repo.relativePath,
      'path': repo.directory!.path,
      if (!success) 'error': result['error'] ?? 'git diff failed',
    };
  }

  Future<Map<String, dynamic>> commitHistory(
    Map<String, dynamic> params,
  ) async {
    final repo = await _repositoryFromParams(params);
    if (repo.error != null) {
      return {'success': false, 'error': repo.error, 'commits': const []};
    }
    final gitDirectory = _repositoryPath(repo);
    final limit = (_int(params['limit']) ?? 40).clamp(1, 100);
    final args = <String>[
      '-C',
      gitDirectory,
      'log',
      '--graph',
      '--date=iso-strict',
      '--pretty=format:%x1f%H%x1f%h%x1f%P%x1f%an%x1f%ae%x1f%aI%x1f%D%x1f%s',
      '-n',
      limit.toString(),
    ];
    final result = await _runner.runGit(
      args,
      timeout: const Duration(seconds: 30),
      outputLimit: 120000,
    );
    final success = result['exitCode'] == 0;
    return {
      ...result,
      'tool': 'git_commit_history',
      'success': success,
      'directory': repo.relativePath,
      'path': repo.directory!.path,
      'commits': success
          ? _parseCommitHistory(result['stdout'] as String? ?? '')
          : const [],
      if (!success) 'error': result['error'] ?? 'git log failed',
    };
  }

  Future<Map<String, dynamic>> commitDiff(Map<String, dynamic> params) async {
    final repo = await _repositoryFromParams(params);
    if (repo.error != null) {
      return {'success': false, 'error': repo.error, 'files': const []};
    }
    final gitDirectory = _repositoryPath(repo);
    final hash = (params['hash'] as String? ?? '').trim();
    if (!_isSafeGitRef(hash)) {
      return {'success': false, 'error': 'commit hash/ref is invalid'};
    }
    final stat = await _runner.runGit(
      [
        '-c',
        'core.quotePath=false',
        '-C',
        gitDirectory,
        'show',
        '--format=',
        '--numstat',
        '--find-renames',
        hash,
      ],
      timeout: const Duration(seconds: 30),
      outputLimit: 60000,
    );
    if (stat['exitCode'] != 0) {
      return {
        ...stat,
        'tool': 'git_commit_diff',
        'success': false,
        'directory': repo.relativePath,
        'hash': hash,
        'files': const [],
        'error': stat['error'] ?? 'git show failed',
      };
    }
    final files = _parseCommitNumstat(stat['stdout'] as String? ?? '');
    final changed = files.fold<int>(0, (sum, file) {
      final additions = file['additions'];
      final deletions = file['deletions'];
      return sum +
          (additions is int ? additions : 0) +
          (deletions is int ? deletions : 0);
    });
    if (changed > _kMaxDiffLines) {
      return {
        'tool': 'git_commit_diff',
        'success': true,
        'directory': repo.relativePath,
        'hash': hash,
        'files': files,
        'tooLarge': true,
      };
    }
    final diff = await _runner.runGit(
      [
        '-c',
        'core.quotePath=false',
        '-C',
        gitDirectory,
        'show',
        '--no-color',
        '--format=',
        '--find-renames',
        hash,
      ],
      timeout: const Duration(seconds: 30),
      outputLimit: 200000,
    );
    final success = diff['exitCode'] == 0;
    return {
      ...diff,
      'tool': 'git_commit_diff',
      'success': success,
      'directory': repo.relativePath,
      'hash': hash,
      'files': files,
      if (!success) 'error': diff['error'] ?? 'git show failed',
    };
  }

  List<Map<String, dynamic>> _parseCommitHistory(String stdout) {
    final commits = <Map<String, dynamic>>[];
    for (final line in stdout.split('\n')) {
      if (!line.contains('\x1f')) continue;
      final delimiter = line.indexOf('\x1f');
      final graph = line.substring(0, delimiter).trimRight();
      final parts = line.substring(delimiter + 1).split('\x1f');
      if (parts.length < 8) continue;
      final hash = parts[0].trim();
      if (hash.isEmpty) continue;
      commits.add({
        'graph': graph,
        'hash': hash,
        'shortHash': parts[1].trim(),
        'parents': parts[2]
            .split(' ')
            .where((parent) => parent.trim().isNotEmpty)
            .toList(growable: false),
        'authorName': parts[3].trim(),
        'authorEmail': parts[4].trim(),
        'authoredAt': parts[5].trim(),
        'refs': parts[6].trim(),
        'subject': parts.sublist(7).join('\x1f').trim(),
      });
    }
    return commits;
  }

  List<Map<String, dynamic>> _parseCommitNumstat(String stdout) {
    final files = <Map<String, dynamic>>[];
    for (final line in stdout.split('\n')) {
      if (line.trim().isEmpty) continue;
      final parts = line.split('\t');
      if (parts.length < 3) continue;
      final add = parts[0] == '-' ? null : int.tryParse(parts[0]);
      final del = parts[1] == '-' ? null : int.tryParse(parts[1]);
      files.add({
        'path': parts.sublist(2).join('\t'),
        'additions': add,
        'deletions': del,
      });
    }
    return files;
  }

  Future<Map<String, dynamic>> listBranches(Map<String, dynamic> params) async {
    final repo = await _repositoryFromParams(params);
    if (repo.error != null) {
      return {'success': false, 'error': repo.error, 'branches': const []};
    }
    final gitDirectory = _repositoryPath(repo);
    final local = await _runner.runGit([
      '-C',
      gitDirectory,
      'branch',
      '--list',
      '--format=%(refname:short)%09%(upstream:short)%09%(HEAD)',
    ], timeout: const Duration(seconds: 30));
    if (local['exitCode'] != 0) {
      return {
        ...local,
        'tool': 'git_list_branches',
        'success': false,
        'directory': repo.relativePath,
        'branches': const [],
        'error': local['error'] ?? 'git branch list failed',
      };
    }
    final remote = await _runner.runGit([
      '-C',
      gitDirectory,
      'branch',
      '--remotes',
      '--format=%(refname:short)%09%(upstream:short)%09%(HEAD)',
    ], timeout: const Duration(seconds: 30));
    final remotes = await _listRemotesForRepo(repo, gitDirectory);
    final branches = <Map<String, dynamic>>[
      ..._parseBranchList(local['stdout'] as String? ?? '', remote: false),
      if (remote['exitCode'] == 0)
        ..._parseBranchList(remote['stdout'] as String? ?? '', remote: true),
      ...await _listRemoteHeads(gitDirectory, remotes),
    ];
    final deduped = <String, Map<String, dynamic>>{};
    for (final branch in branches) {
      final name = branch['name'] as String? ?? '';
      if (name.isEmpty) continue;
      final key = '${branch['remote'] == true ? 'r' : 'l'}:$name';
      deduped[key] = {...?deduped[key], ...branch};
    }
    final sortedBranches = deduped.values.toList(growable: false);
    sortedBranches.sort((a, b) {
      final aCurrent = a['current'] as bool? ?? false;
      final bCurrent = b['current'] as bool? ?? false;
      if (aCurrent != bCurrent) return aCurrent ? -1 : 1;
      final aRemote = a['remote'] as bool? ?? false;
      final bRemote = b['remote'] as bool? ?? false;
      if (aRemote != bRemote) return aRemote ? 1 : -1;
      return (a['name'] as String).toLowerCase().compareTo(
        (b['name'] as String).toLowerCase(),
      );
    });
    return {
      'tool': 'git_list_branches',
      'success': true,
      'directory': repo.relativePath,
      'branches': sortedBranches,
      if (remote['exitCode'] != 0) 'remoteWarning': remote['stderr'],
    };
  }

  Future<Map<String, dynamic>> switchBranch(Map<String, dynamic> params) async {
    final repo = await _repositoryFromParams(params);
    if (repo.error != null) {
      return {'success': false, 'error': repo.error};
    }
    final branch = (params['branch'] as String? ?? '').trim();
    if (!_isSafeGitRef(branch)) {
      return {'success': false, 'error': 'branch/ref is invalid'};
    }
    final allowDirty = params['allowDirty'] as bool? ?? false;
    final dirtyFiles = allowDirty
        ? const <String>[]
        : await _changedFiles(repo.directory!, repo.relativePath ?? '');
    if (dirtyFiles.isNotEmpty) {
      return {
        'tool': 'git_switch_branch',
        'success': false,
        'directory': repo.relativePath,
        'branch': branch,
        'changedFiles': dirtyFiles,
        'error':
            'working tree has uncommitted changes; commit, stash, or explicitly allowDirty before switching branches',
      };
    }

    final gitDirectory = _repositoryPath(repo);
    final remote = params['remote'] as bool? ?? false;
    final args = ['-C', gitDirectory, 'checkout'];
    if (remote) {
      final localName = _localBranchNameForRemote(branch);
      if (localName == null) {
        return {'success': false, 'error': 'remote branch is invalid'};
      }
      final localExists = await _branchExists(gitDirectory, localName);
      if (localExists) {
        args.add(localName);
      } else {
        final parts = _remoteBranchParts(branch);
        if (parts == null) {
          return {'success': false, 'error': 'remote branch is invalid'};
        }
        await _expandRemoteFetchSpecs(gitDirectory, [parts.remote]);
        await _removeStaleGitLock(repo.directory!, 'shallow.lock');
        final fetch = await _runner.runGit([
          '-C',
          gitDirectory,
          'fetch',
          '--no-write-fetch-head',
          '--depth',
          '1',
          parts.remote,
          'refs/heads/${parts.head}:refs/remotes/${parts.remote}/${parts.head}',
        ], timeout: const Duration(minutes: 2));
        if (fetch['exitCode'] != 0) {
          return {
            ...fetch,
            'tool': 'git_switch_branch',
            'success': false,
            'directory': repo.relativePath,
            'branch': branch,
            'error': _gitFailureMessage(
              fetch,
              'git remote branch fetch failed',
            ),
          };
        }
        final createBranch = await _runner.runGit([
          '-C',
          gitDirectory,
          'branch',
          '--track',
          localName,
          'refs/remotes/${parts.remote}/${parts.head}',
        ], timeout: const Duration(seconds: 30));
        if (createBranch['exitCode'] != 0) {
          return {
            ...createBranch,
            'tool': 'git_switch_branch',
            'success': false,
            'directory': repo.relativePath,
            'branch': branch,
            'error': _gitFailureMessage(
              createBranch,
              'git tracking branch creation failed',
            ),
          };
        }
        args.add(localName);
      }
    } else {
      args.add(branch);
    }

    final result = await _runner.runGit(
      args,
      timeout: const Duration(seconds: 60),
    );
    final success = result['exitCode'] == 0;
    return {
      ...result,
      'tool': 'git_switch_branch',
      'success': success,
      'directory': repo.relativePath,
      'branch': branch,
      if (success)
        'message': remote
            ? 'Switched to branch from $branch'
            : 'Switched to $branch',
      if (!success)
        'error': _gitFailureMessage(result, 'git branch switch failed'),
    };
  }

  Future<Map<String, dynamic>> listRemotes(Map<String, dynamic> params) async {
    final repo = await _repositoryFromParams(params);
    if (repo.error != null) {
      return {'success': false, 'error': repo.error, 'remotes': const []};
    }
    final gitDirectory = _repositoryPath(repo);
    final result = await _runner.runGit([
      '-C',
      gitDirectory,
      'remote',
      '-v',
    ], timeout: const Duration(seconds: 30));
    final success = result['exitCode'] == 0;
    final parsed = success
        ? _parseRemoteList(result['stdout'] as String? ?? '')
        : const <Map<String, dynamic>>[];
    final remotes = parsed.isEmpty
        ? await _remotesFromConfigFile(repo.directory!)
        : parsed;
    return {
      ...result,
      'tool': 'git_list_remotes',
      'success': success,
      'directory': repo.relativePath,
      'remotes': remotes,
      if (!success) 'error': result['error'] ?? 'git remote list failed',
    };
  }

  Future<Map<String, dynamic>> setRemote(Map<String, dynamic> params) async {
    final repo = await _repositoryFromParams(params);
    if (repo.error != null) {
      return {'success': false, 'error': repo.error};
    }
    final name = (params['name'] as String? ?? '').trim();
    if (!_isSafeRemoteName(name)) {
      return {'success': false, 'error': 'remote name is invalid'};
    }
    final action = (params['action'] as String? ?? 'upsert').trim();
    if (action == 'remove') {
      return _removeRemote(repo, name);
    }
    final url = (params['url'] as String? ?? '').trim();
    if (!_isAllowedRemoteUrl(url)) {
      return {'success': false, 'error': 'remote url is invalid'};
    }
    final gitDirectory = _repositoryPath(repo);
    final exists = await _remoteExists(gitDirectory, name);
    final result = await _runner.runGit([
      '-C',
      gitDirectory,
      'remote',
      exists ? 'set-url' : 'add',
      name,
      url,
    ], timeout: const Duration(seconds: 30));
    final success = result['exitCode'] == 0;
    return {
      ...result,
      'tool': 'git_set_remote',
      'success': success,
      'directory': repo.relativePath,
      'name': name,
      'url': url,
      'action': exists ? 'update' : 'add',
      if (success)
        'message': exists ? 'Updated remote $name' : 'Added remote $name',
      if (!success) 'error': result['error'] ?? 'git remote update failed',
    };
  }

  Future<Map<String, dynamic>> fetch(Map<String, dynamic> params) async {
    final repo = await _repositoryFromParams(params);
    if (repo.error != null) {
      return {'success': false, 'error': repo.error};
    }
    final remote = (params['remote'] as String? ?? '').trim();
    if (remote.isNotEmpty && !_isSafeRemoteName(remote)) {
      return {'success': false, 'error': 'remote name is invalid'};
    }
    final gitDirectory = _repositoryPath(repo);
    final prune = params['prune'] as bool? ?? true;
    final remotes = await _listRemotesForRepo(repo, gitDirectory);
    final remoteNames = remote.isEmpty
        ? [
            for (final item in remotes)
              if ((item['name'] as String? ?? '').isNotEmpty)
                item['name'] as String,
          ]
        : [remote];
    await _expandRemoteFetchSpecs(gitDirectory, remoteNames);
    await _removeStaleGitLock(repo.directory!, 'shallow.lock');
    final args = ['-C', gitDirectory, 'fetch', '--no-write-fetch-head'];
    if (prune) args.add('--prune');
    if (remote.isEmpty) {
      args.add('--all');
    } else {
      args.add(remote);
    }
    final result = await _runner.runGit(
      args,
      timeout: const Duration(minutes: 2),
    );
    final success = result['exitCode'] == 0;
    return {
      ...result,
      'tool': 'git_fetch',
      'success': success,
      'directory': repo.relativePath,
      if (remote.isNotEmpty) 'remote': remote,
      if (success)
        'message': remote.isEmpty ? 'Fetched remotes' : 'Fetched $remote',
      if (!success) 'error': result['error'] ?? 'git fetch failed',
    };
  }

  Future<Map<String, dynamic>> push(Map<String, dynamic> params) async {
    final repo = await _repositoryFromParams(params);
    if (repo.error != null) {
      return {'success': false, 'error': repo.error};
    }
    final remote = (params['remote'] as String? ?? '').trim();
    if (remote.isNotEmpty && !_isSafeRemoteName(remote)) {
      return {'success': false, 'error': 'remote name is invalid'};
    }
    final gitDirectory = _repositoryPath(repo);
    await _removeStaleGitLock(repo.directory!, 'shallow.lock');

    Future<Map<String, dynamic>> runPush(List<String> extra) {
      final args = <String>['-C', gitDirectory, 'push'];
      args.addAll(extra);
      return _runner.runGit(args, timeout: const Duration(minutes: 2));
    }

    Map<String, dynamic> shape(
      Map<String, dynamic> result, {
      required String label,
      String? usedRemote,
    }) {
      final stdout = result['stdout'] as String? ?? '';
      final stderr = result['stderr'] as String? ?? '';
      final combined = '$stdout\n$stderr'.toLowerCase();
      final upToDate =
          combined.contains('everything up-to-date') ||
          combined.contains('everything up to date');
      final success = result['exitCode'] == 0 || upToDate;
      return {
        ...result,
        'tool': 'git_push',
        'success': success,
        'directory': repo.relativePath,
        if (usedRemote != null) 'remote': usedRemote,
        if (success) 'message': upToDate ? 'Everything up-to-date' : label,
        if (!success) 'error': _gitFailureMessage(result, 'git push failed'),
      };
    }

    if (remote.isNotEmpty) {
      final result = await runPush([remote, 'HEAD']);
      return shape(result, label: 'Pushed to $remote', usedRemote: remote);
    }

    // Rely on the configured upstream first; if HEAD has no upstream, fall back
    // to setting up tracking against the first available remote.
    var result = await runPush(const []);
    final combined =
        '${result['stdout'] as String? ?? ''}\n${result['stderr'] as String? ?? ''}'
            .toLowerCase();
    final noUpstream =
        result['exitCode'] != 0 &&
        (combined.contains('no upstream') ||
            combined.contains('has no upstream branch') ||
            combined.contains('set the remote as upstream'));
    if (noUpstream) {
      final remotes = await _listRemotesForRepo(repo, gitDirectory);
      final firstRemote = remotes
          .map((item) => (item['name'] as String? ?? '').trim())
          .firstWhere(_isSafeRemoteName, orElse: () => '');
      if (firstRemote.isNotEmpty) {
        final retry = await runPush(['-u', firstRemote, 'HEAD']);
        return shape(
          retry,
          label: 'Pushed to $firstRemote',
          usedRemote: firstRemote,
        );
      }
    }
    return shape(result, label: 'Pushed to upstream');
  }

  Future<Map<String, dynamic>> pull(Map<String, dynamic> params) async {
    final repo = await _repositoryFromParams(params);
    if (repo.error != null) {
      return {'success': false, 'error': repo.error};
    }
    final remote = (params['remote'] as String? ?? '').trim();
    if (remote.isNotEmpty && !_isSafeRemoteName(remote)) {
      return {'success': false, 'error': 'remote name is invalid'};
    }
    final gitDirectory = _repositoryPath(repo);
    await _removeStaleGitLock(repo.directory!, 'shallow.lock');
    final args = <String>['-C', gitDirectory, 'pull'];
    if (remote.isNotEmpty) {
      args.addAll([remote, 'HEAD']);
    }
    final result = await _runner.runGit(
      args,
      timeout: const Duration(minutes: 2),
    );
    final stdout = result['stdout'] as String? ?? '';
    final stderr = result['stderr'] as String? ?? '';
    final combined = '$stdout\n$stderr'.toLowerCase();
    final upToDate =
        combined.contains('already up to date') ||
        combined.contains('already up-to-date');
    final success = result['exitCode'] == 0 || upToDate;
    final source = remote.isEmpty ? 'upstream' : remote;
    return {
      ...result,
      'tool': 'git_pull',
      'success': success,
      'directory': repo.relativePath,
      if (remote.isNotEmpty) 'remote': remote,
      if (success)
        'message': upToDate ? 'Already up to date' : 'Pulled from $source',
      if (!success) 'error': _gitFailureMessage(result, 'git pull failed'),
    };
  }

  /// Whether [directory] is inside a Git work tree.
  ///
  /// Uses `git rev-parse --is-inside-work-tree` rather than probing for a `.git`
  /// *directory*: a linked worktree, a submodule, or a `git worktree add`'d
  /// path expose `.git` as a plain file (or a `gitdir:` pointer), not a
  /// directory, so `Directory('.git').exists()` falsely rejects them. Asking
  /// git itself also covers bare repos reached via `-C` correctly.
  Future<bool> _isGitRepository(_GitRepositoryRef repo) async {
    final directory = repo.directory;
    if (directory == null) return false;
    final result = await _runner.runGit([
      '-C',
      _repositoryPath(repo),
      'rev-parse',
      '--is-inside-work-tree',
    ], timeout: const Duration(seconds: 15));
    if (result['exitCode'] != 0) return false;
    return (result['stdout'] as String? ?? '').trim() == 'true';
  }

  Future<_GitRepositoryRef> _repositoryFromParams(
    Map<String, dynamic> params,
  ) async {
    final rawDirectory = (params['directory'] as String? ?? '').trim();
    final rawAbsolutePath = (params['absolutePath'] as String? ?? '').trim();
    final relativePath = rawDirectory.isEmpty
        ? null
        : _safeRelativePath(rawDirectory);
    if (rawAbsolutePath.isEmpty && relativePath == null) {
      return const _GitRepositoryRef(error: 'directory is required');
    }
    final directory = rawAbsolutePath.isNotEmpty
        ? Directory(rawAbsolutePath)
        : Directory('${workspaceDirectory.path}/${relativePath!}');
    if (!await directory.exists()) {
      return _GitRepositoryRef(
        error:
            'repository directory does not exist: ${relativePath ?? rawAbsolutePath}',
      );
    }
    final repo = _GitRepositoryRef(
      directory: directory,
      relativePath:
          relativePath ??
          _relativePathFromWorkspace(directory) ??
          _directoryName(directory.path),
      realPathOverride: directory.path,
    );
    if (!await _isGitRepository(repo)) {
      return _GitRepositoryRef(
        error:
            'directory is not a Git repository: ${relativePath ?? rawAbsolutePath}',
      );
    }
    return repo;
  }

  Future<_GitRepositoryRef> _repositoryRefForDirectory(
    Directory directory,
    String relativePath,
  ) async {
    final normalizedRelativePath = relativePath.trim().isEmpty
        ? _relativePathFromWorkspace(directory)
        : _safeRelativePath(relativePath);
    if (normalizedRelativePath == null) {
      return const _GitRepositoryRef(
        error: 'directory must be a relative path inside the Git workspace',
      );
    }
    if (!await directory.exists()) {
      return _GitRepositoryRef(
        error: 'repository directory does not exist: $normalizedRelativePath',
      );
    }
    final repo = _GitRepositoryRef(
      directory: directory,
      relativePath: normalizedRelativePath,
      realPathOverride: directory.path,
    );
    if (!await _isGitRepository(repo)) {
      return _GitRepositoryRef(
        error: 'directory is not a Git repository: $normalizedRelativePath',
      );
    }
    return repo;
  }

  String? _relativePathFromWorkspace(Directory directory) {
    final workspacePath = _normalizePath(workspaceDirectory.absolute.path);
    final directoryPath = _normalizePath(directory.absolute.path);
    if (directoryPath == workspacePath) return null;
    final prefix = '$workspacePath/';
    if (!directoryPath.startsWith(prefix)) return null;
    return _safeRelativePath(directoryPath.substring(prefix.length));
  }

  String _repositoryPath(_GitRepositoryRef repo) {
    return _runner.repositoryPath(
      repo.relativePath ?? _directoryName(repo.directory!.path),
      repo.realPathOverride ?? repo.directory!.path,
    );
  }

  String _normalizePath(String path) {
    return path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  }

  String _directoryName(String path) {
    final normalized = _normalizePath(path);
    if (normalized.isEmpty) return normalized;
    return normalized.split('/').last;
  }

  bool _isAllowedGitUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.scheme == 'https') return uri.host.trim().isNotEmpty;
    if (uri.scheme == 'file') return uri.path.trim().isNotEmpty;
    return false;
  }

  String _repositoryNameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final segments =
        uri?.pathSegments
            .where((segment) => segment.trim().isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    final rawName = segments.isEmpty ? 'repository' : segments.last;
    final withoutGit = rawName.endsWith('.git')
        ? rawName.substring(0, rawName.length - 4)
        : rawName;
    return _safePathSegment(withoutGit) ??
        'repository-${DateTime.now().millisecondsSinceEpoch}';
  }

  String? _safeRelativePath(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        normalized.contains('://')) {
      return null;
    }
    final parts = <String>[];
    for (final rawPart in normalized.split('/')) {
      final part = rawPart.trim();
      if (part.isEmpty || part == '.') continue;
      if (part == '..') return null;
      final safe = _safePathSegment(part);
      if (safe == null) return null;
      parts.add(safe);
    }
    if (parts.isEmpty) return null;
    return parts.join('/');
  }

  String? _safePathSegment(String value) {
    final replaced = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    final stripped = replaced.replaceAll(RegExp(r'^[.-]+|[.-]+$'), '');
    if (stripped.isEmpty || stripped == '.' || stripped == '..') return null;
    return stripped;
  }

  Future<String> _availableDefaultDirectory(String defaultDirectory) async {
    for (var index = 0; index < 1000; index += 1) {
      final candidate = index == 0
          ? defaultDirectory
          : '$defaultDirectory-${index + 1}';
      final safe = _safeRelativePath(candidate);
      if (safe == null) continue;
      final dir = Directory('${workspaceDirectory.path}/$safe');
      if (!await dir.exists() || await dir.list().isEmpty) {
        return safe;
      }
    }
    return 'repository-${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<List<String>> _changedFiles(
    Directory directory,
    String relativePath,
  ) async {
    // Reuse `changes()` rather than re-parsing a non-`-z` porcelain stream:
    // `changes()` already splits paths verbatim with `-z`, so paths containing
    // spaces, quotes, or unicode (and rename targets) are captured correctly
    // where the old `line.substring(3)` parser misread them. The branch
    // switch's dirty-check only needs the set of changed paths.
    final raw = await changes({
      'directory': relativePath,
      'absolutePath': directory.path,
    });
    if (raw['success'] != true) return const [];
    final entries = raw['entries'];
    if (entries is! List) return const [];
    return List.unmodifiable(
      [
        for (final entry in entries)
          if (entry is Map) (entry['path'] as String? ?? '').trim(),
      ].where((path) => path.isNotEmpty),
    );
  }

  Future<bool> _branchExists(String gitDirectory, String branch) async {
    final result = await _runner.runGit([
      '-C',
      gitDirectory,
      'rev-parse',
      '--verify',
      '--quiet',
      'refs/heads/$branch',
    ], timeout: const Duration(seconds: 15));
    return result['exitCode'] == 0;
  }

  Future<bool> _remoteExists(String gitDirectory, String name) async {
    final result = await _runner.runGit([
      '-C',
      gitDirectory,
      'remote',
      'get-url',
      name,
    ], timeout: const Duration(seconds: 15));
    return result['exitCode'] == 0;
  }

  Future<Map<String, dynamic>> _removeRemote(
    _GitRepositoryRef repo,
    String name,
  ) async {
    final gitDirectory = _repositoryPath(repo);
    final result = await _runner.runGit([
      '-C',
      gitDirectory,
      'remote',
      'remove',
      name,
    ], timeout: const Duration(seconds: 30));
    final success = result['exitCode'] == 0;
    return {
      ...result,
      'tool': 'git_set_remote',
      'success': success,
      'directory': repo.relativePath,
      'name': name,
      'action': 'remove',
      if (success) 'message': 'Removed remote $name',
      if (!success) 'error': result['error'] ?? 'git remote remove failed',
    };
  }

  Future<List<Map<String, dynamic>>> _listRemotesForRepo(
    _GitRepositoryRef repo,
    String gitDirectory,
  ) async {
    final result = await _runner.runGit([
      '-C',
      gitDirectory,
      'remote',
      '-v',
    ], timeout: const Duration(seconds: 30));
    final parsed = result['exitCode'] == 0
        ? _parseRemoteList(result['stdout'] as String? ?? '')
        : const <Map<String, dynamic>>[];
    if (parsed.isNotEmpty) return parsed;
    return _remotesFromConfigFile(repo.directory!);
  }

  Future<List<Map<String, dynamic>>> _listRemoteHeads(
    String gitDirectory,
    List<Map<String, dynamic>> remotes,
  ) async {
    // List-remote is a network round-trip per remote; doing them serially made
    // `listBranches` block for up to N×45s on slow/offline links. Fan out in
    // parallel and bound the whole batch so one stuck remote can't hang the
    // branch picker indefinitely.
    final names = <String>[
      for (final remote in remotes) (remote['name'] as String? ?? '').trim(),
    ].where(_isSafeRemoteName).toList(growable: false);
    if (names.isEmpty) return const [];

    Future<List<Map<String, dynamic>>> headsFor(String name) async {
      final result = await _runner.runGit([
        '-C',
        gitDirectory,
        'ls-remote',
        '--heads',
        name,
      ], timeout: const Duration(seconds: 45));
      if (result['exitCode'] != 0) return const [];
      return _parseLsRemoteHeads(
        result['stdout'] as String? ?? '',
        remoteName: name,
      );
    }

    final results = await Future.wait(
      names.map(headsFor),
    ).timeout(const Duration(seconds: 60), onTimeout: () => const []);
    final branches = <Map<String, dynamic>>[];
    for (final batch in results) {
      branches.addAll(batch);
    }
    return branches;
  }

  Future<void> _expandRemoteFetchSpecs(
    String gitDirectory,
    List<String> remoteNames,
  ) async {
    for (final remote in remoteNames) {
      if (!_isSafeRemoteName(remote)) continue;
      await _runner.runGit([
        '-C',
        gitDirectory,
        'config',
        '--replace-all',
        'remote.$remote.fetch',
        '+refs/heads/*:refs/remotes/$remote/*',
      ], timeout: const Duration(seconds: 15));
    }
  }

  List<Map<String, dynamic>> _parseBranchList(
    String stdout, {
    required bool remote,
  }) {
    final branches = <Map<String, dynamic>>[];
    for (final line in stdout.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.contains(' -> ')) continue;
      final parts = trimmed.split('\t');
      final name = parts.isEmpty ? '' : parts[0].trim();
      if (name.isEmpty || name == 'HEAD') continue;
      branches.add({
        'name': name,
        'remote': remote,
        'current': parts.length > 2 && parts[2].trim() == '*',
        if (parts.length > 1 && parts[1].trim().isNotEmpty)
          'upstream': parts[1].trim(),
      });
    }
    return branches;
  }

  List<Map<String, dynamic>> _parseLsRemoteHeads(
    String stdout, {
    required String remoteName,
  }) {
    final branches = <Map<String, dynamic>>[];
    for (final line in stdout.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      const prefix = 'refs/heads/';
      final ref = parts[1];
      if (!ref.startsWith(prefix)) continue;
      final head = ref.substring(prefix.length);
      if (!_isSafeGitRef(head)) continue;
      branches.add({
        'name': '$remoteName/$head',
        'remote': true,
        'current': false,
      });
    }
    return branches;
  }

  List<Map<String, dynamic>> _parseRemoteList(String stdout) {
    final byName = <String, Map<String, dynamic>>{};
    final pattern = RegExp(r'^(\S+)\s+(\S+)\s+\((fetch|push)\)$');
    for (final line in stdout.split('\n')) {
      final match = pattern.firstMatch(line.trim());
      if (match == null) continue;
      final name = match.group(1)!;
      final url = match.group(2)!;
      final kind = match.group(3)!;
      final entry = byName.putIfAbsent(name, () => {'name': name});
      if (kind == 'fetch') {
        entry['fetchUrl'] = url;
      } else {
        entry['pushUrl'] = url;
      }
    }
    return byName.values.toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _remotesFromConfigFile(
    Directory repoDirectory,
  ) async {
    try {
      final config = await File(
        '${repoDirectory.path}/.git/config',
      ).readAsString();
      return _parseRemoteConfig(config);
    } catch (_) {
      return const [];
    }
  }

  List<Map<String, dynamic>> _parseRemoteConfig(String config) {
    final remotes = <Map<String, dynamic>>[];
    Map<String, dynamic>? current;
    final sectionPattern = RegExp(r'^\s*\[remote\s+"([^"]+)"\]\s*$');
    for (final rawLine in config.split('\n')) {
      final line = rawLine.trimRight();
      final section = sectionPattern.firstMatch(line.trim());
      if (section != null) {
        final name = section.group(1) ?? '';
        current = _isSafeRemoteName(name) ? {'name': name} : null;
        if (current != null) remotes.add(current);
        continue;
      }
      if (line.trimLeft().startsWith('[')) {
        current = null;
        continue;
      }
      final entry = current;
      if (entry == null) continue;
      final separator = line.indexOf('=');
      if (separator < 0) continue;
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      if (key == 'url') {
        entry['fetchUrl'] = value;
        entry['pushUrl'] = value;
      } else if (key == 'pushurl') {
        entry['pushUrl'] = value;
      }
    }
    return remotes;
  }

  String? _localBranchNameForRemote(String branch) {
    final parts = branch.split('/');
    if (parts.length < 2) return null;
    final local = parts.skip(1).join('/');
    return _isSafeGitRef(local) ? local : null;
  }

  _RemoteBranchParts? _remoteBranchParts(String branch) {
    final parts = branch.split('/');
    if (parts.length < 2) return null;
    final remote = parts.first;
    final head = parts.skip(1).join('/');
    if (!_isSafeRemoteName(remote) || !_isSafeGitRef(head)) return null;
    return _RemoteBranchParts(remote: remote, head: head);
  }

  bool _isSafeGitRef(String value) {
    final ref = value.trim();
    if (ref.isEmpty ||
        ref.startsWith('-') ||
        ref.startsWith('/') ||
        ref.endsWith('/') ||
        ref.contains('..') ||
        ref.contains('\u0000') ||
        ref.contains(RegExp(r'\s')) ||
        ref.contains(RegExp(r'[\^~:?*\[\\]'))) {
      return false;
    }
    return true;
  }

  bool _isSafeRemoteName(String value) {
    final name = value.trim();
    if (name.isEmpty || name.startsWith('-')) return false;
    return RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name);
  }

  bool _isAllowedRemoteUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('-') ||
        trimmed.contains('\u0000') ||
        trimmed.contains(RegExp(r'[\r\n]'))) {
      return false;
    }
    if (RegExp(r'^[A-Za-z0-9._%+-]+@[^:\s]+:.+$').hasMatch(trimmed)) {
      return true;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    if (uri.scheme == 'https' || uri.scheme == 'ssh') {
      return uri.host.trim().isNotEmpty;
    }
    if (uri.scheme == 'file') return uri.path.trim().isNotEmpty;
    return false;
  }

  int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  String _gitFailureMessage(Map<String, dynamic> result, String fallback) {
    final error = (result['error'] as String? ?? '').trim();
    if (error.isNotEmpty) return error;
    final stderr = (result['stderr'] as String? ?? '').trim();
    if (stderr.isNotEmpty) return stderr;
    final stdout = (result['stdout'] as String? ?? '').trim();
    if (stdout.isNotEmpty) return stdout;
    return fallback;
  }

  Future<bool> _removeStaleGitLock(
    Directory repoDirectory,
    String lockName, {
    Duration minAge = const Duration(minutes: 2),
  }) async {
    if (!_isSafeGitLockName(lockName)) return false;
    final lock = File('${repoDirectory.path}/.git/$lockName');
    try {
      final stat = await lock.stat();
      if (stat.type != FileSystemEntityType.file) return false;
      if (DateTime.now().difference(stat.modified) < minAge) return false;
      await lock.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  bool _isSafeGitLockName(String value) {
    return RegExp(r'^[A-Za-z0-9._-]+\.lock$').hasMatch(value);
  }
}

abstract class DemoGitRunner {
  const DemoGitRunner();

  factory DemoGitRunner.defaultFor(Directory workspaceDirectory) {
    if (Platform.isAndroid) {
      return AndroidLinuxDemoGitRunner(workspaceDirectory: workspaceDirectory);
    }
    return const HostDemoGitRunner();
  }

  String repositoryPath(String relativePath, String realPath);

  String workspacePath(String realPath);

  Future<Map<String, dynamic>> runGit(
    List<String> args, {
    String? workingDirectory,
    Duration timeout = const Duration(seconds: 60),
    int outputLimit = 6000,
  });
}

class HostDemoGitRunner extends DemoGitRunner {
  const HostDemoGitRunner();

  @override
  String repositoryPath(String relativePath, String realPath) => realPath;

  @override
  String workspacePath(String realPath) => realPath;

  @override
  Future<Map<String, dynamic>> runGit(
    List<String> args, {
    String? workingDirectory,
    Duration timeout = const Duration(seconds: 60),
    int outputLimit = 6000,
  }) async {
    final startedAt = DateTime.now();
    int durationMs() => DateTime.now().difference(startedAt).inMilliseconds;
    Process? process;
    try {
      // Process.start (vs Process.run) gives us the child handle so a timeout
      // can kill it; otherwise a slow clone/fetch keeps running as an orphan
      // eating CPU/network/disk after we've already returned a timeout result.
      process = await Process.start(
        'git',
        args,
        workingDirectory: workingDirectory,
      );
      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(timeout);
      final out = await stdout;
      final err = await stderr;
      if (exitCode != 0) {
        _logGitCommandFailure(
          source: 'host',
          args: args,
          workingDirectory: workingDirectory,
          exitCode: exitCode,
          stderr: _trimProcessOutput(err, outputLimit),
        );
      }
      return {
        'providerAvailable': true,
        'exitCode': exitCode,
        'stdout': _trimProcessOutput(out, outputLimit),
        'stderr': _trimProcessOutput(err, outputLimit),
        'durationMs': durationMs(),
      };
    } on TimeoutException {
      _killProcess(process);
      _logGitCommandFailure(
        source: 'host',
        args: args,
        workingDirectory: workingDirectory,
        exitCode: -1,
        stderr: '',
        error: 'git command timed out after ${timeout.inSeconds}s',
      );
      return {
        'providerAvailable': true,
        'exitCode': -1,
        'stdout': '',
        'stderr': '',
        'durationMs': durationMs(),
        'error': 'git command timed out after ${timeout.inSeconds}s',
      };
    } on ProcessException catch (error) {
      _logGitCommandFailure(
        source: 'host',
        args: args,
        workingDirectory: workingDirectory,
        exitCode: -1,
        stderr: _trimProcessOutput(error.message),
        error: 'git executable is not available on this host',
      );
      return {
        'providerAvailable': false,
        'exitCode': -1,
        'stdout': '',
        'stderr': _trimProcessOutput(error.message),
        'durationMs': durationMs(),
        'error': 'git executable is not available on this host',
      };
    } catch (error) {
      _killProcess(process);
      _logGitCommandFailure(
        source: 'host',
        args: args,
        workingDirectory: workingDirectory,
        exitCode: -1,
        stderr: '',
        error: error.toString(),
      );
      return {
        'providerAvailable': false,
        'exitCode': -1,
        'stdout': '',
        'stderr': '',
        'durationMs': durationMs(),
        'error': error.toString(),
      };
    }
  }
}

void _killProcess(Process? process) {
  if (process == null) return;
  try {
    process.kill(ProcessSignal.sigkill);
  } catch (_) {
    // Best-effort: the process may have already exited.
  }
}

class AndroidLinuxDemoGitRunner extends DemoGitRunner {
  AndroidLinuxDemoGitRunner({required this.workspaceDirectory});

  static const MethodChannel _channel = MethodChannel(
    'com.napaxi.flutter/platform_context',
  );

  final Directory workspaceDirectory;

  @override
  String repositoryPath(String relativePath, String realPath) {
    final normalized = relativePath.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return '/workspace';
    return '/workspace/$normalized';
  }

  @override
  String workspacePath(String realPath) => '/workspace';

  @override
  Future<Map<String, dynamic>> runGit(
    List<String> args, {
    String? workingDirectory,
    Duration timeout = const Duration(seconds: 60),
    int outputLimit = 6000,
  }) async {
    final startedAt = DateTime.now();
    int durationMs() => DateTime.now().difference(startedAt).inMilliseconds;
    try {
      final response = await _channel
          .invokeMethod<String>('executeLinuxProgram', {
            'workspaceDir': workspaceDirectory.path,
            'argv': ['/usr/bin/git', ...args],
            'workdir': workingDirectory?.startsWith('/workspace') == true
                ? workingDirectory
                : '/workspace',
            'timeout': timeout.inSeconds.clamp(1, 600).toInt(),
          })
          .timeout(timeout + const Duration(seconds: 5));
      final decoded = jsonDecode(response ?? '{}');
      if (decoded is! Map) {
        return {
          'providerAvailable': false,
          'exitCode': -1,
          'stdout': '',
          'stderr': '',
          'durationMs': durationMs(),
          'error': 'Android Linux Git runner returned invalid JSON',
        };
      }
      final result = Map<String, dynamic>.from(decoded);
      final exitCode = result['exitCode'] as int? ?? -1;
      if (exitCode != 0) {
        _logGitCommandFailure(
          source: 'android',
          args: args,
          workingDirectory: workingDirectory,
          exitCode: exitCode,
          stderr: _trimProcessOutput(result['stderr'], outputLimit),
          error: result['error']?.toString(),
        );
      }
      return {
        'providerAvailable': result['providerAvailable'] as bool? ?? false,
        'exitCode': exitCode,
        'stdout': _trimProcessOutput(result['stdout'], outputLimit),
        'stderr': _trimProcessOutput(result['stderr'], outputLimit),
        'durationMs': result['durationMs'] as int? ?? durationMs(),
        if (result['error'] != null) 'error': result['error'].toString(),
      };
    } on TimeoutException {
      _logGitCommandFailure(
        source: 'android',
        args: args,
        workingDirectory: workingDirectory,
        exitCode: -1,
        stderr: '',
        error: 'git command timed out after ${timeout.inSeconds}s',
      );
      return {
        'providerAvailable': true,
        'exitCode': -1,
        'stdout': '',
        'stderr': '',
        'durationMs': durationMs(),
        'error': 'git command timed out after ${timeout.inSeconds}s',
      };
    } on PlatformException catch (error) {
      _logGitCommandFailure(
        source: 'android',
        args: args,
        workingDirectory: workingDirectory,
        exitCode: -1,
        stderr: '',
        error: error.message ?? error.code,
      );
      return {
        'providerAvailable': false,
        'exitCode': -1,
        'stdout': '',
        'stderr': '',
        'durationMs': durationMs(),
        'error': error.message ?? error.code,
      };
    } catch (error) {
      _logGitCommandFailure(
        source: 'android',
        args: args,
        workingDirectory: workingDirectory,
        exitCode: -1,
        stderr: '',
        error: error.toString(),
      );
      return {
        'providerAvailable': false,
        'exitCode': -1,
        'stdout': '',
        'stderr': '',
        'durationMs': durationMs(),
        'error': error.toString(),
      };
    }
  }
}

void _logGitCommandFailure({
  required String source,
  required List<String> args,
  required String? workingDirectory,
  required int exitCode,
  required String stderr,
  String? error,
}) {
  final buffer = StringBuffer()
    ..write('[GitToolTrace] git command failed')
    ..write(' source=$source')
    ..write(' exitCode=$exitCode')
    ..write(' workdir=${workingDirectory ?? "(default)"}')
    ..write(' args=${jsonEncode(args)}');
  if (stderr.trim().isNotEmpty) {
    buffer.write(' stderr=${stderr.trim().replaceAll('\n', ' | ')}');
  }
  if (error != null && error.trim().isNotEmpty) {
    buffer.write(' error=${error.trim()}');
  }
  debugPrint(buffer.toString());
}

class _GitRepositoryRef {
  const _GitRepositoryRef({
    this.directory,
    this.relativePath,
    this.realPathOverride,
    this.error,
  });

  final Directory? directory;
  final String? relativePath;
  final String? realPathOverride;
  final String? error;
}

class _RemoteBranchParts {
  const _RemoteBranchParts({required this.remote, required this.head});

  final String remote;
  final String head;
}

String _trimProcessOutput(Object? value, [int maxChars = 6000]) {
  final text = (value ?? '').toString().trim();
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars)}...';
}

/// Upper bound on changed lines for an inline [DemoGitProvider.fileDiff] view;
/// beyond this the UI shows a "diff too large" placeholder.
const int _kMaxDiffLines = 500;
