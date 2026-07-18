import 'package:flutter/material.dart';

import '../../api/calagopus_client.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class SshKeysScreen extends StatefulWidget {
  final CalagopusClient client;

  const SshKeysScreen({super.key, required this.client});

  @override
  State<SshKeysScreen> createState() => _SshKeysScreenState();
}

class _SshKeysScreenState extends State<SshKeysScreen> {
  final _listKey = GlobalKey<PagedListViewState<SshKey>>();

  Future<void> _create() async {
    final name = await promptText(context,
        title: '新增 SSH 金鑰', label: '名稱', confirmLabel: '下一步');
    if (name == null || name.trim().isEmpty) return;
    if (!mounted) return;
    final publicKey = await promptText(context,
        title: '公鑰內容',
        label: 'ssh-ed25519 / ssh-rsa …',
        confirmLabel: '新增',
        maxLines: 4);
    if (publicKey == null || publicKey.trim().isEmpty) return;
    try {
      await widget.client
          .createSshKey(name.trim(), publicKey.trim());
      _listKey.currentState?.refresh();
    } catch (e) {
      if (mounted) showSnack(context, '新增失敗：$e', isError: true);
    }
  }

  Future<void> _import() async {
    String provider = 'github';
    final username = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('匯入 SSH 金鑰'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: provider,
                decoration: const InputDecoration(
                    labelText: '來源', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(
                      value: 'github', child: Text('GitHub')),
                  DropdownMenuItem(
                      value: 'gitlab', child: Text('GitLab')),
                  DropdownMenuItem(
                      value: 'launchpad', child: Text('Launchpad')),
                ],
                onChanged: (v) =>
                    setDialogState(() => provider = v ?? provider),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: username,
                decoration: const InputDecoration(
                    labelText: '使用者名稱', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('匯入')),
          ],
        ),
      ),
    );
    if (ok != true || username.text.trim().isEmpty) return;
    try {
      final count = await widget.client
          .importSshKeys(provider, username.text.trim());
      if (mounted) showSnack(context, '已匯入 $count 把金鑰');
      _listKey.currentState?.refresh();
    } catch (e) {
      if (mounted) showSnack(context, '匯入失敗：$e', isError: true);
    }
  }

  Future<void> _delete(SshKey key) async {
    final ok = await confirm(context,
        title: '刪除 SSH 金鑰',
        message: '確定要刪除「${key.name}」嗎？',
        confirmLabel: '刪除',
        destructive: true);
    if (!ok) return;
    try {
      await widget.client.deleteSshKey(key.uuid);
      _listKey.currentState?.refresh();
    } catch (e) {
      if (mounted) showSnack(context, '刪除失敗：$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH 金鑰'),
        actions: [
          IconButton(
            tooltip: '從 GitHub/GitLab 匯入',
            icon: const Icon(Icons.cloud_download_outlined),
            onPressed: _import,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
      body: PagedListView<SshKey>(
        key: _listKey,
        emptyLabel: '沒有 SSH 金鑰',
        fetch: (page, _) => widget.client.getSshKeys(page: page),
        itemBuilder: (context, k) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.vpn_key_outlined),
            title: Text(k.name),
            subtitle: Text(k.fingerprint,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(k),
            ),
          ),
        ),
      ),
    );
  }
}
