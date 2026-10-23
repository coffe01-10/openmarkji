import 'dart:convert';
import 'dart:typed_data';

class ContentNode {
  const ContentNode(
    this.kind,
    this.text,
    this.offset, {
    this.params = const [],
    this.children = const [],
  });
  final String kind, text;
  final int offset;
  final List<String> params;
  final List<ContentNode> children;
  String? param(String prefix) {
    for (final p in params) {
      if (p.startsWith(prefix)) return p.substring(prefix.length);
    }
    return null;
  }
}

class ContentIssue {
  const ContentIssue(this.offset, this.message);
  final int offset;
  final String message;
}

class ParsedContent {
  const ParsedContent(this.nodes, this.issues);
  final List<ContentNode> nodes;
  final List<ContentIssue> issues;
  String get plainText => nodes.map(_plain).join();
  static String _plain(ContentNode n) => n.kind == 'answer'
      ? '\n答案\n'
      : n.kind == 'Pic'
      ? '[图片]'
      : n.kind == 'P'
      ? '${n.children.map(_plain).join()}\n'
      : n.text;
}

/// Balanced scanning preserves formulas, nested paragraph styles and escaped brackets.
class MarkjiParser {
  ParsedContent parse(String source) {
    final issues = <ContentIssue>[];
    return ParsedContent(
      _scan(source.replaceAll('\r\n', '\n').replaceAll('\r', '\n'), 0, issues),
      issues,
    );
  }

  List<ContentNode> _scan(String source, int base, List<ContentIssue> issues) {
    final nodes = <ContentNode>[];
    var pos = 0;
    var start = 0;
    void flush(int end) {
      if (end <= start) return;
      final raw = source.substring(start, end);
      var previous = 0;
      for (final match in RegExp(r'^---$', multiLine: true).allMatches(raw)) {
        if (match.start > previous) {
          nodes.add(
            ContentNode(
              'text',
              _unescape(raw.substring(previous, match.start)),
              base + start + previous,
            ),
          );
        }
        nodes.add(ContentNode('answer', '', base + start + match.start));
        previous = match.end;
      }
      if (previous < raw.length) {
        nodes.add(
          ContentNode(
            'text',
            _unescape(raw.substring(previous)),
            base + start + previous,
          ),
        );
      }
    }

    while (pos < source.length) {
      if (source[pos] == '\\' &&
          pos + 1 < source.length &&
          '[]'.contains(source[pos + 1])) {
        pos += 2;
        continue;
      }
      if (source[pos] != '[') {
        pos++;
        continue;
      }
      final header = RegExp(r'^\[([A-Za-z]+)#([^\n#]*)#')
          .firstMatch(source.substring(pos));
      if (header == null) {
        pos++;
        continue;
      }
      final contentStart = pos + header.end;
      var end = contentStart;
      var depth = 1;
      while (end < source.length) {
        if (source[end] == '\\' &&
            end + 1 < source.length &&
            '[]'.contains(source[end + 1])) {
          end += 2;
          continue;
        }
        if (source[end] == '[') depth++;
        if (source[end] == ']') {
          depth--;
          if (depth == 0) break;
        }
        end++;
      }
      if (depth != 0) {
        issues.add(ContentIssue(base + pos, '语法缺少结束中括号，已保留原文'));
        pos++;
        continue;
      }
      flush(pos);
      final tag = header[1]!;
      final params = header[2]!.isEmpty ? <String>[] : header[2]!.split(',');
      final raw = source.substring(contentStart, end);
      if (!{'T', 'P', 'F', 'E', 'Pic'}.contains(tag)) {
        issues.add(ContentIssue(base + pos, '$tag 暂不支持交互，已保留源码'));
        nodes.add(
          ContentNode(
            'unsupported',
            source.substring(pos, end + 1),
            base + pos,
          ),
        );
      } else {
        if (tag == 'F' &&
            (params.isEmpty || (int.tryParse(params.first) ?? 0) <= 0)) {
          issues.add(ContentIssue(base + pos, '挖空编号应为正整数'));
        }
        nodes.add(
          ContentNode(
            tag,
            tag == 'E' ? raw : _unescape(raw),
            base + pos,
            params: params,
            children: tag == 'P'
                ? _scan(raw, base + contentStart, issues)
                : const [],
          ),
        );
      }
      pos = end + 1;
      start = pos;
    }
    flush(source.length);
    return nodes;
  }

