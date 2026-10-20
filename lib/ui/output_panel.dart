import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/run_model.dart';
import '../theme/app_theme.dart';
import 'widgets/app_widgets.dart';

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

    // A program waiting for input() always shows the field.
    final bool collapsed = _collapsed && run.state != RunState.waitingInput;

    if (!hasContent && collapsed) {
      return const SizedBox.shrink();
    }

    final double screenH = MediaQuery.of(context).size.height;
    final double openHeight = (screenH * 0.32).clamp(190.0, 340.0);

    String status;
    Color statusColor;
    IconData statusIcon;
    if (run.state == RunState.running) {
      status = 'Running';
      statusColor = scheme.secondary;
      statusIcon = Icons.sync_rounded;
    } else if (run.state == RunState.waitingInput) {
      status = 'Waiting for input';
      statusColor = scheme.flame;
      statusIcon = Icons.keyboard_rounded;
    } else if (run.hasError) {
      status = 'Error';
      statusColor = scheme.error;
      statusIcon = Icons.error_rounded;
    } else if (run.lines.isNotEmpty) {
      status = 'Finished';
      statusColor = scheme.success;
      statusIcon = Icons.check_circle_rounded;
    } else {
      status = 'Ready';
      statusColor = scheme.muted;
      statusIcon = Icons.terminal_rounded;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: collapsed ? 56 : openHeight,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        children: <Widget>[
          // Header: status, actions. The whole row toggles the panel.
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            onTap: () => setState(() => _collapsed = !_collapsed),
            child: SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
                child: Row(
                  children: <Widget>[
                    Icon(
                      collapsed
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 24,
                      color: scheme.muted,
                    ),
                    const SizedBox(width: 6),
                    const Text('Output',
                        style: TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 10),
                    Pill(label: status, icon: statusIcon, color: statusColor),
                    const Spacer(),
                    if (run.state != RunState.idle)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          backgroundColor: scheme.error,
                          foregroundColor: scheme.onError,
                        ),
                        icon: const Icon(Icons.stop_rounded, size: 20),
                        label: const Text('Stop'),
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          run.stop();
                        },
                      ),
                    IconButton(
                      tooltip: 'Clear output',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        run.clear();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (run.hasError && !collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44)),
                      icon:
                          const Icon(Icons.lightbulb_outline_rounded, size: 20),
                      label: const Text('Explain error'),
                      onPressed: widget.onExplainError,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44)),
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 20),
                      label: const Text('Fix it'),
                      onPressed: widget.onFixError,
                    ),
                  ),
                ],
              ),
            ),
          // Terminal body.
          if (!collapsed)
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                decoration: BoxDecoration(
                  color: scheme.isDark
                      ? Colors.black.withValues(alpha: 0.35)
                      : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: run.lines.isEmpty
                    ? Align(
                        alignment: Alignment.topLeft,
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.play_circle_outline_rounded,
                                size: 20, color: scheme.faint),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Tap Run to see your program output here.',
                                style: TextStyle(
                                    color: scheme.muted, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      )
                    : _buildTerminal(context),
              ),
            ),
          // input() support.
          if (run.state == RunState.waitingInput)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      autofocus: true,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: run.inputPrompt?.isNotEmpty == true
                            ? run.inputPrompt
                            : 'Program is waiting for input...',
                      ),
                      onSubmitted: (String value) => _submit(value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send',
                    icon: const Icon(Icons.send_rounded),
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
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
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
            fontFamily: kMonoFont,
            fontSize: 13,
            height: 1.45,
            color: isErr ? scheme.error : scheme.onSurface,
          ),
        );
      },
    );
  }
}
