import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import '../state/workspace_model.dart';

/// Collapsible file explorer with create / rename / delete and
/// swipe-to-delete gestures.
class FileTreePanel extends StatelessWidget {
  const FileTreePanel({super.key, required this.workspace});

  final WorkspaceModel workspace;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'FILES',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                _IconAction(
                  icon: Icons.create_new_folder_outlined,
                  tooltip: 'New folder',
                  onTap: () => _createNode(context, root: true),
                ),
                _IconAction(
                  icon: Icons.add_circle_outline,
                  tooltip: 'New file',
                  onTap: () => _createNode(context, root: false),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: <Widget>[
                for (final FileNode node in workspace.tree)
                  _FileNodeTile(node: node, depth: 0),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createNode(BuildContext context, {required bool root}) async {
    final String parent = root
        ? workspace.root
        : (workspace.activePath == null
            ? workspace.root
            : workspace.activePath!.substring(
                0, workspace.activePath!.lastIndexOf(Platform.pathSeparator)));
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => _NameDialog(
        title: root ? 'New folder' : 'New Python file',
        hint: root ? 'my_folder' : 'my_script.py',
      ),
    );
    if (name == null) return;
    final String? created =
        await workspace.createNode(parent, name, asFolder: root);
    if (created == null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That name is invalid or already used.')),
      );
    } else if (!root && created != null) {
      await workspace.openFile(created);
    }
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: () {
        HapticFeedback.selectionClick();
        onTap();
      },
    );
  }
}

class _FileNodeTile extends StatefulWidget {
  const _FileNodeTile({required this.node, required this.depth});

  final FileNode node;
  final int depth;

  @override
  State<_FileNodeTile> createState() => _FileNodeTileState();
}

class _FileNodeTileState extends State<_FileNodeTile> {
  final Map<FileNode, bool> _expanded = <FileNode, bool>{};

  @override
  Widget build(BuildContext context) {
    final WorkspaceModel workspace = context.watch<WorkspaceModel>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isActive = workspace.activePath == widget.node.path;
    final bool expanded = _expanded[widget.node] ?? false;

    return Column(
      children: <Widget>[
        Dismissible(
          key: ValueKey<String>(widget.node.path),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: scheme.error,
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          confirmDismiss: (DismissDirection direction) async {
            HapticFeedback.mediumImpact();
            final bool? confirmed = await showDialog<bool>(
              context: context,
              builder: (BuildContext dialogContext) => AlertDialog(
                title: Text('Delete ${widget.node.name}?'),
                content: const Text('This cannot be undone.'),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            return confirmed ?? false;
          },
          onDismissed: (DismissDirection direction) async {
            await workspace.deleteNode(widget.node.path);
          },
          child: ListTile(
            dense: true,
            selected: isActive,
            selectedTileColor: scheme.primary.withValues(alpha: 0.12),
            contentPadding:
                EdgeInsets.only(left: 8.0 + widget.depth * 14.0, right: 4),
            leading: Icon(
              widget.node.isDir
                  ? (expanded
                      ? Icons.folder_open
                      : Icons.folder_outlined)
                  : (widget.node.isPython
                      ? Icons.code
                      : Icons.description_outlined),
              size: 18,
              color: isActive
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.7),
            ),
            title: Text(
              workspace.isDirty(widget.node.path)
                  ? '${widget.node.name} •'
                  : widget.node.name,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            onTap: () {
              HapticFeedback.selectionClick();
              if (widget.node.isDir) {
                setState(() {
                  _expanded[widget.node] = !expanded;
                });
              } else {
                workspace.openFile(widget.node.path);
              }
            },
            onLongPress: () => _renameDialog(context, workspace),
          ),
        ),
        if (widget.node.isDir && expanded)
          for (final FileNode child in widget.node.children)
            _FileNodeTile(node: child, depth: widget.depth + 1),
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
