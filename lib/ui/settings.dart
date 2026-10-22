part of 'app.dart';

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = <({IconData icon, String title, Widget page})>[
      (
        icon: Icons.brush_outlined,
        title: '外观与阅读',
        page: _AppearancePage(store: store),
      ),
      (
        icon: Icons.auto_stories_outlined,
        title: '学习偏好',
        page: _StudyPrefsPage(store: store),
      ),
      (
        icon: Icons.cloud_outlined,
        title: '资料与备份',
        page: _BackupPage(store: store),
      ),
      (icon: Icons.info_outline, title: '关于', page: const _AboutPage()),
    ];
    return ColoredBox(
      color: _settingsCanvas(scheme),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 132),
            children: [
              Text(
                '设置',
                style: TextStyle(
                  fontSize: 34,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: scheme.onSurface,
                ),
              ),
              for (final group in [
                (title: '偏好设置', items: entries.take(3).toList()),
                (title: '更多', items: entries.skip(3).toList()),
              ]) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
                  child: Text(
                    group.title,
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < group.items.length; i++)
                      _SettingsLink(
                        icon: group.items[i].icon,
                        title: group.items[i].title,
                        page: group.items[i].page,
                        radius: _settingsRowRadius(i, group.items.length),
                        divided: i != group.items.length - 1,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

const _settingsCorner = 28.0;

Color _settingsCanvas(ColorScheme scheme) =>
    scheme.brightness == Brightness.light
    ? scheme.surfaceContainer
    : scheme.surface;

Color _settingsCard(ColorScheme scheme) => scheme.brightness == Brightness.light
    ? scheme.surfaceContainerLowest
    : scheme.surfaceContainerHigh;

BorderRadius _settingsRowRadius(int index, int length) {
  const corner = Radius.circular(_settingsCorner);
  if (length == 1) return const BorderRadius.all(corner);
  if (index == 0) return const BorderRadius.vertical(top: corner);
  if (index == length - 1) return const BorderRadius.vertical(bottom: corner);
  return BorderRadius.zero;
}

class _SettingsLink extends StatefulWidget {
  const _SettingsLink({
    required this.icon,
    required this.title,
    required this.page,
    required this.radius,
    required this.divided,
  });

  final IconData icon;
  final String title;
  final Widget page;
  final BorderRadius radius;
  final bool divided;

  @override
  State<_SettingsLink> createState() => _SettingsLinkState();
}

class _SettingsLinkState extends State<_SettingsLink> {
  final _key = GlobalKey();
  double? _holdHeight;

  Rect? _measure() {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    final navigator = Navigator.maybeOf(context)?.context.findRenderObject();
    if (box == null ||
        navigator is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        !navigator.attached) {
      return null;
    }
    return MatrixUtils.transformRect(
      box.getTransformTo(navigator),
      Offset.zero & box.size,
    );
  }

  Widget _tile({VoidCallback? onTap}) => _SettingsTile(
    icon: widget.icon,
    title: widget.title,
    radius: widget.radius,
    divided: widget.divided,
    onTap: onTap,
  );

  Future<void> _open() async {
    final rect = _measure();
    if (rect == null || rect.width <= 0 || rect.height <= 0) {
      await _push(context, widget.page);
      return;
    }
    HapticFeedback.selectionClick();
    final closed = _tile();
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 300);
    setState(() => _holdHeight = rect.height);
    final route = _RowExpandRoute(
      source: rect,
      closedRadius: widget.radius,
      closed: closed,
      page: widget.page,
      transition: motion,
    );
    await Navigator.of(context).push(route);
    // push 的 Future 在开始返回时完成；此时动画中的行仍然可见。
    await route.completed;
    if (mounted) setState(() => _holdHeight = null);
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _key,
      child: _holdHeight == null
          ? _tile(onTap: _open)
          : SizedBox(height: _holdHeight),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.radius,
    required this.divided,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final BorderRadius radius;
  final bool divided;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedSuperellipseBorder(borderRadius: radius);
    return Material(
      color: _settingsCard(scheme),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              child: Row(
                children: [
                  Icon(icon, size: 22, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
            if (divided)
              Positioned(
                left: 54,
                right: 16,
                bottom: 0,
                child: ColoredBox(
                  color: scheme.outlineVariant.withValues(alpha: .55),
                  child: const SizedBox(height: 0.6),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 行矩形展开到整页。节奏对齐 FlClash `_OpenContainerRoute`：300ms，
/// fastOutSlowIn；打开页在进入的 0.2-0.4 淡入，返回时在 0.8-0.6 淡出。
class _RowExpandRoute extends PageRoute<void> {
  _RowExpandRoute({
    required this.source,
    required this.closedRadius,
    required this.closed,
    required this.page,
    required this.transition,
  });

  final Rect source;
  final BorderRadius closedRadius;
  final Widget closed;
  final Widget page;
  final Duration transition;

  @override
  Duration get transitionDuration => transition;

  @override
  bool get opaque => true;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => page;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _RowExpandTransition(
      animation: animation,
      source: source,
      closedRadius: closedRadius,
      closed: closed,
      open: child,
    );
  }
}

class _RowExpandTransition extends StatelessWidget {
  const _RowExpandTransition({
    required this.animation,
    required this.source,
    required this.closedRadius,
    required this.closed,
    required this.open,
  });

  final Animation<double> animation;
  final Rect source;
  final BorderRadius closedRadius;
  final Widget closed;
  final Widget open;

  double _progress() {
    final t = animation.value;
    if (t == 0 || t == 1) return t;
    final curve = animation.status == AnimationStatus.reverse
        ? Curves.fastOutSlowIn.flipped
        : Curves.fastOutSlowIn;
    return curve.transform(t);
  }

  double _fade() {
    if (animation.value == 1) return 1;
    final start = animation.status == AnimationStatus.reverse ? 0.6 : 0.2;
    return ((animation.value - start) / 0.2).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
              return open;
            }
            final full = Offset.zero & constraints.biggest;
            final progress = _progress();
            final rect = Rect.lerp(source, full, progress)!;
            final radius = BorderRadius.lerp(
              closedRadius,
              BorderRadius.zero,
              progress,
            )!;
            final fade = _fade();
            final shape = RoundedSuperellipseBorder(borderRadius: radius);
            final scale = source.width == 0 ? 1.0 : rect.width / source.width;
            return Stack(
              fit: StackFit.expand,
              children: [
                const Positioned.fill(
                  child: ModalBarrier(
                    color: Colors.transparent,
                    dismissible: false,
                  ),
                ),
                Positioned.fromRect(
                  rect: rect,
                  child: ClipPath(
                    clipper: ShapeBorderClipper(shape: shape),
                    child: ColoredBox(
                      color: _settingsCard(Theme.of(context).colorScheme),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          OverflowBox(
                            alignment: Alignment.topLeft,
                            minWidth: source.width,
                            maxWidth: source.width,
                            minHeight: source.height,
                            maxHeight: source.height,
                            child: Transform.scale(
                              alignment: Alignment.topLeft,
                              scale: scale,
                              child: ExcludeFocus(
                                child: ExcludeSemantics(
                                  child: IgnorePointer(child: closed),
                                ),
                              ),
                            ),
                          ),
                          OverflowBox(
                            alignment: Alignment.topLeft,
                            minWidth: full.width,
                            maxWidth: full.width,
                            minHeight: full.height,
                            maxHeight: full.height,
                            child: IgnorePointer(
                              ignoring: fade == 0,
                              child: Opacity(opacity: fade, child: open),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _SettingsDetail extends StatelessWidget {
  const _SettingsDetail({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final background = _settingsCard(Theme.of(context).colorScheme);
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        title: Text(title),
        leading: _appearanceBack(context),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
            children: [child],
          ),
        ),
      ),
    );
  }
}

class _StudyPrefsPage extends StatefulWidget {
  const _StudyPrefsPage({required this.store});
  final AppStore store;
  @override
  State<_StudyPrefsPage> createState() => _StudyPrefsPageState();
}

class _StudyPrefsPageState extends State<_StudyPrefsPage> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.store.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.store.preferences;
    return _SettingsDetail(
      title: '学习偏好',
      child: _Panel(
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
    );
  }
}

class _BackupPage extends StatefulWidget {
  const _BackupPage({required this.store});
  final AppStore store;
  @override
  State<_BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<_BackupPage> {
  bool _working = false;

  Future<void> _backupTask(Future<void> Function() callback) async {
    if (_working) return;
    setState(() => _working = true);
    await _action(context, callback);
    if (mounted) setState(() => _working = false);
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsDetail(
      title: '资料与备份',
      child: _Panel(
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
    );
  }
}

class _AboutPage extends StatelessWidget {
  const _AboutPage();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return _SettingsDetail(
      title: '关于',
      child: _Panel(
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
    );
  }
}
