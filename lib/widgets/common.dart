import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';

void showSnack(BuildContext context, String message,
    {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
  ));
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '確定',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error)
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Single-field text prompt dialog. Returns null when cancelled.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String label = '',
  String initialValue = '',
  String confirmLabel = '確定',
  bool obscure = false,
  int maxLines = 1,
}) {
  final controller = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: obscure,
        maxLines: maxLines,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        onSubmitted: maxLines == 1
            ? (v) => Navigator.pop(context, v)
            : null,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

void copyToClipboard(BuildContext context, String value, String label) {
  Clipboard.setData(ClipboardData(text: value));
  showSnack(context, '$label已複製');
}

/// Generic paginated list with pull-to-refresh, search, and load-more.
class PagedListView<T> extends StatefulWidget {
  final Future<Paginated<T>> Function(int page, String? search) fetch;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String emptyLabel;
  final bool searchable;
  final Widget? header;

  const PagedListView({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    this.emptyLabel = '沒有資料',
    this.searchable = false,
    this.header,
  });

  @override
  State<PagedListView<T>> createState() => PagedListViewState<T>();
}

class PagedListViewState<T> extends State<PagedListView<T>> {
  final List<T> _items = [];
  int _page = 1;
  bool _hasMore = false;
  bool _loading = false;
  String? _error;
  String? _search;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    _page = 1;
    await _load(clear: true);
  }

  Future<void> _load({bool clear = false}) async {
    setState(() {
      _loading = true;
      if (clear) _error = null;
    });
    try {
      final result = await widget.fetch(_page, _search);
      if (!mounted) return;
      setState(() {
        if (clear) _items.clear();
        _items.addAll(result.data);
        _hasMore = result.hasMore;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.searchable)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              onChanged: (v) {
                _search = v;
              },
              onSubmitted: (_) => refresh(),
              decoration: InputDecoration(
                hintText: '搜尋…',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
        Expanded(
          child: _error != null && _items.isEmpty
              ? _ErrorRetry(error: _error!, onRetry: refresh)
              : _loading && _items.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: refresh,
                      child: _items.isEmpty
                          ? ListView(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              children: [
                                if (widget.header != null) widget.header!,
                                const SizedBox(height: 120),
                                Center(child: Text(widget.emptyLabel)),
                              ],
                            )
                          : ListView.builder(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              itemCount: _items.length +
                                  (widget.header != null ? 1 : 0) +
                                  (_hasMore ? 1 : 0),
                              itemBuilder: (context, i) {
                                var index = i;
                                if (widget.header != null) {
                                  if (index == 0) return widget.header!;
                                  index--;
                                }
                                if (index >= _items.length) {
                                  return Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Center(
                                      child: _loading
                                          ? const CircularProgressIndicator()
                                          : OutlinedButton(
                                              onPressed: () {
                                                _page++;
                                                _load();
                                              },
                                              child: const Text('載入更多'),
                                            ),
                                    ),
                                  );
                                }
                                return widget.itemBuilder(
                                    context, _items[index]);
                              },
                            ),
                    ),
        ),
      ],
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String error;
  final Future<void> Function() onRetry;

  const _ErrorRetry({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 40, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重試'),
            ),
          ],
        ),
      ),
    );
  }
}
