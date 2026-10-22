part of 'app.dart';

class _FavoriteButton extends StatefulWidget {
  const _FavoriteButton({
    required this.store,
    required this.card,
    this.grouped = false,
  });
  final AppStore store;
  final StudyCard card;
  final bool grouped;
  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  late bool _favorite = widget.card.favorite;
  bool _busy = false;
  @override
  void didUpdateWidget(_FavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.id != widget.card.id ||
        oldWidget.card.favorite != widget.card.favorite) {
      _favorite = widget.card.favorite;
    }
  }

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      tooltip: _favorite ? '取消收藏' : '收藏卡片',
      isSelected: _favorite,
      selectedIcon: const Icon(Icons.star_rounded),
      icon: const Icon(Icons.star_outline_rounded),
      onPressed: _busy
          ? null
          : () => _action(context, () async {
              setState(() => _busy = true);
              final selected = !_favorite;
              final id = widget.card.id;
              try {
                await widget.store.setFavorite(id, selected);
                if (mounted && widget.card.id == id) {
                  setState(() => _favorite = selected);
                }
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            }),
    );
    return widget.grouped ? button : ElasticButton(child: button);
  }
}

class _PracticeSetupPage extends StatefulWidget {
  const _PracticeSetupPage({
    required this.store,
    required this.deck,
    this.focus,
  });
  final AppStore store;
  final DeckData deck;
  final String? focus;
  @override
  State<_PracticeSetupPage> createState() => _PracticeSetupPageState();
}

