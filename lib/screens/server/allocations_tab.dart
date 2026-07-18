import 'package:flutter/material.dart';

import '../../api/calagopus_client.dart';
import '../../models/server.dart';
import '../../widgets/common.dart';

class AllocationsTab extends StatefulWidget {
  final CalagopusClient client;
  final Server server;

  const AllocationsTab(
      {super.key, required this.client, required this.server});

  @override
  State<AllocationsTab> createState() => _AllocationsTabState();
}

class _AllocationsTabState extends State<AllocationsTab>
    with AutomaticKeepAliveClientMixin {
  final _listKey = GlobalKey<PagedListViewState<ServerAllocation>>();

  @override
  bool get wantKeepAlive => true;

  Future<void> _create() async {
    try {
      await widget.client.createAllocation(widget.server.uuid);
      _listKey.currentState?.refresh();
    } catch (e) {
      if (mounted) showSnack(context, '新增失敗：$e', isError: true);
    }
  }

  Future<void> _actions(ServerAllocation allocation) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(allocation.display,
                  style: Theme.of(context).textTheme.titleMedium),
              subtitle: allocation.notes == null
                  ? null
                  : Text(allocation.notes!),
            ),
            const Divider(height: 1),
            if (!allocation.isPrimary)
              ListTile(
                leading: const Icon(Icons.star_outline),
                title: const Text('設為主要位址'),
                onTap: () => Navigator.pop(context, 'primary'),
              ),
            ListTile(
              leading: const Icon(Icons.notes),
              title: const Text('編輯備註'),
              onTap: () => Navigator.pop(context, 'notes'),
            ),
            if (!allocation.isPrimary)
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error),
                title: Text('移除',
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
        case 'primary':
          await widget.client.updateAllocation(
              widget.server.uuid, allocation.uuid,
              primary: true);
          _listKey.currentState?.refresh();
        case 'notes':
          final notes = await promptText(context,
              title: '編輯備註',
              label: '備註',
              initialValue: allocation.notes ?? '',
              confirmLabel: '儲存');
          if (notes == null) return;
          await widget.client.updateAllocation(
              widget.server.uuid, allocation.uuid,
              notes: notes);
          _listKey.currentState?.refresh();
        case 'delete':
          final ok = await confirm(context,
              title: '移除位址',
              message: '確定要移除「${allocation.display}」嗎？',
              confirmLabel: '移除',
              destructive: true);
          if (!ok) return;
          await widget.client
              .deleteAllocation(widget.server.uuid, allocation.uuid);
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
        (widget.server.featureLimits['allocations'] as num?)?.toInt() ?? 0;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'allocation_fab',
        onPressed: _create,
        tooltip: '自動分配新位址',
        child: const Icon(Icons.add),
      ),
      body: PagedListView<ServerAllocation>(
        key: _listKey,
        emptyLabel: '沒有網路位址',
        header: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SFTP：${widget.server.sftpHost}:${widget.server.sftpPort}',
                  style: Theme.of(context).textTheme.bodySmall),
              if (limit > 0)
                Text('位址上限：$limit',
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        fetch: (page, _) =>
            widget.client.getAllocations(widget.server.uuid, page: page),
        itemBuilder: (context, a) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: Icon(
              a.isPrimary ? Icons.star : Icons.lan_outlined,
              color: a.isPrimary ? Colors.amber.shade700 : null,
            ),
            title: Text(a.display),
            subtitle: a.notes != null && a.notes!.isNotEmpty
                ? Text(a.notes!)
                : null,
            trailing: IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: '複製位址',
              onPressed: () =>
                  copyToClipboard(context, a.display, '位址'),
            ),
            onTap: () => _actions(a),
          ),
        ),
      ),
    );
  }
}
