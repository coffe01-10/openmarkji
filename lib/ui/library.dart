part of 'app.dart';

class _LibraryPage extends StatefulWidget {
  const _LibraryPage({required this.store});
  final AppStore store;
  @override
  State<_LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<_LibraryPage> {
  String _search = '';
  String? _group, _selected;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => _Load(
      future: widget.store.decks(),
      builder: (decks) {
        final visible = decks
            .where(
              (d) =>
                  d.name.toLowerCase().contains(_search.toLowerCase()) &&
                  (_group == null || d.group == _group),
            )
            .toList();
        final wide = MediaQuery.sizeOf(context).width >= 840;
        final list = _Page(
          title: '你的知识收藏',
          subtitle: 'LIBRARY  /  ${decks.length} 副牌组',
          trailing: IconButton.filledTonal(
            onPressed: () => _editDeck(context, widget.store),
            tooltip: '新建牌组',
            icon: const Icon(Icons.add_rounded),
          ),
          children: [
            TextField(
              onChanged: (s) => setState(() => _search = s),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: '搜索牌组',
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('全部'),
                  selected: _group == null,
                  onSelected: (_) => setState(() => _group = null),
                ),
                ...decks
                    .map((d) => d.group)
                    .where((g) => g.isNotEmpty)
                    .toSet()
                    .map(
                      (g) => ChoiceChip(
                        label: Text(g),
                        selected: _group == g,
                        onSelected: (_) => setState(() => _group = g),
                      ),
                    ),
              ],
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
            ...visible.map(
              (d) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DeckTile(
                  store: widget.store,
                  deck: d,
                  selected: wide && d.id == _selected,
                  onTap: () {
                    if (wide) {
                      setState(() => _selected = d.id);
                    } else {
                      _push(
                        context,
                        _DeckPage(store: widget.store, deckId: d.id),
                      );
                    }
                  },
                ),
              ),
            ),
            if (decks.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () =>
                    _push(context, _ImportPage(store: widget.store)),
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('导入墨墨文本'),
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
  var algorithm = deck?.algorithm ?? 6;
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
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 6, label: Text('MMX-6')),
                      ButtonSegment(value: 5, label: Text('MMX-5')),
                    ],
                    selected: {algorithm},
                    onSelectionChanged: (s) => setSheet(() {
                      algorithm = s.first;
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
    this.embedded = false,
  });
  final AppStore store;
  final String deckId;
  final bool embedded;
  @override
  State<_DeckPage> createState() => _DeckPageState();
}

class _DeckPageState extends State<_DeckPage> {
  String _search = '';
  String? _chapter, _plan, _tag, _focus;
  final _selected = <String>{};
  final _scroll = ScrollController();
  List<StudyCard> _cards = [];
  DeckData? _deck;
  List<String> _tags = [];
  bool _loading = false, _more = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_refresh);
    _refresh();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _loadMore();
    });
  }

  @override
  void dispose() {
    widget.store.removeListener(_refresh);
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    _generation++;
    _cards = [];
    _more = true;
    _loading = false;
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_more) return;
    final gen = _generation;
    _loading = true;
    try {
      final values = await widget.store.cards(
        deckId: widget.deckId,
        search: _search,
        chapter: _chapter,
        plan: _plan,
        tag: _tag,
        focus: _focus,
        offset: _cards.length,
      );
      final deck = await widget.store.deck(widget.deckId);
      final tags = await widget.store.tags(widget.deckId);
      if (mounted && gen == _generation) {
        setState(() {
          _cards.addAll(values);
          _more = values.length == 60;
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
    setState(update);
    _refresh();
  }

  Future<void> _batch(String operation) async {
    final ids = _selected.toList();
    await _action(context, () async {
      if (operation == 'delete') {
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

  @override
  Widget build(BuildContext context) {
    final d = _deck;
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: widget.embedded ? c.surface : null,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Text(d?.name ?? '牌组'),
        actions: [
          if (d != null)
            IconButton(
              tooltip: '专项练习',
              icon: const Icon(Icons.school_outlined),
              onPressed: () => _push(
                context,
                _PracticeSetupPage(store: widget.store, deck: d, focus: _focus),
              ),
            ),
          if (d != null)
            IconButton(
              tooltip: '牌组设置',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => _editDeck(context, widget.store, deck: d),
            ),
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
                  'SELECT source FROM cards WHERE deck_id=? ORDER BY rowid',
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
                  context.mounted &&
                  await _confirm(context, '删除整副牌组？', '牌组中的卡片和学习记录将一起删除。')) {
                await widget.store.deleteDeck(widget.deckId);
                if (context.mounted && !widget.embedded) Navigator.pop(context);
              }
            }),
            options: const {
              'chapter': '新建章节',
              'export': '导出语法 TXT',
              'plain': '导出纯文本',
              'delete': '删除牌组',
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
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
                      child: FilledButton.tonalIcon(
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
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('写卡片'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _push(
                          context,
                          _ImportPage(
                            store: widget.store,
                            deckId: widget.deckId,
                          ),
                        ),
                        icon: const Icon(Icons.file_download_outlined),
                        label: const Text('导入'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  onChanged: (s) => _filter(() => _search = s),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: '搜索内容或标签',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final entry in const {
                        'favorite': '收藏',
                        'difficult': '难卡',
                      }.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            avatar: Icon(
                              entry.key == 'favorite'
                                  ? Icons.star_outline_rounded
                                  : Icons.psychology_outlined,
                              size: 18,
                            ),
                            label: Text(entry.value),
                            selected: _focus == entry.key,
                            onSelected: (selected) => _filter(
                              () => _focus = selected ? entry.key : null,
                            ),
                          ),
                        ),
                      for (final entry in <String?, String>{
                        null: '全部',
                        'library': '未加入',
                        'active': '计划内',
                        'paused': '暂停',
                      }.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(entry.value),
                            selected: _plan == entry.key,
                            onSelected: (_) => _filter(() => _plan = entry.key),
                          ),
                        ),
                      _ActionMenu<String>(
                        tooltip: '按章节筛选',
                        selected: _chapter ?? '__all',
                        onSelected: (s) =>
                            _filter(() => _chapter = s == '__all' ? null : s),
                        options: {
                          '__all': '所有章节',
                          '': '未分类',
                          for (final s in d?.chapters ?? <String>[]) s: s,
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            _chapter == null
                                ? '章节 ▾'
                                : _chapter!.isEmpty
                                ? '未分类 ▾'
                                : '$_chapter ▾',
                          ),
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
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text('${_tag ?? '标签'} ▾'),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_selected.isNotEmpty)
            Container(
              color: c.secondaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() => _selected.clear()),
                    child: Text('取消 ${_selected.length}'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _batch('active'),
                    child: const Text('加入计划'),
                  ),
                  _ActionMenu<String>(
                    destructive: const {'delete'},
                    onSelected: _batch,
                    options: const {
                      'paused': '暂停学习',
                      'library': '移出计划',
                      'move': '移动到牌组',
                      'chapter': '移动到章节',
                      'delete': '删除所选',
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            child: _cards.isEmpty && !_loading
                ? Padding(
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
                : ListView.builder(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(
                      12,
                      8,
                      12,
                      widget.embedded ? 24 : 100,
                    ),
                    itemCount: _cards.length + (_more ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == _cards.length) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      final card = _cards[i];
                      return Card(
                        key: ValueKey(card.id),
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        color: _selected.contains(card.id)
                            ? c.secondaryContainer
                            : c.surfaceContainerLow,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          leading: Checkbox(
                            value: _selected.contains(card.id),
                            onChanged: (checked) => setState(() {
                              checked!
                                  ? _selected.add(card.id)
                                  : _selected.remove(card.id);
                            }),
                          ),
                          trailing: _FavoriteButton(
                            store: widget.store,
                            card: card,
                          ),
                          title: Text(
                            _short(card.source, 100),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, height: 1.5),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${card.chapter.isEmpty ? '未分类' : card.chapter} · ${switch (card.plan) {
                                'active' => card.isNew ? '等待新学' : '计划内',
                                'paused' => '已暂停',
                                _ => '未加入计划',
                              }}${card.tags.isEmpty ? '' : ' · ${card.tags.join(' / ')}'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          onTap: () => _push(
                            context,
                            _CardPage(store: widget.store, cardId: card.id),
                          ),
                          onLongPress: () =>
                              setState(() => _selected.add(card.id)),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  TextButton(
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
                        setState(() => _selected.addAll(rows.map((c) => c.id)));
                      }
                    }),
                    child: const Text('全选筛选结果'),
                  ),
                  const Spacer(),
                  Text(
                    '${_cards.length}${_more ? '+' : ''} 张',
                    style: TextStyle(color: c.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
