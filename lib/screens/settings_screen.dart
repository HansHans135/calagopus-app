import 'package:flutter/material.dart';

import '../api/calagopus_client.dart';
import '../services/settings_service.dart';

/// Manages saved panel connections (URL + API key) and which one is active.
class SettingsScreen extends StatefulWidget {
  final SettingsService settings;

  const SettingsScreen({super.key, required this.settings});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _openEditor({int? index}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProfileEditorScreen(
          settings: widget.settings,
          editIndex: index,
        ),
      ),
    );
    if (changed == true && mounted) setState(() {});
  }

  Future<void> _confirmDelete(int index) async {
    final profile = widget.settings.profiles[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除連線'),
        content: Text('確定要刪除「${profile.name}」嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.settings.deleteProfile(index);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final profiles = widget.settings.profiles;
    final activeIndex = widget.settings.activeIndex;

    return Scaffold(
      appBar: AppBar(title: const Text('連線設定')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('新增連線'),
      ),
      body: profiles.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.dns_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  const Text('尚未設定任何面板連線'),
                  const SizedBox(height: 8),
                  Text(
                    '點右下角「新增連線」輸入面板網址與 API Key',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: profiles.length,
              itemBuilder: (context, i) {
                final p = profiles[i];
                final active = i == activeIndex;
                return ListTile(
                  leading: Icon(
                    active
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: active
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(p.name.isEmpty ? p.url : p.name),
                  subtitle: Text(p.url),
                  selected: active,
                  onTap: () async {
                    await widget.settings.setActiveIndex(i);
                    if (mounted) setState(() {});
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: '編輯',
                        onPressed: () => _openEditor(index: i),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '刪除',
                        onPressed: () => _confirmDelete(i),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class ProfileEditorScreen extends StatefulWidget {
  final SettingsService settings;
  final int? editIndex;

  const ProfileEditorScreen({
    super.key,
    required this.settings,
    this.editIndex,
  });

  @override
  State<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends State<ProfileEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _keyController;
  bool _obscureKey = true;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  bool get _isEdit => widget.editIndex != null;

  @override
  void initState() {
    super.initState();
    final existing =
        _isEdit ? widget.settings.profiles[widget.editIndex!] : null;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _urlController = TextEditingController(
        text: existing?.url ?? 'https://panel.nyastack.dev');
    _keyController = TextEditingController(text: existing?.apiKey ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final client = CalagopusClient(
      baseUrl: _urlController.text,
      apiKey: _keyController.text.trim(),
    );
    try {
      final account = await client.getAccount();
      setState(() {
        _testOk = true;
        _testResult =
            '連線成功：${account.username} (${account.email})${account.admin ? ' [管理員]' : ''}';
      });
    } catch (e) {
      setState(() {
        _testOk = false;
        _testResult = '連線失敗：$e';
      });
    } finally {
      client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final url = _urlController.text.trim();
    final profile = PanelProfile(
      name: _nameController.text.trim().isEmpty
          ? Uri.parse(url.startsWith('http') ? url : 'https://$url').host
          : _nameController.text.trim(),
      url: url,
      apiKey: _keyController.text.trim(),
    );
    if (_isEdit) {
      await widget.settings.updateProfile(widget.editIndex!, profile);
    } else {
      await widget.settings.addProfile(profile);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? '編輯連線' : '新增連線')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '名稱（選填）',
                hintText: '例如：主要面板',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '面板網址',
                hintText: 'https://panel.nyastack.dev',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.isEmpty) return '請輸入面板網址';
                final withScheme =
                    value.startsWith('http') ? value : 'https://$value';
                final uri = Uri.tryParse(withScheme);
                if (uri == null || uri.host.isEmpty) return '網址格式不正確';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _keyController,
              obscureText: _obscureKey,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: '在面板「帳號 → API Keys」建立',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.key),
                suffixIcon: IconButton(
                  icon: Icon(_obscureKey
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () =>
                      setState(() => _obscureKey = !_obscureKey),
                ),
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? '請輸入 API Key' : null,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : _testConnection,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering),
                    label: const Text('測試連線'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('儲存'),
                  ),
                ),
              ],
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 16),
              Card(
                color: _testOk
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(_testOk ? Icons.check_circle : Icons.error,
                          color: _testOk
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_testResult!)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
