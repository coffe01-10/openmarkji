part of 'app.dart';

const _recallChoices = [
  RecallGrade.know,
  RecallGrade.vague,
  RecallGrade.forgot,
];

RecallGrade _choiceGrade(ChoiceOutcome outcome) => switch (outcome) {
  ChoiceOutcome.correct => RecallGrade.know,
  ChoiceOutcome.partial => RecallGrade.vague,
  ChoiceOutcome.incorrect => RecallGrade.forgot,
};

class _StudyPage extends StatefulWidget {
  const _StudyPage({required this.store});
  final AppStore store;
  @override
  State<_StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<_StudyPage> with WidgetsBindingObserver {
  StudySession? _session;
  StudyCard? _card;
  DeckData? _deck;
  bool _revealed = false, _busy = true, _undoAvailable = false;
  bool _backwards = false;
  bool _hasChoices = false;
  RecallGrade? _choiceSuggestion;
  var _contentKey = GlobalKey<ContentViewState>();
  double _swipeDistance = 0;
  int _turn = 0;
  final _watch = Stopwatch();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watch.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _watch.start();
      if (_session?.day != dayKey(DateTime.now())) _load();
    } else {
      _watch.stop();
    }
  }

  Future<void> _load({bool backwards = false}) async {
    try {
      final session = await widget.store.prepareSession();
      final card = session.queue.isEmpty
          ? null
          : await widget.store.card(session.queue.first.cardId);
      final deck = card == null ? null : await widget.store.deck(card.deckId);
      final undo = await widget.store.setting('undo') != null;
      if (mounted) {
        setState(() {
          _session = session;
          _card = card;
          _deck = deck;
          _revealed = false;
          _hasChoices =
              card != null &&
              MarkjiParser().parse(card.source).questionChoices.isNotEmpty;
          _choiceSuggestion = null;
          _contentKey = GlobalKey<ContentViewState>();
          _busy = false;
          _undoAvailable = undo;
          _backwards = backwards;
          _turn++;
        });
        _watch.reset();
        _watch.start();
      }
    } catch (e, stack) {
      DiagnosticLog.instance.error('加载学习任务', e, stack);
      if (mounted) {
        setState(() => _busy = false);
        _toast(context, '$e');
      }
    }
  }

  void _reveal() {
    ChoiceOutcome? outcome;
    if (_hasChoices) {
      outcome = _contentKey.currentState!.submitChoices();
      if (outcome == null) return;
    }
    if (widget.store.preferences.studyHaptics) HapticFeedback.lightImpact();
    setState(() {
      _revealed = true;
      _choiceSuggestion = outcome == null ? null : _choiceGrade(outcome);
    });
  }

  Future<void> _grade(RecallGrade grade) async {
    if (_busy) return;
    setState(() => _busy = true);
    _watch.stop();
    try {
      await widget.store.grade(grade, elapsedMs: _watch.elapsedMilliseconds);
      await _load();
    } catch (e, stack) {
      DiagnosticLog.instance.error('学习评分', e, stack);
      if (mounted) {
        setState(() => _busy = false);
        _watch.start();
        _toast(context, '$e');
      }
    }
  }

  Future<void> _undo() async {
    if (_busy || !_undoAvailable) return;
    setState(() => _busy = true);
    _watch.stop();
    try {
      await widget.store.undo();
      await _load(backwards: true);
    } catch (e, stack) {
      DiagnosticLog.instance.error('撤销评分', e, stack);
      if (mounted) {
        setState(() => _busy = false);
        _watch.start();
        _toast(context, '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final card = _card;
    final session = _session;
    final finished = session != null && session.queue.isEmpty;
    final stage = session?.queue.firstOrNull?.stage;
    final title = switch (stage) {
      'new' => '认识新知识',
      'relearn' => '再回忆一次',
      _ => '唤醒旧记忆',
    };
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          clipBehavior: Clip.none,
          leading: _appearanceBack(context),
          title: Text(finished ? '今日完成' : title),
          actions: [
            if (card != null) _FavoriteButton(store: widget.store, card: card),
            IconButton(
              tooltip: '撤销上一次评分',
              onPressed: _busy || !_undoAvailable ? null : _undo,
              icon: const Icon(Icons.undo_rounded),
            ),
            if (card != null && _deck != null)
              IconButton(
                tooltip: '编辑当前卡片',
                onPressed: _busy
                    ? null
                    : () async {
                        _watch.stop();
                        await _push(
                          context,
                          _EditorPage(
                            store: widget.store,
                            deck: _deck!,
                            card: card,
                          ),
                        );
                        await _load();
                      },
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: !_busy && _undoAvailable
              ? (_) => _swipeDistance = 0
              : null,
          onHorizontalDragUpdate: !_busy && _undoAvailable
              ? (details) => _swipeDistance += details.delta.dx
              : null,
          onHorizontalDragEnd: !_busy && _undoAvailable
              ? (details) {
                  if (_swipeDistance > 80 ||
                      (_swipeDistance > 24 &&
                          (details.primaryVelocity ?? 0) > 700)) {
                    _undo();
                  }
                }
              : null,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 850),
                child: finished
                    ? _completion(context, session)
                    : session == null || card == null
                    ? Center(
                        child: _busy
                            ? const CircularProgressIndicator()
                            : OutlinedButton(
                                onPressed: _load,
                                child: const Text('重新加载任务'),
                              ),
                      )
                    : IgnorePointer(
                        ignoring: _busy,
                        child: AnimatedSwitcher(
                          duration: _duration(context, 260),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: _backwards
                                    ? SlideTransition(
                                        position: Tween<Offset>(
                                          begin: Offset(
                                            child.key == ValueKey(_turn)
                                                ? -.08
                                                : .08,
                                            0,
                                          ),
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: child,
                                      )
                                    : child,
                              ),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          layoutBuilder: (current, previous) => Stack(
                            fit: StackFit.expand,
                            children: [
                              for (final child in previous)
                                IgnorePointer(child: child),
                              ?current,
                            ],
                          ),
                          child: Column(
                            key: ValueKey(_turn),
                            children: [
                              if (widget.store.preferences.showStudyProgress)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    12,
                                    24,
                                    20,
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${_deck?.name ?? ''}${card.chapter.isEmpty ? '' : ' / ${card.chapter}'}',
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: c.onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '已完成 ${session.completed} · 剩余 ${session.queue.length}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: c.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: LinearProgressIndicator(
                                          value:
                                              session.completed /
                                              math.max(
                                                1,
                                                session.completed +
                                                    session.queue.length,
                                              ),
                                          minHeight: 5,
                                          backgroundColor:
                                              c.surfaceContainerHigh,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 8,
                                  ),
                                  child: Container(
                                    width: double.infinity,
                                    constraints: const BoxConstraints(
                                      minHeight: 300,
                                    ),
                                    padding: const EdgeInsets.all(26),
                                    decoration: BoxDecoration(
                                      color: c.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            _Pill(
                                              stage == 'new'
                                                  ? '新卡片'
                                                  : stage == 'relearn'
                                                  ? '当日重学'
                                                  : '到期复习',
                                              icon: stage == 'relearn'
                                                  ? Icons.refresh
                                                  : Icons.style_outlined,
                                            ),
                                            const Spacer(),
                                            CommonPopupBox(
                                              targetBuilder: (open) =>
                                                  ElasticButton(
                                                    child: IconButton(
                                                      tooltip: '当前卡片操作',
                                                      onPressed: _busy
                                                          ? null
                                                          : open,
                                                      icon: const Icon(
                                                        Icons.more_horiz,
                                                      ),
                                                    ),
                                                  ),
                                              popupBuilder: (_) => CommonPopupMenu(
                                                items: [
                                                  CommonPopupMenuItem(
                                                    label: '暂停这张卡',
                                                    glyph: Icons
                                                        .pause_circle_outline,
                                                    onPressed: () => _action(
                                                      context,
                                                      () async {
                                                        setState(
                                                          () => _busy = true,
                                                        );
                                                        try {
                                                          await widget.store
                                                              .bulkUpdate(
                                                                [card.id],
                                                                {
                                                                  'plan':
                                                                      'paused',
                                                                },
                                                              );
                                                          await _load();
                                                          if (context.mounted) {
                                                            _toast(
                                                              context,
                                                              '已暂停，可在牌组的“暂停”筛选中重新加入计划',
                                                            );
                                                          }
                                                        } finally {
                                                          if (mounted) {
                                                            setState(
                                                              () =>
                                                                  _busy = false,
                                                            );
                                                          }
                                                        }
                                                      },
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 24),
                                        ContentView(
                                          key: _contentKey,
                                          source: card.source,
                                          store: widget.store,
                                          revealed: _revealed,
                                          interactive: true,
                                        ),
                                        const SizedBox(height: 24),
                                        if (!_revealed &&
                                            widget
                                                .store
                                                .preferences
                                                .showRecallHint)
                                          Text(
                                            _hasChoices
                                                ? '选择答案，提交后查看解析'
                                                : '先在心里回忆一下答案',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: c.onSurfaceVariant,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  20,
                                  24,
                                  20,
                                ),
                                child: _StudyActionSwitcher(
                                  revealed: _revealed,
                                  reveal: SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                      onPressed: _reveal,
                                      icon: Icon(
                                        _hasChoices
                                            ? Icons.fact_check_outlined
                                            : Icons.visibility_outlined,
                                      ),
                                      label: Text(
                                        _hasChoices ? '提交答案' : '揭晓答案',
                                      ),
                                    ),
                                  ),
                                  rating: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _choiceSuggestion != null
                                            ? '建议评分：${_choiceSuggestion!.label} · 可按实际记忆调整'
                                            : stage == 'relearn'
                                            ? '这次练习不会改变长期排期'
                                            : '刚才，你记得怎么样？',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: c.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      LayoutBuilder(
                                        builder: (context, constraints) {
                                          final buttons = _recallChoices.map((
                                            g,
                                          ) {
                                            final colors = switch (g) {
                                              RecallGrade.forgot => (
                                                c.errorContainer,
                                                c.onErrorContainer,
                                              ),
                                              RecallGrade.vague => (
                                                c.tertiaryContainer,
                                                c.onTertiaryContainer,
                                              ),
                                              RecallGrade.know => (
                                                c.primaryContainer,
                                                c.onPrimaryContainer,
                                              ),
                                              RecallGrade.familiar => (
                                                c.secondaryContainer,
                                                c.onSecondaryContainer,
                                              ),
                                            };
                                            return FilledButton(
                                              style: FilledButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 14,
                                                    ),
                                                backgroundColor: colors.$1,
                                                foregroundColor: colors.$2,
                                                side: g == _choiceSuggestion
                                                    ? BorderSide(
                                                        color: colors.$2,
                                                        width: 2,
                                                      )
                                                    : BorderSide.none,
                                              ),
                                              onPressed: () => _grade(g),
                                              child: Column(
                                                children: [
                                                  Text(
                                                    g.label,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    g == RecallGrade.forgot ||
                                                            g ==
                                                                RecallGrade
                                                                    .vague
                                                        ? '稍后再来'
                                                        : '完成这张',
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList();
                                          return Row(
                                            children: [
                                              for (
                                                var i = 0;
                                                i < buttons.length;
                                                i++
                                              ) ...[
                                                if (i > 0)
                                                  const SizedBox(width: 8),
                                                Expanded(child: buttons[i]),
                                              ],
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                  ),
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
      ),
    );
  }

  Widget _completion(BuildContext context, StudySession session) =>
      SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.done_all_rounded,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              '今天，也进步了一点',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              '完成 ${session.completed} 张卡片\n下一次相遇，已经为你安排好了。',
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.8),
            ),
            const SizedBox(height: 30),
            _Load(
              future: widget.store.overview(),
              builder: (d) => Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: '首次回忆',
                      value: '${d['formal']}',
                      icon: Icons.style_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Metric(
                      label: '当日重学',
                      value: '${d['practice']}',
                      icon: Icons.refresh,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Metric(
                      label: '分钟',
                      value: '${((d['elapsed'] as int) / 60000).ceil()}',
                      icon: Icons.schedule,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('回到今日'),
            ),
          ],
        ),
      );
}

/// 两种操作始终共用同一高度和底部基线，切换时不会先缩短再跳回。
class _StudyActionSwitcher extends StatelessWidget {
  const _StudyActionSwitcher({
    required this.revealed,
    required this.reveal,
    required this.rating,
  });
  final bool revealed;
  final Widget reveal, rating;
  @override
  Widget build(BuildContext context) => Stack(
    key: const ValueKey('study-actions'),
    alignment: Alignment.bottomCenter,
    children: [
      for (final (visible, child) in [(!revealed, reveal), (revealed, rating)])
        IgnorePointer(
          ignoring: !visible,
          child: ExcludeSemantics(
            excluding: !visible,
            child: ExcludeFocus(
              excluding: !visible,
              child: AnimatedOpacity(
                duration: _duration(context, 180),
                opacity: visible ? 1 : 0,
                child: child,
              ),
            ),
          ),
        ),
    ],
  );
}

class _CardPage extends StatelessWidget {
  const _CardPage({required this.store, required this.cardId});
  final AppStore store;
  final String cardId;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => _Load(
      future: store
          .card(cardId)
          .then(
            (c) async => c == null
                ? null
                : (
                    card: c,
                    deck: (await store.deck(c.deckId))!,
                    history: await store.historyFor(c.id),
                  ),
          ),
      builder: (data) {
        if (data == null) {
          return const Scaffold(body: Center(child: Text('卡片已删除')));
        }
        final card = data.card;
        final c = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(
            clipBehavior: Clip.none,
            leading: _appearanceBack(context),
            title: const Text('卡片详情'),
            actions: [
              _GlassToolbar(
                children: [
                  _FavoriteButton(store: store, card: card, grouped: true),
                  IconButton(
                    tooltip: '编辑卡片',
                    onPressed: () => _push(
                      context,
                      _EditorPage(store: store, deck: data.deck, card: card),
                    ),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
              const SizedBox(width: 16),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      _Pill(data.deck.name),
                      _Pill(card.chapter.isEmpty ? '未分类' : card.chapter),
                      ...card.tags.map((s) => _Pill(s)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _Panel(
                    child: ContentView(
                      source: card.source,
                      store: store,
                      replaceImages: true,
                    ),
                  ),
                  const _SectionLabel('学习状态'),
                  _Panel(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Text('下次复习'),
                            const Spacer(),
                            Text(_dateLabel(card.dueAt)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Text('长期复习'),
                            const Spacer(),
                            Text('${data.history.length} 次'),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Text('当前算法'),
                            const Spacer(),
                            Text('MMX-${card.algorithm}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const _SectionLabel('记忆保持率'),
                  if (card.state == null)
                    const _Panel(child: Text('完成首次学习后，会在这里看到预测曲线。'))
                  else
                    _Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '从上次复习起的预测 · 0—30 天',
                            style: TextStyle(
                              color: c.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 160,
                            width: double.infinity,
                            child: CustomPaint(
                              painter: _CurvePainter(
                                values: List.generate(
                                  61,
                                  (i) => store
                                      .algorithm(data.deck, card.algorithm)
                                      .forgettingCurve(
                                        i / 2,
                                        MmxState.fromJsonString(card.state!)
                                            .stability,
                                      ),
                                ),
                                color: c.primary,
                                grid: c.outlineVariant,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                '0 天',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: c.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '30 天',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: c.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  const _SectionLabel('正式复习记录'),
                  if (data.history.isEmpty)
                    const Text('还没有复习记录')
                  else
                    ...data.history.reversed
                        .take(30)
                        .map(
                          (log) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.history),
                            title: Text(
                              '${RecallGrade.fromAppCode(log['grade'])?.label ?? ''} · ${_dateLabel(DateTime.parse(log['reviewed_at']))}',
                            ),
                            subtitle: Text(
                              '距上次 ${(log['interval_days'] as num).toStringAsFixed(2)} 天',
                            ),
                          ),
                        ),
                  const SizedBox(height: 24),
                  FilledButton.tonal(
                    onPressed: () => _action(
                      context,
                      () => store.bulkUpdate(
                        [card.id],
                        {'plan': card.plan == 'active' ? 'paused' : 'active'},
                      ),
                    ),
                    child: Text(card.plan == 'active' ? '暂停这张卡的学习' : '加入学习计划'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.values,
    required this.color,
    required this.grid,
  });
  final List<double> values;
  final Color color, grid;
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = grid
      ..strokeWidth = .6;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1),
          y = size.height * (1 - values[i].clamp(0.0, 1.0));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter oldDelegate) =>
      oldDelegate.color != color || !identical(oldDelegate.values, values);
}
