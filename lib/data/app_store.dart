import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../algorithms/mmx.dart';
import '../content/external_import.dart';
import '../content/markji.dart';
import '../content/official_decks.dart';
import '../domain/entities.dart';
import '../domain/statistics.dart';
import 'connection.dart';
import 'database.dart';
import 'diagnostics.dart';
import 'statistics_compute.dart';

typedef CardSearchHit = ({StudyCard card, List<String> deckNames});

class AppStore extends ChangeNotifier {
  AppStore(this.db, {this.loadOfficialDecks = true});
  final AppDatabase db;
  static const webDavSetting = 'webdavConnection';

  /// 测试可关闭，避免每次建库都读入整套官方词表。
  final bool loadOfficialDecks;
  Preferences preferences = Preferences();
  final _changes = StreamController<void>.broadcast();
  int revision = 0;
  Future<Map<String, dynamic>>? _overviewCache;
  String? _overviewDay;
  final _retentionCache = <(String, int), Future<Map<String, dynamic>>>{};
  final _learningCache =
      <(String, StatisticsPeriod), Future<List<LearningBucket>>>{};
  bool _submitting = false;
  void changed() {
    revision++;
    _overviewCache = null;
    _retentionCache.clear();
    _learningCache.clear();
    _changes.add(null);
    notifyListeners();
  }

  Stream<T> watch<T>(Future<T> Function() query) async* {
    yield await query();
    await for (final _ in _changes.stream) {
      yield await query();
    }
  }

  Future<void> initialize({Map<String, String>? legacy}) async {
    await db.customSelect('SELECT 1').get();
    if (await setting('migrated') == null) {
      final files = legacy ?? await legacyFiles();
      await db.transaction(() async {
        final decks = (jsonDecode(files['decks'] ?? '[]') as List)
            .cast<Map<String, dynamic>>();
        final cards = (jsonDecode(files['cards'] ?? '[]') as List)
            .cast<Map<String, dynamic>>();
        final logs = (jsonDecode(files['logs'] ?? '[]') as List)
            .cast<Map<String, dynamic>>();
        for (final d in decks) {
          await putDeck(DeckData.fromJson(d), announce: false);
        }
        final byCard = <String, List<Map<String, dynamic>>>{};
        for (final log in logs) {
          byCard.putIfAbsent(log['card_id'], () => []).add(log);
        }
        for (final c in cards) {
          final history = byCard[c['id']] ?? [];
          history.sort(
            (a, b) => (a['reviewed_at'] as String).compareTo(b['reviewed_at']),
          );
          final learned = c['sr_state'] != null;
          final front = escapeMarkji(c['front'] ?? '');
          final back = escapeMarkji(c['back'] ?? '');
          final card = StudyCard(
            id: c['id'],
            deckId: c['deck_id'],
            source: '$front\n---\n$back',
            plan: 'active',
            tags: List<String>.from(c['tags'] ?? []),
            state: c['sr_state'],
            dueAt: c['due_at'] == null ? null : DateTime.parse(c['due_at']),
            algorithm: c['algo_version'] ?? 6,
            createdAt: DateTime.parse(c['created_at']),
            enrolledAt: DateTime.parse(c['created_at']),
            firstLearned: !learned
                ? null
                : DateTime.parse(
                    history.isEmpty
                        ? c['created_at']
                        : history.first['reviewed_at'],
                  ),
            lastReview: history.isEmpty
                ? null
                : DateTime.parse(history.last['reviewed_at']),
          );
          await putCard(card, announce: false);
          for (final log in history) {
            final id = newId();
            await db.customStatement(
              'INSERT INTO reviews VALUES (?,?,?,?,?,?,?,?)',
              [
                id,
                card.id,
                card.deckId,
                DateTime.parse(log['reviewed_at']).millisecondsSinceEpoch,
                log['grade'],
                'formal',
                log['elapsed_ms'] ?? 0,
                jsonEncode(log),
              ],
            );
          }
        }
        await setSetting('migrated', '1');
      });
    }
    if (loadOfficialDecks) await _ensureOfficialDecks();
    preferences = Preferences.fromJson(
      decodeObject(await setting('preferences') ?? '{}'),
    );
  }

  Future<String?> setting(String key) async =>
      (await db.rows('SELECT value FROM settings WHERE key=?', [
            key,
          ])).firstOrNull?['value']
          as String?;
  Future<void> setSetting(String key, String value) => db.customStatement(
    'INSERT OR REPLACE INTO settings VALUES (?,?)',
    [key, value],
  );
  Future<void> clearSetting(String key) =>
      db.customStatement('DELETE FROM settings WHERE key=?', [key]);

  /// Preview preferences immediately without reloading study data or writing
  /// every intermediate slider position to disk. Save when interaction ends.
  void updatePreferences(void Function(Preferences) update) {
    update(preferences);
    notifyListeners();
  }

  Future<void> savePreferences() async {
    await setSetting('preferences', jsonEncode(preferences.toJson()));
    changed();
  }

  Future<int> setDefaultAlgorithm(
    int version, {
    bool applyToExisting = false,
  }) async {
    if (version != 5 && version != 6) {
      throw ArgumentError.value(version, 'version', '支持 MMX-5 或 MMX-6');
    }
    var updated = 0;
    await db.transaction(() async {
      await setSetting(
        'preferences',
        jsonEncode({...preferences.toJson(), 'defaultAlgorithm': version}),
      );
      if (applyToExisting) {
        for (final deck in await decks()) {
          if (deck.algorithm == version) continue;
          await db.customStatement('UPDATE decks SET payload=? WHERE id=?', [
            jsonEncode({
              ...deck.toJson(),
              'algorithm': version,
              'params': <double>[],
            }),
            deck.id,
          ]);
          updated++;
        }
      }
    });
    preferences.defaultAlgorithm = version;
    changed();
    return updated;
  }

