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

/// Number of inserted + deleted lines between [a] and [b] (equal lines are
/// the LCS). Uses two rolling rows, so memory is O(min(n, m)) — safe to call
/// on every save even for large files. Used for the lines-written stat.
int countChangedLines(String a, String b) {
  final List<String> x = a.split('\n');
  final List<String> y = b.split('\n');
  // Keep the shorter sequence as the row dimension.
  final bool swapped = y.length < x.length;
  final List<String> u = swapped ? y : x;
  final List<String> v = swapped ? x : y;
  final int n = u.length, m = v.length;
  List<int> prev = List<int>.filled(m + 1, 0);
  List<int> cur = List<int>.filled(m + 1, 0);
  for (int i = n - 1; i >= 0; i--) {
    for (int j = m - 1; j >= 0; j--) {
      cur[j] = u[i] == v[j]
          ? prev[j + 1] + 1
          : (prev[j] >= cur[j + 1] ? prev[j] : cur[j + 1]);
    }
    final List<int> tmp = prev;
    prev = cur;
    cur = tmp;
    // cur[0] is always 0 and every other cell is overwritten below.
  }
  final int lcs = prev[0];
  return x.length + y.length - 2 * lcs;
}

/// Hirschberg's algorithm: the same LCS-based diff as before, but with
/// O(min(n, m)) memory instead of an (n+1)x(m+1) table. The old table was
/// ~100 MB for two 5,000-line files and ran on every save.
List<DiffLine> diffLines(String a, String b) {
  final List<String> oldLines = a.split('\n');
  final List<String> newLines = b.split('\n');
  final List<DiffLine> out = <DiffLine>[];
  _diff(oldLines, 0, oldLines.length, newLines, 0, newLines.length, out);
  return out;
}

void _diff(List<String> a, int aLo, int aHi, List<String> b, int bLo,
    int bHi, List<DiffLine> out) {
  final int n = aHi - aLo, m = bHi - bLo;
  if (n == 0) {
    for (int j = 0; j < m; j++) {
      out.add(DiffLine(DiffAction.insert, b[bLo + j]));
    }
    return;
  }
  if (m == 0) {
    for (int i = 0; i < n; i++) {
      out.add(DiffLine(DiffAction.delete, a[aLo + i]));
    }
    return;
  }
  if (n == 1) {
    // Single line: match it against the first equal line in b if any.
    int match = -1;
    for (int j = 0; j < m; j++) {
      if (b[bLo + j] == a[aLo]) {
        match = j;
        break;
      }
    }
    for (int j = 0; j < m; j++) {
      if (j != match) {
        out.add(DiffLine(DiffAction.insert, b[bLo + j]));
      }
      if (j == match) {
        out.add(DiffLine(DiffAction.equal, a[aLo]));
      }
    }
    if (match < 0) out.add(DiffLine(DiffAction.delete, a[aLo]));
    return;
  }
  // Split a in half and find the b-split with the best combined LCS.
  final int mid = aLo + n ~/ 2;
  final List<int> forward = _lcsRow(a, aLo, mid, b, bLo, bHi);
  final List<int> backward = _lcsRowBackward(a, mid, aHi, b, bLo, bHi);
  int bestK = 0, best = -1;
  for (int k = 0; k <= m; k++) {
    final int total = forward[k] + backward[m - k];
    if (total > best) {
      best = total;
      bestK = k;
    }
  }
  _diff(a, aLo, mid, b, bLo, bLo + bestK, out);
  _diff(a, mid, aHi, b, bLo + bestK, bHi, out);
}

/// LCS lengths of a[aLo..aHi) against every prefix of b[bLo..bHi).
/// Returns row[m + 1] where row[k] = LCS(a-range, b[bLo..bLo+k)).
List<int> _lcsRow(List<String> a, int aLo, int aHi, List<String> b,
    int bLo, int bHi) {
  final int m = bHi - bLo;
  List<int> prev = List<int>.filled(m + 1, 0);
  List<int> cur = List<int>.filled(m + 1, 0);
  for (int i = aLo; i < aHi; i++) {
    for (int j = 0; j < m; j++) {
      cur[j + 1] = a[i] == b[bLo + j]
          ? prev[j] + 1
          : (prev[j + 1] >= cur[j] ? prev[j + 1] : cur[j]);
    }
    final List<int> tmp = prev;
    prev = cur;
    cur = tmp;
  }
  return prev;
}

/// Same, but from the right: row[k] = LCS(a-range, b[bHi-k..bHi)).
List<int> _lcsRowBackward(List<String> a, int aLo, int aHi, List<String> b,
    int bLo, int bHi) {
  final int m = bHi - bLo;
  List<int> prev = List<int>.filled(m + 1, 0);
  List<int> cur = List<int>.filled(m + 1, 0);
  for (int i = aHi - 1; i >= aLo; i--) {
    for (int j = m - 1; j >= 0; j--) {
      cur[m - j] = a[i] == b[bLo + j]
          ? prev[m - j - 1] + 1
          : (prev[m - j] >= cur[m - j - 1] ? prev[m - j] : cur[m - j - 1]);
    }
    final List<int> tmp = prev;
    prev = cur;
    cur = tmp;
  }
  return prev;
}
