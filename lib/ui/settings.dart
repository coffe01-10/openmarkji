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
        icon: Icons.touch_app_outlined,
        title: '卡片与交互',
        page: _StudyPrefsPage(store: store, interaction: true),
      ),
      (
        icon: Icons.cloud_outlined,
        title: '资料与备份',
        page: _BackupPage(store: store),
      ),
      (
        icon: Icons.help_outline_rounded,
        title: '帮助与反馈',
        page: const _HelpPage(),
      ),
      (icon: Icons.info_outline, title: '关于', page: const _AboutPage()),
    ];
    return ColoredBox(
      color: _settingsCanvas(scheme),
      child: _PinnedPage(
        backgroundColor: _settingsCanvas(scheme),
        title: '设置',
        maxWidth: 720,
        horizontalPadding: 16,
        children: [
          for (final group in [
            (title: '偏好设置', items: entries.take(4).toList()),
            (title: '更多', items: entries.skip(4).toList()),
          ]) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
              child: Text(
                group.title,
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
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
    );
  }
}

Route<dynamic>? _topRoute(NavigatorState navigator) {
  Route<dynamic>? top;
  navigator.popUntil((route) {
    top = route;
    return true;
  });
  return top;
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
  Animation<double>? _closing;
  late final _restoreRow = _restoreCoveredRow;

  @override
  void dispose() {
    _closing?.removeListener(_restoreRow);
    super.dispose();
  }

  /// 收回接近原位时，卡片仍然盖住这一行。先放回真实行，
  /// 展开层卸掉的那一帧下面就有内容，不会露出空白。
  void _restoreCoveredRow() {
    final animation = _closing;
    if (animation == null ||
        animation.status != AnimationStatus.reverse ||
        animation.value > .08) {
      return;
    }
    animation.removeListener(_restoreRow);
    _closing = null;
    if (mounted && _holdHeight != null) setState(() => _holdHeight = null);
  }

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
    final disabled = MediaQuery.disableAnimationsOf(context);
    setState(() => _holdHeight = rect.height);
    final navigator = Navigator.of(context);
    // 同一帧里先 pop 再 push 会让 Flutter 丢掉正在进行的过渡。
    // 延后一帧再展开下一行，上一段才能反向收回并与新的展开重叠。
    final top = _topRoute(navigator);
    final transitioning =
        top is _RowExpandRoute && top.animation?.isCompleted == false;
    if (transitioning && top.animation?.status == AnimationStatus.forward) {
      navigator.pop();
    }
    if (transitioning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pushExpand(navigator, closed, rect, disabled);
      });
      return;
    }
    await _pushExpand(navigator, closed, rect, disabled);
  }

  Future<void> _pushExpand(
    NavigatorState navigator,
    Widget closed,
    Rect rect,
    bool disabled,
  ) async {
    final route = _RowExpandRoute(
      source: rect,
      closedRadius: widget.radius,
      closed: closed,
      page: widget.page,
      transition: disabled ? Duration.zero : const Duration(milliseconds: 300),
    );
    await navigator.push(route);
    _closing = route.animation?..addListener(_restoreRow);
    // push 的 Future 在开始返回时完成；此时动画中的行仍然可见。
    await route.completed;
    _closing?.removeListener(_restoreRow);
    _closing = null;
    if (mounted && _holdHeight != null) setState(() => _holdHeight = null);
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

/// 行矩形展开到整页。沿用 GPL-3.0 上游 `_OpenContainerRoute` 的节奏：300ms，
/// fastOutSlowIn；打开页在进入的 0.2-0.4 淡入，返回时在 0.8-0.6 淡出。
/// 连续点另一行时，旧路由反向收起和新路由正向展开同时进行。
class _RowExpandRoute extends PageRoute<void> {
  _RowExpandRoute({
    required this.source,
    required this.closedRadius,
    required this.closed,
    required this.page,
    required this.transition,
  }) : _snapshot = SnapshotController(
         allowSnapshotting: transition > Duration.zero,
       ),
       super(settings: RouteSettings(name: _pageName(page)));

  final Rect source;
  final BorderRadius closedRadius;
  final Widget closed;
  final Widget page;
  final Duration transition;
  late final SnapshotController _snapshot;

  /// 进场第一帧路由会把代理动画临时标成完成，用来离屏排版。
  /// 快照要跟控制器的真实进度走，不能跟这个临时状态走。
  void _syncSnapshot() {
    final controller = super.animation;
    final moving =
        transition > Duration.zero &&
        controller != null &&
        controller.status.isAnimating &&
        controller.value > 0 &&
        controller.value < 1;
    if (_snapshot.allowSnapshotting != moving) {
      _snapshot.allowSnapshotting = moving;
    }
  }

  /// 上一段动画的方向。中途被反向打断时，曲线要沿用打断前的方向，
  /// 沿用上游 `_transitionWasInterrupted`：只有完整走完再折返才换曲线。
  AnimationStatus? _lastStatus;
  AnimationStatus? _currentStatus;

  bool get closing {
    final animation = this.animation;
    if (animation == null) return false;
    final interrupted =
        (_lastStatus?.isAnimating ?? false) &&
        (_currentStatus?.isAnimating ?? false);
    return animation.status == AnimationStatus.reverse && !interrupted;
  }

  @override
  Duration get transitionDuration => transition;

  @override
  Duration get reverseTransitionDuration => transition;

  @override
  bool get opaque => true;

  @override
  TickerFuture didPush() {
    animation!.addStatusListener((status) {
      _lastStatus = _currentStatus;
      _currentStatus = status;
    });
    super.animation!.addListener(_syncSnapshot);
    // 监听要先于首次 forward，中途折返才能认出上一段仍在播放。
    return super.didPush();
  }

  @override
  void dispose() {
    super.animation?.removeListener(_syncSnapshot);
    _snapshot.dispose();
    super.dispose();
  }

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  /// 默认遮罩会铺满整页并吃掉点击。展开途中只由卡片本身接点击。
  @override
  Widget buildModalBarrier() => const SizedBox.shrink();

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
      route: this,
      animation: animation,
      source: source,
      closedRadius: closedRadius,
      closed: closed,
      open: SnapshotWidget(controller: _snapshot, child: child),
    );
  }
}

