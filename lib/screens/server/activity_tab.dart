import 'dart:convert';

import 'package:flutter/material.dart';

import '../../api/calagopus_client.dart';
import '../../models/models.dart';
import '../../models/server.dart';
import '../../widgets/common.dart';

class ActivityTab extends StatefulWidget {
  final CalagopusClient client;
  final Server server;

  const ActivityTab({super.key, required this.client, required this.server});

  @override
  State<ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<ActivityTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PagedListView<ActivityEntry>(
      emptyLabel: '沒有活動紀錄',
      searchable: true,
      fetch: (page, search) => widget.client.getServerActivity(
          widget.server.uuid,
          page: page,
          search: search),
      itemBuilder: (context, a) => ActivityListTile(entry: a),
    );
  }
}

class ActivityListTile extends StatelessWidget {
  final ActivityEntry entry;

  const ActivityListTile({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final hasData = entry.data != null &&
        entry.data is Map &&
        (entry.data as Map).isNotEmpty;
    return ListTile(
      dense: true,
      leading: Icon(
        entry.isApi ? Icons.key : Icons.person_outline,
        size: 20,
      ),
      title: Text(entry.event),
      subtitle: Text([
        if (entry.username != null) entry.username!,
        if (entry.ip != null) entry.ip!,
        formatDateTime(entry.created),
      ].join(' · ')),
      onTap: !hasData
          ? null
          : () => showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(entry.event),
                  content: SingleChildScrollView(
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ')
                          .convert(entry.data),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('關閉')),
                  ],
                ),
              ),
    );
  }
}
