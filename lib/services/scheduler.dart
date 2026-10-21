/// 调度服务：把算法、卡片存储、复习历史串联起来。
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../algorithms/mmx.dart';
import '../algorithms/mmx5.dart';
import '../algorithms/mmx6.dart';
import '../models/models.dart' as m;
import 'storage_stub.dart' if (dart.library.io) 'storage_io.dart' as store;

/// 存储/调度门面 —— 原生端 JSON 文件持久化，Web 内存模式。
class Scheduler {
  Scheduler(String dataDirPath) : _isWeb = false, _dataDirPath = dataDirPath;

  /// Web 内存模式。
  Scheduler.web() : _isWeb = true, _dataDirPath = null;

  final bool _isWeb;
  final String? _dataDirPath;

  String _filePath(String name) => p.join(_dataDirPath!, name);

  List<m.Card> cards = [];
  List<m.Deck> decks = [];
  List<m.ReviewLog> logs = [];

  Future<void> load() async {
    if (_isWeb || _dataDirPath == null) return;
    await store.ensureDir(_dataDirPath);
    cards = await _readList(_filePath('cards.json'), m.Card.fromJson);
    decks = await _readList(_filePath('decks.json'), m.Deck.fromJson);
    logs = await _readList(_filePath('logs.json'), m.ReviewLog.fromJson);
  }

  Future<List<T>> _readList<T>(
    String path,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final raw = await store.readText(path);
    if (raw == null || raw.trim().isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => parse(e as Map<String, dynamic>)).toList();
  }

  Future<void> save() async {
    if (_isWeb || _dataDirPath == null) return;
    const enc = JsonEncoder.withIndent('  ');
    await store.writeText(
      _filePath('cards.json'),
      enc.convert(cards.map((c) => c.toJson()).toList()),
    );
    await store.writeText(
      _filePath('decks.json'),
      enc.convert(decks.map((d) => d.toJson()).toList()),
    );
    await store.writeText(
      _filePath('logs.json'),
      enc.convert(logs.map((l) => l.toJson()).toList()),
    );
  }

  // ---------- 牌组 ----------

  m.Deck createDeck(String name, {int algoVersion = 6}) {
    final deck = m.Deck(id: _newId(), name: name, algoVersion: algoVersion);
    decks.add(deck);
    return deck;
  }

  // ---------- 卡片 ----------

  m.Card createCard({
    required String deckId,
    required String front,
    required String back,
    int? algoVersion,
  }) {
    final deck = decks.firstWhere((d) => d.id == deckId);
    final card = m.Card(
      id: _newId(),
      deckId: deckId,
      front: front,
      back: back,
      algoVersion: algoVersion ?? deck.algoVersion,
    );
    cards.add(card);
    return card;
  }

  /// 今日到期 + 新卡。
  List<m.Card> dueCards(m.Deck deck, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final due =
        cards
            .where(
              (c) =>
                  c.deckId == deck.id &&
                  c.dueAt != null &&
                  !c.dueAt!.isAfter(n),
            )
            .toList()
          ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    final fresh = cards
        .where((c) => c.deckId == deck.id && c.isNew)
        .take(deck.newCardsPerDay)
        .toList();
    return [...due, ...fresh];
  }

  // ---------- 复习 ----------

  MmxAlgorithm _algoFor(m.Card card) {
    final deck = decks.firstWhere(
      (d) => d.id == card.deckId,
      orElse: () => m.Deck(id: '', name: ''),
    );
    if (card.algoVersion == 5) {
      return deck.params.length == 12 ? Mmx5(deck.params) : const Mmx5();
    }
    return deck.params.length == 21 ? Mmx6(deck.params) : const Mmx6();
  }

  ({List<int> resp, List<double> ivl}) _historyFor(m.Card card) {
    final cardLogs = logs
        .where((l) => l.cardId == card.id)
        .toList(growable: false);
    final resp = cardLogs.map((l) => l.grade).toList();
    final ivl = cardLogs.map((l) => l.intervalDays).toList();
    return (resp: resp, ivl: ivl);
  }