  String _unescape(String text) =>
      text.replaceAll(r'\[', '[').replaceAll(r'\]', ']');
}

String escapeMarkji(String text) =>
    text.replaceAll('[', r'\[').replaceAll(']', r'\]');

/// 外部纯文本中独占一行的 --- 会被当成答案线，导入时改成普通文字。
String escapeImportText(String text) => escapeAnswerLines(escapeMarkji(text));

String escapeAnswerLines(String text) => text.replaceAllMapped(
  RegExp(r'^(\s*)---(\s*)$', multiLine: true),
  (m) => '${m[1]}- - -${m[2]}',
);

/// 导入得到的一张卡：源码之外还可带标签和章节。
class ImportEntry {
  const ImportEntry(this.source, {this.tags = const [], this.chapter = ''});
  final String source;
  final List<String> tags;
  final String chapter;
}

/// 随导入一起写入媒体库的文件；[id] 即卡片源码中 `[Pic#ID/…#]` 的引用。
class ImportMedia {
  const ImportMedia(this.id, this.name, this.bytes);
  final String id, name;
  final Uint8List bytes;
}

final _picHeader = RegExp(r'\[Pic#([^\n#]*)#');

/// 卡片源码引用的媒体 ID，按出现顺序去重。
List<String> mediaIdsIn(String source) => {
  for (final m in _picHeader.allMatches(source))
    for (final p in m[1]!.split(','))
      if (p.startsWith('ID/') && p.length > 3) p.substring(3),
}.toList();

String remapMediaIds(String source, Map<String, String> ids) => ids.isEmpty
    ? source
    : source.replaceAllMapped(_picHeader, (m) {
        final params = m[1]!.split(',').map((p) {
          if (!p.startsWith('ID/')) return p;
          final next = ids[p.substring(3)];
          return next == null ? p : 'ID/$next';
        });
        return '[Pic#${params.join(',')}#';
      });
String decodeImportBytes(Uint8List bytes) {
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
          (bytes[0] == 0xfe && bytes[1] == 0xff))) {
    if ((bytes.length - 2).isOdd) throw const FormatException('UTF-16 文件不完整');
    final little = bytes[0] == 0xff;
    return String.fromCharCodes([
      for (var i = 2; i < bytes.length; i += 2)
        little ? bytes[i] | bytes[i + 1] << 8 : bytes[i] << 8 | bytes[i + 1],
    ]);
  }
  final offset =
      bytes.length >= 3 &&
          bytes[0] == 0xef &&
          bytes[1] == 0xbb &&
          bytes[2] == 0xbf
      ? 3
      : 0;
  return utf8.decode(bytes.sublist(offset));
}

List<String> splitImport(
  String input, {
  String delimiter = '',
  String answerDelimiter = '',
  bool plain = false,
}) {
  final source = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (delimiter == '---') throw const FormatException('--- 是答案线，请为卡片选择其他分隔行');
  final ranges = <String>[];
  if (delimiter.isEmpty) {
    ranges.add(source);
  } else {
    // Only split a top-level text node: a matching line inside a formula is content.
    final parsed = MarkjiParser().parse(source);
    final cuts = <({int start, int end})>[];
    for (final n in parsed.nodes.where((n) => n.kind == 'text')) {
      // Offsets refer to original source, before unescaping.
      final nextOffset =
          parsed.nodes
              .where((other) => other.offset > n.offset)
              .map((e) => e.offset)
              .firstOrNull ??
          source.length;
      final raw = source.substring(n.offset, nextOffset);
      for (final m in RegExp(
        '^${RegExp.escape(delimiter)}\$',
        multiLine: true,
      ).allMatches(raw)) {
        cuts.add((start: n.offset + m.start, end: n.offset + m.end));
      }
    }
    var start = 0;
    for (final cut in cuts) {
      ranges.add(source.substring(start, cut.start));
      start = cut.end;
    }
    ranges.add(source.substring(start));
  }
  return ranges.where((e) => e.trim().isNotEmpty).map((e) {
    if (!plain) return e.trim();
    if (answerDelimiter.isEmpty) return escapeMarkji(e.trim());
    final at = e.indexOf(answerDelimiter);
    return at < 0
        ? escapeMarkji(e.trim())
        : '${escapeMarkji(e.substring(0, at).trim())}\n---\n${escapeMarkji(e.substring(at + answerDelimiter.length).trim())}';
  }).toList();
}
