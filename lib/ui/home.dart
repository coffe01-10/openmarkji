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
              Container(
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
                              color: c.onPrimaryContainer.withValues(alpha: .8),
                            ),
                          ),
                          const SizedBox(height: 26),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: remaining > 0
                                  ? () =>
                                        _push(context, _StudyPage(store: store))
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
                        ],
                      ),
                    ),
                  ],
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
              _SectionLabel(
                '我的学习空间',
                trailing: TextButton(
                  onPressed: onLibrary,
                  child: const Text('全部牌组 →'),
                ),
              ),
              _Load(
                future: store.decks(),
                builder: (decks) => decks.isEmpty
                    ? _Empty(
                        icon: Icons.spa_outlined,
                        title: '先种下一颗知识的种子',
                        detail: '导入墨墨文本，或写下自己的第一张卡。\n选入计划后，我们会安排每天的复习。',
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
                                child: _DeckTile(
                                  store: store,
                                  deck: d,
                                  onTap: () => _push(
                                    context,
                                    _DeckPage(store: store, deckId: d.id),
                                  ),
                                ),
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

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon});
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return _Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: c.primary),
          const SizedBox(height: 15),
          Text(
            value,
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w600,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
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
    required this.onTap,
    this.selected = false,
  });
  final AppStore store;
  final DeckData deck;
  final VoidCallback onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Material(
      color: selected ? c.secondaryContainer : c.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
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
                    _Load(
                      future: store.counts(deck.id),
                      builder: (count) => Text(
                        '${count['total']} 张卡片  ·  ${count['active']} 张在计划中',
                        style: TextStyle(
                          fontSize: 12,
                          color: c.onSurfaceVariant,
                        ),
                      ),
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
  }
}

class _StatsPage extends StatelessWidget {
  const _StatsPage({required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => _Load(
      future: Future.wait([store.overview(), store.activity()]),
      builder: (data) {
        final overview = data[0] as Map<String, dynamic>,
            activity = data[1] as List<Map<String, dynamic>>;
        final formal = overview['formal'] as int;
        final c = Theme.of(context).colorScheme;
        return _Page(
          navigationTitle: '统计',
          title: '',
          subtitle: '',
          showHeading: false,
          children: [
            _StatisticsViews(store: store),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: '今日首次回忆',
                    value: '$formal',
                    icon: Icons.check_circle_outline,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Metric(
                    label: '认识与熟知',
                    value: formal == 0
                        ? '—'
                        : '${((overview['recalled'] as int) / formal * 100).round()}%',
                    icon: Icons.psychology_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Metric(
                    label: '学习分钟',
                    value: '${((overview['elapsed'] as int) / 60000).ceil()}',
                    icon: Icons.timelapse_rounded,
                  ),
                ),
              ],
            ),
            const _SectionLabel('学习日历'),
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('过去 12 周', style: TextStyle(color: c.onSurfaceVariant)),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final map = {
                        for (final row in activity)
                          row['day'] as String:
                              (row['formal'] as int) + (row['practice'] as int),
                      };
                      final now = DateTime.now();
                      return Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: List.generate(84, (index) {
                          final date = DateTime(
                            now.year,
                            now.month,
                            now.day - (83 - index),
                          );
                          final count = map[dayKey(date)] ?? 0;
                          return Tooltip(
                            message: '${dayKey(date)} · $count 次回忆',
                            child: Container(
                              width: (constraints.maxWidth - 13 * 5) / 14,
                              height: 18,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(5),
                                color: count == 0
                                    ? c.surfaceContainerHighest
                                    : c.primary.withValues(
                                        alpha:
                                            (.25 +
                                            math.min(count, 20) / 20 * .75),
                                      ),
                              ),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      Text(
                        '${activity.length} 个学习日',
                        style: TextStyle(
                          fontSize: 12,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '浅 → 深  ·  回忆次数增加',
                        style: TextStyle(
                          fontSize: 10,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
                            '首次 ${row['formal']} 次 · 重学 ${row['practice']} 次',
                          ),
                          trailing: Text(
                            '${((row['elapsed'] as int) / 60000).ceil()} 分钟',
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              '回忆表现仅统计首次评分；重学单独记录。未来数量根据当前排期计算，未包含未来新卡。',
              style: TextStyle(
                fontSize: 12,
                height: 1.7,
                color: c.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    ),
  );
}
