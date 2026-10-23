part of 'app.dart';

const _newDeckValue = '\u0000new';

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
      _chapter = TextEditingController(),
      _deckName = TextEditingController();
  late String? _deckId = widget.deckId;
  late final _decks = widget.store.decks();
  bool _plain = false, _keep = false, _busy = false;
  int _step = 0;
  String _kind = 'text';
  ImportTable? _table;
  String _fileName = '';
  bool _header = true;
  var _question = <int>[0], _answerColumns = <int>[1];
  int? _tagColumn, _chapterColumn;
  ExternalImport? _external;
  List<ImportEntry> _cards = [];
  List<ImportMedia> _media = [];
  Map<String, Uint8List> _pending = {};
  final _excluded = <int>{};
  @override
  void dispose() {
    for (final c in [_input, _delimiter, _answer, _chapter, _deckName]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<PlatformFile?> _pick(List<String> extensions) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: true,
    );
    final file = result?.files.firstOrNull;
    return file?.bytes == null ? null : file;
  }

  void _useTable(ImportTable table, String name) {
    if (table.rows.isEmpty) throw const FormatException('表格中没有内容');
    final headers = table.headers(true);
    int? find(List<String> words) {
      for (var i = 0; i < headers.length; i++) {
        if (words.contains(headers[i].toLowerCase())) return i;
      }
      return null;
    }

    setState(() {
      _table = table;
      _fileName = name;
      _header = true;
      _tagColumn = find(['标签', 'tag', 'tags']);
      _chapterColumn = find(['章节', 'chapter', '分类']);
      final free = [
        for (var i = 0; i < table.columnCount; i++)
          if (i != _tagColumn && i != _chapterColumn) i,
      ];
      _question = free.take(1).toList();
      _answerColumns = free.skip(1).take(1).toList();
    });
  }

  Future<void> _load(Future<ExternalImport> Function() read) async {
    setState(() => _busy = true);
    try {
      final result = await read();
      if (result.entries.isEmpty) {
        throw const FormatException('没有找到可导入的卡片');
      }
      if (mounted) setState(() => _external = result);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(text, style: const TextStyle(fontSize: 12, height: 1.6)),
  );

  Widget _filePicker({
    required IconData icon,
    required String label,
    required List<String> extensions,
    required Future<void> Function(PlatformFile file) onPicked,
  }) => OutlinedButton.icon(
    onPressed: _busy
        ? null
        : () => _action(context, () async {
            final file = await _pick(extensions);
            if (file != null) await onPicked(file);
          }),
    icon: Icon(icon),
    label: Text(_busy ? '正在读取…' : label),
  );

  List<Widget> _sourceFields(BuildContext context) => switch (_kind) {
    'table' => [
      _filePicker(
        icon: Icons.table_chart_outlined,
        label: '选择 CSV / Excel 文件',
        extensions: ['csv', 'tsv', 'txt', 'xlsx', 'xls'],
        onPicked: (file) async =>
            _useTable(readTableFile(file.name, file.bytes!), file.name),
      ),
      _hint('支持 xlsx（读取第一张工作表）、CSV 与 TSV。CSV 请使用 UTF-8 编码；单元格按纯文本导入。'),
      if (_table != null) ..._mappingFields(_table!),
    ],
    'anki' => [
      _filePicker(
        icon: Icons.style_outlined,
        label: '选择 Anki 牌组包（.apkg）',
        extensions: ['apkg', 'colpkg'],
        onPicked: (file) async {
          _fileName = file.name;
          await _load(() => readApkg(file.bytes!));
        },
      ),
      _hint('按笔记模板生成问答卡；挖空笔记每条合成一张卡，图片一并导入。只导入内容，Anki 的复习记录不会带入。'),
      if (_external != null) _summary(context, _external!),
    ],
    'package' => [
      _filePicker(
        icon: Icons.inventory_2_outlined,
        label: '选择牌组分享包（.omdeck）',
        extensions: [deckPackageExtension, 'zip'],
        onPicked: (file) async {
          _fileName = file.name;
          await _load(() async => decodeDeckPackage(file.bytes!));
        },
      ),
      _hint('分享包在牌组的更多操作中导出，包含卡片、章节、标签和图片，不含学习记录。'),
      if (_external != null) _summary(context, _external!),
    ],
    _ => [
      _filePicker(
        icon: Icons.upload_file_outlined,
        label: '选择 TXT 文件',
        extensions: ['txt'],
        onPicked: (file) async =>
            setState(() => _input.text = decodeImportBytes(file.bytes!)),
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
      _hint('不按空行切卡；--- 专用于分隔问题与答案。分隔行必须与原文完全一致。'),
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
  };

  Widget _summary(BuildContext context, ExternalImport data) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: _Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '${data.entries.length} 张卡片 · ${data.media.length} 张图片 · $_fileName',
            style: const TextStyle(fontSize: 13),
          ),
          for (final warning in data.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                warning,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    ),
  );

  List<Widget> _mappingFields(ImportTable table) {
    final headers = table.headers(_header);
    final rows = table.rows.length - (_header ? 1 : 0);
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
    Widget columns(List<int> value, ValueChanged<List<int>> onChanged) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < headers.length; i++)
          FilterChip(
            label: Text(headers[i]),
            selected: value.contains(i),
            onSelected: (on) => setState(
              () => onChanged(
                on
                    ? ([...value, i]..sort())
                    : value.where((c) => c != i).toList(),
              ),
            ),
          ),
      ],
    );
    Widget column(int? value, ValueChanged<int?> onChanged) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('不使用'),
          selected: value == null,
          onSelected: (_) => setState(() => onChanged(null)),
        ),
        for (var i = 0; i < headers.length; i++)
          ChoiceChip(
            label: Text(headers[i]),
            selected: value == i,
            onSelected: (_) => setState(() => onChanged(i)),
          ),
      ],
    );
    return [
      const SizedBox(height: 16),
      Text('$_fileName · ${table.columnCount} 列 · $rows 行'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('首行是表头', style: TextStyle(fontSize: 14)),
        value: _header,
        onChanged: (v) => setState(() => _header = v),
      ),
      label('问题'),
      columns(_question, (v) => _question = v),
      label('答案'),
      columns(_answerColumns, (v) => _answerColumns = v),
      _hint('选中多列时按顺序换行合并。'),
      label('标签'),
      column(_tagColumn, (v) => _tagColumn = v),
      _hint('一个单元格可写多个标签，用空格、逗号或分号分隔。'),
      label('章节'),
      column(_chapterColumn, (v) => _chapterColumn = v),
    ];
  }

  List<ImportEntry> _collect() => switch (_kind) {
    'table' =>
      _table == null
          ? []
          : tableEntries(
              _table!,
              TableMapping(
                firstRowHeader: _header,
                question: _question,
                answer: _answerColumns,
                tags: _tagColumn,
                chapter: _chapterColumn,
              ),
            ),
    'anki' || 'package' => _external?.entries ?? [],
    _ => splitImport(
      _input.text,
      delimiter: _delimiter.text,
      answerDelimiter: _answer.text,
      plain: _plain,
    ).map(ImportEntry.new).toList(),
  };

  Future<void> _next(BuildContext context) async {
    if (_step == 0) {
      if (_kind == 'table' && _table != null && _question.isEmpty) {
        _toast(context, '请至少选择一列作为问题');
        return;
      }
      final cards = _collect();
      if (cards.isEmpty) {
        _toast(context, _kind == 'text' ? '请先粘贴或选择文本' : '请先选择包含卡片的文件');
        return;
      }
      final external = _kind == 'anki' || _kind == 'package';
      setState(() {
        _cards = cards;
        _media = external ? _external!.media : [];
        _pending = external ? _external!.mediaById : {};
        _excluded.clear();
        // 文件来源默认导入同名新牌组，避免混进当前牌组。
        if (_kind != 'text' && widget.deckId == null) {
          _deckId = _newDeckValue;
          _deckName.text = external
              ? _external!.title
              : _fileName.replaceFirst(RegExp(r'\.[^.]*$'), '');
        }
        _step = 1;
      });
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
    if (_deckId == _newDeckValue && _deckName.text.trim().isEmpty) {
      _toast(context, '请填写新牌组名称');
      return;
    }
    setState(() => _busy = true);
    try {
      var deckId = _deckId!;
      if (deckId == _newDeckValue) {
        final shared = _kind == 'package';
        deckId = (await widget.store.createDeck(
          _deckName.text.trim(),
          description: shared ? _external!.description : '',
          group: shared ? _external!.group : '',
        )).id;
      }
      final result = await widget.store.importEntries(
        deckId,
        selected,
        chapter: _chapter.text.trim(),
        keepDuplicates: _keep,
        media: _media,
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
  }

  Widget _preview(BuildContext context, int i) {
    final card = _cards[i];
    final meta = [
      if (card.chapter.isNotEmpty) '章节 ${card.chapter}',
      if (card.tags.isNotEmpty) '标签 ${card.tags.join('、')}',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _Panel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('卡片 ${i + 1}'),
              subtitle: meta.isEmpty
                  ? null
                  : Text(
                      meta.join(' · '),
                      style: const TextStyle(fontSize: 12),
                    ),
              value: !_excluded.contains(i),
              onChanged: (v) => setState(() {
                v! ? _excluded.remove(i) : _excluded.add(i);
              }),
            ),
            ContentView(
              source: card.source,
              store: widget.store,
              pendingMedia: _pending,
            ),
            ...MarkjiParser()
                .parse(card.source)
                .issues
                .map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      e.message,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _targetFields() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Column(
      children: [
        _Load(
          future: _decks,
          builder: (decks) {
            _deckId ??= decks.firstOrNull?.id ?? _newDeckValue;
            return DropdownButtonFormField<String>(
              initialValue: _deckId,
              decoration: const InputDecoration(labelText: '目标牌组'),
              items: [
                for (final d in decks)
                  DropdownMenuItem(value: d.id, child: Text(d.name)),
                const DropdownMenuItem(
                  value: _newDeckValue,
                  child: Text('新建牌组'),
                ),
              ],
              onChanged: (s) => setState(() => _deckId = s),
            );
          },
        ),
        if (_deckId == _newDeckValue) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _deckName,
            decoration: const InputDecoration(labelText: '新牌组名称'),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _chapter,
          decoration: InputDecoration(
            labelText: '目标章节（可选）',
            helperText: _cards.any((c) => c.chapter.isNotEmpty)
                ? '已带章节的卡片保留原章节'
                : null,
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('保留重复卡片', style: TextStyle(fontSize: 14)),
          subtitle: const Text(
            '默认跳过该牌组中源码相同的内容',
            style: TextStyle(fontSize: 11),
          ),
          value: _keep,
          onChanged: (v) => setState(() => _keep = v),
        ),
      ],
    ),
  );

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
                    '${i + 1}  ${['选择来源', '检查预览', '导入资料库'][i]}',
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
                      _GlassSegments<String>(
                        options: const {
                          'text': '文本',
                          'table': '表格',
                          'anki': 'Anki',
                          'package': '分享包',
                        },
                        value: _kind,
                        onChanged: (value) {
                          if (_busy) return;
                          setState(() {
                            _kind = value;
                            _external = null;
                          });
                        },
                      ),
                      const SizedBox(height: 18),
                      ..._sourceFields(context),
                    ],
                  )
                : Column(
                    children: [
                      _targetFields(),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: _cards.length,
                          itemBuilder: _preview,
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
                        : () => _action(context, () => _next(context)),
                    child: Text(
                      _busy
                          ? (_step == 0 ? '正在读取…' : '正在导入…')
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
