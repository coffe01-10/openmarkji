import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../content/external_import.dart';
import '../content/markji.dart';
import 'sqlite_bytes.dart';
import 'sqlite_bytes_common.dart' show CommonDatabase;

/// 读取 Anki 导出的 .apkg：渲染卡片模板，把 HTML 转为卡片语法，图片随卡片导入。
/// 只导入内容，不带入 Anki 的复习记录与排期。
Future<ExternalImport> readApkg(Uint8List bytes) async {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('不是有效的 Anki 牌组包');
  }
  final latest = archive.findFile('collection.anki21b');
  final legacy =
      archive.findFile('collection.anki21') ??
      archive.findFile('collection.anki2');
  final Uint8List collection;
  if (latest != null) {
    collection = ZstdDecoder().decodeBytes(latest.content);
  } else if (legacy != null) {
    collection = legacy.content;
  } else {
    throw const FormatException('Anki 牌组包中没有找到卡片数据');
  }
  final names = _mediaNames(archive, zstd: latest != null);
  final raw = await readSqliteBytes(collection, _readCollection);
  final warnings = <String>[];
  final media = <String, ImportMedia>{};
  var missing = 0;
  String? resolve(String filename) {
    final entry = names[filename];
    final file = entry == null ? null : archive.findFile(entry);
    if (file == null) {
      missing++;
      return null;
    }
    final existing = media[filename];
    if (existing != null) return existing.id;
    var content = file.content;
    if (latest != null) content = ZstdDecoder().decodeBytes(content);
    final key = mediaKey(content);
    media[filename] = ImportMedia(key, filename, content);
    return key;
  }

  final converter = AnkiHtml(resolve);
  final entries = <ImportEntry>[];
  final clozeNotes = <int>{};
  final deckNames = <String>{for (final c in raw.cards) raw.decks[c.deck] ?? ''}
    ..remove('');
  final root = _commonDeckPath(deckNames);
  for (final card in raw.cards) {
    final type = raw.types[card.type];
    if (type == null) continue;
    final template = type.cloze
        ? type.templates.firstOrNull
        : type.templates.where((t) => t.ord == card.ord).firstOrNull;
    if (template == null) continue;
    if (type.cloze && !clozeNotes.add(card.note)) continue;
    final fields = <String, String>{
      for (var i = 0; i < type.fields.length; i++)
        type.fields[i]: i < card.fields.length ? card.fields[i] : '',
    };
    final deck = raw.decks[card.deck] ?? '';
    final source = converter.card(
      template.question,
      template.answer,
      fields,
      tags: card.tags,
      deck: deck,
    );
    if (source.trim().isEmpty) continue;
    entries.add(
      ImportEntry(source, tags: card.tags, chapter: _relativeDeck(deck, root)),
    );
  }
  if (missing > 0) warnings.add('$missing 处图片未包含在牌组包中，已保留文件名');
  if (converter.sounds > 0) {
    warnings.add('${converter.sounds} 处音频暂不支持播放，已省略');
  }
  final title = root.isEmpty
      ? (deckNames.length == 1 ? deckNames.first : 'Anki 牌组')
      : root;
  return ExternalImport(
    title: title.split('::').last,
    entries: entries,
    media: media.values.toList(),
    warnings: warnings,
  );
}

/// 文件在压缩包中的名字 → 原始文件名。
Map<String, String> _mediaNames(Archive archive, {required bool zstd}) {
  final file = archive.findFile('media');
  if (file == null) return {};
  final content = file.content;
  if (content.isEmpty) return {};
  if (!zstd) {
    try {
      final map = Map<String, dynamic>.from(jsonDecode(utf8.decode(content)));
      return {for (final e in map.entries) '${e.value}': e.key};
    } catch (_) {
      return {};
    }
  }
  // MediaEntries { repeated MediaEntry entries = 1; }
  // MediaEntry { string name = 1; uint32 size = 2; bytes sha1 = 3; uint32 legacy_zip_filename = 255; }
  final result = <String, String>{};
  final entries = _proto(ZstdDecoder().decodeBytes(content))[1] ?? const [];
  for (var i = 0; i < entries.length; i++) {
    final entry = _proto(entries[i] as Uint8List);
    final name = entry[1]?.firstOrNull;
    if (name is! Uint8List) continue;
    final legacy = entry[255]?.firstOrNull;
    result[utf8.decode(name, allowMalformed: true)] =
        '${legacy is int ? legacy : i}';
  }
  return result;
}

