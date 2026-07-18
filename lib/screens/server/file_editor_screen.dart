import 'package:flutter/material.dart';

import '../../api/calagopus_client.dart';
import '../../models/server.dart';
import '../../widgets/common.dart';

/// Plain-text editor for a server file.
class FileEditorScreen extends StatefulWidget {
  final CalagopusClient client;
  final Server server;
  final String path;

  const FileEditorScreen({
    super.key,
    required this.client,
    required this.server,
    required this.path,
  });

  @override
  State<FileEditorScreen> createState() => _FileEditorScreenState();
}

class _FileEditorScreenState extends State<FileEditorScreen> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final content = await widget.client
          .getFileContents(widget.server.uuid, widget.path);
      if (!mounted) return;
      _controller.text = content;
      setState(() => _dirty = false);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.client.writeFile(
          widget.server.uuid, widget.path, _controller.text);
      if (!mounted) return;
      setState(() => _dirty = false);
      showSnack(context, '已儲存');
    } catch (e) {
      if (mounted) showSnack(context, '儲存失敗：$e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    return confirm(context,
        title: '尚未儲存',
        message: '有未儲存的變更，確定要離開嗎？',
        confirmLabel: '離開',
        destructive: true);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.path.split('/').last;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('$name${_dirty ? ' •' : ''}'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新載入',
              onPressed: _loading ? null : _load,
            ),
            IconButton(
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              tooltip: '儲存',
              onPressed: _saving || _loading ? null : _save,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : Padding(
                    padding: const EdgeInsets.all(8),
                    child: TextField(
                      controller: _controller,
                      onChanged: (_) {
                        if (!_dirty) setState(() => _dirty = true);
                      },
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontFamilyFallback: ['Consolas', 'Courier New'],
                        fontSize: 13,
                        height: 1.4,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
      ),
    );
  }
}
