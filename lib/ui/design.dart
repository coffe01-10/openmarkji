part of 'app.dart';

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
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
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
        focusedBorder: glass
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: c.primary.withValues(alpha: .5)),
              )
            : null,
      ),
    );
    if (!glass) return field;
    return LiquidGlass(
      style: LiquidGlassStyle.regular(c).copyWith(blur: 12),
      pressed: _focus.hasFocus,
      clipper: const ShapeBorderClipper(
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      child: field,
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
    targetBuilder: (open) => ElasticButton(
      child: child == null
          ? IconButton(
              tooltip: tooltip,
              onPressed: open,
              icon: const Icon(Icons.more_vert_rounded),
            )
          : Tooltip(
              message: tooltip,
              child: TextButton(onPressed: open, child: child!),
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

class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    required this.subtitle,
    required this.children,
    this.trailing,
  });
  final String title, subtitle;
  final List<Widget> children;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1120),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 132),
        children: [
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
          ...children,
        ],
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(22)});
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
