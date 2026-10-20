import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/python_bridge.dart';

class RunLine {
  RunLine({required this.stream, required this.text, this.open = true});

  final String stream; // stdout | stderr
  String text;

  /// True while more text may still be appended to this logical line.
  bool open;
}

enum RunState { idle, running, waitingInput }

/// Live program output, run lifecycle and input() handling.
class RunModel extends ChangeNotifier {
  RunState state = RunState.idle;
  final List<RunLine> lines = <RunLine>[];
  String? inputPrompt;
  String? runId;
  Map<String, dynamic>? lastError;
  bool lastRunCancelled = false;

  StreamSubscription<Map<String, dynamic>>? _sub;

  void wire() {
    _sub = PythonBridge.instance.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onEvent(Map<String, dynamic> event) {
    final String type = event['type'] as String? ?? '';
    if (type == 'output') {
      if (event['runId'] != runId) return;
      final String stream = event['stream'] as String? ?? 'stdout';
      final String text = event['text'] as String? ?? '';
      if (text.isEmpty) return;
      _appendText(stream, text);
      // Keep the terminal bounded so huge print loops stay smooth.
      if (lines.length > 5000) lines.removeRange(0, lines.length - 5000);
      notifyListeners();
    } else if (type == 'input_request') {
      if (event['runId'] != runId) return;
      state = RunState.waitingInput;
      inputPrompt = event['prompt'] as String? ?? '';
      notifyListeners();
    }
  }

  /// Coalesces streamed chunks into logical lines (a single print() can
  /// arrive as several writes).
  void _appendText(String stream, String text) {
    final List<String> parts = text.split('\n');
    for (int i = 0; i < parts.length; i++) {
      final String part = parts[i];
      final bool isLast = i == parts.length - 1;
      if (i == 0 &&
          lines.isNotEmpty &&
          lines.last.open &&
          lines.last.stream == stream) {
        lines.last.text += part;
        if (!isLast) lines.last.open = false;
        continue;
      }
      if (i > 0 && lines.isNotEmpty && lines.last.open) {
        lines.last.open = false;
      }
      // An empty part is only skipped when it is the (empty) tail after a
      // trailing "\n"; otherwise it is a real blank line from print().
      if (part.isNotEmpty || !isLast) {
        lines.add(RunLine(stream: stream, text: part, open: isLast));
      }
    }
  }

  bool get hasError => lastError != null;

  void clear() {
    lines.clear();
    lastError = null;
    lastRunCancelled = false;
    notifyListeners();
  }

  Future<void> run(
    String filePath,
    String source, {
    void Function(Map<String, dynamic> result)? onDone,
  }) async {
    clear();
    runId = 'run-${DateTime.now().millisecondsSinceEpoch}';
    state = RunState.running;
    notifyListeners();
    Map<String, dynamic> result;
    try {
      result = await PythonBridge.instance.runCode(
        runId: runId!,
        filePath: filePath,
        source: source,
      );
    } catch (e) {
      // Never leave the UI stuck in "running" if the bridge itself fails.
      result = <String, dynamic>{
        'ok': false,
        'error': <String, dynamic>{
          'type': 'BridgeError',
          'message': '$e',
          'line': null,
          'traceback': '$e',
        },
      };
    }
    _showResult(result);
    state = RunState.idle;
    inputPrompt = null;
    notifyListeners();
    onDone?.call(result);
  }

  /// Appends the "[stopped]" / traceback lines for a finished run or debug.
  void _showResult(Map<String, dynamic> result) {
    if (result['cancelled'] == true || result['stoppedByUser'] == true) {
      lastRunCancelled = true;
      lines.add(RunLine(
          stream: 'stderr', text: '\n[stopped by user]\n', open: false));
    }
    if (result['ok'] == false && result['error'] is Map) {
      lastError = Map<String, dynamic>.from(result['error'] as Map);
      lines.add(RunLine(
        stream: 'stderr',
        text: '\n${(lastError!['traceback'] as String? ?? '').trim()}',
        open: false,
      ));
    }
  }

  /// Capture output for a debug session (output events for [debugId]).
  void beginDebugCapture(String debugId) {
    clear();
    runId = debugId;
    state = RunState.running;
    notifyListeners();
  }

  void endDebugCapture([Map<String, dynamic>? result]) {
    if (result != null) _showResult(result);
    state = RunState.idle;
    inputPrompt = null;
    notifyListeners();
  }

  Future<void> stop() => PythonBridge.instance.stopRun();

  Future<void> submitInput(String text) async {
    state = RunState.running;
    inputPrompt = null;
    notifyListeners();
    lines.add(RunLine(stream: 'stdout', text: text, open: false));
    await PythonBridge.instance.submitInput(text);
  }
}

/// The visual step-through debugger. Pauses are real: the Python worker
/// thread blocks until Step / Continue / Stop arrives.
class DebuggerModel extends ChangeNotifier {
  bool active = false;
  bool paused = false;
  int currentLine = 0;
  Map<String, String> variables = <String, String>{};
  String? filePath;
  String? runId;
  final Map<String, Set<int>> breakpoints = <String, Set<int>>{};
  StreamSubscription<Map<String, dynamic>>? _sub;

  void wire() {
    _sub = PythonBridge.instance.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onEvent(Map<String, dynamic> event) {
    if (!active) return;
    final String type = event['type'] as String? ?? '';
    if (type != 'debug_pause') return;
    if (event['runId'] != runId) return;
    paused = true;
    currentLine = (event['line'] as num?)?.toInt() ?? 0;
    final dynamic locals = event['locals'];
    if (locals is String) {
      try {
        final Map<String, dynamic> raw =
            jsonDecode(locals) as Map<String, dynamic>;
        variables = raw.map((String k, dynamic v) => MapEntry(k, v.toString()));
      } catch (_) {
        variables = <String, String>{};
      }
    }
    notifyListeners();
  }

  List<int> breakpointsFor(String path) =>
      (breakpoints[path] ?? <int>{}).toList()..sort();

  void toggleBreakpoint(String path, int line) {
    final Set<int> set = breakpoints.putIfAbsent(path, () => <int>{});
    if (!set.add(line)) set.remove(line);
    if (set.isEmpty) breakpoints.remove(path);
    notifyListeners();
  }

  /// Runs under the debugger and returns the Python result so the caller
  /// can show a traceback if the program crashed.
  Future<Map<String, dynamic>> start(String filePath, String source,
      {String? runId}) async {
    final String id =
        runId ?? 'debug-${DateTime.now().millisecondsSinceEpoch}';
    this.filePath = filePath;
    this.runId = id;
    active = true;
    paused = false;
    variables = <String, String>{};
    notifyListeners();
    Map<String, dynamic> result;
    try {
      result = await PythonBridge.instance.debugRun(
        runId: id,
        filePath: filePath,
        source: source,
        breakpoints: breakpointsFor(filePath),
      );
    } catch (e) {
      result = <String, dynamic>{
        'ok': false,
        'error': <String, dynamic>{
          'type': 'BridgeError',
          'message': '$e',
          'line': null,
          'traceback': '$e',
        },
      };
    }
    active = false;
    paused = false;
    notifyListeners();
    return result;
  }

  Future<void> step() async {
    paused = false;
    notifyListeners();
    await PythonBridge.instance.debugStep();
  }

  Future<void> continueRun() async {
    paused = false;
    notifyListeners();
    await PythonBridge.instance.debugContinue();
  }

  Future<void> stop() async {
    await PythonBridge.instance.debugStop();
    active = false;
    paused = false;
    notifyListeners();
  }

  Future<void> pause() => PythonBridge.instance.debugPause();
}