String _commonDeckPath(Set<String> names) {
  if (names.isEmpty) return '';
  var parts = names.first.split('::');
  for (final name in names.skip(1)) {
    final other = name.split('::');
    var n = 0;
    while (n < parts.length && n < other.length && parts[n] == other[n]) {
      n++;
    }
    parts = parts.sublist(0, n);
  }
  return parts.join('::');
}

String _relativeDeck(String deck, String root) {
  if (deck == root || deck.isEmpty) return '';
  final rest = root.isEmpty ? deck : deck.substring(root.length + 2);
  return rest.split('::').join(' / ');
}

class _Template {
  const _Template(this.ord, this.question, this.answer);
  final int ord;
  final String question, answer;
}

class _NoteType {
  _NoteType({
    required this.cloze,
    required this.fields,
    required this.templates,
  });
  final bool cloze;
  final List<String> fields;
  final List<_Template> templates;
}

class _Card {
  const _Card(
    this.note,
    this.ord,
    this.deck,
    this.type,
    this.fields,
    this.tags,
  );
  final int note, ord, deck, type;
  final List<String> fields, tags;
}

class _Collection {
  const _Collection(this.types, this.decks, this.cards);
  final Map<int, _NoteType> types;
  final Map<int, String> decks;
  final List<_Card> cards;
}

_Collection _readCollection(CommonDatabase db) {
  final tables = {
    for (final row in db.select(
      "SELECT name FROM sqlite_master WHERE type='table'",
    ))
      row['name'] as String,
  };
  if (!tables.contains('notes') || !tables.contains('cards')) {
    throw const FormatException('Anki 数据库缺少卡片表');
  }
  final types = <int, _NoteType>{};
  final decks = <int, String>{};
  if (tables.contains('notetypes')) {
    final fields = <int, List<String>>{};
    for (final row in db.select(
      'SELECT ntid, name FROM fields ORDER BY ntid, ord',
    )) {
      fields.putIfAbsent(row['ntid'] as int, () => []).add('${row['name']}');
    }
    final templates = <int, List<_Template>>{};
    for (final row in db.select(
      'SELECT ntid, ord, config FROM templates ORDER BY ntid, ord',
    )) {
      final config = _proto(row['config'] as Uint8List);
      templates
          .putIfAbsent(row['ntid'] as int, () => [])
          .add(
            _Template(
              row['ord'] as int,
              _string(config[1]),
              _string(config[2]),
            ),
          );
    }
    for (final row in db.select('SELECT id, config FROM notetypes')) {
      final id = row['id'] as int;
      final config = _proto(row['config'] as Uint8List);
      types[id] = _NoteType(
        cloze: config[1]?.firstOrNull == 1,
        fields: fields[id] ?? const [],
        templates: templates[id] ?? const [],
      );
    }
    for (final row in db.select('SELECT id, name FROM decks')) {
      decks[row['id'] as int] = '${row['name']}'.replaceAll('\x1f', '::');
    }
  } else {
    final col = db.select('SELECT models, decks FROM col').firstOrNull;
    if (col == null) throw const FormatException('Anki 数据库缺少牌组信息');
    final models = Map<String, dynamic>.from(jsonDecode(col['models']));
    for (final model in models.values.cast<Map>()) {
      final flds = [...(model['flds'] as List).cast<Map>()]
        ..sort((a, b) => (a['ord'] as int).compareTo(b['ord'] as int));
      types[int.parse('${model['id']}')] = _NoteType(
        cloze: model['type'] == 1,
        fields: [for (final f in flds) '${f['name']}'],
        templates: [
          for (final t in (model['tmpls'] as List).cast<Map>())
            _Template(t['ord'] as int, '${t['qfmt']}', '${t['afmt']}'),
        ],
      );
    }
    final deckMap = Map<String, dynamic>.from(jsonDecode(col['decks']));
    for (final deck in deckMap.values.cast<Map>()) {
      decks[int.parse('${deck['id']}')] = '${deck['name']}';
    }
  }
  final cards = [
    for (final row in db.select(
      'SELECT c.nid, c.ord, c.did, n.mid, n.flds, n.tags FROM cards c '
      'JOIN notes n ON n.id=c.nid ORDER BY c.nid, c.ord',
    ))
      _Card(
        row['nid'] as int,
        row['ord'] as int,
        row['did'] as int,
        row['mid'] as int,
        '${row['flds']}'.split('\x1f'),
        '${row['tags']}'
            .split(RegExp(r'\s+'))
            .where((t) => t.isNotEmpty)
            .toList(),
      ),
  ];
  return _Collection(types, decks, cards);
}

