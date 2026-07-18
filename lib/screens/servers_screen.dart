import 'dart:async';

import 'package:flutter/material.dart';

import '../api/calagopus_client.dart';
import '../models/models.dart';
import '../models/server.dart';
import '../services/settings_service.dart';
import '../widgets/common.dart';
import 'account/account_screen.dart';
import 'server/server_shell.dart';
import 'settings_screen.dart';

/// Home screen: server list (with groups) for the active panel connection.
class ServersScreen extends StatefulWidget {
  final SettingsService settings;

  const ServersScreen({super.key, required this.settings});

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  CalagopusClient? _client;
  List<Server> _servers = [];
  List<ServerGroup> _groups = [];
  bool _loading = false;
  String? _error;
  String _search = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _rebuildClientAndLoad();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _client?.close();
    super.dispose();
  }

  void _rebuildClientAndLoad() {
    _client?.close();
    final profile = widget.settings.activeProfile;
    _client = profile == null
        ? null
        : CalagopusClient(baseUrl: profile.url, apiKey: profile.apiKey);
    _load();
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) {
      setState(() {
        _servers = [];
        _groups = [];
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = <Server>[];
      var page = 1;
      ServerPage result;
      do {
        result = await client.getServers(
            page: page, perPage: 50, search: _search);
        all.addAll(result.servers);
        page++;
      } while (result.hasMore && page <= 10);
      List<ServerGroup> groups = [];
      try {
        groups = await client.getServerGroups();
        groups.sort((a, b) => a.order.compareTo(b.order));
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _servers = all;
        _groups = groups;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String value) {
    _search = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => SettingsScreen(settings: widget.settings)),
    );
    _rebuildClientAndLoad();
  }

  void _openAccount() {
    final client = _client;
    if (client == null) return;
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AccountScreen(client: client)));
  }

  Future<void> _manageGroups() async {
    final client = _client;
    if (client == null) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('建立群組'),
              onTap: () => Navigator.pop(context, 'create'),
            ),
            for (final g in _groups)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(g.name),
                subtitle: Text('${g.serverOrder.length} 台伺服器'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () =>
                          Navigator.pop(context, 'edit:${g.uuid}'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () =>
                          Navigator.pop(context, 'delete:${g.uuid}'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'create') {
      await _editGroup(null);
    } else if (action.startsWith('edit:')) {
      final group =
          _groups.firstWhere((g) => g.uuid == action.substring(5));
      await _editGroup(group);
    } else if (action.startsWith('delete:')) {
      final group =
          _groups.firstWhere((g) => g.uuid == action.substring(7));
      final ok = await confirm(context,
          title: '刪除群組',
          message: '確定要刪除「${group.name}」嗎？（伺服器不會被刪除）',
          confirmLabel: '刪除',
          destructive: true);
      if (!ok) return;
      try {
        await client.deleteServerGroup(group.uuid);
        _load();
      } catch (e) {
        if (mounted) showSnack(context, '刪除失敗：$e', isError: true);
      }
    }
  }

  Future<void> _editGroup(ServerGroup? group) async {
    final client = _client!;
    final name = TextEditingController(text: group?.name ?? '');
    final selected = (group?.serverOrder ?? const []).toSet();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(group == null ? '建立群組' : '編輯群組'),
          content: SizedBox(
            width: double.maxFinite,
            height: 380,
            child: Column(
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                      labelText: '群組名稱', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      for (final s in _servers)
                        CheckboxListTile(
                          dense: true,
                          title: Text(s.name),
                          value: selected.contains(s.uuid),
                          onChanged: (v) => setDialogState(() {
                            v == true
                                ? selected.add(s.uuid)
                                : selected.remove(s.uuid);
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
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
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      if (group == null) {
        await client.createServerGroup(
            name.text.trim(), selected.toList());
      } else {
        await client.updateServerGroup(
            group.uuid, name.text.trim(), selected.toList());
      }
      _load();
    } catch (e) {
      if (mounted) showSnack(context, '儲存失敗：$e', isError: true);
    }
  }

  (Color, String) _statusStyle(BuildContext context, Server s) {
    final scheme = Theme.of(context).colorScheme;
    if (s.isSuspended) return (scheme.error, '已停權');
    if (s.isTransferring) return (scheme.tertiary, '轉移中');
    switch (s.status) {
      case null:
        return (scheme.primary, '正常');
      default:
        return (scheme.tertiary, s.status!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.settings.activeProfile;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Calagopus'),
            if (profile != null)
              Text(
                profile.name,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          if (widget.settings.profiles.length > 1)
            PopupMenuButton<int>(
              icon: const Icon(Icons.swap_horiz),
              tooltip: '切換面板',
              onSelected: (i) async {
                await widget.settings.setActiveIndex(i);
                _rebuildClientAndLoad();
              },
              itemBuilder: (context) => [
                for (var i = 0;
                    i < widget.settings.profiles.length;
                    i++)
                  PopupMenuItem(
                    value: i,
                    child: Row(
                      children: [
                        Icon(
                          i == widget.settings.activeIndex
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(widget.settings.profiles[i].name),
                      ],
                    ),
                  ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            tooltip: '伺服器群組',
            onPressed: _client == null ? null : _manageGroups,
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: '帳號',
            onPressed: _client == null ? null : _openAccount,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '連線設定',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: profile == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('尚未設定面板連線'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _openSettings,
                    icon: const Icon(Icons.settings),
                    label: const Text('前往設定'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: '搜尋伺服器…',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                Expanded(child: _buildList(context)),
              ],
            ),
    );
  }

  Widget _buildList(BuildContext context) {
    if (_loading && _servers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('重試'),
              ),
            ],
          ),
        ),
      );
    }
    if (_servers.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 160),
            Center(child: Text('沒有伺服器')),
          ],
        ),
      );
    }

    // Order servers into groups (only when not searching).
    final byUuid = {for (final s in _servers) s.uuid: s};
    final grouped = <(String, List<Server>)>[];
    final used = <String>{};
    if (_search.isEmpty) {
      for (final g in _groups) {
        final members = [
          for (final uuid in g.serverOrder)
            if (byUuid[uuid] != null) byUuid[uuid]!,
        ];
        if (members.isNotEmpty) {
          grouped.add((g.name, members));
          used.addAll(members.map((s) => s.uuid));
        }
      }
    }
    final ungrouped =
        _servers.where((s) => !used.contains(s.uuid)).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          for (final (name, members) in grouped) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined, size: 18),
                  const SizedBox(width: 6),
                  Text(name,
                      style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
            ),
            for (final s in members) _serverCard(context, s),
          ],
          if (grouped.isNotEmpty && ungrouped.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('未分組',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
          for (final s in ungrouped) _serverCard(context, s),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _serverCard(BuildContext context, Server s) {
    final (color, label) = _statusStyle(context, s);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Icon(Icons.dns, color: color),
        title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            if (s.allocation != null) s.allocation!.display,
            s.nodeName,
            label,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          final client = _client;
          if (client == null) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ServerShell(client: client, server: s),
            ),
          );
        },
      ),
    );
  }
}
