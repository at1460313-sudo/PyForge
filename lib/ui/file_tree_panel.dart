import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/workspace_model.dart';
import '../theme/app_theme.dart';
import 'widgets/app_widgets.dart';

/// Asks for a name and creates a file (or folder). Shared by the explorer,
/// the Home screen and the editor's empty state. Opens new files.
Future<String?> createNodeFlow(
  BuildContext context,
  WorkspaceModel workspace, {
  bool folder = false,
}) async {
  final String parent = folder || workspace.activePath == null
      ? workspace.root
      : workspace.activePath!.substring(
          0, workspace.activePath!.lastIndexOf(Platform.pathSeparator));
  final String? name = await showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => _NameDialog(
      title: folder ? 'New folder' : 'New Python file',
      hint: folder ? 'my_folder' : 'my_script.py',
    ),
  );
  if (name == null) return null;
  final String? created =
      await workspace.createNode(parent, name, asFolder: folder);
  if (created == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That name is invalid or already used.')),
      );
    }
    return null;
  }
  if (!folder) await workspace.openFile(created);
  return created;
}

/// File explorer. Used as a slide-in drawer on phones and as a side panel on
/// wide screens. Rows are 48 dp tall and every action is a visible button.
class FileTreePanel extends StatelessWidget {
  const FileTreePanel({super.key, required this.workspace, this.onOpened});

  final WorkspaceModel workspace;

  /// Called after a file is opened (the drawer uses it to close itself).
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: <Widget>[
                  IconBadge(
                      icon: Icons.folder_copy_rounded,
                      color: scheme.primary,
                      size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('My workspace',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text('Your Python files',
                            style:
                                TextStyle(fontSize: 12.5, color: scheme.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.note_add_rounded, size: 20),
                      label: const Text('New file'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 46)),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        createNodeFlow(context, workspace).then((String? p) {
                          if (p != null) onOpened?.call();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.create_new_folder_rounded),
                    tooltip: 'New folder',
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      createNodeFlow(context, workspace, folder: true);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 8),
            Expanded(
              child: workspace.tree.isEmpty
                  ? const EmptyState(
                      icon: Icons.insert_drive_file_outlined,
                      title: 'No files yet',
                      message: 'Tap New file to write your first script.',
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                      children: <Widget>[
                        for (final FileNode node in workspace.tree)
                          _FileNodeTile(
                              node: node, depth: 0, onOpened: onOpened),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileNodeTile extends StatefulWidget {
  const _FileNodeTile({
    required this.node,
    required this.depth,
    this.onOpened,
  });

  final FileNode node;
  final int depth;
  final VoidCallback? onOpened;

  @override
  State<_FileNodeTile> createState() => _FileNodeTileState();
}

class _FileNodeTileState extends State<_FileNodeTile> {
  final Map<FileNode, bool> _expanded = <FileNode, bool>{};

  Future<bool> _confirmDelete(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        icon: Icon(Icons.delete_outline_rounded,
            color: Theme.of(context).colorScheme.error, size: 32),
        title: Text('Delete ${widget.node.name}?'),
        content: const Text('This cannot be undone.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final WorkspaceModel workspace = context.watch<WorkspaceModel>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isActive = workspace.activePath == widget.node.path;
    final bool expanded = _expanded[widget.node] ?? false;
    final bool dirty = workspace.isDirty(widget.node.path);

    final Color iconColor = widget.node.isDir
        ? scheme.flame
        : (widget.node.isPython ? scheme.secondary : scheme.muted);

    return Column(
      children: <Widget>[
        Dismissible(
          key: ValueKey<String>(widget.node.path),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: scheme.error,
              borderRadius: BorderRadius.circular(14),
            ),
            child:
                const Icon(Icons.delete_outline_rounded, color: Colors.white),
          ),
          confirmDismiss: (DismissDirection direction) =>
              _confirmDelete(context),
          onDismissed: (DismissDirection direction) async {
            await workspace.deleteNode(widget.node.path);
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(
              color: isActive ? scheme.primary.withValues(alpha: 0.14) : null,
              borderRadius: BorderRadius.circular(14),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                HapticFeedback.selectionClick();
                if (widget.node.isDir) {
                  setState(() => _expanded[widget.node] = !expanded);
                } else {
                  workspace.openFile(widget.node.path).then((_) {
                    widget.onOpened?.call();
                  });
                }
              },
              child: Padding(
                padding:
                    EdgeInsets.only(left: 10.0 + widget.depth * 18.0, right: 2),
                child: SizedBox(
                  height: 48,
                  child: Row(
                    children: <Widget>[
                      Icon(
                        widget.node.isDir
                            ? (expanded
                                ? Icons.folder_open_rounded
                                : Icons.folder_rounded)
                            : (widget.node.isPython
                                ? Icons.code_rounded
                                : Icons.description_outlined),
                        size: 22,
                        color: iconColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.node.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                isActive ? FontWeight.w800 : FontWeight.w600,
                            color: isActive ? scheme.primary : null,
                          ),
                        ),
                      ),
                      if (dirty)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                              color: scheme.flame, shape: BoxShape.circle),
                        ),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert_rounded,
                            size: 20, color: scheme.muted),
                        tooltip: 'File actions',
                        onSelected: (String v) async {
                          if (v == 'rename') {
                            await _renameDialog(context, workspace);
                          } else if (v == 'delete') {
                            if (await _confirmDelete(context)) {
                              await workspace.deleteNode(widget.node.path);
                            }
                          }
                        },
                        itemBuilder: (BuildContext context) =>
                            <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'rename',
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.drive_file_rename_outline),
                              title: Text('Rename'),
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.delete_outline_rounded,
                                  color: scheme.error),
                              title: Text('Delete',
                                  style: TextStyle(color: scheme.error)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.node.isDir && expanded)
          for (final FileNode child in widget.node.children)
            _FileNodeTile(
                node: child,
                depth: widget.depth + 1,
                onOpened: widget.onOpened),
      ],
    );
  }

  Future<void> _renameDialog(
      BuildContext context, WorkspaceModel workspace) async {
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => _NameDialog(
        title: 'Rename ${widget.node.name}',
        hint: widget.node.name,
      ),
    );
    if (name == null) return;
    final String? renamed = await workspace.renameNode(widget.node.path, name);
    if (renamed == null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rename failed (name taken?).')),
      );
    }
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.hint,
  });

  final String title;
  final String hint;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.hint);
    // Select the name without the extension so typing replaces just that.
    final int dot = widget.hint.lastIndexOf('.');
    controller.selection = TextSelection(
        baseOffset: 0, extentOffset: dot > 0 ? dot : widget.hint.length);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (String v) => Navigator.of(context).pop(v),
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
