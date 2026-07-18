import 'package:flutter/material.dart';

import '../../api/calagopus_client.dart';
import '../../models/models.dart';
import '../../models/server.dart';
import '../../widgets/common.dart';

class SubusersTab extends StatefulWidget {
  final CalagopusClient client;
  final Server server;

  const SubusersTab({super.key, required this.client, required this.server});

  @override
  State<SubusersTab> createState() => _SubusersTabState();
}

class _SubusersTabState extends State<SubusersTab>
    with AutomaticKeepAliveClientMixin {
  final _listKey = GlobalKey<PagedListViewState<Subuser>>();

  /// {category: {permission: description}} from /api/client/permissions.
  Map<String, Map<String, String>>? _catalog;

  @override
  bool get wantKeepAlive => true;

  Future<Map<String, Map<String, String>>> _loadCatalog() async {
    if (_catalog != null) return _catalog!;
    final json = await widget.client.getPermissions();
    final raw =
        json['server_permissions'] as Map<String, dynamic>? ?? const {};
    final catalog = <String, Map<String, String>>{};
    raw.forEach((category, value) {
      if (value is Map) {
        final permissions = value['permissions'];
        if (permissions is Map) {
          catalog[category] = {
            for (final e in permissions.entries)
              e.key.toString(): e.value.toString(),
          };
          return;
        }
      }
      if (value is Map) {
        catalog[category] = {
          for (final e in value.entries)
            e.key.toString(): e.value.toString(),
        };
      }
    });
    _catalog = catalog;
    return catalog;
  }

  Future<List<String>?> _pickPermissions(List<String> initial) async {
    Map<String, Map<String, String>> catalog;
    try {
      catalog = await _loadCatalog();
    } catch (e) {
      if (mounted) showSnack(context, '無法載入權限清單：$e', isError: true);
      return null;
    }
    if (!mounted) return null;
    final selected = initial.toSet();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('權限'),
          content: SizedBox(
            width: double.maxFinite,
            height: 420,
            child: ListView(
              children: [
                for (final category in catalog.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                    child: Text(category.key,
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  for (final perm in category.value.entries)
                    CheckboxListTile(
                      dense: true,
                      title: Text('${category.key}.${perm.key}'),
                      subtitle: perm.value.isEmpty
                          ? null
                          : Text(perm.value,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                      value: selected
                          .contains('${category.key}.${perm.key}'),
                      onChanged: (v) => setDialogState(() {
                        final key = '${category.key}.${perm.key}';
                        v == true
                            ? selected.add(key)
                            : selected.remove(key);
                      }),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('確定')),
          ],
        ),
      ),
    );
    return ok == true ? selected.toList() : null;
  }

  Future<void> _create() async {
    final email = await promptText(context,
        title: '新增子使用者', label: '使用者 Email', confirmLabel: '下一步');
    if (email == null || email.trim().isEmpty) return;
    final permissions = await _pickPermissions([]);
    if (permissions == null) return;
    try {
      await widget.client
          .createSubuser(widget.server.uuid, email.trim(), permissions);
      _listKey.currentState?.refresh();
    } catch (e) {
      if (mounted) showSnack(context, '新增失敗：$e', isError: true);
    }
  }

  Future<void> _edit(Subuser subuser) async {
    final permissions = await _pickPermissions(subuser.permissions);
    if (permissions == null) return;
    try {
      await widget.client.updateSubuser(
          widget.server.uuid, subuser.userUuid, permissions);
      _listKey.currentState?.refresh();
    } catch (e) {
      if (mounted) showSnack(context, '更新失敗：$e', isError: true);
    }
  }

  Future<void> _delete(Subuser subuser) async {
    final ok = await confirm(context,
        title: '移除子使用者',
        message: '確定要移除「${subuser.username}」的存取權限嗎？',
        confirmLabel: '移除',
        destructive: true);
    if (!ok) return;
    try {
      await widget.client
          .deleteSubuser(widget.server.uuid, subuser.userUuid);
      _listKey.currentState?.refresh();
    } catch (e) {
      if (mounted) showSnack(context, '移除失敗：$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'subuser_fab',
        onPressed: _create,
        child: const Icon(Icons.person_add),
      ),
      body: PagedListView<Subuser>(
        key: _listKey,
        emptyLabel: '沒有子使用者',
        fetch: (page, _) =>
            widget.client.getSubusers(widget.server.uuid, page: page),
        itemBuilder: (context, u) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(u.username),
            subtitle: Text('${u.permissions.length} 項權限'
                '${u.totpEnabled ? ' · 已啟用 2FA' : ''}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(u)),
                IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(u)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
