// Copy to PyForge/test/audit_dart_regressions_test.dart and run `flutter test`.
// These assert desired behavior, so failures on the reviewed commit are expected.
// (The debugger test needs DebuggerModel.start to return its result, which the
// original code discarded; on the original it fails to compile for that reason.)
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyforge/services/python_bridge.dart';
import 'package:pyforge/state/run_model.dart';

Future<void> emit(Map<String, dynamic> event) async {
  await TestDefaultBinaryMessenger(event);
}

// ignore: non_constant_identifier_names
Future<void> TestDefaultBinaryMessenger(Map<String, dynamic> event) async {
  final ByteData data = const StandardMethodCodec()
      .encodeMethodCall(MethodCall('onEvent', jsonEncode(event)));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('pyforge/events', data, (_) {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final List<MethodCall> calls = <MethodCall>[];
  Object? Function(MethodCall)? bridgeReply;

  setUp(() {
    calls.clear();
    bridgeReply = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('pyforge/bridge'),
            (MethodCall call) async {
      calls.add(call);
      if (call.method == 'ping') return 'pong';
      return bridgeReply?.call(call);
    });
    PythonBridge.instance.init();
  });

  test('blank lines printed by print() are kept in the terminal', () async {
    final RunModel run = RunModel()..wire();
    run.runId = 'r1';
    await emit({'type': 'output', 'runId': 'r1', 'stream': 'stdout', 'text': 'a'});
    await emit({'type': 'output', 'runId': 'r1', 'stream': 'stdout', 'text': '\n'});
    await emit({'type': 'output', 'runId': 'r1', 'stream': 'stdout', 'text': '\n'});
    await emit({'type': 'output', 'runId': 'r1', 'stream': 'stdout', 'text': 'b'});
    await emit({'type': 'output', 'runId': 'r1', 'stream': 'stdout', 'text': '\n'});
    expect(run.lines.map((RunLine l) => l.text).toList(), <String>['a', '', 'b']);
  });

  test('a bridge failure does not leave the run state stuck', () async {
    final RunModel run = RunModel()..wire();
    bridgeReply = (MethodCall c) => throw PlatformException(code: 'boom');
    try {
      await run.run('/tmp/a.py', 'print(1)');
    } catch (_) {}
    expect(run.state, RunState.idle);
  });

  test('the bridge-level error string is shown to the user', () async {
    final RunModel run = RunModel()..wire();
    bridgeReply = (MethodCall c) =>
        jsonEncode({'ok': false, 'error': 'No module named pyforge'});
    await run.run('/tmp/a.py', 'print(1)');
    expect(run.lines.map((RunLine l) => l.text).join('\n'),
        contains('No module named pyforge'));
  });

  test('a crash inside the debugger is reported in the terminal', () async {
    final RunModel run = RunModel()..wire();
    final DebuggerModel debugger = DebuggerModel();
    bridgeReply = (MethodCall c) => jsonEncode({
          'ok': false,
          'error': {
            'type': 'ZeroDivisionError',
            'message': 'division by zero',
            'line': 1,
            'traceback': 'ZeroDivisionError: division by zero'
          }
        });
    run.beginDebugCapture('d1');
    // Mirrors EditorScreen._debug(): the result of start() must reach the terminal.
    final Map<String, dynamic> result =
        await debugger.start('/tmp/a.py', '1/0', runId: 'd1');
    run.endDebugCapture(result);
    expect(run.lines.map((RunLine l) => l.text).join('\n'),
        contains('ZeroDivisionError'));
  });

  test('debugger.start works without an explicit runId', () async {
    final DebuggerModel debugger = DebuggerModel();
    bridgeReply = (MethodCall c) => jsonEncode({'ok': true});
    await debugger.start('/tmp/a.py', 'x = 1');
    expect(calls.last.arguments['runId'], isNotNull);
  });
}
