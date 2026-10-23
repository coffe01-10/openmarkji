part of 'app.dart';

class _StatisticsViews extends StatefulWidget {
  const _StatisticsViews({required this.store});
  final AppStore store;
  @override
  State<_StatisticsViews> createState() => _StatisticsViewsState();
}

class _StatisticsViewsState extends State<_StatisticsViews> {
  int _tab = 0;
  bool _cognition = true;
  StatisticsPeriod _period = StatisticsPeriod.day;
  late int _revision;
  late Future<(Map<String, dynamic>, List<LearningBucket>)> _data;
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
  Widget build(BuildContext context) => Column(
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
          late String note;
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
                colors.total,
                (data.$1['learningCurve'] as List).cast<double?>(),
              ),
              _StatSeries('艾宾浩斯遗忘曲线', colors.teal, [
                for (var d = 0; d <= 30; d++) ebbinghausReference(d.toDouble()),
              ]),
            ];
            note =
                '个人曲线按 ${data.$1['modeledCards']} 张已学卡片的 MMX 状态估算，从刚复习后的 100% 起算，假设之后不再复习。参考线按经典采样插值示意，节省率与个人回忆概率并非同一测量指标。';
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
                historyOnly && b.start.isAfter(now) ? null : read(b).toDouble(),
            ];
            series = _cognition
                ? [
                    _StatSeries('认识', colors.know, values((b) => b.grades[0])),
                    _StatSeries('模糊', colors.vague, values((b) => b.grades[1])),
                    _StatSeries('忘记', colors.total, values((b) => b.grades[2])),
                    _StatSeries('熟知', colors.teal, values((b) => b.grades[3])),
                    _StatSeries(
                      '待学',
                      colors.pending,
                      values((b) => b.pending, historyOnly: false),
                    ),
                  ]
                : [
                    _StatSeries('新学', colors.know, values((b) => b.newCards)),
                    _StatSeries(
                      '复习',
                      colors.total,
                      values((b) => b.reviewCards),
                    ),
                    _StatSeries(
                      '待学',
                      colors.pending,
                      values((b) => b.pending, historyOnly: false),
                    ),
                  ];
            note = '认知情况与复习新学仅计正式首次评分，当日重学不重复计数；用时包含当日重学。灰色待学按当前排期预测，逾期卡片计入今天，未包含未来新增卡片。';
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
              _StatSeries('已加入学习的全部卡片', colors.total, [
                for (final b in buckets) b.enrolled.toDouble(),
              ]),
              for (var j = 0; j < 4; j++)
                _StatSeries(
                  '记忆持久度 ≥ ${[10, 30, 60, 90][j]} 天',
                  [colors.vague, colors.know, colors.teal, colors.deepTeal][j],
                  [for (final b in buckets) b.durability[j]?.toDouble()],
                ),
            ];
            note = '持久度为安排的复习间隔；各门槛累计包含，≥90 天也计入 ≥10 天。按当前学习计划（含暂停）回看各期末状态，已移出或删除的卡片不计。旧记录按保存状态估算，缺失状态处留空。';
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
                  const SizedBox(height: 6),
                  Text(
                    '左右滑动查看 · 点选日期查看数值',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.onSurfaceVariant,
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
                  const SizedBox(height: 18),
                  Text(
                    note,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: theme.onSurfaceVariant,
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

class _StatisticsColors {
  _StatisticsColors(ColorScheme scheme)
    : total = scheme.brightness == Brightness.dark
          ? const Color(0xffff976e)
          : const Color(0xffe9673f),
      vague = scheme.brightness == Brightness.dark
          ? const Color(0xffffc164)
          : const Color(0xffcc8600),
      know = scheme.brightness == Brightness.dark
          ? const Color(0xff92d4c2)
          : const Color(0xff4a9d88),
      teal = scheme.brightness == Brightness.dark
          ? const Color(0xff54d8c6)
          : const Color(0xff009e8b),
      deepTeal = scheme.brightness == Brightness.dark
          ? const Color(0xff4fa99d)
          : const Color(0xff14675b),
      pending = scheme.outlineVariant;
  final Color total, vague, know, teal, deepTeal, pending;
}

class _StatSeries {
  const _StatSeries(this.label, this.color, this.values);
  final String label;
  final Color color;
  final List<double?> values;
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
    final rawMax = widget.series
        .expand((s) => s.values)
        .whereType<double>()
        .fold<double>(0, math.max);
    final maxY = widget.percentage
        ? 100.0
        : rawMax <= 10
        ? 10.0
        : (rawMax / 5).ceil() * 5.0;
    final chartHeight = 280.0 + textScaler.scale(12);
    final labelHeight = textScaler.scale(12) + 14;
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
      style: const TextStyle(fontWeight: FontWeight.w600),
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
                            gridColor: c.outlineVariant.withValues(alpha: .35),
                            stripeColor: c.onSurface.withValues(alpha: .025),
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
        const SizedBox(height: 20),
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
                style: TextStyle(fontWeight: FontWeight.w600, color: c.primary),
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
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: widget.bars ? 12 : 3,
                        width: 22,
                        decoration: BoxDecoration(
                          color: widget.series[i].color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      if (!widget.bars)
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: widget.series[i].color,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
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
                    style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        if (widget.bars) ...[
          const SizedBox(height: 8),
          Text(
            '学习时长：${(widget.bucketDetails[_selected].elapsedMs / 60000).floor()} 分 ${(widget.bucketDetails[_selected].elapsedMs / 1000).floor() % 60} 秒',
            style: TextStyle(fontSize: 13, color: c.onSurfaceVariant),
          ),
        ],
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
        style: TextStyle(fontSize: 10, color: color),
      );
      text.layout();
      text.paint(
        canvas,
        Offset(
          size.width - text.width - 5,
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

class _StatisticsPlotPainter extends CustomPainter {
  _StatisticsPlotPainter({
    required this.series,
    required this.labels,
    required this.selected,
    required this.maxY,
    required this.bars,
    required this.color,
    required this.gridColor,
    required this.stripeColor,
    required this.labelColor,
    required this.scaler,
    required this.labelHeight,
  });
  final List<_StatSeries> series;
  final List<String> labels;
  final int selected;
  final double maxY, labelHeight;
  final bool bars;
  final Color color, gridColor, stripeColor, labelColor;
  final TextScaler scaler;
  @override
  void paint(Canvas canvas, Size size) {
    final slot = size.width / labels.length;
    final height = size.height - labelHeight - 12;
    final bottom = height + 6;
    final text = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    );
    for (var i = 0; i < labels.length; i++) {
      if (i.isEven) {
        canvas.drawRect(
          Rect.fromLTWH(i * slot, 6, slot, height),
          Paint()..color = stripeColor,
        );
      }
      text.text = TextSpan(
        text: labels[i],
        style: TextStyle(
          fontSize: 10,
          color: i == selected ? color : labelColor,
          fontWeight: i == selected ? FontWeight.w700 : FontWeight.normal,
        ),
      );
      text.layout();
      text.paint(canvas, Offset((i + .5) * slot - text.width / 2, bottom + 9));
    }
    for (var i = 0; i <= 5; i++) {
      final y = 6 + height * i / 5;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = gridColor
          ..strokeWidth = .7,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(selected * slot, 6, slot, height),
      Paint()..color = color.withValues(alpha: .05),
    );
    for (var j = 0; j < series.length; j++) {
      final s = series[j];
      final path = Path();
      var connected = false;
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < s.values.length; i++) {
        final v = s.values[i];
        if (v == null) {
          connected = false;
          continue;
        }
        final x = (i + .5) * slot;
        final y = bottom - v / maxY * height;
        if (bars) {
          final w = slot * .7 / series.length;
          if (v > 0) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(
                  i * slot + slot * .15 + j * w,
                  y,
                  w - 1,
                  bottom - y,
                ),
                const Radius.circular(2),
              ),
              Paint()..color = s.color,
            );
          }
        } else {
          if (connected) {
            path.lineTo(x, y);
          } else {
            path.moveTo(x, y);
          }
          connected = true;
          canvas.drawCircle(
            Offset(x, y),
            i == selected ? 4.5 : 2.5,
            Paint()..color = s.color,
          );
        }
      }
      if (!bars) canvas.drawPath(path, paint);
    }
    text.dispose();
  }

  @override
  bool shouldRepaint(_StatisticsPlotPainter old) => true;
}
