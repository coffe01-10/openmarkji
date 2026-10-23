import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'markji.dart';

/// 外部来源解析结果：建议的牌组信息、待导入卡片及其引用的媒体。
class ExternalImport {
  const ExternalImport({
    required this.title,
    required this.entries,
    this.description = '',
    this.group = '',
    this.media = const [],
    this.warnings = const [],
  });
  final String title, description, group;
  final List<ImportEntry> entries;
  final List<ImportMedia> media;
  final List<String> warnings;
  Map<String, Uint8List> get mediaById => {
    for (final m in media) m.id: m.bytes,
  };
}

/// 按内容生成媒体 ID：重复导入同一文件只保留一份，也不会覆盖本机其他图片。
String mediaKey(Uint8List bytes) =>
    'm${getCrc32(bytes).toRadixString(16).padLeft(8, '0')}_${bytes.length}';

const deckPackageFormat = 'openmarkji-deck';
const deckPackageExtension = 'omdeck';

/// 牌组分享包只含卡片内容与媒体，不含学习记录和排期。
Uint8List encodeDeckPackage({
  required String name,
  String description = '',
  String group = '',
  List<String> chapters = const [],
  required List<ImportEntry> cards,
  required Map<String, ({String name, Uint8List bytes})> media,
}) {
  final archive = Archive();
  final used = <String>{for (final c in cards) ...mediaIdsIn(c.source)};
  final mediaList = [
    for (final id in used)
      if (media[id] != null) {'id': id, 'name': media[id]!.name},
  ];
  final manifest = utf8.encode(
    jsonEncode({
      'format': deckPackageFormat,
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'deck': {
        'name': name,
        'description': description,
        'group': group,
        'chapters': chapters,
      },
      'cards': [
        for (final c in cards)
          {'source': c.source, 'chapter': c.chapter, 'tags': c.tags},
      ],
      'media': mediaList,
    }),
  );
  archive.addFile(ArchiveFile('deck.json', manifest.length, manifest));
  for (final m in mediaList) {
    final bytes = media[m['id']]!.bytes;
    archive.addFile(ArchiveFile('media/${m['id']}', bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

ExternalImport decodeDeckPackage(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('不是有效的牌组分享包');
  }
  final file = archive.findFile('deck.json');
  if (file == null) {
    throw FormatException(
      archive.findFile('openmarkji.json') != null
          ? '这是完整备份，请在设置的资料与备份中恢复'
          : '不是有效的牌组分享包',
    );
  }
  final data = Map<String, dynamic>.from(jsonDecode(utf8.decode(file.content)));
  if (data['format'] != deckPackageFormat) {
    throw const FormatException('不是有效的牌组分享包');
  }
  if (data['version'] != 1) {
    throw const FormatException('分享包版本较新，请先更新应用');
  }
  final deck = Map<String, dynamic>.from(data['deck'] ?? {});
  final warnings = <String>[];
  final ids = <String, String>{};
  final media = <ImportMedia>[];
  for (final raw in data['media'] as List? ?? const []) {
    final m = Map<String, dynamic>.from(raw);
    final entry = archive.findFile('media/${m['id']}');
    if (entry == null) {
      warnings.add('分享包缺少图片 ${m['name']}');
      continue;
    }
    final content = entry.content;
    final key = mediaKey(content);
    ids['${m['id']}'] = key;
    media.add(ImportMedia(key, '${m['name'] ?? key}', content));
  }
  return ExternalImport(
    title: '${deck['name'] ?? '分享的牌组'}',
    description: '${deck['description'] ?? ''}',
    group: '${deck['group'] ?? ''}',
    entries: [
      for (final raw in data['cards'] as List? ?? const [])
        ImportEntry(
          remapMediaIds('${raw['source']}', ids),
          chapter: '${raw['chapter'] ?? ''}',
          tags: List<String>.from(raw['tags'] ?? const []),
        ),
    ],
    media: media,
    warnings: warnings,
  );
}
