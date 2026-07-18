import 'package:flutter/material.dart';

import '../../api/calagopus_client.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../server/activity_tab.dart' show ActivityListTile;
import 'api_keys_screen.dart';
import 'sessions_screen.dart';
import 'snippets_screen.dart';
import 'ssh_keys_screen.dart';
import 'two_factor_screen.dart';

/// Account hub: profile, credentials, keys, sessions, snippets, activity.
class AccountScreen extends StatefulWidget {
  final CalagopusClient client;

  const AccountScreen({super.key, required this.client});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  Map<String, dynamic>? _user;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = await widget.client.getAccountRaw();
      if (mounted) {
        setState(() {
          _user = user;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _editProfile() async {
    final user = _user;
    if (user == null) return;
    final username =
        TextEditingController(text: user['username'] as String? ?? '');
    final first =
        TextEditingController(text: user['name_first'] as String? ?? '');
    final last =
        TextEditingController(text: user['name_last'] as String? ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('編輯個人資料'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: username,
                decoration: const InputDecoration(
                    labelText: '使用者名稱', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: first,
                decoration: const InputDecoration(
                    labelText: '名', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: last,
                decoration: const InputDecoration(
                    labelText: '姓', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('儲存')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.client.updateAccount({
        'username': username.text.trim(),
        'name_first': first.text.trim(),
        'name_last': last.text.trim(),
      });
      _load();
      if (mounted) showSnack(context, '已更新個人資料');
    } catch (e) {
      if (mounted) showSnack(context, '更新失敗：$e', isError: true);
    }
  }

  Future<void> _changeEmail() async {
    final email = TextEditingController(
        text: _user?['email'] as String? ?? '');
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('變更 Email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                    labelText: '新 Email', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: '目前密碼', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('變更')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.client
          .updateEmail(email.text.trim(), password.text);
      _load();
      if (mounted) showSnack(context, 'Email 已更新');
    } catch (e) {
      if (mounted) showSnack(context, '更新失敗：$e', isError: true);
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final fresh = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('變更密碼'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: current,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: '目前密碼', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: fresh,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: '新密碼', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('變更')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.client.updatePassword(current.text, fresh.text);
      if (mounted) showSnack(context, '密碼已更新');
    } catch (e) {
      if (mounted) showSnack(context, '更新失敗：$e', isError: true);
    }
  }

  void _push(Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen))
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Scaffold(
      appBar: AppBar(title: const Text('帳號')),
      body: user == null
          ? Center(
              child: _error != null
                  ? Text(_error!)
                  : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                          radius: 24, child: Icon(Icons.person)),
                      title: Text(user['username'] as String? ?? ''),
                      subtitle: Text([
                        user['email'] as String? ?? '',
                        if (user['admin'] == true) '管理員',
                      ].join(' · ')),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: _editProfile,
                    ),
                  ),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.email_outlined),
                          title: const Text('變更 Email'),
                          onTap: _changeEmail,
                        ),
                        ListTile(
                          leading: const Icon(Icons.password),
                          title: const Text('變更密碼'),
                          onTap: _changePassword,
                        ),
                        ListTile(
                          leading: const Icon(Icons.verified_user_outlined),
                          title: const Text('兩步驟驗證'),
                          subtitle: Text(user['totp_enabled'] == true
                              ? '已啟用'
                              : '未啟用'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _push(TwoFactorScreen(
                              client: widget.client,
                              enabled: user['totp_enabled'] == true)),
                        ),
                      ],
                    ),
                  ),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.key),
                          title: const Text('API 金鑰'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _push(
                              ApiKeysScreen(client: widget.client)),
                        ),
                        ListTile(
                          leading: const Icon(Icons.terminal),
                          title: const Text('SSH 金鑰'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _push(
                              SshKeysScreen(client: widget.client)),
                        ),
                        ListTile(
                          leading: const Icon(Icons.devices),
                          title: const Text('工作階段與安全金鑰'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _push(
                              SessionsScreen(client: widget.client)),
                        ),
                        ListTile(
                          leading: const Icon(Icons.bolt),
                          title: const Text('指令片段'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _push(
                              SnippetsScreen(client: widget.client)),
                        ),
                      ],
                    ),
                  ),
                  Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.history),
                      title: const Text('帳號活動'),
                      children: [
                        SizedBox(
                          height: 360,
                          child: PagedListView<ActivityEntry>(
                            emptyLabel: '沒有活動紀錄',
                            fetch: (page, _) => widget.client
                                .getAccountActivity(page: page),
                            itemBuilder: (context, a) =>
                                ActivityListTile(entry: a),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