  Future<({int planned, double dailyNew, double dailyReview})> learningLoad({
    int days = 30,
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day - days + 1,
    ).millisecondsSinceEpoch;
    final end = dayEnd(now).millisecondsSinceEpoch;
    final cards = (await db.rows(
      "SELECT count(*) planned, coalesce(sum(first_learned>=? AND first_learned<?),0) learned FROM cards WHERE plan='active'",
      [start, end],
    )).first;
    final reviews = (await db.rows(
      "SELECT count(*) n FROM reviews r JOIN cards c ON c.id=r.card_id WHERE c.plan='active' AND r.kind='formal' AND r.reviewed_at>=? AND r.reviewed_at<? AND r.reviewed_at>c.first_learned",
      [start, end],
    )).first;
    return (
      planned: cards['planned'] as int,
      dailyNew: (cards['learned'] as int) / days,
      dailyReview: (reviews['n'] as int) / days,
    );
  }

  Future<List<DeckData>> decks() async {
    final rows = await db.rows('SELECT payload FROM decks ORDER BY rowid');
    final indexed = <({int order, DeckData deck})>[];
    for (var i = 0; i < rows.length; i++) {
      final deck = DeckData.fromJson(decodeObject(rows[i]['payload']));
      if (deck.id == officialLibraryDeckId) continue;
      indexed.add((order: i, deck: deck));
    }
    indexed.sort((a, b) {
      final order = a.deck.sortOrder.compareTo(b.deck.sortOrder);
      return order != 0 ? order : a.order.compareTo(b.order);
    });
    return indexed.map((entry) => entry.deck).toList();
  }

  Future<DeckData?> deck(String id) async {
    final r = await db.rows('SELECT payload FROM decks WHERE id=?', [id]);
    return r.isEmpty
        ? null
        : DeckData.fromJson(decodeObject(r.first['payload']));
  }

  Future<void> putDeck(DeckData deck, {bool announce = true}) async {
    await db.customStatement('INSERT OR REPLACE INTO decks VALUES (?,?)', [
      deck.id,
      jsonEncode(deck.toJson()),
    ]);
    if (announce) changed();
  }

  Future<StudyCard?> card(String id) async {
    final r = await db.rows('SELECT payload FROM cards WHERE id=?', [id]);
    return r.isEmpty
        ? null
        : StudyCard.fromJson(decodeObject(r.first['payload']));
  }

  Future<void> putCard(
    StudyCard card, {
    bool announce = true,
    String? plainText,
  }) async {
    await db.customStatement(
      // 保留 rowid，加入计划、评分和编辑都不应把卡片挪到列表末尾。
      'INSERT INTO cards VALUES (?,?,?,?,?,?,?,?,?,?,?) '
      'ON CONFLICT(id) DO UPDATE SET '
      'deck_id=excluded.deck_id,source=excluded.source,'
      'search_text=excluded.search_text,chapter=excluded.chapter,'
      'tags=excluded.tags,plan=excluded.plan,due_at=excluded.due_at,'
      'enrolled_at=excluded.enrolled_at,first_learned=excluded.first_learned,'
      'payload=excluded.payload',
      [
        card.id,
        card.deckId,
        card.source,
        plainText ?? MarkjiParser().parse(card.source).plainText,
        card.chapter,
        jsonEncode(card.tags),
        card.plan,
        card.dueAt?.millisecondsSinceEpoch,
        (card.enrolledAt ?? card.createdAt).millisecondsSinceEpoch,
        card.firstLearned?.millisecondsSinceEpoch,
        jsonEncode(card.toJson()),
      ],
    );
    await db.customStatement('INSERT OR IGNORE INTO card_decks VALUES (?,?)', [
      card.id,
      card.deckId,
    ]);
    if (announce) {
      await clearSetting('undo');
      changed();
    }
  }

  Future<List<StudyCard>> cards({
    required String deckId,
    String search = '',
    String? chapter,
    String? plan,
    String? tag,
    String? focus,
    bool randomOrder = false,
    int offset = 0,
    int limit = 60,
  }) async {
    var sql =
        'SELECT cards.payload FROM cards JOIN card_decks ON card_decks.card_id=cards.id WHERE card_decks.deck_id=?';
    final args = <Object>[deckId];
    if (search.isNotEmpty) {
      sql += ' AND (instr(lower(search_text),lower(?))>0 OR instr(lower(tags),lower(?))>0)';
      args.addAll([search, search]);
    }
    if (chapter != null) {
      sql += ' AND chapter=?';
      args.add(chapter);
    }
    if (plan != null) {
      sql += ' AND plan=?';
      args.add(plan);
    }
    if (tag != null) {
      sql += ' AND EXISTS (SELECT 1 FROM json_each(cards.tags) WHERE value=?)';
      args.add(tag);
    }
    if (focus == 'favorite') {
      sql += " AND json_extract(payload,'\$.favorite')=1";
    } else if (focus == 'difficult') {
      // The most recent formal answer defines a difficult card; practice never
      // replaces that evidence or changes its next scheduled review.
      sql += " AND (SELECT grade FROM reviews WHERE card_id=cards.id AND kind='formal' ORDER BY reviewed_at DESC,rowid DESC LIMIT 1) IN (2,3)";
    }
    sql +=
        ' ORDER BY ${randomOrder ? 'random()' : 'cards.rowid'} LIMIT ? OFFSET ?';
    args.addAll([limit, offset]);
    return (await db.rows(
      sql,
      args,
    )).map((r) => StudyCard.fromJson(decodeObject(r['payload']))).toList();
  }

  Future<List<CardSearchHit>> searchCards(
    String search, {
    String? group,
    int limit = 60,
  }) async {
    var sql = r'''
      SELECT cards.payload,
        json_group_array(json_extract(decks.payload, '$.name')) AS deck_names
      FROM cards
      JOIN card_decks ON card_decks.card_id=cards.id
      JOIN decks ON decks.id=card_decks.deck_id
      WHERE (instr(lower(cards.search_text),lower(?))>0
        OR instr(lower(cards.tags),lower(?))>0)
    ''';
    final args = <Object>[search, search];
    if (group != null) {
      sql += r" AND json_extract(decks.payload,'$.group')=?";
      args.add(group);
    }
    sql += ' GROUP BY cards.id ORDER BY cards.rowid LIMIT ?';
    args.add(limit);
    return (await db.rows(sql, args))
        .map(
          (row) => (
            card: StudyCard.fromJson(decodeObject(row['payload'])),
            deckNames: (jsonDecode(row['deck_names'] as String) as List)
                .cast<String>(),
          ),
        )
        .toList();
  }

