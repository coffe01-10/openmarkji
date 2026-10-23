import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmarkji/content/external_import.dart';
import 'package:openmarkji/content/markji.dart';
import 'package:openmarkji/content/table_import.dart';
import 'package:openmarkji/data/anki_import.dart';
import 'package:openmarkji/data/app_store.dart';
import 'package:openmarkji/data/database.dart';
import 'package:openmarkji/domain/entities.dart';
import 'package:sqlite3/sqlite3.dart';

final _png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  ),
);

/// 按 Anki 2.1 旧版 schema 构造一个 .apkg：基础问答、挖空各一条，附一张图片。
Uint8List _buildApkg() {
  final dir = Directory.systemTemp.createTempSync('om_apkg');
  try {
    final path = '${dir.path}/collection.anki2';
    final db = sqlite3.open(path);
    db.execute('CREATE TABLE col (models TEXT, decks TEXT)');
    db.execute(
      'CREATE TABLE notes (id INTEGER PRIMARY KEY, mid INTEGER, flds TEXT, tags TEXT)',
    );
    db.execute(
      'CREATE TABLE cards (id INTEGER PRIMARY KEY, nid INTEGER, did INTEGER, ord INTEGER)',
    );
    final models = {
      '1': {
        'id': 1,
        'type': 0,
        'flds': [
          {'name': 'Front', 'ord': 0},
          {'name': 'Back', 'ord': 1},
        ],
        'tmpls': [
          {
            'ord': 0,
            'qfmt': '{{Front}}',
            'afmt': '{{FrontSide}}<hr id=answer>{{Back}}',
          },
        ],
      },
      '2': {
        'id': 2,
        'type': 1,
        'flds': [
          {'name': 'Text', 'ord': 0},
          {'name': 'Extra', 'ord': 1},
        ],
        'tmpls': [
          {
            'ord': 0,
            'qfmt': '{{cloze:Text}}',
            'afmt': '{{cloze:Text}}<br>{{Extra}}',
          },
        ],
      },
    };
    final decks = {
      '10': {'id': 10, 'name': '生物::细胞'},
      '11': {'id': 11, 'name': '生物::遗传'},
    };
    db.execute('INSERT INTO col VALUES (?,?)', [
      jsonEncode(models),
      jsonEncode(decks),
    ]);
    db.execute('INSERT INTO notes VALUES (?,?,?,?)', [
      100,
      1,
      '<b>线粒体</b>的作用？<br><img src="cell.png">\x1f产生 ATP &amp; 能量 [1]',
      ' 细胞 基础 ',
    ]);
    db.execute('INSERT INTO notes VALUES (?,?,?,?)', [
      200,
      2,
      'DNA 由{{c1::脱氧核苷酸}}组成，呈{{c2::双螺旋::结构}}\x1f\\(A=T\\)',
      '',
    ]);
    db.execute('INSERT INTO cards VALUES (1,100,10,0)');
    db.execute('INSERT INTO cards VALUES (2,200,11,0)');
    db.execute('INSERT INTO cards VALUES (3,200,11,1)');
    db.close();
    final collection = File(path).readAsBytesSync();
    final media = utf8.encode(jsonEncode({'0': 'cell.png'}));
    final archive = Archive()
      ..addFile(ArchiveFile('collection.anki2', collection.length, collection))
      ..addFile(ArchiveFile('media', media.length, media))
      ..addFile(ArchiveFile('0', _png.length, _png));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void main() {
  late AppStore store;
  setUp(() async {
    store = AppStore(
      AppDatabase(NativeDatabase.memory()),
      loadOfficialDecks: false,
    );
    await store.initialize(legacy: {});
    await store.putDeck(DeckData(id: 'd', name: '学习'));
  });
  tearDown(() async {
    store.dispose();
    await store.db.close();
  });

  group('表格导入', () {
    test('CSV 引号内的逗号、换行和转义引号保持为同一单元格', () {
      final rows = parseDelimited('问题,答案\n"a,b","第一行\n第二行"\n"说""好""",x');
      expect(rows, [
        ['问题', '答案'],
        ['a,b', '第一行\n第二行'],
        ['说"好"', 'x'],
      ]);
    });

    test('自动识别制表符与分号分隔', () {
      expect(parseDelimited('a\tb,c\n1\t2'), [
        ['a', 'b,c'],
        ['1', '2'],
      ]);
      expect(parseDelimited('a;b\n1;2').first, ['a', 'b']);
    });

    test('列映射生成问答、标签和章节，文本中的语法字符被转义', () {
      final table = ImportTable([
        ['词', '释义', '例句', '标签', '单元'],
        ['apple', '苹果 [n.]', '', '水果，名词', 'U1'],
        ['', '', '', '', ''],
        ['run', '---', 'I run.', '', ''],
      ]);
      final entries = tableEntries(
        table,
        const TableMapping(question: [0], answer: [1, 2], tags: 3, chapter: 4),
      );
      expect(entries.length, 2);
      expect(entries[0].source, 'apple\n---\n苹果 \\[n.\\]');
      expect(entries[0].tags, ['水果', '名词']);
      expect(entries[0].chapter, 'U1');
      // 单元格里的 --- 不能变成第二条答案线。
      expect(entries[1].source, 'run\n---\n- - -\nI run.');
      expect(
        MarkjiParser()
            .parse(entries[1].source)
            .nodes
            .where((n) => n.kind == 'answer')
            .length,
        1,
      );
    });

    test('读取 xlsx 共享字符串、行内字符串与空列', () {
      String xml(String body) => '<?xml version="1.0"?>$body';
      final files = {
        'xl/workbook.xml': xml(
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="词表" sheetId="1" r:id="rId1"/></sheets></workbook>',
        ),
        'xl/_rels/workbook.xml.rels': xml(
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>',
        ),
        'xl/sharedStrings.xml': xml(
          '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>问题</t></si><si><r><t>答</t></r><r><t>案</t></r></si></sst>',
        ),
        'xl/worksheets/sheet1.xml': xml(
          '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
          '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row>'
          '<row r="2"><c r="A2" t="inlineStr"><is><t>水</t></is></c><c r="C2"><v>42</v></c></row>'
          '</sheetData></worksheet>',
        ),
      };
      final archive = Archive();
      files.forEach((name, text) {
        final bytes = utf8.encode(text);
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      });
      final table = readTableFile(
        '词表.xlsx',
        Uint8List.fromList(ZipEncoder().encode(archive)),
      );
      expect(table.rows, [
        ['问题', '', '答案'],
        ['水', '', '42'],
      ]);
      expect(table.headers(true), ['问题', 'B', '答案']);
    });

    test('旧版 xls 和非 UTF-8 CSV 给出明确提示', () {
      expect(
        () => readTableFile('a.xls', Uint8List(4)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('xlsx'),
          ),
        ),
      );
      expect(
        () => readTableFile(
          'a.csv',
          Uint8List.fromList([0xc4, 0xe3, 0xba, 0xc3]),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('UTF-8'),
          ),
        ),
      );
    });
  });

  group('Anki 导入', () {
    test('模板、HTML、挖空、公式、标签、子牌组和图片都转为卡片语法', () async {
      final result = await readApkg(_buildApkg());
      expect(result.title, '生物');
      expect(result.entries.length, 2, reason: '挖空笔记的多张卡合并为一张');
      final basic = result.entries[0];
      expect(basic.chapter, '细胞');
      expect(basic.tags, ['细胞', '基础']);
      expect(result.media.length, 1);
      final id = result.media.single.id;
      expect(result.media.single.bytes, _png);
      expect(
        basic.source,
        '[T#B#线粒体]的作用？\n\n[Pic#ID/$id#]\n---\n产生 ATP & 能量 \\[1\\]',
      );
      final cloze = result.entries[1];
      expect(cloze.chapter, '遗传');
      expect(cloze.source, contains('[F#1#脱氧核苷酸]'));
      expect(cloze.source, contains('[F#2#双螺旋]'));
      expect(cloze.source, contains('[E##A=T]'));
      for (final e in result.entries) {
        expect(
          MarkjiParser().parse(e.source).issues,
          isEmpty,
          reason: e.source,
        );
      }
    });

    test('导入只进资料库，图片写入媒体库且不带入排期', () async {
      final result = await readApkg(_buildApkg());
      final summary = await store.importEntries(
        'd',
        result.entries,
        media: result.media,
      );
      expect(summary.added, 2);
      final cards = await store.cards(deckId: 'd');
      expect(cards.every((c) => c.plan == 'library' && c.isNew), isTrue);
      expect(await store.media(result.media.single.id), _png);
      expect((await store.deck('d'))!.chapters, ['细胞', '遗传']);
      final again = await store.importEntries(
        'd',
        result.entries,
        media: result.media,
      );
      expect(again.skipped, 2);
    });

    test('损坏的文件给出可读错误', () async {
      await expectLater(
        readApkg(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
      final empty = Uint8List.fromList(
        ZipEncoder().encode(Archive()..addFile(ArchiveFile('x', 1, [0]))),
      );
      await expectLater(readApkg(empty), throwsFormatException);
    });

    test('模板条件段落按字段是否为空显示', () {
      final html = AnkiHtml((_) => null);
      expect(
        html.render('{{Q}}{{#Hint}}（{{Hint}}）{{/Hint}}{{^Hint}}无提示{{/Hint}}', {
          'Q': '问',
          'Hint': '',
        }),
        '问无提示',
      );
      expect(html.render('{{#Hint}}<{{Hint}}>{{/Hint}}', {'Hint': '有'}), '<有>');
    });
  });

  group('牌组分享包', () {
    test('导出再导入保留卡片、章节、标签和图片，不含学习记录', () async {
      final media = await store.addMedia('a.png', _png);
      await store.putDeck(
        DeckData(id: 'd', name: '学习', group: '语言', chapters: ['一']),
      );
      await store.putCard(
        StudyCard(
          id: 'c1',
          deckId: 'd',
          source: '图\n[Pic#ID/$media#]\n---\n答',
          chapter: '一',
          tags: ['图片'],
          plan: 'active',
          state: '{"x":1}',
          dueAt: DateTime(2026, 10, 30),
        ),
      );
      await store.putCard(StudyCard(id: 'c2', deckId: 'd', source: '纯文字'));
      final package = await store.exportDeckPackage('d');
      final archive = ZipDecoder().decodeBytes(package);
      final manifest = utf8.decode(archive.findFile('deck.json')!.content);
      expect(manifest, isNot(contains('dueAt')));
      expect(manifest, isNot(contains('state')));

      final data = decodeDeckPackage(package);
      expect(data.title, '学习');
      expect(data.group, '语言');
      expect(data.media.single.bytes, _png);
      final target = await store.createDeck(data.title, group: data.group);
      await store.importEntries(target.id, data.entries, media: data.media);
      final cards = await store.cards(deckId: target.id);
      expect(cards.length, 2);
      final image = cards.firstWhere((c) => c.chapter == '一');
      expect(image.tags, ['图片']);
      expect(image.plan, 'library');
      expect(image.isNew, isTrue);
      final ids = mediaIdsIn(image.source);
      expect(await store.media(ids.single), _png);
      expect((await store.decks()).last.id, target.id, reason: '新牌组排在最后');
    });

    test('完整备份和其他文件不会被当作分享包', () async {
      final backup = await store.backup();
      expect(
        () => decodeDeckPackage(backup),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('完整备份'),
          ),
        ),
      );
      expect(() => decodeDeckPackage(Uint8List(3)), throwsFormatException);
    });

    test('图片引用按映射替换，其他参数保持不变', () {
      expect(
        remapMediaIds('[Pic#ID/a,W/100#] [Pic#ID/b#]', {'a': 'x'}),
        '[Pic#ID/x,W/100#] [Pic#ID/b#]',
      );
      expect(mediaIdsIn('[Pic#ID/a#][Pic#W/1,ID/b#][Pic#ID/a#]'), ['a', 'b']);
    });
  });
}
