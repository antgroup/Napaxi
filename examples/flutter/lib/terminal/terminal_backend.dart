part of '../main.dart';

/// PTY 形状的终端后端契约。
///
/// 终端 widget（xterm）只和这个接口对话，所以「今天跑在 `executeLinuxProgram`
/// 上的 REPL 适配器」和「未来同事的原生 PTY 后端」可以互换——升级时只换实现，
/// widget 和 UI 零返工。
///
/// 接口故意照「能力更大的 PTY」来设计：它是 PTY（`write`/`output`/`resize`/
/// `exitCode`）的严格子集、又是 xterm 所需的严格超集。让能力更小的 REPL 去
/// 降级适配它——反过来 PTY 会塞不进去。
abstract class TerminalBackend {
  /// 启动会话。`cols`/`rows` 让真 PTY 给 tty 设定初始尺寸；REPL 适配器记录后忽略。
  Future<void> start({
    required List<String> argv, // ['/bin/sh', '-lc'] 登录 shell
    required String workdir, // '/workspace'
    required int cols,
    required int rows,
  });

  /// 用户键入 / stdin。xterm 的 `onOutput` 原样喂入。
  void write(String data);

  /// 终端尺寸变化。xterm 的 `onResize` 喂入。
  void resize(int cols, int rows);

  /// 要渲染的字节流（broadcast）。screen 订阅后 pipe 给 `terminal.write`。
  Stream<String> get output;

  /// 终止会话、释放资源。
  Future<void> kill();

  /// 会话结束时完成。真 PTY 进程退出时给出退出码；REPL「shell」概念上不退出 →
  /// 返回 `null`。
  Future<int>? get exitCode;
}
