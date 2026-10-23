import 'dart:math' as math;

import '../algorithms/mmx.dart';
import '../algorithms/mmx5.dart';
import '../algorithms/mmx6.dart';
import '../domain/entities.dart';
import '../domain/statistics.dart';

typedef StatisticsRows = List<Map<String, dynamic>>;
typedef RetentionInput = ({
  DateTime now,
  int days,
  StatisticsRows reviews,
  StatisticsRows cards,
  StatisticsRows decks,
});
typedef LearningInput = ({
  DateTime now,
  StatisticsPeriod period,
  StatisticsRows reviews,
  StatisticsRows cards,
  StatisticsRows decks,
});

MmxAlgorithm algorithmForDeck(DeckData d, int version) => version == 5
    ? (d.params.length == 12 ? Mmx5(d.params) : const Mmx5())
    : (d.params.length == 21 ? Mmx6(d.params) : const Mmx6());

// 只接收查询结果，不捕获 AppStore 或数据库连接，便于交给原生后台 isolate。
Map<String, dynamic> calculateRetention(RetentionInput input) {
  final decks = {
    for (final row in input.decks)
      row['id'] as String: DeckData.fromJson(decodeObject(row['payload'])),
  };
  final now = input.now;
  final days = input.days;
  final dayList = List<int>.generate(days + 1, (i) => i);
  final dates = [
    for (final d in dayList) DateTime(now.year, now.month, now.day - days + d),
  ];
  final counts = List.filled(days + 1, 0);
  final remembered = List.filled(days + 1, 0);
  final indices = {for (var i = 0; i < dates.length; i++) dayKey(dates[i]): i};
  final reviews = input.reviews;
  for (final row in reviews) {
    final log = decodeObject(row['payload']);
    // 首次学习的自评不是隔日回忆观测；当日重学已由 kind 过滤。
    if (((log['interval_days'] as num?) ?? 0) <= 0) continue;
    final date = DateTime.fromMillisecondsSinceEpoch(row['reviewed_at'] as int);
    final i = indices[dayKey(date)]!;
    counts[i]++;
    if (row['grade'] == 1 || row['grade'] == 4) remembered[i]++;
  }
  final actual = <double?>[
    for (final i in dayList)
      counts[i] == 0 ? null : remembered[i] / counts[i] * 100,
  ];

  // 每张卡按自己的状态版本、牌组参数和距上次正式复习的时间预测，
  // 再对概率求平均；不能把平均稳定性代入一个任意指数函数。
  final forecast = List<double>.filled(days + 1, 0);
  final learningCurve = List<double>.filled(days + 1, 0);
  var modeledCards = 0;
  final cardRows = input.cards;
  for (final row in cardRows) {
    final c = StudyCard.fromJson(decodeObject(row['card_payload']));
    if (c.state == null || c.lastReview == null) continue;
    final state = MmxState.fromJsonString(c.state!);
    if (!state.stability.isFinite || state.stability <= 0) continue;
    final deck = decks[row['deck_id']]!;
    final model = algorithmForDeck(deck, state.version);
    final elapsed = math.max(
      0.0,
      now.difference(c.lastReview!).inMilliseconds /
          Duration.millisecondsPerDay,
    );
    for (final d in dayList) {
      forecast[d] += model.forgettingCurve(elapsed + d, state.stability) * 100;
      learningCurve[d] +=
          model.forgettingCurve(d.toDouble(), state.stability) * 100;
    }
    modeledCards++;
  }

  return {
    'actual': actual,
    'counts': counts,
    'dates': dates,
    'forecast': <double?>[
      for (final value in forecast)
        modeledCards == 0 ? null : value / modeledCards,
    ],
    'modeledCards': modeledCards,
    'learningCurve': <double?>[
      for (final value in learningCurve)
        modeledCards == 0 ? null : value / modeledCards,
    ],
    'days': dayList,
  };
}

