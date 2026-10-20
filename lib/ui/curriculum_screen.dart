import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../data/curriculum_data.dart';
import '../editor/python_mode.dart';
import '../services/python_bridge.dart';
import '../state/progress_model.dart';
import '../state/settings_model.dart';
import '../theme/syntax_themes.dart';

/// The learning hub: lessons, coding challenges (auto-graded on-device)
/// and syntax cheat sheets. Fully offline.
class CurriculumScreen extends StatelessWidget {
  const CurriculumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ProgressModel progress = context.watch<ProgressModel>();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Learn'),
          bottom: TabBar(
            tabs: <Widget>[
              Tab(
                  icon: const Icon(Icons.school_outlined, size: 18),
                  text: 'Lessons'),
              Tab(
                  icon: const Icon(Icons.emoji_events_outlined, size: 18),
                  text: 'Challenges'),
              Tab(
                  icon: const Icon(Icons.bolt_outlined, size: 18),
                  text: 'Cheat sheets'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _LessonList(progress: progress),
            const _ChallengeList(),
            const _CheatSheetList(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lessons
// ---------------------------------------------------------------------------

class _LessonList extends StatelessWidget {
  const _LessonList({required this.progress});

  final ProgressModel progress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: kLessons.length,
      itemBuilder: (BuildContext context, int index) {
        final Lesson lesson = kLessons[index];
        final bool done = progress.readLessons.contains(lesson.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(14),
              leading: CircleAvatar(
                backgroundColor: done
                    ? Colors.green.withValues(alpha: 0.2)
                    : scheme.primary.withValues(alpha: 0.15),
                child: Icon(
                  done ? Icons.check : Icons.play_arrow,
                  color: done ? Colors.green : scheme.primary,
                ),
              ),
              title: Text(lesson.title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(lesson.summary,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurface.withValues(alpha: 0.65))),
              ),
              trailing: Text('${lesson.minutes} min',
                  style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.5))),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (BuildContext routeContext) =>
                        _LessonPage(lesson: lesson),
                  )),
            ),
          ),
        );
      },
    );
  }
}

class _LessonPage extends StatelessWidget {
  const _LessonPage({required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final ProgressModel progress = context.watch<ProgressModel>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool done = progress.readLessons.contains(lesson.id);
    return Scaffold(
      appBar: AppBar(title: Text(lesson.title)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'lesson-${lesson.id}',
        icon: const Icon(Icons.emoji_events_outlined),
        label: const Text('Start challenge'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (BuildContext routeContext) =>
                  _ChallengePage(challengeId: lesson.challengeId),
            )),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          _MarkdownLite(text: lesson.content),
          const SizedBox(height: 80),
          if (!done)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Mark lesson as read'),
                onPressed: () async {
                  HapticFeedback.selectionClick();
                  await progress.markLessonRead(lesson.id);
                  await progress.recordActivity();
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Tiny markdown renderer: # / ## headings, ``` code fences, - bullets
/// and `inline code`.
class _MarkdownLite extends StatelessWidget {
  const _MarkdownLite({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<Widget> blocks = <Widget>[];
    final List<String> lines = text.split('\n');
    final List<String> codeBuffer = <String>[];
    bool inCode = false;

    for (final String line in lines) {
      if (line.startsWith('```')) {
        if (inCode) {
          blocks.add(_codeBlock(context, codeBuffer.join('\n')));
          codeBuffer.clear();
        }
        inCode = !inCode;
        continue;
      }
      if (inCode) {
        codeBuffer.add(line);
        continue;
      }
      if (line.startsWith('## ')) {
        blocks.add(_heading(context, line.substring(3), 15));
      } else if (line.startsWith('# ')) {
        blocks.add(_heading(context, line.substring(2), 19));
      } else if (line.startsWith('- ')) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('•  ',
                  style: TextStyle(color: scheme.primary, fontSize: 13.5)),
              Expanded(child: _inlineText(context, line.substring(2))),
            ],
          ),
        ));
      } else if (line.trim().isEmpty) {
        blocks.add(const SizedBox(height: 8));
      } else {
        blocks.add(_inlineText(context, line));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  Widget _heading(BuildContext context, String text, double size) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: size > 17 ? 8 : 12, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w900,
          color: scheme.primary,
        ),
      ),
    );
  }

  Widget _codeBlock(BuildContext context, String code) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        code,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
      ),
    );
  }

  Widget _inlineText(BuildContext context, String text) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<InlineSpan> spans = <InlineSpan>[];
    final List<String> parts = text.split('`');
    for (int i = 0; i < parts.length; i++) {
      spans.add(TextSpan(
        text: parts[i],
        style: TextStyle(
          fontSize: 13.5,
          height: 1.45,
          color: scheme.onSurface,
          fontFamily: i % 2 == 1 ? 'monospace' : null,
        ),
      ));
    }
    return Text.rich(TextSpan(children: spans));
  }
}

// ---------------------------------------------------------------------------
// Challenges
// ---------------------------------------------------------------------------

class _ChallengeList extends StatelessWidget {
  const _ChallengeList();

