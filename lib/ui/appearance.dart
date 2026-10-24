part of 'app.dart';

// Appearance layout follows the GPL-3.0 upstream; see third_party/GPL-3.0.
const _navigationDestinations = [
  NavigationDockDestination(glyph: Icons.wb_sunny_outlined, label: '今日'),
  NavigationDockDestination(glyph: Icons.layers_outlined, label: '牌组'),
  NavigationDockDestination(glyph: Icons.bar_chart_rounded, label: '统计'),
  NavigationDockDestination(glyph: Icons.tune_rounded, label: '设置'),
];

Widget _appearanceBack(BuildContext context) => Center(
  child: ElasticButton(
    child: IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      style: LiquidGlassScope.of(context)
          ? LiquidGlass.buttonStyle(
              (_) => LiquidGlassScope.controlStyleOf(context),
            )
          : null,
      onPressed: () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.arrow_back_rounded),
    ),
  ),
);

class _AppearancePage extends StatefulWidget {
  const _AppearancePage({required this.store});
  final AppStore store;
  @override
  State<_AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<_AppearancePage> {
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
    setState(() {});
  }

  void _save(void Function(Preferences) update) => _action(context, () async {
    widget.store.updatePreferences(update);
    await widget.store.savePreferences();
  });

  @override
  Widget build(BuildContext context) {
    final p = widget.store.preferences;
    final c = Theme.of(context).colorScheme;
    return _SettingsScaffold(
      title: '外观与阅读',
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: _settingsContentPadding(context),
            children: [
              _AppearanceLivePreview(preferences: p),
              _AppearanceChoices(
                title: '主题模式',
                icon: Icons.brightness_6_outlined,
                value: p.theme,
                choices: [
                  (
                    value: 'system',
                    label: '跟随系统',
                    preview: const _MiniAppearance(split: true),
                  ),
                  (
                    value: 'light',
                    label: '浅色',
                    preview: const _MiniAppearance(),
                  ),
                  (
                    value: 'dark',
                    label: '深色',
                    preview: const _MiniAppearance(dark: true),
                  ),
                ],
                onChanged: (value) => _save((p) => p.theme = value),
              ),
              _AppearanceHeader('纯黑背景', Icons.contrast),
              _AppearanceCard(
                child: SwitchListTile(
                  title: const Text('深色模式使用纯黑'),
                  value: p.pureBlack,
                  onChanged: (value) => _save((p) => p.pureBlack = value),
                ),
              ),
              _AppearanceHeader('主题色', Icons.palette_outlined),
              _AppearanceCard(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final value in [
                            null,
                            0xff5479bc,
                            0xff49776a,
                            0xff8f6594,
                            0xff9b6a45,
                            0xff526b7a,
                          ])
                            _ThemeSwatch(
                              color: value == null ? c.primary : Color(value),
                              system: value == null,
                              selected: value == null
                                  ? p.dynamicColor
                                  : !p.dynamicColor && p.color == value,
                              onTap: () => _save((p) {
                                p.dynamicColor = value == null;
                                if (value != null) p.color = value;
                              }),
                            ),
                        ],
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('跟随系统动态取色'),
                      value: p.dynamicColor,
                      onChanged: (value) =>
                          _save((p) => p.dynamicColor = value),
                    ),
                    _AppearanceMenu(
                      title: '色彩风格',
                      value: p.colorStyle,
                      options: const {
                        'tonalSpot': '柔和',
                        'vibrant': '鲜明',
                        'neutral': '中性',
                      },
                      onChanged: (value) => _save((p) => p.colorStyle = value),
                    ),
                  ],
                ),
              ),
              _AppearanceChoices(
                title: '导航栏样式',
                icon: Icons.layers_outlined,
                value: p.floatingNavigation ? 'floating' : 'docked',
                choices: const [
                  (value: 'floating', label: '悬浮', preview: _MiniAppearance()),
                  (
                    value: 'docked',
                    label: '固定',
                    preview: _MiniAppearance(floating: false),
                  ),
                ],
                onChanged: (value) =>
                    _save((p) => p.floatingNavigation = value == 'floating'),
              ),
              _AppearanceChoices(
                title: '页面切换动画',
                icon: Icons.swipe_outlined,
                value: p.tabAnimation,
                choices: const [
                  (
                    value: 'slide',
                    label: '滑动',
                    preview: _MiniAppearance(motion: 'slide'),
                  ),
                  (
                    value: 'fade',
                    label: '淡入淡出',
                    preview: _MiniAppearance(motion: 'fade'),
                  ),
                ],
                onChanged: (value) => _save((p) => p.tabAnimation = value),
              ),
              _AppearanceChoices(
                title: '液态玻璃',
                icon: Icons.blur_on_rounded,
                value: p.liquidGlass,
                choices: const [
                  (
                    value: 'none',
                    label: '关闭',
                    preview: _MiniAppearance(glass: false),
                  ),
                  (
                    value: 'standard',
                    label: '标准',
                    preview: _MiniAppearance(glass: true),
                  ),
                  (
                    value: 'ultra',
                    label: '超高',
                    preview: _MiniAppearance(glass: true, ultra: true),
                  ),
                ],
                onChanged: (value) => _save((p) => p.liquidGlass = value),
              ),
              _AppearanceHeader('全局玻璃质感', Icons.opacity_rounded),
              _AppearanceCard(
                child: Column(
                  children: [
                    _GlassMaterialPreview(preferences: p),
                    _PreferenceSlider(
                      title: '透明度',
                      value: 1 - p.dockOpacity,
                      max: 1,
                      divisions: 20,
                      label: '${((1 - p.dockOpacity) * 100).round()}%',
                      enabled: p.liquidGlass != 'none',
                      onChanged: (v) => widget.store.updatePreferences(
                        (p) => p.dockOpacity = 1 - v,
                      ),
                      onChangeEnd: (_) =>
                          _action(context, widget.store.savePreferences),
                    ),
                    _PreferenceSlider(
                      title: '背景模糊',
                      value: p.dockBlur,
                      max: 30,
                      divisions: 30,
                      label: '${p.dockBlur.round()}',
                      enabled: p.liquidGlass != 'none',
                      onChanged: (v) =>
                          widget.store.updatePreferences((p) => p.dockBlur = v),
                      onChangeEnd: (_) =>
                          _action(context, widget.store.savePreferences),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        p.liquidGlass == 'none'
                            ? '启用液态玻璃后可调节，统一应用于导航、切换栏、按钮、搜索框和菜单。'
                            : '导航、切换栏、按钮、搜索框和菜单同步生效。透明度越高越通透，模糊越高背景越柔和。',
                        style: TextStyle(
                          fontSize: 12,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _save((p) {
                        p.dockOpacity = .58;
                        p.dockBlur = 16;
                      }),
                      child: const Text('恢复默认质感'),
                    ),
                  ],
                ),
              ),
              _AppearanceHeader('文字', Icons.text_fields_rounded),
              _AppearanceCard(
                child: Column(
                  children: [
                    _AppearanceMenu(
                      title: '字体',
                      value: p.fontFamily,
                      options: const {
                        'system': '系统默认',
                        'sans-serif': '无衬线',
                        'serif': '衬线',
                        'monospace': '等宽',
                      },
                      onChanged: (value) => _save((p) => p.fontFamily = value),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          const Expanded(child: Text('界面字号')),
                          Text('${(p.textScale * 100).round()}%'),
                        ],
                      ),
                    ),
                    Slider(
                      value: p.textScale,
                      min: .85,
                      max: 1.4,
                      divisions: 11,
                      label: '${(p.textScale * 100).round()}%',
                      onChanged: (value) => _save((p) => p.textScale = value),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          const Expanded(child: Text('卡片阅读字号')),
                          Text('${p.fontSize.round()}'),
                        ],
                      ),
                    ),
                    Slider(
                      value: p.fontSize,
                      min: 14,
                      max: 30,
                      divisions: 8,
                      onChanged: (value) => setState(() => p.fontSize = value),
                      onChangeEnd: (_) =>
                          _action(context, widget.store.savePreferences),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      child: Text(
                        '在恰当的时间，想起重要的事。',
                        style: TextStyle(fontSize: p.fontSize, height: 1.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppearanceHeader extends StatelessWidget {
  const _AppearanceHeader(this.title, this.icon);
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
    child: Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: _settingsCard(Theme.of(context).colorScheme),
    shape: const RoundedSuperellipseBorder(
      borderRadius: BorderRadius.all(Radius.circular(24)),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _AppearanceChoices extends StatelessWidget {
  const _AppearanceChoices({
    required this.title,
    required this.icon,
    required this.value,
    required this.choices,
    required this.onChanged,
  });
  final String title, value;
  final IconData icon;
  final List<({String value, String label, Widget preview})> choices;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AppearanceHeader(title, icon),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < choices.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  button: true,
                  selected: choices[i].value == value,
                  label: '$title：${choices[i].label}',
                  excludeSemantics: true,
                  onTap: () => onChanged(choices[i].value),
                  child: ElasticPress(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => onChanged(choices[i].value),
                      child: Column(
                        children: [
                          AnimatedContainer(
                            duration: _duration(context, 200),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: choices[i].value == value
                                    ? c.primary
                                    : c.outlineVariant.withValues(alpha: .45),
                                width: choices[i].value == value ? 2 : 1,
                              ),
                            ),
                            child: choices[i].preview,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            choices[i].label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          Icon(
                            choices[i].value == value
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: choices[i].value == value
                                ? c.primary
                                : c.outlineVariant,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _MiniAppearance extends StatelessWidget {
  const _MiniAppearance({
    this.dark = false,
    this.split = false,
    this.floating = true,
    this.glass = false,
    this.ultra = false,
    this.motion,
  });
  final bool dark, split, floating, glass, ultra;
  final String? motion;
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 105,
        width: double.infinity,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xff202127)
                      : const Color(0xfff0f1f7),
                  gradient: split
                      ? const LinearGradient(
                          colors: [Color(0xfff0f1f7), Color(0xff202127)],
                          stops: [.5, .5],
                        )
                      : null,
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              top: 12,
              child: Column(
                children: [
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: i == 0
                              ? primary.withValues(alpha: dark ? .7 : .25)
                              : dark
                              ? Colors.white.withValues(alpha: .1)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (motion != null)
              Positioned(
                left: 14,
                right: 14,
                top: 25,
                child: Icon(
                  motion == 'slide'
                      ? Icons.swipe_rounded
                      : Icons.gradient_rounded,
                  color: primary,
                  size: 28,
                ),
              ),
            Positioned(
              left: floating ? 7 : 0,
              right: floating ? 7 : 0,
              bottom: floating ? 9 : 0,
              child: Container(
                height: 23,
                decoration: BoxDecoration(
                  color: glass
                      ? Colors.white.withValues(alpha: ultra ? .4 : .65)
                      : dark
                      ? const Color(0xff45464d)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(floating ? 16 : 0),
                  border: glass
                      ? Border.all(color: Colors.white.withValues(alpha: .9))
                      : null,
                  boxShadow: glass
                      ? [
                          BoxShadow(
                            color: primary.withValues(alpha: .15),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: i == 1 ? .8 : .25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppearanceLivePreview extends StatefulWidget {
  const _AppearanceLivePreview({required this.preferences});
  final Preferences preferences;
  @override
  State<_AppearanceLivePreview> createState() => _AppearanceLivePreviewState();
}

class _AppearanceLivePreviewState extends State<_AppearanceLivePreview> {
  int _selected = 0;
  @override
  Widget build(BuildContext context) {
    final p = widget.preferences;
    final c = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    c.primaryContainer,
                    c.tertiaryContainer,
                    c.surfaceContainer,
                  ],
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: _duration(context, 300),
                transitionBuilder: (child, animation) =>
                    p.tabAnimation == 'fade'
                    ? FadeTransition(opacity: animation, child: child)
                    : SlideTransition(
                        position:
                            Tween(
                              begin: const Offset(.5, 0),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.fastOutSlowIn,
                              ),
                            ),
                        child: child,
                      ),
                child: Padding(
                  key: ValueKey(_selected),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _ShellState.labels[_selected],
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '实时预览',
                            style: TextStyle(
                              fontSize: 11,
                              color: c.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      for (final text in ['每天一点，让记忆慢慢生长', '知识属于你，记忆也是。'])
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: c.surface.withValues(alpha: .7),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            text,
                            style: TextStyle(fontSize: 13, color: c.onSurface),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: p.floatingNavigation
                    ? NavigationDock(
                        destinations: _navigationDestinations,
                        selectedIndex: _selected,
                        onSelected: (value) =>
                            setState(() => _selected = value),
                      )
                    : NavigationBar(
                        height: 64,
                        selectedIndex: _selected,
                        onDestinationSelected: (value) =>
                            setState(() => _selected = value),
                        destinations: [
                          for (final entry in _navigationDestinations)
                            NavigationDestination(
                              icon: Icon(entry.glyph, size: 22),
                              label: entry.label,
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.color,
    required this.system,
    required this.selected,
    required this.onTap,
  });
  final Color color;
  final bool system, selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: system ? '系统主题色' : '主题色 ${color.toARGB32().toRadixString(16)}',
    child: ElasticPress(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: _duration(context, 200),
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? color : Colors.transparent,
              width: 2,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: AnimatedScale(
              scale: selected || system ? 1 : 0,
              duration: _duration(context, 200),
              curve: Curves.easeOutBack,
              child: Icon(
                system ? Icons.colorize : Icons.check,
                size: 18,
                color:
                    ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _AppearanceMenu extends StatelessWidget {
  const _AppearanceMenu({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String title, value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    trailing: CommonPopupBox(
      popupBuilder: (_) => CommonPopupMenu(
        items: [
          for (final entry in options.entries)
            CommonPopupMenuItem(
              label: entry.value,
              checked: value == entry.key,
              onPressed: () => onChanged(entry.key),
            ),
        ],
      ),
      targetBuilder: (open) => ElasticButton(
        child: TextButton(
          onPressed: open,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupValueText(options[value]!),
              const SizedBox(width: 6),
              const Icon(Icons.unfold_more_rounded, size: 18),
            ],
          ),
        ),
      ),
    ),
  );
}

class _GlassMaterialPreview extends StatefulWidget {
  const _GlassMaterialPreview({required this.preferences});
  final Preferences preferences;
  @override
  State<_GlassMaterialPreview> createState() => _GlassMaterialPreviewState();
}

class _GlassMaterialPreviewState extends State<_GlassMaterialPreview> {
  int _selected = 0;
  @override
  Widget build(BuildContext context) {
    final p = widget.preferences;
    final c = Theme.of(context).colorScheme;
    return LiquidGlassScope(
      enabled: p.liquidGlass != 'none',
      quality: p.liquidGlass == 'standard'
          ? LiquidGlassQuality.standard
          : LiquidGlassQuality.ultra,
      dockOpacity: p.dockOpacity,
      dockBlur: p.dockBlur,
      child: Container(
        padding: const EdgeInsets.only(top: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              c.primaryContainer,
              c.tertiaryContainer,
              c.secondaryContainer,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              _GlassSegments<int>(
                options: {
                  for (var i = 0; i < _navigationDestinations.length; i++)
                    i: _navigationDestinations[i].label,
                },
                value: _selected,
                stretch: true,
                onChanged: (value) => setState(() => _selected = value),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text('按住滑动预览', style: TextStyle(fontSize: 12)),
                  ),
                  _GlassToolbar(
                    children: [
                      IconButton(
                        tooltip: '预览上一项',
                        onPressed: () =>
                            setState(() => _selected = (_selected + 3) % 4),
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      IconButton(
                        tooltip: '预览下一项',
                        onPressed: () =>
                            setState(() => _selected = (_selected + 1) % 4),
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                ],
              ),
              NavigationDock(
                destinations: _navigationDestinations,
                selectedIndex: _selected,
                onSelected: (value) => setState(() => _selected = value),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreferenceSlider extends StatelessWidget {
  const _PreferenceSlider({
    required this.title,
    required this.value,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
    required this.onChangeEnd,
    this.enabled = true,
  });
  final String title, label;
  final double value, max;
  final int divisions;
  final bool enabled;
  final ValueChanged<double> onChanged, onChangeEnd;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            Expanded(child: Text(title)),
            Text(label),
          ],
        ),
      ),
      Slider(
        value: value,
        max: max,
        divisions: divisions,
        label: label,
        semanticFormatterCallback: (_) => '$title $label',
        onChanged: enabled ? onChanged : null,
        onChangeEnd: enabled ? onChangeEnd : null,
      ),
    ],
  );
}
