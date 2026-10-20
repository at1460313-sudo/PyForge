import 'package:flutter/foundation.dart';

import '../services/ai_service.dart';
import '../utils/ai_parsing.dart';
import 'settings_model.dart';

/// AI Co-Pilot state machine. All prompts are sent only when the user
/// explicitly taps an action; nothing is auto-submitted.
class AiModel extends ChangeNotifier {
  bool busy = false;
  String? explanation;
  Map<String, String>? fix; // {explanation, fixed_code}
  String? fixOriginalCode;
  String? fixPath; // the file the fix was generated for
  List<QuizQuestion> quiz = <QuizQuestion>[];
  String? error;

  Future<String?> _key(SettingsModel settings) => settings.apiKey;

  Future<bool> _begin(SettingsModel settings) async {
    final String? key = await _key(settings);
    if (key == null || key.isEmpty) {
      error = 'No API key configured. Open Settings and add your key.';
      notifyListeners();
      return false;
    }
    busy = true;
    error = null;
    notifyListeners();
    return true;
  }

  Future<void> _run(
    SettingsModel settings,
    Future<void> Function(String apiKey) body,
  ) async {
    if (!await _begin(settings)) return;
    try {
      await body((await _key(settings))!);
    } on AiServiceException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'AI request failed: $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void clear() {
    explanation = null;
    fix = null;
    fixOriginalCode = null;
    fixPath = null;
    quiz = <QuizQuestion>[];
    error = null;
    notifyListeners();
  }

  /// "Explain this code"
  Future<void> explainCode(String code, SettingsModel settings) => _run(
        settings,
        (String apiKey) async {
          final String reply = await AiService.instance.complete(
            settings.aiConfig,
            apiKey,
            system: 'You are a friendly, patient Python tutor for beginners. '
                'Explain code concisely in plain English, define jargon, and '
                'point out one thing the learner did well or could improve. '
                'Use short paragraphs, never markdown tables.',
            user: 'Explain this Python code:\n\n```\n$code\n```',
          );
          explanation = reply.trim();
        },
      );

  /// "Fix my bug" — returns explanation + fixed code for the diff view.
  Future<void> fixCode(
    String code,
    Map<String, dynamic>? runError,
    SettingsModel settings, {
    String? path,
  }) => _run(
        settings,
        (String apiKey) async {
          final String errorText = runError == null
              ? 'The user reports the code is not working as expected.'
              : 'Error: ${runError['type']}: ${runError['message']}\n'
                  'On line: ${runError['line']}\n\n'
                  'Traceback:\n${runError['traceback']}';
          final String reply = await AiService.instance.complete(
            settings.aiConfig,
            apiKey,
            system: 'You are a Python expert fixing a learner\'s code. '
                'Reply ONLY with JSON: {"explanation": "what was wrong, in '
                'one or two friendly sentences", "fixed_code": "the complete '
                'fixed file"} — no markdown fences, no extra keys.',
            user: 'Fix this code.\n$errorText\n\nThe code:\n\n$code',
            maxTokens: 4096,
          );
          final Map<String, String>? parsed = parseFixReply(reply);
          if (parsed == null) {
            error = 'The AI reply could not be parsed as a fix. Try again.';
            return;
          }
          fixOriginalCode = code;
          fixPath = path;
          fix = parsed;
        },
      );

  /// "Generate a quiz on this topic"
  Future<void> generateQuiz(String topic, SettingsModel settings) => _run(
        settings,
        (String apiKey) async {
          final String reply = await AiService.instance.complete(
            settings.aiConfig,
            apiKey,
            system: 'You are a Python quiz generator. Reply ONLY with a JSON '
                'array of 5 objects: {"question": str, "options": [4 '
                'strings], "answerIndex": 0-3, "explanation": str}. '
                'No markdown fences, no extra text.',
            user: 'Create a quiz about: $topic',
            maxTokens: 3072,
          );
          final List<QuizQuestion> parsed = parseQuizReply(reply);
          if (parsed.isEmpty) {
            error = 'The AI reply could not be parsed as a quiz. Try again.';
            return;
          }
          quiz = parsed;
        },
      );

  /// "Smart error explanation" for a crashed run.
  Future<void> explainTraceback(
    Map<String, dynamic> runError,
    String code,
    SettingsModel settings,
  ) => _run(
        settings,
        (String apiKey) async {
          final String reply = await AiService.instance.complete(
            settings.aiConfig,
            apiKey,
            system: 'You are a Python tutor translating tracebacks into '
                'plain English for a beginner. Explain what went wrong, why, '
                'and how to avoid it. Be concise and warm.',
            user: 'This Python program crashed:\n'
                '${runError['type']}: ${runError['message']}\n'
                'Line ${runError['line']}\n\n'
                'Traceback:\n${runError['traceback']}\n\n'
                'The code:\n\n$code',
          );
          explanation = reply.trim();
        },
      );
}
