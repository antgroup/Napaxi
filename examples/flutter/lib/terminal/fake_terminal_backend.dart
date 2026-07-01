part of '../main.dart';

/// 纯内存的测试用后端：无 platform channel，`flutter test` 里安全。
///
/// `start()` 发欢迎 banner（测试锚点 `napaxi fake terminal ready`），`write` 回显，
/// 遇换行补提示符。
class FakeTerminalBackend implements TerminalBackend {
  final StreamController<String> _out = StreamController<String>.broadcast();
  bool _closed = false;

  @override
  Stream<String> get output => _out.stream;

  @override
  Future<int>? get exitCode => null;

  @override
  Future<void> start({
    required List<String> argv,
    required String workdir,
    required int cols,
    required int rows,
  }) async {
    _emit('napaxi fake terminal ready\r\n\$ ');
  }

  void _emit(String data) {
    if (!_closed) _out.add(data);
  }

  @override
  void write(String data) {
    _emit(data); // 回显
    if (data.contains('\r') || data.contains('\n')) _emit('\$ ');
  }

  @override
  void resize(int cols, int rows) {}

  @override
  Future<void> kill() async {
    _closed = true;
    await _out.close();
  }
}
