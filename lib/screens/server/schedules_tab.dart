import 'dart:convert';

import 'package:flutter/material.dart';

import '../../api/calagopus_client.dart';
import '../../models/models.dart';
import '../../models/server.dart';
import '../../widgets/common.dart';

class SchedulesTab extends StatefulWidget {
  final CalagopusClient client;
  final Server server;

  const SchedulesTab(
      {super.key, required this.client, required this.server});

  @override
  State<SchedulesTab> createState() => _SchedulesTabState();
}

class _SchedulesTabState extends State<SchedulesTab>
    with AutomaticKeepAliveClientMixin {
  final _listKey = GlobalKey<PagedListViewState<Schedule>>();

  @override
  bool get wantKeepAlive => true;

  String _triggerSummary(dynamic trigger) {
    if (trigger is! Map) return trigger.toString();
    return switch (trigger['type']) {
      'cron' => 'Cron：${trigger['schedule']}',
      'power_action' => '電源操作：${trigger['action']}',
      'server_state' => '狀態變為：${trigger['state']}',
      'backup_status' => '備份狀態：${trigger['status']}',
      'console_line' => '主控台包含：${trigger['contains']}',
      'crash' => '伺服器崩潰',
      _ => trigger['type'].toString(),
    };
  }

  Future<void> _create() async {
    final nameController = TextEditingController();
    final cronController = TextEditingController(text: '0 0 4 * * *');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('建立排程'),
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
              controller: cronController,
              decoration: const InputDecoration(
                labelText: 'Cron 表達式',
                helperText: '秒 分 時 日 月 週（例如 0 0 4 * * * = 每天 04:00）',
                border: OutlineInputBorder(),
              ),
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
    );
    if (ok != true || nameController.text.trim().isEmpty) return;
    try {
      await widget.client.createSchedule(widget.server.uuid, {
        'name': nameController.text.trim(),
        'enabled': true,
        'triggers': [
          {'type': 'cron', 'schedule': cronController.text.trim()}
        ],
        'condition': {'type': 'none'},
      });
      _listKey.currentState?.refresh();
    } catch (e) {
      if (mounted) showSnack(context, '建立失敗：$e', isError: true);
    }
  }

  Future<void> _openDetail(Schedule schedule) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ScheduleDetailScreen(
          client: widget.client,
          server: widget.server,
          schedule: schedule),
    ));
    _listKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'schedule_fab',
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
      body: PagedListView<Schedule>(
        key: _listKey,
        emptyLabel: '沒有排程',
        fetch: (page, _) =>
            widget.client.getSchedules(widget.server.uuid, page: page),
        itemBuilder: (context, s) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: Icon(
              s.enabled ? Icons.schedule : Icons.pause_circle_outline,
              color: s.enabled ? Colors.green : null,
            ),
            title: Text(s.name),
            subtitle: Text(
              [
                for (final t in s.triggers) _triggerSummary(t),
                if (s.lastRun != null)
                  '上次執行：${formatDateTime(s.lastRun)}',
              ].join('\n'),
            ),
            isThreeLine: s.triggers.isNotEmpty && s.lastRun != null,
            trailing: s.lastFailure != null &&
                    (s.lastRun == null ||
                        s.lastFailure!.isAfter(s.lastRun!))
                ? Icon(Icons.error_outline,
                    color: Theme.of(context).colorScheme.error)
                : null,
            onTap: () => _openDetail(s),
          ),
        ),
      ),
    );
  }
}

class _ScheduleDetailScreen extends StatefulWidget {
  final CalagopusClient client;
  final Server server;
  final Schedule schedule;

  const _ScheduleDetailScreen({
    required this.client,
    required this.server,
    required this.schedule,
  });

  @override
  State<_ScheduleDetailScreen> createState() =>
      _ScheduleDetailScreenState();
}

