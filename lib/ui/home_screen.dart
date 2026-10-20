import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/curriculum_data.dart';
import '../state/nav_model.dart';
import '../state/progress_model.dart';
import '../state/workspace_model.dart';
import '../theme/app_theme.dart';
import 'curriculum_screen.dart';
import 'file_tree_panel.dart';
import 'widgets/app_widgets.dart';

const List<String> _tips = <String>[
  'Use f-strings for readable output: f"Hello, {name}!"',
  'enumerate(items) gives you the index and the item together.',
  'Indentation is how Python knows what belongs inside a block.',
  'Use list comprehensions: [x * x for x in range(5)]',
  'Press Run often. Small steps make bugs easy to find.',
  'dict.get("key", default) avoids KeyError for missing keys.',
  'Use len(), sum(), min() and max() instead of writing loops.',
  'Read the last line of a traceback first: it names the error.',
  'Name things clearly: total_price beats tp.',
  'Use "with open(...) as f:" so files always get closed.',
];

/// Dashboard: continue learning, quick actions, recent files, streak.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  String _greeting() {
    final int h = DateTime.now().hour;
    if (h < 5) return 'Still up?';
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ProgressModel progress = context.watch<ProgressModel>();
    final WorkspaceModel workspace = context.watch<WorkspaceModel>();
    final NavModel nav = context.read<NavModel>();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: <Widget>[
            // ------------------------------------------------ header
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(_greeting(),
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 2),
                      Text('Ready to write some Python?',
                          style:
                              TextStyle(fontSize: 14.5, color: scheme.muted)),
                    ],
                  ),
                ),
                _StreakBadge(days: progress.streakDays),
              ],
            ),
            const SizedBox(height: 18),
            // ------------------------------------------------ continue
            _ContinueCard(progress: progress),
            const SizedBox(height: 20),
            // ------------------------------------------------ actions
            const SectionTitle('Quick actions'),
            AdaptiveGrid(
              columns: 2,
              children: <Widget>[
                _ActionTile(
                  icon: Icons.note_add_rounded,
                  color: scheme.primary,
                  title: 'New script',
                  subtitle: 'Start from scratch',
                  onTap: () async {
                    HapticFeedback.selectionClick();
                    final String? created =
                        await createNodeFlow(context, workspace);
                    if (created != null) nav.go(AppTab.code);
                  },
                ),
                _ActionTile(
                  icon: Icons.code_rounded,
                  color: scheme.secondary,
                  title: 'Open editor',
                  subtitle: 'Back to your code',
                  onTap: () => nav.go(AppTab.code),
                ),
                _ActionTile(
                  icon: Icons.emoji_events_rounded,
                  color: scheme.violet,
                  title: 'Challenges',
                  subtitle: 'Test your skills',
                  onTap: () => nav.go(AppTab.learn),
                ),
                _ActionTile(
                  icon: Icons.bolt_rounded,
                  color: scheme.flame,
                  title: 'Snippets',
                  subtitle: 'Reusable code',
                  onTap: () => nav.go(AppTab.tools),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // ------------------------------------------------ week
            const SectionTitle('This week'),
            _WeekCard(progress: progress),
            const SizedBox(height: 20),
            // ------------------------------------------------ recent
            ..._recentFiles(context, workspace, nav),
            // ------------------------------------------------ stats
            const SectionTitle('Your numbers'),
            Row(
              children: <Widget>[
                Expanded(
                  child: _MiniStat(
                      icon: Icons.play_circle_rounded,
                      value: '${progress.runsCount}',
                      label: 'Runs',
                      color: scheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MiniStat(
                      icon: Icons.edit_note_rounded,
                      value: '${progress.linesWritten}',
                      label: 'Lines',
                      color: scheme.secondary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MiniStat(
                      icon: Icons.emoji_events_rounded,
                      value: '${progress.completedChallenges.length}',
                      label: 'Solved',
                      color: scheme.flame),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // ------------------------------------------------ tip
            _TipCard(tip: _tips[_dayOfYear() % _tips.length]),
          ],
        ),
      ),
    );
  }

  int _dayOfYear() {
    final DateTime now = DateTime.now();
    return now.difference(DateTime(now.year)).inDays;
  }

  List<Widget> _recentFiles(
      BuildContext context, WorkspaceModel workspace, NavModel nav) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<String> paths = <String>[
      ...workspace.openTabs.reversed,
    ];
    void collect(List<FileNode> nodes) {
      for (final FileNode n in nodes) {
        if (n.isDir) {
          collect(n.children);
        } else if (n.isPython && !paths.contains(n.path)) {
          paths.add(n.path);
        }
      }
    }

    collect(workspace.tree);
    final List<String> shown = paths.take(4).toList();
    if (shown.isEmpty) return const <Widget>[];
    return <Widget>[
      const SectionTitle('Recent files'),
      AppCard(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: <Widget>[
            for (int i = 0; i < shown.length; i++) ...<Widget>[
              if (i > 0) Divider(indent: 68, color: scheme.outlineVariant),
              InkWell(
                onTap: () async {
                  await workspace.openFile(shown[i]);
                  nav.go(AppTab.code);
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: <Widget>[
                      IconBadge(
                          icon: Icons.code_rounded,
                          color: scheme.secondary,
                          size: 40),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(shown[i].split('/').last,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15.5, fontWeight: FontWeight.w700)),
                      ),
                      if (workspace.isDirty(shown[i]))
                        Pill(label: 'unsaved', color: scheme.flame),
                      Icon(Icons.chevron_right_rounded, color: scheme.faint),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 20),
    ];
  }
}

class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool active = days > 0;
    final Color c = active ? scheme.flame : scheme.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.local_fire_department_rounded, color: c, size: 22),
          const SizedBox(width: 4),
          Text('$days',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: c)),
          const SizedBox(width: 4),
          Text(days == 1 ? 'day' : 'days',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: c)),
        ],
      ),
    );
  }
}

