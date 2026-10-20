import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/ai_service.dart';
import '../services/secure_store.dart';
import '../theme/app_theme.dart';
import '../theme/syntax_themes.dart';

/// App settings. Secrets (API keys, tokens) live in [SecureStore]; this
/// model persists only non-sensitive preferences.
class SettingsModel extends ChangeNotifier {
  AppThemeMode themeMode = AppThemeMode.dark;
  String syntaxThemeId = SyntaxThemes.defaultId;
  double fontSize = 15;

  AiProvider aiProvider = AiProvider.openai;
  String aiModel = 'gpt-4o-mini';
  String aiBaseUrl = ''; // used by openrouter / custom
  bool hasApiKey = false;

  String gitAuthorName = 'PyForge Learner';
  String gitAuthorEmail = 'learner@pyforge.local';
  String gitRemoteUrl = '';
  String gitUsername = '';

  /// Stored enum indexes can go stale when values are added/reordered in an
  /// app update; an out-of-range index must not crash startup.
  static T _enumAt<T>(List<T> values, int? index, T fallback) =>
      (index != null && index >= 0 && index < values.length)
          ? values[index]
          : fallback;

  Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    themeMode = _enumAt(AppThemeMode.values, prefs.getInt('themeMode'),
        AppThemeMode.dark);
    syntaxThemeId =
        prefs.getString('syntaxTheme') ?? SyntaxThemes.defaultId;
    fontSize = prefs.getDouble('fontSize') ?? 15;
    aiProvider = _enumAt(
        AiProvider.values, prefs.getInt('aiProvider'), AiProvider.openai);
    aiModel = prefs.getString('aiModel') ?? 'gpt-4o-mini';
    aiBaseUrl = prefs.getString('aiBaseUrl') ?? '';
    try {
      hasApiKey = await SecureStore.instance.apiKey != null;
    } catch (_) {
      // Keystore data can be unreadable after a backup restore / new device.
      // Treat it as "no key saved" instead of crashing at startup.
      hasApiKey = false;
    }
    gitAuthorName = prefs.getString('gitAuthorName') ?? gitAuthorName;
    gitAuthorEmail = prefs.getString('gitAuthorEmail') ?? gitAuthorEmail;
    gitRemoteUrl = prefs.getString('gitRemoteUrl') ?? '';
    gitUsername = prefs.getString('gitUsername') ?? '';
    notifyListeners();
  }

  Future<void> _persist(String key, Object value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    themeMode = mode;
    await _persist('themeMode', mode.index);
    notifyListeners();
  }

  Future<void> setSyntaxTheme(String id) async {
    syntaxThemeId = id;
    await _persist('syntaxTheme', id);
    notifyListeners();
  }

  Future<void> setFontSize(double size) async {
    fontSize = size;
    await _persist('fontSize', size);
    notifyListeners();
  }

  Future<void> setAiProvider(AiProvider provider) async {
    aiProvider = provider;
    await _persist('aiProvider', provider.index);
    notifyListeners();
  }

  Future<void> setAiModel(String model) async {
    aiModel = model;
    await _persist('aiModel', model);
    notifyListeners();
  }

  Future<void> setAiBaseUrl(String url) async {
    aiBaseUrl = url;
    await _persist('aiBaseUrl', url);
    notifyListeners();
  }

  Future<void> setGitAuthorName(String value) async {
    gitAuthorName = value;
    await _persist('gitAuthorName', value);
  }

  Future<void> setGitAuthorEmail(String value) async {
    gitAuthorEmail = value;
    await _persist('gitAuthorEmail', value);
  }

  Future<void> setGitRemoteUrl(String value) async {
    gitRemoteUrl = value;
    await _persist('gitRemoteUrl', value);
  }

  Future<void> setGitUsername(String value) async {
    gitUsername = value;
    await _persist('gitUsername', value);
  }

  AiConfig get aiConfig => AiConfig(
        provider: aiProvider,
        model: aiModel,
        baseUrl: aiBaseUrl,
      );

  Future<String?> get apiKey => SecureStore.instance.apiKey;
}
