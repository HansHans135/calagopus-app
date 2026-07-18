import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../../api/calagopus_client.dart';
import '../../models/models.dart';
import '../../models/server.dart';
import '../../services/server_socket.dart';
import '../../widgets/ansi_text.dart';
import '../../widgets/common.dart';
import '../../widgets/stat_chart.dart';

const _chartCapacity = 60; // sliding window: last 60 stats samples (~1/s)
const _consoleCapacity = 500;

/// Live console via websocket, real-time resource charts, power controls.
class ConsoleTab extends StatefulWidget {
  final CalagopusClient client;
  final Server server;

  const ConsoleTab({super.key, required this.client, required this.server});

  @override
  State<ConsoleTab> createState() => _ConsoleTabState();
}

class _ConsoleTabState extends State<ConsoleTab>
    with AutomaticKeepAliveClientMixin {
  late final ServerSocket _socket;
  final List<StreamSubscription> _subscriptions = [];

  ResourceUsage? _usage;
  String _state = 'offline';
  bool _wsConnected = false;
  Timer? _fallbackTimer;
  String? _pendingAction;
  List<Announcement> _announcements = [];

  final _cpuSamples = Queue<double>();
  final _memorySamples = Queue<double>();
  final _rxRateSamples = Queue<double>();
  final _txRateSamples = Queue<double>();
  ResourceUsage? _previousUsage;
  DateTime? _previousUsageAt;

  final _consoleLines = Queue<String>();
  final _consoleScroll = ScrollController();
  final _commandController = TextEditingController();
  bool _autoScroll = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _socket = ServerSocket(
        client: widget.client, serverUuid: widget.server.uuid);
    _subscriptions.add(_socket.consoleLines.listen(_onConsoleLine));
    _subscriptions.add(_socket.stats.listen(_onStats));
    _subscriptions.add(_socket.status.listen((s) {
      if (mounted && s != _state) setState(() => _state = s);
    }));
    _subscriptions.add(_socket.connected.listen((connected) {
      if (!mounted) return;
      setState(() => _wsConnected = connected);
      _configureFallback(connected);
    }));
    _consoleScroll.addListener(() {
      if (!_consoleScroll.hasClients) return;
      final atBottom = _consoleScroll.position.pixels >=
          _consoleScroll.position.maxScrollExtent - 40;
      if (atBottom != _autoScroll) {
        setState(() => _autoScroll = atBottom);
      }
    });
    _socket.connect();
    _pollOnce();
    _configureFallback(false);
    _loadAnnouncements();
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _socket.dispose();
    _fallbackTimer?.cancel();
    _consoleScroll.dispose();
    _commandController.dispose();
    super.dispose();
  }

  Future<void> _loadAnnouncements() async {
    try {
      final list =
          await widget.client.getAnnouncements(widget.server.uuid);
      if (mounted) setState(() => _announcements = list);
    } catch (_) {}
  }

  void _configureFallback(bool wsConnected) {
    _fallbackTimer?.cancel();
    if (!wsConnected) {
      _fallbackTimer =
          Timer.periodic(const Duration(seconds: 5), (_) => _pollOnce());
    }
  }

  Future<void> _pollOnce() async {
    try {
      final usage = await widget.client.getResources(widget.server.uuid);
      if (!_wsConnected) _onStats(usage);
    } catch (_) {}
  }

  void _onStats(ResourceUsage usage) {
    if (!mounted) return;
    final now = DateTime.now();
    void push(Queue<double> queue, double value) {
      queue.addLast(value);
      while (queue.length > _chartCapacity) {
        queue.removeFirst();
      }
    }

    push(_cpuSamples, usage.cpuAbsolute);
    push(_memorySamples, usage.memoryBytes.toDouble());

    final prev = _previousUsage;
    final prevAt = _previousUsageAt;
    if (prev != null && prevAt != null) {
      final seconds =
          now.difference(prevAt).inMilliseconds.clamp(1, 60000) / 1000.0;
      // Counters reset when the server restarts; treat drops as zero rate.
      final rxDelta = usage.rxBytes - prev.rxBytes;
      final txDelta = usage.txBytes - prev.txBytes;
      push(_rxRateSamples, rxDelta > 0 ? rxDelta / seconds : 0);
      push(_txRateSamples, txDelta > 0 ? txDelta / seconds : 0);
    }
    _previousUsage = usage;
    _previousUsageAt = now;

    setState(() {
      _usage = usage;
      _state = usage.state;
    });
  }

  void _onConsoleLine(String line) {
    if (!mounted) return;
    setState(() {
      for (final part in line.split('\n')) {
        _consoleLines.addLast(part);
      }
      while (_consoleLines.length > _consoleCapacity) {
        _consoleLines.removeFirst();
      }
    });
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_consoleScroll.hasClients) {
          _consoleScroll
              .jumpTo(_consoleScroll.position.maxScrollExtent);
        }
      });
    }
  }

  Future<void> _power(String action) async {
    if (action == 'kill' || action == 'stop') {
      final ok = await confirm(
        context,
        title: action == 'kill' ? '強制終止' : '停止伺服器',
        message: action == 'kill'
            ? '強制終止可能造成資料遺失，確定要繼續嗎？'
            : '確定要停止「${widget.server.name}」嗎？',
        destructive: action == 'kill',
      );
      if (!ok) return;
    }
    setState(() => _pendingAction = action);
    try {
      await widget.client.sendPowerAction(widget.server.uuid, action);
      if (mounted) showSnack(context, '已送出「$action」指令');
    } catch (e) {
      if (mounted) showSnack(context, '操作失敗：$e', isError: true);
    } finally {
      if (mounted) setState(() => _pendingAction = null);
    }
  }

  Future<void> _sendCommand() async {
    final command = _commandController.text.trim();
    if (command.isEmpty) return;
    if (_wsConnected) {
      _socket.sendCommand(command);
      _commandController.clear();
      return;
    }
    try {
      await widget.client.sendCommand(widget.server.uuid, command);
      _commandController.clear();
    } catch (e) {
      if (mounted) showSnack(context, '指令送出失敗：$e', isError: true);
    }
  }

  Future<void> _showSnippets() async {
    List<CommandSnippet> snippets = [];
    try {
      final own = await widget.client.getCommandSnippets();
      snippets = own.data
          .where((s) =>
              s.eggs.isEmpty || s.eggs.contains(widget.server.eggUuid))
          .toList();
      final egg = await widget.client
          .getEggCommandSnippets(widget.server.eggUuid);
      final known = snippets.map((e) => e.uuid).toSet();
      snippets.addAll(egg.where((e) => !known.contains(e.uuid)));
    } catch (e) {
      if (mounted) showSnack(context, '無法載入指令片段：$e', isError: true);
      return;
    }
    if (!mounted) return;
    if (snippets.isEmpty) {
      showSnack(context, '沒有可用的指令片段（可在帳號設定中建立）');
      return;
    }
    final chosen = await showModalBottomSheet<CommandSnippet>(
      context: context,
      builder: (context) => ListView(
        children: [
          for (final s in snippets)
            ListTile(
              leading: const Icon(Icons.bolt),
              title: Text(s.name),
              subtitle: Text(s.command,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(context, s),
            ),
        ],
      ),
    );
    if (chosen != null) {
      _commandController.text = chosen.command;
    }
  }

  (Color, IconData, String) _stateStyle(BuildContext context, String state) {
    final scheme = Theme.of(context).colorScheme;
    return switch (state) {
      'running' => (Colors.green, Icons.play_circle, '運行中'),
      'starting' => (Colors.orange, Icons.hourglass_top, '啟動中'),
      'stopping' => (Colors.orange, Icons.hourglass_bottom, '停止中'),
      _ => (scheme.outline, Icons.stop_circle, '離線'),
    };
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final usage = _usage;
    final (stateColor, stateIcon, stateLabel) =
        _stateStyle(context, _state);
    final running = _state == 'running' || _state == 'starting';

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final a in _announcements) _announcementCard(context, a),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(stateIcon, color: stateColor, size: 32),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(stateLabel,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: stateColor)),
                        if (usage != null && usage.uptimeMs > 0)
                          Text('運行時間：${formatUptime(usage.uptimeMs)}',
                              style:
                                  Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Icon(
                          _wsConnected ? Icons.bolt : Icons.sync_problem,
                          size: 16,
                          color: _wsConnected
                              ? Colors.green
                              : Theme.of(context).colorScheme.outline,
                        ),
                        Text(
                          _wsConnected ? '即時' : '輪詢中',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _powerButton('start', Icons.play_arrow, '啟動',
                        enabled: !running),
                    const SizedBox(width: 8),
                    _powerButton('restart', Icons.restart_alt, '重啟',
                        enabled: running),
                    const SizedBox(width: 8),
                    _powerButton('stop', Icons.stop, '停止',
                        enabled: running),
                    const SizedBox(width: 8),
                    _powerButton('kill', Icons.dangerous, '強制終止',
                        enabled: _state != 'offline', destructive: true),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildConsole(context),
        const SizedBox(height: 8),
        StatLineChart(
          title: 'CPU',
          currentLabel:
              '${(usage?.cpuAbsolute ?? 0).toStringAsFixed(2)} %',
          samples: _cpuSamples.toList(),
          capacity: _chartCapacity,
          color: Colors.teal,
          formatValue: (v) =>
              v < 10 ? '${v.toStringAsFixed(2)}%' : '${v.toStringAsFixed(0)}%',
        ),
        StatLineChart(
          title: '記憶體',
          currentLabel: usage == null
              ? '—'
              : usage.memoryLimitBytes > 0
                  ? '${formatBytes(usage.memoryBytes)} / ${formatBytes(usage.memoryLimitBytes)}'
                  : formatBytes(usage.memoryBytes),
          samples: _memorySamples.toList(),
          capacity: _chartCapacity,
          color: Colors.indigo,
          maxY: (usage?.memoryLimitBytes ?? 0) > 0
              ? usage!.memoryLimitBytes.toDouble()
              : null,
          formatValue: (v) => formatBytes(v),
        ),
        StatLineChart(
          title: '網路（↓ 下載 / ↑ 上傳）',
          currentLabel: usage == null
              ? '—'
              : '↓ ${formatBytes(_rxRateSamples.isEmpty ? 0 : _rxRateSamples.last)}/s  ↑ ${formatBytes(_txRateSamples.isEmpty ? 0 : _txRateSamples.last)}/s',
          samples: _rxRateSamples.toList(),
          secondarySamples: _txRateSamples.toList(),
          capacity: _chartCapacity,
          color: Colors.blue,
          secondaryColor: Colors.deepOrange,
          formatValue: (v) => '${formatBytes(v)}/s',
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('磁碟使用量'),
            trailing: Text(
              usage == null ? '—' : formatBytes(usage.diskBytes),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('伺服器資訊',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                _infoRow(
                    '位址', widget.server.allocation?.display ?? '—'),
                _infoRow('節點', widget.server.nodeName),
                _infoRow('位置', widget.server.locationName),
                _infoRow('UUID', widget.server.uuidShort),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _announcementCard(BuildContext context, Announcement a) {
    final scheme = Theme.of(context).colorScheme;
    final (color, icon) = switch (a.type) {
      'success' => (Colors.green, Icons.check_circle_outline),
      'warning' => (Colors.orange, Icons.warning_amber),
      'error' => (scheme.error, Icons.error_outline),
      _ => (scheme.primary, Icons.info_outline),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(a.title),
        subtitle: a.content.isEmpty ? null : Text(a.content),
      ),
    );
  }

  Widget _buildConsole(BuildContext context) {
    const consoleBackground = Color(0xFF1E1E2E);
    const baseStyle = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: ['Consolas', 'Courier New'],
      fontSize: 12,
      height: 1.4,
      color: Color(0xFFCDD6F4),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Text('主控台',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                if (!_autoScroll)
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _autoScroll = true);
                      if (_consoleScroll.hasClients) {
                        _consoleScroll.jumpTo(
                            _consoleScroll.position.maxScrollExtent);
                      }
                    },
                    icon: const Icon(Icons.vertical_align_bottom,
                        size: 16),
                    label: const Text('回到底部'),
                  ),
                IconButton(
                  tooltip: '清空畫面',
                  icon: const Icon(Icons.clear_all, size: 18),
                  onPressed: () =>
                      setState(() => _consoleLines.clear()),
                ),
              ],
            ),
          ),
          Container(
            height: 320,
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: consoleBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _consoleLines.isEmpty
                ? Center(
                    child: Text(
                      _wsConnected ? '尚無輸出' : '連線主控台中…',
                      style: baseStyle.copyWith(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    controller: _consoleScroll,
                    itemCount: _consoleLines.length,
                    itemBuilder: (context, i) => AnsiText(
                      _consoleLines.elementAt(i),
                      baseStyle: baseStyle,
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: '指令片段',
                  icon: const Icon(Icons.bolt),
                  onPressed: _showSnippets,
                ),
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    enabled: _state == 'running',
                    onSubmitted: (_) => _sendCommand(),
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      hintText: '輸入指令…',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _state == 'running' ? _sendCommand : null,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _powerButton(String action, IconData icon, String label,
      {required bool enabled, bool destructive = false}) {
    final busy = _pendingAction != null;
    return Expanded(
      child: Tooltip(
        message: label,
        child: destructive
            ? OutlinedButton(
                onPressed: enabled && !busy ? () => _power(action) : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: _pendingAction == action
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(icon),
              )
            : FilledButton.tonal(
                onPressed: enabled && !busy ? () => _power(action) : null,
                child: _pendingAction == action
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(icon),
              ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 64,
              child: Text(label,
                  style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
