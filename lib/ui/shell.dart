import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/workspace_model.dart';
import 'curriculum_screen.dart';
import 'editor_screen.dart';
import 'package_manager_screen.dart';
import 'progress_screen.dart';
import 'settings_screen.dart';
import 'snippets_screen.dart';

/// Responsive navigation shell: a rail on wide screens, a bar on phones.
/// Focus mode hides all chrome for distraction-free writing.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  static const List<Widget> _screens = <Widget>[
    EditorScreen(),
    CurriculumScreen(),
    SnippetsScreen(),
    PackageManagerScreen(),
    ProgressScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final WorkspaceModel workspace = context.watch<WorkspaceModel>();

    if (workspace.focusMode) {
      return const EditorScreen();
    }

    final bool isWide = MediaQuery.of(context).size.width > 900;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int count = _screens.length;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: <Widget>[
            NavigationRail(
              extended: true,
              minExtendedWidth: 190,
              selectedIndex: _index,
              onDestinationSelected: (int value) =>
                  setState(() => _index = value),
              destinations: <NavigationRailDestination>[
                const NavigationRailDestination(
                    icon: Icon(Icons.code), label: Text('Editor')),
                const NavigationRailDestination(
                    icon: Icon(Icons.school_outlined), label: Text('Learn')),
                const NavigationRailDestination(
                    icon: Icon(Icons.bolt_outlined), label: Text('Snippets')),
                const NavigationRailDestination(
                    icon: Icon(Icons.extension_outlined),
                    label: Text('Packages')),
                const NavigationRailDestination(
                    icon: Icon(Icons.insights_outlined),
                    label: Text('Progress')),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined,
                      color: _index == count - 1
                          ? scheme.primary
                          : scheme.onSurface.withValues(alpha: 0.6)),
                  label: const Text('Settings'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _screens[_index]),
          ],
        ),
      );
    }

    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int value) =>
            setState(() => _index = value),
        destinations: <Widget>[
          const NavigationDestination(
              icon: Icon(Icons.code_outlined),
              selectedIcon: Icon(Icons.code),
              label: 'Editor'),
          const NavigationDestination(
              icon: Icon(Icons.school_outlined),
              selectedIcon: Icon(Icons.school),
              label: 'Learn'),
          const NavigationDestination(
              icon: Icon(Icons.bolt_outlined),
              selectedIcon: Icon(Icons.bolt),
              label: 'Snippets'),
          const NavigationDestination(
              icon: Icon(Icons.extension_outlined),
              selectedIcon: Icon(Icons.extension),
              label: 'Packages'),
          const NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'Progress'),
          const NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
    );
  }
}
