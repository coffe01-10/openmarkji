import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmarkji/algorithms/mmx.dart';
import 'package:openmarkji/algorithms/mmx5.dart';
import 'package:openmarkji/algorithms/mmx6.dart';
import 'package:openmarkji/data/app_store.dart';
import 'package:openmarkji/data/database.dart';
import 'package:openmarkji/domain/entities.dart';

void main() {
  late AppStore store;
  final now = DateTime(2026, 10, 22, 9);
  setUp(() async {
    store = AppStore(AppDatabase(NativeDatabase.memory()));
    await store.initialize(legacy: {});
  });
  tearDown(() async {
    store.dispose();
    await store.db.close();
  });

  test('默认算法持久化，示例牌组采用所选版本，已有牌组单独保留设置', () async {
    await store.putDeck(DeckData(id: 'old', name: '旧牌组'));
    await store.setDefaultAlgorithm(5);
    expect((await store.deck('old'))!.algorithm, 6);
    expect(
      Preferences.fromJson(jsonDecode((await store.setting('preferences'))!))
          .defaultAlgorithm,
      5,
    );
    expect(Preferences.fromJson({}).defaultAlgorithm, 6);
    await store.addExamples();
    expect((await store.decks()).last.algorithm, 5);
    expect(
      (await store.cards(deckId: (await store.decks()).last.id))
          .every((c) => c.algorithm == 5),
      isTrue,
    );
  });

  test('统一切换只重置更换版本的参数，保留排期并在下次正式评分重放历史', () async {
    await store.putDeck(
      DeckData(id: 'd', name: '待切换', params: const Mmx6().params),
    );
    await store.putDeck(
      DeckData(
        id: 'same',
        name: '已是 MMX-5',
        algorithm: 5,
        params: const Mmx5().params,
      ),
    );
    await store.putCard(
      StudyCard(
        id: 'c',
        deckId: 'd',
        source: '问题\n---\n答案',
        plan: 'active',
        enrolledAt: now,
      ),
    );
    await store.prepareSession(at: now);
    await store.grade(RecallGrade.know, elapsedMs: 1000, at: now);
    final previous = (await store.card('c'))!.toJson();
    expect(await store.setDefaultAlgorithm(5, applyToExisting: true), 1);
    expect((await store.decks()).map((d) => d.id), ['d', 'same']);
    expect((await store.deck('d'))!.params, isEmpty);
    expect((await store.deck('same'))!.params, const Mmx5().params);
    expect((await store.card('c'))!.toJson(), previous);
    final later = now.add(const Duration(days: 60));
    await store.prepareSession(at: later);
    await store.grade(RecallGrade.know, elapsedMs: 1000, at: later);
    expect((await store.card('c'))!.algorithm, 5);
    expect(MmxState.fromJsonString((await store.card('c'))!.state!).version, 5);
    expect(await store.historyFor('c'), hasLength(2));
  });

  test('计划学习量按自然日平均，排除暂停卡、首次评分和当日重学', () async {
    await store.putDeck(DeckData(id: 'd', name: '学习量'));
    final inside = DateTime(now.year, now.month, now.day - 6);
    final outside = now.subtract(const Duration(days: 20));
    for (final item in [
      ('new', 'active', inside),
      ('old', 'active', outside),
      ('paused', 'paused', inside),
    ]) {
      await store.putCard(
        StudyCard(
          id: item.$1,
          deckId: 'd',
          source: item.$1,
          plan: item.$2,
          firstLearned: item.$3,
        ),
      );
    }
    await store.putCard(
      StudyCard(id: 'waiting', deckId: 'd', source: '未学', plan: 'active'),
    );
    Future<void> log(String id, String cardId, String kind, DateTime when) =>
        store.db.customStatement(
          'INSERT INTO reviews VALUES (?,?,?,?,?,?,?,?)',
          [id, cardId, 'd', when.millisecondsSinceEpoch, 1, kind, 1000, '{}'],
        );
    await log('initial', 'new', 'formal', inside);
    await log('review', 'old', 'formal', now);
    await log('repeat', 'old', 'practice', now);
    await log('paused', 'paused', 'formal', now);
    final load = await store.learningLoad(days: 7, at: now);
    expect(load.planned, 3);
    expect(load.dailyNew, closeTo(1 / 7, .00001));
    expect(load.dailyReview, closeTo(1 / 7, .00001));
    final today = await store.learningLoad(days: 1, at: now);
    expect(today.dailyNew, 0);
    expect(today.dailyReview, 1);
    expect(
      (await store.learningLoad(days: 30, at: now)).dailyNew,
      closeTo(2 / 30, .00001),
    );
  });
}