class _ScheduleDetailScreenState extends State<_ScheduleDetailScreen> {
  List<ScheduleStep> _steps = [];
  Map<String, dynamic>? _status;
  late bool _enabled = widget.schedule.enabled;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final steps = await widget.client
          .getScheduleSteps(widget.server.uuid, widget.schedule.uuid);
      final status = await widget.client
          .getScheduleStatus(widget.server.uuid, widget.schedule.uuid);
      if (!mounted) return;
      setState(() {
        _steps = steps;
        _status = status;
      });
    } catch (e) {
      if (mounted) showSnack(context, '載入失敗：$e', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _stepSummary(Map<String, dynamic> action) {
    return switch (action['type']) {
      'sleep' => '等待 ${action['duration']} 毫秒',
      'send_power' => '電源操作：${action['action']}',
      'send_command' => '執行指令：${action['command']}',
      'create_backup' => '建立備份${action['name'] != null ? '：${action['name']}' : ''}',
      'create_directory' => '建立資料夾：${action['name']}',
      'write_file' => '寫入檔案：${action['file']}',
      'copy_file' => '複製檔案：${action['file']}',
      'wait_for_console_line' => '等待主控台輸出：${action['contains']}',
      _ => action['type']?.toString() ?? '未知動作',
    };
  }

  Future<void> _addStep() async {
    final typeOptions = {
      'send_command': '執行指令',
      'send_power': '電源操作',
      'create_backup': '建立備份',
      'sleep': '等待（毫秒）',
    };
    String type = 'send_command';
    final valueController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新增步驟'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(
                    labelText: '動作類型', border: OutlineInputBorder()),
                items: [
                  for (final e in typeOptions.entries)
                    DropdownMenuItem(
                        value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) =>
                    setDialogState(() => type = v ?? type),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueController,
                decoration: InputDecoration(
                  labelText: switch (type) {
                    'send_command' => '指令',
                    'send_power' => 'start / stop / restart / kill',
                    'create_backup' => '備份名稱（可留空）',
                    _ => '毫秒數',
                  },
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('新增')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final value = valueController.text.trim();
    final Map<String, dynamic> action = switch (type) {
      'send_command' => {
          'type': 'send_command',
          'command': value,
          'ignore_failure': false,
        },
      'send_power' => {
          'type': 'send_power',
          'action': value.isEmpty ? 'restart' : value,
          'ignore_failure': false,
        },
      'create_backup' => {
          'type': 'create_backup',
          'name': value.isEmpty ? null : value,
          'ignored_files': <String>[],
          'foreground': true,
          'ignore_failure': false,
        },
      _ => {
          'type': 'sleep',
          'duration': int.tryParse(value) ?? 1000,
        },
    };
    try {
      await widget.client.createScheduleStep(
          widget.server.uuid, widget.schedule.uuid, action);
      _load();
    } catch (e) {
      if (mounted) showSnack(context, '新增失敗：$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = _status?['running'] == true;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.schedule.name),
        actions: [
          IconButton(
            tooltip: '匯出 JSON',
            icon: const Icon(Icons.ios_share),
            onPressed: () async {
              try {
                final data = await widget.client.exportSchedule(
                    widget.server.uuid, widget.schedule.uuid);
                if (!mounted) return;
                copyToClipboard(
                    context,
                    const JsonEncoder.withIndent('  ').convert(data),
                    '排程 JSON');
              } catch (e) {
                if (mounted) {
                  showSnack(context, '匯出失敗：$e', isError: true);
                }
              }
            },
          ),
          IconButton(
            tooltip: '刪除排程',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await confirm(context,
                  title: '刪除排程',
                  message: '確定要刪除「${widget.schedule.name}」嗎？',
                  confirmLabel: '刪除',
                  destructive: true);
              if (!ok) return;
              try {
                await widget.client.deleteSchedule(
                    widget.server.uuid, widget.schedule.uuid);
                if (mounted) Navigator.pop(context);
              } catch (e) {
                if (mounted) {
                  showSnack(context, '刪除失敗：$e', isError: true);
                }
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('啟用排程'),
                    value: _enabled,
                    onChanged: (v) async {
                      setState(() => _enabled = v);
                      try {
                        await widget.client.updateSchedule(
                            widget.server.uuid,
                            widget.schedule.uuid,
                            {'enabled': v});
                      } catch (e) {
                        setState(() => _enabled = !v);
                        if (mounted) {
                          showSnack(context, '更新失敗：$e', isError: true);
                        }
                      }
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      running
                          ? Icons.play_circle
                          : Icons.pause_circle_outline,
                      color: running ? Colors.green : null,
                    ),
                    title: Text(running ? '執行中' : '未在執行'),
                    subtitle: running && _status?['step'] != null
                        ? Text('目前步驟：${_status!['step']}')
                        : null,
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: '立即執行',
                          icon: const Icon(Icons.play_arrow),
                          onPressed: running
                              ? null
                              : () async {
                                  try {
                                    await widget.client.triggerSchedule(
                                        widget.server.uuid,
                                        widget.schedule.uuid);
                                    if (mounted) {
                                      showSnack(context, '已觸發排程');
                                    }
                                    _load();
                                  } catch (e) {
                                    if (mounted) {
                                      showSnack(context, '觸發失敗：$e',
                                          isError: true);
                                    }
                                  }
                                },
                        ),
                        IconButton(
                          tooltip: '中止',
                          icon: const Icon(Icons.stop),
                          onPressed: !running
                              ? null
                              : () async {
                                  try {
                                    await widget.client.abortSchedule(
                                        widget.server.uuid,
                                        widget.schedule.uuid);
                                    _load();
                                  } catch (e) {
                                    if (mounted) {
                                      showSnack(context, '中止失敗：$e',
                                          isError: true);
                                    }
                                  }
                                },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('步驟', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addStep,
                  icon: const Icon(Icons.add),
                  label: const Text('新增步驟'),
                ),
              ],
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_steps.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('尚無步驟')),
              )
            else
              for (var i = 0; i < _steps.length; i++)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                        radius: 14, child: Text('${i + 1}')),
                    title: Text(_stepSummary(_steps[i].action)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await confirm(context,
                            title: '刪除步驟',
                            message: '確定要刪除此步驟嗎？',
                            confirmLabel: '刪除',
                            destructive: true);
                        if (!ok) return;
                        try {
                          await widget.client.deleteScheduleStep(
                              widget.server.uuid,
                              widget.schedule.uuid,
                              _steps[i].uuid);
                          _load();
                        } catch (e) {
                          if (mounted) {
                            showSnack(context, '刪除失敗：$e',
                                isError: true);
                          }
                        }
                      },
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
