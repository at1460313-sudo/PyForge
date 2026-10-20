import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import '../services/ai_service.dart';
import '../services/python_bridge.dart';
import '../services/secure_store.dart';
import '../state/settings_model.dart';
import '../state/workspace_model.dart';
import '../theme/app_theme.dart';
import '../theme/syntax_themes.dart';

/// Settings: appearance, AI keys (BYOK) and version control.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _customModelController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _gitName = TextEditingController();
  final TextEditingController _gitEmail = TextEditingController();
  final TextEditingController _gitRemote = TextEditingController();
  final TextEditingController _gitUsername = TextEditingController();
  final TextEditingController _gitToken = TextEditingController();

  bool _obscureKey = true;
  bool _testing = false;
  String? _testResult; // null = none; else OK/error text

  @override
  void initState() {
    super.initState();
    final SettingsModel settings = context.read<SettingsModel>();
    _customModelController.text = settings.aiModel;
    _baseUrlController.text = settings.aiBaseUrl;
    _gitName.text = settings.gitAuthorName;
    _gitEmail.text = settings.gitAuthorEmail;
    _gitRemote.text = settings.gitRemoteUrl;
    _gitUsername.text = settings.gitUsername;
    _gitToken.addListener(_syncGitToken);
  }

  Future<void> _syncGitToken() async {
    // Token is stored securely as the user types; never displayed again.
  }

  @override
  void dispose() {
    _keyController.dispose();
    _customModelController.dispose();
    _baseUrlController.dispose();
    _gitName.dispose();
    _gitEmail.dispose();
    _gitRemote.dispose();
    _gitUsername.dispose();
    _gitToken.dispose();
    super.dispose();
  }

  Future<void> _saveKey(SettingsModel settings) async {
    final String key = _keyController.text.trim();
    if (key.isEmpty) return;
    await SecureStore.instance.saveApiKey(key);
    await settings.load();
    HapticFeedback.selectionClick();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API key saved securely on this device.')),
      );
    }
  }

  Future<void> _testConnection(SettingsModel settings) async {
    final String key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _testResult = 'Enter a key first.');
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final AiConfig config = AiConfig(
        provider: settings.aiProvider,
        model: _customModelController.text.trim().isEmpty
            ? settings.aiModel
            : _customModelController.text.trim(),
        baseUrl: _baseUrlController.text.trim(),
      );
      final String reply = await AiService.instance.testConnection(config, key);
      setState(() => _testResult = 'Success — model replied: "$reply"');
      HapticFeedback.lightImpact();
    } on AiServiceException catch (e) {
      setState(() => _testResult = e.message);
    } catch (e) {
      setState(() => _testResult = 'Connection failed: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final SettingsModel settings = context.watch<SettingsModel>();
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // ------------------------------------------------ APPEARANCE
          _Section(icon: Icons.palette_outlined, title: 'Appearance'),
          const SizedBox(height: 10),
          SegmentedButton<AppThemeMode>(
            segments: const <ButtonSegment<AppThemeMode>>[
              ButtonSegment(
                  value: AppThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_outlined)),
              ButtonSegment(
                  value: AppThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_outlined)),
              ButtonSegment(
                  value: AppThemeMode.oled,
                  label: Text('OLED'),
                  icon: Icon(Icons.contrast)),
            ],
            selected: <AppThemeMode>{settings.themeMode},
            onSelectionChanged: (Set<AppThemeMode> value) =>
                settings.setThemeMode(value.first),
          ),
          const SizedBox(height: 16),
          _buildSyntaxChips(settings),
          const SizedBox(height: 16),
          _SliderTile(
            label: 'Font size',
            value: settings.fontSize,
            min: 11,
            max: 22,
            display: '${settings.fontSize.round()} pt',
            onChanged: (double v) => settings.setFontSize(v),
          ),

          const SizedBox(height: 28),
          // ------------------------------------------------ AI CO-PILOT
          _Section(icon: Icons.auto_awesome, title: 'AI Co-Pilot (BYOK)'),
          const SizedBox(height: 4),
          Text(
            'Your key is stored encrypted on this device only. It is sent '
            'solely to the provider you choose, only when you trigger an AI '
            'action.',
            style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSurface.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<AiProvider>(
            decoration: const InputDecoration(
                labelText: 'Provider', prefixIcon: Icon(Icons.cloud_outlined)),
            value: settings.aiProvider,
            items: <DropdownMenuItem<AiProvider>>[
              for (final AiProvider p in AiProvider.values)
                DropdownMenuItem<AiProvider>(
                    value: p, child: Text(p.label)),
            ],
            onChanged: (AiProvider? p) async {
              if (p == null) return;
              await settings.setAiProvider(p);
              _customModelController.text =
                  AiService.suggestedModels[p]?.first ?? '';
              await settings.setAiModel(_customModelController.text);
            },
          ),
          const SizedBox(height: 12),
          if (settings.aiProvider == AiProvider.openrouter ||
              settings.aiProvider == AiProvider.custom)
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: 'Base URL (OpenAI-compatible)',
                prefixIcon: Icon(Icons.link),
                hintText: 'https://your-endpoint.com/v1',
              ),
              onChanged: (String v) => settings.setAiBaseUrl(v.trim()),
            ),
          if (settings.aiProvider == AiProvider.openrouter ||
              settings.aiProvider == AiProvider.custom)
            const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Model', prefixIcon: Icon(Icons.smart_toy_outlined)),
            value: (AiService.suggestedModels[settings.aiProvider] ?? const <String>[])
                    .contains(settings.aiModel) ||
                    settings.aiModel.isEmpty
                ? settings.aiModel
                : null,
            items: <DropdownMenuItem<String>>[
              for (final String m
                  in AiService.suggestedModels[settings.aiProvider] ?? <String>[])
                DropdownMenuItem<String>(value: m, child: Text(m)),
            ],
            onChanged: (String? m) async {
              if (m == null) return;
              _customModelController.text = m;
              await settings.setAiModel(m);
            },
          ),
          TextField(
            controller: _customModelController,
            decoration: const InputDecoration(
              labelText: 'Model (type any name)',
              prefixIcon: Icon(Icons.edit_outlined),
              helperText: 'Pick from the list above or type your own.',
            ),
            onChanged: (String v) => settings.setAiModel(v.trim()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyController,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              labelText: settings.hasApiKey
                  ? 'API key (saved — type to replace)'
                  : 'API key',
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscureKey ? Icons.visibility : Icons.visibility_off),
                onPressed: () =>
                    setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  icon: _testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('Test connection'),
                  onPressed: _testing ? null : () => _testConnection(settings),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save key'),
                  onPressed: () => _saveKey(settings),
                ),
              ),
            ],
          ),
          if (_testResult != null) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _testResult!.startsWith('Success')
                    ? Colors.green.withValues(alpha: 0.12)
                    : scheme.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_testResult!,
                  style: TextStyle(
                      fontSize: 13,
                      color: _testResult!.startsWith('Success')
                          ? Colors.green.shade700
                          : scheme.error)),
            ),
          ],
          if (settings.hasApiKey)
            TextButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove saved key'),
              onPressed: () async {
                await SecureStore.instance.deleteApiKey();
                await settings.load();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('API key removed.')),
                  );
                }
              },
            ),

          const SizedBox(height: 28),
          // ------------------------------------------------ VERSION CONTROL
          _Section(icon: Icons.source_outlined, title: 'Version control'),
          const SizedBox(height: 4),
          Text(
            'Commits are stored in a local Git repository inside your '
            'workspace. Push works over HTTPS with your token kept in '
            'encrypted storage.',
            style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSurface.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _gitName,
            decoration: const InputDecoration(
                labelText: 'Author name', prefixIcon: Icon(Icons.person_outline)),
            onChanged: (String v) => settings.setGitAuthorName(v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _gitEmail,
            decoration: const InputDecoration(
                labelText: 'Author email', prefixIcon: Icon(Icons.mail_outline)),
            onChanged: (String v) => settings.setGitAuthorEmail(v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _gitRemote,
            decoration: const InputDecoration(
              labelText: 'Remote URL (HTTPS)',
              prefixIcon: Icon(Icons.cloud_upload_outlined),
              hintText: 'https://github.com/you/repo.git',
            ),
            onChanged: (String v) => settings.setGitRemoteUrl(v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _gitUsername,
            decoration: const InputDecoration(
                labelText: 'Remote username',
                prefixIcon: Icon(Icons.badge_outlined)),
            onChanged: (String v) => settings.setGitUsername(v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _gitToken,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Access token (stored encrypted)',
              prefixIcon: Icon(Icons.vpn_key_outlined),
            ),
            onChanged: (String v) async {
              if (v.isEmpty) return;
              await SecureStore.instance.saveGitToken(v);
            },
          ),
          const SizedBox(height: 14),
          _buildGitActions(),

          const SizedBox(height: 28),
          // ------------------------------------------------ ABOUT
          _Section(icon: Icons.info_outline, title: 'About'),
          const SizedBox(height: 8),
          Text(
            'PyForge 1.0.0 — offline Python IDE.\n'
            'Python runtime by Chaquopy. Everything except AI features and '
            'git push works without internet.',
            style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSurface.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSyntaxChips(SettingsModel settings) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final SyntaxThemeDef theme in SyntaxThemes.all)
          ChoiceChip(
            label: Text(theme.label,
                style: const TextStyle(fontSize: 12.5)),
            selected: settings.syntaxThemeId == theme.id,
            onSelected: (_) => settings.setSyntaxTheme(theme.id),
          ),
      ],
    );
  }

  Widget _buildGitActions() {
    final SettingsModel settings = context.watch<SettingsModel>();
    final WorkspaceModel workspace = context.watch<WorkspaceModel>();
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.create_new_folder_outlined, size: 16),
            label: const Text('Init', style: TextStyle(fontSize: 12.5)),
            onPressed: () => _gitOp(
                () => PythonBridge.instance.gitInit(workspace.root)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.commit, size: 16),
            label: const Text('Commit', style: TextStyle(fontSize: 12.5)),
            onPressed: () => _commit(workspace, settings),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            icon: const Icon(Icons.upload, size: 16),
            label: const Text('Push', style: TextStyle(fontSize: 12.5)),
            onPressed: () => _push(workspace, settings),
          ),
        ),
      ],
    );
  }

  Future<void> _gitOp(Future<Map<String, dynamic>> Function() op) async {
    try {
      final Map<String, dynamic> result = await op();
      if (!mounted) return;
      final String message = result['ok'] == true
          ? (result['sha'] != null
              ? 'Committed ${result['sha']}'.substring(0, 24)
              : (result['message'] as String? ?? 'Done.'))
          : (result['message'] as String? ?? 'Operation failed.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _commit(WorkspaceModel workspace, SettingsModel settings) async {
    final String? message = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        final TextEditingController controller = TextEditingController();
        return AlertDialog(
          title: const Text('Commit message'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'What did you learn?'),
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(null),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(controller.text),
                child: const Text('Commit')),
          ],
        );
      },
    );
    if (message == null || message.trim().isEmpty) return;
    await _gitOp(() => PythonBridge.instance.gitCommit(
          repoPath: workspace.root,
          message: message.trim(),
          authorName: settings.gitAuthorName,
          authorEmail: settings.gitAuthorEmail,
        ));
  }

  Future<void> _push(WorkspaceModel workspace, SettingsModel settings) async {
    if (settings.gitRemoteUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add a remote URL (HTTPS) first.')),
      );
      return;
    }
    final String? token = await SecureStore.instance.gitToken;
    await _gitOp(() => PythonBridge.instance.gitPush(
          repoPath: workspace.root,
          remoteUrl: settings.gitRemoteUrl,
          username: settings.gitUsername,
          token: token ?? '',
        ));
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 8),
        Text(title,
            style:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(label,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
            Text(display,
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7))),
          ],
        ),
        Slider(value: value, min: min, max: max, onChanged: onChanged),
      ],
    );
  }
}