  /// 复习一张卡。
  ScheduleResult review(
    m.Card card,
    RecallGrade grade, {
    double elapsedDays = 0,
    int elapsedMs = 0,
    DateTime? now,
  }) {
    now ??= DateTime.now();
    final algo = _algoFor(card);
    final h = _historyFor(card);

    final resp = [...h.resp, grade.appCode];
    final ivl = [...h.ivl, elapsedDays];

    final res = algo.schedule(
      responseHistory: resp,
      intervalHistory: ivl,
      srStateJson: card.srState,
    );
    if (!res.success || res.state == null || res.nextInterval == null) {
      return const ScheduleResult(success: false);
    }

    card.srState = res.state!.toJsonString();
    card.dueAt = now.add(Duration(days: res.nextInterval!));

    logs.add(
      m.ReviewLog(
        cardId: card.id,
        grade: grade.appCode,
        reviewedAt: now,
        intervalDays: elapsedDays,
        srStateAfter: card.srState!,
        algoVersion: card.algoVersion,
        elapsedMs: elapsedMs,
      ),
    );
    return res;
  }

  /// 遗忘曲线采样 —— 对应 JS `card_forgetting_curves()`。
  List<ForgettingCurvePoint> forgettingCurve(
    m.Card card, {
    double totalDaysSinceLastReview = 0,
    double lastScheduledDays = 0,
  }) {
    final algo = _algoFor(card);
    final h = _historyFor(card);
    if (h.resp.isEmpty) return [];

    final states = <MmxState>[];
    for (var i = 0; i < h.resp.length; i++) {
      final r = scoreOf(h.resp[i]);
      states.add(
        i == 0 ? algo.initState(r) : algo.nextState(states[i - 1], r, h.ivl[i]),
      );
    }
    if (states.isEmpty) return [];

    const minPoints = 1000.0;
    var daysSinceFirstLearn = 0.0;
    for (final t in h.ivl) {
      daysSinceFirstLearn += t;
    }
    final maxDays = math.min(
      daysSinceFirstLearn +
          math.max(
            lastScheduledDays * 1.5 - totalDaysSinceLastReview,
            lastScheduledDays * 0.5,
          ),
      365.0,
    );
    final step = math.min(maxDays / minPoints, 1.0);

    final out = <ForgettingCurvePoint>[];
    var lastS = states[0].stability;
    out.add(
      ForgettingCurvePoint(
        date: 0,
        daysSinceFirstLearn: 0,
        elapsedDaysSinceLastReview: 0,
        retrievability: 100,
        stability: lastS,
        reviewTh: 1,
        difficulty: states[0].difficulty,
      ),
    );
    var elapsedAcc = 0.0;
    for (var i = 1; i < h.resp.length; i++) {
      final interval = h.ivl[i];
      var elapsed = 0.0;
      while (elapsed < interval - step) {
        elapsed += step;
        out.add(
          ForgettingCurvePoint(
            date: elapsedAcc + elapsed,
            daysSinceFirstLearn: elapsedAcc + elapsed,
            elapsedDaysSinceLastReview: elapsed,
            retrievability: algo.forgettingCurve(elapsed, lastS) * 100,
            stability: lastS,
            reviewTh: i,
          ),
        );
      }
      elapsedAcc += interval;
      lastS = states[i].stability;
      out.add(
        ForgettingCurvePoint(
          date: elapsedAcc,
          daysSinceFirstLearn: elapsedAcc,
          elapsedDaysSinceLastReview: 0,
          retrievability: 100,
          stability: lastS,
          reviewTh: i,
        ),
      );
    }
    var elapsed = 0.0;
    while (elapsed < totalDaysSinceLastReview - step) {
      elapsed += step;
      out.add(
        ForgettingCurvePoint(
          date: elapsedAcc + elapsed,
          daysSinceFirstLearn: elapsedAcc + elapsed,
          elapsedDaysSinceLastReview: elapsed,
          retrievability: algo.forgettingCurve(elapsed, lastS) * 100,
          stability: lastS,
          reviewTh: h.resp.length,
        ),
      );
    }
    final remaining = math.max(
      maxDays - elapsedAcc - totalDaysSinceLastReview,
      0,
    );
    var preview = 0.0;
    while (preview < remaining) {
      preview += step;
      out.add(
        ForgettingCurvePoint(
          date: elapsedAcc + totalDaysSinceLastReview + preview,
          daysSinceFirstLearn: elapsedAcc + totalDaysSinceLastReview + preview,
          elapsedDaysSinceLastReview: totalDaysSinceLastReview + preview,
          retrievability:
              algo.forgettingCurve(totalDaysSinceLastReview + preview, lastS) *
              100,
          stability: lastS,
          reviewTh: h.resp.length,
        ),
      );
    }
    return out;
  }

  static int _idSeq = 0;
  String _newId() => '${DateTime.now().millisecondsSinceEpoch}_${_idSeq++}';
}
