import 'dart:convert';

/// Helpers for parsing AI responses (quizzes, code fixes).
/// All of them degrade gracefully: a malformed reply never crashes the UI.

class QuizQuestion {
  const QuizQuestion({
    required this.question,
    required this.options,
    required this.answerIndex,
    this.explanation = '',
  });

  final String question;
  final List<String> options;
  final int answerIndex;
  final String explanation;
}

/// Extracts the first fenced ``` code block from a reply (language tag
/// optional). Falls back to the raw text.
String extractFencedCode(String reply) {
  final RegExp fenced = RegExp(r'```[a-zA-Z]*\n(.*?)```', dotAll: true);
  final RegExpMatch? match = fenced.firstMatch(reply);
  if (match != null) return match.group(1)!.trim();
  return reply.trim();
}

/// Parses a fix reply that should contain JSON:
/// {"explanation": "...", "fixed_code": "..."} — with a fenced-code
/// fallback. Returns null when nothing usable is found.
Map<String, String>? parseFixReply(String reply) {
  // Try direct JSON first.
  final Map<String, String>? direct = _tryFixJson(reply);
  if (direct != null) return direct;
  // Then a fenced JSON block.
  final RegExp fencedJson = RegExp(r'```(?:json)?\n(\{.*?\})\s*```', dotAll: true);
  final RegExpMatch? match = fencedJson.firstMatch(reply);
  if (match != null) {
    final Map<String, String>? parsed = _tryFixJson(match.group(1)!);
    if (parsed != null) return parsed;
  }
  // Fallback: any explanation text + fenced code block.
  final String code = extractFencedCode(reply);
  if (code.isNotEmpty && code != reply.trim()) {
    return <String, String>{
      'explanation': reply.replaceAll(RegExp(r'```.*?```', dotAll: true), '').trim(),
      'fixed_code': code,
    };
  }
  return null;
}

Map<String, String>? _tryFixJson(String text) {
  try {
    final Map<String, dynamic> decoded =
        jsonDecode(text) as Map<String, dynamic>;
    final String? code = decoded['fixed_code'] as String?;
    if (code == null || code.isEmpty) return null;
    return <String, String>{
      'explanation': (decoded['explanation'] as String?) ?? '',
      'fixed_code': code,
    };
  } catch (_) {
    return null;
  }
}

/// Parses a quiz reply: expected JSON list of
/// {question, options[], answerIndex, explanation}. Lenient: accepts
/// "answer" as a letter (A-D) or index, and tolerates surrounding prose.
List<QuizQuestion> parseQuizReply(String reply) {
  final String candidate = _extractJsonList(reply);
  if (candidate.isEmpty) return <QuizQuestion>[];
  try {
    final List<dynamic> decoded = jsonDecode(candidate) as List<dynamic>;
    final List<QuizQuestion> questions = <QuizQuestion>[];
    for (final dynamic item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final String question = (item['question'] as String?)?.trim() ?? '';
      final List<String> options =
          ((item['options'] as List<dynamic>?) ?? <dynamic>[])
              .map((dynamic e) => e.toString())
              .toList();
      if (question.isEmpty || options.length < 2) continue;
      int answerIndex = 0;
      final dynamic answer = item['answerIndex'] ?? item['answer'] ?? item['answer_index'];
      if (answer is int) {
        answerIndex = answer;
      } else if (answer is String) {
        final int? asInt = int.tryParse(answer);
        if (asInt != null) {
          answerIndex = asInt;
        } else if (answer.isNotEmpty) {
          answerIndex = answer.toUpperCase().codeUnitAt(0) - 0x41; // A=0, B=1…
        }
      }
      if (answerIndex < 0 || answerIndex >= options.length) answerIndex = 0;
      questions.add(QuizQuestion(
        question: question,
        options: options.cast<String>(),
        answerIndex: answerIndex,
        explanation: (item['explanation'] as String?) ?? '',
      ));
    }
    return questions;
  } catch (_) {
    return <QuizQuestion>[];
  }
}

String _extractJsonList(String reply) {
  final int start = reply.indexOf('[');
  final int end = reply.lastIndexOf(']');
  if (start >= 0 && end > start) return reply.substring(start, end + 1);
  return '';
}

/// A tiny line-based diff used by the "Fix my bug" preview.
/// Returns per-line actions for rendering an inline diff view.
enum DiffAction { equal, insert, delete }

class DiffLine {
  const DiffLine(this.action, this.text);
  final DiffAction action;
  final String text;
}

/// Simple LCS-based diff (fine for the small files learners write).
List<DiffLine> diffLines(String a, String b) {
  final List<String> oldLines = a.split('\n');
  final List<String> newLines = b.split('\n');
  final int n = oldLines.length;
  final int m = newLines.length;
  final List<List<int>> lcs = List<List<int>>.generate(
    n + 1,
    (_) => List<int>.filled(m + 1, 0),
  );
  for (int i = n - 1; i >= 0; i--) {
    for (int j = m - 1; j >= 0; j--) {
      lcs[i][j] = oldLines[i] == newLines[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final List<DiffLine> out = <DiffLine>[];
  int i = 0, j = 0;
  while (i < n && j < m) {
    if (oldLines[i] == newLines[j]) {
      out.add(DiffLine(DiffAction.equal, oldLines[i]));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      out.add(DiffLine(DiffAction.delete, oldLines[i]));
      i++;
    } else {
      out.add(DiffLine(DiffAction.insert, newLines[j]));
      j++;
    }
  }
  while (i < n) {
    out.add(DiffLine(DiffAction.delete, oldLines[i]));
    i++;
  }
  while (j < m) {
    out.add(DiffLine(DiffAction.insert, newLines[j]));
    j++;
  }
  return out;
}
