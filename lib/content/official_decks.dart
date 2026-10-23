import 'package:flutter/services.dart';

/// 随应用提供、启动时写入资料库的考试词表。
/// 词条来自 KyleBing/english-vocabulary，许可说明见 assets/vocabulary/SOURCES.md。
class OfficialDeck {
  const OfficialDeck({
    required this.id,
    required this.name,
    required this.asset,
  });

  final String id;
  final String name;
  final String asset;
}

const officialDeckGroup = '官方';
const officialLibraryDeckId = 'official-library';
// 词表内容变更时递增；已导入的安装无需每次启动重新解析整套资源。
const officialLibraryVersion = '1';

/// 六级词表文件只收录相对四级新增的词。牌组展示时并入四级，考试范围才完整。
const officialDeckIncludes = <String, List<String>>{
  'official-cet6': ['official-cet4'],
};

const officialDecks = <OfficialDeck>[
  OfficialDeck(
    id: 'official-cet4',
    name: '大学英语四级',
    asset: 'assets/vocabulary/cet4.txt',
  ),
  OfficialDeck(
    id: 'official-cet6',
    name: '大学英语六级',
    asset: 'assets/vocabulary/cet6.txt',
  ),
  OfficialDeck(
    id: 'official-kaoyan',
    name: '考研英语',
    asset: 'assets/vocabulary/kaoyan.txt',
  ),
  OfficialDeck(
    id: 'official-toefl',
    name: '托福',
    asset: 'assets/vocabulary/toefl.txt',
  ),
];

bool isOfficialContentDeck(String id) =>
    id == officialLibraryDeckId || officialDeckById(id) != null;

OfficialDeck? officialDeckById(String id) {
  for (final deck in officialDecks) {
    if (deck.id == id) return deck;
  }
  return null;
}

typedef OfficialDeckReader = Future<String> Function(String asset);

OfficialDeckReader officialDeckReader = rootBundle.loadString;

List<String> parseOfficialCards(String text) => text
    .split('\n===CARD===\n')
    .map((card) => card.trim())
    .where((card) => card.isNotEmpty)
    .toList();

String officialCardKey(String source) =>
    source.split('\n').first.trim().toLowerCase();

Future<List<String>> loadOfficialCards(OfficialDeck deck) async =>
    parseOfficialCards(await officialDeckReader(deck.asset));

/// 四套词表共用一份词库。单词不区分大小写，只保留第一次出现的释义。
Future<({Map<String, String> cards, Map<String, List<String>> membership})>
loadSharedOfficialLibrary() async {
  final cards = <String, String>{};
  final membership = <String, List<String>>{};
  for (final deck in officialDecks) {
    final keys = <String>[];
    for (final source in await loadOfficialCards(deck)) {
      final key = officialCardKey(source);
      if (key.isEmpty) continue;
      cards.putIfAbsent(key, () => source);
      keys.add(key);
    }
    membership[deck.id] = keys;
  }
  for (final entry in officialDeckIncludes.entries) {
    final keys = {...membership[entry.key]!};
    for (final included in entry.value) {
      keys.addAll(membership[included]!);
    }
    membership[entry.key] = keys.toList();
  }
  return (cards: cards, membership: membership);
}
