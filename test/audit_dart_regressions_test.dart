// Copy to PyForge/test/audit_dart_regressions_test.dart and run `flutter test`.
// These assert desired behavior, so failures on the reviewed commit are expected.
// (The debugger test needs DebuggerModel.start to return its result, which the
// original code discarded; on the original it fails to compile for that reason.)
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyforge/services/python_bridge.dart';
import 'package:flutter/material.dart';
import 'package:pyforge/state/run_model.dart';
import 'package:pyforge/ui/output_panel.dart';
import 'package:pyforge/utils/ai_parsing.dart';

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

  test('countChangedLines matches the diff it replaces', () {
    const String a = 'one\ntwo\nthree\nfour';
    const String b = 'one\nTWO\nthree\nfive';
    final List<DiffLine> d = diffLines(a, b);
    final int changed =
        d.where((DiffLine x) => x.action != DiffAction.equal).length;
    expect(countChangedLines(a, b), changed);
    expect(countChangedLines(a, a), 0);
    expect(countChangedLines('', 'x\ny'), 3); // '' counts as one line
  });

  test('diffLines edits apply cleanly', () {
    const String a = 'keep\nold1\nold2\nkeep2';
    const String b = 'keep\nnew1\nkeep2\ntail';
    final List<DiffLine> d = diffLines(a, b);
    final String back =
        d.where((x) => x.action != DiffAction.insert).map((x) => x.text).join('\n');
    final String forth =
        d.where((x) => x.action != DiffAction.delete).map((x) => x.text).join('\n');
    expect(back, a);
    expect(forth, b);
  });

  test('input echo has no extra blank row', () async {
    final RunModel run = RunModel()..wire();
    run.runId = 'r1';
    await emit({'type': 'input_request', 'runId': 'r1', 'prompt': ''});
    expect(run.state, RunState.waitingInput);
    await run.submitInput('hello');
    expect(run.lines.last.text, 'hello'); // no trailing newline
    expect(run.lines.last.stream, 'stdout');
  });

  testWidgets('terminal does not yank the view while scrolled up',
      (WidgetTester tester) async {
    final RunModel run = RunModel()..wire();
    run.runId = 'r1';
    for (int i = 0; i < 80; i++) {
      await emit({
        'type': 'output',
        'runId': 'r1',
        'stream': 'stdout',
        'text': 'line $i\n',
      });
    }
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OutputPanel(
          run: run,
          onExplainError: () {},
          onFixError: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // Scrolling up to read must disable follow-the-output.
    await tester.drag(find.byType(ListView), const Offset(0, 120));
    await tester.pumpAndSettle();
    final double before = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(before, greaterThan(0.0)); // actually scrolled up
    // New output arrives: the view must stay where the user put it.
    for (int i = 100; i < 140; i++) {
      await emit({
        'type': 'output',
        'runId': 'r1',
        'stream': 'stdout',
        'text': 'line $i\n',
      });
    }
    await tester.pumpAndSettle();
    final double after = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(after, before);
  });

  test('debugger.start works without an explicit runId', () async {
    final DebuggerModel debugger = DebuggerModel();
    bridgeReply = (MethodCall c) => jsonEncode({'ok': true});
    await debugger.start('/tmp/a.py', 'x = 1');
    expect(calls.last.arguments['runId'], isNotNull);
  });
}
