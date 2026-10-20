import 'package:flutter_test/flutter_test.dart';

import 'package:pyforge/utils/ai_parsing.dart';

void main() {
  group('extractFencedCode', () {
    test('extracts a fenced python block', () {
      const String reply = 'Here you go:\n```python\nprint("hi")\n```\nDone.';
      expect(extractFencedCode(reply), 'print("hi")');
    });

    test('falls back to raw text', () {
      expect(extractFencedCode('just text'), 'just text');
    });
  });

  group('parseFixReply', () {
    test('parses JSON fix replies', () {
      const String reply =
          '{"explanation": "typo", "fixed_code": "print(1)"}';
      final Map<String, String>? parsed = parseFixReply(reply);
      expect(parsed, isNotNull);
      expect(parsed!['fixed_code'], 'print(1)');
    });

    test('parses fenced-JSON fix replies', () {
      const String reply =
          'Sure!\n```json\n{"explanation": "x", "fixed_code": "y"}\n```';
      final Map<String, String>? parsed = parseFixReply(reply);
      expect(parsed?['fixed_code'], 'y');
    });

    test('returns null for garbage', () {
      expect(parseFixReply('no code here at all'), isNull);
    });
  });

  group('parseQuizReply', () {
    test('parses a quiz with answerIndex', () {
      const String reply =
          '[{"question": "Q?", "options": ["a", "b"], "answerIndex": 1, '
          '"explanation": "e"}]';
      final List<QuizQuestion> quiz = parseQuizReply(reply);
      expect(quiz, hasLength(1));
      expect(quiz.first.answerIndex, 1);
    });

    test('accepts letter answers', () {
      const String reply =
          '[{"question": "Q?", "options": ["a", "b"], "answer": "B"}]';
      final List<QuizQuestion> quiz = parseQuizReply(reply);
      expect(quiz.first.answerIndex, 1);
    });

    test('ignores malformed quizzes', () {
      expect(parseQuizReply('not json'), isEmpty);
    });
  });

  group('diffLines', () {
    test('detects insertions and deletions', () {
      final List<DiffLine> diff = diffLines('a\nb\nc', 'a\nx\nc\nd');
      final int inserts =
          diff.where((DiffLine d) => d.action == DiffAction.insert).length;
      final int deletes =
          diff.where((DiffLine d) => d.action == DiffAction.delete).length;
      expect(inserts, 2); // x and d
      expect(deletes, 1); // b
      expect(diff.first.text, 'a');
    });

    test('equal text produces all-equal diff', () {
      final List<DiffLine> diff = diffLines('a\nb', 'a\nb');
      expect(diff.every((DiffLine d) => d.action == DiffAction.equal), isTrue);
    });
  });
}
