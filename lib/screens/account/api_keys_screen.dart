import 'package:flutter/material.dart';

import '../../api/calagopus_client.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class ApiKeysScreen extends StatefulWidget {
  final CalagopusClient client;

  const ApiKeysScreen({super.key, required this.client});

  @override
  State<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends State<ApiKeysScreen> {
  final _listKey = GlobalKey<PagedListViewState<ApiKeyInfo>>();

  /// Collects every permission key in a scope of the permission catalog.
  List<String> _allPermissions(dynamic scope) {
    final result = <String>[];
    if (scope is! Map) return result;
    scope.forEach((category, value) {
      dynamic permissions = value;
      if (value is Map && value['permissions'] is Map) {
        permissions = value['permissions'];
      }
      if (permissions is Map) {
        for (final key in permissions.keys) {
          result.add('$category.$key');
        }
      }
    });
    return result;
  }

  Future<void> _create() async {
    final name = await promptText(context,
        title: '建立 API 金鑰', label: '名稱', confirmLabel: '建立');
    if (name == null || name.trim().isEmpty) return;
    try {
      // Grant the full permission catalog (matches "all permissions" keys).
      final catalog = await widget.client.getPermissions();
      final key = await widget.client.createApiKey(
        name: name.trim(),
        userPermissions: _allPermissions(catalog['user_permissions']),
        adminPermissions: _allPermissions(catalog['admin_permissions']),
        serverPermissions:
            _allPermissions(catalog['server_permissions']),
      );
      if (!mounted) return;
      await _showKey(key);
      _listKey.currentState?.refresh();
    } catch (e) {
      if (mounted) showSnack(context, '建立失敗：$e', isError: true);
    }
  }

  Future<void> _showKey(String key) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('API 金鑰'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('金鑰只會顯示這一次，請立即複製：'),
            const SizedBox(height: 12),
            SelectableText(key,
                style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => copyToClipboard(context, key, '金鑰'),
            child: const Text('複製'),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('關閉')),
        ],
      ),
    );
  }

  Future<void> _actions(ApiKeyInfo key) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(key.name),
              subtitle: Text('${key.keyStart}…'
                  '${key.lastUsed != null ? ' · 上次使用 ${formatDateTime(key.lastUsed)}' : ''}'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.autorenew),
              title: const Text('重新產生'),
              onTap: () => Navigator.pop(context, 'recreate'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text('刪除',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      switch (action) {
        case 'recreate':
          final ok = await confirm(context,
              title: '重新產生金鑰',
              message: '舊金鑰將立即失效。確定要繼續嗎？',
              confirmLabel: '重新產生',
              destructive: true);
          if (!ok) return;
          final newKey = await widget.client.recreateApiKey(key.uuid);
          if (mounted) await _showKey(newKey);
          _listKey.currentState?.refresh();
        case 'delete':
          final ok = await confirm(context,
              title: '刪除金鑰',
              message: '確定要刪除「${key.name}」嗎？使用中的應用將無法連線。',
              confirmLabel: '刪除',
              destructive: true);
          if (!ok) return;
          await widget.client.deleteApiKey(key.uuid);
          _listKey.currentState?.refresh();
      }
    } catch (e) {
      if (mounted) showSnack(context, '操作失敗：$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API 金鑰')),
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
      body: PagedListView<ApiKeyInfo>(
        key: _listKey,
        emptyLabel: '沒有 API 金鑰',
        fetch: (page, _) => widget.client.getApiKeys(page: page),
        itemBuilder: (context, k) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.key),
            title: Text(k.name),
            subtitle: Text([
              '${k.keyStart}…',
              if (k.lastUsed != null)
                '上次使用 ${formatDateTime(k.lastUsed)}',
              if (k.expires != null) '到期 ${formatDateTime(k.expires)}',
            ].join(' · ')),
            onTap: () => _actions(k),
          ),
        ),
      ),
    );
  }
}