class _RowExpandTransition extends StatelessWidget {
  const _RowExpandTransition({
    required this.route,
    required this.animation,
    required this.source,
    required this.closedRadius,
    required this.closed,
    required this.open,
  });

  final _RowExpandRoute route;
  final Animation<double> animation;
  final Rect source;
  final BorderRadius closedRadius;
  final Widget closed;
  final Widget open;

  double _progress() {
    final t = animation.value;
    if (t == 0 || t == 1) return t;
    final curve = route.closing
        ? Curves.fastOutSlowIn.flipped
        : Curves.fastOutSlowIn;
    return curve.transform(t);
  }

  double _fade() {
    if (animation.value == 1 && !route.closing) return 1;
    final start = route.closing ? 0.6 : 0.2;
    return ((animation.value - start) / 0.2).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: RepaintBoundary(child: open),
      builder: (context, openPage) {
        return LayoutBuilder(
          builder: (context, constraints) {
            if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
              return openPage!;
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
            // 卡片还没铺满时不接点击，下面被盖住的行仍能点到。
            return IgnorePointer(
              ignoring: progress < 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (progress >= 1)
                    const Positioned.fill(
                      child: ModalBarrier(
                        color: Colors.transparent,
                        dismissible: false,
                      ),
                    ),
                  Positioned.fromRect(
                    rect: rect,
                    child: ClipPath(
                      clipBehavior: progress == 1 ? Clip.none : Clip.antiAlias,
                      clipper: ShapeBorderClipper(shape: shape),
                      child: ColoredBox(
                        color: _settingsCard(Theme.of(context).colorScheme),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            const Positioned.fill(
                              child: AbsorbPointer(child: SizedBox.expand()),
                            ),
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
                                    child: Offstage(
                                      offstage: fade == 1,
                                      child: RepaintBoundary(
                                        child: IgnorePointer(child: closed),
                                      ),
                                    ),
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
                                child: Opacity(opacity: fade, child: openPage),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
    final background = _settingsCanvas(Theme.of(context).colorScheme);
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        clipBehavior: Clip.none,
        backgroundColor: background,
        title: Text(title),
        leading: _appearanceBack(context),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [child],
          ),
        ),
      ),
    );
  }
}

class _StudyPrefsPage extends StatefulWidget {
  const _StudyPrefsPage({required this.store, this.interaction = false});
  final AppStore store;
  final bool interaction;
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
      title: widget.interaction ? '卡片与交互' : '学习偏好',
      child: Column(
        children: [
          if (!widget.interaction) _AlgorithmPlanSection(store: widget.store),
          _AppearanceCard(
            child: Column(
              children: [
                if (widget.interaction) ...[
                  SwitchListTile(
                    title: const Text('学习触感反馈'),
                    subtitle: const Text('揭晓答案时轻触振动'),
                    value: p.studyHaptics,
                    onChanged: (v) => _action(context, () async {
                      p.studyHaptics = v;
                      await widget.store.savePreferences();
                    }),
                  ),
                  SwitchListTile(
                    title: const Text('显示学习进度'),
                    subtitle: const Text('显示已完成数量、剩余数量和进度条'),
                    value: p.showStudyProgress,
                    onChanged: (v) => _action(context, () async {
                      p.showStudyProgress = v;
                      await widget.store.savePreferences();
                    }),
                  ),
                  SwitchListTile(
                    title: const Text('显示回忆提示'),
                    subtitle: const Text('揭晓前提示先在心里回忆答案'),
                    value: p.showRecallHint,
                    onChanged: (v) => _action(context, () async {
                      p.showRecallHint = v;
                      await widget.store.savePreferences();
                    }),
                  ),
                ] else ...[
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
                  _AppearanceMenu(
                    title: '当日重学间隔',
                    value: '${p.relearnGap}',
                    options: const {
                      '1': '间隔 1 张',
                      '3': '间隔 3 张',
                      '5': '间隔 5 张',
                      '10': '间隔 10 张',
                    },
                    onChanged: (v) => _action(context, () async {
                      p.relearnGap = int.parse(v);
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
              ],
            ),
          ),
        ],
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
      child: Column(
        children: [
          _AppearanceCard(
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
          const SizedBox(height: 16),
          _AppearanceCard(
            child: ListTile(
              enabled: !_working,
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('WebDAV 备份'),
              subtitle: const Text(
                '连接服务器，上传或恢复完整备份',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(context, _WebDavPage(store: widget.store)),
            ),
          ),
        ],
      ),
    );
  }
}