  @override
  Widget build(BuildContext context) {
    final ProgressModel progress = context.watch<ProgressModel>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: kChallenges.length,
      itemBuilder: (BuildContext context, int index) {
        final Challenge challenge = kChallenges[index];
        final bool done = progress.completedChallenges.contains(challenge.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: ListTile(
              leading: Icon(
                done ? Icons.emoji_events : Icons.lock_outline,
                color: done
                    ? Colors.amber
                    : scheme.onSurface.withValues(alpha: 0.4),
              ),
              title: Text(challenge.title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(challenge.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurface.withValues(alpha: 0.65))),
              ),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (BuildContext routeContext) =>
                        _ChallengePage(challengeId: challenge.id),
                  )),
            ),
          ),
        );
      },
    );
  }
}

class _ChallengePage extends StatefulWidget {
  const _ChallengePage({required this.challengeId});

  final String challengeId;

  @override
  State<_ChallengePage> createState() => _ChallengePageState();
}

class _ChallengePageState extends State<_ChallengePage> {
  late final Challenge challenge;
  late final CodeLineEditingController controller;
  List<Map<String, dynamic>>? results;
  bool checking = false;
  bool showHint = false;
  String? runError;

  @override
  void initState() {
    super.initState();
    challenge = kChallenges.firstWhere(
      (Challenge c) => c.id == widget.challengeId,
      orElse: () => kChallenges.first,
    );
    controller = CodeLineEditingController.fromText(challenge.starterCode);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _runTests() async {
    final ProgressModel progress = context.read<ProgressModel>();
    HapticFeedback.mediumImpact();
    setState(() {
      checking = true;
      runError = null;
    });
    final Map<String, dynamic> result =
        await PythonBridge.instance.challengeCheck(
      challengeId: challenge.id,
      source: controller.text,
      testCode: challenge.testCode,
    );
    if (!mounted) return;
    setState(() {
      checking = false;
      if (result['ok'] == true) {
        results = (result['results'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic r) => r as Map<String, dynamic>)
            .toList();
      } else {
        runError = result['error'] is Map
            ? '${(result['error'] as Map<String, dynamic>)['type']}: '
                '${(result['error'] as Map<String, dynamic>)['message']}'
            : 'Something went wrong.';
      }
    });
    final bool allPassed =
        results != null && results!.isNotEmpty && results!.every((r) => r['passed'] == true);
    if (allPassed) {
      await progress.completeChallenge(challenge.id);
      await progress.recordActivity();
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Challenge complete — nice work!'),
              backgroundColor: Colors.green),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final SettingsModel settings = context.watch<SettingsModel>();
    final SyntaxThemeDef syntax = SyntaxThemes.byId(settings.syntaxThemeId);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(challenge.title)),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(challenge.description,
                style: const TextStyle(fontSize: 13.5, height: 1.4)),
          ),
          Expanded(
            child: CodeEditor(
              controller: controller,
              wordWrap: false,
              style: CodeEditorStyle(
                fontSize: 14,
                backgroundColor: syntax.background,
                textColor: syntax.text,
                codeTheme: CodeHighlightTheme(
                  languages: <String, CodeHighlightThemeMode>{
                    'python': CodeHighlightThemeMode(mode: pyforgePythonMode),
                  },
                  theme: syntax.map,
                ),
              ),
              indicatorBuilder: (BuildContext indicatorContext,
                  editingController, chunkController, notifier) {
                return DefaultCodeLineNumber(
                  controller: editingController,
                  notifier: notifier,
                );
              },
            ),
          ),
          if (results != null || runError != null)
            _buildResults(context, scheme),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'challenge-${challenge.id}',
        icon: checking
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.play_arrow),
        label: const Text('Run tests'),
        onPressed: checking ? null : _runTests,
      ),
    );
  }

  Widget _buildResults(BuildContext context, ColorScheme scheme) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      child: Column(
        children: <Widget>[
          if (runError != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  Icon(Icons.error_outline, color: scheme.error, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(runError!,
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.error)),
                  ),
                ],
              ),
            )
          else if (results != null)
            Expanded(
              child: ListView.builder(
                itemCount: results!.length,
                itemBuilder: (BuildContext context, int index) {
                  final Map<String, dynamic> result = results![index];
                  final bool passed = result['passed'] == true;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      passed ? Icons.check_circle : Icons.cancel,
                      color: passed ? Colors.green : scheme.error,
                      size: 18,
                    ),
                    title: Text(result['name'] as String? ?? '',
                        style: const TextStyle(fontSize: 12.5)),
                    subtitle: passed
                        ? null
                        : Text(result['message'] as String? ?? '',
                            style: TextStyle(
                                fontSize: 11.5, color: scheme.error)),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}


// ---------------------------------------------------------------------------
// Cheat sheets
// ---------------------------------------------------------------------------

class _CheatSheetList extends StatelessWidget {
  const _CheatSheetList();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        for (final CheatSheet sheet in kCheatSheets) ...<Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(sheet.title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  for (final List<String> row in sheet.rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            width: 150,
                            child: Text(row[0],
                                style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: scheme.primary)),
                          ),
                          Expanded(
                            child: Text(row[1],
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.75))),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
