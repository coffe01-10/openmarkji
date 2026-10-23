import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'markji.dart';

/// 表格文件读出的单元格；行长短不一时按最长行补空。
class ImportTable {
  ImportTable(List<List<String>> rows)
    : rows = [
        for (final row in rows)
          if (row.any((cell) => cell.trim().isNotEmpty)) row,
      ] {
    final width = this.rows.fold(
      0,
      (w, row) => row.length > w ? row.length : w,
    );
    for (final row in this.rows) {
      while (row.length < width) {
        row.add('');
      }
    }
    columnCount = width;
  }
  final List<List<String>> rows;
  late final int columnCount;

  /// 列标题：首行作表头时取首行文字，否则用 A、B、C…。
  List<String> headers(bool firstRowHeader) => [
    for (var i = 0; i < columnCount; i++)
      firstRowHeader && rows.isNotEmpty && rows.first[i].trim().isNotEmpty
          ? rows.first[i].trim()
          : columnName(i),
  ];
}

String columnName(int index) {
  var name = '';
  for (var n = index + 1; n > 0; n = (n - 1) ~/ 26) {
    name = String.fromCharCode(65 + (n - 1) % 26) + name;
  }
  return name;
}

class TableMapping {
  const TableMapping({
    this.firstRowHeader = true,
    this.question = const [0],
    this.answer = const [1],
    this.tags,
    this.chapter,
  });
  final bool firstRowHeader;
  final List<int> question, answer;
  final int? tags, chapter;
}

/// 按列映射生成卡片。单元格按纯文本处理，多列之间换行连接。
List<ImportEntry> tableEntries(ImportTable table, TableMapping mapping) {
  String join(List<String> row, List<int> columns) => columns
      .where((c) => c < row.length)
      .map((c) => row[c].trim())
      .where((text) => text.isNotEmpty)
      .map(escapeImportText)
      .join('\n');
  final entries = <ImportEntry>[];
  for (final row in table.rows.skip(mapping.firstRowHeader ? 1 : 0)) {
    final question = join(row, mapping.question);
    final answer = join(row, mapping.answer);
    if (question.isEmpty && answer.isEmpty) continue;
    entries.add(
      ImportEntry(
        answer.isEmpty ? question : '$question\n---\n$answer',
        tags: mapping.tags == null || mapping.tags! >= row.length
            ? const []
            : row[mapping.tags!]
                  .split(RegExp(r'[\s,，;；、]+'))
                  .where((tag) => tag.isNotEmpty)
                  .toSet()
                  .toList(),
        chapter: mapping.chapter == null || mapping.chapter! >= row.length
            ? ''
            : row[mapping.chapter!].trim(),
      ),
    );
  }
  return entries;
}

ImportTable readTableFile(String name, Uint8List bytes) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.xlsx')) return ImportTable(parseXlsx(bytes));
  if (lower.endsWith('.xls')) {
    throw const FormatException('不支持旧版 xls，请在 Excel 中另存为 xlsx 或 CSV UTF-8');
  }
  final String text;
  try {
    text = decodeImportBytes(bytes);
  } on FormatException {
    throw const FormatException(
      '文件不是 UTF-8 编码，请在 Excel 中另存为“CSV UTF-8”，或直接选择 xlsx',
    );
  }
  return ImportTable(
    parseDelimited(text, delimiter: lower.endsWith('.tsv') ? '\t' : null),
  );
}

/// RFC 4180 风格解析：引号内可含分隔符、换行和成对引号。未指定分隔符时按首行猜测。
List<List<String>> parseDelimited(String text, {String? delimiter}) {
  final source = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  delimiter ??= _guessDelimiter(source);
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  var started = false;
  for (var i = 0; i < source.length; i++) {
    final ch = source[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < source.length && source[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
      continue;
    }
    if (ch == '"' && cell.isEmpty) {
      quoted = true;
      started = true;
    } else if (ch == delimiter) {
      row.add(cell.toString());
      cell.clear();
      started = true;
    } else if (ch == '\n') {
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
      started = false;
    } else {
      cell.write(ch);
      started = true;
    }
  }
  if (started || cell.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

String _guessDelimiter(String source) {
  final counts = {'\t': 0, ',': 0, ';': 0};
  var quoted = false;
  for (var i = 0; i < source.length; i++) {
    final ch = source[i];
    if (ch == '"') quoted = !quoted;
    if (!quoted && ch == '\n') break;
    if (!quoted && counts.containsKey(ch)) counts[ch] = counts[ch]! + 1;
  }
  final best = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
  return best.value == 0 ? ',' : best.key;
}

/// 读取 xlsx 工作簿的第一张工作表。数字和日期保留存储值，不套用单元格格式。
List<List<String>> parseXlsx(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('不是有效的 xlsx 文件');
  }
  XmlDocument? read(String path) {
    final file = archive.findFile(path);
    return file == null
        ? null
        : XmlDocument.parse(utf8.decode(file.content, allowMalformed: true));
  }

  Iterable<XmlElement> all(XmlNode node, String name) =>
      node.findAllElements(name, namespaceUri: '*');
  final workbook = read('xl/workbook.xml');
  if (workbook == null) throw const FormatException('不是有效的 xlsx 文件');
  var sheetPath = 'xl/worksheets/sheet1.xml';
  final firstSheet = all(workbook, 'sheet').firstOrNull;
  final relId = firstSheet?.attributes
      .where((a) => a.name.local == 'id')
      .firstOrNull
      ?.value;
  final rels = read('xl/_rels/workbook.xml.rels');
  if (relId != null && rels != null) {
    final target = all(rels, 'Relationship')
        .where((r) => r.getAttribute('Id') == relId)
        .firstOrNull
        ?.getAttribute('Target');
    if (target != null) {
      sheetPath = target.startsWith('/')
          ? target.substring(1)
          : 'xl/${target.replaceFirst(RegExp(r'^\./'), '')}';
    }
  }
  final sheet = read(sheetPath);
  if (sheet == null) throw const FormatException('xlsx 中没有找到工作表');
  String text(XmlElement element) => [
    for (final t in all(element, 't'))
      if (!t.ancestors.whereType<XmlElement>().any(
        (a) => a.name.local == 'rPh',
      ))
        t.innerText,
  ].join();
  final shared = [
    for (final si in all(read('xl/sharedStrings.xml') ?? XmlDocument(), 'si'))
      text(si),
  ];
  final rows = <List<String>>[];
  for (final row in all(sheet, 'row')) {
    final values = <String>[];
    for (final cell in row.childElements.where((e) => e.name.local == 'c')) {
      final ref = cell.getAttribute('r');
      if (ref != null) {
        final letters = RegExp(r'^[A-Z]+').stringMatch(ref) ?? '';
        var column = 0;
        for (final code in letters.codeUnits) {
          column = column * 26 + code - 64;
        }
        while (values.length < column - 1) {
          values.add('');
        }
      }
      final type = cell.getAttribute('t');
      final raw = cell.childElements
          .where((e) => e.name.local == 'v')
          .firstOrNull
          ?.innerText;
      values.add(switch (type) {
        's' => shared.elementAtOrNull(int.tryParse(raw ?? '') ?? -1) ?? '',
        'inlineStr' => text(cell),
        'b' => raw == '1' ? 'TRUE' : 'FALSE',
        _ => raw ?? '',
      });
    }
    rows.add(values);
  }
  return rows;
}
