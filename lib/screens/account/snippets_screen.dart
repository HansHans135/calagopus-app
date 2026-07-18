import 'package:flutter/material.dart';

import '../../api/calagopus_client.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class SnippetsScreen extends StatefulWidget {
  final CalagopusClient client;

  const SnippetsScreen({super.key, required this.client});

  @override
  State<SnippetsScreen> createState() => _SnippetsScreenState();
}

class _SnippetsScreenState extends State<SnippetsScreen> {
  final _listKey = GlobalKey<PagedListViewState<CommandSnippet>>();

  Future<void> _edit({CommandSnippet? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final command = TextEditingController(text: existing?.command ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? '建立指令片段' : '編輯指令片段'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: '名稱', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: command,
                maxLines: 3,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(
                    labelText: '指令', border: OutlineInputBorder())),
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
    if (ok != true ||
        name.text.trim().isEmpty ||
        command.text.trim().isEmpty) {
      return;
    }
    try {
      if (existing == null) {
        await widget.client.createCommandSnippet(
            name.text.trim(), command.text.trim(), const []);
      } else {
        await widget.client.updateCommandSnippet(
            existing.uuid, name.text.trim(), command.text.trim());
      }
      _listKey.currentState?.refresh();
    } catch (e) {
      if (mounted) showSnack(context, '儲存失敗：$e', isError: true);
    }
  }

  Future<void> _delete(CommandSnippet snippet) async {
    final ok = await confirm(context,
        title: '刪除指令片段',
        message: '確定要刪除「${snippet.name}」嗎？',
        confirmLabel: '刪除',
        destructive: true);
    if (!ok) return;
    try {
      await widget.client.deleteCommandSnippet(snippet.uuid);
      _listKey.currentState?.refresh();
    } catch (e) {
      if (mounted) showSnack(context, '刪除失敗：$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('指令片段')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(),
        child: const Icon(Icons.add),
      ),
      body: PagedListView<CommandSnippet>(
        key: _listKey,
        emptyLabel: '沒有指令片段',
        fetch: (page, _) =>
            widget.client.getCommandSnippets(page: page),
        itemBuilder: (context, s) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.bolt),
            title: Text(s.name),
            subtitle: Text(s.command,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'monospace')),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(existing: s)),
                IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(s)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
