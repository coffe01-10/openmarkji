part of 'app.dart';

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.child,
    this.pressed = false,
    this.pill = false,
  });
  final Widget child;
  final bool pressed;
  final bool pill;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final ShapeBorder shape = pill
        ? const StadiumBorder()
        : const RoundedSuperellipseBorder(
            borderRadius: BorderRadius.all(Radius.circular(28)),
          );
    final material = Material(
      color: LiquidGlassScope.of(context)
          ? Colors.transparent
          : c.surfaceContainerLow,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
    if (!LiquidGlassScope.of(context)) return material;
    return LiquidGlass(
      style: LiquidGlassScope.controlStyleOf(context),
      clipper: pill ? null : ShapeBorderClipper(shape: shape),
      pressed: pressed,
      child: material,
    );
  }
}

/// GPL-3.0 上游 TonalButtonGroup 的按压结构：整块玻璃共用一个弹性变换。
class _GlassGroup extends StatefulWidget {
  const _GlassGroup({required this.child, this.pill = false});
  final Widget child;
  final bool pill;
  @override
  State<_GlassGroup> createState() => _GlassGroupState();
}

class _GlassGroupState extends State<_GlassGroup> {
  int? _pointer;

  void _end(PointerEvent event) {
    if (event.pointer == _pointer) setState(() => _pointer = null);
  }

  @override
  Widget build(BuildContext context) => ElasticButton(
    enabled: !MediaQuery.disableAnimationsOf(context),
    child: Listener(
      onPointerDown: (event) {
        if (_pointer == null && event.buttons & kPrimaryButton != 0) {
          setState(() => _pointer = event.pointer);
        }
      },
      onPointerUp: _end,
      onPointerCancel: _end,
      child: _GlassSurface(
        pressed: _pointer != null,
        pill: widget.pill,
        child: widget.child,
      ),
    ),
  );
}

