part of '../main.dart';

/// 今天的终端实现：把请求/响应式的 `executeLinuxProgram` 适配成 [TerminalBackend]
/// 的流式接口。
///
/// 行模式 REPL——每行命令是一次独立的 `executeLinuxProgram` 调用。channel 处理
/// 照搬 [AndroidLinuxDemoGitRunner]（同一个 `platform_context` channel、`.timeout()`、
/// catch `TimeoutException`/`PlatformException`/`MissingPluginException`）。
///
/// 诚实的限制（屏幕 banner 里也会写明）：
/// - 命令执行**期间不流式**：输出在命令结束后才整块出现。`tail -f`/`top` 会卡到超时。
/// - **无 Ctrl-C / 信号**：没有 stdin 连到活进程，执行期间键入被丢弃。
/// - **无 vim/less/python REPL** 等交互程序（需要活 tty）。
/// - 子程序自身的 ANSI 颜色能透传（xterm 渲染，所以 `ls --color` 实际可用）。
///
/// 同事的原生 PTY 后端落地后，只需用一个实现了 [TerminalBackend] 的 PTY wrapper
/// 替换本类，widget 和 UI 无需改动。
class ReplTerminalBackend implements TerminalBackend {
  ReplTerminalBackend({required this.workspaceDir});

  static const MethodChannel _channel = MethodChannel(
    'com.napaxi.flutter/platform_context',
  );

  final String workspaceDir;

  final StreamController<String> _out = StreamController<String>.broadcast();
  final StringBuffer _lineBuffer = StringBuffer();
  String _cwd = '/workspace';
  bool _busy = false;
  bool _closed = false;

  @override
  Stream<String> get output => _out.stream;

  @override
  Future<int>? get exitCode => null; // REPL「shell」不退出

  @override
  Future<void> start({
    required List<String> argv,
    required String workdir,
    required int cols,
    required int rows,
  }) async {
    _cwd = workdir.isNotEmpty ? workdir : '/workspace';
    _emit('napaxi sandbox shell (REPL mode)\r\n');
    _emit(
      '\x1b[90mLimited: no streaming, no Ctrl-C, no vim/colors. '
      'One command per line.\x1b[0m\r\n',
    );
    _prompt();
  }

  void _emit(String data) {
    if (!_closed) _out.add(data);
  }

  void _prompt() => _emit('\x1b[32m$_cwd\x1b[0m \$ ');

  @override
  void write(String data) {
    if (_busy || _closed) return; // 命令执行期间丢弃键入（REPL 无法 Ctrl-C）
    for (final ch in data.split('')) {
      if (ch == '\r' || ch == '\n') {
        _emit('\r\n');
        final line = _lineBuffer.toString();
        _lineBuffer.clear();
        unawaited(_runLine(line));
        return; // 一次只处理一行；后续字符等命令结束
      } else if (ch == '\x7f' || ch == '\b') {
        if (_lineBuffer.isNotEmpty) {
          final current = _lineBuffer.toString();
          _lineBuffer
            ..clear()
            ..write(current.substring(0, current.length - 1));
          _emit('\b \b'); // 屏幕上擦除一个字符
        }
      } else {
        _lineBuffer.write(ch);
        _emit(ch); // 本地回显
      }
    }
  }

  Future<void> _runLine(String line) async {
    final cmd = line.trim();
    if (cmd.isEmpty) {
      _prompt();
      return;
    }
    _busy = true;
    try {
      // cwd 跟踪：在已记录的 cwd 里执行，并在末尾用 marker 打印新的 pwd，
      // 这样 `cd` 才能跨命令生效（否则每条命令都是全新进程）。
      final wrapped =
          'cd ${_shQuote(_cwd)} && { $cmd; } ; __rc=\$? ; '
          'printf "\\n__NAPAXI_CWD__%s\\n" "\$(pwd)" ; exit \$__rc';
      final response = await _channel
          .invokeMethod<String>('executeLinuxProgram', {
            'workspaceDir': workspaceDir,
            'argv': ['/bin/sh', '-lc', wrapped],
            'workdir': _cwd,
            'timeout': 60,
          })
          .timeout(const Duration(seconds: 65));
      final decoded = jsonDecode(response ?? '{}');
      final map = decoded is Map ? Map<String, dynamic>.from(decoded) : {};
      var stdout = (map['stdout'] ?? '').toString();
      final stderr = (map['stderr'] ?? '').toString();

      // 剥出 cwd marker，更新会话 cwd。
      final marker = RegExp(r'__NAPAXI_CWD__(.*)\r?\n?$');
      final m = marker.firstMatch(stdout);
      if (m != null) {
        final next = m.group(1)?.trim();
        if (next != null && next.isNotEmpty) _cwd = next;
        stdout = stdout.replaceAll(marker, '');
      }

      if (stdout.isNotEmpty) _emit(_toCrlf(stdout));
      if (stderr.isNotEmpty) _emit('\x1b[31m${_toCrlf(stderr)}\x1b[0m');
    } on MissingPluginException {
      _emit(
        '\x1b[31m[terminal] native exec bridge unavailable on this '
        'platform\x1b[0m\r\n',
      );
    } on PlatformException catch (e) {
      _emit('\x1b[31m[terminal] ${e.message ?? e.code}\x1b[0m\r\n');
    } on TimeoutException {
      _emit('\x1b[31m[terminal] command timed out (60s)\x1b[0m\r\n');
    } catch (e) {
      _emit('\x1b[31m[terminal] $e\x1b[0m\r\n');
    } finally {
      _busy = false;
      if (!_closed) _prompt();
    }
  }

  // 终端需要 CRLF；把裸 \n 转成 \r\n（已是 \r\n 的不重复加）。
  String _toCrlf(String s) => s.replaceAll(RegExp(r'(?<!\r)\n'), '\r\n');

  // POSIX 单引号转义，安全拼进 sh -lc。
  String _shQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

  @override
  void resize(int cols, int rows) {
    // REPL 无活 tty，记录后忽略（未来 PTY 后端会真正 resize）。
  }

  @override
  Future<void> kill() async {
    _closed = true;
    await _out.close();
  }
}
