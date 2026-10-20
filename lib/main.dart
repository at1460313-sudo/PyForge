import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/python_bridge.dart';
import 'state/ai_model.dart';
import 'state/progress_model.dart';
import 'state/run_model.dart';
import 'state/settings_model.dart';
import 'state/workspace_model.dart';
import 'theme/app_theme.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  await PythonBridge.instance.init();

  final SettingsModel settings = SettingsModel();
  final WorkspaceModel workspace = WorkspaceModel();
  final RunModel run = RunModel();
  final DebuggerModel debugger = DebuggerModel();
  final ProgressModel progress = ProgressModel();
  final AiModel ai = AiModel();

  run.wire();
  debugger.wire();
  await settings.load();
  await workspace.init();
  await progress.load();

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsModel>.value(value: settings),
      ChangeNotifierProvider<WorkspaceModel>.value(value: workspace),
      ChangeNotifierProvider<RunModel>.value(value: run),
      ChangeNotifierProvider<DebuggerModel>.value(value: debugger),
      ChangeNotifierProvider<ProgressModel>.value(value: progress),
      ChangeNotifierProvider<AiModel>.value(value: ai),
    ],
    child: const PyForgeApp(),
  ));
}

class PyForgeApp extends StatelessWidget {
  const PyForgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsModel settings = context.watch<SettingsModel>();
    final ThemeData theme = switch (settings.themeMode) {
      AppThemeMode.dark => AppThemes.dark(),
      AppThemeMode.light => AppThemes.light(),
      AppThemeMode.oled => AppThemes.oled(),
    };
    return MaterialApp(
      title: 'PyForge',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: const Shell(),
    );
  }
}
