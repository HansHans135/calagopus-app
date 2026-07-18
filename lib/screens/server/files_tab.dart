import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/calagopus_client.dart';
import '../../models/models.dart';
import '../../models/server.dart';
import '../../widgets/common.dart';
import 'file_editor_screen.dart';

/// File manager: browse, edit, upload, download, rename, copy, delete,
/// compress/decompress, chmod, pull from URL, search.
class FilesTab extends StatefulWidget {
  final CalagopusClient client;
  final Server server;

  const FilesTab({super.key, required this.client, required this.server});

  @override
  State<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<FilesTab>
    with AutomaticKeepAliveClientMixin {
  String _directory = '/';
  List<FileEntry> _entries = [];
  bool _loading = true;
  String? _error;
  int _page = 1;
  bool _hasMore = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false}) async {
    if (!append) {
      _page = 1;
    }
    setState(() {
      _loading = true;
      if (!append) _error = null;
    });
    try {
      final result = await widget.client.listFiles(widget.server.uuid,
          directory: _directory, page: _page);
      if (!mounted) return;
      setState(() {
        if (append) {
          _entries.addAll(result.entries.data);
        } else {
          _entries = result.entries.data;
        }
        _hasMore = result.entries.hasMore;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(String directory) {
    setState(() => _directory = directory);
    _load();
  }

  String _join(String dir, String name) =>
      dir == '/' ? '/$name' : '$dir/$name';

  Future<void> _createDirectory() async {
    final name = await promptText(context,
        title: '建立資料夾', label: '資料夾名稱', confirmLabel: '建立');
    if (name == null || name.trim().isEmpty) return;
    await _run(() => widget.client
        .createDirectory(widget.server.uuid, _directory, name.trim()));
  }

  Future<void> _createFile() async {
    final name = await promptText(context,
        title: '建立檔案', label: '檔案名稱', confirmLabel: '建立');
    if (name == null || name.trim().isEmpty) return;
    final path = _join(_directory, name.trim());
    await _run(
        () => widget.client.writeFile(widget.server.uuid, path, ''));
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FileEditorScreen(
          client: widget.client, server: widget.server, path: path),
    ));
    _load();
  }

  Future<void> _upload() async {
    final result =
        await FilePicker.pickFiles(allowMultiple: true, withData: true);
    if (result == null || result.files.isEmpty) return;
    try {
      final url =
          await widget.client.getFileUploadUrl(widget.server.uuid);
      var uploaded = 0;
      for (final f in result.files) {
        final bytes = f.bytes;
        if (bytes == null) continue;
        if (mounted) {
          showSnack(context,
              '上傳中 (${uploaded + 1}/${result.files.length})：${f.name}');
        }
        await widget.client.uploadFile(
          uploadUrl: url,
          directory: _directory,
          filename: f.name,
          bytes: bytes,
        );
        uploaded++;
      }
      if (mounted) showSnack(context, '已上傳 $uploaded 個檔案');
      _load();
    } catch (e) {
      if (mounted) showSnack(context, '上傳失敗：$e', isError: true);
    }
  }

  Future<void> _pullFromUrl() async {
    final url = await promptText(context,
        title: '從網址下載到伺服器', label: 'URL', confirmLabel: '下載');
    if (url == null || url.trim().isEmpty) return;
    await _run(() =>
        widget.client.pullFile(widget.server.uuid, _directory, url.trim()));
    if (mounted) showSnack(context, '已在背景開始下載');
  }

  Future<void> _downloadDirectory() async {
    try {
      final url = await widget.client.getFilesDownloadUrl(
          widget.server.uuid,
          root: _directory,
          directory: true);
      await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) showSnack(context, '下載失敗：$e', isError: true);
    }
  }

  Future<void> _search() async {
    final query = await promptText(context,
        title: '搜尋檔案', label: '檔名關鍵字', confirmLabel: '搜尋');
    if (query == null || query.trim().isEmpty) return;
    try {
      final results = await widget.client
          .searchFiles(widget.server.uuid, _directory, query.trim());
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        builder: (context) => results.isEmpty
            ? const SizedBox(
                height: 160, child: Center(child: Text('沒有符合的檔案')))
            : ListView(
                children: [
                  for (final e in results)
                    ListTile(
                      leading: Icon(e.directory
                          ? Icons.folder
                          : Icons.insert_drive_file_outlined),
                      title: Text(e.name),
                      subtitle: Text(formatBytesShort(e.size)),
                    ),
                ],
              ),
      );
    } catch (e) {
      if (mounted) showSnack(context, '搜尋失敗：$e', isError: true);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      _load();
    } catch (e) {
      if (mounted) showSnack(context, '操作失敗：$e', isError: true);
    }
  }

  Future<void> _entryActions(FileEntry entry) async {
    final path = _join(_directory, entry.name);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(entry.name,
                  style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text(
                  '${entry.mode}  ·  ${formatBytesShort(entry.size)}  ·  ${formatDateTime(entry.modified)}'),
            ),
            const Divider(height: 1),
            if (entry.file && entry.editable)
              _sheetItem(context, 'edit', Icons.edit_outlined, '編輯'),
            _sheetItem(context, 'rename', Icons.drive_file_rename_outline,
                '重新命名'),
            if (entry.file)
              _sheetItem(context, 'copy', Icons.copy_outlined, '建立複本'),
            _sheetItem(
                context, 'download', Icons.download_outlined, '下載'),
            if (entry.isArchive)
              _sheetItem(
                  context, 'decompress', Icons.unarchive_outlined, '解壓縮'),
            _sheetItem(
                context, 'compress', Icons.archive_outlined, '壓縮'),
            _sheetItem(context, 'chmod', Icons.lock_outline, '權限 (chmod)'),
            _sheetItem(context, 'delete', Icons.delete_outline, '刪除',
                destructive: true),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'edit':
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FileEditorScreen(
              client: widget.client, server: widget.server, path: path),
        ));
        _load();
      case 'rename':
        final name = await promptText(context,
            title: '重新命名',
            label: '新名稱',
            initialValue: entry.name,
            confirmLabel: '確定');
        if (name == null || name.trim().isEmpty || name == entry.name) {
          return;
        }
        await _run(() => widget.client.renameFiles(widget.server.uuid,
            _directory, [(from: entry.name, to: name.trim())]));
      case 'copy':
        await _run(() => widget.client.copyFile(widget.server.uuid, path));
      case 'download':
        try {
          final url = await widget.client.getFilesDownloadUrl(
              widget.server.uuid,
              root: _directory,
              files: [entry.name],
              directory: entry.directory);
          await launchUrl(Uri.parse(url),
              mode: LaunchMode.externalApplication);
        } catch (e) {
          if (mounted) showSnack(context, '下載失敗：$e', isError: true);
        }
      case 'decompress':
        await _run(() => widget.client
            .decompressFile(widget.server.uuid, _directory, entry.name));
        if (mounted) showSnack(context, '已在背景開始解壓縮');
      case 'compress':
        await _run(() => widget.client.compressFiles(
            widget.server.uuid, _directory, [entry.name], 'tar_gz'));
        if (mounted) showSnack(context, '已在背景開始壓縮');
      case 'chmod':
        final mode = await promptText(context,
            title: '變更權限',
            label: '模式（例如 755）',
            initialValue: entry.modeBits,
            confirmLabel: '套用');
        if (mode == null || mode.trim().isEmpty) return;
        await _run(() => widget.client.chmodFiles(widget.server.uuid,
            _directory, [(file: entry.name, mode: mode.trim())]));
      case 'delete':
        final ok = await confirm(context,
            title: '刪除',
            message: '確定要刪除「${entry.name}」嗎？此操作無法復原。',
            confirmLabel: '刪除',
            destructive: true);
        if (!ok) return;
        await _run(() => widget.client
            .deleteFiles(widget.server.uuid, _directory, [entry.name]));
    }
  }

  ListTile _sheetItem(
      BuildContext context, String value, IconData icon, String label,
      {bool destructive = false}) {
    final color =
        destructive ? Theme.of(context).colorScheme.error : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: () => Navigator.pop(context, value),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final crumbs = _directory == '/'
        ? <String>[]
        : _directory.split('/').where((e) => e.isNotEmpty).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => _open('/'),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.home_outlined, size: 20),
                        ),
                      ),
                      for (var i = 0; i < crumbs.length; i++) ...[
                        const Text('/'),
                        InkWell(
                          onTap: () =>
                              _open('/${crumbs.sublist(0, i + 1).join('/')}'),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Text(crumbs[i]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              IconButton(
                  tooltip: '搜尋',
                  icon: const Icon(Icons.search),
                  onPressed: _search),
              PopupMenuButton<String>(
                onSelected: (v) => switch (v) {
                  'newdir' => _createDirectory(),
                  'newfile' => _createFile(),
                  'upload' => _upload(),
                  'pull' => _pullFromUrl(),
                  'downloaddir' => _downloadDirectory(),
                  _ => null,
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                      value: 'newdir', child: Text('建立資料夾')),
                  PopupMenuItem(
                      value: 'newfile', child: Text('建立檔案')),
                  PopupMenuItem(
                      value: 'upload', child: Text('上傳檔案')),
                  PopupMenuItem(
                      value: 'pull', child: Text('從網址下載')),
                  PopupMenuItem(
                      value: 'downloaddir',
                      child: Text('下載整個資料夾')),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 8),
        Expanded(
          child: _error != null
              ? Center(child: Text(_error!))
              : _loading && _entries.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () => _load(),
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _entries.length +
                            (_directory != '/' ? 1 : 0) +
                            (_hasMore ? 1 : 0),
                        itemBuilder: (context, i) {
                          var index = i;
                          if (_directory != '/') {
                            if (index == 0) {
                              return ListTile(
                                leading:
                                    const Icon(Icons.arrow_upward),
                                title: const Text('..'),
                                dense: true,
                                onTap: () {
                                  final parent = _directory.substring(
                                      0, _directory.lastIndexOf('/'));
                                  _open(parent.isEmpty ? '/' : parent);
                                },
                              );
                            }
                            index--;
                          }
                          if (index >= _entries.length) {
                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: Center(
                                child: OutlinedButton(
                                  onPressed: () {
                                    _page++;
                                    _load(append: true);
                                  },
                                  child: const Text('載入更多'),
                                ),
                              ),
                            );
                          }
                          final e = _entries[index];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              e.directory
                                  ? Icons.folder
                                  : e.isArchive
                                      ? Icons.archive_outlined
                                      : Icons.insert_drive_file_outlined,
                              color: e.directory
                                  ? Colors.amber.shade700
                                  : null,
                            ),
                            title: Text(e.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                '${e.directory ? '' : '${formatBytesShort(e.size)} · '}${formatDateTime(e.modified)}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.more_vert),
                              onPressed: () => _entryActions(e),
                            ),
                            onTap: () {
                              if (e.directory) {
                                _open(_join(_directory, e.name));
                              } else if (e.editable) {
                                Navigator.of(context)
                                    .push(MaterialPageRoute(
                                  builder: (_) => FileEditorScreen(
                                    client: widget.client,
                                    server: widget.server,
                                    path: _join(_directory, e.name),
                                  ),
                                ));
                              } else {
                                _entryActions(e);
                              }
                            },
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

String formatBytesShort(num bytes) {
  const units = ['B', 'K', 'M', 'G', 'T'];
  double value = bytes.toDouble();
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 10 || unit == 0 ? 0 : 1)}${units[unit]}';
}
