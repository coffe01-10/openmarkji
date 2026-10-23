import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmarkji/algorithms/mmx.dart';
import 'package:flutter/services.dart';
import 'package:openmarkji/content/official_decks.dart';
import 'package:openmarkji/data/app_store.dart';
import 'package:openmarkji/data/database.dart';
import 'package:openmarkji/domain/entities.dart';

void main() {
  late AppStore store;
  final now = DateTime(2026, 10, 21, 9);
  setUp(() async {
    store = AppStore(
      AppDatabase(NativeDatabase.memory()),
      loadOfficialDecks: false,
    );
    await store.initialize(legacy: {});
    await store.putDeck(DeckData(id: 'd', name: '学习', newLimit: 2));
  });
  tearDown(() async {
    store.dispose();
    await store.db.close();
  });
  Future<void> add(String id, {String plan = 'active'}) => store.putCard(
    StudyCard(
      id: id,
      deckId: 'd',
      source: '问题$id\n---\n答案',
      plan: plan,
      createdAt: now,
      enrolledAt: now,
    ),
  );

  test('加入计划、编辑和评分保留卡片顺序，分页不跳卡', () async {
    for (final id in ['a', 'b', 'c', 'd']) {
      await add(id, plan: 'library');
    }
    await store.bulkUpdate(['a', 'b'], {'plan': 'active'});
    expect((await store.cards(deckId: 'd', limit: 2)).map((c) => c.id), [
      'a',
      'b',
    ]);
    expect((await store.cards(deckId: 'd', offset: 2)).map((c) => c.id), [
      'c',
      'd',
    ]);
    await store.putCard(
      (await store.card('b'))!.withValues({'source': '编辑后的内容\n---\n答案'}),
    );
    await store.prepareSession(at: now);
    await store.grade(RecallGrade.know, elapsedMs: 1000, at: now);
    expect((await store.cards(deckId: 'd')).map((c) => c.id), [
      'a',
      'b',
      'c',
      'd',
    ]);
    expect((await store.card('b'))!.source, contains('编辑后的内容'));
  });

  test('牌组顺序落库，旧数据保留原顺序，备份恢复和重新初始化不丢失', () async {
    for (final id in ['a', 'b']) {
      await store.putDeck(DeckData.fromJson({'id': id, 'name': id}));
    }
    expect((await store.decks()).map((d) => d.id), ['d', 'a', 'b']);
    await store.reorderDecks(['b', 'd', 'a']);
    final backup = await store.backup();
    await store.reorderDecks(['a', 'b', 'd']);
    await store.restore(backup);
    await store.initialize(legacy: {});
    expect((await store.decks()).map((d) => d.id), ['b', 'd', 'a']);
    expect((await store.decks()).map((d) => d.sortOrder), [0, 1, 2]);
  });

  test('官方牌组和共享卡片拒绝删除，普通牌组仍可删除', () async {
    await add('user-card');
    for (final id in [
      officialLibraryDeckId,
      ...officialDecks.map((d) => d.id),
    ]) {
      await store.putDeck(DeckData(id: id, name: '改过名称', group: '自定义'));
      await expectLater(store.deleteDeck(id), throwsStateError);
      expect(await store.deck(id), isNotNull);
    }
    await store.putCard(
      StudyCard(
        id: 'official-card',
        deckId: officialLibraryDeckId,
        source: '官方内容',
        createdAt: now,
      ),
    );
    await expectLater(
      store.deleteCards(['user-card', 'official-card']),
      throwsStateError,
    );
    expect(await store.card('user-card'), isNotNull);
    expect(await store.card('official-card'), isNotNull);
    await store.putDeck(DeckData(id: 'd', name: '自建牌组', group: '官方'));
    await store.deleteDeck('d');
    expect(await store.deck('d'), isNull);
    expect(await store.card('user-card'), isNull);
    expect(await store.card('official-card'), isNotNull);
  });

  test('外观选项保存后可恢复，旧设置保留默认值', () async {
    store.preferences
      ..liquidGlass = 'standard'
      ..floatingNavigation = false
      ..tabAnimation = 'fade'
      ..pureBlack = true
      ..colorStyle = 'neutral'
      ..textScale = 1.2
      ..fontFamily = 'serif';
    store.preferences
      ..dockOpacity = .3
      ..dockBlur = 24
      ..relearnGap = 5
      ..studyHaptics = false
      ..showStudyProgress = false
      ..showRecallHint = false;
    await store.savePreferences();
    final restored = Preferences.fromJson(
      jsonDecode((await store.setting('preferences'))!) as Map<String, dynamic>,
    );
    expect(restored.liquidGlass, 'standard');
    expect(restored.floatingNavigation, isFalse);
    expect(restored.tabAnimation, 'fade');
    expect(restored.pureBlack, isTrue);
    expect(restored.colorStyle, 'neutral');
    expect(restored.textScale, 1.2);
    expect(restored.fontFamily, 'serif');
    expect(restored.dockOpacity, .3);
    expect(restored.dockBlur, 24);
    expect(restored.relearnGap, 5);
    expect(restored.studyHaptics, isFalse);
    expect(restored.showStudyProgress, isFalse);
    expect(restored.showRecallHint, isFalse);
    final legacy = Preferences.fromJson({'theme': 'dark', 'fontSize': 22});
    expect(legacy.theme, 'dark');
    expect(legacy.fontSize, 22);
    expect(legacy.liquidGlass, 'ultra');
    expect(legacy.relearnGap, 3);
    expect(legacy.dockBlur, 16);
  });

  test('资料库不自动加入计划，重复导入可跳过或保留', () async {
    final one = await store.importCards('d', ['A', 'A', 'B']);
    expect(one.added, 2);
    expect(one.skipped, 1);
    expect((await store.prepareSession(at: now)).queue, isEmpty);
    final two = await store.importCards('d', ['A'], keepDuplicates: true);
    expect(two.added, 1);
  });
  test('当日重学使用设置中的间隔，重进仍保留队列', () async {
    await store.putDeck(DeckData(id: 'd', name: '学习', newLimit: 5));
    for (final id in ['a', 'b', 'c', 'd', 'e']) {
      await add(id);
    }
    store.preferences.relearnGap = 1;
    await store.prepareSession(at: now);
    await store.grade(RecallGrade.forgot, elapsedMs: 1000, at: now);
    final queue = (await store.prepareSession(at: now)).queue;
    expect(queue.map((e) => e.cardId), ['b', 'a', 'c', 'd', 'e']);
    expect(queue[1].stage, 'relearn');
  });

  test('反复进入不突破每日新卡额度', () async {
    await add('a');
    await add('b');
    await add('c');
    expect((await store.prepareSession(at: now)).queue.length, 2);
    await store.grade(RecallGrade.know, elapsedMs: 1000, at: now);
    expect((await store.prepareSession(at: now)).queue.map((e) => e.cardId), [
      'b',
    ]);
    await store.grade(RecallGrade.know, elapsedMs: 1000, at: now);
    expect((await store.prepareSession(at: now)).queue, isEmpty);
    expect(
      (await store.prepareSession(at: now.add(const Duration(days: 1)))).queue
          .any((e) => e.cardId == 'c'),
      isTrue,
    );
  });
  test('重学不改记忆状态，撤销恢复日志、队列和额度', () async {
    await add('a');
    await store.prepareSession(at: now);
    await store.grade(RecallGrade.forgot, elapsedMs: 1200, at: now);
    final scheduled = await store.card('a');
    expect((await store.session())!.queue.single.stage, 'relearn');
    await store.grade(
      RecallGrade.know,
      elapsedMs: 900,
      at: now.add(const Duration(minutes: 3)),
    );
    expect((await store.card('a'))!.state, scheduled!.state);
    expect((await store.card('a'))!.dueAt, scheduled.dueAt);
    expect((await store.historyFor('a')).length, 1);
    expect((await store.session())!.queue, isEmpty);
    expect(await store.undo(), isTrue);
    expect((await store.session())!.queue.single.stage, 'relearn');
    expect(
      (await store.db.rows(
        "SELECT count(*) n FROM reviews WHERE kind='practice'",
      )).first['n'],
      0,
    );
  });
  test('撤销首次评分恢复新卡额度', () async {
    await add('a');
    await store.prepareSession(at: now);
    await store.grade(RecallGrade.know, elapsedMs: 1, at: now);
    await store.undo();
    expect((await store.card('a'))!.firstLearned, isNull);
    expect((await store.card('a'))!.state, isNull);
    expect(await store.historyFor('a'), isEmpty);
    expect((await store.prepareSession(at: now)).queue.single.cardId, 'a');
  });
  test('间隔基于上次正式复习而不是到期日', () async {
    await add('a');
    await store.prepareSession(at: now);
    await store.grade(RecallGrade.know, elapsedMs: 500, at: now);
    final c = (await store.card('a'))!;
    final later = now.add(const Duration(days: 8));
    await store.putCard(
      c.withValues({
        'dueAt': now.add(const Duration(days: 5)).toIso8601String(),
      }),
    );
    await store.prepareSession(at: later);
    await store.grade(RecallGrade.know, elapsedMs: 500, at: later);
    expect((await store.historyFor('a')).last['interval_days'], 8);
  });
  test('复习先于新学，重学插入三张之后', () async {
    await store.putDeck(DeckData(id: 'd', name: '学习', newLimit: 10));
    for (final id in ['a', 'b', 'c', 'd', 'e']) {
      await add(id);
    }
    await store.prepareSession(at: now);
    await store.grade(RecallGrade.forgot, elapsedMs: 1, at: now);
    expect((await store.session())!.queue.map((e) => e.cardId), [
      'b',
      'c',
      'd',
      'a',
      'e',
    ]);
    expect((await store.prepareSession(at: now)).queue.map((e) => e.cardId), [
      'b',
      'c',
      'd',
      'a',
      'e',
    ]);
  });
  test('跨日保留未完成重学，暂停卡不再出队', () async {
    await add('a');
    await store.prepareSession(at: now);
    await store.grade(RecallGrade.forgot, elapsedMs: 1, at: now);
    expect(
      (await store.prepareSession(at: now.add(const Duration(days: 1))))
          .queue
          .single
          .stage,
      'relearn',
    );
    await store.bulkUpdate(['a'], {'plan': 'paused'});
    expect(
      (await store.prepareSession(at: now.add(const Duration(days: 1)))).queue,
      isEmpty,
    );
  });
  test('评分写入失败时整体回滚', () async {
    await add('a');
    await store.prepareSession(at: now);
    await store.db.customStatement(
      "CREATE TRIGGER reject_review BEFORE INSERT ON reviews BEGIN SELECT RAISE(ABORT, 'simulated disk failure'); END",
    );
    await expectLater(
      store.grade(RecallGrade.know, elapsedMs: 1, at: now),
      throwsA(anything),
    );
    expect((await store.card('a'))!.state, isNull);
    expect((await store.session())!.queue.single.cardId, 'a');
  });

  test('首页刷新与评分同时发生，不把已评分卡塞回队列', () async {
    await add('a');
    await store.prepareSession(at: now);
    await store.grade(RecallGrade.know, elapsedMs: 1, at: now);
    final later = now.add(const Duration(days: 10));
    await store.prepareSession(at: later);
    await Future.wait([
      store.prepareSession(at: later),
      store.grade(RecallGrade.know, elapsedMs: 1, at: later),
    ]);
    expect((await store.session())!.queue, isEmpty);
    expect((await store.historyFor('a')).length, 2);
  });

  test('评分后编辑卡片，不允许撤销操作覆盖新内容', () async {
    await add('a');
    await store.prepareSession(at: now);
    await store.grade(RecallGrade.know, elapsedMs: 1, at: now);
    final card = (await store.card('a'))!;
    await store.putCard(card.withValues({'source': '改过的内容'}));
    expect(await store.undo(), isFalse);
    expect((await store.card('a'))!.source, '改过的内容');
  });
  test('备份恢复包含图片、会话与历史，并可找回恢复前资料', () async {
    await add('a');
    await store.addMedia(
      'photo.png',
      Uint8List.fromList([1, 2, 3]),
      id: 'image',
    );
    await store.prepareSession(at: now);
    await store.grade(RecallGrade.forgot, elapsedMs: 1000, at: now);
    await store.putDeck(DeckData(id: 'shared', name: '共享'));
    await store.db.customStatement('INSERT INTO card_decks VALUES (?,?)', [
      'a',
      'shared',
    ]);
    await store.setSetting(AppStore.webDavSetting, 'local-credential');
    final bytes = await store.backup();
    final fresh = AppStore(
      AppDatabase(NativeDatabase.memory()),
      loadOfficialDecks: false,
    );
    await fresh.initialize(legacy: {});
    await fresh.setSetting(AppStore.webDavSetting, 'other-device-credential');
    try {
      await fresh.restore(bytes);
      expect((await fresh.cards(deckId: 'd')).single.id, 'a');
      expect((await fresh.cards(deckId: 'shared')).single.id, 'a');
      expect(
        await fresh.setting(AppStore.webDavSetting),
        'other-device-credential',
      );
      await fresh.clearSetting(AppStore.webDavSetting);
      await fresh.restore(bytes);
      expect(await fresh.setting(AppStore.webDavSetting), isNull);
      final legacy =
          decodeObject(
              utf8.decode(
                ZipDecoder()
                    .decodeBytes(bytes)
                    .findFile('openmarkji.json')!
                    .content,
              ),
            )
            ..remove('card_decks')
            ..remove('practice_activity');
      final legacyJson = utf8.encode(jsonEncode(legacy));
      await fresh.restore(
        Uint8List.fromList(
          ZipEncoder().encode(
            Archive()..addFile(
              ArchiveFile('openmarkji.json', legacyJson.length, legacyJson),
            ),
          ),
        ),
      );
      expect((await fresh.cards(deckId: 'd')).single.id, 'a');
    } finally {
      fresh.dispose();
      await fresh.db.close();
    }
    await add('later');
    await store.restore(bytes);
    expect(await store.card('later'), isNull);
    expect(await store.media('image'), [1, 2, 3]);
    expect((await store.session())!.queue.single.stage, 'relearn');
    expect((await store.historyFor('a')).length, 1);
    final recovery = base64Decode((await store.setting('recoveryBackup'))!);
    await store.restore(recovery);
    expect(await store.card('later'), isNotNull);
  });
  test('官方词库在启动时进入官方分类并保留在资料库', () async {
    officialDeckReader = (asset) async => File(asset).readAsStringSync();
    addTearDown(() => officialDeckReader = rootBundle.loadString);
    store.dispose();
    await store.db.close();
    store = AppStore(AppDatabase(NativeDatabase.memory()));
    await store.initialize(legacy: {});
    final deck = (await store.deck('official-cet4'))!;
    expect(deck.group, '官方');
    expect(deck.description, isEmpty);
    final cet4 = await loadOfficialCards(officialDecks.first);
    final uniqueCet4 = cet4.map(officialCardKey).toSet();
    expect((await store.counts(deck.id))['total'], uniqueCet4.length);
    final cet6Own = (await loadOfficialCards(officialDecks[1]))
        .map(officialCardKey)
        .toSet();
    final cet6Count = (await store.counts('official-cet6'))['total'];
    expect(cet6Count, {...uniqueCet4, ...cet6Own}.length);
    expect(cet6Count, greaterThan(uniqueCet4.length));
    final stored = (await store.cards(deckId: deck.id, limit: 1)).single;
    expect(stored.plan, 'library');
    expect(stored.deckId, officialLibraryDeckId);
    expect(stored.source, contains('\n---\n'));
    final libraryTotal = (await store.db.rows(
      'SELECT COUNT(*) AS n FROM cards WHERE deck_id=?',
      [officialLibraryDeckId],
    )).first['n'];
    expect(libraryTotal, lessThan(7508 + 5651 + 9602 + 13477));
    await store.initialize(legacy: {});
    expect((await store.counts('official-cet6'))['total'], cet6Count);
    expect(
      (await store.db.rows('SELECT COUNT(*) AS n FROM cards WHERE deck_id=?', [
        officialLibraryDeckId,
      ])).first['n'],
      libraryTotal,
    );
    final visible = await store.decks();
    expect(visible.where((d) => d.group == '官方').map((d) => d.id), [
      'official-cet4',
      'official-cet6',
      'official-kaoyan',
      'official-toefl',
    ]);
    expect(visible.any((d) => d.id == officialLibraryDeckId), isFalse);
    final reordered = visible.reversed.map((d) => d.id).toList();
    await store.reorderDecks(reordered);
    await store.initialize(legacy: {});
    expect((await store.decks()).map((d) => d.id), reordered);
  });

  test('旧 JSON 一次性迁移，保持 ID 和评分映射', () async {
    final migrated = AppStore(
      AppDatabase(NativeDatabase.memory()),
      loadOfficialDecks: false,
    );
    await migrated.initialize(
      legacy: {
        'decks': jsonEncode([
          {'id': 'legacy', 'name': '旧牌组'},
        ]),
        'cards': jsonEncode([
          {
            'id': 'old',
            'deck_id': 'legacy',
            'front': '[问题]',
            'back': '答案',
            'created_at': now.toIso8601String(),
            'algo_version': 5,
          },
        ]),
        'logs': '[]',
      },
    );
    final c = (await migrated.card('old'))!;
    expect(c.plan, 'active');
    expect(c.algorithm, 5);
    expect(c.source, '\\[问题\\]\n---\n答案');
    await migrated.initialize(legacy: {});
    expect((await migrated.cards(deckId: 'legacy')).length, 1);
    migrated.dispose();
    await migrated.db.close();
  });
  test('万张导入、分页、正文和标签搜索', () async {
    final watch = Stopwatch()..start();
    await store.importCards(
      'd',
      List.generate(10000, (i) => '概念 $i\n---\n知识点 $i'),
    );
    expect((await store.counts('d'))['total'], 10000);
    expect((await store.cards(deckId: 'd', limit: 60)).length, 60);
    expect((await store.cards(deckId: 'd', search: '概念 9999')).length, 1);
    final c = (await store.cards(deckId: 'd', limit: 1)).single;
    await store.putCard(
      c.withValues({
        'tags': ['数学'],
      }),
    );
    expect((await store.cards(deckId: 'd', tag: '数学')).length, 1);
    await store.putDeck(DeckData(id: 'shared', name: '共享资料', group: '备考'));
    await store.db.customStatement(
      'INSERT INTO card_decks(card_id,deck_id) VALUES (?,?)',
      [c.id, 'shared'],
    );
    final matches = await store.searchCards('数学');
    expect(matches.map((hit) => hit.card.id), [c.id]);
    expect(matches.single.deckNames, containsAll(['学习', '共享资料']));
    expect((await store.searchCards('数学', group: '备考')).single.card.id, c.id);
    expect(await store.searchCards('数学', group: '其他'), isEmpty);
    expect(
      (await store.searchCards('知识点 9999')).single.card.source,
      contains('9999'),
    );
    expect((await store.searchCards('概念', limit: 10)).length, 10);

    expect((await store.prepareSession(at: now)).queue, isEmpty);
    // Report timing, without an environment-dependent performance gate.
    // ignore: avoid_print
    print(
      '10,000 cards import + pagination + search: ${watch.elapsedMilliseconds} ms',
    );
  });
}
