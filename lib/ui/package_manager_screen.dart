import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/python_bridge.dart';
import '../theme/app_theme.dart';
import 'widgets/app_widgets.dart';

/// Package manager GUI. Shows everything bundled with the interpreter and
/// offers one-tap installs for popular libraries (with an honest fallback
/// when runtime pip is unavailable — see the info card).
class PackageManagerScreen extends StatefulWidget {
  const PackageManagerScreen({super.key, this.embedded = false});

  /// Hosted inside the Tools tab: no AppBar of its own.
  final bool embedded;

  @override
  State<PackageManagerScreen> createState() => _PackageManagerScreenState();
}

class _PackageManagerScreenState extends State<PackageManagerScreen> {
  List<Map<String, dynamic>> _packages = <Map<String, dynamic>>[];
  bool _loading = true;
  String _query = '';
  String? _installing;

  static const List<String> _popular = <String>[
    'numpy',
    'requests',
    'scipy',
    'pandas',
    'pillow',
    'matplotlib',
    'sympy',
    'beautifulsoup4',
    'pyyaml',
    'attrs',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final Map<String, dynamic> result =
          await PythonBridge.instance.listPackages();
      if (result['ok'] == true) {
        final List<dynamic> packages =
            result['packages'] as List<dynamic>? ?? <dynamic>[];
        setState(() {
          _packages = packages
              .map((dynamic p) => <String, dynamic>{
                    'name': (p as Map<String, dynamic>)['name'],
                    'version': p['version'],
                  })
              .toList();
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _install(String name) async {
    HapticFeedback.mediumImpact();
    setState(() => _installing = name);
    final Map<String, dynamic> result =
        await PythonBridge.instance.tryInstallPackage(name);
    setState(() => _installing = null);
    if (!mounted) return;
    final bool ok = result['ok'] == true;
    final String message = result['message'] as String? ?? '';
    final String reason = result['reason'] as String? ?? '';
    if (reason == 'runtime_pip_unavailable') {
      _showUnavailableDialog(name, message);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? message : 'Install failed: $message'),
        action: ok ? SnackBarAction(label: 'Refresh', onPressed: _load) : null,
      ),
    );
    if (ok) await _load();
  }

  void _showUnavailableDialog(String name, String message) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Runtime install unavailable'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(message),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                'install("$name")',
                style: const TextStyle(fontFamily: kMonoFont),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy line'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: 'install("$name")'));
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text(
                        'Copied. Paste it in android/app/build.gradle and rebuild.')),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<Map<String, dynamic>> filtered = _query.isEmpty
        ? _packages
        : _packages
            .where((Map<String, dynamic> p) => (p['name'] as String)
                .toLowerCase()
                .contains(_query.toLowerCase()))
            .toList();

    return Scaffold(
      backgroundColor: widget.embedded ? Colors.transparent : null,
      appBar: widget.embedded ? null : AppBar(title: const Text('Packages')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search installed packages',
              ),
              onChanged: (String v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppCard(
              padding: const EdgeInsets.all(14),
              color: scheme.tint(scheme.secondary, 0.08),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  IconBadge(
                      icon: Icons.inventory_2_rounded,
                      color: scheme.secondary,
                      size: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'These libraries are bundled inside the app and work '
                      'offline. To add more, include them when building the '
                      'APK (README: "Adding packages").',
                      style: TextStyle(
                          fontSize: 13, height: 1.4, color: scheme.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? EmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: _query.isEmpty
                            ? 'No packages found'
                            : 'No match for "$_query"',
                        message: _query.isEmpty
                            ? 'Pull down to refresh the list.'
                            : 'Check the spelling, or tap Install to add it.',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (BuildContext context, int index) {
                            final Map<String, dynamic> pkg = filtered[index];
                            final bool isPopular =
                                _popular.contains(pkg['name']);
                            return AppCard(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              child: Row(
                                children: <Widget>[
                                  IconBadge(
                                    icon: isPopular
                                        ? Icons.star_rounded
                                        : Icons.extension_rounded,
                                    color: isPopular
                                        ? scheme.flame
                                        : scheme.success,
                                    size: 40,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(pkg['name'] as String,
                                        style: const TextStyle(
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                  Pill(
                                      label: 'v${pkg['version'] ?? '?'}',
                                      color: scheme.muted),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'install',
        icon: const Icon(Icons.add_rounded),
        label: const Text('Install'),
        onPressed: () => _showInstallSheet(),
      ),
    );
  }

  Future<void> _showInstallSheet() {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) => Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('Install a package',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Attempts a runtime pip install. If this build does not '
                'include pip, you will get the exact line to add to your '
                'build instead.',
                style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String name in _popular)
                    ActionChip(
                      label: _installing == name
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(name),
                      onPressed:
                          _installing == null ? () => _install(name) : null,
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