/// 工具栏按钮的 44 dp 胶囊；组内没有额外边距或分隔线。
class _GlassToolbar extends StatelessWidget {
  const _GlassToolbar({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => _GlassGroup(
    pill: true,
    child: IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          fixedSize: const Size.square(44),
          minimumSize: const Size.square(44),
          padding: EdgeInsets.zero,
          iconSize: 24,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          backgroundColor: Colors.transparent,
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ).merge(ElasticPress.buttonStyle),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

class _GlassChoice extends StatelessWidget {
  const _GlassChoice({
    required this.label,
    required this.onPressed,
    this.icon,
    this.selected = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: _GlassGroup(
        pill: true,
        child: AnimatedContainer(
          duration: _duration(context, 220),
          color: selected
              ? c.primaryContainer.withValues(alpha: .65)
              : Colors.transparent,
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: selected ? c.onPrimaryContainer : c.onSurface,
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: onPressed,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _ProgressPhase { idle, loading, success }

/// 保持同一块玻璃，从文字胶囊收缩为进度圆，再恢复宽度。
class _GlassProgressButton extends StatefulWidget {
  const _GlassProgressButton({
    super.key,
    required this.label,
    this.onPressed,
    required this.onComplete,
    this.onIdlePressed,
    this.idleIcon,
    this.progressId = 'enroll',
    this.successLabel = '已加入计划',
    this.enabled = true,
  });
  final String label;
  final Future<bool> Function()? onPressed;
  final ValueChanged<bool> onComplete;
  final VoidCallback? onIdlePressed;
  final IconData? idleIcon;
  final String progressId, successLabel;
  final bool enabled;
  @override
  State<_GlassProgressButton> createState() => _GlassProgressButtonState();
}

class _GlassProgressButtonState extends State<_GlassProgressButton>
    with SingleTickerProviderStateMixin {
  _ProgressPhase _phase = _ProgressPhase.idle;
  late final _morph = AnimationController(vsync: this);

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  Future<void> run([Future<bool> Function()? action]) async {
    if (_phase != _ProgressPhase.idle) return;
    _morph.duration = _duration(context, 340);
    _morph.reverseDuration = _duration(context, 420);
    setState(() => _phase = _ProgressPhase.loading);
    try {
      final operation = (action ?? widget.onPressed!)();
      await _morph.forward().orCancel;
      final success = await operation;
      if (!mounted) return;
      if (success) {
        setState(() => _phase = _ProgressPhase.success);
        await Future<void>.delayed(_duration(context, 650));
        if (!mounted) return;
      }
      await _morph.reverse().orCancel;
      setState(() => _phase = _ProgressPhase.idle);
      widget.onComplete(success);
    } on TickerCanceled {
      // 页面退出时随按钮一起结束反馈动画。
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.labelLarge!;
    final text = TextPainter(
      text: TextSpan(text: widget.label, style: textStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = widget.idleIcon == null
        ? math.max(44.0, text.width + 32)
        : 44.0;
    text.dispose();
    return Semantics(
      liveRegion: true,
      label: switch (_phase) {
        _ProgressPhase.loading => '正在${widget.label}',
        _ProgressPhase.success => widget.successLabel,
        _ => widget.label,
      },
      child: _GlassGroup(
        pill: true,
        child: AnimatedBuilder(
          animation: _morph,
          builder: (context, child) {
            final shape = Curves.easeInOutCubic.transform(_morph.value);
            return SizedBox(
              key: ValueKey('${widget.progressId}-progress'),
              width: width + (44 - width) * shape,
              height: 44,
              child: TextButton(
                onPressed: _phase == _ProgressPhase.idle && widget.enabled
                    ? widget.onIdlePressed ??
                          (widget.onPressed == null ? null : run)
                    : null,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: c.onSurface,
                  disabledForegroundColor: c.onSurface,
                ),
                child: ClipRect(
                  child: OverflowBox(
                    minWidth: width,
                    maxWidth: width,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Opacity(
                          opacity: (1 - shape * 3).clamp(0.0, 1.0),
                          child: widget.idleIcon == null
                              ? Text(widget.label, style: textStyle)
                              : Icon(widget.idleIcon),
                        ),
                        if (_phase != _ProgressPhase.idle)
                          Opacity(
                            opacity: ((shape - .5) * 2).clamp(0.0, 1.0),
                            child: AnimatedSwitcher(
                              duration: _duration(context, 280),
                              reverseDuration: _duration(context, 140),
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child:
                                        child.key ==
                                            ValueKey(
                                              '${widget.progressId}-success',
                                            )
                                        ? ScaleTransition(
                                            scale: animation.drive(
                                              Tween<double>(
                                                begin: .55,
                                                end: 1,
                                              ).chain(
                                                CurveTween(
                                                  curve: Curves.easeOutBack,
                                                ),
                                              ),
                                            ),
                                            child: child,
                                          )
                                        : child,
                                  ),
                              child: _phase == _ProgressPhase.loading
                                  ? SizedBox.square(
                                      key: ValueKey(
                                        '${widget.progressId}-loading',
                                      ),
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.primary,
                                      ),
                                    )
                                  : Icon(
                                      Icons.check_rounded,
                                      key: ValueKey(
                                        '${widget.progressId}-success',
                                      ),
                                      size: 24,
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 分段栏直接复用导航的玻璃透镜、按住滑动和回弹。
class _GlassSegments<T> extends StatelessWidget {
  const _GlassSegments({
    required this.options,
    required this.value,
    required this.onChanged,
    this.stretch = false,
  });
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool stretch;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final entries = options.entries.toList();
      const style = TextStyle(
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w500,
      );
      var widest = 0.0;
      var lineHeight = 0.0;
      for (final entry in entries) {
        final painter = TextPainter(
          text: TextSpan(text: entry.value, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        widest = math.max(widest, painter.width);
        lineHeight = math.max(lineHeight, painter.height);
        painter.dispose();
      }
      final cellWidth = math.max(48.0, widest + 28);
      final available = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : cellWidth * entries.length + 8;
      final columns = ((available - 8) / cellWidth).floor().clamp(
        1,
        entries.length,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var start = 0; start < entries.length; start += columns)
            Padding(
              padding: EdgeInsets.only(top: start == 0 ? 0 : 8),
              child: SizedBox(
                width: stretch
                    ? available
                    : math.min(
                        available,
                        cellWidth * math.min(columns, entries.length - start) +
                            8,
                      ),
                height: math.max(44, lineHeight + 20) + 8,
                child: Builder(
                  builder: (context) {
                    final row = entries.sublist(
                      start,
                      math.min(start + columns, entries.length),
                    );
                    return FloatingNavigationBar(
                      key: ValueKey(row.first.key),
                      labelsOnly: true,
                      destinations: [
                        for (final entry in row)
                          NavigationDockDestination(
                            glyph: Icons.circle,
                            label: entry.value,
                          ),
                      ],
                      selectedIndex: row.indexWhere(
                        (entry) => entry.key == value,
                      ),
                      onSelected: (index) => onChanged(row[index].key),
                    );
                  },
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _GlassSearchField extends StatefulWidget {
  const _GlassSearchField({
    required this.hint,
    required this.onChanged,
    this.dense = false,
  });
  final String hint;
  final ValueChanged<String> onChanged;
  final bool dense;
  @override
  State<_GlassSearchField> createState() => _GlassSearchFieldState();
}

class _GlassSearchFieldState extends State<_GlassSearchField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
  }

  void _refresh() {
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.removeListener(_refresh);
    _focus.dispose();
    super.dispose();
  }

  void _changed(String value) {
    setState(() {});
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final glass = LiquidGlassScope.of(context);
    final c = Theme.of(context).colorScheme;
    final field = TextField(
      controller: _controller,
      focusNode: _focus,
      onChanged: _changed,
      style: widget.dense ? const TextStyle(fontSize: 14) : null,
      decoration: InputDecoration(
        prefixIcon: AnimatedScale(
          scale: _focus.hasFocus ? 1.12 : 1,
          duration: _duration(context, 220),
          child: AnimatedRotation(
            turns: _focus.hasFocus ? -.035 : 0,
            duration: _duration(context, 260),
            child: const Icon(Icons.search_rounded),
          ),
        ),
        hintText: widget.hint,
        isDense: widget.dense,
        filled: !glass,
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清除搜索',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _controller.clear();
                  _changed('');
                },
              ),
        border: glass ? InputBorder.none : null,
        enabledBorder: glass ? InputBorder.none : null,
        focusedBorder: glass ? InputBorder.none : null,
      ),
    );
    final surface = glass
        ? _GlassSurface(pressed: _focus.hasFocus, child: field)
        : field;
    return AnimatedScale(
      scale: _focus.hasFocus ? 1.015 : 1,
      alignment: Alignment.centerLeft,
      duration: _duration(context, 260),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: _duration(context, 240),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: c.primary.withValues(alpha: _focus.hasFocus ? .28 : 0),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: c.primary.withValues(alpha: _focus.hasFocus ? .08 : 0),
              blurRadius: _focus.hasFocus ? 18 : 0,
            ),
          ],
        ),
        child: surface,
      ),
    );
  }
}

class _ActionMenu<T> extends StatelessWidget {
  const _ActionMenu({
    required this.options,
    required this.onSelected,
    this.selected,
    this.child,
    this.tooltip = '更多操作',
    this.destructive = const {},
    this.targetBuilder,
  });
  final Map<T, String> options;
  final ValueChanged<T> onSelected;
  final T? selected;
  final Widget? child;
  final String tooltip;
  final Set<T> destructive;
  final Widget Function(VoidCallback open)? targetBuilder;
  @override
  Widget build(BuildContext context) => CommonPopupBox(
    popupBuilder: (_) => CommonPopupMenu(
      items: [
        for (final entry in options.entries)
          CommonPopupMenuItem(
            label: entry.value,
            checked: selected == null ? null : selected == entry.key,
            danger: destructive.contains(entry.key),
            onPressed: () => onSelected(entry.key),
          ),
      ],
    ),
    targetBuilder: (open) =>
        targetBuilder?.call(open) ??
        (child == null
            ? _GlassToolbar(
                children: [
                  IconButton(
                    tooltip: tooltip,
                    onPressed: open,
                    icon: const Icon(Icons.more_vert_rounded),
                  ),
                ],
              )
            : _GlassGroup(
                pill: true,
                child: Tooltip(
                  message: tooltip,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                    ),
                    onPressed: open,
                    child: child!,
                  ),
                ),
              )),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo/app_icon.png',
      width: size,
      height: size,
      semanticLabel: 'OpenMarkji 应用图标',
    );
  }
}

/// 标题浮于内容之上；复用 GPL-3.0 上游顶栏的无硬边渐变遮罩。
class _PinnedPage extends StatefulWidget {
  const _PinnedPage({
    required this.title,
    this.children = const [],
    this.slivers,
    this.toolbar,
    this.backgroundColor,
    this.maxWidth = 1120,
    this.horizontalPadding = 24,
  });
  final String title;
  final List<Widget> children;
  final List<Widget>? slivers;
  final Widget? toolbar;
  final Color? backgroundColor;
  final double maxWidth, horizontalPadding;
  @override
  State<_PinnedPage> createState() => _PinnedPageState();
}

class _PinnedPageState extends State<_PinnedPage> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final rowHeight = math.max(52.0, scaler.scale(28) * 1.15);
    final topInset = MediaQuery.paddingOf(context).top;
    final headerHeight = topInset + rowHeight + 24;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: Stack(
          children: [
            if (widget.slivers != null)
              CustomScrollView(
                key: PageStorageKey('page-${widget.title}'),
                controller: _scroll,
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      widget.horizontalPadding,
                      headerHeight + 16,
                      widget.horizontalPadding,
                      132,
                    ),
                    sliver: SliverMainAxisGroup(slivers: widget.slivers!),
                  ),
                ],
              )
            else
              ListView(
                key: PageStorageKey('page-${widget.title}'),
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(
                  widget.horizontalPadding,
                  headerHeight + 16,
                  widget.horizontalPadding,
                  132,
                ),
                children: widget.children,
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: FloatingHeader(
                key: ValueKey('pinned-backdrop-${widget.title}'),
                backgroundColor:
                    widget.backgroundColor ??
                    Theme.of(context).scaffoldBackgroundColor,
                overhang: 16,
                child: SizedBox(
                  height: headerHeight,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      widget.horizontalPadding,
                      topInset + 12,
                      widget.horizontalPadding,
                      12,
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          height: rowHeight,
                          child:
                              widget.toolbar ??
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      widget.title,
                                      key: ValueKey(
                                        'pinned-heading-${widget.title}',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 28,
                                        height: 1.15,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                        ),
                      ],
                    ),
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

class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    required this.subtitle,
    required this.children,
    this.trailing,
    this.showHeading = true,
    this.navigationTitle,
  });
  final String title, subtitle;
  final List<Widget> children;
  final Widget? trailing;
  final bool showHeading;
  final String? navigationTitle;
  @override
  Widget build(BuildContext context) => _PinnedPage(
    title: navigationTitle ?? title,
    children: [
      if (showHeading) ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                    ),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 28),
      ],
      ...children,
    ],
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(28),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 14),
    child: Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });
  final IconData icon;
  final String title, detail;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: c.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: c.onSecondaryContainer),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.onSurfaceVariant, height: 1.7),
            ),
            if (action != null) ...[const SizedBox(height: 22), action!],
          ],
        ),
      ),
    );
  }
}

class _Load<T> extends StatelessWidget {
  const _Load({required this.future, required this.builder});
  final Future<T> future;
  final Widget Function(T data) builder;
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snap) {
      if (snap.hasError) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Text('加载失败：${snap.error}'),
        );
      }
      if (!snap.hasData && snap.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      }
      return builder(snap.data as T);
    },
  );
}

/// 进度变化时平滑过渡；首次出现时可从 [from] 补完上一步的增长。
class _SmoothProgress extends StatelessWidget {
  const _SmoothProgress({
    required this.value,
    this.from,
    this.minHeight = 5,
    this.backgroundColor,
  });
  final double value;
  final double? from;
  final double minHeight;
  final Color? backgroundColor;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: from ?? value, end: value),
      duration: _duration(context, 420),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => LinearProgressIndicator(
        value: v,
        minHeight: minHeight,
        backgroundColor: backgroundColor,
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.icon});
  final String text;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.secondaryContainer.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13), const SizedBox(width: 4)],
          Text(
            text,
            style: TextStyle(fontSize: 11, color: c.onSecondaryContainer),
          ),
        ],
      ),
    );
  }
}
