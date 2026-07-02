part of '../main.dart';

/// A mobile-only virtual keyboard toolbar for the terminal.
///
/// Provides TUI-essential keys that are absent from the on-screen software
/// keyboard: Escape, Tab, arrow keys, and sticky Ctrl / Shift / Alt modifiers.
///
/// Modifier buttons are *sticky*: tapping Ctrl highlights it; the next
/// non-modifier tap sends Ctrl+Key and auto-clears the modifier. This mirrors
/// the behaviour in Paseo's terminal-pane virtual keyboard bar.
class TerminalToolbar extends StatefulWidget {
  const TerminalToolbar({
    super.key,
    required this.terminal,
    required this.modifiers,
  });

  final Terminal terminal;
  final TerminalModifierController modifiers;

  @override
  State<TerminalToolbar> createState() => _TerminalToolbarState();
}

class _TerminalToolbarState extends State<TerminalToolbar> {
  /// Send a key with any currently-active modifiers, then clear modifiers.
  void _sendKey(TerminalKey key) {
    widget.terminal.keyInput(
      key,
      ctrl: widget.modifiers.ctrlActive,
      shift: widget.modifiers.shiftActive,
      alt: widget.modifiers.altActive,
    );
    widget.modifiers.clearModifiers();
  }

  void _sendText(String text) {
    widget.terminal.textInput(widget.modifiers.consumeTextInput(text));
  }

  @override
  Widget build(BuildContext context) {
    // Only show on mobile platforms.
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: widget.modifiers,
      builder: (context, _) => Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFD1D5DB))),
          color: Color(0xFFF9FAFB),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildRow([
              _VirtualKeyButton(
                label: 'Esc',
                onTap: () => _sendKey(TerminalKey.escape),
              ),
              _VirtualKeyButton(
                label: 'Tab',
                onTap: () => _sendKey(TerminalKey.tab),
              ),
              _ModifierButton(
                label: 'Ctrl',
                active: widget.modifiers.ctrlActive,
                onTap: widget.modifiers.toggleCtrl,
              ),
              _VirtualKeyButton(
                label: '↑',
                onTap: () => _sendKey(TerminalKey.arrowUp),
              ),
              _ModifierButton(
                label: 'Shift',
                active: widget.modifiers.shiftActive,
                onTap: widget.modifiers.toggleShift,
              ),
              _VirtualKeyButton(
                label: '⌫',
                onTap: () => _sendKey(TerminalKey.backspace),
              ),
            ]),
            const SizedBox(height: 4),
            _buildRow([
              _ModifierButton(
                label: 'Alt',
                active: widget.modifiers.altActive,
                onTap: widget.modifiers.toggleAlt,
              ),
              _VirtualKeyButton(label: 'Space', onTap: () => _sendText(' ')),
              _VirtualKeyButton(
                label: '←',
                onTap: () => _sendKey(TerminalKey.arrowLeft),
              ),
              _VirtualKeyButton(
                label: '↓',
                onTap: () => _sendKey(TerminalKey.arrowDown),
              ),
              _VirtualKeyButton(
                label: '→',
                onTap: () => _sendKey(TerminalKey.arrowRight),
              ),
              _VirtualKeyButton(
                label: '↵',
                onTap: () => _sendKey(TerminalKey.enter),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(List<Widget> children) {
    return Row(
      children:
          children
              .expand((w) => [Expanded(child: w), const SizedBox(width: 3)])
              .toList()
            ..removeLast(), // Remove trailing spacer
    );
  }
}

class TerminalModifierController extends ChangeNotifier {
  bool _ctrlActive = false;
  bool _shiftActive = false;
  bool _altActive = false;

  bool get ctrlActive => _ctrlActive;
  bool get shiftActive => _shiftActive;
  bool get altActive => _altActive;

  void toggleCtrl() => _set(ctrl: !_ctrlActive);
  void toggleShift() => _set(shift: !_shiftActive);
  void toggleAlt() => _set(alt: !_altActive);

  void clearModifiers() {
    if (!_ctrlActive && !_shiftActive && !_altActive) return;
    _ctrlActive = false;
    _shiftActive = false;
    _altActive = false;
    notifyListeners();
  }

  String consumeTextInput(String data) {
    if (data.isEmpty || (!_ctrlActive && !_shiftActive && !_altActive)) {
      return data;
    }

    var resolved = data;
    if (_ctrlActive) {
      resolved = _controlCharacterFor(data) ?? data;
    }
    if (_altActive) {
      resolved = '\x1b$resolved';
    }
    clearModifiers();
    return resolved;
  }

  void _set({bool? ctrl, bool? shift, bool? alt}) {
    final nextCtrl = ctrl ?? _ctrlActive;
    final nextShift = shift ?? _shiftActive;
    final nextAlt = alt ?? _altActive;
    if (nextCtrl == _ctrlActive &&
        nextShift == _shiftActive &&
        nextAlt == _altActive) {
      return;
    }
    _ctrlActive = nextCtrl;
    _shiftActive = nextShift;
    _altActive = nextAlt;
    notifyListeners();
  }

  static String? _controlCharacterFor(String data) {
    if (data.runes.length != 1) return null;
    final code = data.runes.single;
    if (code >= 0x61 && code <= 0x7a) {
      return String.fromCharCode(code - 0x60);
    }
    if (code >= 0x41 && code <= 0x5a) {
      return String.fromCharCode(code - 0x40);
    }
    return switch (code) {
      0x20 || 0x40 => '\x00',
      0x5b => '\x1b',
      0x5c => '\x1c',
      0x5d => '\x1d',
      0x5e => '\x1e',
      0x5f || 0x3f => '\x1f',
      _ => null,
    };
  }
}

/// A regular virtual key button (Esc, Tab, arrows, etc.).
class _VirtualKeyButton extends StatelessWidget {
  const _VirtualKeyButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFD1D5DB)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
      ),
    );
  }
}

/// A sticky modifier button (Ctrl, Shift, Alt).
class _ModifierButton extends StatelessWidget {
  const _ModifierButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF3B82F6) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? const Color(0xFF2563EB) : const Color(0xFFD1D5DB),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : const Color(0xFF374151),
          ),
        ),
      ),
    );
  }
}
