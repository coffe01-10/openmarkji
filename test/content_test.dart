import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openmarkji/content/markji.dart';

void main() {
  final parser = MarkjiParser();
  test('段落嵌套文字样式和挖空，保留分组', () {
    final result = parser.parse('[P#H1#[T#B#重点]与[F#2#内容]]\n---\n答案');
    expect(result.issues, isEmpty);
    expect(result.nodes.first.children.map((e) => e.kind), ['T', 'text', 'F']);
    expect(result.nodes.first.children.last.params, ['2']);
    expect(result.nodes.where((e) => e.kind == 'answer').length, 1);
    final reference = parser.parse('[P##关联 [Ref#ID/card1#概念说明]]');
    expect(reference.issues, isEmpty);
    expect(reference.nodes.single.children.last.kind, 'Ref');
    expect(reference.nodes.single.children.last.param('ID/'), 'card1');
    expect(reference.plainText, '关联 概念说明\n');
  });
  test('公式换行和方括号不会变成卡片分隔', () {
    const text =
        '[E##\\begin{aligned}\na[2]+b\\\\\n===CARD===\n\\end{aligned}]\n===CARD===\n下一张';
    final result = splitImport(text, delimiter: '===CARD===');
    expect(result.length, 2);
    expect(result.first, contains('===CARD==='));
    expect(parser.parse(result.first).nodes.single.kind, 'E');
  });
  test('空行保留，答案线不能作为卡片分隔', () {
    expect(splitImport('题目\n\n---\n答案').length, 1);
    expect(() => splitImport('题目', delimiter: '---'), throwsFormatException);
  });
  test('转义不丢中括号和原文位置', () {
    final result = parser.parse(r'区间 \[a,b\] [T#B#第 \[3\] 章]');
    expect(result.plainText, '区间 [a,b] 第 [3] 章');
    expect(result.nodes.last.kind, 'T');
  });
  test('未支持语法与不完整语法不吞内容', () {
    const source = '[Audio#ID/test#声音]\n[F#1#少了结尾';
    final result = parser.parse(source);
    expect(result.issues.length, 2);
    expect(result.plainText, contains('[Audio#ID/test#声音]'));
    expect(result.plainText, contains('[F#1#少了结尾'));
  });
  test('支持 UTF-8 BOM 与 UTF-16 双字节编码', () {
    expect(
      decodeImportBytes(
        Uint8List.fromList([239, 187, 191, ...utf8.encode('知识')]),
      ),
      '知识',
    );
    final units = '知识'.codeUnits;
    expect(
      decodeImportBytes(
        Uint8List.fromList([
          255,
          254,
          for (final unit in units) ...[unit & 255, unit >> 8],
        ]),
      ),
      '知识',
    );
    expect(
      decodeImportBytes(
        Uint8List.fromList([
          254,
          255,
          for (final unit in units) ...[unit >> 8, unit & 255],
        ]),
      ),
      '知识',
    );
  });
  test('纯文本分题答并转义语法', () {
    final result = splitImport(
      '[问题]答案：[答案]',
      plain: true,
      answerDelimiter: '答案：',
    );
    expect(result.single, '\\[问题\\]\n---\n\\[答案\\]');
  });

  test('写卡悬浮预览识别光标处的公式与图片', () {
    const src = r'前文 [E##x^2] 中间 [Pic#ID/m1#] [T#B#粗]';
    final formula = inlineTokenAt(src, src.indexOf('x^2') + 1)!;
    expect((formula.tag, formula.body, formula.closed), ('E', 'x^2', true));
    // 刚输入完结束中括号时光标紧跟其后，仍显示预览。
    expect(inlineTokenAt(src, src.indexOf(']') + 1)?.tag, 'E');
    expect(inlineTokenAt(src, src.indexOf(']') + 2), isNull);
    expect(inlineTokenAt(src, src.indexOf('m1'))?.params, ['ID/m1']);
    expect(inlineTokenAt(src, src.indexOf('粗')), isNull);
    expect(inlineTokenAt(src, 0), isNull);
    // 未闭合的公式按到行尾的内容实时预览。
    const open = '[E##\\frac{a}{b}\n下一行';
    final typing = inlineTokenAt(open, 8)!;
    expect((typing.body, typing.closed), (r'\frac{a}{b}', false));
    expect(inlineTokenAt(open, open.length), isNull);
    // 嵌套中括号与转义的语法头。
    expect(inlineTokenAt(r'[E##\sqrt[3]{x}]', 6)?.body, r'\sqrt[3]{x}');
    expect(inlineTokenAt(r'\[E##x]', 5), isNull);
  });
}
