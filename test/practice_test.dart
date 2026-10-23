import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmarkji/algorithms/mmx.dart';
import 'package:openmarkji/data/app_store.dart';
import 'package:openmarkji/data/database.dart';
import 'package:openmarkji/domain/entities.dart';

void main() {
  late AppStore store;
  final now = DateTime(2026, 10, 22, 9);
  setUp(() async {
    store = AppStore(
      AppDatabase(NativeDatabase.memory()),
      loadOfficialDecks: false,
    );
    await store.initialize(legacy: {});
    await store.putDeck(DeckData(id: 'd', name: '测试', newLimit: 20));
  });
  tearDown(() async {
    store.dispose();
    await store.db.close();
  });
  Future<void> add(String id, {bool active = true}) => store.putCard(
    StudyCard(
      id: id,
      deckId: 'd',
      source: '问题$id\n---\n答案$id',
      plan: active ? 'active' : 'library',
      enrolledAt: now,
    ),
  );

  test('收藏可筛选，撤销评分和备份恢复均保留收藏', () async {
    await add('a');
    await add('b');
    await store.prepareSession(at: now);
    await store.grade(RecallGrade.know, elapsedMs: 1000, at: now);
    await store.setFavorite('a', true);
    expect(
      (await store.cards(deckId: 'd', focus: 'favorite')).map((c) => c.id),
      ['a'],
    );
    await store.undo();
    expect((await store.card('a'))!.favorite, isTrue);
    expect((await store.card('a'))!.state, isNull);
    final backup = await store.backup();
    await store.setFavorite('a', false);
    await store.restore(backup);
    expect((await store.card('a'))!.favorite, isTrue);
    expect(
      StudyCard.fromJson({'id': 'old', 'deckId': 'd', 'source': '旧卡片'})
          .favorite,
      isFalse,
    );
  });

  test('收藏原位保存，不改变列表顺序或每日选卡顺序', () async {
    await add('a');
    await add('b');
    await store.setFavorite('a', true);
    expect((await store.cards(deckId: 'd')).map((c) => c.id), ['a', 'b']);
    expect((await store.prepareSession(at: now)).queue.map((c) => c.cardId), [
      'a',
      'b',
    ]);
    await store.setFavorite('a', false);
    expect((await store.cards(deckId: 'd')).map((c) => c.id), ['a', 'b']);
  });

  test('难卡取最新正式评分，重学和专项练习不覆盖依据', () async {
    await add('a');
    await store.prepareSession(at: now);
    await store.grade(RecallGrade.forgot, elapsedMs: 1000, at: now);
    await store.grade(RecallGrade.familiar, elapsedMs: 1000, at: now);
    expect(
      (await store.cards(deckId: 'd', focus: 'difficult')).map((c) => c.id),
      ['a'],
    );
    await store.startPractice('d', focus: 'difficult');
    await store.gradePractice(RecallGrade.familiar);
    expect(await store.cards(deckId: 'd', focus: 'difficult'), hasLength(1));
    final later = now.add(const Duration(days: 30));
    await store.prepareSession(at: later);
    await store.grade(RecallGrade.know, elapsedMs: 1000, at: later);
    expect(await store.cards(deckId: 'd', focus: 'difficult'), isEmpty);
  });

  test('专项练习独立续练，忘记重排，保留每日队列和长期状态', () async {
    await add('a');
    await add('b', active: false);
    await store.prepareSession(at: now);
    final daily = await store.setting('session');
    final original = (await store.card('a'))!.toJson();
    final session = await store.startPractice('d', limit: 10, shuffle: false);
    expect(session.queue, ['a', 'b']);
    await store.gradePractice(RecallGrade.forgot, elapsedMs: 1200, at: now);
    expect((await store.preparePractice())!.queue, ['b', 'a']);
    final restored = PracticeSession.fromJson(
      jsonDecode((await store.setting('practiceSession'))!),
    );
    expect(restored.mistakes, ['a']);
    expect(restored.attempts, 1);
    await store.gradePractice(RecallGrade.know, elapsedMs: 800, at: now);
    await store.gradePractice(
      RecallGrade.familiar,
      elapsedMs: 2500,
      at: now.add(const Duration(days: 1)),
    );
    final result = (await store.practiceSession())!;
    expect(result.queue, isEmpty);
    expect(result.completed, 2);
    expect(result.firstRecalled, 1);
    expect(result.attempts, 3);
    expect(await store.setting('session'), daily);
    expect((await store.card('a'))!.toJson(), original);
    expect(await store.historyFor('a'), isEmpty);
    expect(await store.db.rows('SELECT * FROM reviews'), isEmpty);
    final backup = await store.backup();
    await store.clearSetting('practiceSession');
    await store.restore(backup);
    expect((await store.practiceSession())!.completed, 2);
    expect(await store.totalStudyTime(), 4500);
    expect((await store.studySummary(at: now))['elapsed'], 2000);
    expect(
      (await store.studySummary(
        at: now.add(const Duration(days: 1)),
      ))['elapsed'],
      2500,
    );
    expect((await store.activity()).first['independent'], 1);
  });

  test('专项练习跳过已删除卡片，空范围不会覆盖未完成进度', () async {
    await add('a');
    await add('b');
    await store.startPractice('d', shuffle: false);
    final saved = await store.setting('practiceSession');
    await expectLater(
      store.startPractice('d', focus: 'favorite'),
      throwsFormatException,
    );
    expect(await store.setting('practiceSession'), saved);
    await store.deleteCards(['a']);
    final resumed = (await store.preparePractice())!;
    expect(resumed.queue, ['b']);
    expect(resumed.skipped, 1);
    await store.gradePractice(RecallGrade.know);
    expect((await store.preparePractice())!.completed, 1);
    expect((await store.practiceSession())!.queue, isEmpty);
  });
}
