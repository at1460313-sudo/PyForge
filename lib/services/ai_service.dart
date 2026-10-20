import 'dart:convert';

import 'package:http/http.dart' as http;

/// Supported BYOK providers. OpenAI / OpenRouter / custom all speak the
/// OpenAI chat-completions protocol; Anthropic and Gemini have their own.
enum AiProvider {
  openai('OpenAI', 'https://api.openai.com/v1'),
  openrouter('OpenRouter', 'https://openrouter.ai/api/v1'),
  anthropic('Anthropic', 'https://api.anthropic.com'),
  gemini('Google Gemini', 'https://generativelanguage.googleapis.com/v1beta'),
  custom('Custom (OpenAI-compatible)', '');

  const AiProvider(this.label, this.defaultBaseUrl);
  final String label;
  final String defaultBaseUrl;
}

class AiConfig {
  const AiConfig({
    required this.provider,
    required this.model,
    this.baseUrl = '',
  });

  final AiProvider provider;
  final String model;
  final String baseUrl; // only used for openrouter/custom

  String get effectiveBaseUrl {
    switch (provider) {
      case AiProvider.openai:
      case AiProvider.anthropic:
      case AiProvider.gemini:
        return provider.defaultBaseUrl;
      case AiProvider.openrouter:
        return baseUrl.isEmpty ? provider.defaultBaseUrl : baseUrl;
      case AiProvider.custom:
        return baseUrl;
    }
  }
}

class AiServiceException implements Exception {
  AiServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thin, provider-aware chat client. The API key is passed per call and
/// never stored by this class.
class AiService {
  AiService._();

  static final AiService instance = AiService._();

  final http.Client _client = http.Client();

  /// Suggested models per provider (all editable in Settings).
  static const Map<AiProvider, List<String>> suggestedModels = {
    AiProvider.openai: ['gpt-4o', 'gpt-4o-mini', 'gpt-4.1', 'gpt-4.1-mini'],
    AiProvider.openrouter: [
      'openai/gpt-4o-mini',
      'anthropic/claude-sonnet-4.5',
      'google/gemini-2.5-flash',
    ],
    AiProvider.anthropic: [
      'claude-sonnet-4-5',
      'claude-haiku-4-5',
      'claude-opus-4-1',
    ],
    AiProvider.gemini: ['gemini-2.5-pro', 'gemini-2.5-flash'],
    AiProvider.custom: [],
  };

  /// One-shot completion. [apiKey] is required; throws [AiServiceException]
  /// with a human-readable message on failure.
  Future<String> complete(
    AiConfig config,
    String apiKey, {
    required String system,
    required String user,
    int maxTokens = 2048,
    double temperature = 0.3,
  }) async {
    switch (config.provider) {
      case AiProvider.openai:
      case AiProvider.openrouter:
      case AiProvider.custom:
        return _openAiCompatible(config, apiKey, system, user,
            maxTokens, temperature);
      case AiProvider.anthropic:
        return _anthropic(config, apiKey, system, user, maxTokens, temperature);
      case AiProvider.gemini:
        return _gemini(config, apiKey, system, user, temperature);
    }
  }

  /// Validates the key with a tiny request against the chosen model.
  Future<String> testConnection(AiConfig config, String apiKey) async {
    final String reply = await complete(
      config,
      apiKey,
      system: 'You are a connection test. Reply with the single word: OK',
      user: 'ping',
      maxTokens: 16,
    );
    return reply.trim();
  }

  // ---------------------------------------------------------------------
  // OpenAI-compatible (OpenAI, OpenRouter, custom endpoints)
  // ---------------------------------------------------------------------

