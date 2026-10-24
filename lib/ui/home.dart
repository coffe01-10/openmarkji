part of 'app.dart';

class _TodayPage extends StatelessWidget {
  const _TodayPage({required this.store, required this.onLibrary});
  final AppStore store;
  final VoidCallback onLibrary;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final c = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => _Load(
        future: store.overview(),
        builder: (data) {
          final remaining = data['remaining'] as int,
              completed = data['completed'] as int;
          final hasCards = (data['totalCards'] as int) > 0;
          return _Page(
            navigationTitle: '今日',
            title: '让记忆，慢慢生长',
            subtitle:
                '${now.month} 月 ${now.day} 日  ·  星期${['一', '二', '三', '四', '五', '六', '日'][now.weekday - 1]}',
            trailing: const _BrandMark(),
            children: [
              _TouchTiltCard(
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        c.primaryContainer,
                        c.secondaryContainer.withValues(alpha: .65),
                      ],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -48,
                        top: -54,
                        child: IgnorePointer(
                          child: CustomPaint(
                            size: const Size(270, 270),
                            painter: _OrbitPainter(
                              c.primary.withValues(alpha: .11),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(26),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome_outlined,
                                  size: 17,
                                  color: c.onPrimaryContainer,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'TODAY’S FOCUS',
                                    style: TextStyle(
                                      fontSize: 11,
                                      letterSpacing: 2.2,
                                      fontWeight: FontWeight.w600,
                                      color: c.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Text(
                              remaining > 0
                                  ? '$remaining'
                                  : completed > 0
                                  ? '做得很好'
                                  : '从一张卡开始',
                              style: TextStyle(
                                fontSize: remaining > 0 ? 64 : 32,
                                height: 1.15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -2,
                                color: c.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              remaining > 0
                                  ? '张卡片，等待今天的你'
                                  : completed > 0
                                  ? '今天的任务已完成，让知识沉淀一下。'
                                  : '给值得记住的知识，一个留下来的地方。',
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.6,
                                color: c.onPrimaryContainer.withValues(
                                  alpha: .8,
                                ),
                              ),
                            ),
                            const SizedBox(height: 26),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: remaining > 0
                                    ? () => _push(
                                        context,
                                        _StudyPage(store: store),
                                      )
                                    : onLibrary,
                                icon: Icon(
                                  remaining > 0
                                      ? Icons.play_arrow_rounded
                                      : Icons.add_rounded,
                                ),
                                label: Text(
                                  remaining > 0
                                      ? completed > 0 ||
                                                (data['formal'] as int) > 0
                                            ? '继续学习'
                                            : '开始今日学习'
                                      : hasCards
                                      ? '去牌组选择学习内容'
                                      : '建立我的第一副牌组',
                                ),
                              ),
                            ),
                            if (remaining + completed > 0) ...[
                              const SizedBox(height: 18),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: ExcludeSemantics(
                                  child: LinearProgressIndicator(
                                    value: completed / (remaining + completed),
                                    minHeight: 5,
                                    backgroundColor: c.onPrimaryContainer
                                        .withValues(alpha: .08),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '已完成 $completed 张 · 一点一滴，都算数',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: c.onPrimaryContainer,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Text(
                              '今日学习时间 · ${_studyTime(data['elapsed'] as int)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: c.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _Load(
                future: store.practiceSession(),
                builder: (session) => session == null || session.queue.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _AppearanceCard(
                          child: _supportTile(
                            Icons.school_outlined,
                            '继续专项练习',
                            () => _push(context, _PracticePage(store: store)),
                            subtitle:
                                '已掌握 ${session.completed} / ${session.total} 张 · 独立于每日计划',
                          ),
                        ),
                      ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: '待复习',
                      value: '${data['review']}',
                      icon: Icons.history_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Metric(
                      label: '待新学',
                      value: '${data['new']}',
                      icon: Icons.auto_stories_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Metric(
                      label: '待重学',
                      value: '${data['relearn']}',
                      icon: Icons.refresh_rounded,
                    ),
                  ),
                ],
              ),
              const _SectionLabel('我的学习空间'),
              _Load(
                future: store.decks(),
                builder: (decks) => decks.isEmpty
                    ? _Empty(
                        icon: Icons.spa_outlined,
                        title: '先种下一颗知识的种子',
                        detail: '导入卡片文本，或写下自己的第一张卡。\n选入计划后，我们会安排每天的复习。',
                        action: TextButton.icon(
                          onPressed: () => _action(context, store.addExamples),
                          icon: const Icon(Icons.explore_outlined),
                          label: const Text('用三张示例体验一下'),
                        ),
                      )
                    : Column(
                        children: decks
                            .take(4)
                            .map(
                              (d) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _DeckTile(store: store, deck: d),
                              ),
                            )
                            .toList(),
                      ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 18,
                    color: c.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '先试着回忆，再揭晓答案。诚实的评分，才会带来适合你的复习节奏。',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.7,
                        color: c.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 监听原始触点，不参与手势竞争，保留卡片按钮和页面滚动。
class _TouchTiltCard extends StatefulWidget {
  const _TouchTiltCard({required this.child});
  final Widget child;

  @override
  State<_TouchTiltCard> createState() => _TouchTiltCardState();
}

class _TouchTiltCardState extends State<_TouchTiltCard>
    with SingleTickerProviderStateMixin {
  late final _return = AnimationController.unbounded(vsync: this);
  Offset _touch = Offset.zero;
  int? _pointer;
  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_reducedMotion) {
      _pointer = null;
      _return.value = 0;
    }
  }

  void _follow(PointerEvent event) {
    final box = context.findRenderObject()! as RenderBox;
    final position = box.globalToLocal(event.position);
    setState(() {
      _touch = Offset(
        (position.dx / box.size.width * 2 - 1).clamp(-1.0, 1.0),
        (position.dy / box.size.height * 2 - 1).clamp(-1.0, 1.0),
      );
    });
  }

  void _release(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _return.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 260, damping: 23),
        1,
        0,
        0,
      ),
    );
  }

  @override
  void dispose() {
    _return.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      if (_reducedMotion || _pointer != null) return;
      _pointer = event.pointer;
      _return.value = 1;
      _follow(event);
    },
    onPointerMove: (event) {
      if (event.pointer == _pointer) _follow(event);
    },
    onPointerUp: _release,
    onPointerCancel: _release,
    child: AnimatedBuilder(
      animation: _return,
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        final amount = _return.value;
        final light = amount.clamp(0.0, 1.0);
        final dark = Theme.of(context).brightness == Brightness.dark;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, .001)
            ..rotateX(_touch.dy * .10 * amount)
            ..rotateY(-_touch.dx * .10 * amount),
          child: Stack(
            children: [
              child!,
              if (light > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        gradient: RadialGradient(
                          center: Alignment(_touch.dx, _touch.dy),
                          radius: .85,
                          colors: [
                            Colors.white.withValues(
                              alpha: (dark ? .20 : .36) * light,
                            ),
                            Colors.white.withValues(alpha: .08 * light),
                            Colors.white.withValues(alpha: 0),
                          ],
                          stops: const [0, .35, 1],
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
  );
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (var i = 0; i < 5; i++) {
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        35 + i * 24,
        p,
      );
    }
    final dot = Paint()..color = color.withValues(alpha: .3);
    canvas.drawCircle(
      Offset(size.width / 2 + 82, size.height / 2 - 48),
      9,
      dot,
    );
  }

  @override
  bool shouldRepaint(_OrbitPainter oldDelegate) => oldDelegate.color != color;
}

String _studyTime(int milliseconds) {
  final seconds = (milliseconds / 1000).ceil();
  if (seconds < 60) return '$seconds 秒';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes 分 ${seconds % 60} 秒';
  return '${minutes ~/ 60} 小时 ${minutes % 60} 分';
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
    this.fontSize = 27,
    this.unit,
  });
  final String label, value;
  final IconData icon;
  final double fontSize;
  final String? unit;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    return _Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: math.max(19, scaler.scale(10) * 1.2),
            child: Row(
              children: [
                Icon(icon, size: 19, color: c.primary),
                if (unit != null) ...[
                  const SizedBox(width: 4),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        unit!,
                        style: TextStyle(
                          fontSize: 10,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            height: scaler.scale(27) * 1.3,
            width: double.infinity,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: fontSize,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: scaler.scale(12) * 1.4 * 2,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: c.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeckTile extends StatelessWidget {
  const _DeckTile({
    required this.store,
    required this.deck,
    this.onTap,
    this.selected = false,
    this.counts,
  });
  final AppStore store;
  final DeckData deck;
  final VoidCallback? onTap;
  final bool selected;
  final Map<String, int>? counts;
  @override
  Widget build(BuildContext context) => counts != null
      ? _card(context, counts)
      : FutureBuilder<Map<String, int>>(
          future: store.counts(deck.id),
          builder: (context, snapshot) => _card(context, snapshot.data),
        );

  Widget _card(BuildContext context, Map<String, int>? count) {
    final c = Theme.of(context).colorScheme;
    late final Widget card;
    card = Material(
      color: selected ? c.secondaryContainer : c.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap:
            onTap ??
            () =>
                _openDeckCard(context, store: store, deck: deck, closed: card),
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 54,
                decoration: BoxDecoration(
                  color: c.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.style_outlined, color: c.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deck.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      count == null
                          ? '正在统计卡片…'
                          : '${count['total']} 张卡片  ·  ${count['active']} 张在计划中',
                      style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: c.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
    return card;
  }
}

Future<void> _openDeckCard(
  BuildContext context, {
  required AppStore store,
  required DeckData deck,
  required Widget closed,
}) {
  final navigator = Navigator.of(context);
  final cardBox = context.findRenderObject()! as RenderBox;
  final navigatorBox = navigator.context.findRenderObject()! as RenderBox;
  final origin = cardBox.localToGlobal(Offset.zero, ancestor: navigatorBox);
  final source = origin & cardBox.size;
  return navigator.push<void>(
    _RowExpandRoute(
      source: source,
      closedRadius: BorderRadius.circular(24),
      closed: closed,
      page: _DeckPage(store: store, deckId: deck.id, initialDeck: deck),
      transition: _duration(context, 300),
    ),
  );
}

class _StudyCalendar extends StatefulWidget {
  const _StudyCalendar({required this.activity});
  final List<Map<String, dynamic>> activity;
  @override
  State<_StudyCalendar> createState() => _StudyCalendarState();
}

class _StudyCalendarState extends State<_StudyCalendar> {
  late DateTime _month;
  DateTime _selected = dayStart(DateTime.now());

  @override
  void initState() {
    super.initState();
    _month = DateTime(_selected.year, _selected.month);
  }

  void _move(int months) => setState(() {
    _month = DateTime(_month.year, _month.month + months);
    _selected = _month;
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final activity = {
      for (final row in widget.activity) row['day'] as String: row,
    };
    final leading = _month.weekday - 1;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final cellHeight = math.max(
      44.0,
      MediaQuery.textScalerOf(context).scale(14) * 1.3 + 20,
    );
    final today = dayKey(DateTime.now());
    final selected = activity[dayKey(_selected)];
    final count = selected == null
        ? 0
        : (selected['formal'] as int) +
              (selected['practice'] as int) +
              (selected['independent'] as int? ?? 0);
    return _Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              _GlassToolbar(
                children: [
                  IconButton(
                    tooltip: '上个月',
                    onPressed: () => _move(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_month.year}年${_month.month}月',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              _GlassToolbar(
                children: [
                  IconButton(
                    tooltip: '下个月',
                    onPressed: () => _move(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final weekday in ['一', '二', '三', '四', '五', '六', '日'])
                Expanded(
                  child: Center(
                    child: Text(
                      weekday,
                      style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var week = 0; week < 6; week++)
            Row(
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final day = week * 7 + column - leading + 1;
                        if (day < 1 || day > days) {
                          return SizedBox(height: cellHeight + 4);
                        }
                        final date = DateTime(_month.year, _month.month, day);
                        final key = dayKey(date);
                        final row = activity[key];
                        final total = row == null
                            ? 0
                            : (row['formal'] as int) +
                                  (row['practice'] as int) +
                                  (row['independent'] as int? ?? 0);
                        final isSelected = dayKey(_selected) == key;
                        return Semantics(
                          label: '$key，$total 次回忆${key == today ? '，今天' : ''}',
                          selected: isSelected,
                          button: true,
                          child: ExcludeSemantics(
                            child: Tooltip(
                              message: '$key · $total 次回忆',
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Material(
                                  color: isSelected
                                      ? c.primaryContainer
                                      : total > 0
                                      ? c.primary.withValues(
                                          alpha:
                                              .08 +
                                              math.min(total, 20) / 20 * .15,
                                        )
                                      : Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: key == today
                                        ? BorderSide(color: c.primary)
                                        : BorderSide.none,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () =>
                                        setState(() => _selected = date),
                                    child: SizedBox(
                                      height: cellHeight,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              '$day',
                                              maxLines: 1,
                                              style: TextStyle(
                                                fontSize: 14,
                                                height: 1.2,
                                                fontWeight:
                                                    key == today || isSelected
                                                    ? FontWeight.w700
                                                    : FontWeight.w400,
                                                color: isSelected
                                                    ? c.onPrimaryContainer
                                                    : c.onSurface,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Container(
                                            width: 4,
                                            height: 4,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: total > 0
                                                  ? c.primary
                                                  : Colors.transparent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(12) * 1.6 * 2,
            child: Center(
              child: Text(
                '${_selected.month}月${_selected.day}日 · $count 次回忆 · ${_studyTime(selected?['elapsed'] as int? ?? 0)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: c.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsPage extends StatelessWidget {
  const _StatsPage({required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => _Load(
      future: Future.wait([
        store.studySummary(),
        store.activity(),
        store.totalStudyTime(),
      ]),
      builder: (data) {
        final overview = data[0] as Map<String, dynamic>,
            activity = data[1] as List<Map<String, dynamic>>;
        final formal = overview['formal'] as int;
        return _Page(
          navigationTitle: '统计',
          title: '',
          subtitle: '',
          showHeading: false,
          children: [
            _StatisticsViews(store: store),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final seconds = ((data[2] as int) / 1000).ceil();
                final time = seconds < 60
                    ? ('$seconds', '秒')
                    : seconds < 3600
                    ? (
                        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                        '分:秒',
                      )
                    : (
                        '${seconds ~/ 3600}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}',
                        '小时:分',
                      );
                final values = [
                  '$formal',
                  formal == 0
                      ? '—'
                      : '${((overview['recalled'] as int) / formal * 100).round()}%',
                  time.$1,
                ];
                const numberStyle = TextStyle(
                  fontSize: 27,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1,
                );
                final painter = TextPainter(
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: 1,
                );
                var widest = 0.0;
                for (final value in values) {
                  painter.text = TextSpan(
                    text: value,
                    style: DefaultTextStyle.of(context).style
                        .merge(numberStyle),
                  );
                  painter.layout();
                  widest = math.max(widest, painter.width);
                }
                painter.dispose();
                final fontSize =
                    27.0 *
                    math.min(
                      1.0,
                      ((constraints.maxWidth - 20) / 3 - 32) / widest,
                    );
                return Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        label: '今日首次回忆',
                        value: values[0],
                        fontSize: fontSize,
                        icon: Icons.check_circle_outline,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Metric(
                        label: '认识与熟知',
                        value: values[1],
                        fontSize: fontSize,
                        icon: Icons.psychology_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Metric(
                        label: '累计学习时间',
                        value: values[2],
                        fontSize: fontSize,
                        unit: time.$2,
                        icon: Icons.timelapse_rounded,
                      ),
                    ),
                  ],
                );
              },
            ),
            const _SectionLabel('学习日历'),
            _StudyCalendar(activity: activity),
            const _SectionLabel('最近学习'),
            if (activity.isEmpty)
              const _Empty(
                icon: Icons.show_chart_rounded,
                title: '成长会留下痕迹',
                detail: '完成第一次学习后，回忆表现与学习用时会出现在这里。',
              )
            else
              _Panel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                child: Column(
                  children: activity
                      .take(7)
                      .map(
                        (row) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(row['day']),
                          subtitle: Text(
                            '首次 ${row['formal']} 次 · 重学 ${row['practice']} 次${(row['independent'] as int? ?? 0) > 0 ? ' · 专项 ${row['independent']} 次' : ''}',
                          ),
                          trailing: Text(
                            '${((row['elapsed'] as int) / 60000).ceil()} 分钟',
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
          ],
        );
      },
    ),
  );
}
