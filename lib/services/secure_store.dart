import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted local storage for secrets (API keys, git tokens).
///
/// Keys never touch SharedPreferences, logs or the repository.
class SecureStore {
  SecureStore._();

  static final SecureStore instance = SecureStore._();

  static const String _kApiKey = 'ai_api_key';
  static const String _kGitToken = 'git_token';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<String?> get apiKey async => await _storage.read(key: _kApiKey);

  Future<void> saveApiKey(String key) async =>
      await _storage.write(key: _kApiKey, value: key);

  Future<void> deleteApiKey() async =>
      await _storage.delete(key: _kApiKey);

  Future<String?> get gitToken async => await _storage.read(key: _kGitToken);

  Future<void> saveGitToken(String token) async =>
      await _storage.write(key: _kGitToken, value: token);

  Future<void> deleteGitToken() async =>
      await _storage.delete(key: _kGitToken);
}