  Future<void> setFavorite(String id, bool favorite) async {
    await db.transaction(() async {
      final current = await card(id);
      if (current == null) return;
      await db.customStatement('UPDATE cards SET payload=? WHERE id=?', [
        jsonEncode(current.withValues({'favorite': favorite}).toJson()),
        id,
      ]);
    });
    changed();
  }

  Future<PracticeSession?> practiceSession() async {
    final raw = await setting('practiceSession');
    return raw == null ? null : PracticeSession.fromJson(decodeObject(raw));
  }

  Future<PracticeSession> startPractice(
    String deckId, {
    String? focus,
    int limit = 20,
    bool shuffle = true,
  }) async {
    final pool = await cards(
      deckId: deckId,
      focus: focus,
      limit: limit,
      randomOrder: shuffle,
    );
    final ids = pool.take(limit).map((c) => c.id).toList();
    DiagnosticLog.instance.event(
      '专项练习',
      '准备：scope=$focus limit=$limit shuffle=$shuffle matched=${ids.length}',
    );
    if (ids.isEmpty) throw const FormatException('当前范围没有可练习的卡片');
    final session = PracticeSession(
      deckId: deckId,
      queue: ids,
      total: ids.length,
    );
    await setSetting('practiceSession', jsonEncode(session.toJson()));
    changed();
    return session;
  }

  Future<PracticeSession?> preparePractice() => db.transaction(() async {
    final session = await practiceSession();
    if (session == null) return null;
    final queue = <String>[];
    for (final id in session.queue) {
      if (await card(id) != null) queue.add(id);
    }
    final next = PracticeSession.fromJson({
      ...session.toJson(),
      'queue': queue,
      'skipped': session.skipped + session.queue.length - queue.length,
    });
    await setSetting('practiceSession', jsonEncode(next.toJson()));
    return next;
  });

  Future<void> gradePractice(
    RecallGrade grade, {
    int elapsedMs = 0,
    DateTime? at,
  }) async {
    await db.transaction(() async {
      final session = await practiceSession();
      if (session == null || session.queue.isEmpty) return;
      final id = session.queue.first;
      final recalled =
          grade == RecallGrade.know || grade == RecallGrade.familiar;
      final first = !session.answered.contains(id);
      final queue = [...session.queue]..removeAt(0);
      if (!recalled) {
        queue.insert(math.min(preferences.relearnGap, queue.length), id);
      }
      final next = PracticeSession.fromJson({
        ...session.toJson(),
        'queue': queue,
        'completed': session.completed + (recalled ? 1 : 0),
        'attempts': session.attempts + 1,
        'firstRecalled': session.firstRecalled + (first && recalled ? 1 : 0),
        'answered': {...session.answered, id}.toList(),
        'mistakes': {...session.mistakes, if (!recalled) id}.toList(),
      });
      await setSetting('practiceSession', jsonEncode(next.toJson()));
      await db.customStatement(
        'INSERT INTO practice_activity(id,studied_at,elapsed_ms) VALUES (?,?,?)',
        [newId(), (at ?? DateTime.now()).millisecondsSinceEpoch, elapsedMs],
      );
    });
    changed();
  }

  Future<List<String>> tags(String deckId) async => (await db.rows(
    'SELECT DISTINCT value FROM cards JOIN card_decks ON card_decks.card_id=cards.id, json_each(cards.tags) WHERE card_decks.deck_id=? ORDER BY value',
    [deckId],
  )).map((r) => r['value'] as String).toList();
  Future<Map<String, int>> counts(String deckId) async {
    final r = (await db.rows(
      "SELECT count(*) total, sum(plan='active') active, sum(plan='library') library, sum(plan='paused') paused FROM cards JOIN card_decks ON card_decks.card_id=cards.id WHERE card_decks.deck_id=?",
      [deckId],
    )).first;
    return r.map((k, v) => MapEntry(k, (v as num? ?? 0).toInt()));
  }

  Future<void> bulkUpdate(
    Iterable<String> ids,
    Map<String, dynamic> values,
  ) async {
    DiagnosticLog.instance.event(
      '批量操作',
      '开始：count=${ids.length} fields=${values.keys.join(',')} plan=${values['plan'] ?? '-'}',
    );
    await db.transaction(() async {
      for (final id in ids) {
        final c = await card(id);
        if (c == null) continue;
        final update = {...values};
        if (values['plan'] == 'active' && c.enrolledAt == null) {
          update['enrolledAt'] = DateTime.now().toIso8601String();
        }
        await putCard(c.withValues(update), announce: false);
      }
      // A content/plan change invalidates the single-step undo snapshot.
      await clearSetting('undo');
    });
    changed();
  }

  Future<void> deleteCards(Iterable<String> ids) async {
    final official = <String>{};
    for (final id in ids) {
      final current = await card(id);
      if (current != null && isOfficialContentDeck(current.deckId)) {
        official.add(id);
      }
    }
    if (official.isNotEmpty) throw StateError('官方卡片不能删除');
    await db.transaction(() async {
      for (final id in ids) {
        await db.customStatement('DELETE FROM cards WHERE id=?', [id]);
        await db.customStatement('DELETE FROM card_decks WHERE card_id=?', [
          id,
        ]);
        await db.customStatement('DELETE FROM reviews WHERE card_id=?', [id]);
      }
      await clearSetting('undo');
    });
    changed();
  }

  Future<void> reorderDecks(List<String> ids) async {
    final current = await decks();
    final ranked = <String, int>{};
    var next = 0;
    for (final id in ids) {
      if (current.any((deck) => deck.id == id)) ranked[id] = next++;
    }
    for (final deck in current) {
      ranked.putIfAbsent(deck.id, () => next++);
    }
    await db.transaction(() async {
      for (final deck in current) {
        final order = ranked[deck.id]!;
        if (deck.sortOrder == order) continue;
        await putDeck(
          DeckData.fromJson({...deck.toJson(), 'sortOrder': order}),
          announce: false,
        );
      }
    });
    changed();
  }

