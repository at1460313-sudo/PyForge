import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/curriculum_data.dart';
import '../state/progress_model.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';
import 'widgets/app_widgets.dart';

class _Badge {
  const _Badge(this.icon, this.title, this.hint, this.color, this.earned);
  final IconData icon;
  final String title;
  final String hint;
  final Color color;
  final bool earned;
}

/// Profile: overall progress, streak, stats, badges, and a way to Settings.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ProgressModel p = context.watch<ProgressModel>();
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final int lessons = p.readLessons
        .where((String id) => kLessons.any((Lesson l) => l.id == id))
        .length;
    final int challenges = p.completedChallenges
        .where((String id) => kChallenges.any((Challenge c) => c.id == id))
        .length;
    final int total = kLessons.length + kChallenges.length;
    final double value = total == 0 ? 0 : (lessons + challenges) / total;

    final List<_Badge> badges = <_Badge>[
      _Badge(Icons.play_circle_rounded, 'First run', 'Run any program',
          scheme.primary, p.runsCount >= 1),
      _Badge(Icons.menu_book_rounded, 'Reader', 'Finish a lesson',
          scheme.secondary, lessons >= 1),
      _Badge(Icons.emoji_events_rounded, 'Solver', 'Solve a challenge',
          scheme.flame, challenges >= 1),
      _Badge(Icons.local_fire_department_rounded, '3-day streak',
          'Code 3 days in a row', scheme.flame, p.streakDays >= 3),
      _Badge(Icons.bolt_rounded, 'Busy fingers', 'Write 100 lines',
          scheme.violet, p.linesWritten >= 100),
      _Badge(Icons.workspace_premium_rounded, 'Graduate',
          'Complete the whole course', scheme.success, value >= 1),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext c) => const SettingsScreen(),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: <Widget>[
          // Hero: ring + streak.
          AppCard(
            gradient: heroGradient(scheme),
            padding: const EdgeInsets.all(20),
            child: Row(
              children: <Widget>[
                ProgressRing(
                  value: value,
                  size: 104,
                  stroke: 12,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('${(value * 100).round()}%',
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w800)),
                      Text('done',
                          style: TextStyle(fontSize: 12, color: scheme.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(Icons.local_fire_department_rounded,
                              color: scheme.flame, size: 30),
                          const SizedBox(width: 4),
                          Text('${p.streakDays}',
                              style: const TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                  height: 1)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.streakDays == 1 ? 'day streak' : 'day streak',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.streakDays > 0
                            ? 'Keep going. Consistency beats intensity.'
                            : 'Run some code today to start a streak.',
                        style: TextStyle(
                            fontSize: 13, height: 1.35, color: scheme.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AdaptiveGrid(
            columns: 2,
            children: <Widget>[
              StatTile(
                  icon: Icons.emoji_events_rounded,
                  label: 'Challenges',
                  value: '$challenges/${kChallenges.length}',
                  color: scheme.flame),
              StatTile(
                  icon: Icons.menu_book_rounded,
                  label: 'Lessons',
                  value: '$lessons/${kLessons.length}',
                  color: scheme.secondary),
              StatTile(
                  icon: Icons.edit_note_rounded,
                  label: 'Lines',
                  value: '${p.linesWritten}',
                  color: scheme.primary),
              StatTile(
                  icon: Icons.play_circle_rounded,
                  label: 'Runs',
                  value: '${p.runsCount}',
                  color: scheme.violet),
            ],
          ),
          const SizedBox(height: 12),
          SectionTitle('Badges',
              trailing: Text(
                  '${badges.where((_Badge b) => b.earned).length}/${badges.length}',
                  style: TextStyle(
                      color: scheme.muted, fontWeight: FontWeight.w700))),
          AdaptiveGrid(
            columns: 3,
            children: <Widget>[
              for (final _Badge b in badges) _BadgeTile(badge: b),
            ],
          ),
          const SizedBox(height: 12),
          const SectionTitle('Challenges'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < kChallenges.length; i++) ...<Widget>[
                  if (i > 0) Divider(indent: 56, color: scheme.outlineVariant),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          p.completedChallenges.contains(kChallenges[i].id)
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color:
                              p.completedChallenges.contains(kChallenges[i].id)
                                  ? scheme.success
                                  : scheme.faint,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(kChallenges[i].title,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.settings_rounded),
            label: const Text('Settings, AI and Git'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext c) => const SettingsScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge});

  final _Badge badge;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: <Widget>[
          Opacity(
            opacity: badge.earned ? 1 : 0.4,
            child: IconBadge(
                icon: badge.earned ? badge.icon : Icons.lock_rounded,
                color: badge.earned ? badge.color : scheme.muted,
                size: 46,
                filled: badge.earned),
          ),
          const SizedBox(height: 8),
          Text(badge.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: badge.earned ? null : scheme.muted)),
          const SizedBox(height: 2),
          Text(badge.hint,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontSize: 11, height: 1.25, color: scheme.muted)),
        ],
      ),
    );
  }
}
