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
  final _sourceFocus = FocusNode();
  final _fieldStack = GlobalKey();
  InlineToken? _token;
  Rect? _caret;
  Timer? _draftTimer;
  Future<void> _draftWrite = Future.value();
  String get _key => 'draft:${widget.card?.id ?? widget.deck.id}';
  @override
  void initState() {
    super.initState();
    _restoreDraft();
    _source.addListener(_edited);
    _tags.addListener(_edited);
    _source.addListener(_track);
    _sourceFocus.addListener(_track);
  }

  /// 光标在公式或图片语法上时，记录语法与光标位置，供悬浮预览定位。
  void _track() {
    final s = _source.selection;
    final token = _sourceFocus.hasFocus && s.isValid && s.isCollapsed
        ? inlineTokenAt(_source.text, s.baseOffset)
        : null;
    if (token == null) {
      if (_token != null && mounted) {
        setState(() {
          _token = null;
          _caret = null;
        });
      }
      return;
    }
    _token = token;
    // 新文本布局完成后才能取得光标坐标。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _token == null) return;
      final caret = _caretRect();
      if (caret != _caret) setState(() => _caret = caret);
    });
    if (mounted) setState(() {});
  }

  Rect? _caretRect() {
    final stack = _fieldStack.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null || !stack.attached) return null;
    RenderEditable? editable;
    void visit(RenderObject o) {
      if (editable != null) return;
      if (o is RenderEditable) {
        editable = o;
      } else {
        o.visitChildren(visit);
      }
    }

    stack.visitChildren(visit);
    final e = editable;
    if (e == null || !e.hasSize) return null;
    final offset = _source.selection.baseOffset.clamp(0, _source.text.length);
    final local = e.getLocalRectForCaret(TextPosition(offset: offset));
    final origin = stack.globalToLocal(e.localToGlobal(local.topLeft));
    final rect = origin & local.size;
    final visible = Offset.zero & stack.size;
    return visible.contains(rect.center) ? rect : null;
  }

  /// 光标上方的玻璃悬浮窗，不拦截输入手势；上方被标题栏挡住时才放到下方。
  Widget _inlineBubble(BoxConstraints box) {
    final token = _token, caret = _caret;
    final show = token != null && caret != null;
    final r = caret ?? Rect.zero;
    final stack = _fieldStack.currentContext?.findRenderObject() as RenderBox?;
    final top = stack != null && stack.attached
        ? stack.localToGlobal(Offset.zero).dy
        : 0.0;
    final roomAbove =
        top + r.top - MediaQuery.paddingOf(context).top - kToolbarHeight;
    final below =
        roomAbove < (token?.tag == 'Pic' ? 210 : 120) &&
        r.bottom + 210 < box.maxHeight;
    final x = box.maxWidth <= 0 ? 0.0 : (r.left / box.maxWidth) * 2 - 1;
    return Positioned(
      left: 0,
      right: 0,
      top: below ? r.bottom + 6 : null,
      bottom: below ? null : box.maxHeight - r.top + 6,
      child: IgnorePointer(
        child: Align(
          alignment: Alignment(x.clamp(-1.0, 1.0), below ? -1 : 1),
          child: AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: _duration(context, 160),
            child: AnimatedScale(
              scale: show ? 1 : .94,
              alignment: below ? Alignment.topCenter : Alignment.bottomCenter,
              duration: _duration(context, 200),
              curve: Curves.easeOutCubic,
              child: !show
                  ? const SizedBox.shrink()
                  : ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 120,
                        maxWidth: 360,
                        maxHeight: 190,
                      ),
                      child: _GlassSurface(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                token.tag == 'E' ? '公式预览' : '图片预览',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Flexible(
                                child: InlinePreview(
                                  token: token,
                                  store: widget.store,
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
    _source.removeListener(_track);
    _tags.removeListener(_edited);
    _sourceFocus.dispose();
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
    // 工具栏按钮和文件选择会让输入框失焦，插入后回到输入框以显示悬浮预览。
    // Web 端重新聚焦时浏览器会把光标重置到开头，下一帧再恢复插入后的选区。
    final value = _source.value;
    _sourceFocus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _source.text == value.text) _source.value = value;
    });
  }

  Future<void> _insertReference() async {
    final card = await showModalBottomSheet<StudyCard>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReferencePicker(store: widget.store),
    );
    if (card != null && mounted) {
      _insert(
        '[Ref#ID/${card.id}#',
        ']',
        escapeMarkji(_short(card.source, 36)),
      );
    }
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
    } catch (e, stack) {
      DiagnosticLog.instance.error('保存卡片', e, stack);
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
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                key: _fieldStack,
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: TextField(
                      controller: _source,
                      focusNode: _sourceFocus,
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
                  _inlineBubble(box),
                ],
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
                      tooltip: '引用卡片',
                      onPressed: _insertReference,
                      icon: const Icon(Icons.link_rounded),
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
                                '常用卡片语法\n\n[T#B#加粗]\n[T#!!fff59d#高亮]\n[F#1#挖空答案]\n[P#H1#标题]\n[E##x^2+y^2=z^2]\n[Ref#ID/卡片ID#显示文字]\n---（独立一行分隔答案）\n\n同编号的挖空一起揭晓。普通中括号写成 \\[ 和 \\]。图片和卡片引用可通过工具栏插入；点击引用先预览，再打开详情。未支持的语法会保留原文。',
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

class _ReferencePicker extends StatefulWidget {
  const _ReferencePicker({required this.store});
  final AppStore store;

  @override
  State<_ReferencePicker> createState() => _ReferencePickerState();
}

class _ReferencePickerState extends State<_ReferencePicker> {
  String _search = '';

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .85,
    child: SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 16, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '引用卡片',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: '关闭选卡',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _GlassSearchField(
              hint: '搜索要引用的卡片',
              onChanged: (value) => setState(() => _search = value.trim()),
            ),
          ),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  sliver: _LibraryCardResults(
                    store: widget.store,
                    search: _search,
                    group: null,
                    revision: widget.store.revision,
                    onSelected: (card) => Navigator.pop(context, card),
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
