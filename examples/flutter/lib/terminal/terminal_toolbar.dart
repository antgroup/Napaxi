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
  });

  final Terminal terminal;

  @override
  State<TerminalToolbar> createState() => _TerminalToolbarState();
}

class _TerminalToolbarState extends State<TerminalToolbar> {
  bool _ctrlActive = false;
  bool _shiftActive = false;
  bool _altActive = false;

  void _clearModifiers() {
    if (_ctrlActive || _shiftActive || _altActive) {
      setState(() {
        _ctrlActive = false;
        _shiftActive = false;
        _altActive = false;
      });
    }
  }

  void _toggleModifier(String which) {
    setState(() {
      switch (which) {
        case 'ctrl':
          _ctrlActive = !_ctrlActive;
          break;
        case 'shift':
          _shiftActive = !_shiftActive;
          break;
        case 'alt':
          _altActive = !_altActive;
          break;
      }
    });
  }

  /// Send a key with any currently-active modifiers, then clear modifiers.
  void _sendKey(TerminalKey key) {
    widget.terminal.keyInput(
      key,
      ctrl: _ctrlActive,
      shift: _shiftActive,
      alt: _altActive,
    );
    _clearModifiers();
  }

  @override
  Widget build(BuildContext context) {
    // Only show on mobile platforms.
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFD1D5DB))),
        color: Color(0xFFF9FAFB),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRow([
            _VirtualKeyButton(label: 'Esc', onTap: () => _sendKey(TerminalKey.escape)),
            _VirtualKeyButton(label: 'Tab', onTap: () => _sendKey(TerminalKey.tab)),
            _ModifierButton(
              label: 'Ctrl',
              active: _ctrlActive,
              onTap: () => _toggleModifier('ctrl'),
            ),
            _VirtualKeyButton(
              label: '↑',
              onTap: () => _sendKey(TerminalKey.arrowUp),
            ),
            _ModifierButton(
              label: 'Shift',
              active: _shiftActive,
              onTap: () => _toggleModifier('shift'),
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
              active: _altActive,
              onTap: () => _toggleModifier('alt'),
            ),
            _VirtualKeyButton(
              label: 'Space',
              onTap: () => _sendKey(TerminalKey.space),
            ),
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
    );
  }

  Widget _buildRow(List<Widget> children) {
    return Row(
      children: children
          .expand((w) => [Expanded(child: w), const SizedBox(width: 3)])
          .toList()
        ..removeLast(), // Remove trailing spacer
    );
  }
}

/// A regular virtual key button (Esc, Tab, arrows, etc.).
class _VirtualKeyButton extends StatelessWidget {
  const _VirtualKeyButton({
    required this.label,
    required this.onTap,
  });

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