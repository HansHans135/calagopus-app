import 'package:flutter/material.dart';

import '../../api/calagopus_client.dart';
import '../../models/models.dart';
import '../../models/server.dart';
import '../../widgets/common.dart';

class DatabasesTab extends StatefulWidget {
  final CalagopusClient client;
  final Server server;

  const DatabasesTab(
      {super.key, required this.client, required this.server});

  @override
  State<DatabasesTab> createState() => _DatabasesTabState();
}

class _DatabasesTabState extends State<DatabasesTab>
    with AutomaticKeepAliveClientMixin {
  final _listKey = GlobalKey<PagedListViewState<ServerDatabase>>();

  @override
  bool get wantKeepAlive => true;

  Future<void> _create() async {
    List<DatabaseHost> hosts;
    try {
      hosts = await widget.client.getDatabaseHosts(widget.server.uuid);
    } catch (e) {
      if (mounted) showSnack(context, '無法載入資料庫主機：$e', isError: true);
      return;
    }
    if (!mounted) return;
    if (hosts.isEmpty) {
      showSnack(context, '此節點沒有可用的資料庫主機', isError: true);
      return;
    }
    String? hostUuid = hosts.first.uuid;
    final nameController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('建立資料庫'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: hostUuid,
                decoration: const InputDecoration(
                    labelText: '資料庫主機', border: OutlineInputBorder()),
                items: [
                  for (final h in hosts)
                    DropdownMenuItem(
                        value: h.uuid,
                        child: Text('${h.name} (${h.type})')),
                ],
                onChanged: (v) => setDialogState(() => hostUuid = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                    labelText: '資料庫名稱', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('建立')),
          ],
        ),
      ),
    );
    if (ok != true || hostUuid == null) return;
    try {
      await widget.client.createDatabase(
          widget.server.uuid, hostUuid!, nameController.text.trim());
      _listKey.currentState?.refresh();
    } catch (e) {
      if (mounted) showSnack(context, '建立失敗：$e', isError: true);
    }
  }

  Future<void> _details(ServerDatabase db) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(db.name,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              _row(context, '類型', db.type),
              _row(context, '主機', '${db.host}:${db.port}'),
              _row(context, '使用者', db.username),
              _row(context, '密碼', db.password ?? '（無權檢視）',
                  copyable: db.password != null),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.key),
                    label: const Text('重設密碼'),
                    onPressed: () async {
                      Navigator.pop(context);
                      try {
                        await widget.client.rotateDatabasePassword(
                            widget.server.uuid, db.uuid);
                        _listKey.currentState?.refresh();
                        if (mounted) showSnack(context, '密碼已重設');
                      } catch (e) {
                        if (mounted) {
                          showSnack(context, '重設失敗：$e', isError: true);
                        }
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    style: OutlinedButton.styleFrom(
                        foregroundColor:
                            Theme.of(context).colorScheme.error),
                    label: const Text('刪除'),
                    onPressed: db.isLocked
                        ? null
                        : () {
                            Navigator.pop(context);
                            _delete(db);
                          },
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

  Future<void> _delete(ServerDatabase db) async {
    final ok = await confirm(context,
        title: '刪除資料庫',
        message: '確定要刪除「${db.name}」嗎？所有資料將永久遺失。',
        confirmLabel: '刪除',
        destructive: true);
    if (!ok) return;
    try {
      await widget.client.deleteDatabase(widget.server.uuid, db.uuid);
      _listKey.currentState?.refresh();
    } catch (e) {
      if (mounted) showSnack(context, '刪除失敗：$e', isError: true);
    }
  }

  Widget _row(BuildContext context, String label, String value,
      {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 64,
              child:
                  Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: SelectableText(value)),
          if (copyable)
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () => copyToClipboard(context, value, label),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'db_fab',
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
      body: PagedListView<ServerDatabase>(
        key: _listKey,
        emptyLabel: '沒有資料庫',
        fetch: (page, _) =>
            widget.client.getDatabases(widget.server.uuid, page: page),
        itemBuilder: (context, db) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: Icon(
              switch (db.type) {
                'postgres' => Icons.storage,
                'mongodb' => Icons.eco_outlined,
                _ => Icons.storage_outlined,
              },
            ),
            title: Text(db.name),
            subtitle: Text('${db.type} · ${db.host}:${db.port}'),
            trailing: db.isLocked ? const Icon(Icons.lock, size: 16) : null,
            onTap: () => _details(db),
          ),
        ),
      ),
    );
  }
}
