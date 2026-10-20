import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/nav_model.dart';
import '../state/workspace_model.dart';
import 'curriculum_screen.dart';
import 'editor_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'tools_screen.dart';

/// Responsive navigation shell: a rail on wide screens, a bar on phones.
/// Focus mode hides all chrome for distraction-free writing.
class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<NavModel>(
      create: (_) => NavModel(),
      child: const _ShellBody(),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const List<_Destination> _destinations = <_Destination>[
  _Destination('Home', Icons.home_outlined, Icons.home_rounded),
  _Destination('Code', Icons.code_rounded, Icons.code_rounded),
  _Destination('Learn', Icons.school_outlined, Icons.school_rounded),
  _Destination('Tools', Icons.handyman_outlined, Icons.handyman_rounded),
  _Destination('Profile', Icons.person_outline_rounded, Icons.person_rounded),
];

class _ShellBody extends StatefulWidget {
  const _ShellBody();

  @override
  State<_ShellBody> createState() => _ShellBodyState();
}

class _ShellBodyState extends State<_ShellBody> {
  // Screens are built the first time they are visited and then kept alive,
  // so switching tabs does not lose scroll positions or in-progress work.
  final Set<int> _visited = <int>{0};

  Widget _screenFor(int i) {
    switch (AppTab.values[i]) {
      case AppTab.home:
        return const HomeScreen();
      case AppTab.code:
        return const EditorScreen();
      case AppTab.learn:
        return const CurriculumScreen();
      case AppTab.tools:
        return const ToolsScreen();
      case AppTab.profile:
        return const ProfileScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final WorkspaceModel workspace = context.watch<WorkspaceModel>();
    final NavModel nav = context.watch<NavModel>();

    if (workspace.focusMode) {
      return const EditorScreen();
    }

    final int index = nav.tab.index;
    _visited.add(index);

    final Widget stack = IndexedStack(
      index: index,
      children: <Widget>[
        for (int i = 0; i < _destinations.length; i++)
          _visited.contains(i) ? _screenFor(i) : const SizedBox.shrink(),
      ],
    );

    void select(int value) {
      // A hidden-but-focused editor would keep the soft keyboard open.
      FocusManager.instance.primaryFocus?.unfocus();
      nav.go(AppTab.values[value]);
    }

    final bool isWide = MediaQuery.of(context).size.width > 900;

    // Android back from any tab other than Home returns to Home first.
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) select(0);
      },
      child: isWide
          ? Scaffold(
              body: Row(
                children: <Widget>[
                  NavigationRail(
                    extended: true,
                    minExtendedWidth: 190,
                    selectedIndex: index,
                    onDestinationSelected: select,
                    destinations: <NavigationRailDestination>[
                      for (final _Destination d in _destinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: stack),
                ],
              ),
            )
          : Scaffold(
              body: stack,
              // While typing, the bar would ride on top of the soft keyboard
              // and steal ~74 dp from the code area.
              bottomNavigationBar: MediaQuery.of(context).viewInsets.bottom > 0
                  ? null
                  : NavigationBar(
                selectedIndex: index,
                onDestinationSelected: select,
                destinations: <Widget>[
                  for (final _Destination d in _destinations)
                    NavigationDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: d.label,
                    ),
                ],
              ),
            ),
    );
  }
}
