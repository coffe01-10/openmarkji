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
  final now = DateTime(2026, 10, 22, 12);
  setUp(() async {
    store = AppStore(AppDatabase(NativeDatabase.memory()));
    await store.initialize(legacy: {});
    await store.putDeck(DeckData(id: 'd', name: '测试'));
  });
  tearDown(() async {
    store.dispose();
    await store.db.close();
  });

  test('空白历史与未学卡片不产生虚假的零值或默认预测', () async {
    await store.putCard(
      StudyCard(id: 'new', deckId: 'd', source: '新卡', plan: 'active'),
    );
    final stats = await store.retentionStats(at: now);
    expect(stats['actual'], everyElement(isNull));
    expect(stats['forecast'], everyElement(isNull));
    expect(stats['counts'], everyElement(0));
    expect(stats['modeledCards'], 0);
  });

  test('无记录留空，真实忘记保留零值，首次学习和当日重学不混入', () async {
    Future<void> review(
      String id,
      DateTime date,
      int grade, {
      String kind = 'formal',
      double interval = 1,
    }) async {
      await store.db.customStatement(
        'INSERT INTO reviews VALUES (?,?,?,?,?,?,?,?)',
        [
          id,
          'a',
          'd',
          date.millisecondsSinceEpoch,
          grade,
          kind,
          1000,
          jsonEncode({'interval_days': interval}),
        ],
      );
    }

    await review('forgot', DateTime(2026, 10, 20, 10), 3);
    await review('know', now, 1);
    await review('vague', now, 2);
    await review('initial', now, 1, interval: 0);
    await review('relearn', now, 1, kind: 'practice');
    await review('future', now.add(const Duration(hours: 1)), 1);
    final stats = await store.retentionStats(days: 3, at: now);
    expect(stats['actual'], [null, 0.0, null, 50.0]);
    expect(stats['counts'], [0, 1, 0, 2]);
    expect(stats['dates'], [
      for (var d = 19; d <= 22; d++) DateTime(2026, 10, d),
    ]);
  });

  test('预测逐卡使用状态版本、个体稳定性、参数与已流逝时间', () async {
    final params = [...kMmx6DefaultParams]..[20] = .3;
    await store.putDeck(
      DeckData(id: 'd', name: '已切换算法', algorithm: 6, params: params),
    );
    Future<void> card(
      String id,
      int version,
      double stability,
      int elapsed, {
      String plan = 'active',
    }) => store.putCard(
      StudyCard(
        id: id,
        deckId: 'd',
        source: id,
        plan: plan,
        state: MmxState(
          difficulty: 5,
          stability: stability,
          repeatLong: 1,
          version: version,
        ).toJsonString(),
        lastReview: now.subtract(Duration(days: elapsed)),
      ),
    );
    await card('mmx5', 5, 2, 1);
    await card('mmx6', 6, 8, 3);
    await card('library', 6, 100, 0, plan: 'library');
    final stats = await store.retentionStats(days: 14, at: now);
    final values = (stats['forecast'] as List).cast<double>();
    expect(stats['modeledCards'], 2);
    for (var d = 0; d <= 14; d++) {
      final expected =
          (const Mmx5().forgettingCurve(1.0 + d, 2) +
              Mmx6(params).forgettingCurve(3.0 + d, 8)) *
          50;
      expect(values[d], closeTo(expected, 1e-8));
      expect(values[d].isFinite, isTrue);
      if (d > 0) expect(values[d], lessThan(values[d - 1]));
    }
    expect(values.first, lessThan(100));
    final learning = (stats['learningCurve'] as List).cast<double>();
    expect(learning.first, closeTo(100, 1e-8));
    expect(
      learning[1],
      closeTo(
        (const Mmx5().forgettingCurve(1, 2) +
                Mmx6(params).forgettingCurve(1, 8)) *
            50,
        1e-8,
      ),
    );
  });
}
