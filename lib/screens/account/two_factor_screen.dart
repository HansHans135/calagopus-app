import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/calagopus_client.dart';
import '../../widgets/common.dart';

class TwoFactorScreen extends StatefulWidget {
  final CalagopusClient client;
  final bool enabled;

  const TwoFactorScreen(
      {super.key, required this.client, required this.enabled});

  @override
  State<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends State<TwoFactorScreen> {
  String? _otpUrl;
  String? _secret;
  String? _error;
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) _loadSetup();
  }

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadSetup() async {
    try {
      final setup = await widget.client.getTwoFactorSetup();
      if (mounted) {
        setState(() {
          _otpUrl = setup.otpUrl;
          _secret = setup.secret;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    try {
      final recoveryCodes = await widget.client
          .enableTwoFactor(_code.text.trim(), _password.text);
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('救援碼'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('請妥善保存以下救援碼，遺失驗證器時可用來登入：'),
                const SizedBox(height: 12),
                SelectableText(recoveryCodes.join('\n'),
                    style: const TextStyle(fontFamily: 'monospace')),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                copyToClipboard(
                    context, recoveryCodes.join('\n'), '救援碼');
              },
              child: const Text('複製'),
            ),
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('我已保存')),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, '啟用失敗：$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    setState(() => _busy = true);
    try {
      await widget.client
          .disableTwoFactor(_code.text.trim(), _password.text);
      if (!mounted) return;
      showSnack(context, '已停用兩步驟驗證');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, '停用失敗：$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('兩步驟驗證')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!widget.enabled) ...[
            if (_error != null)
              Text(_error!)
            else if (_otpUrl == null)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator()))
            else ...[
              const Text('使用驗證器 App（如 Google Authenticator）掃描：'),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(data: _otpUrl!, size: 200),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SelectableText('密鑰：$_secret',
                        style:
                            const TextStyle(fontFamily: 'monospace')),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () =>
                        copyToClipboard(context, _secret!, '密鑰'),
                  ),
                ],
              ),
              const Divider(height: 32),
            ],
          ] else
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text('兩步驟驗證目前已啟用。輸入驗證碼與密碼以停用：'),
            ),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: '6 位數驗證碼', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: '帳號密碼', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy
                ? null
                : widget.enabled
                    ? _disable
                    : _enable,
            style: widget.enabled
                ? FilledButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).colorScheme.error)
                : null,
            child: Text(widget.enabled ? '停用' : '啟用'),
          ),
        ],
      ),
    );
  }
}
