part of 'app.dart';

class _StatisticsViews extends StatefulWidget {
  const _StatisticsViews({required this.store});
  final AppStore store;
  @override
  State<_StatisticsViews> createState() => _StatisticsViewsState();
}

class _StatisticsViewsState extends State<_StatisticsViews>
    with AutomaticKeepAliveClientMixin<_StatisticsViews> {
  int _tab = 0;
  bool _cognition = true;
  StatisticsPeriod _period = StatisticsPeriod.day;
  late int _revision;
  late Future<(Map<String, dynamic>, List<LearningBucket>)> _data;
  // 离开视口后保留图表，避免回滑时重新加载使列表高度骤变。
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _revision = widget.store.revision;
    _data =
        Future.wait([
          _tab == 0
              ? widget.store.retentionStats(days: 30)
              : Future.value(<String, dynamic>{}),
          _tab != 0
              ? widget.store.learningStatistics(period: _period)
              : Future.value(<LearningBucket>[]),
        ]).then(
          (values) => (
            values[0] as Map<String, dynamic>,
            values[1] as List<LearningBucket>,
          ),
        );
  }

  @override
  void didUpdateWidget(_StatisticsViews oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_revision != widget.store.revision) _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatsChoices<int>(
          options: const {0: '遗忘曲线', 1: '学习情况', 2: '记忆持久度'},
          value: _tab,
          onChanged: (v) => setState(() {
            _tab = v;
            _load();
          }),
        ),
        const SizedBox(height: 16),
        if (_tab != 0) ...[
          if (_tab == 1) ...[
            _StatsChoices<bool>(
              options: const {true: '认知情况', false: '复习新学'},
              value: _cognition,
              onChanged: (v) => setState(() => _cognition = v),
            ),
            const SizedBox(height: 12),
          ],
          _StatsChoices<StatisticsPeriod>(
            options: {for (final p in StatisticsPeriod.values) p: p.label},
            value: _period,
            onChanged: (v) => setState(() {
              _period = v;
              _load();
            }),
          ),
          const SizedBox(height: 16),
        ],
        FutureBuilder<(Map<String, dynamic>, List<LearningBucket>)>(
          future: _data,
          builder: (context, snapshot) {
            // 时间粒度改变时不能继续显示旧分组，否则选中索引与新分组错位。
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 360,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            if (snapshot.hasError) return Text('加载失败：${snapshot.error}');
            final data = snapshot.requireData;
            final theme = Theme.of(context).colorScheme;
            final now = DateTime.now();
            final all = data.$2;
            final today = all.indexWhere(
              (b) => !now.isBefore(b.start) && now.isBefore(b.end),
            );
            final colors = _StatisticsColors(theme);
            late List<_StatSeries> series;
            late List<String> labels;
            late int selected;
            late String title;
            late bool bars;
            late bool percentage;
            late List<LearningBucket> buckets;
            if (_tab == 0) {
              buckets = const [];
              title = '遗忘曲线';
              labels = [
                for (var d = 0; d <= 30; d++)
                  d == 0
                      ? '今天'
                      : d == 1
                      ? '明天'
                      : d == 2
                      ? '后天'
                      : '+$d天',
              ];
              selected = 0;
              bars = false;
              percentage = true;
              series = [
                _StatSeries(
                  '你的学习遗忘曲线',
                  theme.primary,
                  (data.$1['learningCurve'] as List).cast<double?>(),
                  fill: true,
                ),
                _StatSeries('艾宾浩斯遗忘曲线', colors.neutral, [
                  for (var d = 0; d <= 30; d++)
                    ebbinghausReference(d.toDouble()),
                ], dashed: true),
              ];
            } else if (_tab == 1) {
              buckets = all;
              title = '学习情况';
              labels = [
                for (var i = 0; i < all.length; i++)
                  _bucketLabel(all[i], i == today),
              ];
              selected = today;
              bars = true;
              percentage = false;
              List<double?> values(
                int Function(LearningBucket) read, {
                bool historyOnly = true,
              }) => [
                for (final b in all)
                  historyOnly && b.start.isAfter(now)
                      ? null
                      : read(b).toDouble(),
              ];
              series = _cognition
                  ? [
                      _StatSeries(
                        '认识',
                        colors.know,
                        values((b) => b.grades[0]),
                        stacked: true,
                      ),
                      _StatSeries(
                        '模糊',
                        colors.vague,
                        values((b) => b.grades[1]),
                        stacked: true,
                      ),
                      _StatSeries(
                        '忘记',
                        colors.forget,
                        values((b) => b.grades[2]),
                        stacked: true,
                      ),
                      _StatSeries(
                        '熟知',
                        colors.mastered,
                        values((b) => b.grades[3]),
                        stacked: true,
                      ),
                      _StatSeries(
                        '待学',
                        colors.pending,
                        values((b) => b.pending, historyOnly: false),
                      ),
                    ]
                  : [
                      _StatSeries(
                        '新学',
                        colors.know,
                        values((b) => b.newCards),
                        stacked: true,
                      ),
                      _StatSeries(
                        '复习',
                        colors.mastered,
                        values((b) => b.reviewCards),
                        stacked: true,
                      ),
                      _StatSeries(
                        '待学',
                        colors.pending,
                        values((b) => b.pending, historyOnly: false),
                      ),
                    ];
            } else {
              buckets = all.take(today + 1).toList();
              title = '记忆持久度';
              labels = [
                for (var i = 0; i < buckets.length; i++)
                  _bucketLabel(buckets[i], i == today),
              ];
              selected = today;
              bars = false;
              percentage = false;
              series = [
                _StatSeries('已加入学习的全部卡片', colors.neutral, [
                  for (final b in buckets) b.enrolled.toDouble(),
                ]),
                for (var j = 0; j < 4; j++)
                  _StatSeries(
                    '记忆持久度 ≥ ${[10, 30, 60, 90][j]} 天',
                    colors.durability[j],
                    [for (final b in buckets) b.durability[j]?.toDouble()],
                    fill: true,
                  ),
              ];
            }
            return AnimatedSwitcher(
              duration: _duration(context, 240),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              child: _Panel(
                key: ValueKey('panel-$_tab-$_period-$_cognition-$_revision'),
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _StatisticsGraph(
                      key: ValueKey('$_tab-$_period-$_cognition-$_revision'),
                      series: series,
                      labels: labels,
                      initialIndex: selected,
                      bars: bars,
                      percentage: percentage,
                      bucketDetails: buckets,
                      showRatios: _tab == 2,
                    ),
                    if (_tab == 0 && data.$1['modeledCards'] == 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(
                          '完成首次学习后显示你的个人曲线。',
                          style: TextStyle(color: theme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  String _bucketLabel(LearningBucket b, bool current) => current
      ? switch (_period) {
          StatisticsPeriod.day => '今天',
          StatisticsPeriod.week => '本周',
          StatisticsPeriod.month => '本月',
        }
      : switch (_period) {
          StatisticsPeriod.day => '${b.start.month}/${b.start.day}',
          StatisticsPeriod.week => '${b.start.month}/${b.start.day}周',
          StatisticsPeriod.month => '${b.start.year % 100}/${b.start.month}月',
        };
}

class _StatsChoices<T> extends StatelessWidget {
  const _StatsChoices({
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => _GlassSegments<T>(
    options: options,
    value: value,
    onChanged: onChanged,
    stretch: options.values.any((label) => label.length >= 4),
  );
}

// 各色经 dataviz 校验：相邻色在色觉缺陷模拟下 ΔE ≥ 8，正常视觉 ΔE ≥ 15。
class _StatisticsColors {
  _StatisticsColors(ColorScheme scheme)
    : know = _dark(scheme) ? const Color(0xff199e70) : const Color(0xff1f9e74),
      vague = _dark(scheme) ? const Color(0xffc98500) : const Color(0xffe09b00),
      forget = _dark(scheme)
          ? const Color(0xffd9466e)
          : const Color(0xffd9473f),
      mastered = _dark(scheme)
          ? const Color(0xff3987e5)
          : const Color(0xff2a78d6),
      durability = _dark(scheme)
          ? const [
              Color(0xff1b7a5f),
              Color(0xff2fa07f),
              Color(0xff5cc4a2),
              Color(0xff9be3c9),
            ]
          : const [
              Color(0xff5fb596),
              Color(0xff2e977a),
              Color(0xff16795f),
              Color(0xff0b4d3c),
            ],
      neutral = scheme.onSurfaceVariant,
      pending = scheme.outlineVariant;
  static bool _dark(ColorScheme s) => s.brightness == Brightness.dark;
  final Color know, vague, forget, mastered, neutral, pending;
  final List<Color> durability;
}

class _StatSeries {
  const _StatSeries(
    this.label,
    this.color,
    this.values, {
    this.stacked = false,
    this.fill = false,
    this.dashed = false,
  });
  final String label;
  final Color color;
  final List<double?> values;
  // stacked：柱状图中叠成同一根柱；fill：折线下方绘制渐变面积；dashed：参考线。
  final bool stacked, fill, dashed;
}

class _StatisticsGraph extends StatefulWidget {
  const _StatisticsGraph({
    super.key,
    required this.series,
    required this.labels,
    required this.initialIndex,
    required this.bars,
    required this.percentage,
    required this.bucketDetails,
    required this.showRatios,
  });
  final List<_StatSeries> series;
  final List<String> labels;
  final int initialIndex;
  final bool bars, percentage, showRatios;
  final List<LearningBucket> bucketDetails;
  @override
  State<_StatisticsGraph> createState() => _StatisticsGraphState();
}

class _StatisticsGraphState extends State<_StatisticsGraph> {
  late int _selected = widget.initialIndex;
  // 每张图自行定位当前日期，不继承其他统计图的 PageStorage 偏移。
  final _scroll = ScrollController(keepScrollOffset: false);
  final _viewport = GlobalKey();
  bool _positioned = false;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final textScaler = MediaQuery.textScalerOf(context);
    final slot = 46.0 * math.max(1, textScaler.scale(1));
    // 叠放柱按整根柱高取最大值，否则顶部会越出绘图区。
    final stacked = widget.series.where((s) => s.stacked);
    final rawMax = [
      for (final s in widget.series.where((s) => !s.stacked))
        ...s.values.whereType<double>(),
      for (var i = 0; i < widget.labels.length; i++)
        stacked.fold<double>(0, (sum, s) => sum + (s.values[i] ?? 0)),
    ].fold<double>(0, math.max);
    final maxY = widget.percentage
        ? 100.0
        : rawMax <= 10
        ? 10.0
        : (rawMax / 5).ceil() * 5.0;
    final chartHeight = 280.0 + textScaler.scale(12);
    final labelHeight = textScaler.scale(12) + 18;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients || _positioned) return;
      _positioned = true;
      if (widget.initialIndex > 0) {
        _scroll.jumpTo(
          math.min(
            _scroll.position.maxScrollExtent,
            math.max(0, (widget.initialIndex - 1) * slot),
          ),
        );
      }
    });
    Widget number(double? value) => Text(
      value == null
          ? '—'
          : '${value.toStringAsFixed(widget.percentage ? 1 : 0)}${widget.percentage ? '%' : ''}',
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: textScaler.scale(35) + 4,
              height: chartHeight,
              child: CustomPaint(
                painter: _StatisticsAxisPainter(
                  maxY: maxY,
                  percentage: widget.percentage,
                  color: c.onSurfaceVariant,
                  scaler: textScaler,
                  labelHeight: labelHeight,
                ),
              ),
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    ...ScrollConfiguration.of(context).dragDevices,
                    PointerDeviceKind.mouse,
                  },
                ),
                child: SingleChildScrollView(
                  key: _viewport,
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: GestureDetector(
                    // 图表不能成为一个巨大的语义按钮；Web 无障碍点击会被
                    // 合成为该按钮中心的点击，丢失用户实际选中的日期坐标。
                    // 读屏使用下方前后按钮选点，图表本身只朗读当前数据。
                    excludeFromSemantics: true,
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) {
                      final box =
                          _viewport.currentContext!.findRenderObject()
                              as RenderBox;
                      final x =
                          box.globalToLocal(details.globalPosition).dx +
                          _scroll.offset;
                      setState(
                        () => _selected = (x / slot).floor().clamp(
                          0,
                          widget.labels.length - 1,
                        ),
                      );
                    },
                    child: Semantics(
                      label:
                          '${widget.labels[_selected]}，${[for (final s in widget.series) '${s.label} ${s.values[_selected]?.toStringAsFixed(1) ?? '无数据'}'].join('，')}',
                      child: SizedBox(
                        width: slot * widget.labels.length,
                        height: chartHeight,
                        child: CustomPaint(
                          painter: _StatisticsPlotPainter(
                            series: widget.series,
                            labels: widget.labels,
                            selected: _selected,
                            maxY: maxY,
                            bars: widget.bars,
                            color: c.primary,
                            surface: c.surfaceContainerLow,
                            gridColor: c.outlineVariant.withValues(alpha: .45),
                            labelColor: c.onSurfaceVariant,
                            scaler: textScaler,
                            labelHeight: labelHeight,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
          decoration: ShapeDecoration(
            color: c.surfaceContainerHigh.withValues(alpha: .6),
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: '上一个时间点',
                    visualDensity: VisualDensity.compact,
                    onPressed: _selected == 0
                        ? null
                        : () => _pick(_selected - 1, slot),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Text(
                      widget.labels[_selected],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.primary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '下一个时间点',
                    visualDensity: VisualDensity.compact,
                    onPressed: _selected == widget.labels.length - 1
                        ? null
                        : () => _pick(_selected + 1, slot),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              for (var i = 0; i < widget.series.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        height: 12,
                        child: CustomPaint(
                          painter: _LegendKeyPainter(
                            widget.series[i],
                            bar: widget.bars,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.series[i].label,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      number(widget.series[i].values[_selected]),
                      if (widget.showRatios &&
                          i > 0 &&
                          widget.series[i].values[_selected] != null)
                        Text(
                          ' · ${widget.bucketDetails[_selected].enrolled == 0 ? '0' : (widget.series[i].values[_selected]! / widget.bucketDetails[_selected].enrolled * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 12,
                            color: c.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              if (widget.bars) ...[
                Divider(
                  height: 14,
                  indent: 10,
                  endIndent: 10,
                  color: c.outlineVariant.withValues(alpha: .5),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 16,
                        color: c.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '学习时长：${(widget.bucketDetails[_selected].elapsedMs / 60000).floor()} 分 ${(widget.bucketDetails[_selected].elapsedMs / 1000).floor() % 60} 秒',
                          style: TextStyle(
                            fontSize: 13,
                            color: c.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _pick(int index, double slot) {
    setState(() => _selected = index);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240);
    _scroll.animateTo(
      (index * slot - slot).clamp(0, _scroll.position.maxScrollExtent),
      duration: duration,
      curve: Curves.easeOutCubic,
    );
  }
}

class _StatisticsAxisPainter extends CustomPainter {
  _StatisticsAxisPainter({
    required this.maxY,
    required this.percentage,
    required this.color,
    required this.scaler,
    required this.labelHeight,
  });
  final double maxY, labelHeight;
  final bool percentage;
  final Color color;
  final TextScaler scaler;
  @override
  void paint(Canvas canvas, Size size) {
    final text = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    );
    final height = size.height - labelHeight - 12;
    for (var i = 0; i <= 5; i++) {
      text.text = TextSpan(
        text: '${(maxY * (5 - i) / 5).round()}${percentage ? '%' : ''}',
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
      text.layout();
      text.paint(
        canvas,
        Offset(
          size.width - text.width - 6,
          6 + height * i / 5 - text.height / 2,
        ),
      );
    }
    text.dispose();
  }

  @override
  bool shouldRepaint(_StatisticsAxisPainter old) =>
      maxY != old.maxY ||
      percentage != old.percentage ||
      color != old.color ||
      scaler != old.scaler;
}

class _LegendKeyPainter extends CustomPainter {
  _LegendKeyPainter(this.series, {required this.bar});
  final _StatSeries series;
  final bool bar;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    if (bar) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: 12, height: 12),
          const Radius.circular(4),
        ),
        Paint()..color = series.color,
      );
      return;
    }
    final line = Path()
      ..moveTo(1, center.dy)
      ..lineTo(size.width - 1, center.dy);
    canvas.drawPath(
      series.dashed ? _dashed(line) : line,
      Paint()
        ..color = series.color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    if (!series.dashed) {
      canvas.drawCircle(center, 3.5, Paint()..color = series.color);
    }
  }

  @override
  bool shouldRepaint(_LegendKeyPainter old) =>
      old.series.color != series.color || old.bar != bar;
}

Path _dashed(Path source, {double dash = 5, double gap = 4}) {
  final out = Path();
  for (final metric in source.computeMetrics()) {
    for (var d = 0.0; d < metric.length; d += dash + gap) {
      out.addPath(metric.extractPath(d, d + dash), Offset.zero);
    }
  }
  return out;
}

class _StatisticsPlotPainter extends CustomPainter {
  _StatisticsPlotPainter({
    required this.series,
    required this.labels,
    required this.selected,
    required this.maxY,
    required this.bars,
    required this.color,
    required this.surface,
    required this.gridColor,
    required this.labelColor,
    required this.scaler,
    required this.labelHeight,
  });
  final List<_StatSeries> series;
  final List<String> labels;
  final int selected;
  final double maxY, labelHeight;
  final bool bars;
  final Color color, surface, gridColor, labelColor;
  final TextScaler scaler;
  @override
  void paint(Canvas canvas, Size size) {
    final slot = size.width / labels.length;
    final height = size.height - labelHeight - 12;
    final bottom = height + 6;
    double yOf(double v) => bottom - v / maxY * height;

    // 选中列：圆角高亮底，标签放进同色胶囊。
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(selected * slot + 3, 0, slot - 6, bottom + 4),
        const Radius.circular(12),
      ),
      Paint()..color = color.withValues(alpha: .07),
    );
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final y = 6 + height * i / 5;
      canvas.drawPath(
        _dashed(
          Path()
            ..moveTo(0, y)
            ..lineTo(size.width, y),
          dash: 3,
          gap: 4,
        ),
        grid..style = PaintingStyle.stroke,
      );
    }
    canvas.drawLine(
      Offset(0, bottom),
      Offset(size.width, bottom),
      Paint()
        ..color = gridColor.withValues(alpha: 1)
        ..strokeWidth = 1,
    );

    final text = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    );
    for (var i = 0; i < labels.length; i++) {
      final active = i == selected;
      text.text = TextSpan(
        text: labels[i],
        style: TextStyle(
          fontSize: 10,
          color: active ? color : labelColor,
          fontWeight: active ? FontWeight.w700 : FontWeight.normal,
        ),
      );
      text.layout();
      final origin = Offset((i + .5) * slot - text.width / 2, bottom + 10);
      if (active) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              origin.dx - 6,
              origin.dy - 3,
              text.width + 12,
              text.height + 6,
            ),
            Radius.circular(text.height),
          ),
          Paint()..color = color.withValues(alpha: .14),
        );
      }
      text.paint(canvas, origin);
    }
    text.dispose();

    if (bars) {
      _paintBars(canvas, slot, bottom, yOf);
    } else {
      _paintLines(canvas, size, slot, bottom, yOf);
    }
  }

  void _paintBars(
    Canvas canvas,
    double slot,
    double bottom,
    double Function(double) yOf,
  ) {
    final stacked = [
      for (final s in series)
        if (s.stacked) s,
    ];
    final singles = [
      for (final s in series)
        if (!s.stacked) s,
    ];
    final groups = (stacked.isEmpty ? 0 : 1) + singles.length;
    const gap = 3.0;
    final w = math.min(18.0, (slot * .64 - gap * (groups - 1)) / groups);
    final start = (slot - (w * groups + gap * (groups - 1))) / 2;
    const radius = Radius.circular(4);
    for (var i = 0; i < labels.length; i++) {
      final alpha = i == selected ? 1.0 : .82;
      var left = i * slot + start;
      if (stacked.isNotEmpty) {
        var base = bottom;
        final visible = [
          for (final s in stacked)
            if ((s.values[i] ?? 0) > 0) s,
        ];
        for (var k = 0; k < visible.length; k++) {
          final s = visible[k];
          final h = bottom - yOf(s.values[i]!);
          final top = k == visible.length - 1;
          // 段间留 2px 表面色缝隙，只给最顶段做圆角数据端。
          final segment = Rect.fromLTWH(
            left,
            base - h,
            w,
            math.max(0, h - (k == 0 ? 0 : 2)),
          );
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              segment,
              topLeft: top ? radius : Radius.zero,
              topRight: top ? radius : Radius.zero,
            ),
            Paint()..color = s.color.withValues(alpha: alpha),
          );
          base -= h;
        }
        left += w + gap;
      }
      for (final s in singles) {
        final v = s.values[i];
        if (v != null && v > 0) {
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              Rect.fromLTRB(left, yOf(v), left + w, bottom),
              topLeft: radius,
              topRight: radius,
            ),
            Paint()..color = s.color.withValues(alpha: alpha),
          );
        }
        left += w + gap;
      }
    }
  }

  void _paintLines(
    Canvas canvas,
    Size size,
    double slot,
    double bottom,
    double Function(double) yOf,
  ) {
    canvas.drawLine(
      Offset((selected + .5) * slot, 6),
      Offset((selected + .5) * slot, bottom),
      Paint()
        ..color = color.withValues(alpha: .35)
        ..strokeWidth = 1,
    );
    final fills = series.where((s) => s.fill).length;
    for (final s in series) {
      // 按空值断开成多段；水平控制点的三次曲线在相邻点间单调，不会越界。
      final segments = <List<Offset>>[[]];
      for (var i = 0; i < s.values.length; i++) {
        final v = s.values[i];
        if (v == null) {
          if (segments.last.isNotEmpty) segments.add([]);
          continue;
        }
        segments.last.add(Offset((i + .5) * slot, yOf(v)));
      }
      for (final points in segments.where((p) => p.isNotEmpty)) {
        final line = Path()..moveTo(points.first.dx, points.first.dy);
        for (var k = 1; k < points.length; k++) {
          final a = points[k - 1], b = points[k];
          final mid = (a.dx + b.dx) / 2;
          line.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
        }
        if (s.fill && points.length > 1) {
          final area = Path.from(line)
            ..lineTo(points.last.dx, bottom)
            ..lineTo(points.first.dx, bottom)
            ..close();
          canvas.drawPath(
            area,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  s.color.withValues(alpha: fills > 1 ? .10 : .22),
                  s.color.withValues(alpha: 0),
                ],
              ).createShader(Rect.fromLTRB(0, 6, size.width, bottom)),
          );
        }
        canvas.drawPath(
          s.dashed ? _dashed(line) : line,
          Paint()
            ..color = s.color
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
        if (points.length == 1) {
          canvas.drawCircle(points.first, 3, Paint()..color = s.color);
        }
      }
    }
    // 选中点最后绘制，带表面色描边，避免被其他线遮住。
    for (final s in series) {
      final v = s.values[selected];
      if (v == null) continue;
      final center = Offset((selected + .5) * slot, yOf(v));
      canvas.drawCircle(center, 6, Paint()..color = surface);
      canvas.drawCircle(center, 4.5, Paint()..color = s.color);
    }
  }

  @override
  bool shouldRepaint(_StatisticsPlotPainter old) => true;
}
