import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import '../data/snippets_data.dart';
import '../state/workspace_model.dart';

/// Searchable boilerplate library — one tap inserts at the caret.
class SnippetsScreen extends StatefulWidget {
  const SnippetsScreen({super.key});

  @override
  State<SnippetsScreen> createState() => _SnippetsScreenState();
}

class _SnippetsScreenState extends State<SnippetsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final WorkspaceModel workspace = context.watch<WorkspaceModel>();
    final List<CodeSnippet> filtered = _query.isEmpty
        ? kSnippets
        : kSnippets
            .where((CodeSnippet s) =>
                s.title.toLowerCase().contains(_query.toLowerCase()) ||
                s.keywords.any((String k) => k.contains(_query.toLowerCase())))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Snippets'),
        actions: <Widget>[
          if (workspace.hasActive)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                avatar: Icon(Icons.code, size: 14, color: scheme.primary),
                label: Text(
                  'inserts into ${workspace.activePath!.split('/').last}',
                  style: const TextStyle(fontSize: 11),
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search snippets…',
                isDense: true,
              ),
              onChanged: (String v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: filtered.length,
              itemBuilder: (BuildContext context, int index) {
                final CodeSnippet snippet = filtered[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  child: Card(
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        dividerColor: Colors.transparent,
                      ),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        title: Text(snippet.title,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                        subtitle: Text(snippet.keywords.join(' · '),
                            style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurface
                                    .withValues(alpha: 0.5))),
                        children: <Widget>[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              snippet.code,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.copy, size: 16),
                                  label: const Text('Copy'),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(
                                        text: snippet.code));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Snippet copied to clipboard.')),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('Insert'),
                                  onPressed: workspace.hasActive
                                      ? () {
                                          HapticFeedback.selectionClick();
                                          workspace.insertSnippet(
                                              '${snippet.code}');
                                        }
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
