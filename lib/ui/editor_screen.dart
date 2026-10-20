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
import '../theme/syntax_themes.dart';
import '../utils/ai_parsing.dart';
import 'ai_panel.dart';
import 'debugger_panel.dart';
import 'file_tree_panel.dart';
import 'keyboard_bar.dart';
import 'output_panel.dart';

/// The IDE: file tree + editor + terminal + debugger + AI.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final FocusNode _editorFocus = FocusNode();
  Timer? _syntaxDebounce;
  Map<String, dynamic>? _syntaxError;

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

  Future<void> _confirmCloseTab(
      WorkspaceModel workspace, String path) async {
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
    final OpenBuffer? buffer =
        path == null ? null : workspace.buffers[path];
    if (path == null || buffer == null) return;
    if (recordLines && buffer.isDirty) {
      final int changed = diffLines(buffer.savedText, buffer.controller.text)
          .where((DiffLine d) => d.action != DiffAction.equal)
          .length;
      if (changed > 0) {
        unawaited(
            context.read<ProgressModel>().recordLinesWritten(changed));
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
    await _save(recordLines: true);
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
    HapticFeedback.mediumImpact();
    await _save();
    final String debugId =
        'debug-${DateTime.now().millisecondsSinceEpoch}';
    run.beginDebugCapture(debugId);
    await debugger.start(workspace.activePath!, workspace.activeText,
        runId: debugId);
    run.endDebugCapture();
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

  void _onCodeChanged(WorkspaceModel workspace) {
    setState(() {}); // tabs / dirty dots
    _syntaxDebounce?.cancel();
    _syntaxDebounce = Timer(const Duration(milliseconds: 600), () {
      final String source = workspace.activeText;
      PythonBridge.instance
          .checkSyntax(source)
          .then((Map<String, dynamic> result) {
        if (!mounted) return;
        setState(() {
          _syntaxError = result['ok'] == true ? null : result;
        });
      });
    });
  }

  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final WorkspaceModel workspace = context.watch<WorkspaceModel>();
    final SettingsModel settings = context.watch<SettingsModel>();
    final RunModel run = context.watch<RunModel>();
    final DebuggerModel debugger = context.watch<DebuggerModel>();
    final AiModel ai = context.watch<AiModel>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final SyntaxThemeDef syntax = SyntaxThemes.byId(settings.syntaxThemeId);

    final CodeLineEditingController? controller =
        workspace.controllerFor(workspace.activePath);
    final bool focusMode = workspace.focusMode;

    return Scaffold(
      backgroundColor: syntax.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            if (!focusMode) _buildToolbar(context, workspace, debugger),
            if (!focusMode && _syntaxError != null)
              _ErrorLensBanner(error: _syntaxError!, onFix: _fixError),
            Expanded(
              child: Row(
                children: <Widget>[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    width: workspace.treeExpanded ? 210 : 0,
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
                          _buildEmptyState(context, scheme),
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
                            right: 18,
                            bottom: 18,
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
            if (!focusMode)
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

  Widget _buildEmptyState(BuildContext context, ColorScheme scheme) {
    final SyntaxThemeDef syntax =
        SyntaxThemes.byId(context.watch<SettingsModel>().syntaxThemeId);
    return Container(
      color: syntax.background,
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.code_rounded,
              size: 56, color: syntax.text.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(
            'Open a file or create a new one',
            style: TextStyle(
                color: syntax.text.withValues(alpha: 0.6), fontSize: 14),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('New file'),
            onPressed: () => context.read<WorkspaceModel>().toggleTree(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(
      BuildContext context, WorkspaceModel workspace, DebuggerModel debugger) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final SettingsModel settings = context.watch<SettingsModel>();
    return Material(
      color: scheme.surface,
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 52,
            child: Row(
              children: <Widget>[
                IconButton(
                  tooltip: 'Toggle file tree',
                  icon: Icon(
                    workspace.treeExpanded
                        ? Icons.menu_open
                        : Icons.menu,
                    size: 20,
                  ),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    workspace.toggleTree();
                  },
                ),
                Expanded(
                  child: workspace.openTabs.isEmpty
                      ? Text('PyForge',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface.withValues(alpha: 0.7)))
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: workspace.openTabs.length,
                          itemBuilder: (BuildContext tabContext, int index) {
                            final String path = workspace.openTabs[index];
                            final bool isActive = path == workspace.activePath;
                            final String name =
                                path.split('/').last.split(r'\').last;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InputChip(
                                label: Text(
                                  workspace.isDirty(path)
                                      ? '$name •'
                                      : name,
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: isActive
                                          ? FontWeight.w800
                                          : FontWeight.w500),
                                ),
                                selected: isActive,
                                onSelected: (_) => workspace.openFile(path),
                                onDeleted: () => _confirmCloseTab(workspace, path),
                                deleteIconColor:
                                    scheme.onSurface.withValues(alpha: 0.5),
                                visualDensity: VisualDensity.compact,
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Toggle breakpoint at cursor',
                  icon: Badge(
                    isLabelVisible:
                        (debugger.breakpoints[workspace.activePath] ?? const <int>{})
                            .isNotEmpty,
                    child: const Icon(Icons.bookmark_add_outlined, size: 20),
                  ),
                  onPressed: _toggleBreakpoint,
                ),
                IconButton(
                  tooltip: 'Save',
                  icon: const Icon(Icons.save_outlined, size: 20),
                  onPressed: () => _save(recordLines: true),
                ),
                IconButton(
                  tooltip: 'AI Co-Pilot',
                  icon: Icon(Icons.auto_awesome,
                      size: 20,
                      color: settings.hasApiKey
                          ? scheme.primary
                          : scheme.onSurface.withValues(alpha: 0.5)),
                  onPressed: _openAiPanel,
                ),
                IconButton(
                  tooltip: 'Focus mode',
                  icon: const Icon(Icons.fullscreen_outlined, size: 20),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    workspace.setFocusMode(true);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating run / debug button.
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
      children: <Widget>[
        FloatingActionButton.small(
          heroTag: 'debug',
          tooltip: 'Debug',
          backgroundColor: scheme.surfaceContainerHighest,
          foregroundColor: scheme.primary,
          onPressed: running ? null : onDebug,
          child: const Icon(Icons.bug_report_outlined, size: 18),
        ),
        const SizedBox(height: 10),
        FloatingActionButton(
          heroTag: 'run',
          tooltip: 'Run',
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          onPressed: running ? null : onRun,
          child: Icon(running ? Icons.hourglass_empty : Icons.play_arrow,
              size: 30),
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
      color: scheme.error.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline, size: 16, color: scheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Ln $line: $message',
                style: TextStyle(
                  color: scheme.error,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: scheme.error,
              ),
              onPressed: onFix,
              icon: const Icon(Icons.auto_fix_high, size: 14),
              label: const Text('Fix it', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
