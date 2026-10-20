import 'package:flutter/material.dart';

import 'package_manager_screen.dart';
import 'snippets_screen.dart';

/// Snippets and Packages share one tab so the bottom bar stays at five
/// destinations (Material guidance is 3-5).
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('Tools')),
        body: const Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _ToolsTabs(),
            ),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  SnippetsScreen(embedded: true),
                  PackageManagerScreen(embedded: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolsTabs extends StatelessWidget {
  const _ToolsTabs();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: const TabBar(
        tabs: <Widget>[
          Tab(
            height: 48,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.bolt_rounded, size: 20),
                SizedBox(width: 6),
                Flexible(child: Text('Snippets', overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          Tab(
            height: 48,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.extension_rounded, size: 20),
                SizedBox(width: 6),
                Flexible(child: Text('Packages', overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
