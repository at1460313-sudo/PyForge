import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

/// The custom keyboard bar: quick keys that make mobile Python editing
/// painless. Shown while the editor has focus, above the system keyboard.
class KeyboardBar extends StatelessWidget {
  const KeyboardBar({super.key, required this.controller});

  final CodeLineEditingController? controller;

  static const List<_KeyDef> _keys = <_KeyDef>[
    _KeyDef('Tab', _KeyAction.tab),
    _KeyDef('←', _KeyAction.left),
    _KeyDef('→', _KeyAction.right),
    _KeyDef('↑', _KeyAction.up),
    _KeyDef('↓', _KeyAction.down),
    _KeyDef('(', _KeyAction.text),
    _KeyDef(')', _KeyAction.text),
    _KeyDef('[', _KeyAction.text),
    _KeyDef(']', _KeyAction.text),
    _KeyDef('{', _KeyAction.text),
    _KeyDef('}', _KeyAction.text),
    _KeyDef(':', _KeyAction.text),
    _KeyDef(';', _KeyAction.text),
    _KeyDef("'", _KeyAction.text),
    _KeyDef('"', _KeyAction.text),
    _KeyDef('=', _KeyAction.text),
    _KeyDef('==', _KeyAction.text),
    _KeyDef('#', _KeyAction.text),
    _KeyDef('_', _KeyAction.text),
    _KeyDef('↺', _KeyAction.undo),
    _KeyDef('↻', _KeyAction.redo),
  ];

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SizedBox(
        height: 46,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          itemCount: _keys.length,
          itemBuilder: (BuildContext context, int index) {
            final _KeyDef key = _keys[index];
            final bool isAction =
                key.action != _KeyAction.text && key.action != _KeyAction.tab;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: isAction
                    ? scheme.primary.withValues(alpha: 0.15)
                    : scheme.surface,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _handle(key),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 44),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    child: Text(
                      key.label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isAction ? scheme.primary : scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _handle(_KeyDef key) {
    final CodeLineEditingController? c = controller;
    if (c == null) return;
    HapticFeedback.selectionClick();
    switch (key.action) {
      case _KeyAction.tab:
        c.replaceSelection('    ');
      case _KeyAction.left:
        c.moveCursor(AxisDirection.left);
      case _KeyAction.right:
        c.moveCursor(AxisDirection.right);
      case _KeyAction.up:
        c.moveCursor(AxisDirection.up);
      case _KeyAction.down:
        c.moveCursor(AxisDirection.down);
      case _KeyAction.undo:
        if (c.canUndo) c.undo();
      case _KeyAction.redo:
        if (c.canRedo) c.redo();
      case _KeyAction.text:
        c.replaceSelection(key.label);
    }
  }
}

enum _KeyAction { tab, left, right, up, down, undo, redo, text }

class _KeyDef {
  const _KeyDef(this.label, this.action);
  final String label;
  final _KeyAction action;
}
