import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/snippets_data.dart';
import '../state/nav_model.dart';
import '../state/workspace_model.dart';
import '../theme/app_theme.dart';
import 'widgets/app_widgets.dart';

enum _Category {
  basics('Basics', Icons.play_arrow_rounded),
  control('Flow', Icons.alt_route_rounded),
  data('Data', Icons.data_array_rounded),
  structure('Structure', Icons.account_tree_rounded),
  files('Files & errors', Icons.folder_open_rounded),
  libraries('Libraries', Icons.extension_rounded);

  const _Category(this.label, this.icon);
  final String label;
  final IconData icon;
}

_Category _categoryOf(CodeSnippet s) {
  final String hay = '${s.title} ${s.keywords.join(' ')}'.toLowerCase();
  bool has(List<String> words) => words.any(hay.contains);
  if (has(<String>['requests', 'numpy', 'http', 'url', 'math'])) {
    return _Category.libraries;
  }
  if (has(<String>['file', 'read', 'write', 'try', 'except', 'error'])) {
    return _Category.files;
  }
  if (has(<String>['class', 'object', 'def ', 'function', 'main', 'guard'])) {
    return _Category.structure;
  }
  if (has(<String>['list', 'dict', 'comprehension', 'map'])) {
    return _Category.data;
  }
  if (has(<String>['if', 'elif', 'for', 'while', 'loop', 'condition'])) {
    return _Category.control;
  }
  return _Category.basics;
}

Color _categoryColor(ColorScheme scheme, _Category c) {
  switch (c) {
    case _Category.basics:
      return scheme.primary;
    case _Category.control:
      return scheme.secondary;
    case _Category.data:
      return scheme.flame;
    case _Category.structure:
      return scheme.violet;
    case _Category.files:
      return scheme.error;
    case _Category.libraries:
      return scheme.success;
  }
}

/// Searchable boilerplate library — one tap inserts at the caret.
class SnippetsScreen extends StatefulWidget {
  const SnippetsScreen({super.key, this.embedded = false});

  /// Hosted inside the Tools tab: no AppBar of its own.
  final bool embedded;

  @override
  State<SnippetsScreen> createState() => _SnippetsScreenState();
}

class _SnippetsScreenState extends State<SnippetsScreen> {
  String _query = '';
  _Category? _filter;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final WorkspaceModel workspace = context.watch<WorkspaceModel>();
    final String q = _query.toLowerCase();
    final List<CodeSnippet> filtered = kSnippets.where((CodeSnippet s) {
      if (_filter != null && _categoryOf(s) != _filter) return false;
      if (q.isEmpty) return true;
      return s.title.toLowerCase().contains(q) ||
          s.keywords.any((String k) => k.contains(q));
    }).toList();

    final Widget body = Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search snippets',
            ),
            onChanged: (String v) => setState(() => _query = v),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('All'),
                  selected: _filter == null,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _filter = null),
                ),
              ),
              for (final _Category c in _Category.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(c.icon,
                        size: 18, color: _categoryColor(scheme, c)),
                    label: Text(c.label),
                    selected: _filter == c,
                    showCheckmark: false,
                    onSelected: (_) =>
                        setState(() => _filter = _filter == c ? null : c),
                  ),
                ),
            ],
          ),
        ),
        if (workspace.hasActive)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(
              children: <Widget>[
                Icon(Icons.input_rounded, size: 15, color: scheme.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Inserts into ${workspace.activePath!.split('/').last}',
                    style: TextStyle(fontSize: 12.5, color: scheme.muted),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: filtered.isEmpty
              ? const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No snippets found',
                  message: 'Try a different word, or clear the filter.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int index) =>
                      _SnippetCard(snippet: filtered[index]),
                ),
        ),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Snippets')),
      body: body,
    );
  }
}

class _SnippetCard extends StatelessWidget {
  const _SnippetCard({required this.snippet});

  final CodeSnippet snippet;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final WorkspaceModel workspace = context.watch<WorkspaceModel>();
    final _Category category = _categoryOf(snippet);
    final Color accent = _categoryColor(scheme, category);

    return AppCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: IconBadge(icon: category.icon, color: accent, size: 44),
          title: Text(snippet.title,
              style:
                  const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(snippet.keywords.join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: scheme.muted)),
          ),
          children: <Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: SelectableText(
                snippet.code.trimRight(),
                style: const TextStyle(
                    fontFamily: kMonoFont, fontSize: 13, height: 1.5),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: snippet.code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Snippet copied to clipboard.')),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('Insert'),
                    onPressed: workspace.hasActive
                        ? () {
                            HapticFeedback.selectionClick();
                            workspace.insertSnippet(snippet.code);
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(SnackBar(
                                content: const Text('Inserted at the cursor.'),
                                action: SnackBarAction(
                                  label: 'Open editor',
                                  onPressed: () =>
                                      context.read<NavModel>().go(AppTab.code),
                                ),
                              ));
                          }
                        : null,
                  ),
                ),
              ],
            ),
            if (!workspace.hasActive)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Open a file in the Code tab to insert snippets.',
                    style: TextStyle(fontSize: 12.5, color: scheme.muted)),
              ),
          ],
        ),
      ),
    );
  }
}
