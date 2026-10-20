import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../editor/python_mode.dart';
import '../editor/prompts_builder.dart';
import '../services/python_bridge.dart';
import '../state/ai_model.dart';
import '../state/progress_model.dart';
import '../state/run_model.dart';
import '../state/settings_model.dart';
import '../state/workspace_model.dart';
import '../theme/app_theme.dart';
import '../theme/syntax_themes.dart';
import '../utils/ai_parsing.dart';
import 'ai_panel.dart';
import 'debugger_panel.dart';
import 'file_tree_panel.dart';
import 'keyboard_bar.dart';
import 'output_panel.dart';
import 'widgets/app_widgets.dart';

/// The IDE: file tree + editor + terminal + debugger + AI.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final FocusNode _editorFocus = FocusNode();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Timer? _syntaxDebounce;
  Map<String, dynamic>? _syntaxError;
  String? _syntaxErrorPath; // file the banner belongs to

  @override
  void initState() {
    super.initState();
    _editorFocus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _syntaxDebounce?.cancel();
    _editorFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  Future<void> _confirmCloseTab(WorkspaceModel workspace, String path) async {
    if (!workspace.isDirty(path)) {
      workspace.closeTab(path);
      return;
    }
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Close ${path.split('/').last}?'),
        content: const Text('This file has unsaved changes.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard & close'),
          ),
        ],
      ),
    );
    if (discard == true) workspace.closeTab(path);
  }

  Future<void> _save({bool recordLines = false}) async {
    final WorkspaceModel workspace = context.read<WorkspaceModel>();
    final String? path = workspace.activePath;
    final OpenBuffer? buffer = path == null ? null : workspace.buffers[path];
    if (path == null || buffer == null) return;
    if (recordLines && buffer.isDirty) {
      // O(n+m) memory: never build the full diff just to count changes.
      final int changed =
          countChangedLines(buffer.savedText, buffer.controller.text);
      if (changed > 0) {
        unawaited(context.read<ProgressModel>().recordLinesWritten(changed));
      }
    }
    await workspace.saveActive();
    HapticFeedback.selectionClick();
  }

  Future<void> _run() async {
    final WorkspaceModel workspace = context.read<WorkspaceModel>();
    final RunModel run = context.read<RunModel>();
    if (!workspace.hasActive) return;
    if (run.state != RunState.idle) return; // never overlap sessions
    HapticFeedback.mediumImpact();
    // Dismiss the soft keyboard so the output is visible.
    FocusManager.instance.primaryFocus?.unfocus();
    await _save(recordLines: true);
    // Save every other open file too: helper modules imported by this script
    // are read from disk, so unsaved edits in other tabs would be ignored.
    await workspace.saveAll();
    unawaited(_recordProgress());
    await run.run(workspace.activePath!, workspace.activeText);
    if (run.hasError && mounted) {
      HapticFeedback.heavyImpact();
    }
  }

  Future<void> _recordProgress() async {
    final ProgressModel progress = context.read<ProgressModel>();
    await progress.recordRun();
    await progress.recordActivity();
  }

  Future<void> _debug() async {
    final WorkspaceModel workspace = context.read<WorkspaceModel>();
    final RunModel run = context.read<RunModel>();
    final DebuggerModel debugger = context.read<DebuggerModel>();
    if (!workspace.hasActive) return;
    if (run.state != RunState.idle || debugger.active) return; // no overlap
    HapticFeedback.mediumImpact();
    await _save();
    await workspace.saveAll();
    final String debugId = 'debug-${DateTime.now().millisecondsSinceEpoch}';
    run.beginDebugCapture(debugId);
    final Map<String, dynamic> result = await debugger
        .start(workspace.activePath!, workspace.activeText, runId: debugId);
    run.endDebugCapture(result);
  }

  void _toggleBreakpoint() {
    final WorkspaceModel workspace = context.read<WorkspaceModel>();
    final DebuggerModel debugger = context.read<DebuggerModel>();
    final CodeLineEditingController? controller =
        workspace.controllerFor(workspace.activePath);
    if (controller == null) return;
    final int line = controller.selection.extentIndex + 1;
    debugger.toggleBreakpoint(workspace.activePath!, line);
    HapticFeedback.selectionClick();
  }

  void _openAiPanel() {
    final AiModel ai = context.read<AiModel>();
    final SettingsModel settings = context.read<SettingsModel>();
    final WorkspaceModel workspace = context.read<WorkspaceModel>();
    showAiPanel(context, ai: ai, settings: settings, workspace: workspace);
  }

  void _explainError() {
    final AiModel ai = context.read<AiModel>();
    final SettingsModel settings = context.read<SettingsModel>();
    final RunModel run = context.read<RunModel>();
    final WorkspaceModel workspace = context.read<WorkspaceModel>();
    final Map<String, dynamic>? error = run.lastError;
    if (error == null) return;
    ai.explainTraceback(error, workspace.activeText, settings);
    _openAiPanel();
  }

  void _fixError() {
    final AiModel ai = context.read<AiModel>();
    final SettingsModel settings = context.read<SettingsModel>();
    final RunModel run = context.read<RunModel>();
    final WorkspaceModel workspace = context.read<WorkspaceModel>();
    ai.fixCode(workspace.activeText, run.lastError, settings,
        path: workspace.activePath);
    _openAiPanel();
  }

  /// "Fix it" on the red Error Lens banner: send the syntax error itself,
  /// not whatever runtime error (if any) the last run happened to produce.
  void _fixSyntaxError() {
    final AiModel ai = context.read<AiModel>();
    final SettingsModel settings = context.read<SettingsModel>();
    final WorkspaceModel workspace = context.read<WorkspaceModel>();
    final Map<String, dynamic>? e = _syntaxError;
    ai.fixCode(
      workspace.activeText,
      e == null
          ? null
          : <String, dynamic>{
              'type': 'SyntaxError',
              'message': e['message'],
              'line': e['line'],
              'traceback': '${e['text'] ?? ''}',
            },
      settings,
      path: workspace.activePath,
    );
    _openAiPanel();
  }

  void _onCodeChanged(WorkspaceModel workspace) {
    setState(() {}); // tabs / dirty dots
    _syntaxDebounce?.cancel();
    _syntaxDebounce = Timer(const Duration(milliseconds: 600), () {
      final String? path = workspace.activePath;
      final String source = workspace.activeText;
      PythonBridge.instance.checkSyntax(source).then(
        (Map<String, dynamic> result) {
          // Ignore answers for a file the user has already switched away from.
          if (!mounted || workspace.activePath != path) return;
          setState(() {
            _syntaxError = result['ok'] == true ? null : result;
            _syntaxErrorPath = path;
          });
        },
        onError: (Object _) {}, // Error Lens is best-effort; never crash on it
      );
    });
  }

  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final WorkspaceModel workspace = context.watch<WorkspaceModel>();
    final SettingsModel settings = context.watch<SettingsModel>();
    final RunModel run = context.watch<RunModel>();
    final DebuggerModel debugger = context.watch<DebuggerModel>();
    // Subscribe: this screen must rebuild when AI state changes, even
    // though it no longer reads the model directly.
    context.watch<AiModel>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final SyntaxThemeDef syntax = SyntaxThemes.byId(settings.syntaxThemeId);

    final CodeLineEditingController? controller =
        workspace.controllerFor(workspace.activePath);
    final bool focusMode = workspace.focusMode;

    // Phones: the file tree is a slide-in drawer (a permanent 210 dp panel
    // would leave ~150 dp for code). Tablets / landscape: side panel.
    final bool wide = MediaQuery.of(context).size.width >= 700;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: syntax.background,
      drawer: (wide || focusMode)
          ? null
          : Drawer(
              width: 316,
              child: FileTreePanel(
                workspace: workspace,
                onOpened: () => _scaffoldKey.currentState?.closeDrawer(),
              ),
            ),
      drawerEnableOpenDragGesture: false, // would fight horizontal code scroll
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            if (!focusMode) _buildToolbar(context, workspace, debugger),
            if (!focusMode &&
                _syntaxError != null &&
                _syntaxErrorPath == workspace.activePath)
              _ErrorLensBanner(error: _syntaxError!, onFix: _fixSyntaxError),
            Expanded(
              child: Row(
                children: <Widget>[
                  if (wide)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      width: workspace.treeExpanded ? 260 : 0,
                      child: workspace.treeExpanded
                          ? FileTreePanel(workspace: workspace)
                          : null,
                    ),
                  Expanded(
                    child: Stack(
                      children: <Widget>[
                        if (controller != null)
                          CodeAutocomplete(
                            viewBuilder: (BuildContext viewContext,
                                ValueNotifier<CodeAutocompleteEditingValue>
                                    notifier,
                                ValueChanged<CodeAutocompleteResult>
                                    onSelected) {
                              return PythonAutocompleteView(
                                notifier: notifier,
                                onSelected: onSelected,
                              );
                            },
                            promptsBuilder: PythonPromptsBuilder(
                              documentProvider: () => controller.text,
                            ),
                            child: CodeEditor(
                              controller: controller,
                              focusNode: _editorFocus,
                              wordWrap: false,
                              onChanged: (dynamic value) =>
                                  _onCodeChanged(workspace),
                              style: CodeEditorStyle(
                                fontSize: settings.fontSize,
                                fontFamily: kMonoFont,
                                fontHeight: 1.5,
                                backgroundColor: syntax.background,
                                textColor: syntax.text,
                                codeTheme: CodeHighlightTheme(
                                  languages: <String, CodeHighlightThemeMode>{
                                    'python': CodeHighlightThemeMode(
                                        mode: pyforgePythonMode),
                                  },
                                  theme: syntax.map,
                                ),
                              ),
                              indicatorBuilder: (BuildContext indicatorContext,
                                  editingController,
                                  chunkController,
                                  notifier) {
                                return DefaultCodeLineNumber(
                                  controller: editingController,
                                  notifier: notifier,
                                );
                              },
                            ),
                          )
                        else
                          _buildEmptyState(context, scheme, workspace),
                        // Focus-mode exit.
                        if (focusMode)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton(
                              tooltip: 'Exit focus mode',
                              style: IconButton.styleFrom(
                                backgroundColor: syntax.background,
                              ),
                              icon: Icon(Icons.fullscreen_exit,
                                  color: syntax.text.withValues(alpha: 0.8),
                                  size: 20),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                workspace.setFocusMode(false);
                              },
                            ),
                          ),
                        // Run button.
                        if (!focusMode)
                          Positioned(
                            right: 16,
                            bottom: 16,
                            child: _RunButton(
                              running: run.state == RunState.running,
                              onRun: _run,
                              onDebug: _debug,
                            ),
                          ),
                        // Debugger overlay.
                        if (debugger.active)
                          DebuggerPanel(
                            debugger: debugger,
                            onClose: () => debugger.stop(),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Keyboard bar (above the system keyboard when editing).
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.bottomCenter,
              child: _editorFocus.hasFocus
                  ? KeyboardBar(controller: controller)
                  : const SizedBox(width: double.infinity),
            ),
            // Terminal / output.
            if (!focusMode &&
                (MediaQuery.of(context).viewInsets.bottom == 0 ||
                    run.state != RunState.idle))
              OutputPanel(
                run: run,
                onExplainError: _explainError,
                onFixError: _fixError,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
      BuildContext context, ColorScheme scheme, WorkspaceModel workspace) {
    final SyntaxThemeDef syntax =
        SyntaxThemes.byId(context.watch<SettingsModel>().syntaxThemeId);
    return Container(
      color: syntax.background,
      width: double.infinity,
      child: EmptyState(
        icon: Icons.code_rounded,
        title: 'No file open',
        message: 'Create a new Python file, or open one from your workspace.',
        actions: <Widget>[
          FilledButton.icon(
            icon: const Icon(Icons.note_add_rounded),
            label: const Text('New file'),
            onPressed: () => createNodeFlow(context, workspace),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('Open files'),
            onPressed: () {
              if (MediaQuery.of(context).size.width >= 700) {
                workspace.toggleTree();
              } else {
                _scaffoldKey.currentState?.openDrawer();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(
      BuildContext context, WorkspaceModel workspace, DebuggerModel debugger) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final SettingsModel settings = context.watch<SettingsModel>();
    final bool wide = MediaQuery.of(context).size.width >= 700;
    final String? active = workspace.activePath;
    final String title =
        active == null ? 'Code' : active.split('/').last.split(r'\\').last;
    final bool dirty = active != null && workspace.isDirty(active);
    final bool hasBreakpoints =
        (debugger.breakpoints[active] ?? const <int>{}).isNotEmpty;

    return Material(
      color: scheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 56,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Files',
                    icon: Icon(wide && workspace.treeExpanded
                        ? Icons.menu_open_rounded
                        : Icons.folder_open_rounded),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      if (wide) {
                        workspace.toggleTree();
                      } else {
                        _scaffoldKey.currentState?.openDrawer();
                      }
                    },
                  ),
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (dirty) ...<Widget>[
                          const SizedBox(width: 8),
                          Pill(label: 'unsaved', color: scheme.flame),
                        ],
                      ],
                    ),
                  ),
                  if (dirty)
                    IconButton(
                      tooltip: 'Save',
                      icon: Icon(Icons.save_rounded, color: scheme.primary),
                      onPressed: () => _save(recordLines: true),
                    ),
                  IconButton(
                    tooltip: 'AI Co-Pilot',
                    icon: Icon(Icons.auto_awesome_rounded,
                        color:
                            settings.hasApiKey ? scheme.primary : scheme.muted),
                    onPressed: _openAiPanel,
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    icon: Badge(
                      isLabelVisible: hasBreakpoints,
                      smallSize: 8,
                      child: const Icon(Icons.more_vert_rounded),
                    ),
                    onSelected: (String v) {
                      switch (v) {
                        case 'save':
                          _save(recordLines: true);
                        case 'breakpoint':
                          _toggleBreakpoint();
                        case 'debug':
                          _debug();
                        case 'focus':
                          HapticFeedback.selectionClick();
                          workspace.setFocusMode(true);
                        case 'close':
                          if (active != null) {
                            _confirmCloseTab(workspace, active);
                          }
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                      _menuItem('save', Icons.save_outlined, 'Save'),
                      _menuItem('breakpoint', Icons.bookmark_add_outlined,
                          'Toggle breakpoint at cursor'),
                      _menuItem('debug', Icons.bug_report_outlined,
                          'Debug (step through)'),
                      _menuItem(
                          'focus', Icons.fullscreen_rounded, 'Focus mode'),
                      const PopupMenuDivider(),
                      _menuItem(
                          'close', Icons.close_rounded, 'Close this file'),
                    ],
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            if (workspace.openTabs.length > 1)
              SizedBox(
                height: 48,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  itemCount: workspace.openTabs.length,
                  itemBuilder: (BuildContext tabContext, int index) {
                    final String path = workspace.openTabs[index];
                    final bool isActive = path == active;
                    final String name = path.split('/').last.split(r'\\').last;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Material(
                        color: isActive
                            ? scheme.primary.withValues(alpha: 0.16)
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => workspace.openFile(path),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Row(
                              children: <Widget>[
                                Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: isActive
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: isActive
                                        ? scheme.primary
                                        : scheme.muted,
                                  ),
                                ),
                                if (workspace.isDirty(path))
                                  Container(
                                    width: 7,
                                    height: 7,
                                    margin: const EdgeInsets.only(left: 6),
                                    decoration: BoxDecoration(
                                        color: scheme.flame,
                                        shape: BoxShape.circle),
                                  ),
                                InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () =>
                                      _confirmCloseTab(workspace, path),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Icon(Icons.close_rounded,
                                        size: 16, color: scheme.muted),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
  return PopupMenuItem<String>(
    value: value,
    child: Row(
      children: <Widget>[
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
    ),
  );
}

/// Floating run / debug buttons. "Run" carries a label so it is obvious.
class _RunButton extends StatelessWidget {
  const _RunButton({
    required this.running,
    required this.onRun,
    required this.onDebug,
  });

  final bool running;
  final VoidCallback onRun;
  final VoidCallback onDebug;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        FloatingActionButton.small(
          heroTag: 'debug',
          tooltip: 'Debug',
          backgroundColor: scheme.surfaceContainerHighest,
          foregroundColor: scheme.secondary,
          elevation: 2,
          onPressed: running ? null : onDebug,
          child: const Icon(Icons.bug_report_outlined, size: 22),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'run',
          tooltip: 'Run',
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          onPressed: running ? null : onRun,
          icon: running
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: scheme.onPrimary),
                )
              : const Icon(Icons.play_arrow_rounded, size: 28),
          label: Text(running ? 'Running' : 'Run'),
        ),
      ],
    );
  }
}

/// Inline error banner ("Error Lens"): shows the current syntax error with
/// a one-tap AI fix.
class _ErrorLensBanner extends StatelessWidget {
  const _ErrorLensBanner({required this.error, required this.onFix});

  final Map<String, dynamic> error;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int line = (error['line'] as num?)?.toInt() ?? 1;
    final String message = error['message'] as String? ?? 'Syntax error';
    return Material(
      color: scheme.error.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline_rounded, size: 20, color: scheme.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Line $line: $message',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.error,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              onPressed: onFix,
              icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: const Text('Fix it'),
            ),
          ],
        ),
      ),
    );
  }
}
