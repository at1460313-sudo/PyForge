import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Dart side of the Kotlin/Chaquopy bridge.
///
/// All commands go over the "pyforge/bridge" method channel; events
/// (streamed output, debugger pauses, input requests) arrive on
/// "pyforge/events". Every payload is JSON.
class PythonBridge {
  PythonBridge._();

  static final PythonBridge instance = PythonBridge._();

  static const MethodChannel _bridge = MethodChannel('pyforge/bridge');
  static const MethodChannel _events = MethodChannel('pyforge/events');

  final StreamController<Map<String, dynamic>> _eventController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Broadcast stream of bridge events: type is one of
  /// output | input_request | debug_pause.
  Stream<Map<String, dynamic>> get events => _eventController.stream;

  Future<void> init() async {
    _events.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onEvent') {
        final Map<String, dynamic> payload =
            jsonDecode(call.arguments as String) as Map<String, dynamic>;
        _eventController.add(payload);
      }
      return null;
    });
    // Warm up the interpreter so the first Run feels instant.
    unawaited(ping());
  }

  /// Decodes a bridge reply. The Kotlin layer reports its own failures
  /// (e.g. Python failed to start) as {"ok": false, "error": "<text>"},
  /// whereas Python reports {"ok": false, "error": {type, message, ...}}.
  /// Normalise both to the map shape so errors are never silently dropped.
  static Map<String, dynamic> _decode(String raw) {
    final Map<String, dynamic> map = jsonDecode(raw) as Map<String, dynamic>;
    final Object? error = map['error'];
    if (map['ok'] == false && error is String) {
      map['error'] = <String, dynamic>{
        'type': 'BridgeError',
        'message': error,
        'line': null,
        'traceback': error,
      };
      map['message'] ??= error;
    }
    return map;
  }

  Future<bool> ping() async =>
      await _bridge.invokeMethod('ping') == 'pong';

  // ---- Error Lens -------------------------------------------------------

  Future<Map<String, dynamic>> checkSyntax(String source) async {
    final String raw = await _bridge.invokeMethod('checkSyntax', {
      'source': source,
    });
    return _decode(raw);
  }

  // ---- Run --------------------------------------------------------------

  Future<Map<String, dynamic>> runCode({
    required String runId,
    required String filePath,
    required String source,
  }) async {
    final String raw = await _bridge.invokeMethod('runCode', {
      'runId': runId,
      'filePath': filePath,
      'source': source,
    });
    return _decode(raw);
  }

  Future<void> stopRun() => _bridge.invokeMethod('stopRun');

  Future<void> submitInput(String text) =>
      _bridge.invokeMethod('submitInput', {'text': text});

  // ---- Debugger ---------------------------------------------------------

  Future<Map<String, dynamic>> debugRun({
    required String runId,
    required String filePath,
    required String source,
    required List<int> breakpoints,
  }) async {
    final String raw = await _bridge.invokeMethod('debugRun', {
      'runId': runId,
      'filePath': filePath,
      'source': source,
      'breakpoints': breakpoints,
    });
    return _decode(raw);
  }

  Future<void> debugStep() => _bridge.invokeMethod('debugStep');
  Future<void> debugContinue() => _bridge.invokeMethod('debugContinue');
  Future<void> debugStop() => _bridge.invokeMethod('debugStop');
  Future<void> debugPause() => _bridge.invokeMethod('debugPause');

  // ---- Packages ---------------------------------------------------------

  Future<Map<String, dynamic>> listPackages() async {
    final String raw = await _bridge.invokeMethod('listPackages');
    return _decode(raw);
  }

  Future<Map<String, dynamic>> tryInstallPackage(String name) async {
    final String raw = await _bridge.invokeMethod('tryInstallPackage', {
      'name': name,
    });
    return _decode(raw);
  }

  // ---- Curriculum -------------------------------------------------------

  Future<Map<String, dynamic>> challengeCheck({
    required String challengeId,
    required String source,
    required String testCode,
  }) async {
    final String raw = await _bridge.invokeMethod('challengeCheck', {
      'challengeId': challengeId,
      'source': source,
      'testCode': testCode,
    });
    return _decode(raw);
  }

  // ---- Git --------------------------------------------------------------

  Future<Map<String, dynamic>> gitInit(String repoPath) async {
    final String raw =
        await _bridge.invokeMethod('gitInit', {'repoPath': repoPath});
    return _decode(raw);
  }

  Future<Map<String, dynamic>> gitStatus(String repoPath) async {
    final String raw =
        await _bridge.invokeMethod('gitStatus', {'repoPath': repoPath});
    return _decode(raw);
  }

  Future<Map<String, dynamic>> gitCommit({
    required String repoPath,
    required String message,
    required String authorName,
    required String authorEmail,
  }) async {
    final String raw = await _bridge.invokeMethod('gitCommit', {
      'repoPath': repoPath,
      'message': message,
      'authorName': authorName,
      'authorEmail': authorEmail,
    });
    return _decode(raw);
  }

  Future<Map<String, dynamic>> gitPush({
    required String repoPath,
    required String remoteUrl,
    required String username,
    required String token,
  }) async {
    final String raw = await _bridge.invokeMethod('gitPush', {
      'repoPath': repoPath,
      'remoteUrl': remoteUrl,
      'username': username,
      'token': token,
    });
    return _decode(raw);
  }
}