  Future<void> deleteDeck(String id) async {
    if (isOfficialContentDeck(id)) {
      throw StateError('官方牌组不能删除');
    }
    await db.transaction(() async {
      await db.customStatement(
        'DELETE FROM reviews WHERE card_id IN (SELECT card_id FROM card_decks WHERE deck_id=? AND card_id NOT IN (SELECT card_id FROM card_decks WHERE deck_id!=?))',
        [id, id],
      );
      await db.customStatement(
        'DELETE FROM cards WHERE id IN (SELECT card_id FROM card_decks WHERE deck_id=? AND card_id NOT IN (SELECT card_id FROM card_decks WHERE deck_id!=?))',
        [id, id],
      );
      await db.customStatement('DELETE FROM card_decks WHERE deck_id=?', [id]);
      await db.customStatement('DELETE FROM decks WHERE id=?', [id]);
      await clearSetting('undo');
    });
    changed();
  }

  Future<({int added, int skipped})> importCards(
    String deckId,
    List<String> sources, {
    String chapter = '',
    bool keepDuplicates = false,
    bool plainSource = false,
    bool announce = true,
  }) => importEntries(
    deckId,
    [for (final source in sources) ImportEntry(source)],
    chapter: chapter,
    keepDuplicates: keepDuplicates,
    plainSource: plainSource,
    announce: announce,
  );

  /// 导入的卡片只进资料库。条目自带章节时优先使用，否则用 [chapter]；
  /// 媒体按内容命名，已存在的同名媒体保持不变。
  Future<({int added, int skipped})> importEntries(
    String deckId,
    List<ImportEntry> entries, {
    String chapter = '',
    bool keepDuplicates = false,
    bool plainSource = false,
    bool announce = true,
    List<ImportMedia> media = const [],
  }) async {
    final d = (await deck(deckId))!;
    final existing = (await db.rows(
      'SELECT source FROM cards WHERE deck_id=?',
      [deckId],
    )).map((r) => r['source'] as String).toSet();
    var added = 0;
    var skipped = 0;
    final chapters = [...d.chapters];
    await db.transaction(() async {
      final used = <String>{};
      for (final entry in entries) {
        final source = entry.source;
        if (!keepDuplicates && existing.contains(source)) {
          skipped++;
          continue;
        }
        final target = entry.chapter.isEmpty ? chapter : entry.chapter;
        await putCard(
          StudyCard(
            id: newId(),
            deckId: deckId,
            source: source,
            chapter: target,
            tags: entry.tags,
            algorithm: d.algorithm,
          ),
          announce: false,
          plainText: plainSource ? source.replaceAll('---', '答案') : null,
        );
        used.addAll(mediaIdsIn(source));
        existing.add(source);
        if (target.isNotEmpty && !chapters.contains(target)) {
          chapters.add(target);
        }
        added++;
      }
      for (final m in media) {
        if (!used.contains(m.id)) continue;
        await db.customStatement('INSERT OR IGNORE INTO media VALUES (?,?,?)', [
          m.id,
          m.name,
          m.bytes,
        ]);
      }
      if (chapters.length != d.chapters.length) {
        await putDeck(
          DeckData.fromJson({...d.toJson(), 'chapters': chapters}),
          announce: false,
        );
      }
    });
    if (announce) changed();
    return (added: added, skipped: skipped);
  }

  /// 新建牌组接收导入内容，排在现有牌组之后。
  Future<DeckData> createDeck(
    String name, {
    String description = '',
    String group = '',
  }) async {
    final placed = await decks();
    final d = DeckData(
      id: newId(),
      name: name,
      description: description,
      group: group,
      newLimit: preferences.defaultLimit,
      algorithm: preferences.defaultAlgorithm,
      sortOrder: placed.isEmpty
          ? 0
          : placed.map((deck) => deck.sortOrder).reduce(math.max) + 1,
    );
    await putDeck(d);
    return d;
  }

  /// 牌组分享包：卡片源码、章节、标签和引用的图片，不含学习记录。
  Future<Uint8List> exportDeckPackage(String deckId) async {
    final d = await deck(deckId);
    if (d == null) throw StateError('牌组不存在');
    final rows = await db.rows(
      'SELECT cards.source, cards.chapter, cards.tags FROM cards JOIN card_decks ON card_decks.card_id=cards.id WHERE card_decks.deck_id=? ORDER BY cards.rowid',
      [deckId],
    );
    final cards = [
      for (final r in rows)
        ImportEntry(
          r['source'] as String,
          chapter: r['chapter'] as String,
          tags: List<String>.from(jsonDecode(r['tags'] as String)),
        ),
    ];
    final ids = {for (final c in cards) ...mediaIdsIn(c.source)};
    final media = <String, ({String name, Uint8List bytes})>{};
    for (final id in ids) {
      final row = (await db.rows('SELECT name, bytes FROM media WHERE id=?', [
        id,
      ])).firstOrNull;
      if (row != null) {
        media[id] = (name: row['name'] as String, bytes: row['bytes']);
      }
    }
    return encodeDeckPackage(
      name: d.name,
      description: d.description,
      group: isOfficialContentDeck(deckId) ? '' : d.group,
      chapters: d.chapters,
      cards: cards,
      media: media,
    );
  }

  Future<StudySession?> session() async {
    final raw = await setting('session');
    return raw == null ? null : StudySession.fromJson(decodeObject(raw));
  }

