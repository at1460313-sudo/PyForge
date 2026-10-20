import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/run_model.dart';

/// The visual debugger: current line, variable explorer and controls.
/// Rendered as an overlay panel whenever execution is paused.
class DebuggerPanel extends StatelessWidget {
  const DebuggerPanel({
    super.key,
    required this.debugger,
    required this.onClose,
  });

  final DebuggerModel debugger;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<MapEntry<String, String>> vars =
        debugger.variables.entries.toList()
          ..sort((MapEntry<String, String> a, MapEntry<String, String> b) =>
              a.key.compareTo(b.key));

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 12),
        child: Material(
          elevation: 10,
          borderRadius: BorderRadius.circular(18),
          color: scheme.surfaceContainerHighest,
          child: Container(
            constraints: const BoxConstraints(
                maxWidth: 340, maxHeight: 320),
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.bug_report, size: 18, color: scheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Paused at line ${debugger.currentLine}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const Spacer(),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: onClose,
                      child: Icon(Icons.close,
                          size: 18,
                          color: scheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Control buttons.
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _DebugButton(
                        icon: Icons.skip_next,
                        label: 'Step',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          debugger.step();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DebugButton(
                        icon: Icons.play_arrow,
                        label: 'Continue',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          debugger.continueRun();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DebugButton(
                        icon: Icons.stop,
                        label: 'Stop',
                        danger: true,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          debugger.stop();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'VARIABLES',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1),
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: vars.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'No local variables yet.',
                            style: TextStyle(
                              color: scheme.onSurface.withValues(alpha: 0.5),
                              fontSize: 12.5,
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: vars.length,
                          itemBuilder: (BuildContext context, int index) {
                            final MapEntry<String, String> entry =
                                vars[index];
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 2.5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    entry.key,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12.5,
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      entry.value,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DebugButton extends StatelessWidget {
  const _DebugButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = danger ? scheme.error : scheme.primary;
    return Material(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
