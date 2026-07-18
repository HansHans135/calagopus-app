import 'package:flutter/material.dart';

import '../../api/calagopus_client.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// Login sessions, WebAuthn security keys, and OAuth links.
class SessionsScreen extends StatefulWidget {
  final CalagopusClient client;

  const SessionsScreen({super.key, required this.client});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  final _sessionsKey = GlobalKey<PagedListViewState<UserSession>>();
  final _securityKeysKey = GlobalKey<PagedListViewState<SecurityKey>>();
  final _oauthKey = GlobalKey<PagedListViewState<OAuthLink>>();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('工作階段與安全性'),
          bottom: const TabBar(tabs: [
            Tab(text: '工作階段'),
            Tab(text: '安全金鑰'),
            Tab(text: 'OAuth 連結'),
          ]),
        ),
        body: TabBarView(
          children: [
            PagedListView<UserSession>(
              key: _sessionsKey,
              emptyLabel: '沒有工作階段',
              fetch: (page, _) => widget.client.getSessions(page: page),
              itemBuilder: (context, s) => Card(
                margin: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                child: ListTile(
                  leading: Icon(
                    s.isUsing ? Icons.smartphone : Icons.devices_other,
                    color: s.isUsing ? Colors.green : null,
                  ),
                  title: Text(s.ip),
                  subtitle: Text(
                    '${s.userAgent}\n上次使用：${formatDateTime(s.lastUsed)}'
                    '${s.isUsing ? '（目前工作階段）' : ''}',
                  ),
                  isThreeLine: true,
                  trailing: s.isUsing
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.logout),
                          tooltip: '登出此工作階段',
                          onPressed: () async {
                            final ok = await confirm(context,
                                title: '登出工作階段',
                                message: '確定要登出「${s.ip}」的工作階段嗎？',
                                confirmLabel: '登出',
                                destructive: true);
                            if (!ok) return;
                            try {
                              await widget.client
                                  .deleteSession(s.uuid);
                              _sessionsKey.currentState?.refresh();
                            } catch (e) {
                              if (mounted) {
                                showSnack(context, '操作失敗：$e',
                                    isError: true);
                              }
                            }
                          },
                        ),
                ),
              ),
            ),
            PagedListView<SecurityKey>(
              key: _securityKeysKey,
              emptyLabel: '沒有安全金鑰\n（WebAuthn 金鑰需在網頁版面板註冊）',
              fetch: (page, _) =>
                  widget.client.getSecurityKeys(page: page),
              itemBuilder: (context, k) => Card(
                margin: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.security),
                  title: Text(k.name),
                  subtitle: Text(
                      '上次使用：${formatDateTime(k.lastUsed)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          final name = await promptText(context,
                              title: '重新命名',
                              label: '名稱',
                              initialValue: k.name,
                              confirmLabel: '儲存');
                          if (name == null || name.trim().isEmpty) {
                            return;
                          }
                          try {
                            await widget.client.renameSecurityKey(
                                k.uuid, name.trim());
                            _securityKeysKey.currentState?.refresh();
                          } catch (e) {
                            if (mounted) {
                              showSnack(context, '更新失敗：$e',
                                  isError: true);
                            }
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final ok = await confirm(context,
                              title: '刪除安全金鑰',
                              message: '確定要刪除「${k.name}」嗎？',
                              confirmLabel: '刪除',
                              destructive: true);
                          if (!ok) return;
                          try {
                            await widget.client
                                .deleteSecurityKey(k.uuid);
                            _securityKeysKey.currentState?.refresh();
                          } catch (e) {
                            if (mounted) {
                              showSnack(context, '刪除失敗：$e',
                                  isError: true);
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            PagedListView<OAuthLink>(
              key: _oauthKey,
              emptyLabel: '沒有 OAuth 連結',
              fetch: (page, _) =>
                  widget.client.getOAuthLinks(page: page),
              itemBuilder: (context, link) => Card(
                margin: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.link),
                  title: Text(link.providerName),
                  subtitle: Text(link.identifier),
                  trailing: !link.userManageable
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.link_off),
                          tooltip: '解除連結',
                          onPressed: () async {
                            final ok = await confirm(context,
                                title: '解除 OAuth 連結',
                                message:
                                    '確定要解除「${link.providerName}」的連結嗎？',
                                confirmLabel: '解除',
                                destructive: true);
                            if (!ok) return;
                            try {
                              await widget.client
                                  .deleteOAuthLink(link.uuid);
                              _oauthKey.currentState?.refresh();
                            } catch (e) {
                              if (mounted) {
                                showSnack(context, '操作失敗：$e',
                                    isError: true);
                              }
                            }
                          },
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
