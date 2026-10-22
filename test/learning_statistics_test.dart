import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmarkji/data/app_store.dart';
import 'package:openmarkji/data/database.dart';
import 'package:openmarkji/domain/entities.dart';
import 'package:openmarkji/domain/statistics.dart';

void main() {
  late AppStore store;
  final now = DateTime(2026, 10, 22, 12);
  setUp(() async {
    store = AppStore(AppDatabase(NativeDatabase.memory()));
    await store.initialize(legacy: {});
    await store.putDeck(DeckData(id: 'd', name: '统计'));
  });
  tearDown(() async {
    store.dispose();
    await store.db.close();
  });
  Future<void> review(
    String id,
    DateTime at, {
    int grade = 1,
    String kind = 'formal',
    double interval = 1,
    int? scheduled,
  }) =>
      store.db.customStatement('INSERT INTO reviews VALUES (?,?,?,?,?,?,?,?)', [
        id,
        'a',
        'd',
        at.millisecondsSinceEpoch,
        grade,
        kind,
        1000,
        jsonEncode({
          'interval_days': interval,
          'scheduled_interval_days': ?scheduled,
        }),
      ]);

  test('日周月按自然周期合并，重学只计用时，未来不伪造评级', () async {
    await review('initial', now, interval: 0);
    await review('review', now, grade: 3);
    await review('practice', now, grade: 1, kind: 'practice');
    await review('week', DateTime(2026, 10, 19, 10), grade: 2);
    await review('previousWeek', DateTime(2026, 10, 18, 10), grade: 4);
    await review('previousMonth', DateTime(2026, 9, 30, 10));
    for (final period in StatisticsPeriod.values) {
      final stats = await store.learningStatistics(period: period, at: now);
      final bucket = stats.singleWhere(
        (b) => !now.isBefore(b.start) && now.isBefore(b.end),
      );
      expect(bucket.grades, switch (period) {
        StatisticsPeriod.day => [1, 0, 1, 0],
        StatisticsPeriod.week => [1, 1, 1, 0],
        StatisticsPeriod.month => [1, 1, 1, 1],
      });
      expect(bucket.newCards, 1);
      expect(bucket.reviewCards, switch (period) {
        StatisticsPeriod.day => 1,
        StatisticsPeriod.week => 2,
        StatisticsPeriod.month => 3,
      });
      expect(bucket.elapsedMs, switch (period) {
        StatisticsPeriod.day => 3000,
        StatisticsPeriod.week => 4000,
        StatisticsPeriod.month => 5000,
      });
      expect(stats.last.grades, [0, 0, 0, 0]);
    }
    expect(
      StatisticsPeriod.month.start(DateTime(2026, 1, 15), -1),
      DateTime(2025, 12),
    );
    expect(
      StatisticsPeriod.week.start(DateTime(2026, 10, 18)),
      DateTime(2026, 10, 12),
    );
  });

  test('持久度使用历史排期间隔，不把当前状态倒灌历史，分档累计包含', () async {
    await store.putCard(
      StudyCard(
        id: 'a',
        deckId: 'd',
        source: 'A',
        plan: 'active',
        enrolledAt: DateTime(2026, 10, 18),
        firstLearned: DateTime(2026, 10, 19),
        lastReview: DateTime(2026, 10, 21),
        dueAt: DateTime(2026, 10, 26),
      ),
    );
    await store.putCard(
      StudyCard(
        id: 'b',
        deckId: 'd',
        source: 'B',
        plan: 'paused',
        enrolledAt: DateTime(2026, 10, 22),
        firstLearned: now,
        lastReview: now,
        dueAt: now.add(const Duration(days: 30)),
      ),
    );
    await store.putCard(
      StudyCard(
        id: 'c',
        deckId: 'd',
        source: 'C',
        plan: 'active',
        enrolledAt: now,
      ),
    );
    await review(
      'old',
      DateTime(2026, 10, 19, 10),
      scheduled: 100,
      interval: 0,
    );
    await review('next', DateTime(2026, 10, 21, 10), scheduled: 5);
    final stats = await store.learningStatistics(at: now);
    final old = stats.singleWhere((b) => b.start == DateTime(2026, 10, 19));
    expect(old.enrolled, 1);
    expect(old.durability, [1, 1, 1, 1]);
    final current = stats.singleWhere((b) => b.start == dayStart(now));
    expect(current.enrolled, 3);
    expect(current.durability, [1, 1, 0, 0]);
    expect(stats.first.enrolled, 0);
  });

  test('逾期待学计入今天，未来排期保留日期，暂停不计待学', () async {
    for (final entry in [
      ('late', -3, 'active'),
      ('later', 2, 'active'),
      ('paused', 0, 'paused'),
    ]) {
      await store.putCard(
        StudyCard(
          id: entry.$1,
          deckId: 'd',
          source: entry.$1,
          plan: entry.$3,
          dueAt: now.add(Duration(days: entry.$2)),
        ),
      );
    }
    final stats = await store.learningStatistics(at: now);
    expect(stats.singleWhere((b) => b.start == dayStart(now)).pending, 1);
    expect(
      stats.singleWhere((b) => b.start == DateTime(2026, 10, 24)).pending,
      1,
    );
  });
}
