import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pyforge/main.dart';
import 'package:pyforge/services/python_bridge.dart';
import 'package:pyforge/state/ai_model.dart';
import 'package:pyforge/state/progress_model.dart';
import 'package:pyforge/state/run_model.dart';
import 'package:pyforge/state/settings_model.dart';
import 'package:pyforge/state/workspace_model.dart';
import 'package:pyforge/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phone-size UI regression tests for the 5-tab shell, the drawer-based file
/// tree, and layout robustness (no overflow at 360 dp, even with 1.4x text).
double _lin(double v) =>
    v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

double _contrast(Color a, Color b) {
  final double la = _luminance(a), lb = _luminance(b);
  final double hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

/// The default test font (Ahem) has square, very wide glyphs and would report
/// overflows no phone would ever see, so layout tests load real Roboto.
String? _robotoDir() {
  final String? root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return null;
  final String dir = '$root/bin/cache/artifacts/material_fonts';
  return File('$dir/Roboto-Regular.ttf').existsSync() ? dir : null;
}

Future<void> _loadRoboto(String dir) async {
  final FontLoader loader = FontLoader('Roboto');
  for (final String f in <String>[
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]) {
    loader.addFont(
        File('$dir/$f').readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await loader.load();
  final FontLoader icons = FontLoader('MaterialIcons')
    ..addFont(File('$dir/MaterialIcons-Regular.otf')
        .readAsBytes()
        .then((b) => ByteData.view(b.buffer)));
  await icons.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('theme contrast', () {
    for (final MapEntry<String, ThemeData> e in <String, ThemeData>{
      'dark': AppThemes.dark(),
      'oled': AppThemes.oled(),
      'light': AppThemes.light(),
    }.entries) {
      test('${e.key}: secondary text is readable (>= 4.5:1)', () {
        final ColorScheme s = e.value.colorScheme;
        final Color bg = e.value.scaffoldBackgroundColor;
        expect(_contrast(_over(s.muted, bg), bg), greaterThanOrEqualTo(4.5));
        expect(_contrast(_over(s.muted, s.surface), s.surface),
            greaterThanOrEqualTo(4.5));
        expect(_contrast(s.primary, s.surface), greaterThanOrEqualTo(3.0));
      });
    }
  });

  group('shell', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('pyforge_ui');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        ..setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (MethodCall c) async => tmp.path)
        ..setMockMethodCallHandler(const MethodChannel('pyforge/bridge'),
            (MethodCall c) async {
          if (c.method == 'listPackages') {
            return '{"ok":true,"packages":[{"name":"numpy","version":"1.26.4"}]}';
          }
          return '{"ok":true}';
        })
        ..setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (MethodCall c) async => null);
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    Future<void> pumpApp(WidgetTester tester, {double textScale = 1.0}) async {
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = const Size(1080, 1920); // 360 x 640 dp
      addTearDown(tester.view.reset);
      PythonBridge.instance.init();
      final SettingsModel settings = SettingsModel();
      final WorkspaceModel workspace = WorkspaceModel();
      final RunModel run = RunModel()..wire();
      final DebuggerModel debugger = DebuggerModel()..wire();
      final ProgressModel progress = ProgressModel();
      final AiModel ai = AiModel();
      await tester.runAsync(() async {
        await settings.load();
        await workspace.init();
        await progress.load();
      });
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 640),
          devicePixelRatio: 3.0,
          textScaler: TextScaler.linear(textScale),
        ),
        child: MultiProvider(
          providers: <ChangeNotifierProvider<ChangeNotifier>>[
            ChangeNotifierProvider<SettingsModel>.value(value: settings),
            ChangeNotifierProvider<WorkspaceModel>.value(value: workspace),
            ChangeNotifierProvider<RunModel>.value(value: run),
            ChangeNotifierProvider<DebuggerModel>.value(value: debugger),
            ChangeNotifierProvider<ProgressModel>.value(value: progress),
            ChangeNotifierProvider<AiModel>.value(value: ai),
          ],
          child: const PyForgeApp(),
        ),
      ));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('bottom bar has five labelled tabs and starts on Home',
        (WidgetTester tester) async {
      await pumpApp(tester);
      for (final String label in <String>[
        'Home',
        'Code',
        'Learn',
        'Tools',
        'Profile'
      ]) {
        expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
            findsOneWidget,
            reason: label);
      }
      expect(find.text('Quick actions'), findsOneWidget);
    });

    testWidgets('each tab opens its screen', (WidgetTester tester) async {
      await pumpApp(tester);
      Future<void> tap(String label) async {
        await tester.tap(find.descendant(
            of: find.byType(NavigationBar), matching: find.text(label)));
        await tester.pump(const Duration(milliseconds: 500));
      }

      await tap('Learn');
      expect(find.text('Learn Python'), findsOneWidget);
      await tap('Tools');
      expect(find.text('Snippets'), findsWidgets);
      expect(find.text('Packages'), findsWidgets);
      await tap('Profile');
      expect(find.text('Badges'), findsOneWidget);
      await tap('Home');
      expect(find.text('Quick actions'), findsOneWidget);
    });

    testWidgets('Profile opens Settings through the gear',
        (WidgetTester tester) async {
      await pumpApp(tester);
      await tester.tap(find.descendant(
          of: find.byType(NavigationBar), matching: find.text('Profile')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byTooltip('Settings'));
      await tester.pump(); // start the route transition
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Appearance'), findsOneWidget);
    });

    testWidgets('file tree is a drawer on phones', (WidgetTester tester) async {
      await pumpApp(tester);
      await tester.tap(find.descendant(
          of: find.byType(NavigationBar), matching: find.text('Code')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('My workspace'), findsNothing);
      await tester.tap(find.byTooltip('Files'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('My workspace'), findsOneWidget);
      expect(find.text('New file'), findsOneWidget);
    });

    testWidgets('no layout overflow at 360 dp with 1.4x text',
        skip: _robotoDir() == null,
        (WidgetTester tester) async {
      await tester.runAsync(() => _loadRoboto(_robotoDir()!));
      await pumpApp(tester, textScale: 1.8);
      for (final String label in <String>[
        'Learn',
        'Tools',
        'Profile',
        'Code',
        'Home'
      ]) {
        await tester.tap(find.descendant(
            of: find.byType(NavigationBar), matching: find.text(label)));
        await tester.pump(const Duration(milliseconds: 600));
        final Object? error = tester.takeException();
        final String detail = error is FlutterError
            ? error.diagnostics.map((d) => d.toString()).join(' | ')
            : '$error';
        expect(error, isNull, reason: 'tab $label: $detail');
      }
    });
  });
}
