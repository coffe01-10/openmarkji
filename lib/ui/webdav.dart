part of 'app.dart';

class _WebDavPage extends StatelessWidget {
  const _WebDavPage({required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => _SettingsDetail(
    title: 'WebDAV 备份',
    child: _WebDavPanel(store: store),
  );
}

class _WebDavPanel extends StatefulWidget {
  const _WebDavPanel({required this.store});
  final AppStore store;
  @override
  State<_WebDavPanel> createState() => _WebDavPanelState();
}

class _WebDavPanelState extends State<_WebDavPanel> {
  final _address = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _folder = TextEditingController(text: 'OpenMarkji');
  WebDavConfig? _connected;
  List<WebDavBackup> _files = [];
  bool _working = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = await widget.store.setting(AppStore.webDavSetting);
    if (!mounted || raw == null) return;
    final config = WebDavConfig.fromJson(decodeObject(raw));
    setState(() {
      _address.text = config.address;
      _username.text = config.username;
      _password.text = config.password;
      _folder.text = config.folder;
      _message = '已保存连接，点击“连接并刷新”查看远端备份。';
    });
  }

  @override
  void dispose() {
    for (final controller in [_address, _username, _password, _folder]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _edited(String _) {
    if (_connected == null) return;
    setState(() {
      _connected = null;
      _files = [];
      _message = '连接信息已修改，请重新连接。';
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await action();
    } catch (e, stack) {
      DiagnosticLog.instance.error('WebDAV 操作', e, stack);
      if (mounted) setState(() => _message = '操作失败：$e');
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _connect() => _run(() async {
    final config = WebDavConfig(
      address: _address.text.trim(),
      username: _username.text,
      password: _password.text,
      folder: _folder.text.trim(),
    );
    final client = WebDavClient(config);
    try {
      await client.connect();
      final files = await client.listBackups();
      await widget.store.setSetting(
        AppStore.webDavSetting,
        jsonEncode(config.toJson()),
      );
      if (mounted) {
        setState(() {
          _connected = config;
          _files = files;
          _message = '连接成功 · ${files.length} 份远端备份';
        });
      }
    } finally {
      client.close();
    }
  });

  Future<void> _upload() => _run(() async {
    final client = WebDavClient(_connected!);
    try {
      final now = DateTime.now();
      final stamp = '${dayKey(now)}-${now.microsecondsSinceEpoch}';
      await client.upload('OpenMarkji-$stamp.zip', await widget.store.backup());
      final files = await client.listBackups();
      if (mounted) {
        setState(() {
          _files = files;
          _message = '备份已上传';
        });
      }
    } finally {
      client.close();
    }
  });

  Future<void> _restore(WebDavBackup file) async {
    if (!await _confirm(
      context,
      '恢复远端备份？',
      '将用 ${file.name} 替换当前资料。恢复前的数据会保留在“导出恢复前的资料”中。',
    )) {
      return;
    }
    if (!mounted) return;
    await _run(() async {
      final client = WebDavClient(_connected!);
      try {
        await widget.store.restore(await client.download(file));
        if (mounted) setState(() => _message = '已恢复资料、图片和学习进度');
      } finally {
        client.close();
      }
    });
  }

  @override
  Widget build(BuildContext context) => _AppearanceCard(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'WebDAV 备份',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            '连接自己的服务器，上传或恢复完整备份。连接信息仅保存在本机，不随备份导出。',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _address,
            enabled: !_working,
            onChanged: _edited,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'WebDAV 地址',
              hintText: 'https://dav.example.com/dav/',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            enabled: !_working,
            onChanged: _edited,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '用户名'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            enabled: !_working,
            onChanged: _edited,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: '密码或应用专用密码'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _folder,
            enabled: !_working,
            onChanged: _edited,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '备份目录',
              helperText: '相对于服务器地址，不存在时自动创建',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _GlassChoice(
                label: '连接并刷新',
                icon: Icons.sync_rounded,
                onPressed: _working ? null : _connect,
              ),
              if (_connected != null)
                _GlassChoice(
                  label: '备份到 WebDAV',
                  icon: Icons.cloud_upload_outlined,
                  onPressed: _working ? null : _upload,
                ),
              if (_address.text.isNotEmpty)
                TextButton(
                  onPressed: _working
                      ? null
                      : () async {
                          await widget.store.clearSetting(
                            AppStore.webDavSetting,
                          );
                          if (!mounted) return;
                          setState(() {
                            _connected = null;
                            _files = [];
                            _address.clear();
                            _username.clear();
                            _password.clear();
                            _folder.text = 'OpenMarkji';
                            _message = '本机连接信息已清除';
                          });
                        },
                  child: const Text('清除连接'),
                ),
            ],
          ),
          if (_working)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _message!,
                style: const TextStyle(fontSize: 12, height: 1.6),
              ),
            ),
          if (kIsWeb)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                '网页版连接需要服务器允许跨域请求（CORS）。',
                style: TextStyle(fontSize: 12, height: 1.6),
              ),
            ),
          if (_connected != null && _files.isEmpty && !_working)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text('远端还没有 ZIP 备份。'),
            ),
          for (final file in _files)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                '${(file.bytes / 1024).ceil()} KB${file.modified.isEmpty ? '' : ' · ${file.modified}'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: _GlassChoice(
                label: '恢复',
                onPressed: _working ? null : () => _restore(file),
              ),
            ),
        ],
      ),
    ),
  );
}