  Future<String> _openAiCompatible(
    AiConfig config,
    String apiKey,
    String system,
    String user,
    int maxTokens,
    double temperature,
  ) async {
    final Uri uri = Uri.parse('${config.effectiveBaseUrl}/chat/completions');
    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{
        'model': config.model,
        'temperature': temperature,
        'max_tokens': maxTokens,
        'messages': <Map<String, String>>[
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': user},
        ],
      }),
    );
    _checkStatus(response);
    final Map<String, dynamic> body = jsonDecode(response.body)
        as Map<String, dynamic>;
    final List<dynamic> choices = body['choices'] as List<dynamic>? ?? <dynamic>[];
    if (choices.isEmpty) {
      throw AiServiceException('The model returned no choices.');
    }
    return (choices.first as Map<String, dynamic>)['message']
            ?['content'] as String? ??
        '';
  }

  // ---------------------------------------------------------------------
  // Anthropic
  // ---------------------------------------------------------------------

  Future<String> _anthropic(
    AiConfig config,
    String apiKey,
    String system,
    String user,
    int maxTokens,
    double temperature,
  ) async {
    final Uri uri = Uri.parse('${config.effectiveBaseUrl}/v1/messages');
    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{
        'model': config.model,
        'system': system,
        'max_tokens': maxTokens,
        'temperature': temperature,
        'messages': <Map<String, String>>[
          {'role': 'user', 'content': user},
        ],
      }),
    );
    _checkStatus(response);
    final Map<String, dynamic> body =
        jsonDecode(response.body) as Map<String, dynamic>;
    final List<dynamic> content = body['content'] as List<dynamic>? ?? <dynamic>[];
    final StringBuffer buffer = StringBuffer();
    for (final dynamic part in content) {
      if (part is Map<String, dynamic> && part['text'] != null) {
        buffer.write(part['text']);
      }
    }
    return buffer.toString();
  }

  // ---------------------------------------------------------------------
  // Gemini
  // ---------------------------------------------------------------------

  Future<String> _gemini(
    AiConfig config,
    String apiKey,
    String system,
    String user,
    double temperature,
  ) async {
    final Uri uri = Uri.parse(
      '${config.effectiveBaseUrl}/models/${config.model}:generateContent',
    );
    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        'x-goog-api-key': apiKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{
        'system_instruction': <String, dynamic>{
          'parts': <Map<String, String>>[{'text': system}],
        },
        'contents': <Map<String, dynamic>>[
          <String, dynamic>{
            'parts': <Map<String, String>>[{'text': user}],
          },
        ],
        'generationConfig': <String, dynamic>{
          'temperature': temperature,
        },
      }),
    );
    _checkStatus(response);
    final Map<String, dynamic> body =
        jsonDecode(response.body) as Map<String, dynamic>;
    final List<dynamic> candidates =
        body['candidates'] as List<dynamic>? ?? <dynamic>[];
    if (candidates.isEmpty) {
      throw AiServiceException('Gemini returned no candidates.');
    }
    final List<dynamic> parts =
        (candidates.first as Map<String, dynamic>)['content']?['parts']
                as List<dynamic>? ??
            <dynamic>[];
    final StringBuffer buffer = StringBuffer();
    for (final dynamic part in parts) {
      if (part is Map<String, dynamic> && part['text'] != null) {
        buffer.write(part['text']);
      }
    }
    return buffer.toString();
  }

  void _checkStatus(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String detail = '';
    try {
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final dynamic error = body['error'];
      if (error is Map<String, dynamic>) {
        detail = error['message'] as String? ?? '';
      } else if (error != null) {
        detail = error.toString();
      }
    } catch (_) {
      detail = response.body.length > 200
          ? '${response.body.substring(0, 200)}…'
          : response.body;
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw AiServiceException(
        'Authentication failed (${response.statusCode}). Check your API key '
        'and that the key has access to the selected model. $detail',
      );
    }
    if (response.statusCode == 404) {
      throw AiServiceException(
        'Model or endpoint not found (404). Check the model name and base '
        'URL. $detail',
      );
    }
    throw AiServiceException(
      'Request failed (${response.statusCode}). $detail',
    );
  }
}
