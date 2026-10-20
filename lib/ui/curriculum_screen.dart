import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../data/curriculum_data.dart';
import '../editor/python_mode.dart';
import '../services/python_bridge.dart';
import '../state/progress_model.dart';
import '../state/settings_model.dart';
import '../theme/app_theme.dart';
import '../theme/syntax_themes.dart';
import 'widgets/app_widgets.dart';

/// The learning hub: lessons, coding challenges (auto-graded on-device)
/// and syntax cheat sheets. Fully offline.
class CurriculumScreen extends StatelessWidget {
  const CurriculumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ProgressModel progress = context.watch<ProgressModel>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(title: const Text('Learn Python')),
        body: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _LearnHeader(progress: progress),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: const TabBar(
                  tabs: <Widget>[
                    Tab(height: 42, text: 'Lessons'),
                    Tab(height: 42, text: 'Challenges'),
                    Tab(height: 42, text: 'Cheats'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  _LessonList(progress: progress),
                  const _ChallengeList(),
                  const _CheatSheetList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Overall course progress: a ring plus lessons / challenges counters.
class _LearnHeader extends StatelessWidget {
  const _LearnHeader({required this.progress});

  final ProgressModel progress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int lessons = progress.readLessons
        .where((String id) => kLessons.any((Lesson l) => l.id == id))
        .length;
    final int challenges = progress.completedChallenges
        .where((String id) => kChallenges.any((Challenge c) => c.id == id))
        .length;
    final int total = kLessons.length + kChallenges.length;
    final double value = total == 0 ? 0 : (lessons + challenges) / total;
    return AppCard(
      gradient: heroGradient(scheme),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          ProgressRing(
            value: value,
            size: 76,
            stroke: 9,
            child: Text('${(value * 100).round()}%',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  value >= 1 ? 'Course complete' : 'Your course progress',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    Pill(
                        icon: Icons.menu_book_rounded,
                        label: '$lessons/${kLessons.length} lessons',
                        color: scheme.secondary),
                    Pill(
                        icon: Icons.emoji_events_rounded,
                        label: '$challenges/${kChallenges.length} challenges',
                        color: scheme.flame),
                  ],
                ),
              ],
            ),
          ),
        ],
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
    final int nextIndex =
        kLessons.indexWhere((Lesson l) => !progress.readLessons.contains(l.id));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount: kLessons.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        final Lesson lesson = kLessons[index];
        final bool done = progress.readLessons.contains(lesson.id);
        final bool isNext = index == nextIndex;
        final Color accent = done
            ? scheme.success
            : (isNext ? scheme.primary : scheme.secondary);
        return AppCard(
          padding: const EdgeInsets.all(14),
          color: isNext ? scheme.tint(scheme.primary, 0.07) : null,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (BuildContext routeContext) => LessonPage(lesson: lesson),
          )),
          child: Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: done
                    ? Icon(Icons.check_rounded, color: accent, size: 26)
                    : Text('${index + 1}',
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: accent)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(lesson.title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(lesson.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5, height: 1.35, color: scheme.muted)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: <Widget>[
                        Pill(
                            icon: Icons.schedule_rounded,
                            label: '${lesson.minutes} min'),
                        if (isNext)
                          Pill(
                              icon: Icons.bolt_rounded,
                              label: 'Up next',
                              color: scheme.primary),
                        if (done)
                          Pill(label: 'Completed', color: scheme.success),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.faint),
            ],
          ),
        );
      },
    );
  }
}

/// A single lesson (public so the Home screen can open it directly).
class LessonPage extends StatelessWidget {
  const LessonPage({super.key, required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final ProgressModel progress = context.watch<ProgressModel>();
    final bool done = progress.readLessons.contains(lesson.id);
    return Scaffold(
      appBar: AppBar(title: Text(lesson.title)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'lesson-${lesson.id}',
        icon: const Icon(Icons.emoji_events_outlined),
        label: const Text('Start challenge'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (BuildContext routeContext) =>
              ChallengePage(challengeId: lesson.challengeId),
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
        style: const TextStyle(fontFamily: kMonoFont, fontSize: 12.5),
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
          fontFamily: i % 2 == 1 ? kMonoFont : null,
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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount: kChallenges.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        final Challenge challenge = kChallenges[index];
        final bool done = progress.completedChallenges.contains(challenge.id);
        final Color accent = done ? scheme.flame : scheme.violet;
        return AppCard(
          padding: const EdgeInsets.all(14),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (BuildContext routeContext) =>
                ChallengePage(challengeId: challenge.id),
          )),
          child: Row(
            children: <Widget>[
              IconBadge(
                icon:
                    done ? Icons.emoji_events_rounded : Icons.terminal_rounded,
                color: accent,
                size: 48,
                filled: done,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(challenge.title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(challenge.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5, height: 1.35, color: scheme.muted)),
                    const SizedBox(height: 8),
                    done
                        ? Pill(
                            icon: Icons.check_rounded,
                            label: 'Solved',
                            color: scheme.success)
                        : Pill(
                            icon: Icons.play_arrow_rounded,
                            label: 'Try it',
                            color: scheme.violet),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.faint),
            ],
          ),
        );
      },
    );
  }
}

class ChallengePage extends StatefulWidget {
  const ChallengePage({super.key, required this.challengeId});

  final String challengeId;

  @override
  State<ChallengePage> createState() => _ChallengePageState();
}

class _ChallengePageState extends State<ChallengePage> {
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
      results = null; // never judge this run by the previous run's results
    });
    Map<String, dynamic> result;
    try {
      result = await PythonBridge.instance.challengeCheck(
        challengeId: challenge.id,
        source: controller.text,
        testCode: challenge.testCode,
      );
    } catch (e) {
      result = <String, dynamic>{
        'ok': false,
        'error': <String, dynamic>{'type': 'BridgeError', 'message': '$e'},
      };
    }
    if (!mounted) return;
    List<Map<String, dynamic>>? fresh;
    setState(() {
      checking = false;
      if (result['ok'] == true) {
        fresh = (result['results'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic r) => r as Map<String, dynamic>)
            .toList();
        results = fresh;
      } else {
        runError = result['error'] is Map
            ? '${(result['error'] as Map<String, dynamic>)['type']}: '
                '${(result['error'] as Map<String, dynamic>)['message']}'
            : 'Something went wrong.';
      }
    });
    final List<Map<String, dynamic>>? checked = fresh;
    final bool allPassed = checked != null &&
        checked.isNotEmpty &&
        checked.every((r) => r['passed'] == true);
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
                        style: TextStyle(fontSize: 12.5, color: scheme.error)),
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
                            style:
                                TextStyle(fontSize: 11.5, color: scheme.error)),
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: <Widget>[
        for (final CheatSheet sheet in kCheatSheets) ...<Widget>[
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    IconBadge(
                        icon: Icons.bolt_rounded,
                        color: scheme.secondary,
                        size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(sheet.title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final List<String> row in sheet.rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          flex: 5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(row[0],
                                style: TextStyle(
                                    fontFamily: kMonoFont,
                                    fontSize: 12.5,
                                    color: scheme.primary)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 6,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(row[1],
                                style: TextStyle(
                                    fontSize: 13.5,
                                    height: 1.35,
                                    color: scheme.muted)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