/// "Continue learning" hero: next unread lesson, else next unsolved
/// challenge, else a completion message.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.progress});

  final ProgressModel progress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final NavModel nav = context.read<NavModel>();

    final int lessonsDone = progress.readLessons
        .where((String id) => kLessons.any((Lesson l) => l.id == id))
        .length;
    final int challengesDone = progress.completedChallenges
        .where((String id) => kChallenges.any((Challenge c) => c.id == id))
        .length;
    final int total = kLessons.length + kChallenges.length;
    final double value =
        total == 0 ? 0 : (lessonsDone + challengesDone) / total;

    final int lessonIdx =
        kLessons.indexWhere((Lesson l) => !progress.readLessons.contains(l.id));
    final int challengeIdx = kChallenges.indexWhere(
        (Challenge c) => !progress.completedChallenges.contains(c.id));

    String eyebrow;
    String title;
    String body;
    String button;
    VoidCallback onTap;
    if (lessonIdx >= 0) {
      final Lesson l = kLessons[lessonIdx];
      eyebrow = lessonsDone == 0
          ? 'START HERE'
          : 'CONTINUE · LESSON ${lessonIdx + 1}';
      title = l.title;
      body = l.summary;
      button = 'Continue lesson';
      onTap = () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (BuildContext c) => LessonPage(lesson: l)));
    } else if (challengeIdx >= 0) {
      final Challenge c = kChallenges[challengeIdx];
      eyebrow = 'NEXT CHALLENGE';
      title = c.title;
      body = c.description;
      button = 'Solve it';
      onTap = () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (BuildContext r) => ChallengePage(challengeId: c.id)));
    } else {
      eyebrow = 'ALL DONE';
      title = 'You finished the course';
      body = 'Keep practising in the editor or revisit any lesson.';
      button = 'Review lessons';
      onTap = () => nav.go(AppTab.learn);
    }

    return AppCard(
      gradient: heroGradient(scheme),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(eyebrow,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: scheme.primary)),
                    const SizedBox(height: 6),
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ProgressRing(
                value: value,
                size: 64,
                stroke: 8,
                child: Text('${(value * 100).round()}%',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, height: 1.4, color: scheme.muted)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(button),
              onPressed: () {
                HapticFeedback.selectionClick();
                onTap();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          IconBadge(icon: icon, color: color, size: 38),
          const SizedBox(height: 10),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 15.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 1),
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: scheme.muted)),
        ],
      ),
    );
  }
}

/// Mon-Sun row of dots; days inside the current streak are filled.
class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.progress});

  final ProgressModel progress;

  bool _active(DateTime day) {
    final DateTime? last = progress.lastActiveDate;
    if (last == null || progress.streakDays <= 0) return false;
    // Calendar-day maths in UTC (DST-safe).
    final int dayNum =
        DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
            86400000;
    final int lastNum =
        DateTime.utc(last.year, last.month, last.day).millisecondsSinceEpoch ~/
            86400000;
    return dayNum <= lastNum && dayNum > lastNum - progress.streakDays;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DateTime now = DateTime.now();
    final DateTime monday =
        DateTime(now.year, now.month, now.day - (now.weekday - 1));
    const List<String> labels = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          for (int i = 0; i < 7; i++)
            Builder(builder: (BuildContext context) {
              final DateTime day =
                  DateTime(monday.year, monday.month, monday.day + i);
              final bool active = _active(day);
              final bool today = day.year == now.year &&
                  day.month == now.month &&
                  day.day == now.day;
              final bool future = day.isAfter(now) && !today;
              return Column(
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active
                          ? scheme.flame.withValues(alpha: 0.22)
                          : scheme.surfaceContainerHigh,
                      border: Border.all(
                        color: today
                            ? scheme.primary
                            : (active
                                ? scheme.flame.withValues(alpha: 0.5)
                                : scheme.outlineVariant),
                        width: today ? 2 : 1,
                      ),
                    ),
                    child: active
                        ? Icon(Icons.local_fire_department_rounded,
                            size: 20, color: scheme.flame)
                        : Text('${day.day}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: future ? scheme.faint : scheme.muted)),
                  ),
                  const SizedBox(height: 6),
                  Text(labels[i],
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: today ? FontWeight.w800 : FontWeight.w600,
                          color: today ? scheme.primary : scheme.muted)),
                ],
              );
            }),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(
        children: <Widget>[
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, height: 1)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.muted)),
        ],
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.tip});

  final String tip;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AppCard(
      color: scheme.tint(scheme.flame, 0.08),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IconBadge(
              icon: Icons.lightbulb_rounded, color: scheme.flame, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Python tip',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: scheme.flame)),
                const SizedBox(height: 4),
                Text(tip, style: const TextStyle(fontSize: 14.5, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
