import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Learning progress: streaks, challenges, lessons read, lines written.
class ProgressModel extends ChangeNotifier {
  int streakDays = 0;
  DateTime? lastActiveDate;
  int linesWritten = 0;
  int runsCount = 0;
  int quizzesTaken = 0;
  final Set<String> completedChallenges = <String>{};
  final Set<String> readLessons = <String>{};

  Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    streakDays = prefs.getInt('streakDays') ?? 0;
    final int? lastMs = prefs.getInt('lastActiveMs');
    lastActiveDate = lastMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lastMs);
    linesWritten = prefs.getInt('linesWritten') ?? 0;
    runsCount = prefs.getInt('runsCount') ?? 0;
    quizzesTaken = prefs.getInt('quizzesTaken') ?? 0;
    completedChallenges.clear();
    completedChallenges.addAll(prefs.getStringList('completedChallenges') ?? <String>[]);
    readLessons.clear();
    readLessons.addAll(prefs.getStringList('readLessons') ?? <String>[]);
    notifyListeners();
  }

  Future<void> _save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('streakDays', streakDays);
    await prefs.setInt(
        'lastActiveMs', lastActiveDate?.millisecondsSinceEpoch ?? 0);
    await prefs.setInt('linesWritten', linesWritten);
    await prefs.setInt('runsCount', runsCount);
    await prefs.setInt('quizzesTaken', quizzesTaken);
    await prefs.setStringList(
        'completedChallenges', completedChallenges.toList());
    await prefs.setStringList('readLessons', readLessons.toList());
  }

  /// Call on any meaningful activity (run, save, challenge).
  /// Maintains the daily streak with a one-day grace for timezones.
  Future<void> recordActivity() async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    if (lastActiveDate == null) {
      streakDays = 1;
    } else {
      final int dayDelta = today.difference(DateTime(
        lastActiveDate!.year,
        lastActiveDate!.month,
        lastActiveDate!.day,
      )).inDays;
      if (dayDelta == 0) {
        return; // already counted today
      } else if (dayDelta == 1) {
        streakDays += 1;
      } else {
        streakDays = 1;
      }
    }
    lastActiveDate = today;
    await _save();
    notifyListeners();
  }

  Future<void> recordLinesWritten(int delta) async {
    if (delta <= 0) return;
    linesWritten += delta;
    await _save();
    notifyListeners();
  }

  Future<void> recordRun() async {
    runsCount += 1;
    await _save();
    notifyListeners();
  }

  Future<void> recordQuiz() async {
    quizzesTaken += 1;
    await _save();
    notifyListeners();
  }

  Future<void> completeChallenge(String id) async {
    final bool added = completedChallenges.add(id);
    if (added) await _save();
    notifyListeners();
  }

  Future<void> markLessonRead(String id) async {
    final bool added = readLessons.add(id);
    if (added) await _save();
    notifyListeners();
  }
}
