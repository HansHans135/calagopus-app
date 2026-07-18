import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/calagopus_client.dart';
import '../../models/models.dart';
import '../../models/server.dart';
import '../../widgets/common.dart';

class BackupsTab extends StatefulWidget {
  final CalagopusClient client;
  final Server server;

  const BackupsTab({super.key, required this.client, required this.server});

  @override
  State<BackupsTab> createState() => _BackupsTabState();
}

class _BackupsTabState extends State<BackupsTab>
    with AutomaticKeepAliveClientMixin {
  final _listKey = GlobalKey<PagedListViewState<Backup>>();

  @override
  bool get wantKeepAlive => true;

  Future<void> _create() async {
    final name = await promptText(context,
        title: '建立備份', label: '名稱（留空自動命名）', confirmLabel: '建立');
    if (name == null) return;
    try {
      await widget.client.createBackup(widget.server.uuid,
          name: name.trim().isEmpty ? null : name.trim());
      if (mounted) showSnack(context, '備份已開始建立');
      _listKey.currentState?.refresh();
    } catch (e) {
      if (mounted) showSnack(context, '建立失敗：$e', isError: true);
    }
  }

  Future<void> _actions(Backup backup) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(backup.name,
                  style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text(
                  '${formatBytes(backup.bytes)} · ${backup.files} 個檔案 · ${formatDateTime(backup.created)}'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('下載'),
              onTap: () => Navigator.pop(context, 'download'),
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('還原'),
              onTap: () => Navigator.pop(context, 'restore'),
            ),
            ListTile(
              leading: Icon(
                  backup.isLocked ? Icons.lock_open : Icons.lock_outline),
              title: Text(backup.isLocked ? '解除鎖定' : '鎖定'),
              onTap: () => Navigator.pop(context, 'lock'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重新命名'),
              onTap: () => Navigator.pop(context, 'rename'),
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
        case 'download':
          final url = await widget.client
              .getBackupDownloadUrl(widget.server.uuid, backup.uuid);
          await launchUrl(Uri.parse(url),
              mode: LaunchMode.externalApplication);
        case 'restore':
          final ok = await confirm(context,
              title: '還原備份',
              message:
                  '將以「${backup.name}」的內容還原伺服器檔案。伺服器需為離線狀態。確定要繼續嗎？',
              confirmLabel: '還原',
              destructive: true);
          if (!ok) return;
          await widget.client
              .restoreBackup(widget.server.uuid, backup.uuid);
          if (mounted) showSnack(context, '還原已開始');
        case 'lock':
          await widget.client.updateBackup(widget.server.uuid, backup.uuid,
              locked: !backup.isLocked);
          _listKey.currentState?.refresh();
        case 'rename':
          final name = await promptText(context,
              title: '重新命名',
              label: '新名稱',
              initialValue: backup.name,
              confirmLabel: '確定');
          if (name == null || name.trim().isEmpty) return;
          await widget.client.updateBackup(widget.server.uuid, backup.uuid,
              name: name.trim());
          _listKey.currentState?.refresh();
        case 'delete':
          if (backup.isLocked) {
            showSnack(context, '備份已鎖定，請先解除鎖定', isError: true);
            return;
          }
          final ok = await confirm(context,
              title: '刪除備份',
              message: '確定要刪除「${backup.name}」嗎？',
              confirmLabel: '刪除',
              destructive: true);
          if (!ok) return;
          await widget.client
              .deleteBackup(widget.server.uuid, backup.uuid);
          _listKey.currentState?.refresh();
      }
    } catch (e) {
      if (mounted) showSnack(context, '操作失敗：$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final limit =
        (widget.server.featureLimits['backups'] as num?)?.toInt() ?? 0;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'backup_fab',
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
      body: PagedListView<Backup>(
        key: _listKey,
        emptyLabel: '沒有備份',
        header: limit > 0
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('備份上限：$limit',
                    style: Theme.of(context).textTheme.bodySmall),
              )
            : null,
        fetch: (page, _) =>
            widget.client.getBackups(widget.server.uuid, page: page),
        itemBuilder: (context, b) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: Icon(
              b.completed == null
                  ? Icons.hourglass_top
                  : b.isSuccessful
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
              color: b.completed == null
                  ? Colors.orange
                  : b.isSuccessful
                      ? Colors.green
                      : Theme.of(context).colorScheme.error,
            ),
            title: Row(
              children: [
                Expanded(
                    child: Text(b.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (b.isLocked) const Icon(Icons.lock, size: 14),
              ],
            ),
            subtitle: Text(
                '${formatBytes(b.bytes)} · ${b.files} 個檔案 · ${formatDateTime(b.created)}'),
            onTap: () => _actions(b),
          ),
        ),
      ),
    );
  }
}
