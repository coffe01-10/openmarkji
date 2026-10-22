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
                Text(label),
              ],
            ),
          ),
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
    if (mounted) setState(() {});
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
  });
  final Map<T, String> options;
  final ValueChanged<T> onSelected;
  final T? selected;
  final Widget? child;
  final String tooltip;
  final Set<T> destructive;
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
    targetBuilder: (open) => child == null
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
          ),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.primary,
        borderRadius: BorderRadius.circular(size * .32),
      ),
      child: Icon(
        Icons.auto_awesome_mosaic_rounded,
        size: size * .58,
        color: c.onPrimary,
      ),
    );
  }
}

/// 标题浮于内容之上；复用 GPL-3.0 上游顶栏的无硬边渐变遮罩。
class _PinnedPage extends StatefulWidget {
  const _PinnedPage({
    required this.title,
    required this.children,
    this.toolbar,
    this.backgroundColor,
    this.maxWidth = 1120,
    this.horizontalPadding = 24,
  });
  final String title;
  final List<Widget> children;
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
  const _SectionLabel(this.title, {this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        ?trailing,
      ],
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