  Future<StudySession> prepareSession({
    DateTime? at,
  }) => db.transaction(() async {
    final now = at ?? DateTime.now();
    final today = dayKey(now);
    final old = await session();
    DiagnosticLog.instance.event(
      '学习任务',
      '准备：day=$today previous=${old?.queue.length ?? 0}',
    );
    final queue = <QueueEntry>[];
    final seen = <String>{};
    final active = old == null || old.queue.isEmpty
        ? <String>{}
        : (await db.rows(
            "SELECT id FROM cards WHERE plan='active' AND id IN (SELECT value FROM json_each(?))",
            [jsonEncode(old.queue.map((entry) => entry.cardId).toList())],
          )).map((r) => r['id'] as String).toSet();
    if (old != null) {
      for (final e in old.queue) {
        if (active.contains(e.cardId) &&
            (old.day == today || e.stage == 'relearn') &&
            seen.add(e.cardId)) {
          queue.add(e);
        }
      }
    }
    final due = await db.rows(
      "SELECT id FROM cards WHERE plan='active' AND due_at<? AND NOT EXISTS (SELECT 1 FROM reviews WHERE card_id=cards.id AND kind='formal' AND reviewed_at>=? AND reviewed_at<?) ORDER BY due_at",
      [
        dayEnd(now).millisecondsSinceEpoch,
        dayStart(now).millisecondsSinceEpoch,
        dayEnd(now).millisecondsSinceEpoch,
      ],
    );
    final reviews = <QueueEntry>[];
    for (final r in due) {
      if (seen.add(r['id'])) reviews.add(QueueEntry(r['id'], 'review'));
    }
    // Due reviews precede unstarted new material; existing relearning order is preserved.
    final firstNew = queue.indexWhere((e) => e.stage == 'new');
    queue.insertAll(firstNew < 0 ? 0 : firstNew, reviews);
    final allowedNew = <String>{};
    for (final d in await decks()) {
      final studied =
          (await db.rows(
                'SELECT count(*) n FROM cards WHERE first_learned>=? AND first_learned<? AND EXISTS (SELECT 1 FROM card_decks WHERE card_id=cards.id AND deck_id=?)',
                [
                  dayStart(now).millisecondsSinceEpoch,
                  dayEnd(now).millisecondsSinceEpoch,
                  d.id,
                ],
              )).first['n']
              as int;
      final fresh = await db.rows(
        "SELECT id FROM cards WHERE plan='active' AND first_learned IS NULL AND EXISTS (SELECT 1 FROM card_decks WHERE card_id=cards.id AND deck_id=?) ORDER BY enrolled_at,cards.rowid LIMIT ?",
        [d.id, math.max(0, d.newLimit - studied)],
      );
      allowedNew.addAll(fresh.map((e) => e['id'] as String));
    }
    // 共享卡片只需满足一个牌组的额度，不能被另一个牌组从任务中删掉。
    queue.removeWhere(
      (e) => e.stage == 'new' && !allowedNew.contains(e.cardId),
    );
    for (final id in allowedNew) {
      if (seen.add(id)) queue.add(QueueEntry(id, 'new'));
    }
    final next = StudySession(
      day: today,
      queue: queue,
      completed: old?.day == today ? old!.completed : 0,
      started: old?.day == today ? old!.started : 0,
    );
    await setSetting('session', jsonEncode(next.toJson()));
    DiagnosticLog.instance.event(
      '学习任务',
      '就绪：new=${queue.where((e) => e.stage == 'new').length} review=${queue.where((e) => e.stage == 'review').length} relearn=${queue.where((e) => e.stage == 'relearn').length} completed=${next.completed}',
    );
    if (old?.day != today) await clearSetting('undo');
    return next;
  });

  MmxAlgorithm algorithm(DeckData d, int version) =>
      algorithmForDeck(d, version);
  Future<void> grade(
    RecallGrade grade, {
    required int elapsedMs,
    DateTime? at,
  }) async {
    if (_submitting) return;
    DiagnosticLog.instance.event('学习评分', '${grade.name} elapsedMs=$elapsedMs');
    _submitting = true;
    try {
      final now = at ?? DateTime.now();
      await db.transaction(() async {
        final current = await session();
        if (current == null || current.queue.isEmpty) return;
        final entry = current.queue.first;
        final c = await card(entry.cardId);
        if (c == null || c.plan != 'active') {
          throw StateError('卡片已移出计划，请返回今日刷新任务');
        }
        final d = (await deck(c.deckId))!;
        final logId = newId();
        var updated = c;
        final formal = entry.stage != 'relearn';
        Map<String, dynamic> log = {
          'card_id': c.id,
          'grade': grade.appCode,
          'reviewed_at': now.toIso8601String(),
          'elapsed_ms': elapsedMs,
          'algo_version': d.algorithm,
        };
        if (formal) {
          final history = await historyFor(c.id);
          final interval = c.lastReview == null
              ? 0.0
              : math.max(
                  0.0,
                  now.difference(c.lastReview!).inMilliseconds /
                      Duration.millisecondsPerDay,
                );
          final result = algorithm(d, d.algorithm).schedule(
            responseHistory: [
              ...history.map((e) => e['grade'] as int),
              grade.appCode,
            ],
            intervalHistory: [
              ...history.map((e) => (e['interval_days'] as num).toDouble()),
              interval,
            ],
            srStateJson: c.state,
          );
          if (!result.success ||
              result.state == null ||
              result.nextInterval == null) {
            throw StateError('本次排期未成功，卡片已保留，请检查牌组算法参数');
          }
          updated = c.withValues({
            'state': result.state!.toJsonString(),
            'dueAt': now
                .add(Duration(days: result.nextInterval!))
                .toIso8601String(),
            'lastReview': now.toIso8601String(),
            'firstLearned': (c.firstLearned ?? now).toIso8601String(),
            'algorithm': d.algorithm,
          });
          log = {
            ...log,
            'interval_days': interval,
            'sr_state_after': updated.state,
            'scheduled_interval_days': result.nextInterval,
          };
          await putCard(updated, announce: false);
        }
        await db.customStatement(
          'INSERT INTO reviews VALUES (?,?,?,?,?,?,?,?)',
          [
            logId,
            c.id,
            c.deckId,
            now.millisecondsSinceEpoch,
            grade.appCode,
            formal ? 'formal' : 'practice',
            elapsedMs,
            jsonEncode(log),
          ],
        );
        final queue = [...current.queue]..removeAt(0);
        final needsPractice =
            grade == RecallGrade.forgot || grade == RecallGrade.vague;
        if (needsPractice) {
          queue.insert(
            math.min(preferences.relearnGap, queue.length),
            QueueEntry(c.id, 'relearn'),
          );
        }
        final next = StudySession(
          day: current.day,
          queue: queue,
          completed: current.completed + (needsPractice ? 0 : 1),
          started: current.started + (formal ? 1 : 0),
        );
        await setSetting(
          'undo',
          jsonEncode({
            'card': c.toJson(),
            'session': current.toJson(),
            'logId': logId,
          }),
        );
        await setSetting('session', jsonEncode(next.toJson()));
      });
      changed();
    } finally {
      _submitting = false;
    }
  }

