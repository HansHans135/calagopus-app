import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../api/calagopus_client.dart';
import '../models/server.dart';

/// Live connection to a server's console websocket (wings-compatible
/// protocol: `auth` handshake, then `console output` / `stats` / `status`
/// events). Handles token renewal and automatic reconnection.
class ServerSocket {
  final CalagopusClient client;
  final String serverUuid;

  final _consoleController = StreamController<String>.broadcast();
  final _statsController = StreamController<ResourceUsage>.broadcast();
  final _statusController = StreamController<String>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  Stream<String> get consoleLines => _consoleController.stream;
  Stream<ResourceUsage> get stats => _statsController.stream;
  Stream<String> get status => _statusController.stream;
  Stream<bool> get connected => _connectionController.stream;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _disposed = false;
  bool _isConnected = false;
  Timer? _reconnectTimer;

  ServerSocket({required this.client, required this.serverUuid});

  Future<void> connect() async {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    await _teardownChannel();
    try {
      final details = await client.getWebsocketDetails(serverUuid);
      if (_disposed) return;
      final channel = WebSocketChannel.connect(Uri.parse(details.url));
      _channel = channel;
      _subscription = channel.stream.listen(
        (message) => _handleMessage(message as String),
        onDone: _onDisconnected,
        onError: (_) => _onDisconnected(),
      );
      _send('auth', [details.token]);
    } catch (_) {
      _onDisconnected();
    }
  }

  void _handleMessage(String message) {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final args = (data['args'] as List?)?.cast<dynamic>() ?? const [];
    switch (data['event'] as String?) {
      case 'auth success':
        _isConnected = true;
        _connectionController.add(true);
        _send('send logs', [null]);
        _send('send stats', [null]);
      case 'console output':
      case 'install output':
        for (final line in args) {
          _consoleController.add(line.toString());
        }
      case 'stats':
        if (args.isEmpty) break;
        try {
          final usage = ResourceUsage.fromJson(
              jsonDecode(args.first as String) as Map<String, dynamic>);
          _statsController.add(usage);
          _statusController.add(usage.state);
        } catch (_) {}
      case 'status':
        if (args.isNotEmpty) _statusController.add(args.first.toString());
      case 'token expiring':
      case 'token expired':
        _renewToken();
      case 'jwt error':
        _renewToken();
    }
  }

  Future<void> _renewToken() async {
    try {
      final details = await client.getWebsocketDetails(serverUuid);
      _send('auth', [details.token]);
    } catch (_) {
      _onDisconnected();
    }
  }

  void _send(String event, List<dynamic> args) {
    try {
      _channel?.sink.add(jsonEncode({'event': event, 'args': args}));
    } catch (_) {}
  }

  void sendCommand(String command) => _send('send command', [command]);

  void setPowerState(String action) => _send('set state', [action]);

  void _onDisconnected() {
    if (_disposed) return;
    if (_isConnected) {
      _isConnected = false;
      _connectionController.add(false);
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), connect);
  }

  Future<void> _teardownChannel() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _teardownChannel();
    _consoleController.close();
    _statsController.close();
    _statusController.close();
    _connectionController.close();
  }
}
