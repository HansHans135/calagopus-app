import 'package:flutter/material.dart';

import '../../api/calagopus_client.dart';
import '../../models/models.dart';
import '../../models/server.dart';
import '../../widgets/common.dart';

/// Startup command, docker image, and egg variables.
class StartupTab extends StatefulWidget {
  final CalagopusClient client;
  final Server server;

  const StartupTab({super.key, required this.client, required this.server});

  @override
  State<StartupTab> createState() => _StartupTabState();
}

class _StartupTabState extends State<StartupTab>
    with AutomaticKeepAliveClientMixin {
  List<StartupVariable> _variables = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final variables =
          await widget.client.getStartupVariables(widget.server.uuid);
      if (mounted) setState(() => _variables = variables);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editCommand() async {
    final command = await promptText(context,
        title: '啟動指令',
        label: '指令',
        initialValue: widget.server.startup,
        confirmLabel: '儲存',
        maxLines: 4);
    if (command == null || command.trim().isEmpty) return;
    try {
      await widget.client
          .updateStartupCommand(widget.server.uuid, command.trim());
      if (mounted) showSnack(context, '已更新啟動指令');
    } catch (e) {
      if (mounted) showSnack(context, '更新失敗：$e', isError: true);
    }
  }

  Future<void> _editImage() async {
    final image = await promptText(context,
        title: 'Docker 映像',
        label: '映像名稱',
        initialValue: widget.server.image,
        confirmLabel: '儲存');
    if (image == null || image.trim().isEmpty) return;
    try {
      await widget.client
          .updateDockerImage(widget.server.uuid, image.trim());
      if (mounted) showSnack(context, '已更新 Docker 映像');
    } catch (e) {
      if (mounted) showSnack(context, '更新失敗：$e', isError: true);
    }
  }

  Future<void> _editVariable(StartupVariable variable) async {
    final value = await promptText(context,
        title: variable.name,
        label: variable.envVariable,
        initialValue: variable.value,
        confirmLabel: '儲存');
    if (value == null) return;
    try {
      await widget.client.updateStartupVariable(
          widget.server.uuid, variable.envVariable, value);
      _load();
    } catch (e) {
      if (mounted) showSnack(context, '更新失敗：$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: const Text('重試')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.terminal),
              title: const Text('啟動指令'),
              subtitle: Text(widget.server.startup,
                  maxLines: 3, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _editCommand,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.developer_board),
              title: const Text('Docker 映像'),
              subtitle: Text(widget.server.image),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _editImage,
            ),
          ),
          const SizedBox(height: 8),
          Text('環境變數', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          if (_variables.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('沒有變數')),
            )
          else
            for (final v in _variables)
              Card(
                child: ListTile(
                  leading: Icon(
                      v.isEditable ? Icons.tune : Icons.lock_outline),
                  title: Text(v.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${v.envVariable} = '
                          '${v.isSecret ? '••••••' : v.value}'),
                      if (v.description != null &&
                          v.description!.isNotEmpty)
                        Text(v.description!,
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                  trailing: v.isEditable
                      ? const Icon(Icons.edit_outlined)
                      : null,
                  onTap: v.isEditable ? () => _editVariable(v) : null,
                ),
              ),
        ],
      ),
    );
  }
}