class _PracticeSetupPageState extends State<_PracticeSetupPage> {
  late String _focus = widget.focus ?? 'all';
  String _limit = '20';
  bool _shuffle = true, _busy = false;
  Future<void> _open() async {
    await _push(context, _PracticePage(store: widget.store));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => _SettingsDetail(
    title: '专项练习',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AppearanceHeader(widget.deck.name, Icons.school_outlined),
        _Load(
          future: widget.store.practiceSession(),
          builder: (session) =>
              session == null ||
                  (session.deckId != widget.deck.id && session.queue.isEmpty)
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _AppearanceCard(
                    child: _supportTile(
                      Icons.play_circle_outline_rounded,
                      session.queue.isEmpty ? '查看上次练习结果' : '继续上次练习',
                      _open,
                      subtitle:
                          '已掌握 ${session.completed} / ${session.total} 张 · 新一轮会替换这份进度',
                    ),
                  ),
                ),
        ),
        _AppearanceCard(
          child: Column(
            children: [
              _AppearanceMenu(
                title: '练习范围',
                value: _focus,
                options: const {
                  'all': '全部卡片',
                  'favorite': '收藏卡片',
                  'difficult': '最近难卡',
                },
                onChanged: (v) => setState(() => _focus = v),
              ),
              _AppearanceMenu(
                title: '本轮数量',
                value: _limit,
                options: const {'10': '10 张', '20': '20 张', '50': '50 张'},
                onChanged: (v) => setState(() => _limit = v),
              ),
              SwitchListTile(
                title: const Text('随机顺序'),
                subtitle: const Text('每次抽取不同的卡片组合'),
                value: _shuffle,
                onChanged: (v) => setState(() => _shuffle = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Load(
          future: widget.store.cards(
            deckId: widget.deck.id,
            focus: _focus,
            limit: int.parse(_limit),
          ),
          builder: (cards) => Text(
            cards.isEmpty
                ? '当前范围没有卡片。可先收藏重点卡片，或完成一次正式学习。'
                : '本轮将练习 ${cards.length} 张卡片，包括尚未加入计划的资料。',
            style: const TextStyle(height: 1.7),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '最近难卡：最近一次正式评分为“忘记”或“模糊”的卡片。专项练习独立保存进度，不改变每日任务、复习日期或正式学习记录。',
          style: TextStyle(fontSize: 12, height: 1.7),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () => _action(context, () async {
                  setState(() => _busy = true);
                  try {
                    await widget.store.startPractice(
                      widget.deck.id,
                      focus: _focus,
                      limit: int.parse(_limit),
                      shuffle: _shuffle,
                    );
                    if (mounted) await _open();
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                }),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(_busy ? '正在准备…' : '开始新一轮练习'),
        ),
      ],
    ),
  );
}

class _PracticePage extends StatefulWidget {
  const _PracticePage({required this.store});
  final AppStore store;
  @override
  State<_PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<_PracticePage> {
  PracticeSession? _session;
  StudyCard? _card;
  bool _busy = true, _revealed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final session = await widget.store.preparePractice();
      final card = session == null || session.queue.isEmpty
          ? null
          : await widget.store.card(session.queue.first);
      if (mounted) {
        setState(() {
          _session = session;
          _card = card;
          _revealed = false;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toast(context, '$e');
      }
    }
  }

  Future<void> _grade(RecallGrade grade) => _action(context, () async {
    setState(() => _busy = true);
    try {
      await widget.store.gradePractice(grade);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  });
  @override
  Widget build(BuildContext context) {
    final session = _session;
    final card = _card;
    final c = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: _settingsCanvas(c),
        appBar: AppBar(
          clipBehavior: Clip.none,
          backgroundColor: _settingsCanvas(c),
          leading: _appearanceBack(context),
          title: Text(session?.queue.isEmpty == true ? '练习完成' : '专项练习'),
          actions: [
            if (card != null) _FavoriteButton(store: widget.store, card: card),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: session == null
                  ? Center(
                      child: _busy
                          ? const CircularProgressIndicator()
                          : TextButton(
                              onPressed: _load,
                              child: const Text('重新加载练习'),
                            ),
                    )
                  : session.queue.isEmpty
                  ? _summary(session)
                  : card == null
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '已掌握 ${session.completed} / ${session.total} 张 · 已作答 ${session.attempts} 次',
                              ),
                              const SizedBox(height: 12),
                              LinearProgressIndicator(
                                value:
                                    (session.completed + session.skipped) /
                                    session.total,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '进度自动保存，可随时返回后继续。',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: c.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: _AppearanceCard(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Text(
                                      '先主动回忆，再揭晓答案',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(height: 20),
                                    ContentView(
                                      key: ValueKey(
                                        '${card.id}-${session.attempts}',
                                      ),
                                      source: card.source,
                                      store: widget.store,
                                      revealed: _revealed,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: _revealed
                              ? Row(
                                  children: [
                                    for (final (index, grade)
                                        in _recallChoices.indexed) ...[
                                      if (index > 0) const SizedBox(width: 8),
                                      Expanded(
                                        child: FilledButton.tonal(
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 14,
                                            ),
                                          ),
                                          onPressed: _busy
                                              ? null
                                              : () => _grade(grade),
                                          child: Text(grade.label),
                                        ),
                                      ),
                                    ],
                                  ],
                                )
                              : SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () {
                                            if (widget
                                                .store
                                                .preferences
                                                .studyHaptics) {
                                              HapticFeedback.lightImpact();
                                            }
                                            setState(() => _revealed = true);
                                          },
                                    icon: const Icon(Icons.visibility_outlined),
                                    label: const Text('揭晓答案'),
                                  ),
                                ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summary(PracticeSession session) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Icon(
        Icons.task_alt_rounded,
        size: 68,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 24),
      const Text(
        '又巩固了一轮',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 24),
      _AppearanceCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('掌握 ${session.completed} 张 · 作答 ${session.attempts} 次'),
              const SizedBox(height: 12),
              Text(
                '首次回忆正确 ${session.firstRecalled} / ${session.answered.length} 张',
              ),
              if (session.skipped > 0) Text('跳过 ${session.skipped} 张已删除的卡片'),
              const SizedBox(height: 12),
              const Text('每日任务和长期复习排期保持原样。', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
      if (session.mistakes.isNotEmpty) ...[
        _AppearanceHeader('本轮需巩固', Icons.psychology_outlined),
        _AppearanceCard(
          child: Column(
            children: [
              for (final id in session.mistakes)
                _Load(
                  future: widget.store.card(id),
                  builder: (card) => card == null
                      ? const SizedBox.shrink()
                      : ListTile(
                          title: Text(
                            _short(card.source, 80),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: _FavoriteButton(
                            store: widget.store,
                            card: card,
                          ),
                          onTap: () => _push(
                            context,
                            _CardPage(store: widget.store, cardId: id),
                          ),
                        ),
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 24),
      FilledButton(
        onPressed: () => Navigator.maybePop(context),
        child: const Text('完成'),
      ),
    ],
  );
}
