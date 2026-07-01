import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi/demo_client/demo_git_provider.dart';

Future<ProcessResult> _runGit(List<String> args, {String? workingDirectory}) {
  return Process.run(
    'git',
    args,
    workingDirectory: workingDirectory,
  ).timeout(const Duration(seconds: 10));
}

Future<void> _ensureGitAvailable() async {
  try {
    final result = await _runGit(['--version']);
    if (result.exitCode == 0) return;
  } on TimeoutException {
    markTestSkipped('git executable timed out in flutter_tester');
    return;
  } catch (_) {}
  markTestSkipped('git executable is not available on this host');
}

void main() {
  test('clones a local repository into the demo Git workspace', () async {
    await _ensureGitAvailable();
    final temp = await Directory.systemTemp.createTemp('git_provider_');
    try {
      final source = Directory('${temp.path}/source');
      await source.create(recursive: true);
      await File('${source.path}/README.md').writeAsString('hello napaxi\n');
      expect(
        (await _runGit(['init'], workingDirectory: source.path)).exitCode,
        0,
      );
      expect(
        (await _runGit([
          'add',
          'README.md',
        ], workingDirectory: source.path)).exitCode,
        0,
      );
      final commit = await _runGit([
        '-c',
        'user.name=Napaxi Test',
        '-c',
        'user.email=napaxi@example.invalid',
        'commit',
        '-m',
        'initial',
      ], workingDirectory: source.path);
      expect(commit.exitCode, 0, reason: commit.stderr.toString());

      final provider = DemoGitProvider(
        workspaceDirectory: Directory('${temp.path}/workspace'),
      );
      final clone = await provider.clone({
        'url': source.uri.toString(),
        'directory': 'fixture',
      });

      expect(clone['success'], true, reason: clone.toString());
      expect(clone['directory'], 'fixture');
      expect(File('${clone['path']}/README.md').existsSync(), true);

      final status = await provider.status({'directory': 'fixture'});

      expect(status['success'], true, reason: status.toString());
      expect((status['stdout'] as String), contains('##'));
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('initializes a generated project as a Git repository', () async {
    await _ensureGitAvailable();
    final temp = await Directory.systemTemp.createTemp('git_provider_init_');
    try {
      final workspace = Directory('${temp.path}/workspace');
      final project = Directory('${workspace.path}/hello-android');
      await project.create(recursive: true);
      await File('${project.path}/README.md').writeAsString('hello android\n');
      final provider = DemoGitProvider(workspaceDirectory: workspace);

      final init = await provider.initRepository(
        directory: 'hello-android',
        commitMessage: 'Initial Android project',
      );

      expect(init['success'], true, reason: init.toString());
      expect(Directory('${project.path}/.git').existsSync(), true);
      final status = await provider.status({'directory': 'hello-android'});
      expect(status['success'], true, reason: status.toString());
      expect(status['stdout'], contains('## main'));
      final head = await _runGit([
        'rev-parse',
        '--verify',
        'HEAD',
      ], workingDirectory: project.path);
      expect(head.exitCode, 0, reason: head.stderr.toString());
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test(
    'Android Linux runner clones into sandbox workspace and avoids default collisions',
    () async {
      final temp = await Directory.systemTemp.createTemp('git_provider_linux_');
      try {
        final workspace = Directory('${temp.path}/workspace');
        await File(
          '${workspace.path}/openclaw/README.md',
        ).create(recursive: true);
        final runner = _RecordingMobileGitRunner();
        final provider = DemoGitProvider(
          workspaceDirectory: workspace,
          runner: runner,
        );

        final clone = await provider.clone({
          'url': 'https://github.com/openclaw/openclaw',
        });

        expect(clone['success'], true, reason: clone.toString());
        expect(clone['directory'], 'openclaw-2');
        expect(runner.lastWorkingDirectory, '/workspace');
        expect(runner.lastArgs, [
          'clone',
          '--depth',
          '1',
          '--no-single-branch',
          'https://github.com/openclaw/openclaw',
          '/workspace/openclaw-2',
        ]);
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'Android Linux runner maps repository paths into workspace before Git calls',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'git_provider_linux_status_',
      );
      try {
        final workspace = Directory('${temp.path}/workspace');
        final repo = Directory('${workspace.path}/repo');
        await Directory('${repo.path}/.git').create(recursive: true);
        final runner = _RecordingMobileGitRunner();
        final provider = DemoGitProvider(
          workspaceDirectory: workspace,
          runner: runner,
        );

        await provider.status({'directory': 'repo'});

        expect(runner.lastArgs, [
          '-C',
          '/workspace/repo',
          'status',
          '--short',
          '--branch',
        ]);
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'Android Linux runner probes repository status with sandbox path during rev-parse',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'git_provider_linux_probe_',
      );
      try {
        final workspace = Directory('${temp.path}/workspace');
        final repo = Directory('${workspace.path}/repo');
        await Directory('${repo.path}/.git').create(recursive: true);
        final runner = _RecordingMobileGitRunner();
        final provider = DemoGitProvider(
          workspaceDirectory: workspace,
          runner: runner,
        );

        await provider.status({'directory': 'repo'});

        expect(runner.calls.first, [
          '-C',
          '/workspace/repo',
          'rev-parse',
          '--is-inside-work-tree',
        ]);
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );

  test('lists branches and refuses dirty branch switches', () async {
    final temp = await Directory.systemTemp.createTemp('git_provider_branch_');
    try {
      final repo = Directory('${temp.path}/workspace/repo');
      await Directory('${repo.path}/.git').create(recursive: true);
      final runner = _ScriptedGitRunner((args) {
        if (_containsInOrder(args, ['status', '--short', '--branch', '-z'])) {
          // `changes()` (NUL-delimited porcelain) used by the dirty-check.
          return {
            'exitCode': 0,
            'stdout': '## main...origin/main\x00 M lib/main.dart',
          };
        }
        if (_containsInOrder(args, ['status', '--short', '--branch'])) {
          return {
            'exitCode': 0,
            'stdout': '## main...origin/main\n M lib/main.dart\n',
          };
        }
        if (_containsInOrder(args, ['branch', '--list'])) {
          return {
            'exitCode': 0,
            'stdout': 'main\torigin/main\t*\nfeature\t\t\n',
          };
        }
        if (_containsInOrder(args, ['branch', '--remotes'])) {
          return {
            'exitCode': 0,
            'stdout': 'origin/main\t\t\norigin/feature\t\t\n',
          };
        }
        return {'exitCode': 0};
      });
      final provider = DemoGitProvider(
        workspaceDirectory: Directory('${temp.path}/workspace'),
        runner: runner,
      );

      final branches = await provider.listBranches({'directory': 'repo'});
      final switchResult = await provider.switchBranch({
        'directory': 'repo',
        'branch': 'feature',
      });

      expect(branches['success'], true, reason: branches.toString());
      final branchRows = (branches['branches'] as List).cast<Map>();
      expect(
        branchRows.any(
          (branch) =>
              branch['name'] == 'main' &&
              branch['remote'] == false &&
              branch['current'] == true &&
              branch['upstream'] == 'origin/main',
        ),
        true,
      );
      expect(
        branchRows.any(
          (branch) =>
              branch['name'] == 'origin/feature' &&
              branch['remote'] == true &&
              branch['current'] == false,
        ),
        true,
      );
      expect(switchResult['success'], false);
      expect(switchResult['changedFiles'], ['lib/main.dart']);
      expect(
        runner.calls.any(
          (args) => _containsInOrder(args, ['checkout', 'feature']),
        ),
        false,
      );
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test(
    'remote branch switch creates tracking branch before checkout',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'git_provider_remote_',
      );
      try {
        final repo = Directory('${temp.path}/workspace/repo');
        await Directory('${repo.path}/.git').create(recursive: true);
        final runner = _ScriptedGitRunner((args) {
          if (_containsInOrder(args, ['status', '--short', '--branch'])) {
            return {'exitCode': 0, 'stdout': '## main...origin/main\n'};
          }
          if (_containsInOrder(args, ['rev-parse', 'refs/heads/feature'])) {
            return {'exitCode': 1};
          }
          return {'exitCode': 0};
        });
        final provider = DemoGitProvider(
          workspaceDirectory: Directory('${temp.path}/workspace'),
          runner: runner,
        );

        final switchResult = await provider.switchBranch({
          'directory': 'repo',
          'branch': 'origin/feature',
          'remote': true,
        });

        expect(switchResult['success'], true, reason: switchResult.toString());
        expect(
          runner.calls.any(
            (args) => _containsInOrder(args, [
              'config',
              '--replace-all',
              'remote.origin.fetch',
              '+refs/heads/*:refs/remotes/origin/*',
            ]),
          ),
          true,
        );
        expect(
          runner.calls.any(
            (args) => _containsInOrder(args, [
              'fetch',
              '--no-write-fetch-head',
              '--depth',
              '1',
              'origin',
              'refs/heads/feature:refs/remotes/origin/feature',
            ]),
          ),
          true,
        );
        expect(
          runner.calls.any(
            (args) => _containsInOrder(args, [
              'branch',
              '--track',
              'feature',
              'refs/remotes/origin/feature',
            ]),
          ),
          true,
        );
        expect(
          runner.calls.any(
            (args) => _containsInOrder(args, ['checkout', 'feature']),
          ),
          true,
        );
        expect(
          runner.calls.any(
            (args) => _containsInOrder(args, ['checkout', '--track']),
          ),
          false,
        );
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'remote branch switch removes stale shallow lock before fetch',
    () async {
      final temp = await Directory.systemTemp.createTemp('git_provider_lock_');
      try {
        final repo = Directory('${temp.path}/workspace/repo');
        await Directory('${repo.path}/.git').create(recursive: true);
        final staleLock = File('${repo.path}/.git/shallow.lock');
        await staleLock.writeAsString('stale\n');
        await staleLock.setLastModified(
          DateTime.now().subtract(const Duration(minutes: 10)),
        );
        final runner = _ScriptedGitRunner((args) {
          if (_containsInOrder(args, ['status', '--short', '--branch'])) {
            return {'exitCode': 0, 'stdout': '## main...origin/main\n'};
          }
          if (_containsInOrder(args, ['rev-parse', 'refs/heads/feature'])) {
            return {'exitCode': 1};
          }
          return {'exitCode': 0};
        });
        final provider = DemoGitProvider(
          workspaceDirectory: Directory('${temp.path}/workspace'),
          runner: runner,
        );

        final switchResult = await provider.switchBranch({
          'directory': 'repo',
          'branch': 'origin/feature',
          'remote': true,
        });

        expect(switchResult['success'], true, reason: switchResult.toString());
        expect(await staleLock.exists(), false);
        expect(
          runner.calls.any(
            (args) => _containsInOrder(args, [
              'fetch',
              '--no-write-fetch-head',
              '--depth',
              '1',
              'origin',
              'refs/heads/feature:refs/remotes/origin/feature',
            ]),
          ),
          true,
        );
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'remote branch switch does not checkout when tracking setup fails',
    () async {
      final temp = await Directory.systemTemp.createTemp('git_provider_track_');
      try {
        final repo = Directory('${temp.path}/workspace/repo');
        await Directory('${repo.path}/.git').create(recursive: true);
        final runner = _ScriptedGitRunner((args) {
          if (_containsInOrder(args, ['status', '--short', '--branch'])) {
            return {'exitCode': 0, 'stdout': '## main...origin/main\n'};
          }
          if (_containsInOrder(args, ['rev-parse', 'refs/heads/feature'])) {
            return {'exitCode': 1};
          }
          if (_containsInOrder(args, ['branch', '--track'])) {
            return {
              'exitCode': 128,
              'stderr': 'fatal: starting point is not a branch',
            };
          }
          return {'exitCode': 0};
        });
        final provider = DemoGitProvider(
          workspaceDirectory: Directory('${temp.path}/workspace'),
          runner: runner,
        );

        final switchResult = await provider.switchBranch({
          'directory': 'repo',
          'branch': 'origin/feature',
          'remote': true,
        });

        expect(switchResult['success'], false);
        expect(
          switchResult['error'],
          contains('fatal: starting point is not a branch'),
        );
        expect(
          runner.calls.any(
            (args) => _containsInOrder(args, ['checkout', 'feature']),
          ),
          false,
        );
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );

  test('lists, sets, removes, and fetches remotes', () async {
    final temp = await Directory.systemTemp.createTemp('git_provider_remote_');
    try {
      final repo = Directory('${temp.path}/workspace/repo');
      await Directory('${repo.path}/.git').create(recursive: true);
      final runner = _ScriptedGitRunner((args) {
        if (_containsInOrder(args, ['remote', '-v'])) {
          return {
            'exitCode': 0,
            'stdout':
                'origin\thttps://example.com/project.git (fetch)\norigin\thttps://example.com/project.git (push)\n',
          };
        }
        if (_containsInOrder(args, ['remote', 'get-url', 'origin'])) {
          return {'exitCode': 1};
        }
        return {'exitCode': 0};
      });
      final provider = DemoGitProvider(
        workspaceDirectory: Directory('${temp.path}/workspace'),
        runner: runner,
      );

      final remotes = await provider.listRemotes({'directory': 'repo'});
      final setRemote = await provider.setRemote({
        'directory': 'repo',
        'name': 'origin',
        'url': 'https://example.com/project.git',
      });
      final fetch = await provider.fetch({'directory': 'repo'});
      final remove = await provider.setRemote({
        'directory': 'repo',
        'name': 'origin',
        'action': 'remove',
      });

      expect(remotes['success'], true, reason: remotes.toString());
      expect(remotes['remotes'], [
        {
          'name': 'origin',
          'fetchUrl': 'https://example.com/project.git',
          'pushUrl': 'https://example.com/project.git',
        },
      ]);
      expect(setRemote['success'], true, reason: setRemote.toString());
      expect(fetch['success'], true, reason: fetch.toString());
      expect(remove['success'], true, reason: remove.toString());
      expect(
        runner.calls.any(
          (args) => _containsInOrder(args, [
            'remote',
            'add',
            'origin',
            'https://example.com/project.git',
          ]),
        ),
        true,
      );
      expect(
        runner.calls.any(
          (args) => _containsInOrder(args, [
            'fetch',
            '--no-write-fetch-head',
            '--prune',
            '--all',
          ]),
        ),
        true,
      );
      expect(
        runner.calls.any(
          (args) => _containsInOrder(args, ['remote', 'remove', 'origin']),
        ),
        true,
      );
    } finally {
      await temp.delete(recursive: true);
    }
  });

  group('source control', () {
    DemoGitProvider providerWithChanges({
      required Directory workspace,
      required _ScriptedGitRunner runner,
    }) {
      return DemoGitProvider(workspaceDirectory: workspace, runner: runner);
    }

    Future<Directory> seedWorkspace() async {
      final temp = await Directory.systemTemp.createTemp('git_provider_sc_');
      final repo = Directory('${temp.path}/workspace/repo');
      await Directory('${repo.path}/.git').create(recursive: true);
      return temp;
    }

    test('changes parses staged/unstaged/untracked/rename/binary', () async {
      final temp = await seedWorkspace();
      try {
        final runner = _ScriptedGitRunner((args) {
          if (_containsInOrder(args, ['status', '--short', '--branch', '-z'])) {
            return {
              'exitCode': 0,
              'stdout':
                  '## main...origin/main\x00MM lib/a.dart\x00'
                  'A  lib/b.dart\x00M  bin.png\x00?? new.txt\x00'
                  'R  lib/renamed.dart\x00lib/old.dart',
            };
          }
          if (_containsInOrder(args, ['diff', '--numstat'])) {
            if (args.contains('--cached')) {
              return {
                'exitCode': 0,
                'stdout':
                    '5\t1\tlib/a.dart\n3\t0\tlib/b.dart\n'
                    '-\t-\tbin.png\n2\t0\tlib/renamed.dart',
              };
            }
            return {'exitCode': 0, 'stdout': '2\t0\tlib/a.dart'};
          }
          return {'exitCode': 0};
        });
        final provider = providerWithChanges(
          workspace: Directory('${temp.path}/workspace'),
          runner: runner,
        );

        final result = await provider.changes({'directory': 'repo'});
        expect(result['success'], true, reason: result.toString());
        // The `## main...origin/main [ahead N]` line is trimmed to the bare
        // local branch name — upstream and divergence markers must not leak.
        expect(result['branch'], 'main');
        expect(result['detached'], false);
        expect(result['noCommits'], false);
        final entries = (result['entries'] as List).cast<Map>();
        Map<dynamic, dynamic>? entry(
          String path,
          String area, [
          String? category,
        ]) {
          for (final e in entries) {
            if (e['path'] == path &&
                e['area'] == area &&
                (category == null || e['category'] == category)) {
              return e;
            }
          }
          return null;
        }

        expect(entry('lib/a.dart', 'staged', 'modified')?['additions'], 5);
        expect(entry('lib/a.dart', 'staged', 'modified')?['deletions'], 1);
        expect(entry('lib/a.dart', 'unstaged', 'modified')?['additions'], 2);
        expect(entry('lib/a.dart', 'unstaged', 'modified')?['deletions'], 0);
        expect(entry('lib/b.dart', 'staged', 'added')?['additions'], 3);
        expect(entry('bin.png', 'staged', 'modified')?['additions'], isNull);
        expect(entry('new.txt', 'untracked', 'untracked'), isNotNull);
        expect(
          entry('new.txt', 'untracked', 'untracked')?['additions'],
          isNull,
        );
        final renamed = entry('lib/renamed.dart', 'staged', 'renamed');
        expect(renamed?['oldPath'], 'lib/old.dart');
        expect(renamed?['additions'], 2);
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test(
      'changes trims ahead/behind and flags detached/unborn branch lines',
      () async {
        final temp = await seedWorkspace();
        try {
          Future<Map<String, dynamic>> changesFor(String branchLine) async {
            final runner = _ScriptedGitRunner((args) {
              if (_containsInOrder(args, [
                'status',
                '--short',
                '--branch',
                '-z',
              ])) {
                return {'exitCode': 0, 'stdout': '$branchLine\x00?? note.md'};
              }
              return {'exitCode': 0, 'stdout': ''};
            });
            final provider = providerWithChanges(
              workspace: Directory('${temp.path}/workspace'),
              runner: runner,
            );
            return provider.changes({'directory': 'repo'});
          }

          // Tracking with divergence → bare branch name only.
          var r = await changesFor('## main...origin/main [ahead 2, behind 1]');
          expect(r['branch'], 'main');
          expect(r['detached'], false);
          expect(r['noCommits'], false);

          // Gone upstream → still just the branch name.
          r = await changesFor('## feature...origin/feature [gone]');
          expect(r['branch'], 'feature');

          // Detached HEAD → empty branch, detached flag set.
          r = await changesFor('## HEAD (no branch)');
          expect(r['branch'], '');
          expect(r['detached'], true);

          // Unborn branch → keeps the name, flags noCommits.
          r = await changesFor('## No commits yet on main');
          expect(r['branch'], 'main');
          expect(r['noCommits'], true);
        } finally {
          await temp.delete(recursive: true);
        }
      },
    );

    test('changes resolves an absolutePath repository', () async {
      final temp = await seedWorkspace();
      try {
        final repo = Directory('${temp.path}/workspace/repo');
        final runner = _ScriptedGitRunner((args) {
          if (_containsInOrder(args, ['status', '--short', '--branch', '-z'])) {
            return {'exitCode': 0, 'stdout': '## main\x00?? note.md'};
          }
          return {'exitCode': 0, 'stdout': ''};
        });
        final provider = providerWithChanges(
          workspace: Directory('${temp.path}/workspace'),
          runner: runner,
        );
        final result = await provider.changes({'absolutePath': repo.path});
        expect(result['success'], true, reason: result.toString());
        expect(result['branch'], 'main');
        final entries = (result['entries'] as List).cast<Map>();
        expect(
          entries.any(
            (e) => e['path'] == 'note.md' && e['area'] == 'untracked',
          ),
          true,
        );
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test(
      'stage runs git add with validated paths and rejects traversal',
      () async {
        final temp = await seedWorkspace();
        try {
          final runner = _ScriptedGitRunner((args) => {'exitCode': 0});
          final provider = providerWithChanges(
            workspace: Directory('${temp.path}/workspace'),
            runner: runner,
          );
          final ok = await provider.stage({
            'directory': 'repo',
            'paths': ['lib/a.dart', 'lib/b.dart'],
          });
          expect(ok['success'], true);
          expect(
            runner.calls.any(
              (args) => _containsInOrder(args, [
                'add',
                '--',
                'lib/a.dart',
                'lib/b.dart',
              ]),
            ),
            true,
          );

          final bad = await provider.stage({
            'directory': 'repo',
            'paths': ['../etc/passwd'],
          });
          expect(bad['success'], false);
        } finally {
          await temp.delete(recursive: true);
        }
      },
    );

    test('stage all and unstage build the expected commands', () async {
      final temp = await seedWorkspace();
      try {
        final runner = _ScriptedGitRunner((args) => {'exitCode': 0});
        final provider = providerWithChanges(
          workspace: Directory('${temp.path}/workspace'),
          runner: runner,
        );
        await provider.stage({'directory': 'repo', 'paths': const []});
        expect(
          runner.calls.any(
            (args) => _containsInOrder(args, ['add', '--', '.']),
          ),
          true,
        );

        await provider.unstage({
          'directory': 'repo',
          'paths': ['lib/a.dart'],
        });
        expect(
          runner.calls.any(
            (args) =>
                _containsInOrder(args, ['reset', '-q', '--', 'lib/a.dart']),
          ),
          true,
        );
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('discard restores tracked and cleans untracked', () async {
      final temp = await seedWorkspace();
      try {
        final runner = _ScriptedGitRunner((args) {
          if (_containsInOrder(args, ['status', '--short', '-z'])) {
            return {'exitCode': 0, 'stdout': 'M  lib/a.dart\x00?? junk.txt'};
          }
          return {'exitCode': 0};
        });
        final provider = providerWithChanges(
          workspace: Directory('${temp.path}/workspace'),
          runner: runner,
        );
        final result = await provider.discard({
          'directory': 'repo',
          'paths': ['lib/a.dart', 'junk.txt'],
        });
        expect(result['success'], true, reason: result.toString());
        expect(
          runner.calls.any(
            (args) => _containsInOrder(args, ['restore', '--', 'lib/a.dart']),
          ),
          true,
        );
        expect(
          runner.calls.any(
            (args) => _containsInOrder(args, ['clean', '-f', '--', 'junk.txt']),
          ),
          true,
        );
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('commit passes the message and tolerates nothing-to-commit', () async {
      final temp = await seedWorkspace();
      try {
        final runner = _ScriptedGitRunner((args) {
          if (_containsInOrder(args, ['commit', '-m'])) {
            return {
              'exitCode': 1,
              'stdout': 'nothing to commit, working tree clean',
            };
          }
          return {'exitCode': 0};
        });
        final provider = providerWithChanges(
          workspace: Directory('${temp.path}/workspace'),
          runner: runner,
        );
        final result = await provider.commit({
          'directory': 'repo',
          'message': 'Fix things',
        });
        expect(result['success'], true, reason: result.toString());
        expect(
          runner.calls.any(
            (args) => _containsInOrder(args, ['commit', '-m', 'Fix things']),
          ),
          true,
        );

        final empty = await provider.commit({
          'directory': 'repo',
          'message': '',
        });
        expect(empty['success'], false);
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('fileDiff bails with tooLarge past the line budget', () async {
      final temp = await seedWorkspace();
      try {
        final runner = _ScriptedGitRunner((args) {
          if (_containsInOrder(args, ['diff', '--numstat']) &&
              args.contains('--cached')) {
            return {'exitCode': 0, 'stdout': '600\t10\tlib/big.dart'};
          }
          if (_containsInOrder(args, ['diff', '--numstat'])) {
            return {'exitCode': 0, 'stdout': ''};
          }
          return {'exitCode': 0, 'stdout': ''};
        });
        final provider = providerWithChanges(
          workspace: Directory('${temp.path}/workspace'),
          runner: runner,
        );
        final big = await provider.fileDiff({
          'directory': 'repo',
          'path': 'lib/big.dart',
          'cached': true,
        });
        expect(big['success'], true);
        expect(big['tooLarge'], true);
        // Never fetched the full diff for the oversized change.
        expect(
          runner.calls.any(
            (args) =>
                _containsInOrder(args, ['diff', '--no-color', '--cached']),
          ),
          false,
        );

        final empty = await provider.fileDiff({
          'directory': 'repo',
          'path': 'lib/none.dart',
        });
        expect(empty['success'], true);
        expect(empty['empty'], true);
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('fileDiff returns the unified diff text for a small change', () async {
      final temp = await seedWorkspace();
      try {
        final runner = _ScriptedGitRunner((args) {
          if (_containsInOrder(args, ['diff', '--numstat'])) {
            return {'exitCode': 0, 'stdout': '2\t1\tlib/main.dart'};
          }
          if (_containsInOrder(args, ['diff', '--no-color'])) {
            return {
              'exitCode': 0,
              'stdout':
                  '@@ -1,2 +1,3 @@\n void main() {\n-  print("hi");\n'
                  '+  print("hello");\n',
            };
          }
          return {'exitCode': 0};
        });
        final provider = providerWithChanges(
          workspace: Directory('${temp.path}/workspace'),
          runner: runner,
        );
        final result = await provider.fileDiff({
          'directory': 'repo',
          'path': 'lib/main.dart',
        });
        expect(result['success'], true);
        expect(result['tooLarge'], isNull);
        expect(result['stdout'] as String, contains('@@ -1,2 +1,3 @@'));
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('commit history and commit diff parse git graph output', () async {
      final temp = await seedWorkspace();
      try {
        final runner = _ScriptedGitRunner((args) {
          if (_containsInOrder(args, ['log', '--graph'])) {
            return {
              'exitCode': 0,
              'stdout':
                  '* \x1fabc123\x1fabc123\x1fdef456\x1fAda\x1fada@example.test\x1f'
                  '2026-01-02T03:04:05+00:00\x1fHEAD -> main\x1fAdd graph\n'
                  '| * \x1fdef456\x1fdef456\x1f\x1fBen\x1fben@example.test\x1f'
                  '2026-01-01T03:04:05+00:00\x1f\x1fInitial',
            };
          }
          if (_containsInOrder(args, ['show', '--format=', '--numstat'])) {
            return {'exitCode': 0, 'stdout': '2\t1\tlib/main.dart'};
          }
          if (_containsInOrder(args, ['show', '--no-color', '--format='])) {
            return {
              'exitCode': 0,
              'stdout':
                  '@@ -1,2 +1,3 @@\n void main() {\n-  print("hi");\n'
                  '+  print("graph");\n',
            };
          }
          return {'exitCode': 0};
        });
        final provider = providerWithChanges(
          workspace: Directory('${temp.path}/workspace'),
          runner: runner,
        );

        final history = await provider.commitHistory({'directory': 'repo'});
        expect(history['success'], true, reason: history.toString());
        final commits = (history['commits'] as List).cast<Map>();
        expect(commits.first['hash'], 'abc123');
        expect(commits.first['graph'], '*');
        expect(commits.first['subject'], 'Add graph');
        expect(commits.first['refs'], 'HEAD -> main');
        final logCall = runner.calls.firstWhere(
          (args) => _containsInOrder(args, ['log', '--graph']),
        );
        expect(logCall, isNot(contains('--all')));

        final diff = await provider.commitDiff({
          'directory': 'repo',
          'hash': 'abc123',
        });
        expect(diff['success'], true, reason: diff.toString());
        expect((diff['files'] as List).first['path'], 'lib/main.dart');
        expect(diff['stdout'], contains('print("graph")'));
      } finally {
        await temp.delete(recursive: true);
      }
    });
  });
}

class _RecordingMobileGitRunner extends DemoGitRunner {
  List<String> lastArgs = const [];
  final calls = <List<String>>[];
  String? lastWorkingDirectory;

  @override
  String repositoryPath(String relativePath, String realPath) =>
      '/workspace/$relativePath';

  @override
  String workspacePath(String realPath) => '/workspace';

  @override
  Future<Map<String, dynamic>> runGit(
    List<String> args, {
    String? workingDirectory,
    Duration timeout = const Duration(seconds: 60),
    int outputLimit = 6000,
  }) async {
    calls.add(List.unmodifiable(args));
    lastArgs = List.unmodifiable(args);
    lastWorkingDirectory = workingDirectory;
    // Tests mark repos with a real `.git` dir; confirm the rev-parse probe so
    // the provider treats the workspace folder as a git repository.
    if (_containsInOrder(args, ['rev-parse', '--is-inside-work-tree'])) {
      return const {
        'providerAvailable': true,
        'exitCode': 0,
        'stdout': 'true',
        'stderr': '',
        'durationMs': 1,
      };
    }
    return {
      'providerAvailable': true,
      'exitCode': 0,
      'stdout': '',
      'stderr': '',
      'durationMs': 1,
    };
  }
}

class _ScriptedGitRunner extends DemoGitRunner {
  _ScriptedGitRunner(this.handler);

  final Map<String, dynamic> Function(List<String> args) handler;
  final calls = <List<String>>[];

  @override
  String repositoryPath(String relativePath, String realPath) =>
      '/workspace/$relativePath';

  @override
  String workspacePath(String realPath) => '/workspace';

  @override
  Future<Map<String, dynamic>> runGit(
    List<String> args, {
    String? workingDirectory,
    Duration timeout = const Duration(seconds: 60),
    int outputLimit = 6000,
  }) async {
    calls.add(List.unmodifiable(args));
    // Tests create a real `.git` directory on disk to mark a workspace folder
    // as a repo; the provider now confirms that via `rev-parse
    // --is-inside-work-tree`, which scripted handlers don't stub. Answer it
    // here so individual tests stay focused on the git commands they assert.
    if (_containsInOrder(args, ['rev-parse', '--is-inside-work-tree'])) {
      return const {
        'providerAvailable': true,
        'exitCode': 0,
        'stdout': 'true',
        'stderr': '',
        'durationMs': 1,
      };
    }
    final scripted = handler(args);
    return {
      'providerAvailable': true,
      'exitCode': scripted['exitCode'] as int? ?? 0,
      'stdout': scripted['stdout'] as String? ?? '',
      'stderr': scripted['stderr'] as String? ?? '',
      'durationMs': 1,
    };
  }
}

bool _containsInOrder(List<String> args, List<String> expected) {
  var index = 0;
  for (final arg in args) {
    if (arg == expected[index]) {
      index += 1;
      if (index == expected.length) return true;
    }
  }
  return false;
}
