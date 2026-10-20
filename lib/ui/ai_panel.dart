import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'package:flutter/services.dart';

import '../state/ai_model.dart';
import '../state/settings_model.dart';
import '../state/workspace_model.dart';
import '../utils/ai_parsing.dart';

/// AI Co-Pilot panel: Explain code, Fix my bug (with diff preview),
/// Generate quiz. Opens as a modal bottom sheet; works only with a
/// configured BYOK key.
Future<void> showAiPanel(
  BuildContext context, {
  required AiModel ai,
  required SettingsModel settings,
  required WorkspaceModel workspace,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: _AiPanel(
        ai: ai,
        settings: settings,
        workspace: workspace,
      ),
    ),
  );
}

class _AiPanel extends StatefulWidget {
  const _AiPanel({
    required this.ai,
    required this.settings,
    required this.workspace,
  });

  final AiModel ai;
  final SettingsModel settings;
  final WorkspaceModel workspace;

  @override
  State<_AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends State<_AiPanel> {
  String _topic = '';

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(maxHeight: 560),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Icon(Icons.auto_awesome, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text('AI Co-Pilot',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const Spacer(),
                ListenableBuilder(
                  listenable: widget.ai,
                  builder: (BuildContext busyContext, Widget? child) {
                    if (!widget.ai.busy) return const SizedBox.shrink();
                    return const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2));
                  },
                ),
              ],
            ),
          ),
          if (!widget.settings.hasApiKey)
            _buildNoKey(context)
          else
            Flexible(
              child: ListenableBuilder(
                listenable: widget.ai,
                builder: (BuildContext builderContext, Widget? child) {
                  return _buildBody(builderContext);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final AiModel ai = widget.ai;
    final String code = widget.workspace.activeText;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ActionChip(
                avatar: const Icon(Icons.menu_book, size: 16),
                label: const Text('Explain this code'),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  ai.explainCode(code, widget.settings);
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.auto_fix_high, size: 16),
                label: const Text('Fix my bug'),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  ai.fixCode(code, null, widget.settings,
                      path: widget.workspace.activePath);
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Quiz topic (e.g. "for loops")',
                  ),
                  onChanged: (String value) =>
                      setState(() => _topic = value),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _topic.trim().isEmpty || ai.busy
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        ai.generateQuiz(_topic.trim(), widget.settings);
                      },
                child: const Text('Quiz me'),
              ),
            ],
          ),
          if (ai.error != null) ...<Widget>[
            const SizedBox(height: 14),
            _ErrorCard(message: ai.error!),
          ],
          if (ai.explanation != null) ...<Widget>[
            const SizedBox(height: 14),
            _SectionTitle('Explanation'),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(ai.explanation!),
            ),
          ],
          if (ai.fix != null && ai.fixOriginalCode != null) ...<Widget>[
            const SizedBox(height: 14),
            _SectionTitle('Suggested fix'),
            Text(ai.fix!['explanation'] ?? ''),
            const SizedBox(height: 8),
            _DiffView(
              original: ai.fixOriginalCode!,
              updated: ai.fix!['fixed_code'] ?? '',
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Apply fix'),
                    onPressed: () => _applyFix(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close),
                    label: const Text('Discard'),
                    onPressed: () {
                      ai.clear();
                    },
                  ),
                ),
              ],
            ),
          ],
          if (ai.quiz.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            _SectionTitle('Quiz'),
            _QuizView(questions: ai.quiz),
          ],
        ],
      ),
    );
  }

  Future<void> _applyFix() async {
    final AiModel ai = widget.ai;
    final WorkspaceModel workspace = widget.workspace;
    final String? fixed = ai.fix?['fixed_code'];
    if (fixed == null) return;
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('Apply the fixed code?'),
            content: const Text(
                'Your current file will be replaced by the AI version '
                '(you can undo with the ↺ key).'),
            actions: <Widget>[
              TextButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(true),
                  child: const Text('Apply')),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    final String? target = ai.fixPath ?? workspace.activePath;
    if (target == null) return;
    workspace.setTextFor(target, fixed);
    HapticFeedback.mediumImpact();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Widget _buildNoKey(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: <Widget>[
          Icon(Icons.key_off, size: 40, color: scheme.onSurface.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          const Text(
            'No API key yet',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Bring your own key (OpenAI, Anthropic, Gemini, OpenRouter…) in '
            'Settings to unlock the AI Co-Pilot. Everything else in PyForge '
            'works fully offline.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.7), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline, color: scheme.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(fontSize: 13, color: scheme.error)),
          ),
        ],
      ),
    );
  }
}

/// Inline diff between the original and fixed code.
class _DiffView extends StatelessWidget {
  const _DiffView({required this.original, required this.updated});

  final String original;
  final String updated;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<DiffLine> diff = diffLines(original, updated);
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: diff.length,
        itemBuilder: (BuildContext context, int index) {
          final DiffLine line = diff[index];
          Color? background;
          if (line.action == DiffAction.insert) {
            background = Colors.green.withValues(alpha: 0.12);
          } else if (line.action == DiffAction.delete) {
            background = Colors.red.withValues(alpha: 0.12);
          }
          return Container(
            width: double.infinity,
            color: background,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
            child: Text(
              line.action == DiffAction.insert
                  ? '+ ${line.text}'
                  : line.action == DiffAction.delete
                      ? '- ${line.text}'
                      : '  ${line.text}',
              style: TextStyle(
                fontFamily: kMonoFont,
                fontSize: 12,
                color: line.action == DiffAction.equal
                    ? scheme.onSurface.withValues(alpha: 0.7)
                    : scheme.onSurface,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _QuizView extends StatefulWidget {
  const _QuizView({required this.questions});
  final List<QuizQuestion> questions;

  @override
  State<_QuizView> createState() => _QuizViewState();
}

class _QuizViewState extends State<_QuizView> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        for (int q = 0; q < widget.questions.length; q++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('${q + 1}. ${widget.questions[q].question}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13.5)),
                  const SizedBox(height: 8),
                  for (int o = 0; o < widget.questions[q].options.length; o++)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _selected = q * 100 + o),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: _optionColor(context, q, o),
                        ),
                        child: Text(
                          '${String.fromCharCode(65 + o)}. '
                          '${widget.questions[q].options[o]}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  if (_selected != null &&
                      _selected! ~/ 100 == q &&
                      _selected! % 100 == widget.questions[q].answerIndex)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Correct! ${widget.questions[q].explanation}',
                        style: TextStyle(
                            color: Colors.green.shade600, fontSize: 12.5),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Color? _optionColor(BuildContext context, int q, int o) {
    if (_selected == null || _selected! ~/ 100 != q) return null;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isCorrect = o == widget.questions[q].answerIndex;
    final bool isSelected = _selected! % 100 == o;
    if (isSelected && isCorrect) {
      return Colors.green.withValues(alpha: 0.18);
    }
    if (isSelected && !isCorrect) {
      return scheme.error.withValues(alpha: 0.18);
    }
    if (isCorrect) {
      return Colors.green.withValues(alpha: 0.10);
    }
    return null;
  }
}