String _string(List<Object>? values) {
  final value = values?.firstOrNull;
  return value is Uint8List ? utf8.decode(value, allowMalformed: true) : '';
}

/// 最小 protobuf 读取：只区分 varint 与长度分隔字段，足够读取模板和媒体清单。
Map<int, List<Object>> _proto(Uint8List data) {
  final result = <int, List<Object>>{};
  var pos = 0;
  int varint() {
    var value = 0;
    var shift = 0;
    while (pos < data.length) {
      final b = data[pos++];
      value |= (b & 0x7f) << shift;
      if (b < 0x80) break;
      shift += 7;
    }
    return value;
  }

  while (pos < data.length) {
    final key = varint();
    final field = key >> 3;
    switch (key & 7) {
      case 0:
        result.putIfAbsent(field, () => []).add(varint());
      case 1:
        pos += 8;
      case 2:
        final length = varint();
        if (pos + length > data.length) return result;
        result
            .putIfAbsent(field, () => [])
            .add(Uint8List.sublistView(data, pos, pos + length));
        pos += length;
      case 5:
        pos += 4;
      default:
        return result;
    }
  }
  return result;
}

/// Anki 模板与 HTML 字段转为卡片语法。
class AnkiHtml {
  AnkiHtml(this.resolveMedia);

  /// 文件名 → 媒体 ID；找不到时返回 null。
  final String? Function(String filename) resolveMedia;
  int sounds = 0;

  String card(
    String question,
    String answer,
    Map<String, String> fields, {
    List<String> tags = const [],
    String deck = '',
  }) {
    final front = convert(render(question, fields, tags: tags, deck: deck));
    final back = convert(
      render(
        answer
            .replaceAll(RegExp(r'\{\{\s*FrontSide\s*\}\}'), '')
            .replaceAll(RegExp(r'\{\{\s*cloze:[^}]+\}\}'), ''),
        fields,
        tags: tags,
        deck: deck,
      ),
    );
    if (back.isEmpty || back == front) return front;
    return front.isEmpty ? back : '$front\n---\n$back';
  }

  String render(
    String template,
    Map<String, String> fields, {
    List<String> tags = const [],
    String deck = '',
  }) {
    String? value(String name) => switch (name) {
      'Tags' => tags.join(' '),
      'Deck' => deck,
      'Subdeck' => deck.split('::').last,
      _ => fields[name],
    };
    var text = template;
    final section = RegExp(
      r'\{\{([#^])\s*([^}]+?)\s*\}\}([\s\S]*?)\{\{/\s*\2\s*\}\}',
    );
    for (var guard = 0; guard < 20 && section.hasMatch(text); guard++) {
      text = text.replaceAllMapped(section, (m) {
        final filled = _stripHtml(value(m[2]!) ?? '').trim().isNotEmpty;
        return (m[1] == '#') == filled ? m[3]! : '';
      });
    }
    return text.replaceAllMapped(RegExp(r'\{\{([^#^/{}][^{}]*?)\}\}'), (m) {
      final parts = m[1]!.split(':').map((p) => p.trim()).toList();
      final content = value(parts.last) ?? '';
      final filters = parts.sublist(0, parts.length - 1);
      if (filters.contains('type') || filters.any((f) => f.startsWith('tts'))) {
        return '';
      }
      if (filters.contains('cloze')) return _cloze(content);
      if (filters.contains('text')) return _stripHtml(content);
      return content;
    });
  }

  /// {{c1::答案::提示}} → 占位符，HTML 转换后再变成 [F#1#答案]。
  String _cloze(String text) => text.replaceAllMapped(
    RegExp(r'\{\{c(\d+)::([\s\S]*?)(?:::[^{}]*?)?\}\}'),
    (m) => '\u0001${m[1]}\u0002${_stripHtml(m[2]!)}\u0003',
  );

