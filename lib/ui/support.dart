part of 'app.dart';

class _AboutPage extends StatelessWidget {
  const _AboutPage();

  void _licenses(BuildContext context) => showLicensePage(
    context: context,
    applicationName: 'OpenMarkji',
    applicationVersion: appDisplayVersion,
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _SettingsDetail(
      title: '关于',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Column(
              children: [
                const _BrandMark(size: 96),
                const SizedBox(height: 20),
                const Text(
                  'OpenMarkji',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.5,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _AboutPill(
                      label: 'v$appDisplayVersion',
                      background: colors.primary,
                      foreground: colors.onPrimary,
                    ),
                    _AboutPill(
                      label: 'GPL-3.0',
                      background: colors.surfaceContainerLowest,
                      foreground: colors.onSurfaceVariant,
                      onTap: () => _licenses(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '离线优先的开源记忆卡片。\n编写、回忆、复习，让知识慢慢积累。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                _GlassGroup(
                  pill: true,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: colors.onSurface,
                      minimumSize: const Size(156, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () => showGlassDialog<void>(
                      context: context,
                      builder: (_) => const _UpdateDialog(),
                    ),
                    icon: const Icon(Icons.sync_rounded, size: 20),
                    label: const Text(
                      '检查更新',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              '更多',
              style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
            ),
          ),
          _AppearanceCard(
            child: Column(
              children: [
                _AboutEntry(
                  icon: Icons.code_rounded,
                  title: '项目主页',
                  external: true,
                  onTap: () => _action(context, () async {
                    await launchUrl(
                      Uri.parse('https://github.com/coffe01-10/openmarkji'),
                      mode: LaunchMode.externalApplication,
                    );
                  }),
                ),
                const Divider(height: 1, indent: 72, endIndent: 16),
                _AboutEntry(
                  icon: Icons.verified_user_outlined,
                  title: '协议与政策',
                  onTap: () => _push(context, const _PoliciesPage()),
                ),
                const Divider(height: 1, indent: 72, endIndent: 16),
                _AboutEntry(
                  icon: Icons.help_outline_rounded,
                  title: '帮助与反馈',
                  onTap: () => _push(context, const _HelpPage()),
                ),
                const Divider(height: 1, indent: 72, endIndent: 16),
                _AboutEntry(
                  icon: Icons.balance_rounded,
                  title: '开源许可',
                  onTap: () => _licenses(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutPill extends StatelessWidget {
  const _AboutPill({
    required this.label,
    required this.background,
    required this.foreground,
    this.onTap,
  });
  final String label;
  final Color background, foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: background,
    shape: const StadiumBorder(),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      customBorder: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
        ),
      ),
    ),
  );
}

class _AboutEntry extends StatelessWidget {
  const _AboutEntry({
    required this.icon,
    required this.title,
    required this.onTap,
    this.external = false,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool external;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: Container(
      width: 40,
      height: 40,
      decoration: ShapeDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: Icon(
        icon,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
    title: Text(title),
    trailing: Icon(
      external ? Icons.open_in_new_rounded : Icons.chevron_right_rounded,
      size: 20,
    ),
    onTap: onTap,
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

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog();
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _checking = false;
  final _installer = AppUpdateInstaller();
  bool _downloading = false, _installing = false, _cancelling = false;
  int _received = 0;
  int? _total;
  String? _downloadedPath;
  String _message = releaseFeed.isEmpty
      ? '此构建尚未配置更新源，暂时无法在线检查。'
      : '点击下方按钮检查新版本。';
  AppRelease? _release;
  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _installer.cancel();
    super.dispose();
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _cancelling = false;
      _received = 0;
      _total = null;
      _message = '正在准备安装包…';
    });
    try {
      final path = await _installer.download(
        _release!,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _received = received;
              _total = total;
              if (!_cancelling) _message = '正在下载安装包…';
            });
          }
        },
      );
      if (!mounted) return;
      if (_cancelling) {
        setState(() => _message = '下载已取消，可重新下载。');
        return;
      }
      setState(() {
        _downloadedPath = path;
        _downloading = false;
      });
      await _install();
    } on UpdateDownloadCancelled {
      if (mounted) setState(() => _message = '下载已取消，可重新下载。');
    } catch (e, stack) {
      DiagnosticLog.instance.error('下载更新', e, stack);
      if (mounted) setState(() => _message = '下载失败：$e\n可点击下方按钮重试。');
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _cancelling = false;
        });
      }
    }
  }

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _message = '下载完成，正在打开系统安装界面…';
    });
    try {
      await _installer.install(_downloadedPath!);
      if (mounted) {
        setState(() => _message = '安装包已下载，请在系统安装界面确认更新。若已返回，可再次点击安装。');
      }
    } catch (e, stack) {
      DiagnosticLog.instance.error('安装更新', e, stack);
      if (mounted) {
        setState(
          () => _message = e is PlatformException
              ? (e.message ?? '未能打开安装界面，可再次点击安装。')
              : '安装失败：$e',
        );
      }
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<void> _check() async {
    if (releaseFeed.isEmpty) {
      setState(() => _message = '此构建尚未配置更新源，暂时无法在线检查。请留意应用提供者发布的新版本。');
      return;
    }
    setState(() {
      _checking = true;
      _message = '正在检查新版本…';
      _release = null;
      _downloadedPath = null;
    });
    try {
      final result = await AppRelease.check(Uri.parse(releaseFeed));
      if (mounted) {
        setState(() {
          _release = result;
          _message = result.isNewer ? '发现新版本 ${result.version}' : '当前已是最新版本';
        });
      }
    } catch (e, stack) {
      DiagnosticLog.instance.error('检查更新', e, stack);
      if (mounted) {
        setState(() => _message = '检查失败，请确认网络连接后重试。');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final newer = _release?.isNewer ?? false;
    final offerInstall = newer && _installer.supported;
    final busy = _checking || _downloading || _installing;
    final label = _checking
        ? '检查中…'
        : _downloading
        ? '下载中…'
        : _installing
        ? '正在安装…'
        : offerInstall
        ? (_downloadedPath == null ? '下载更新' : '立即安装')
        : _release == null
        ? '重新检查'
        : '确定';
    final colors = Theme.of(context).colorScheme;
    final glass = LiquidGlassScope.of(context);
    return GlassAlertDialog(
      title: const Text('检查更新'),
      content: SizedBox(
        width: 288,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_message, style: const TextStyle(height: 1.6)),
              if (newer && (_release?.notes.isNotEmpty ?? false)) ...[
                const SizedBox(height: 16),
                Text(_release!.notes, style: const TextStyle(height: 1.6)),
              ],
              if (_downloading) ...[
                const SizedBox(height: 20),
                LinearProgressIndicator(
                  value: _total != null && _total! > 0
                      ? _received / _total!
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  _total != null && _total! > 0
                      ? '${(_received / _total! * 100).toStringAsFixed(0)}% · ${(_received / 1048576).toStringAsFixed(1)} / ${(_total! / 1048576).toStringAsFixed(1)} MB'
                      : '已下载 ${(_received / 1048576).toStringAsFixed(1)} MB',
                  style: const TextStyle(fontSize: 12),
                ),
              ] else if (_checking || _installing) ...[
                const SizedBox(height: 20),
                const LinearProgressIndicator(),
              ],
              if (offerInstall) ...[
                const SizedBox(height: 16),
                const Text(
                  '首次安装更新可能需要授权，随后由系统确认安装。',
                  style: TextStyle(fontSize: 12, height: 1.6),
                ),
              ] else if (newer) ...[
                const SizedBox(height: 16),
                const Text(
                  'Android 版支持应用内下载安装；网页版刷新后使用最新构建。',
                  style: TextStyle(fontSize: 12, height: 1.6),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: FilledButton.tonal(
                onPressed: _installing || _cancelling
                    ? null
                    : () {
                        if (_downloading) {
                          setState(() {
                            _cancelling = true;
                            _message = '正在取消下载…';
                          });
                          _installer.cancel();
                        } else {
                          Navigator.pop(context);
                        }
                      },
                style: FilledButton.styleFrom(
                  shape: const StadiumBorder(),
                  minimumSize: const Size(0, 48),
                  backgroundColor: glass ? glassFillOf(colors) : null,
                  foregroundColor: colors.onSurface,
                ),
                child: Text(_downloading ? '取消下载' : '取消'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: busy
                    ? null
                    : offerInstall
                    ? (_downloadedPath == null ? _download : _install)
                    : _release == null
                    ? _check
                    : () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  shape: const StadiumBorder(),
                  minimumSize: const Size(0, 48),
                ),
                child: Text(label, textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ],
    );
  }
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
                        '导出的备份包含卡片、媒体和学习记录，请自行保管。反馈报告包含版本、平台及你填写的问题。日志仅在你开启捕捉后记录操作摘要和异常，不会自动上传；复制或导出后由你决定如何分享。',
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
          child: Column(
            children: [
              _supportTile(
                Icons.edit_note_rounded,
                '问题反馈与功能建议',
                () => _push(context, const _FeedbackPage()),
                subtitle: '填写问题，复制或导出反馈报告',
              ),
              _supportTile(
                Icons.bug_report_outlined,
                '捕捉日志',
                () => _push(context, const _DiagnosticsPage()),
                subtitle: '记录复现步骤和异常，预览、复制或导出',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DiagnosticsPage extends StatelessWidget {
  const _DiagnosticsPage();

  @override
  Widget build(BuildContext context) {
    final log = DiagnosticLog.instance;
    return _SettingsDetail(
      title: '捕捉日志',
      child: ListenableBuilder(
        listenable: log,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AppearanceCard(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      log.capturing
                          ? '正在捕捉 · ${log.count} 条记录'
                          : '已停止 · ${log.count} 条记录',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '先开始捕捉，再返回应用复现问题，最后回到这里停止并导出。日志包含页面切换、学习任务摘要、异常和堆栈，不会自动上传。\n\n记录仅保留在本次运行中，关闭应用前请导出；再次开始会替换旧记录。错误信息可能带有文件路径或服务器地址，可在下方预览。',
                      style: TextStyle(height: 1.7),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: log.capturing ? log.stop : log.start,
                      icon: Icon(
                        log.capturing
                            ? Icons.stop_rounded
                            : Icons.fiber_manual_record_rounded,
                      ),
                      label: Text(log.capturing ? '停止捕捉' : '开始捕捉'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: log.count == 0
                          ? null
                          : () => _action(context, () async {
                              await Clipboard.setData(
                                ClipboardData(text: log.report),
                              );
                              if (context.mounted) _toast(context, '已复制诊断日志');
                            }),
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('复制日志'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: log.count == 0
                          ? null
                          : () => _action(context, () async {
                              await _saveBytes(
                                'OpenMarkji-log-${DateTime.now().millisecondsSinceEpoch}.txt',
                                Uint8List.fromList(utf8.encode(log.report)),
                              );
                            }),
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('导出日志'),
                    ),
                  ],
                ),
              ),
            ),
            if (log.count > 0) ...[
              _AppearanceHeader('日志预览', Icons.subject_rounded),
              _AppearanceCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        log.report,
                        style: const TextStyle(fontSize: 12, height: 1.6),
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: log.clear,
                  icon: const Icon(Icons.clear_all_rounded),
                  label: const Text('清空日志'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
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
      '# OpenMarkji 反馈\n\n类型：${_kind == 'bug' ? '问题反馈' : '功能建议'}\n版本：$appDisplayVersion\n平台：${kIsWeb ? 'Web' : defaultTargetPlatform.name}\n\n${_description.text.trim()}\n';
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
