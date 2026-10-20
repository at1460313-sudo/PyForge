import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/run_model.dart';

/// The terminal / output bottom area. Shows live program output, an input
/// field when the program asks for input(), and AI actions on errors.
class OutputPanel extends StatefulWidget {
  const OutputPanel({
    super.key,
    required this.run,
    required this.onExplainError,
    required this.onFixError,
  });

  final RunModel run;
  final VoidCallback onExplainError;
  final VoidCallback onFixError;

  @override
  State<OutputPanel> createState() => _OutputPanelState();
}

class _OutputPanelState extends State<OutputPanel> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  bool _collapsed = false;
  // Follow-the-output only while the user is at the bottom; scrolling up to
  // read must not be yanked back down on every new line.
  bool _followOutput = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final ScrollPosition pos = _scrollController.position;
      final bool atBottom = pos.pixels >= pos.maxScrollExtent - 24;
      if (atBottom != _followOutput) {
        setState(() => _followOutput = atBottom);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final RunModel run = widget.run;
    final bool hasContent = run.lines.isNotEmpty || run.state != RunState.idle;

    if (!hasContent && _collapsed) {
      return const SizedBox.shrink();
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: _collapsed ? 44 : 210,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outline.withValues(alpha: 0.5))),
      ),
      child: Column(
        children: <Widget>[
          // Header: title, state, actions.
          InkWell(
            onTap: () => setState(() => _collapsed = !_collapsed),
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: <Widget>[
                    Icon(
                      _collapsed
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 20,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'OUTPUT',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (run.state == RunState.running)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    const Spacer(),
                    if (run.state != RunState.idle)
                      _HeaderAction(
                        icon: Icons.stop,
                        label: 'Stop',
                        color: scheme.error,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          run.stop();
                        },
                      ),
                    if (run.hasError) ...<Widget>[
                      _HeaderAction(
                        icon: Icons.lightbulb_outline,
                        label: 'Explain',
                        onTap: widget.onExplainError,
                      ),
                      _HeaderAction(
                        icon: Icons.auto_fix_high,
                        label: 'Fix it',
                        onTap: widget.onFixError,
                      ),
                    ],
                    _HeaderAction(
                      icon: Icons.delete_outline,
                      label: 'Clear',
                      onTap: run.clear,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Terminal body.
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: run.lines.isEmpty
                  ? Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        'Run a file to see its output here.',
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.4),
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                        ),
                      ),
                    )
                  : _buildTerminal(context),
            ),
          ),
          // input() support.
          if (run.state == RunState.waitingInput)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      autofocus: true,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText:
                            run.inputPrompt?.isNotEmpty == true
                                ? run.inputPrompt
                                : 'Program is waiting for input…',
                      ),
                      onSubmitted: (String value) => _submit(value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: () => _submit(_inputController.text),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _submit(String value) {
    HapticFeedback.selectionClick();
    widget.run.submitInput(value);
    _inputController.clear();
  }

  Widget _buildTerminal(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final RunModel run = widget.run;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_followOutput && _scrollController.hasClients) {
        _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent);
      }
    });
    return ListView.builder(
      controller: _scrollController,
      itemCount: run.lines.length,
      itemBuilder: (BuildContext context, int index) {
        final RunLine line = run.lines[index];
        final bool isErr = line.stream == 'stderr';
        return Text(
          line.text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12.5,
            color: isErr ? scheme.error : scheme.onSurface,
          ),
        );
      },
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 16, color: color ?? scheme.primary),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color ?? scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
