import 'package:flutter/material.dart';

import '../../api/calagopus_client.dart';
import '../../models/server.dart';
import '../../widgets/common.dart';

/// Rename, timezone, auto-kill/auto-start, reinstall, mounts, logs.
class SettingsTab extends StatefulWidget {
  final CalagopusClient client;
  final Server server;
  final Future<void> Function() onServerChanged;

  const SettingsTab({
    super.key,
    required this.client,
    required this.server,
    required this.onServerChanged,
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Future<void> _rename() async {
    final nameController =
        TextEditingController(text: widget.server.name);
    final descriptionController =
        TextEditingController(text: widget.server.description ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新命名伺服器'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                  labelText: '名稱', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: '描述', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('儲存')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.client.renameServer(widget.server.uuid,
          name: nameController.text.trim(),
          description: descriptionController.text.trim().isEmpty
              ? null
              : descriptionController.text.trim());
      await widget.onServerChanged();
      if (mounted) showSnack(context, '已更新');
    } catch (e) {
      if (mounted) showSnack(context, '更新失敗：$e', isError: true);
    }
  }

  Future<void> _timezone() async {
    final tz = await promptText(context,
        title: '伺服器時區',
        label: '例如 Asia/Taipei（留空使用預設）',
        confirmLabel: '儲存');
    if (tz == null) return;
    try {
      await widget.client.updateTimezone(
          widget.server.uuid, tz.trim().isEmpty ? null : tz.trim());
      if (mounted) showSnack(context, '已更新時區');
    } catch (e) {
      if (mounted) showSnack(context, '更新失敗：$e', isError: true);
    }
  }

  Future<void> _autoKill() async {
    final secondsText = await promptText(context,
        title: '自動強制終止',
        label: '停止逾時秒數（0 = 停用）',
        initialValue: '30',
        confirmLabel: '儲存');
    if (secondsText == null) return;
    final seconds = int.tryParse(secondsText.trim()) ?? 0;
    try {
      await widget.client
          .updateAutoKill(widget.server.uuid, seconds > 0, seconds);
      if (mounted) showSnack(context, '已更新自動終止設定');
    } catch (e) {
      if (mounted) showSnack(context, '更新失敗：$e', isError: true);
    }
  }

  Future<void> _autoStart() async {
    final behavior = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('自動啟動行為'),
        children: [
          for (final (value, label) in [
            ('always', '總是自動啟動'),
            ('unless_stopped', '除非手動停止'),
            ('never', '永不自動啟動'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, value),
              child: Text(label),
            ),
        ],
      ),
    );
    if (behavior == null) return;
    try {
      await widget.client.updateAutoStart(widget.server.uuid, behavior);
      if (mounted) showSnack(context, '已更新自動啟動設定');
    } catch (e) {
      if (mounted) showSnack(context, '更新失敗：$e', isError: true);
    }
  }

  Future<void> _reinstall() async {
    final ok = await confirm(context,
        title: '重新安裝伺服器',
        message: '將重新執行安裝腳本。過程中伺服器會停止。確定要繼續嗎？',
        confirmLabel: '重新安裝',
        destructive: true);
    if (!ok) return;
    try {
      await widget.client.reinstallServer(widget.server.uuid);
      if (mounted) showSnack(context, '已開始重新安裝');
    } catch (e) {
      if (mounted) showSnack(context, '操作失敗：$e', isError: true);
    }
  }

  Future<void> _viewLogs({required bool install}) async {
    try {
      final text = install
          ? await widget.client.getInstallLogs(widget.server.uuid)
          : await widget.client.getServerLogs(widget.server.uuid);
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (context, controller) => Container(
            color: const Color(0xFF1E1E2E),
            padding: const EdgeInsets.all(12),
            child: ListView(
              controller: controller,
              children: [
                SelectableText(
                  text.isEmpty ? '（沒有內容）' : text,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontFamilyFallback: ['Consolas', 'Courier New'],
                    fontSize: 11,
                    color: Color(0xFFCDD6F4),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) showSnack(context, '載入失敗：$e', isError: true);
    }
  }

  Future<void> _mounts() async {
    try {
      final mounts = await widget.client.getMounts(widget.server.uuid);
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        builder: (context) => SafeArea(
          child: mounts.data.isEmpty
              ? const SizedBox(
                  height: 160, child: Center(child: Text('沒有可用的掛載')))
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final m in mounts.data)
                      ListTile(
                        leading: const Icon(Icons.save_outlined),
                        title: Text(m.name),
                        subtitle: Text(
                            '${m.target}${m.readOnly ? '（唯讀）' : ''}'),
                      ),
                  ],
                ),
        ),
      );
    } catch (e) {
      if (mounted) showSnack(context, '載入失敗：$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final limits = widget.server.limits;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('名稱與描述'),
                subtitle: Text(widget.server.name),
                trailing: const Icon(Icons.edit_outlined),
                onTap: _rename,
              ),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('時區'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: _timezone,
              ),
              ListTile(
                leading: const Icon(Icons.timer_off_outlined),
                title: const Text('自動強制終止'),
                subtitle: const Text('停止逾時後自動 kill'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: _autoKill,
              ),
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: const Text('自動啟動行為'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: _autoStart,
              ),
            ],
          ),
        ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('伺服器日誌'),
                onTap: () => _viewLogs(install: false),
              ),
              ListTile(
                leading: const Icon(Icons.build_outlined),
                title: const Text('安裝日誌'),
                onTap: () => _viewLogs(install: true),
              ),
              ListTile(
                leading: const Icon(Icons.save_outlined),
                title: const Text('掛載'),
                onTap: _mounts,
              ),
            ],
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('資源限制',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                _limitRow(
                    'CPU',
                    limits['cpu'] == 0 ? '無限制' : '${limits['cpu']}%'),
                _limitRow(
                    '記憶體',
                    limits['memory'] == 0
                        ? '無限制'
                        : formatBytes(
                            (limits['memory'] as num) * 1024 * 1024)),
                _limitRow(
                    '磁碟',
                    limits['disk'] == 0
                        ? '無限制'
                        : formatBytes(
                            (limits['disk'] as num) * 1024 * 1024)),
                _limitRow(
                    'Swap',
                    (limits['swap'] as num? ?? 0) <= 0
                        ? (limits['swap'] == -1 ? '無限制' : '停用')
                        : formatBytes(
                            (limits['swap'] as num) * 1024 * 1024)),
                const SizedBox(height: 4),
                _limitRow('Egg', widget.server.eggName),
                _limitRow('UUID', widget.server.uuid),
              ],
            ),
          ),
        ),
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: ListTile(
            leading: Icon(Icons.restart_alt,
                color: Theme.of(context).colorScheme.error),
            title: const Text('重新安裝伺服器'),
            subtitle: const Text('重新執行 Egg 安裝腳本'),
            onTap: _reinstall,
          ),
        ),
      ],
    );
  }

  Widget _limitRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 72,
              child: Text(label,
                  style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