  Future<bool> undo() async {
    final raw = await setting('undo');
    if (raw == null) return false;
    final snapshot = decodeObject(raw);
    await db.transaction(() async {
      final current = await card(snapshot['card']['id']);
      await putCard(
        StudyCard.fromJson({
          ...Map<String, dynamic>.from(snapshot['card']),
          if (current != null) 'favorite': current.favorite,
        }),
        announce: false,
      );
      await db.customStatement('DELETE FROM reviews WHERE id=?', [
        snapshot['logId'],
      ]);
      await setSetting('session', jsonEncode(snapshot['session']));
      await clearSetting('undo');
    });
    changed();
    return true;
  }

  Future<List<Map<String, dynamic>>> historyFor(String cardId) async =>
      (await db.rows(
        "SELECT payload FROM reviews WHERE card_id=? AND kind='formal' ORDER BY reviewed_at,rowid",
        [cardId],
      )).map((r) => decodeObject(r['payload'])).toList();
  Future<Map<String, dynamic>> overview({DateTime? at}) {
    if (at != null) return _readOverview(at);
    final now = DateTime.now();
    if (_overviewCache == null || _overviewDay != dayKey(now)) {
      _overviewDay = dayKey(now);
      _overviewCache = _readOverview(now);
    }
    return _overviewCache!;
  }

  Future<Map<String, dynamic>> _readOverview(DateTime now) async {
    final s = await prepareSession(at: now);
    final row = await studySummary(at: now);
    return {
      ...row,
      'review': s.queue.where((e) => e.stage == 'review').length,
      'new': s.queue.where((e) => e.stage == 'new').length,
      'relearn': s.queue.where((e) => e.stage == 'relearn').length,
      'remaining': s.queue.length,
      'completed': s.completed,
      'totalCards': (await db.rows('SELECT count(*) n FROM cards')).first['n'],
    };
  }

  Future<Map<String, dynamic>> studySummary({DateTime? at}) async {
    final now = at ?? DateTime.now();
    final start = dayStart(now).millisecondsSinceEpoch,
        end = dayEnd(now).millisecondsSinceEpoch;
    final row = (await db.rows(
      "SELECT count(*) attempts, coalesce(sum(kind='formal'),0) formal, coalesce(sum(kind='practice'),0) practice, coalesce(sum(elapsed_ms),0)+(SELECT coalesce(sum(elapsed_ms),0) FROM practice_activity WHERE studied_at>=? AND studied_at<?) elapsed, coalesce(sum(kind='formal' AND grade IN (1,4)),0) recalled FROM reviews WHERE reviewed_at>=? AND reviewed_at<?",
      [start, end, start, end],
    )).first;
    return row;
  }

  Future<List<Map<String, dynamic>>> activity() => db.rows(
    "SELECT strftime('%Y-%m-%d',stamp/1000,'unixepoch','localtime') day, sum(formal) formal, sum(practice) practice, sum(independent) independent, sum(elapsed_ms) elapsed FROM (SELECT reviewed_at stamp,kind='formal' formal,kind='practice' practice,0 independent,elapsed_ms FROM reviews UNION ALL SELECT studied_at,0,0,1,elapsed_ms FROM practice_activity) GROUP BY day ORDER BY day DESC",
  );

