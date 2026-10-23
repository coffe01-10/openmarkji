part of 'app.dart';

/// 同一块玻璃从搜索水滴延展成输入框，收回时沿原路径合拢。
class _LibraryToolbar extends StatefulWidget {
  const _LibraryToolbar({required this.actions, required this.onChanged});
  final Widget actions;
  final ValueChanged<String> onChanged;
  @override
  State<_LibraryToolbar> createState() => _LibraryToolbarState();
}

class _LibraryToolbarState extends State<_LibraryToolbar>
    with SingleTickerProviderStateMixin {
  late final _motion =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 460),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && _open) _focus.requestFocus();
      });
  final _focus = FocusNode();
  final _text = TextEditingController();
  final _curve = SpringCurve(
    const SpringDescription(mass: 1, stiffness: 380, damping: 32),
    seconds: .46,
  );
  bool _open = false;

  void _activate() {
    if (_open) {
      if (_motion.isCompleted) _focus.requestFocus();
      return;
    }
    setState(() => _open = true);
    _motion.duration = _duration(context, 460);
    _motion.animateTo(1, curve: _curve);
  }

  void _close() {
    _focus.unfocus();
    _text.clear();
    widget.onChanged('');
    setState(() => _open = false);
    _motion.duration = _duration(context, 460);
    _motion.animateBack(0, curve: _curve);
  }

  @override
  void dispose() {
    _motion.dispose();
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final start = Rect.fromLTWH(width - 140, (height - 44) / 2, 44, 44);
        final fieldHeight = math.max(
          44.0,
          MediaQuery.textScalerOf(context).scale(14) * 1.2 + 16,
        );
        final end = Rect.fromLTWH(
          0,
          (height - fieldHeight) / 2,
          width - 56,
          fieldHeight,
        );
        final c = Theme.of(context).colorScheme;
        return AnimatedBuilder(
          animation: _motion,
          builder: (context, _) {
            final t = _motion.value;
            final fade = t.clamp(0.0, 1.0);
            final rect = Rect.lerp(start, end, t)!;
            final bulge = math.sin(math.pi * _motion.value) * 3;
            final active = _open || !_motion.isDismissed;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  right: 152,
                  child: ExcludeSemantics(
                    excluding: active,
                    child: Opacity(
                      opacity: 1 - fade,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '牌组',
                          key: const ValueKey('pinned-heading-牌组'),
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
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: (height - 44) / 2,
                  child: ExcludeSemantics(
                    excluding: active,
                    child: IgnorePointer(
                      ignoring: active,
                      child: Opacity(opacity: 1 - fade, child: widget.actions),
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: rect.inflate(bulge / 2),
                  child: SizedBox.expand(
                    key: const ValueKey('search-morph-pane'),
                    child: _GlassGroup(
                      pill: true,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (active)
                            ExcludeSemantics(
                              excluding: !_open,
                              child: IgnorePointer(
                                ignoring: !_open,
                                child: Opacity(
                                  opacity: ((fade - .25) / .75).clamp(0.0, 1.0),
                                  child: OverflowBox(
                                    alignment: Alignment.centerLeft,
                                    minWidth: end.width,
                                    maxWidth: end.width,
                                    child: TextField(
                                      controller: _text,
                                      focusNode: _focus,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        height: 1.2,
                                      ),
                                      textAlignVertical:
                                          TextAlignVertical.center,
                                      onChanged: (value) {
                                        setState(() {});
                                        widget.onChanged(value);
                                      },
                                      decoration: InputDecoration(
                                        hintText: '搜索牌组或卡片',
                                        filled: false,
                                        isDense: true,
                                        contentPadding: const EdgeInsets.only(
                                          right: 12,
                                        ),
                                        prefixIcon: const SizedBox(
                                          width: 44,
                                          height: 44,
                                        ),
                                        prefixIconConstraints:
                                            const BoxConstraints.tightFor(
                                              width: 44,
                                              height: 44,
                                            ),
                                        suffixIconConstraints:
                                            const BoxConstraints.tightFor(
                                              width: 44,
                                              height: 44,
                                            ),
                                        suffixIcon: _text.text.isEmpty
                                            ? null
                                            : IconButton(
                                                tooltip: '清除搜索',
                                                onPressed: () {
                                                  _text.clear();
                                                  setState(() {});
                                                  widget.onChanged('');
                                                },
                                                icon: const Icon(
                                                  Icons.close_rounded,
                                                  size: 18,
                                                ),
                                              ),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: 44,
                            child: IconButton(
                              tooltip: '搜索牌组或卡片',
                              style: IconButton.styleFrom(
                                foregroundColor: c.onSurface,
                                padding: EdgeInsets.zero,
                              ).merge(ElasticPress.buttonStyle),
                              onPressed: _activate,
                              icon: const Icon(Icons.search_rounded),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (active)
                  Positioned(
                    right: 0,
                    top: (height - 44) / 2,
                    child: Opacity(
                      opacity: fade,
                      child: _GlassToolbar(
                        children: [
                          IconButton(
                            tooltip: '关闭搜索',
                            onPressed: _close,
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    ),
  );
}