List<LearningBucket> calculateLearning(LearningInput input) {
  final decks = {
    for (final row in input.decks)
      row['id'] as String: DeckData.fromJson(decodeObject(row['payload'])),
  };
  final now = input.now;
  final period = input.period;
  final past = switch (period) {
    StatisticsPeriod.day => 14,
    StatisticsPeriod.week => 8,
    StatisticsPeriod.month => 5,
  };
  final future = switch (period) {
    StatisticsPeriod.day => 15,
    StatisticsPeriod.week => 8,
    StatisticsPeriod.month => 5,
  };
  final buckets = [
    for (var i = -past; i <= future; i++)
      LearningBucket(period.start(now, i), period.start(now, i + 1)),
  ];
  final reviews = input.reviews;
  final formal = <String, List<Map<String, dynamic>>>{};
  for (final row in reviews) {
    final time = DateTime.fromMillisecondsSinceEpoch(row['reviewed_at'] as int);
    final log = decodeObject(row['payload']);
    if (row['kind'] == 'formal') {
      formal.putIfAbsent(row['card_id'] as String, () => []).add({
        ...log,
        'time': time,
      });
    }
    final bucket = buckets
        .where((b) => !time.isBefore(b.start) && time.isBefore(b.end))
        .firstOrNull;
    if (bucket == null) continue;
    bucket.elapsedMs += row['elapsed_ms'] as int;
    if (row['kind'] != 'formal') continue;
    bucket.grades[(row['grade'] as int) - 1]++;
    if (((log['interval_days'] as num?) ?? 0) == 0) {
      bucket.newCards++;
    } else {
      bucket.reviewCards++;
    }
  }
  final rows = input.cards;
  for (final row in rows) {
    final card = StudyCard.fromJson(decodeObject(row['card_payload']));
    final deck = decks[row['deck_id']]!;
    final history = formal[card.id] ?? [];
    var historyIndex = 0;
    Map<String, dynamic>? log;
    final enrolled = card.enrolledAt ?? card.createdAt;
    for (final b in buckets) {
      if (card.plan == 'active' && card.dueAt != null) {
        final due = card.dueAt!.isBefore(dayStart(now))
            ? dayStart(now)
            : card.dueAt!;
        if (!due.isBefore(b.start) && due.isBefore(b.end)) b.pending++;
      }
      if (b.start.isAfter(now) || !enrolled.isBefore(b.end)) continue;
      b.enrolled++;
      // 当前分组用当前排期；过去分组用该分组结束前的最后一次状态。
      final current = !now.isBefore(b.start) && now.isBefore(b.end);
      while (historyIndex < history.length &&
          (history[historyIndex]['time'] as DateTime).isBefore(b.end)) {
        log = history[historyIndex++];
      }
      double? interval;
      if (current && card.lastReview != null && card.dueAt != null) {
        interval =
            card.dueAt!.difference(card.lastReview!).inMilliseconds /
            Duration.millisecondsPerDay;
      } else if (log != null && log['scheduled_interval_days'] != null) {
        interval = (log['scheduled_interval_days'] as num).toDouble();
      } else {
        final stateJson =
            log?['sr_state_after'] as String? ??
            (card.lastReview != null && card.lastReview!.isBefore(b.end)
                ? card.state
                : null);
        if (stateJson != null) {
          final state = MmxState.fromJsonString(stateJson);
          interval = algorithmForDeck(
            deck,
            state.version,
          ).nextInterval(state.stability).toDouble();
        } else if (card.firstLearned != null &&
            card.firstLearned!.isBefore(b.end)) {
          for (var i = 0; i < 4; i++) {
            b.durability[i] = null;
          }
        }
      }
      if (interval != null) {
        for (var i = 0; i < 4; i++) {
          if (interval >= [10, 30, 60, 90][i] && b.durability[i] != null) {
            b.durability[i] = b.durability[i]! + 1;
          }
        }
      }
    }
  }
  return buckets;
}
