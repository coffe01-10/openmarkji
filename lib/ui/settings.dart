part of 'app.dart';

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({required this.store});
  final AppStore store;
  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  bool _working = false;
  Future<void> _backupTask(Future<void> Function() callback) async {
    if (_working) return;
    setState(() => _working = true);
    await _action(context, callback);
    if (mounted) setState(() => _working = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.store.preferences;
    final c = Theme.of(context).colorScheme;
    return _Page(
      title: '让这里，更像你',
      subtitle: 'PREFERENCES',
      children: [
        _Panel(
          child: Row(
            children: [
              const _BrandMark(size: 56),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'OpenMarkji',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '知识属于你，记忆也是。',
                      style: TextStyle(color: c.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const _Pill('本地优先'),
            ],
          ),
        ),
        const _SectionLabel('外观与阅读'),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('主题模式', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'system',
                      icon: Icon(Icons.brightness_auto_outlined),
                      label: Text('系统'),
                    ),
                    ButtonSegment(
                      value: 'light',
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('浅色'),
                    ),
                    ButtonSegment(
                      value: 'dark',
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('深色'),
                    ),
                  ],
                  selected: {p.theme},
                  onSelectionChanged: (s) => _action(context, () async {
                    p.theme = s.first;
                    await widget.store.savePreferences();
                  }),
                ),
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('跟随系统动态取色'),
                subtitle: const Text(
                  '支持动态取色的 Android 设备生效',
                  style: TextStyle(fontSize: 12),
                ),
                value: p.dynamicColor,
                onChanged: (v) => _action(context, () async {
                  p.dynamicColor = v;
                  await widget.store.savePreferences();
                }),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children:
                    [0xff5479bc, 0xff49776a, 0xff8f6594, 0xff9b6a45, 0xff526b7a]
                        .map(
                          (value) => Semantics(
                            button: true,
                            label: '主题色 ${value.toRadixString(16)}',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(50),
                              onTap: () => _action(context, () async {
                                p.color = value;
                                p.dynamicColor = false;
                                await widget.store.savePreferences();
                              }),
                              child: CircleAvatar(
                                radius: 22,
                                backgroundColor: Color(value),
                                child: p.color == value
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Text('卡片阅读字号'),
                  const Spacer(),
                  Text('${p.fontSize.round()}'),
                ],
              ),
              Slider(
                value: p.fontSize,
                min: 14,
                max: 30,
                divisions: 8,
                onChanged: (v) => setState(() => p.fontSize = v),
                onChangeEnd: (_) =>
                    _action(context, widget.store.savePreferences),
              ),
              Text(
                '在恰当的时间，想起重要的事。',
                style: TextStyle(fontSize: p.fontSize, height: 1.7),
              ),
            ],
          ),
        ),
        const _SectionLabel('学习偏好'),
        _Panel(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.auto_stories_outlined),
                title: const Text('新牌组每日新学上限'),
                subtitle: const Text(
                  '已创建牌组请在各自设置中修改',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: Text('${p.defaultLimit} 张'),
                onTap: () => _action(context, () async {
                  final value = await _textPrompt(
                    context,
                    '默认每日新学上限',
                    initial: '${p.defaultLimit}',
                  );
                  if (value == null) return;
                  final n = int.tryParse(value);
                  if (n == null || n < 0) {
                    throw const FormatException('请输入非负整数');
                  }
                  p.defaultLimit = n;
                  await widget.store.savePreferences();
                }),
              ),
              const ListTile(
                leading: Icon(Icons.psychology_outlined),
                title: Text('先复习，再学习'),
                subtitle: Text(
                  '首次评分决定长期排期；当日重学单独记录。',
                  style: TextStyle(fontSize: 12, height: 1.6),
                ),
              ),
            ],
          ),
        ),
        const _SectionLabel('资料与备份'),
        _Panel(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              ListTile(
                enabled: !_working,
                leading: const Icon(Icons.save_alt_rounded),
                title: const Text('导出完整备份'),
                subtitle: const Text(
                  '包含卡片、图片、学习记录和设置',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _backupTask(() async {
                  await _saveBytes(
                    'OpenMarkji-${dayKey(DateTime.now())}.zip',
                    await widget.store.backup(),
                  );
                }),
              ),
              ListTile(
                enabled: !_working,
                leading: const Icon(Icons.restore_page_outlined),
                title: const Text('从备份恢复'),
                subtitle: const Text(
                  '替换当前资料，恢复前保留一份旧数据',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _backupTask(() async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['zip'],
                    withData: true,
                  );
                  final bytes = result?.files.firstOrNull?.bytes;
                  if (bytes == null || !context.mounted) return;
                  if (!await _confirm(
                    context,
                    '恢复这份备份？',
                    '当前资料将被替换。恢复前的数据会保留在“导出恢复前的资料”中。',
                  )) {
                    return;
                  }
                  await widget.store.restore(bytes);
                  if (context.mounted) _toast(context, '已恢复资料、图片和学习进度');
                }),
              ),
              _Load(
                future: widget.store
                    .setting('recoveryBackup')
                    .then((s) => s != null),
                builder: (exists) => !exists
                    ? const SizedBox.shrink()
                    : ListTile(
                        enabled: !_working,
                        leading: const Icon(Icons.history_rounded),
                        title: const Text('导出恢复前的资料'),
                        onTap: () => _backupTask(() async {
                          final saved = await widget.store.setting(
                            'recoveryBackup',
                          );
                          if (saved != null) {
                            await _saveBytes(
                              'OpenMarkji-before-restore.zip',
                              base64Decode(saved),
                            );
                          }
                        }),
                      ),
              ),
              if (_working)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
        const _SectionLabel('关于'),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'OpenMarkji · 1.0',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                '离线使用，无需账号。\nMMX-5 / MMX-6 沿用项目已有实现及默认参数。\n墨墨文本支持文字、公式、图片和挖空；外部媒体 ID 需要对应资源。',
                style: TextStyle(
                  color: c.onSurfaceVariant,
                  height: 1.8,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'OpenMarkji',
                  applicationVersion: '1.0.0',
                ),
                child: const Text('开源许可'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
