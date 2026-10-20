import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/curriculum_data.dart';
import '../state/progress_model.dart';

/// Learning progress dashboard: streak, challenges, lessons, lines written.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ProgressModel progress = context.watch<ProgressModel>();
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // Streak hero card.
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  scheme.primary.withValues(alpha: 0.22),
                  scheme.secondary.withValues(alpha: 0.22),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: <Widget>[
                Column(
                  children: <Widget>[
                    Text(
                      '${progress.streakDays}',
                      style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          color: scheme.primary),
                    ),
                  ],
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(Icons.local_fire_department,
                              color: scheme.primary, size: 20),
                          const SizedBox(width: 6),
                          Text(
                            progress.streakDays == 1
                                ? 'day streak'
                                : 'day streak',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        progress.streakDays == 0
                            ? 'Write some code today to start a streak!'
                            : 'Keep going — consistency beats intensity.',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurface.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Stat grid.
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.7,
            children: <Widget>[
              _StatCard(
                icon: Icons.emoji_events_outlined,
                label: 'Challenges',
                value: '${progress.completedChallenges.length}/${kChallenges.length}',
              ),
              _StatCard(
                icon: Icons.menu_book_outlined,
                label: 'Lessons read',
                value: '${progress.readLessons.length}/${kLessons.length}',
              ),
              _StatCard(
                icon: Icons.code,
                label: 'Lines written',
                value: '${progress.linesWritten}',
              ),
              _StatCard(
                icon: Icons.play_circle_outline,
                label: 'Programs run',
                value: '${progress.runsCount}',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _StatCard(
            icon: Icons.quiz_outlined,
            label: 'Quizzes taken',
            value: '${progress.quizzesTaken}',
          ),
          const SizedBox(height: 24),
          // Challenges checklist.
          const Text('Challenges',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final Challenge challenge in kChallenges)
            ListTile(
              dense: true,
              leading: Icon(
                progress.completedChallenges.contains(challenge.id)
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                color: progress.completedChallenges.contains(challenge.id)
                    ? Colors.green
                    : scheme.onSurface.withValues(alpha: 0.4),
              ),
              title: Text(challenge.title,
                  style: const TextStyle(fontSize: 13.5)),
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurface.withValues(alpha: 0.6))),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
