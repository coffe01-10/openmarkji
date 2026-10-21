part of 'app.dart';

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

class _GlassDock extends StatefulWidget {
  const _GlassDock({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;
  @override
  State<_GlassDock> createState() => _GlassDockState();
}

class _GlassDockState extends State<_GlassDock> {
  double? _drag;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        math.max(18, MediaQuery.paddingOf(context).bottom + 8),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(38),
            boxShadow: [
              BoxShadow(
                color: c.shadow.withValues(alpha: .12),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(38),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                height: 76,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: c.surfaceContainer.withValues(alpha: .84),
                  borderRadius: BorderRadius.circular(38),
                  border: Border.all(color: c.surface.withValues(alpha: .8)),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final pitch = constraints.maxWidth / 4;
                    return GestureDetector(
                      onHorizontalDragUpdate: (details) => setState(
                        () => _drag = (details.localPosition.dx / pitch - .5)
                            .clamp(0.0, 3.0),
                      ),
                      onHorizontalDragEnd: (_) {
                        final selected = _drag?.round();
                        setState(() => _drag = null);
                        if (selected != null) {
                          HapticFeedback.selectionClick();
                          widget.onSelect(selected);
                        }
                      },
                      onHorizontalDragCancel: () =>
                          setState(() => _drag = null),
                      child: Stack(
                        children: [
                          AnimatedPositioned(
                            duration: _duration(
                              context,
                              _drag == null ? 380 : 60,
                            ),
                            curve: Curves.easeOutBack,
                            left: (_drag ?? widget.index.toDouble()) * pitch,
                            top: 0,
                            bottom: 0,
                            width: pitch,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: c.primaryContainer.withValues(
                                  alpha: .88,
                                ),
                                borderRadius: BorderRadius.circular(32),
                                border: Border.all(
                                  color: c.surface.withValues(alpha: .65),
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: List.generate(
                              4,
                              (i) => Expanded(
                                child: Semantics(
                                  selected: widget.index == i,
                                  button: true,
                                  label: _ShellState.labels[i],
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(32),
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      widget.onSelect(i);
                                    },
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        AnimatedScale(
                                          scale: widget.index == i ? 1.08 : 1,
                                          duration: _duration(context, 200),
                                          child: Icon(
                                            _ShellState.icons[i],
                                            size: 24,
                                            color: widget.index == i
                                                ? c.onPrimaryContainer
                                                : c.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _ShellState.labels[i],
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: widget.index == i
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: widget.index == i
                                                ? c.onPrimaryContainer
                                                : c.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
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