  String convert(String html) {
    var source = html
        .replaceAll(
          RegExp(r'<(style|script)[^>]*>[\s\S]*?</\1>', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
        .replaceAllMapped(RegExp(r'\[sound:[^\]]*\]'), (_) {
          sounds++;
          return '';
        });
    final out = StringBuffer();
    final styles = <String>[];
    final pending = StringBuffer();
    void flushText() {
      if (pending.isEmpty) return;
      out.write(_styled(pending.toString(), {...styles}));
      pending.clear();
    }

    void newline() {
      flushText();
      out.write('\n');
    }

    for (final token in RegExp(r'<[^>]*>|[^<]+|<').allMatches(source)) {
      final t = token[0]!;
      if (!t.startsWith('<') || t == '<') {
        pending.write(_decodeEntities(t.replaceAll(RegExp(r'\s*\n\s*'), ' ')));
        continue;
      }
      final tag = RegExp(r'^</?\s*([a-zA-Z0-9]+)')
          .firstMatch(t)?[1]
          ?.toLowerCase();
      final closing = t.startsWith('</');
      switch (tag) {
        case 'br':
          newline();
        case 'div' ||
            'p' ||
            'li' ||
            'tr' ||
            'h1' ||
            'h2' ||
            'h3' ||
            'h4' ||
            'h5' ||
            'h6' ||
            'ul' ||
            'ol' ||
            'table' ||
            'blockquote' ||
            'hr':
          newline();
        case 'b' || 'strong' || 'i' || 'em' || 'u':
          final style = switch (tag) {
            'b' || 'strong' => 'B',
            'i' || 'em' => 'I',
            _ => 'U',
          };
          flushText();
          if (closing) {
            final at = styles.lastIndexOf(style);
            if (at >= 0) styles.removeAt(at);
          } else {
            styles.add(style);
          }
        case 'td' || 'th':
          if (!closing) {
            flushText();
            if (!out.toString().endsWith('\n') && out.isNotEmpty) {
              out.write(' ');
            }
          }
        case 'img':
          final src = RegExp(
            r'''src\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
            caseSensitive: false,
          ).firstMatch(t);
          final name = src == null
              ? null
              : _decodeEntities(src[1] ?? src[2] ?? src[3] ?? '');
          if (name == null || name.isEmpty) break;
          final decoded = _decodeUri(name);
          final id =
              resolveMedia(decoded) ??
              (decoded != name ? resolveMedia(name) : null);
          flushText();
          out.write(
            id == null ? escapeMarkji('[图片 $decoded]') : '\n[Pic#ID/$id#]\n',
          );
      }
    }
    flushText();
    return out
        .toString()
        .split('\n')
        .map((line) => line.trimRight())
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _styled(String text, Set<String> styles) {
    final result = StringBuffer();
    final params = [
      for (final s in ['B', 'I', 'U'])
        if (styles.contains(s)) s,
    ];
    var last = 0;
    void plain(String value) {
      if (value.isEmpty) return;
      final escaped = escapeAnswerLines(_math(value));
      // 公式不能嵌在文字样式里，含公式的片段不加样式。
      result.write(
        params.isEmpty || value.trim().isEmpty || escaped.contains('[E##')
            ? escaped
            : '[T#${params.join(',')}#$escaped]',
      );
    }

    for (final m in RegExp(
      '\u0001(\\d+)\u0002([\\s\\S]*?)\u0003',
    ).allMatches(text)) {
      plain(text.substring(last, m.start));
      result.write('[F#${m[1]}#${escapeMarkji(m[2]!)}]');
      last = m.end;
    }
    plain(text.substring(last));
    return result.toString().replaceAll(RegExp('[\u0001\u0002\u0003]'), '');
  }

  /// MathJax 的 \(…\) 与 \[…\] 转为独立公式，其余文字转义中括号。
  String _math(String text) {
    final result = StringBuffer();
    var last = 0;
    for (final m in RegExp(
      r'\\\(([\s\S]*?)\\\)|\\\[([\s\S]*?)\\\]',
    ).allMatches(text)) {
      result.write(escapeMarkji(text.substring(last, m.start)));
      final tex = (m[1] ?? m[2]!).trim();
      result.write('\n[E##$tex]\n');
      last = m.end;
    }
    result.write(escapeMarkji(text.substring(last)));
    return result.toString();
  }
}

String _stripHtml(String html) => _decodeEntities(
  html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), ''),
);

String _decodeUri(String value) {
  try {
    return Uri.decodeComponent(value);
  } catch (_) {
    return value;
  }
}

const _entities = {
  'nbsp': ' ',
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'ensp': ' ',
  'emsp': ' ',
  'mdash': '—',
  'ndash': '–',
  'hellip': '…',
  'middot': '·',
  'times': '×',
  'divide': '÷',
};

String _decodeEntities(String text) =>
    text.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
      final key = m[1]!;
      if (key.startsWith('#x') || key.startsWith('#X')) {
        final code = int.tryParse(key.substring(2), radix: 16);
        return code == null ? m[0]! : String.fromCharCode(code);
      }
      if (key.startsWith('#')) {
        final code = int.tryParse(key.substring(1));
        return code == null ? m[0]! : String.fromCharCode(code);
      }
      return _entities[key.toLowerCase()] ?? m[0]!;
    });
