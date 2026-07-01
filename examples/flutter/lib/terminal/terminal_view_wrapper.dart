part of '../main.dart';

/// Wraps a [TerminalView] with a keyboard-resize pulse.
///
/// When the software keyboard appears / disappears the PTY backend is resized
/// at staggered delays to capture the final viewport size after the animation
/// settles, mirroring Paseo's `pulseKeyboardRefits` pattern.
///
/// This widget is a transparent pass-through for its child — scrolling and
/// virtual-key behaviours are handled by the caller's layout.
class TerminalViewWrapper extends StatefulWidget {
  const TerminalViewWrapper({
    super.key,
    required this.terminal,
    required this.backend,
    required this.child,
  });

  final Terminal terminal;
  final TerminalBackend backend;
  final Widget child;

  @override
  State<TerminalViewWrapper> createState() => _TerminalViewWrapperState();
}

class _TerminalViewWrapperState extends State<TerminalViewWrapper>
    with WidgetsBindingObserver {
  final List<Timer> _resizeTimers = [];

  // Delay pattern matching Paseo's TERMINAL_REFIT_DELAYS_MS.
  static const _refitDelays = [0, 48, 144, 320];

  bool _keyboardVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleRefitOnFrame();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final keyboardUp = view.viewInsets.bottom > 0;
    if (keyboardUp == _keyboardVisible) return;
    _keyboardVisible = keyboardUp;
    _pulseRefits();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelTimers();
    super.dispose();
  }

  void _cancelTimers() {
    for (final t in _resizeTimers) {
      t.cancel();
    }
    _resizeTimers.clear();
  }

  void _scheduleRefitOnFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pulseRefits();
    });
  }

  void _pulseRefits() {
    _cancelTimers();
    _refitBackend();
    for (final delay in _refitDelays) {
      _resizeTimers.add(Timer(Duration(milliseconds: delay), () {
        if (!mounted) return;
        _refitBackend();
      }));
    }
  }

  void _refitBackend() {
    final cols = widget.terminal.viewWidth;
    final rows = widget.terminal.viewHeight;
    if (cols > 0 && rows > 0) {
      widget.backend.resize(cols, rows);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