  Future<int> totalStudyTime() async =>
      (await db.rows(
            'SELECT (SELECT coalesce(sum(elapsed_ms),0) FROM reviews)+(SELECT coalesce(sum(elapsed_ms),0) FROM practice_activity) elapsed',
          )).single['elapsed']
          as int;
  Future<List<int>> forecast({DateTime? at}) async {
    final now = at ?? DateTime.now();
    final values = <int>[];
    for (var i = 0; i < 15; i++) {
      final start = DateTime(now.year, now.month, now.day + i),
          end = DateTime(now.year, now.month, now.day + i + 1);
      values.add(
        (await db.rows(
              "SELECT count(*) n FROM cards WHERE plan='active' AND due_at>=? AND due_at<?",
              [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
            )).first['n']
            as int,
      );
    }
    return values;
  }

  /// 已读取的统计在数据变更或跨日后重新计算。
  Future<Map<String, dynamic>> retentionStats({int days = 14, DateTime? at}) {
    if (at != null) return _readRetention(days, at);
    final now = DateTime.now();
    return _retentionCache.putIfAbsent((
      dayKey(now),
      days,
    ), () => _readRetention(days, now));
  }

  Future<Map<String, dynamic>> _readRetention(int days, DateTime now) async {
    final start = DateTime(now.year, now.month, now.day - days);
    final reviews = await db.rows(
      "SELECT reviewed_at, grade, payload FROM reviews WHERE kind='formal' AND reviewed_at>=? AND reviewed_at<=?",
      [start.millisecondsSinceEpoch, now.millisecondsSinceEpoch],
    );
    final cards = await db.rows(
      "SELECT c.deck_id, c.payload card_payload FROM cards c JOIN decks d ON d.id=c.deck_id WHERE c.plan='active' AND json_extract(c.payload,'\$.state') IS NOT NULL AND json_extract(c.payload,'\$.lastReview') IS NOT NULL",
    );
    final decks = await db.rows('SELECT id, payload FROM decks');
    final input = (
      now: now,
      days: days,
      reviews: reviews,
      cards: cards,
      decks: decks,
    );
    // 空图只需生成日期和零值，不为它启动后台 isolate。
    return cards.isEmpty && reviews.isEmpty
        ? calculateRetention(input)
        : compute(calculateRetention, input);
  }

  Future<List<LearningBucket>> learningStatistics({
    StatisticsPeriod period = StatisticsPeriod.day,
    DateTime? at,
  }) {
    if (at != null) return _readLearning(period, at);
    final now = DateTime.now();
    return _learningCache.putIfAbsent((
      dayKey(now),
      period,
    ), () => _readLearning(period, now));
  }

  Future<List<LearningBucket>> _readLearning(
    StatisticsPeriod period,
    DateTime now,
  ) async {
    final reviews = await db.rows(
      'SELECT card_id, reviewed_at, grade, kind, elapsed_ms, payload FROM reviews WHERE reviewed_at<=? ORDER BY reviewed_at,rowid',
      [now.millisecondsSinceEpoch],
    );
    final cards = await db.rows(
      "SELECT c.deck_id, c.payload card_payload FROM cards c JOIN decks d ON d.id=c.deck_id WHERE c.plan IN ('active','paused')",
    );
    final decks = await db.rows('SELECT id, payload FROM decks');
    final input = (
      now: now,
      period: period,
      reviews: reviews,
      cards: cards,
      decks: decks,
    );
    return cards.isEmpty && reviews.isEmpty
        ? calculateLearning(input)
        : compute(calculateLearning, input);
  }

  /// 复习评分统计：返回各评级的数量
  Future<Map<String, int>> reviewGradeStats({int days = 30}) async {
    final since = dayStart(DateTime.now().subtract(Duration(days: days)));
    final rows = await db.rows(
      "SELECT grade, count(*) n FROM reviews WHERE kind='formal' AND reviewed_at>=? GROUP BY grade",
      [since.millisecondsSinceEpoch],
    );
    final result = <String, int>{
      'know': 0,
      'vague': 0,
      'forgot': 0,
      'familiar': 0,
    };
    for (final row in rows) {
      final grade = row['grade'] as int;
      final n = row['n'] as int;
      switch (grade) {
        case 1:
          result['know'] = n;
          break;
        case 2:
          result['vague'] = n;
          break;
        case 3:
          result['forgot'] = n;
          break;
        case 4:
          result['familiar'] = n;
          break;
      }
    }
    return result;
  }

  Future<String> addMedia(String name, Uint8List bytes, {String? id}) async {
    final key = id ?? newId();
    await db.customStatement('INSERT OR REPLACE INTO media VALUES (?,?,?)', [
      key,
      name,
      bytes,
    ]);
    changed();
    return key;
  }

  Future<Uint8List?> media(String id) async =>
      (await db.rows('SELECT bytes FROM media WHERE id=?', [
            id,
          ])).firstOrNull?['bytes']
          as Uint8List?;

  Future<Uint8List> backup({bool includeRecovery = false}) async {
    final contents = <String, dynamic>{
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
    };
    await db.transaction(() async {
      for (final table in [
        'decks',
        'cards',
        'reviews',
        'settings',
        'media',
        'practice_activity',
        'card_decks',
      ]) {
        var rows = await db.rows('SELECT * FROM $table');
        if (table == 'settings') {
          rows = rows
              .where(
                (r) =>
                    r['key'] != webDavSetting &&
                    (includeRecovery || r['key'] != 'recoveryBackup'),
              )
              .toList();
        }
        contents[table] = rows
            .map(
              (r) => table == 'media'
                  ? {...r, 'bytes': base64Encode(r['bytes'])}
                  : r,
            )
            .toList();
      }
    });
    final bytes = utf8.encode(jsonEncode(contents));
    return Uint8List.fromList(
      ZipEncoder().encode(
        Archive()..addFile(ArchiveFile('openmarkji.json', bytes.length, bytes)),
      ),
    );
  }

  Future<void> restore(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final file = archive.findFile('openmarkji.json');
    if (file == null) throw const FormatException('不是 OpenMarkji 备份包');
    final data = decodeObject(utf8.decode(file.content));
    if (data['version'] != 1) throw const FormatException('不支持此备份版本');
    for (final key in ['decks', 'cards', 'reviews', 'settings', 'media']) {
      if (data[key] is! List) throw FormatException('备份缺少 $key');
    }
    // Retain the old library inside the database; no external temporary extraction.
    final recovery = await backup();
    final webDav = await setting(webDavSetting);
    await db.transaction(() async {
      for (final table in [
        'decks',
        'cards',
        'reviews',
        'settings',
        'media',
        'practice_activity',
        'card_decks',
      ]) {
        await db.batch((batch) {
          batch.customStatement('DELETE FROM $table');
          for (final raw in data[table] as List? ?? const []) {
            final row = Map<String, dynamic>.from(raw);
            if (table == 'settings' && row['key'] == webDavSetting) continue;
            final columns = switch (table) {
              'decks' => ['id', 'payload'],
              'cards' => [
                'id',
                'deck_id',
                'source',
                'search_text',
                'chapter',
                'tags',
                'plan',
                'due_at',
                'enrolled_at',
                'first_learned',
                'payload',
              ],
              'reviews' => [
                'id',
                'card_id',
                'deck_id',
                'reviewed_at',
                'grade',
                'kind',
                'elapsed_ms',
                'payload',
              ],
              'media' => ['id', 'name', 'bytes'],
              'practice_activity' => ['id', 'studied_at', 'elapsed_ms'],
              'card_decks' => ['card_id', 'deck_id'],
              _ => ['key', 'value'],
            };
            if (table == 'media') row['bytes'] = base64Decode(row['bytes']);
            batch.customStatement(
              'INSERT INTO $table (${columns.join(',')}) VALUES (${List.filled(columns.length, '?').join(',')})',
              columns.map((c) => row[c]).toList(),
            );
          }
        });
      }
      if (data['card_decks'] == null) {
        await db.customStatement(
          'INSERT INTO card_decks SELECT id,deck_id FROM cards',
        );
        await clearSetting('officialLibraryVersion');
      }
      await setSetting('recoveryBackup', base64Encode(recovery));
      if (webDav != null) await setSetting(webDavSetting, webDav);
      await setSetting('migrated', '1');
    });
    preferences = Preferences.fromJson(
      decodeObject(await setting('preferences') ?? '{}'),
    );
    if (data['card_decks'] == null && loadOfficialDecks) {
      await _ensureOfficialDecks();
    }
    changed();
  }

  Future<void> addExamples() async {
    final d = DeckData(
      id: newId(),
      name: '记忆的起点',
      description: '三张示例，认识你的新学习空间',
      group: '示例',
      chapters: ['开始使用'],
      algorithm: preferences.defaultAlgorithm,
    );
    await putDeck(d, announce: false);
    await importCards(d.id, [
      '[P#H1#让知识，真正留下来]\n比起一次反复阅读，更有效的记忆方法是什么？\n---\n[T#B#主动回忆 + 间隔重复]。\n先尝试回忆，再揭晓答案。根据真实感受评分，下一次复习交给算法。',
      '[P#H1#微积分 · 基本定理]\n如果 F 是 f 的一个原函数，定积分如何计算？\n---\n[E##\\int_a^b f(x)\\,dx = F(b)-F(a)]',
      '[P#H1#一个小小的填空]\n记忆不是一次完成的，而是在[F#1#恰当的时间]进行[F#2#主动回忆]。\n---\n点开同一编号的空格会一起揭晓。所有空格共用这张卡的学习进度。',
    ], chapter: '开始使用');
  }

  /// 四套考试牌组共用一份按单词去重的词库，每副牌组仍列出自己的完整词表。
  Future<void> _ensureOfficialDecks() async {
    if (await setting('officialLibraryVersion') == officialLibraryVersion) {
      return;
    }
    var changedDecks = false;
    final oldIds = officialDecks.map((deck) => deck.id).toList();
    final oldCount =
        (await db.rows(
              'SELECT COUNT(*) AS n FROM cards WHERE deck_id IN (?,?,?,?)',
              oldIds,
            )).first['n']
            as int;
    if (oldCount > 0) {
      await db.transaction(() async {
        await db.customStatement(
          'DELETE FROM reviews WHERE card_id IN (SELECT id FROM cards WHERE deck_id IN (?,?,?,?))',
          oldIds,
        );
        await db.customStatement(
          'DELETE FROM card_decks WHERE card_id IN (SELECT id FROM cards WHERE deck_id IN (?,?,?,?))',
          oldIds,
        );
        await db.customStatement(
          'DELETE FROM cards WHERE deck_id IN (?,?,?,?)',
          oldIds,
        );
      });
      changedDecks = true;
    }
    final library = await loadSharedOfficialLibrary();
    final existingCards = await db.rows(
      'SELECT id, source FROM cards WHERE deck_id=?',
      [officialLibraryDeckId],
    );
    final byKey = <String, String>{};
    for (final row in existingCards) {
      byKey[officialCardKey(row['source'] as String)] = row['id'] as String;
    }
    final missing = library.cards.keys.where((key) => !byKey.containsKey(key));
    if (missing.isNotEmpty) {
      final holder = await deck(officialLibraryDeckId);
      if (holder == null) {
        await putDeck(
          DeckData(
            id: officialLibraryDeckId,
            name: '官方词库',
            group: '',
            newLimit: preferences.defaultLimit,
            algorithm: preferences.defaultAlgorithm,
          ),
          announce: false,
        );
      }
      await db.batch((batch) {
        for (final key in missing) {
          final id = 'official_$key';
          final card = StudyCard(
            id: id,
            deckId: officialLibraryDeckId,
            source: library.cards[key]!,
            algorithm: preferences.defaultAlgorithm,
          );
          batch.customStatement(
            'INSERT INTO cards VALUES (?,?,?,?,?,?,?,?,?,?,?)',
            [
              card.id,
              card.deckId,
              card.source,
              card.source.replaceAll('---', '答案'),
              card.chapter,
              jsonEncode(card.tags),
              card.plan,
              null,
              card.createdAt.millisecondsSinceEpoch,
              null,
              jsonEncode(card.toJson()),
            ],
          );
          batch.customStatement(
            'INSERT OR IGNORE INTO card_decks VALUES (?,?)',
            [id, officialLibraryDeckId],
          );
          byKey[key] = id;
        }
      });
      changedDecks = true;
    }
    final placed = await decks();
    var nextOrder = placed.isEmpty
        ? officialDecks.length
        : placed.map((deck) => deck.sortOrder).reduce(math.max) + 1;
    for (var index = 0; index < officialDecks.length; index++) {
      final official = officialDecks[index];
      final existing = await deck(official.id);
      if (existing == null ||
          existing.group != officialDeckGroup ||
          existing.name != official.name ||
          existing.description.isNotEmpty) {
        await putDeck(
          DeckData(
            id: official.id,
            name: official.name,
            group: officialDeckGroup,
            newLimit: existing?.newLimit ?? preferences.defaultLimit,
            algorithm: existing?.algorithm ?? preferences.defaultAlgorithm,
            params: existing?.params ?? const [],
            chapters: existing?.chapters ?? const [],
            sortOrder: existing?.sortOrder ?? nextOrder++,
          ),
          announce: false,
        );
        changedDecks = true;
      }
      final linked = (await db.rows(
        'SELECT card_id FROM card_decks WHERE deck_id=?',
        [official.id],
      )).map((row) => row['card_id'] as String).toSet();
      final wanted = library.membership[official.id]!
          .map((key) => byKey[key]!)
          .toSet();
      final absent = wanted.difference(linked);
      if (absent.isEmpty) continue;
      await db.batch((batch) {
        for (final id in absent) {
          batch.customStatement(
            'INSERT OR IGNORE INTO card_decks VALUES (?,?)',
            [id, official.id],
          );
        }
      });
      changedDecks = true;
    }
    await setSetting('officialLibraryVersion', officialLibraryVersion);
    if (changedDecks) changed();
  }

  @override
  void dispose() {
    _changes.close();
    super.dispose();
  }
}
