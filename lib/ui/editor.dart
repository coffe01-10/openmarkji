part of 'app.dart';

class _EditorPage extends StatefulWidget {
  const _EditorPage({
    required this.store,
    required this.deck,
    this.card,
    this.chapter = '',
  });
  final AppStore store;
  final DeckData deck;
  final StudyCard? card;
  final String chapter;
  @override
  State<_EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<_EditorPage> {
  late final _source = TextEditingController(text: widget.card?.source ?? '');
  late final _tags = TextEditingController(
    text: widget.card?.tags.join(', ') ?? '',
  );
  late String _chapter = widget.card?.chapter ?? widget.chapter;
  bool _preview = false, _saving = false, _ready = false, _saved = false;
  Timer? _draftTimer;
  Future<void> _draftWrite = Future.value();
  String get _key => 'draft:${widget.card?.id ?? widget.deck.id}';
  @override
  void initState() {
    super.initState();
    _restoreDraft();
    _source.addListener(_edited);
    _tags.addListener(_edited);
  }

  Future<void> _restoreDraft() async {
    final draft = await widget.store.setting(_key);
    if (!mounted) return;
    if (draft != null) {
      final data = decodeObject(draft);
      _source.text = data['source'];
      _tags.text = data['tags'];
      _chapter = data['chapter'];
      _source.selection = TextSelection.collapsed(
        offset: (data['cursor'] as int? ?? 0).clamp(0, _source.text.length),
      );
    }
    setState(() => _ready = true);
  }

  void _edited() {
    if (!_ready) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 500), _writeDraft);
    if (mounted) setState(() {});
  }

  void _writeDraft() {
    final data = jsonEncode({
      'source': _source.text,
      'tags': _tags.text,
      'chapter': _chapter,
      'cursor': _source.selection.baseOffset,
    });
    _draftWrite = _draftWrite
        .then((_) => widget.store.setSetting(_key, data))
        .catchError((Object error) {
          if (mounted) _toast(context, '草稿未保存：$error');
        });
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _source.removeListener(_edited);
    _tags.removeListener(_edited);
    _source.dispose();
    _tags.dispose();
    super.dispose();
  }

  void _insert(String prefix, String suffix, [String placeholder = '内容']) {
    final s = _source.selection;
    final start = s.isValid ? s.start : _source.text.length;
    final end = s.isValid ? s.end : start;
    final selected = start == end
        ? placeholder
        : _source.text.substring(start, end);
    _source.value = TextEditingValue(
      text: _source.text.replaceRange(start, end, '$prefix$selected$suffix'),
      selection: TextSelection(
        baseOffset: start + prefix.length,
        extentOffset: start + prefix.length + selected.length,
      ),
    );
  }

  Future<void> _save() async {
    if (_source.text.trim().isEmpty) {
      _toast(context, '先写下一点内容');
      return;
    }
    setState(() => _saving = true);
    _draftTimer?.cancel();
    try {
      await _draftWrite;
      final values = {
        'source': _source.text,
        'tags': _tags.text
            .split(RegExp('[,，]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList(),
        'chapter': _chapter,
      };
      final card = widget.card == null
          ? StudyCard.fromJson({
              ...StudyCard(
                id: newId(),
                deckId: widget.deck.id,
                source: _source.text,
                algorithm: widget.deck.algorithm,
              ).toJson(),
              ...values,
            })
          : widget.card!.withValues(values);
      await widget.store.putCard(card);
      await widget.store.clearSetting(_key);
      if (mounted) {
        setState(() {
          _saved = true;
          _saving = false;
        });
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast(context, '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final issues = MarkjiParser().parse(_source.text).issues;
    final preview = SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: _Panel(
        child: _source.text.isEmpty
            ? const Text('写下内容后，预览会出现在这里。')
            : ContentView(
                source: _source.text,
                store: widget.store,
                replaceImages: true,
              ),
      ),
    );
    final editor = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tags,
                  decoration: const InputDecoration(
                    labelText: '标签',
                    hintText: '用逗号分隔',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: math.min(152, MediaQuery.sizeOf(context).width * .38),
                child: _ActionMenu<String>(
                  tooltip: '选择章节',
                  selected: _chapter,
                  options: {
                    for (final chapter in {
                      '',
                      ...widget.deck.chapters,
                      _chapter,
                    })
                      chapter: chapter.isEmpty ? '未分类' : chapter,
                  },
                  onSelected: (chapter) {
                    setState(() => _chapter = chapter);
                    _edited();
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: PopupValueText(
                          _chapter.isEmpty ? '未分类' : _chapter,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.unfold_more_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: TextField(
              controller: _source,
              expands: true,
              minLines: null,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontSize: 16, height: 1.8),
              decoration: const InputDecoration(
                hintText: '[P#H1#知识点标题]\n你想记住的问题是什么？\n---\n在这里写下答案。',
              ),
            ),
          ),
        ),
        if (issues.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '第 ${'\n'.allMatches(_source.text.substring(0, math.min(issues.first.offset, _source.text.length))).length + 1} 行：${issues.first.message}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
    return PopScope(
      canPop: !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_saved && !_saving) {
          _draftTimer?.cancel();
          _writeDraft();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          clipBehavior: Clip.none,
          leading: _appearanceBack(context),
          title: Text(widget.card == null ? '写一张新卡' : '编辑卡片'),
          actions: [
            _GlassToolbar(
              children: [
                if (!wide)
                  IconButton(
                    tooltip: _preview ? '返回编辑' : '预览卡片',
                    onPressed: () => setState(() => _preview = !_preview),
                    icon: Icon(
                      _preview
                          ? Icons.edit_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(52, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  onPressed: _saving || !_ready ? null : _save,
                  child: Text(_saving ? '保存中…' : '保存'),
                ),
              ],
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const _Pill('卡片语法', icon: Icons.code_rounded),
                    const Spacer(),
                    Text(
                      '草稿自动保存',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: !_ready
                    ? const Center(child: CircularProgressIndicator())
                    : wide
                    ? Row(
                        children: [
                          Expanded(child: editor),
                          const VerticalDivider(width: 1),
                          Expanded(child: preview),
                        ],
                      )
                    : _preview
                    ? preview
                    : editor,
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: _GlassToolbar(
                  children: [
                    IconButton(
                      tooltip: '加粗',
                      onPressed: () => _insert('[T#B#', ']'),
                      icon: const Icon(Icons.format_bold),
                    ),
                    IconButton(
                      tooltip: '挖空',
                      onPressed: () => _insert('[F#1#', ']', '答案'),
                      icon: const Icon(Icons.space_bar_rounded),
                    ),
                    IconButton(
                      tooltip: '公式',
                      onPressed: () => _insert('\n[E##', ']\n', r'E=mc^2'),
                      icon: const Icon(Icons.functions_rounded),
                    ),
                    IconButton(
                      tooltip: '标题',
                      onPressed: () => _insert('\n[P#H1#', ']\n', '标题'),
                      icon: const Icon(Icons.title),
                    ),
                    IconButton(
                      tooltip: '答案线',
                      onPressed: () => _insert('\n---\n', '', ''),
                      icon: const Icon(Icons.horizontal_rule),
                    ),
                    IconButton(
                      tooltip: '插入图片',
                      onPressed: () => _action(context, () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.image,
                          withData: true,
                        );
                        final file = result?.files.firstOrNull;
                        if (file?.bytes != null) {
                          final id = await widget.store.addMedia(
                            file!.name,
                            file.bytes!,
                          );
                          if (mounted) _insert('\n[Pic#ID/$id#', ']\n', '');
                        }
                      }),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                    ),
                    IconButton(
                      tooltip: '语法帮助',
                      onPressed: () => showModalBottomSheet(
                        context: context,
                        builder: (c) => const SafeArea(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                '常用卡片语法\n\n[T#B#加粗]\n[T#!!fff59d#高亮]\n[F#1#挖空答案]\n[P#H1#标题]\n[E##x^2+y^2=z^2]\n---（独立一行分隔答案）\n\n同编号的挖空一起揭晓。普通中括号写成 \\[ 和 \\]。图片通过工具栏插入；未支持的语法会保留原文。',
                                style: TextStyle(height: 1.8),
                              ),
                            ),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.help_outline),
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

class _ImportPage extends StatefulWidget {
  const _ImportPage({required this.store, this.deckId});
  final AppStore store;
  final String? deckId;
  @override
  State<_ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<_ImportPage> {
  final _input = TextEditingController(),
      _delimiter = TextEditingController(),
      _answer = TextEditingController(),
      _chapter = TextEditingController();
  late String? _deckId = widget.deckId;
  bool _plain = false, _keep = false, _busy = false;
  int _step = 0;
  List<String> _cards = [];
  final _excluded = <int>{};
  @override
  void dispose() {
    for (final c in [_input, _delimiter, _answer, _chapter]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      clipBehavior: Clip.none,
      leading: _appearanceBack(context),
      title: const Text('导入卡片'),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            child: Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const Expanded(child: Divider()),
                  _Pill(
                    '${i + 1}  ${['选择文本', '检查预览', '导入资料库'][i]}',
                    icon: _step > i ? Icons.check : null,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _step == 0
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _action(context, () async {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: ['txt'],
                            withData: true,
                          );
                          final file = result?.files.firstOrNull;
                          if (file?.bytes != null) {
                            setState(
                              () =>
                                  _input.text = decodeImportBytes(file!.bytes!),
                            );
                          }
                        }),
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('选择 TXT 文件'),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _input,
                        minLines: 9,
                        maxLines: 15,
                        decoration: const InputDecoration(
                          labelText: '或粘贴文本',
                          alignLabelWithHint: true,
                          hintText: '完整保留原始语法与换行',
                        ),
                      ),
                      const SizedBox(height: 18),
                      _GlassSegments<bool>(
                        options: const {false: '卡片语法', true: '纯文本'},
                        value: _plain,
                        onChanged: (value) => setState(() => _plain = value),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _delimiter,
                        decoration: const InputDecoration(
                          labelText: '卡片之间的独立分隔行',
                          hintText: '留空作为一张卡，例如 ===CARD===',
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '不按空行切卡；--- 专用于分隔问题与答案。分隔行必须与原文完全一致。',
                        style: TextStyle(fontSize: 12, height: 1.6),
                      ),
                      if (_plain) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _answer,
                          decoration: const InputDecoration(
                            labelText: '题答分隔文字',
                            hintText: '可选，例如 答案：',
                          ),
                        ),
                      ],
                    ],
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            _Load(
                              future: widget.store.decks(),
                              builder: (decks) {
                                _deckId ??= decks.firstOrNull?.id;
                                return DropdownButtonFormField<String>(
                                  initialValue: _deckId,
                                  decoration: const InputDecoration(
                                    labelText: '目标牌组',
                                  ),
                                  items: decks
                                      .map(
                                        (d) => DropdownMenuItem(
                                          value: d.id,
                                          child: Text(d.name),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (s) => setState(() => _deckId = s),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _chapter,
                              decoration: const InputDecoration(
                                labelText: '目标章节（可选）',
                              ),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                '保留重复卡片',
                                style: TextStyle(fontSize: 14),
                              ),
                              subtitle: const Text(
                                '默认跳过该牌组中源码相同的内容',
                                style: TextStyle(fontSize: 11),
                              ),
                              value: _keep,
                              onChanged: (v) => setState(() => _keep = v),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: _cards.length,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _Panel(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text('卡片 ${i + 1}'),
                                    value: !_excluded.contains(i),
                                    onChanged: (v) => setState(() {
                                      v!
                                          ? _excluded.remove(i)
                                          : _excluded.add(i);
                                    }),
                                  ),
                                  ContentView(
                                    source: _cards[i],
                                    store: widget.store,
                                  ),
                                  ...MarkjiParser()
                                      .parse(_cards[i])
                                      .issues
                                      .map(
                                        (e) => Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: Text(
                                            e.message,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                            ),
                                          ),
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                if (_step > 0)
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _step = 0),
                    child: const Text('返回修改'),
                  ),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _action(context, () async {
                            if (_step == 0) {
                              final cards = splitImport(
                                _input.text,
                                delimiter: _delimiter.text,
                                answerDelimiter: _answer.text,
                                plain: _plain,
                              );
                              if (cards.isEmpty) {
                                _toast(context, '请先粘贴或选择文本');
                                return;
                              }
                              setState(() {
                                _cards = cards;
                                _excluded.clear();
                                _step = 1;
                              });
                              return;
                            }
                            if (_deckId == null) {
                              _toast(context, '请先新建一副牌组');
                              return;
                            }
                            final selected = [
                              for (var i = 0; i < _cards.length; i++)
                                if (!_excluded.contains(i)) _cards[i],
                            ];
                            if (selected.isEmpty) {
                              _toast(context, '至少选择一张卡片');
                              return;
                            }
                            setState(() => _busy = true);
                            try {
                              final result = await widget.store.importCards(
                                _deckId!,
                                selected,
                                chapter: _chapter.text.trim(),
                                keepDuplicates: _keep,
                              );
                              if (context.mounted) {
                                Navigator.pop(context);
                                _toast(
                                  context,
                                  '已导入 ${result.added} 张，跳过重复 ${result.skipped} 张。到牌组中选卡加入计划。',
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          }),
                    child: Text(
                      _busy
                          ? '正在导入…'
                          : _step == 0
                          ? '预览卡片'
                          : '导入 ${_cards.length - _excluded.length} 张卡片',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _saveBytes(String name, Uint8List bytes) async {
  await file_export.saveBytes(name, bytes);
}
