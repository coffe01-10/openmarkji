part of 'app.dart';

class _AboutPage extends StatelessWidget {
  const _AboutPage();
  @override
  Widget build(BuildContext context) => _SettingsDetail(
    title: '关于',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Column(
            children: [
              Icon(
                Icons.auto_stories_rounded,
                size: 54,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 14),
              const Text(
                'OpenMarkji',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text('$appDisplayVersion ($appBuild) · 离线记忆，慢慢积累'),
            ],
          ),
        ),
        _AppearanceCard(
          child: Column(
            children: [
              _supportTile(
                Icons.system_update_alt_rounded,
                '检查更新',
                () => _push(context, const _UpdatePage()),
                subtitle: '当前版本 $appDisplayVersion',
              ),
              _supportTile(
                Icons.verified_user_outlined,
                '协议与政策',
                () => _push(context, const _PoliciesPage()),
              ),
              _supportTile(
                Icons.help_outline_rounded,
                '帮助与反馈',
                () => _push(context, const _HelpPage()),
              ),
              _supportTile(
                Icons.code_rounded,
                '开源许可',
                () => showLicensePage(
                  context: context,
                  applicationName: 'OpenMarkji',
                  applicationVersion: appDisplayVersion,
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            '无需账号，本地保存。\n编写卡片、安排学习，让知识慢慢积累。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.8),
          ),
        ),
      ],
    ),
  );
}

Widget _supportTile(
  IconData icon,
  String title,
  VoidCallback onTap, {
  String? subtitle,
}) => ListTile(
  leading: Icon(icon, size: 22),
  title: Text(title),
  subtitle: subtitle == null ? null : Text(subtitle),
  trailing: const Icon(Icons.chevron_right_rounded),
  onTap: onTap,
);

class _UpdatePage extends StatefulWidget {
  const _UpdatePage();
  @override
  State<_UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<_UpdatePage> {
  bool _checking = false;
  String _message = releaseFeed.isEmpty
      ? '此构建尚未配置更新源，暂时无法在线检查。'
      : '点击下方按钮检查新版本。';
  AppRelease? _release;
  Future<void> _check() async {
    if (releaseFeed.isEmpty) {
      setState(() => _message = '此构建尚未配置更新源，暂时无法在线检查。请留意应用提供者发布的新版本。');
      return;
    }
    setState(() {
      _checking = true;
      _release = null;
    });
    try {
      final result = await AppRelease.check(Uri.parse(releaseFeed));
      if (mounted) {
        setState(() {
          _release = result;
          _message = result.isNewer ? '发现新版本 ${result.version}' : '当前已是最新版本';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = '检查失败，请确认网络连接后重试。');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => _SettingsDetail(
    title: '检查更新',
    child: _AppearanceCard(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.system_update_alt_rounded,
              size: 44,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            const Text(
              'OpenMarkji $appDisplayVersion',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            Text(
              _message,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.6),
            ),
            if (_release?.notes.isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_release!.notes),
              ),
            const SizedBox(height: 24),
            if (_checking)
              const LinearProgressIndicator()
            else
              FilledButton(onPressed: _check, child: const Text('检查更新')),
            if (_release?.isNewer ?? false)
              TextButton(
                onPressed: () => _action(context, () async {
                  if (!await launchUrl(
                    _release!.download,
                    mode: LaunchMode.externalApplication,
                  )) {
                    throw Exception('无法打开下载页面');
                  }
                }),
                child: const Text('前往下载'),
              ),
          ],
        ),
      ),
    ),
  );
}

class _PoliciesPage extends StatelessWidget {
  const _PoliciesPage();
  @override
  Widget build(BuildContext context) => _SettingsDetail(
    title: '协议与政策',
    child: Column(
      children: [
        _AppearanceCard(
          child: Column(
            children: [
              _supportTile(
                Icons.privacy_tip_outlined,
                '隐私与数据说明',
                () => _push(
                  context,
                  const _InformationPage(
                    title: '隐私与数据说明',
                    sections: [
                      (
                        '本地保存',
                        '卡片、图片、学习记录和偏好设置保存在当前设备或浏览器的本地存储中，无需注册账号。当前版本没有内置广告或统计上报。',
                      ),
                      (
                        '你主动使用的联网功能',
                        '卡片中的外部链接和远程图片可能连接对应网站。点击检查更新时，应用会请求版本信息。WebDAV 仅在你主动连接、备份或恢复时访问所填服务器；上传的是完整备份，连接密码仅保存在本机，不随备份导出。',
                      ),
                      (
                        '备份与反馈',
                        '导出的备份包含卡片、媒体和学习记录，请自行保管。反馈报告只含版本、平台及你填写的问题，复制或导出后由你决定如何分享。',
                      ),
                      ('删除数据', '你可以在牌组中删除卡片或牌组。卸载应用或清除网站数据可能移除本地资料，操作前请先导出备份。'),
                    ],
                  ),
                ),
              ),
              _supportTile(
                Icons.description_outlined,
                '使用说明与条款',
                () => _push(
                  context,
                  const _InformationPage(
                    title: '使用说明与条款',
                    sections: [
                      (
                        '应用用途',
                        'OpenMarkji 提供个人制卡、学习计划、记忆调度和学习统计。学习效果取决于内容与使用方式，排期仅作为学习辅助。',
                      ),
                      (
                        '资料与备份',
                        '请确保你有权使用导入或分享的资料。应用使用本地存储，请定期备份；恢复备份会替换当前资料，并保留一份恢复前的数据供导出。',
                      ),
                      (
                        '开源许可',
                        'GNU General Public License v3.0（GPL-3.0）是自由软件许可证。协议原文可在“关于 → 开源许可 → GPL-3.0”中查看。',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _InformationPage extends StatelessWidget {
  const _InformationPage({required this.title, required this.sections});
  final String title;
  final List<(String, String)> sections;
  @override
  Widget build(BuildContext context) => _SettingsDetail(
    title: title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in sections) ...[
          _AppearanceHeader(section.$1, Icons.notes_rounded),
          _AppearanceCard(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                section.$2,
                style: const TextStyle(height: 1.8),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _HelpPage extends StatelessWidget {
  const _HelpPage();
  @override
  Widget build(BuildContext context) => _SettingsDetail(
    title: '帮助与反馈',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AppearanceHeader('开始使用', Icons.lightbulb_outline_rounded),
        _AppearanceCard(
          child: Column(
            children: [
              for (final item in const [
                (
                  '如何加练重点和难卡？',
                  '点亮卡片的星标可以收藏重点。在牌组中选择收藏或难卡筛选，再点击右上角的专项练习。难卡依据最近一次正式评分，专项练习不改变每日任务和正式排期，进度会自动保存。',
                ),
                (
                  '如何开始学习？',
                  '先新建牌组，写卡片或导入文本。在牌组内勾选卡片并加入计划，再到今日页开始学习。仅导入的资料不会自动进入每日任务。',
                ),
                (
                  '如何设置每日学习量？',
                  '学习偏好中的上限用于新建牌组。已有牌组请打开牌组设置，单独调整每日新学上限；到期复习会优先安排。',
                ),
                (
                  '忘记和模糊有什么区别？',
                  '请按真实回忆情况评分。首次评分决定长期排期；忘记或模糊的卡还会进入当日重学。学习偏好可以调整重学间隔。',
                ),
                (
                  '如何导入卡片？',
                  '打开牌组中的导入，粘贴文本或选择 TXT。问题和答案之间用单独一行 --- 分隔；卡片之间的分隔方式可在导入时选择并预览。',
                ),
                (
                  '如何迁移和恢复资料？',
                  '在资料与备份中导出 ZIP，再在另一设备恢复。恢复会替换资料，请先备份；恢复前的旧资料仍可导出。',
                ),
              ])
                ExpansionTile(
                  title: Text(item.$1),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(item.$2, style: const TextStyle(height: 1.7)),
                  ],
                ),
            ],
          ),
        ),
        _AppearanceHeader('反馈', Icons.chat_bubble_outline_rounded),
        _AppearanceCard(
          child: _supportTile(
            Icons.edit_note_rounded,
            '问题反馈与功能建议',
            () => _push(context, const _FeedbackPage()),
            subtitle: '填写问题，复制或导出反馈报告',
          ),
        ),
      ],
    ),
  );
}

class _FeedbackPage extends StatefulWidget {
  const _FeedbackPage();
  @override
  State<_FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<_FeedbackPage> {
  final _description = TextEditingController();
  String _kind = 'bug';
  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  String get _report =>
      '# OpenMarkji 反馈\n\n类型：${_kind == 'bug' ? '问题反馈' : '功能建议'}\n版本：$appDisplayVersion ($appBuild)\n平台：${kIsWeb ? 'Web' : defaultTargetPlatform.name}\n\n${_description.text.trim()}\n';
  @override
  Widget build(BuildContext context) => _SettingsDetail(
    title: '问题反馈与功能建议',
    child: _AppearanceCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AppearanceMenu(
              title: '反馈类型',
              value: _kind,
              options: const {'bug': '问题反馈', 'idea': '功能建议'},
              onChanged: (v) => setState(() => _kind = v),
            ),
            TextField(
              controller: _description,
              minLines: 6,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: '问题描述',
                hintText: '发生了什么？\n如何重现？\n你期望的结果是什么？',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            const Text(
              '当前尚未接入在线反馈服务。报告包含版本和平台，不包含卡片或学习记录。你可以复制或导出后交给应用提供者。',
              style: TextStyle(fontSize: 12, height: 1.7),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _description.text.trim().isEmpty
                  ? null
                  : () => _action(context, () async {
                      await Clipboard.setData(ClipboardData(text: _report));
                      if (context.mounted) _toast(context, '已复制反馈报告');
                    }),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('复制反馈报告'),
            ),
            TextButton.icon(
              onPressed: _description.text.trim().isEmpty
                  ? null
                  : () => _action(context, () async {
                      await _saveBytes(
                        'OpenMarkji-feedback.md',
                        Uint8List.fromList(utf8.encode(_report)),
                      );
                    }),
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('导出反馈报告'),
            ),
          ],
        ),
      ),
    ),
  );
}
