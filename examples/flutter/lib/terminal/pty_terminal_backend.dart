part of '../main.dart';

/// PTY-backed terminal using the Napaxi Android sandbox bridge.
///
/// Android only — on other platforms [SandboxTerminalScreen] falls back to
/// [ReplTerminalBackend].
///
/// On mobile, TUI programs (claude code, codex, vim, etc.) switch to the
/// alternate screen buffer via `\x1b[?1049h`. On a phone-sized viewport this
/// is usually undesirable: the alt buffer has no scrollback, the virtual
/// keyboard covers half the screen, and the user cannot scroll back to see
/// earlier output. We strip the switch-sequence so the TUI renders in the
/// main buffer with full scrollback, while the program still thinks it is in
/// full-screen mode (cursor positioning, colors, erase-in-display, etc. all
/// work fine in the main buffer).
class PtyTerminalBackend implements TerminalBackend {
  PtyTerminalBackend({this.workspaceDir});

  final String? workspaceDir;
  int? _sessionId;
  bool _closed = false;
  final StreamController<String> _out = StreamController<String>.broadcast();
  final List<String> _pendingOutput = [];
  StreamSubscription<dynamic>? _eventSub;
  final Completer<int> _exitCompleter = Completer<int>();

  @override
  Stream<String> get output => _out.stream;

  @override
  Future<int>? get exitCode => _exitCompleter.future;

  @override
  Future<void> start({
    required List<String> argv,
    required String workdir,
    required int cols,
    required int rows,
  }) async {
    _eventSub = SandboxPtyEvents.shared.listen(
      _handleEvent,
      onError: (Object error) {
        if (!_out.isClosed) {
          _out.add('\x1b[31m[pty] event stream error: $error\x1b[0m\r\n');
        }
      },
    );
    await SandboxPtyEvents.method.invokeMethod<void>('initialize');
    final request = <String, Object>{
      'cols': cols,
      'rows': rows,
      'argv': const ['/bin/sh'],
      'workdir': workdir,
    };
    final hostWorkspace = workspaceDir?.trim();
    if (hostWorkspace != null &&
        hostWorkspace.isNotEmpty &&
        hostWorkspace != '/workspace') {
      request['workspaceDir'] = hostWorkspace;
    }
    final id = await SandboxPtyEvents.method.invokeMethod<int>('openSession', request);
    _sessionId = id;
    if (_pendingOutput.isNotEmpty) {
      for (final data in _pendingOutput) {
        final filtered = _stripAltScreenSwitch(data);
        if (filtered.isNotEmpty && !_out.isClosed) {
          _out.add(filtered);
        }
      }
      _pendingOutput.clear();
    }
  }

  void _handleEvent(dynamic raw) {
    if (_closed || raw is! Map) return;
    final map = Map<String, dynamic>.from(raw);
    final sid = map['sessionId'];
    if (_sessionId != null && sid != _sessionId) return;
    final kind = map['kind'] as String?;
    switch (kind) {
      case 'SessionOutput':
        final data = map['data'];
        if (data is String && data.isNotEmpty) {
          final filtered = _stripAltScreenSwitch(data);
          if (filtered.isNotEmpty) {
            if (_sessionId == null) {
              _pendingOutput.add(filtered);
            } else {
              _out.add(filtered);
            }
          }
        }
      case 'SessionExit':
        final code = map['exitCode'] as int? ?? -1;
        if (!_exitCompleter.isCompleted) _exitCompleter.complete(code);
        _cleanup();
      case 'SessionClosed':
        if (!_exitCompleter.isCompleted) _exitCompleter.complete(-1);
        _cleanup();
    }
  }

  @override
  void write(String data) {
    final id = _sessionId;
    if (id == null || _closed) return;
    SandboxPtyEvents.method.invokeMethod<void>('writeSession', {'sessionId': id, 'data': data});
  }

  @override
  void resize(int cols, int rows) {
    final id = _sessionId;
    if (id == null || _closed) return;
    SandboxPtyEvents.method.invokeMethod<void>('resizeSession', {
      'sessionId': id,
      'cols': cols,
      'rows': rows,
    });
  }

  @override
  Future<void> kill() async {
    if (_closed) return;
    _closed = true;
    final id = _sessionId;
    if (id != null) {
      _sessionId = null;
      try {
        await SandboxPtyEvents.method.invokeMethod<void>('closeSession', {'sessionId': id});
      } catch (_) {}
    }
    _cleanup();
  }

  void _cleanup() {
    _closed = true;
    _eventSub?.cancel();
    _eventSub = null;
    if (!_out.isClosed) _out.close();
  }

  /// Strips DECSET/DECRST sequences that toggle the alternate screen buffer.
  ///
  /// - `\x1b[?1049h` — enter alternate screen (save cursor + switch to alt buffer)
  /// - `\x1b[?1047h` — switch to alt buffer only (used by some programs)
  /// - `\x1b[?1049l` — leave alternate screen
  /// - `\x1b[?1047l` — switch back to main buffer only
  ///
  /// We also strip the paired cursor-save/restore sequences that 1049h/l
  /// imply so the saved-cursor slot stays consistent with the main buffer:
  /// - `\x1b[s` / `\x1b7` — save cursor position (DECSC)
  /// - `\x1b[u` / `\x1b8` — restore cursor position (DECRC)
  ///
  /// Other DECSET/DECRST sequences (e.g. `\x1b[?1h` cursor keys, `\x1b[?25h`
  /// show cursor) pass through untouched.
  static String _stripAltScreenSwitch(String data) {
    // Fast path: if none of the target sequences are present, skip allocation.
    if (!data.contains('\x1b[')) return data;
    // Match: ESC [ ? <digits> h/l  where digits is one of 1047, 1048, 1049
    // Also strip standalone DECSC/DECRC that the 1049 pair triggers.
    return data.replaceAllMapped(
      RegExp(r'\x1b\[\?(1047|1048|1049)[hl]'),
      (_) => '',
    );
  }
}
