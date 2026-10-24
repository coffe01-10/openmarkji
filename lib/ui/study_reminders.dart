part of 'app.dart';

class _StudyReminderPage extends StatefulWidget {
  const _StudyReminderPage({required this.store});
  final AppStore store;
  @override
  State<_StudyReminderPage> createState() => _StudyReminderPageState();
}

class _StudyReminderPageState extends State<_StudyReminderPage>
    with WidgetsBindingObserver {
  bool? _allowed;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermission();
  }

  Future<void> _refreshPermission() => _action(context, () async {
    final allowed = await StudyReminders.isAllowed();
    if (mounted) setState(() => _allowed = allowed);
  });

  Future<void> _toggle(bool enabled) => _action(context, () async {
    setState(() => _working = true);
    try {
      if (enabled) {
        final allowed = await StudyReminders.requestPermission();
        if (mounted) setState(() => _allowed = allowed);
        if (!allowed) return;
      }
      widget.store.preferences.studyReminder = enabled;
      await widget.store.savePreferences();
      await StudyReminders.sync();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final p = widget.store.preferences;
      final supported = StudyReminders.supported;
      return _SettingsDetail(
        title: '学习提醒',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReviewReminderCard(store: widget.store),
            _AppearanceHeader('提醒安排', Icons.notifications_active_outlined),
            _AppearanceCard(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('学习提醒'),
                    subtitle: const Text('每天在设定时间提醒你复习'),
                    value: p.studyReminder,
                    onChanged: supported && !_working ? _toggle : null,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _SettingsPageLink(
                    page: _ReminderTimePage(store: widget.store),
                    radius: _settingsRowRadius(1, supported ? 3 : 2),
                    // 收回动画保留入口控件，时间值也要跟随二级页的修改。
                    builder: (open) => ListenableBuilder(
                      listenable: widget.store,
                      builder: (context, _) => Semantics(
                        container: true,
                        child: ListTile(
                          title: const Text('提醒时间'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_reminderClock(widget.store.preferences)),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                          onTap: !_working ? open : null,
                        ),
                      ),
                    ),
                  ),
                  if (supported) ...[
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      enabled: p.studyReminder && !_working && _allowed == true,
                      leading: const Icon(Icons.notifications_outlined),
                      title: const Text('发送测试提醒'),
                      onTap: p.studyReminder && !_working && _allowed == true
                          ? () => _action(context, () async {
                              final sent = await StudyReminders.preview();
                              if (context.mounted) {
                                _toast(
                                  context,
                                  sent ? '已发送测试提醒，请查看通知栏' : '系统通知未开启',
                                );
                              }
                            })
                          : null,
                    ),
                  ],
                ],
              ),
            ),
            if (supported && _allowed == false) ...[
              const SizedBox(height: 16),
              _AppearanceCard(
                child: ListTile(
                  leading: const Icon(Icons.notifications_off_outlined),
                  title: const Text('系统通知未开启'),
                  subtitle: const Text('允许通知后才能收到学习提醒'),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: () => _action(context, StudyReminders.openSettings),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

String _reminderClock(Preferences p) =>
    '${p.reminderHour.toString().padLeft(2, '0')}:${p.reminderMinute.toString().padLeft(2, '0')}';

class _ReminderTimePage extends StatelessWidget {
  const _ReminderTimePage({required this.store});
  final AppStore store;

  Future<void> _save(BuildContext context, {int? hour, int? minute}) =>
      _action(context, () async {
        final p = store.preferences;
        if (hour != null) p.reminderHour = hour;
        if (minute != null) p.reminderMinute = minute;
        await store.savePreferences();
        await StudyReminders.sync();
      });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final p = store.preferences;
      final c = Theme.of(context).colorScheme;
      return _SettingsDetail(
        title: '提醒时间',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(Icons.schedule_rounded, size: 28, color: c.primary),
                  const SizedBox(height: 12),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _reminderClock(p),
                      style: TextStyle(
                        fontSize: 64,
                        height: 1.15,
                        letterSpacing: -2,
                        fontWeight: FontWeight.w600,
                        color: c.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '每天，留一点时间给记忆',
                    style: TextStyle(color: c.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            _AppearanceCard(
              child: Column(
                children: [
                  _AppearanceMenu(
                    title: '小时',
                    value: '${p.reminderHour}',
                    options: {
                      for (var i = 0; i < 24; i++)
                        '$i': '${i.toString().padLeft(2, '0')} 时',
                    },
                    onChanged: (value) =>
                        _save(context, hour: int.parse(value)),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _AppearanceMenu(
                    title: '分钟',
                    value: '${p.reminderMinute}',
                    options: {
                      for (var i = 0; i < 60; i++)
                        '$i': '${i.toString().padLeft(2, '0')} 分',
                    },
                    onChanged: (value) =>
                        _save(context, minute: int.parse(value)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '选择后立即保存，返回即可。',
                style: TextStyle(color: c.onSurfaceVariant, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _ReviewReminderCard extends StatelessWidget {
  const _ReviewReminderCard({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final p = store.preferences;
    return _AppearanceCard(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                c.primary.withValues(alpha: .11),
                _settingsCard(c),
              ),
              _settingsCard(c),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 49,
              right: 12,
              child: ExcludeSemantics(
                child: CustomPaint(
                  size: const Size(112, 112),
                  painter: _ReminderCardsPainter(c),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_outlined,
                        size: 16,
                        color: c.primary,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '今日待复习',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${now.month}月${now.day}日',
                        style: TextStyle(
                          fontSize: 12,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FutureBuilder<Map<String, dynamic>>(
                    future: store.overview(),
                    builder: (context, snapshot) {
                      final count = snapshot.data?['review'] as int?;
                      final number = Text(
                        count == null ? '—' : '$count',
                        key: ValueKey(count),
                        style: TextStyle(
                          fontSize: 56,
                          height: 1.05,
                          letterSpacing: -1.5,
                          fontWeight: FontWeight.w700,
                          color: c.primary,
                        ),
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        if (count == null)
                                          number
                                        else
                                          Semantics(
                                            label: '$count',
                                            excludeSemantics: true,
                                            child: AnimatedSwitcher(
                                              duration: _duration(context, 220),
                                              transitionBuilder:
                                                  (
                                                    child,
                                                    animation,
                                                  ) => FadeTransition(
                                                    opacity: animation,
                                                    child: SlideTransition(
                                                      position: Tween<Offset>(
                                                        begin: const Offset(
                                                          0,
                                                          .12,
                                                        ),
                                                        end: Offset.zero,
                                                      ).animate(animation),
                                                      child: child,
                                                    ),
                                                  ),
                                              child: number,
                                            ),
                                          ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '张',
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: c.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 92),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            snapshot.hasError
                                ? '暂时无法读取复习安排'
                                : count == null
                                ? '正在整理今天的复习安排'
                                : count == 0
                                ? '今天没有到期复习，轻松一点。'
                                : '到期的知识，值得再见一面。',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.6,
                              color: c.onSurfaceVariant,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 22),
                  Divider(
                    height: 1,
                    color: c.outlineVariant.withValues(alpha: .55),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 16,
                            color: c.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '每天 ${_reminderClock(p)}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: p.studyReminder
                              ? c.primaryContainer
                              : c.surfaceContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          p.studyReminder ? '提醒已开启' : '提醒未开启',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: p.studyReminder
                                ? c.onPrimaryContainer
                                : c.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderCardsPainter extends CustomPainter {
  const _ReminderCardsPainter(this.scheme);
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      const Offset(57, 59),
      49,
      Paint()..color = scheme.primary.withValues(alpha: .05),
    );
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(55 + (i - 1) * 11, 57);
      canvas.rotate((i - 1) * .2);
      final card = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-27, -36, 54, 72),
        const Radius.circular(10),
      );
      canvas.drawRRect(
        card.shift(const Offset(0, 3)),
        Paint()..color = scheme.primary.withValues(alpha: .04),
      );
      canvas.drawRRect(
        card,
        Paint()
          ..color = Color.alphaBlend(
            scheme.primary.withValues(alpha: .05 * (3 - i)),
            _settingsCard(scheme),
          ),
      );
      canvas.drawRRect(
        card,
        Paint()
          ..color = scheme.primary.withValues(alpha: .22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      if (i == 2) {
        final ink = Paint()
          ..color = scheme.primary.withValues(alpha: .45)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(-13, -16), const Offset(5, -16), ink);
        for (var j = 0; j < 3; j++) {
          canvas.drawLine(
            Offset(-13, 1 + j * 9),
            Offset(j == 2 ? 3 : 13, 1 + j * 9),
            ink..color = scheme.primary.withValues(alpha: .16),
          );
        }
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ReminderCardsPainter oldDelegate) =>
      oldDelegate.scheme != scheme;
}
