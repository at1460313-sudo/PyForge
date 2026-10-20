import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../theme/app_theme.dart';

/// The custom keyboard bar: quick keys that make mobile Python editing
/// painless. Shown while the editor has focus, above the system keyboard.
class KeyboardBar extends StatelessWidget {
  const KeyboardBar({super.key, required this.controller});

  final CodeLineEditingController? controller;

  static const List<_KeyDef> _keys = <_KeyDef>[
    _KeyDef('Tab', _KeyAction.tab, icon: Icons.keyboard_tab_rounded),
    _KeyDef('←', _KeyAction.left, icon: Icons.arrow_back_rounded),
    _KeyDef('↓', _KeyAction.down, icon: Icons.arrow_downward_rounded),
    _KeyDef('↑', _KeyAction.up, icon: Icons.arrow_upward_rounded),
    _KeyDef('→', _KeyAction.right, icon: Icons.arrow_forward_rounded),
    _KeyDef('↺', _KeyAction.undo, icon: Icons.undo_rounded),
    _KeyDef('↻', _KeyAction.redo, icon: Icons.redo_rounded),
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
  ];

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        height: 56,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          itemCount: _keys.length,
          itemBuilder: (BuildContext context, int index) {
            final _KeyDef key = _keys[index];
            final bool isAction = key.icon != null;
            // Small gap between groups: Tab | arrows | undo/redo | symbols.
            final bool groupEnd = index == 0 || index == 4 || index == 6;
            return Padding(
              padding: EdgeInsets.only(right: groupEnd ? 14 : 6),
              child: Semantics(
                button: true,
                label: key.semantic,
                child: Material(
                  color: isAction
                      ? scheme.primary.withValues(alpha: 0.16)
                      : scheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _handle(key),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 46),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      child: isAction
                          ? Icon(key.icon, size: 22, color: scheme.primary)
                          : Text(
                              key.label,
                              style: TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                              ),
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
  const _KeyDef(this.label, this.action, {this.icon});
  final String label;
  final _KeyAction action;
  final IconData? icon;

  String get semantic {
    switch (action) {
      case _KeyAction.tab:
        return 'Insert indent';
      case _KeyAction.left:
        return 'Cursor left';
      case _KeyAction.right:
        return 'Cursor right';
      case _KeyAction.up:
        return 'Cursor up';
      case _KeyAction.down:
        return 'Cursor down';
      case _KeyAction.undo:
        return 'Undo';
      case _KeyAction.redo:
        return 'Redo';
      case _KeyAction.text:
        return 'Insert $label';
    }
  }
}
