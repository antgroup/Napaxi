part of '../main.dart';

/// 沙箱交互式终端页。
///
/// 用 xterm widget 渲染，背后接一个可替换的 [TerminalBackend]。默认用
/// [ReplTerminalBackend]（跑在现有 `executeLinuxProgram` 上）；测试或未来的
/// 原生 PTY 后端可通过 [backendFactory] 注入。
class SandboxTerminalScreen extends StatefulWidget {
  const SandboxTerminalScreen({
    super.key,
    this.backendFactory,
    this.workspaceDir,
  });

  /// 后端工厂（测试注入 / 未来 PTY 替换）。为空时用 [ReplTerminalBackend]。
  final TerminalBackend Function()? backendFactory;

  /// host 侧沙箱 workspace 目录，传给 [ReplTerminalBackend]。
  final String? workspaceDir;

  @override
  State<SandboxTerminalScreen> createState() => _SandboxTerminalScreenState();
}

class _SandboxTerminalScreenState extends State<SandboxTerminalScreen> {
  late final Terminal _terminal;
  final TerminalController _controller = TerminalController();
  final TerminalModifierController _modifiers = TerminalModifierController();
  late final TerminalBackend _backend;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);
    _backend =
        widget.backendFactory?.call() ??
        ReplTerminalBackend(workspaceDir: widget.workspaceDir ?? '/workspace');

    // backend 输出 → 屏幕
    _sub = _backend.output.listen(_terminal.write);
    // 键入 → backend stdin
    _terminal.onOutput = (data) =>
        _backend.write(_modifiers.consumeTextInput(data));
    // 尺寸变化 → backend
    _terminal.onResize = (w, h, pw, ph) => _backend.resize(w, h);

    _backend.start(
      argv: const ['/bin/sh', '-lc'],
      workdir: '/workspace',
      cols: _terminal.viewWidth,
      rows: _terminal.viewHeight,
    );
  }

  @override
  void dispose() {
    _sub?.cancel(); // 先断订阅，避免写已 dispose 的 terminal
    _backend.kill();
    _modifiers.dispose();
    super.dispose();
  }

  /// 测试辅助：读出终端 buffer 文本（xterm 用 CustomPaint 渲染，find.text 无效）。
  @visibleForTesting
  String get bufferText => _terminal.buffer.getText();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(strings.terminalTitle)),
      body: SafeArea(
        child: TerminalViewWrapper(
          terminal: _terminal,
          backend: _backend,
          child: Column(
            children: [
              Expanded(
                child: TerminalView(
                  _terminal,
                  controller: _controller,
                  autofocus: true,
                ),
              ),
              if (Platform.isAndroid || Platform.isIOS)
                TerminalToolbar(terminal: _terminal, modifiers: _modifiers),
            ],
          ),
        ),
      ),
    );
  }
}
