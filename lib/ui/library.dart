part of 'app.dart';

typedef _LibraryData = ({
  List<DeckData> decks,
  Map<String, Map<String, int>> counts,
});

class _LibraryPage extends StatefulWidget {
  const _LibraryPage({required this.store});
  final AppStore store;
  @override
  State<_LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<_LibraryPage> {
  String _search = '';
  String? _group, _selected;
  bool _refreshing = false;
  int? _dataRevision;
  Future<_LibraryData>? _data;
  List<String>? _order;
  int _savingOrders = 0;

  Future<_LibraryData> _libraryData() {
    if (_data == null || _dataRevision != widget.store.revision) {
      _dataRevision = widget.store.revision;
      _data = _readLibraryData();
    }
    return _data!;
  }

  Future<_LibraryData> _readLibraryData() async {
    final decks = await widget.store.decks();
    final counts = await Future.wait([
      for (final deck in decks) widget.store.counts(deck.id),
    ]);
    return (
      decks: decks,
      counts: {for (var i = 0; i < decks.length; i++) decks[i].id: counts[i]},
    );
  }

  void _reorder(List<String> ids) {
    final previous = _order;
    _savingOrders++;
    // 在落下的同一帧更新顺序，不等 SQLite 写入后再跳回目标位置。
    setState(() => _order = ids);
    _action(context, () async {
      try {
        await widget.store.reorderDecks(ids);
      } catch (_) {
        if (mounted && identical(_order, ids)) {
          setState(() => _order = previous);
        }
        rethrow;
      } finally {
        _savingOrders--;
      }
    });
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await widget.store.decks();
      widget.store.changed();
      if (mounted) _toast(context, '牌组已刷新');
    } catch (e) {
      if (mounted) _toast(context, '刷新失败：$e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => _Load(
      future: _libraryData(),
      builder: (data) {
        if (_savingOrders == 0 &&
            listEquals(_order, data.decks.map((d) => d.id).toList())) {
          _order = null;
        }
        final byId = {for (final deck in data.decks) deck.id: deck};
        final decks = [
          for (final id in _order ?? const <String>[]) ?byId.remove(id),
          ...byId.values,
        ];
        final groups =
            decks
                .map((d) => d.group)
                .where((g) => g.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        final visible = decks
            .where(
              (d) =>
                  d.name.toLowerCase().contains(_search.toLowerCase()) &&
                  (_group == null || d.group == _group),
            )
            .toList();
        final wide = MediaQuery.sizeOf(context).width >= 840;
        final list = _PinnedPage(
          title: '牌组',
          toolbar: _LibraryToolbar(
            onChanged: (s) => setState(() => _search = s),
            actions: _GlassToolbar(
              children: [
                IconButton(
                  tooltip: '刷新牌组',
                  onPressed: _refreshing ? null : _refresh,
                  icon: _refreshing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: '新建牌组',
                  onPressed: () => _editDeck(context, widget.store),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ),
          slivers: [
            SliverList.list(
              children: [
                Text(
                  '${decks.length} 副牌组',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _GlassSegments<String?>(
                  options: {null: '全部', for (final g in groups) g: g},
                  value: _group,
                  onChanged: (g) => setState(() => _group = g),
                ),
                const SizedBox(height: 20),
                if (visible.isEmpty)
                  _Empty(
                    icon: Icons.layers_outlined,
                    title: decks.isEmpty ? '把知识装进牌组' : '没有找到这个牌组',
                    detail: decks.isEmpty
                        ? '按科目或主题整理卡片，再选择想学习的内容。'
                        : '试试其他关键词，或者切换分组。',
                    action: decks.isEmpty
                        ? FilledButton.icon(
                            onPressed: () => _editDeck(context, widget.store),
                            icon: const Icon(Icons.add),
                            label: const Text('新建牌组'),
                          )
                        : null,
                  ),
              ],
            ),
            if (visible.isNotEmpty)
              _DeckReorderList(
                store: widget.store,
                counts: data.counts,
                onReorder: _reorder,
                decks: decks,
                visible: visible,
                selectedId: wide ? _selected : null,
                onSelect: wide ? (id) => setState(() => _selected = id) : null,
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _push(context, _ImportPage(store: widget.store)),
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('导入卡片文本'),
                ),
              ),
            ),
          ],
        );
        return wide
            ? Row(
                children: [
                  SizedBox(
                    width: MediaQuery.sizeOf(context).width >= 1100 ? 390 : 300,
                    child: list,
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child:
                        _selected != null && decks.any((d) => d.id == _selected)
                        ? _DeckPage(
                            key: ValueKey(_selected),
                            store: widget.store,
                            deckId: _selected!,
                            embedded: true,
                          )
                        : const Center(child: Text('选择一副牌组，浏览你的知识')),
                  ),
                ],
              )
            : list;
      },
    ),
  );
}

class _DeckReorderList extends StatelessWidget {
  const _DeckReorderList({
    required this.store,
    required this.decks,
    required this.visible,
    this.onSelect,
    required this.counts,
    required this.onReorder,
    this.selectedId,
  });

  final AppStore store;
  final List<DeckData> decks;
  final List<DeckData> visible;
  final String? selectedId;
  final ValueChanged<String>? onSelect;
  final Map<String, Map<String, int>> counts;
  final ValueChanged<List<String>> onReorder;

  @override
  Widget build(BuildContext context) {
    return SliverReorderableList(
      itemCount: visible.length,
      onReorderItem: (oldIndex, newIndex) {
        if (oldIndex == newIndex) return;
        final visibleOrder = visible.map((deck) => deck.id).toList();
        visibleOrder.insert(newIndex, visibleOrder.removeAt(oldIndex));
        final visibleIds = visibleOrder.toSet();
        var cursor = 0;
        // 筛选时只交换可见牌组所在的位置，其他牌组留在原位。
        final order = [
          for (final deck in decks)
            visibleIds.contains(deck.id) ? visibleOrder[cursor++] : deck.id,
        ];
        onReorder(order);
      },
      proxyDecorator: (child, index, animation) => AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final lift = MediaQuery.disableAnimationsOf(context)
              ? 0.0
              : Curves.easeOut.transform(animation.value);
          return Transform.scale(
            scale: 1 + lift * .02,
            child: Material(
              color: Colors.transparent,
              elevation: 6 * lift,
              borderRadius: BorderRadius.circular(24),
              child: child,
            ),
          );
        },
        child: child,
      ),
      itemBuilder: (context, index) {
        final deck = visible[index];
        return Padding(
          key: ValueKey(deck.id),
          padding: const EdgeInsets.only(bottom: 12),
          child: ReorderableDelayedDragStartListener(
            index: index,
            child: _DeckTile(
              store: store,
              deck: deck,
              counts: counts[deck.id]!,
              selected: deck.id == selectedId,
              onTap: onSelect == null ? null : () => onSelect!(deck.id),
            ),
          ),
        );
      },
    );
  }
}

Future<void> _editDeck(
  BuildContext context,
  AppStore store, {
  DeckData? deck,
}) async {
  final name = TextEditingController(text: deck?.name ?? ''),
      description = TextEditingController(text: deck?.description ?? ''),
      group = TextEditingController(text: deck?.group ?? ''),
      limit = TextEditingController(
        text: '${deck?.newLimit ?? store.preferences.defaultLimit}',
      ),
      params = TextEditingController(text: deck?.params.join(', ') ?? '');
  var algorithm = deck?.algorithm ?? store.preferences.defaultAlgorithm;
  String? error;
  bool saving = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          MediaQuery.viewInsetsOf(sheet).bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                deck == null ? '新建牌组' : '牌组设置',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 22),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '牌组名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                decoration: const InputDecoration(labelText: '简介（可选）'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: group,
                decoration: const InputDecoration(
                  labelText: '分组（可选）',
                  hintText: '例如：考研、语言、生活',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: limit,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '每日新学上限'),
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('算法高级设置'),
                children: [
                  _GlassSegments<int>(
                    options: const {6: 'MMX-6', 5: 'MMX-5'},
                    value: algorithm,
                    onChanged: (value) => setSheet(() {
                      algorithm = value;
                      params.clear();
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: params,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: '自定义参数（${algorithm == 6 ? 21 : 12} 个）',
                      hintText: '留空使用现有默认参数，英文逗号分隔',
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '目标保留率固定 85%。更换算法后，在下次正式复习时按历史重新计算。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final n = int.tryParse(limit.text);
                          final parsed = params.text.trim().isEmpty
                              ? <double>[]
                              : params.text
                                    .split(',')
                                    .map(
                                      (s) =>
                                          double.tryParse(s.trim()) ??
                                          double.nan,
                                    )
                                    .toList();
                          if (name.text.trim().isEmpty ||
                              n == null ||
                              n < 0 ||
                              (parsed.isNotEmpty &&
                                  (parsed.length !=
                                          (algorithm == 6 ? 21 : 12) ||
                                      parsed.any((p) => !p.isFinite)))) {
                            setSheet(() => error = '请输入名称、非负学习数量，以及正确数量的有限参数。');
                            return;
                          }
                          setSheet(() => saving = true);
                          try {
                            await store.putDeck(
                              DeckData(
                                id: deck?.id ?? newId(),
                                name: name.text.trim(),
                                description: description.text.trim(),
                                group: group.text.trim(),
                                newLimit: n,
                                algorithm: algorithm,
                                params: parsed,
                                chapters: deck?.chapters ?? [],
                                sortOrder: deck?.sortOrder ?? 0,
                              ),
                            );
                            if (sheet.mounted) Navigator.pop(sheet);
                          } catch (e) {
                            setSheet(() {
                              error = '$e';
                              saving = false;
                            });
                          }
                        },
                  child: Text(saving ? '正在保存…' : '保存牌组'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Future.delayed(const Duration(milliseconds: 350), () {
    for (final c in [name, description, group, limit, params]) {
      c.dispose();
    }
  });
}

class _DeckPage extends StatefulWidget {
  const _DeckPage({
    super.key,
    required this.store,
    required this.deckId,
    this.initialDeck,
    this.embedded = false,
  });
  final AppStore store;
  final String deckId;
  final DeckData? initialDeck;
  final bool embedded;
  @override
  State<_DeckPage> createState() => _DeckPageState();
}

class _DeckPageState extends State<_DeckPage> {
  String _search = '';
  String? _chapter, _plan, _tag, _focus;
  final _selected = <String>{};
  final _scroll = ScrollController();
  final _listKey = GlobalKey();
  Timer? _selectionTimer;
  int? _selectionPointer;
  int? _selectionAnchor;
  int? _selectionEnd;
  Offset? _selectionPosition;
  Set<String> _selectionBefore = {};
  bool _selectionValue = true;
  List<StudyCard> _cards = [];
  DeckData? _deck;
  List<String> _tags = [];
  bool _loading = false, _more = true;
  bool _enrolling = false;
  Future<void>? _refreshing;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _deck = widget.initialDeck;
    widget.store.addListener(_refresh);
    _refresh();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _loadMore();
    });
  }

  @override
  void dispose() {
    _endSelection();
    widget.store.removeListener(_refresh);
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    _endSelection();
    _generation++;
    _loading = false;
    _refreshing = _loadMore(replace: true);
  }

  Future<void> _loadMore({bool replace = false}) async {
    if (_loading || (!replace && !_more)) return;
    final gen = _generation;
    final limit = replace ? math.max(60, _cards.length) : 60;
    _loading = true;
    try {
      final values = await widget.store.cards(
        deckId: widget.deckId,
        search: _search,
        chapter: _chapter,
        plan: _plan,
        tag: _tag,
        focus: _focus,
        offset: replace ? 0 : _cards.length,
        limit: limit,
      );
      final deck = await widget.store.deck(widget.deckId);
      final tags = await widget.store.tags(widget.deckId);
      if (mounted && gen == _generation) {
        setState(() {
          _cards = replace ? values : [..._cards, ...values];
          _more = values.length == limit;
          _deck = deck;
          _tags = tags;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && gen == _generation) {
        setState(() => _loading = false);
        _toast(context, '$e');
      }
    }
  }

  void _filter(VoidCallback update) {
    if (_enrolling) return;
    setState(() {
      update();
      _cards = [];
    });
    _refresh();
  }

  double get _rowExtent =>
      math.max(56, MediaQuery.textScalerOf(context).scale(14) * 1.4 + 20);

  void _beginSelection(int index, Offset position) {
    _selectionTimer?.cancel();
    _selectionAnchor = index;
    _selectionEnd = null;
    _selectionPosition = position;
    _selectionBefore = Set.of(_selected);
    _selectionValue = !_selected.contains(_cards[index].id);
    _paintSelection();
    _selectionTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
      final position = _selectionPosition;
      if (box == null || position == null || !_scroll.hasClients) return;
      final y = box.globalToLocal(position).dy;
      const edge = 40.0;
      final speed = y < edge
          ? -10 * ((edge - y) / edge).clamp(0.0, 1.0)
          : y > box.size.height - edge
          ? 10 * ((y - box.size.height + edge) / edge).clamp(0.0, 1.0)
          : 0.0;
      if (speed == 0) return;
      final offset = (_scroll.offset + speed).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      if (offset != _scroll.offset) {
        _scroll.jumpTo(offset);
        _paintSelection();
      }
    });
  }

  void _paintSelection() {
    final anchor = _selectionAnchor;
    final position = _selectionPosition;
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (anchor == null || position == null || box == null || _cards.isEmpty) {
      return;
    }
    final index =
        ((box.globalToLocal(position).dy + _scroll.offset - 8) / _rowExtent)
            .floor()
            .clamp(0, _cards.length - 1);
    if (_selectionEnd == index) return;
    _selectionEnd = index;
    final range = _cards
        .sublist(math.min(anchor, index), math.max(anchor, index) + 1)
        .map((card) => card.id);
    setState(() {
      _selected
        ..clear()
        ..addAll(_selectionBefore);
      if (_selectionValue) {
        _selected.addAll(range);
      } else {
        _selected.removeAll(range);
      }
    });
  }

  void _endSelection() {
    _selectionTimer?.cancel();
    _selectionTimer = null;
    _selectionPointer = null;
    _selectionAnchor = null;
    _selectionEnd = null;
    _selectionPosition = null;
    _selectionBefore = {};
  }

  Future<void> _batch(String operation) async {
    final ids = _selected.toList();
    await _action(context, () async {
      if (operation == 'delete') {
        if (isOfficialContentDeck(widget.deckId)) return;
        if (!await _confirm(
          context,
          '删除 ${ids.length} 张卡片？',
          '这些卡片及其学习记录将被删除。',
        )) {
          return;
        }
        await widget.store.deleteCards(ids);
      } else if (operation == 'move') {
        final decks = await widget.store.decks();
        if (!mounted) return;
        final id = await showModalBottomSheet<String>(
          context: context,
          builder: (c) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(title: Text('移动到牌组')),
                ...decks
                    .where((d) => d.id != widget.deckId)
                    .map(
                      (d) => ListTile(
                        title: Text(d.name),
                        onTap: () => Navigator.pop(c, d.id),
                      ),
                    ),
              ],
            ),
          ),
        );
        if (id == null) return;
        await widget.store.bulkUpdate(ids, {'deckId': id, 'chapter': ''});
      } else if (operation == 'chapter') {
        final chapter = await _textPrompt(context, '移动到章节', hint: '留空表示未分类');
        if (chapter == null) return;
        if (chapter.isNotEmpty && !_deck!.chapters.contains(chapter)) {
          await widget.store.putDeck(
            DeckData.fromJson({
              ..._deck!.toJson(),
              'chapters': [..._deck!.chapters, chapter],
            }),
          );
        }
        await widget.store.bulkUpdate(ids, {'chapter': chapter});
      } else {
        await widget.store.bulkUpdate(ids, {'plan': operation});
      }
      if (mounted) {
        setState(() => _selected.clear());
        _toast(context, '已更新 ${ids.length} 张卡片');
      }
    });
  }

  Future<bool> _enroll() async {
    _endSelection();
    final ids = _selected.toList();
    setState(() {
      _enrolling = true;
    });
    try {
      await widget.store.bulkUpdate(ids, {'plan': 'active'});
      await _refreshing;
      if (!mounted) return false;
      return true;
    } catch (e) {
      if (mounted) _toast(context, '$e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _deck;
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: widget.embedded ? c.surface : null,
      appBar: AppBar(
        clipBehavior: Clip.none,
        automaticallyImplyLeading: !widget.embedded,
        leading: widget.embedded ? null : _appearanceBack(context),
        title: Text(d?.name ?? '牌组'),
        actions: [
          if (d != null)
            _GlassToolbar(
              children: [
                IconButton(
                  tooltip: '专项练习',
                  icon: const Icon(Icons.school_outlined),
                  onPressed: () => _push(
                    context,
                    _PracticeSetupPage(
                      store: widget.store,
                      deck: d,
                      focus: _focus,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '牌组设置',
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: () => _editDeck(context, widget.store, deck: d),
                ),
              ],
            ),
          const SizedBox(width: 8),
          _ActionMenu<String>(
            destructive: const {'delete'},
            onSelected: (v) => _action(context, () async {
              if (v == 'chapter') {
                final name = await _textPrompt(context, '新建章节');
                if (name != null &&
                    name.isNotEmpty &&
                    d != null &&
                    !d.chapters.contains(name)) {
                  await widget.store.putDeck(
                    DeckData.fromJson({
                      ...d.toJson(),
                      'chapters': [...d.chapters, name],
                    }),
                  );
                }
              }
              if (v == 'export' || v == 'plain') {
                final rows = await widget.store.db.rows(
                  'SELECT cards.source FROM cards JOIN card_decks ON card_decks.card_id=cards.id WHERE card_decks.deck_id=? ORDER BY cards.rowid',
                  [widget.deckId],
                );
                final content = rows
                    .map(
                      (r) => v == 'plain'
                          ? MarkjiParser().parse(r['source']).plainText
                          : r['source'],
                    )
                    .join('\n\n===CARD===\n\n');
                await _saveBytes(
                  '${d?.name ?? 'cards'}.txt',
                  Uint8List.fromList(utf8.encode(content)),
                );
              }
              if (v == 'delete' &&
                  !isOfficialContentDeck(widget.deckId) &&
                  context.mounted &&
                  await _confirm(context, '删除整副牌组？', '牌组中的卡片和学习记录将一起删除。')) {
                await widget.store.deleteDeck(widget.deckId);
                if (context.mounted && !widget.embedded) Navigator.pop(context);
              }
            }),
            options: {
              'chapter': '新建章节',
              'export': '导出语法 TXT',
              'plain': '导出纯文本',
              if (!isOfficialContentDeck(widget.deckId)) 'delete': '删除牌组',
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            // 键盘弹出时让筛选区可以纵向滚动，给卡片和操作底栏留出空间。
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(
                  0,
                  constraints.maxHeight -
                      56 -
                      MediaQuery.paddingOf(context).bottom -
                      _rowExtent,
                ),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (d?.description.isNotEmpty ?? false)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text(
                            d!.description,
                            style: TextStyle(color: c.onSurfaceVariant),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: _GlassChoice(
                              label: '写卡片',
                              onPressed: d == null
                                  ? null
                                  : () => _push(
                                      context,
                                      _EditorPage(
                                        store: widget.store,
                                        deck: d,
                                        chapter: _chapter ?? '',
                                      ),
                                    ),
                              icon: Icons.add_rounded,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _GlassChoice(
                              label: '导入',
                              onPressed: () => _push(
                                context,
                                _ImportPage(
                                  store: widget.store,
                                  deckId: widget.deckId,
                                ),
                              ),
                              icon: Icons.file_download_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _GlassSearchField(
                        onChanged: (s) => _filter(() => _search = s),
                        hint: '搜索内容或标签',
                        dense: true,
                      ),
                      const SizedBox(height: 10),
                      _GlassSegments<String?>(
                        options: const {
                          null: '全部',
                          'library': '未加入',
                          'active': '计划内',
                          'paused': '暂停',
                        },
                        value: _plan,
                        stretch: true,
                        onChanged: (value) => _filter(() => _plan = value),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final entry in const {
                            'favorite': '收藏',
                            'difficult': '难卡',
                          }.entries)
                            _GlassChoice(
                              icon: entry.key == 'favorite'
                                  ? Icons.star_outline_rounded
                                  : Icons.psychology_outlined,
                              label: entry.value,
                              selected: _focus == entry.key,
                              onPressed: () => _filter(
                                () => _focus = _focus == entry.key
                                    ? null
                                    : entry.key,
                              ),
                            ),
                          _ActionMenu<String>(
                            tooltip: '按章节筛选',
                            selected: _chapter ?? '__all',
                            onSelected: (s) => _filter(
                              () => _chapter = s == '__all' ? null : s,
                            ),
                            options: {
                              '__all': '所有章节',
                              '': '未分类',
                              for (final s in d?.chapters ?? <String>[]) s: s,
                            },
                            child: Text(
                              _chapter == null
                                  ? '章节 ▾'
                                  : _chapter!.isEmpty
                                  ? '未分类 ▾'
                                  : '$_chapter ▾',
                            ),
                          ),
                          if (_tags.isNotEmpty)
                            _ActionMenu<String>(
                              tooltip: '按标签筛选',
                              selected: _tag ?? '__all',
                              onSelected: (s) =>
                                  _filter(() => _tag = s == '__all' ? null : s),
                              options: {
                                '__all': '所有标签',
                                for (final s in _tags) s: s,
                              },
                              child: Text('${_tag ?? '标签'} ▾'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: _cards.isEmpty && !_loading
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: _Empty(
                        icon: Icons.note_add_outlined,
                        title: _focus == null ? '这里还没有卡片' : '当前筛选没有卡片',
                        detail: _focus == 'favorite'
                            ? '点亮卡片右侧的星标，把重点收进收藏。'
                            : _focus == 'difficult'
                            ? '最近一次正式评分为“忘记”或“模糊”的卡片会出现在这里。'
                            : '新建或导入卡片后，勾选卡片即可加入学习计划。',
                      ),
                    )
                  : IgnorePointer(
                      ignoring: _enrolling,
                      child: Listener(
                        // 起始行会被懒加载列表回收，拖选的移动和松手由稳定的外层接收。
                        onPointerMove: (event) {
                          if (event.pointer != _selectionPointer ||
                              _selectionAnchor == null) {
                            return;
                          }
                          _selectionPosition = event.position;
                          _paintSelection();
                        },
                        onPointerUp: (event) {
                          if (event.pointer == _selectionPointer) {
                            _endSelection();
                          }
                        },
                        onPointerCancel: (event) {
                          if (event.pointer == _selectionPointer) {
                            _endSelection();
                          }
                        },
                        child: ListView.builder(
                          key: _listKey,
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          itemExtent: _rowExtent,
                          itemCount: _cards.length + (_more ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i == _cards.length) {
                              return const Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            }
                            final card = _cards[i];
                            return Card(
                              key: ValueKey(card.id),
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              clipBehavior: Clip.antiAlias,
                              shape: const RoundedSuperellipseBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(16),
                                ),
                              ),
                              color: _selected.contains(card.id)
                                  ? c.secondaryContainer
                                  : c.surfaceContainerLow,
                              child: InkWell(
                                onTap: () => _push(
                                  context,
                                  _CardPage(
                                    store: widget.store,
                                    cardId: card.id,
                                  ),
                                ),
                                onLongPress: () =>
                                    setState(() => _selected.add(card.id)),
                                child: Row(
                                  children: [
                                    Listener(
                                      onPointerDown: (event) {
                                        _selectionPointer ??= event.pointer;
                                      },
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onVerticalDragStart: (event) =>
                                            _beginSelection(
                                              i,
                                              event.globalPosition,
                                            ),
                                        child: SizedBox(
                                          width: 44,
                                          height: double.infinity,
                                          child: Checkbox(
                                            value: _selected.contains(card.id),
                                            onChanged: (checked) => setState(
                                              () {
                                                checked!
                                                    ? _selected.add(card.id)
                                                    : _selected.remove(card.id);
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Tooltip(
                                        message:
                                            '${card.chapter.isEmpty ? '未分类' : card.chapter} · ${switch (card.plan) {
                                              'active' => card.isNew ? '等待新学' : '计划内',
                                              'paused' => '已暂停',
                                              _ => '未加入计划',
                                            }}${card.tags.isEmpty ? '' : ' · ${card.tags.join(' / ')}'}',
                                        child: Text(
                                          _short(card.source, 140),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ),
                                    _FavoriteButton(
                                      store: widget.store,
                                      card: card,
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                child: SizedBox(
                  height: math.max(
                    48,
                    MediaQuery.textScalerOf(context).scale(14) * 1.5 + 20,
                  ),
                  child: _selected.isNotEmpty
                      ? Row(
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: IgnorePointer(
                                  ignoring: _enrolling,
                                  child: _GlassChoice(
                                    label: '取消 ${_selected.length}',
                                    onPressed: () {
                                      _endSelection();
                                      setState(() => _selected.clear());
                                    },
                                  ),
                                ),
                              ),
                            ),
                            _GlassProgressButton(
                              label: '加入计划',
                              onPressed: _enroll,
                              onComplete: () => setState(() {
                                _enrolling = false;
                              }),
                            ),
                            const SizedBox(width: 8),
                            IgnorePointer(
                              ignoring: _enrolling,
                              child: _ActionMenu<String>(
                                destructive: const {'delete'},
                                onSelected: _batch,
                                options: {
                                  'paused': '暂停学习',
                                  'library': '移出计划',
                                  'move': '移动到牌组',
                                  'chapter': '移动到章节',
                                  if (!isOfficialContentDeck(widget.deckId))
                                    'delete': '删除所选',
                                },
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            _GlassChoice(
                              label: '全选筛选结果',
                              onPressed: () => _action(context, () async {
                                final rows = await widget.store.cards(
                                  deckId: widget.deckId,
                                  search: _search,
                                  chapter: _chapter,
                                  plan: _plan,
                                  tag: _tag,
                                  focus: _focus,
                                  limit: 1000000,
                                );
                                if (mounted) {
                                  setState(
                                    () =>
                                        _selected.addAll(rows.map((c) => c.id)),
                                  );
                                }
                              }),
                            ),
                            const Spacer(),
                            Text(
                              '${_cards.length}${_more ? '+' : ''} 张',
                              style: TextStyle(
                                color: c.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
