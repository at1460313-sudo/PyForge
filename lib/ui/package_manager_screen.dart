import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/python_bridge.dart';

/// Package manager GUI. Shows everything bundled with the interpreter and
/// offers one-tap installs for popular libraries (with an honest fallback
/// when runtime pip is unavailable — see the info card).
class PackageManagerScreen extends StatefulWidget {
  const PackageManagerScreen({super.key});

  @override
  State<PackageManagerScreen> createState() => _PackageManagerScreenState();
}

class _PackageManagerScreenState extends State<PackageManagerScreen> {
  List<Map<String, dynamic>> _packages = <Map<String, dynamic>>[];
  bool _loading = true;
  String _query = '';
  String? _installing;

  static const List<String> _popular = <String>[
    'numpy', 'requests', 'scipy', 'pandas', 'pillow', 'matplotlib',
    'sympy', 'beautifulsoup4', 'pyyaml', 'attrs',
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
        final List<dynamic> packages = result['packages'] as List<dynamic>? ?? <dynamic>[];
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
        action: ok
            ? SnackBarAction(label: 'Refresh', onPressed: _load)
            : null,
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
                style: const TextStyle(fontFamily: 'monospace'),
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
      appBar: AppBar(title: const Text('Packages')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search installed packages…',
                isDense: true,
              ),
              onChanged: (String v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.info_outline,
                        size: 18, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'numpy and requests are bundled into the app. '
                        'More libraries can be added when building the APK '
                        '(README → "Adding packages").',
                        style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface.withValues(alpha: 0.7)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: filtered.length,
                      itemBuilder: (BuildContext context, int index) {
                        final Map<String, dynamic> pkg = filtered[index];
                        final bool isPopular =
                            _popular.contains(pkg['name']);
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            isPopular
                                ? Icons.star_outline
                                : Icons.extension_outlined,
                            size: 18,
                            color: scheme.onSurface.withValues(alpha: 0.6),
                          ),
                          title: Text(pkg['name'] as String,
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(pkg['version'] as String? ?? '',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.5))),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'install',
        icon: const Icon(Icons.add),
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
          borderRadius: const BorderRadius.vertical(Radius.circular(24)),
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
                      onPressed: _installing == null
                          ? () => _install(name)
                          : null,
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
