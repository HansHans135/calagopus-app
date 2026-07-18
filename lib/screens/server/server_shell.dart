import 'package:flutter/material.dart';

import '../../api/calagopus_client.dart';
import '../../models/server.dart';
import 'activity_tab.dart';
import 'allocations_tab.dart';
import 'backups_tab.dart';
import 'console_tab.dart';
import 'databases_tab.dart';
import 'files_tab.dart';
import 'schedules_tab.dart';
import 'settings_tab.dart';
import 'startup_tab.dart';
import 'subusers_tab.dart';

/// Shell for one server with a drawer navigation: console, files,
/// databases, backups, schedules, subusers, network, startup, settings,
/// activity.
class ServerShell extends StatefulWidget {
  final CalagopusClient client;
  final Server server;

  const ServerShell({super.key, required this.client, required this.server});

  @override
  State<ServerShell> createState() => _ServerShellState();
}

class _ServerShellState extends State<ServerShell> {
  late Server _server = widget.server;
  int _index = 0;

  /// Pages already opened; unvisited ones stay unbuilt so they don't fire
  /// API calls until first shown.
  final Set<int> _visited = {0};

  static const _sections = [
    (Icons.terminal, '主控台'),
    (Icons.folder_outlined, '檔案'),
    (Icons.storage_outlined, '資料庫'),
    (Icons.archive_outlined, '備份'),
    (Icons.schedule_outlined, '排程'),
    (Icons.group_outlined, '使用者'),
    (Icons.lan_outlined, '網路'),
    (Icons.rocket_launch_outlined, '啟動'),
    (Icons.settings_outlined, '設定'),
    (Icons.history, '活動'),
  ];

  Future<void> _reloadServer() async {
    try {
      final fresh = await widget.client.getServer(widget.server.uuid);
      if (mounted) setState(() => _server = fresh);
    } catch (_) {}
  }

  Widget _buildPage(int index) {
    if (!_visited.contains(index)) return const SizedBox.shrink();
    return switch (index) {
      0 => ConsoleTab(client: widget.client, server: _server),
      1 => FilesTab(client: widget.client, server: _server),
      2 => DatabasesTab(client: widget.client, server: _server),
      3 => BackupsTab(client: widget.client, server: _server),
      4 => SchedulesTab(client: widget.client, server: _server),
      5 => SubusersTab(client: widget.client, server: _server),
      6 => AllocationsTab(client: widget.client, server: _server),
      7 => StartupTab(client: widget.client, server: _server),
      8 => SettingsTab(
          client: widget.client,
          server: _server,
          onServerChanged: _reloadServer,
        ),
      _ => ActivityTab(client: widget.client, server: _server),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_server.name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(_sections[_index].$2,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: '返回伺服器列表',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.dns),
                title: Text(_server.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  _server.allocation?.display ?? _server.uuidShort,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    for (var i = 0; i < _sections.length; i++)
                      ListTile(
                        leading: Icon(_sections[i].$1),
                        title: Text(_sections[i].$2),
                        selected: i == _index,
                        onTap: () {
                          setState(() {
                            _index = i;
                            _visited.add(i);
                          });
                          Navigator.pop(context);
                        },
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.arrow_back),
                title: const Text('返回伺服器列表'),
                onTap: () {
                  Navigator.pop(context); // close drawer
                  Navigator.of(this.context).pop(); // leave server
                },
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < _sections.length; i++) _buildPage(i),
        ],
      ),
    );
  }
}
