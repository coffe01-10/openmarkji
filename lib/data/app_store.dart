import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../algorithms/mmx.dart';
import '../algorithms/mmx5.dart';
import '../algorithms/mmx6.dart';
import '../content/markji.dart';
import '../domain/entities.dart';
import 'connection.dart';
import 'database.dart';

class AppStore extends ChangeNotifier {
  AppStore(this.db);
  final AppDatabase db;
  Preferences preferences = Preferences();
  final _changes = StreamController<void>.broadcast();
  int revision = 0;
  bool _submitting = false;
  void changed() {
    revision++;
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
  Future<void> savePreferences() async {
    await setSetting('preferences', jsonEncode(preferences.toJson()));
    changed();
  }

  Future<List<DeckData>> decks() async =>
      (await db.rows('SELECT payload FROM decks ORDER BY rowid'))
          .map((r) => DeckData.fromJson(decodeObject(r['payload'])))
          .toList();
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

  Future<void> putCard(StudyCard card, {bool announce = true}) async {
    await db.customStatement(
      'INSERT OR REPLACE INTO cards VALUES (?,?,?,?,?,?,?,?,?,?,?)',
      [
        card.id,
        card.deckId,
        card.source,
        MarkjiParser().parse(card.source).plainText,
        card.chapter,
        jsonEncode(card.tags),
        card.plan,
        card.dueAt?.millisecondsSinceEpoch,
        (card.enrolledAt ?? card.createdAt).millisecondsSinceEpoch,
        card.firstLearned?.millisecondsSinceEpoch,
        jsonEncode(card.toJson()),
      ],
    );
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
    var sql = 'SELECT payload FROM cards WHERE deck_id=?';
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
    sql += ' ORDER BY ${randomOrder ? 'random()' : 'rowid'} LIMIT ? OFFSET ?';
    args.addAll([limit, offset]);
    return (await db.rows(
      sql,
      args,
    )).map((r) => StudyCard.fromJson(decodeObject(r['payload']))).toList();
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

  Future<void> gradePractice(RecallGrade grade) async {
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
    });
    changed();
  }

  Future<List<String>> tags(String deckId) async => (await db.rows(
    'SELECT DISTINCT value FROM cards,json_each(cards.tags) WHERE deck_id=? ORDER BY value',
    [deckId],
  )).map((r) => r['value'] as String).toList();
  Future<Map<String, int>> counts(String deckId) async {
    final r = (await db.rows(
      "SELECT count(*) total, sum(plan='active') active, sum(plan='library') library, sum(plan='paused') paused FROM cards WHERE deck_id=?",
      [deckId],
    )).first;
    return r.map((k, v) => MapEntry(k, (v as num? ?? 0).toInt()));
  }

  Future<void> bulkUpdate(
    Iterable<String> ids,
    Map<String, dynamic> values,
  ) async {
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
    await db.transaction(() async {
      for (final id in ids) {
        await db.customStatement('DELETE FROM cards WHERE id=?', [id]);
        await db.customStatement('DELETE FROM reviews WHERE card_id=?', [id]);
      }
      await clearSetting('undo');
    });
    changed();
  }

  Future<void> deleteDeck(String id) async {
    await db.transaction(() async {
      await db.customStatement(
        'DELETE FROM reviews WHERE card_id IN (SELECT id FROM cards WHERE deck_id=?)',
        [id],
      );
      await db.customStatement('DELETE FROM cards WHERE deck_id=?', [id]);
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
  }) async {
    final d = (await deck(deckId))!;
    final existing = (await db.rows(
      'SELECT source FROM cards WHERE deck_id=?',
      [deckId],
    )).map((r) => r['source'] as String).toSet();
    var added = 0;
    var skipped = 0;
    await db.transaction(() async {
      for (final source in sources) {
        if (!keepDuplicates && existing.contains(source)) {
          skipped++;
          continue;
        }
        await putCard(
          StudyCard(
            id: newId(),
            deckId: deckId,
            source: source,
            chapter: chapter,
            algorithm: d.algorithm,
          ),
          announce: false,
        );
        existing.add(source);
        added++;
      }
      if (chapter.isNotEmpty && !d.chapters.contains(chapter)) {
        await putDeck(
          DeckData.fromJson({
            ...d.toJson(),
            'chapters': [...d.chapters, chapter],
          }),
          announce: false,
        );
      }
    });
    changed();
    return (added: added, skipped: skipped);
  }

  Future<StudySession?> session() async {
    final raw = await setting('session');
    return raw == null ? null : StudySession.fromJson(decodeObject(raw));
  }

  Future<StudySession> prepareSession({DateTime? at}) => db.transaction(
    () async {
      final now = at ?? DateTime.now();
      final today = dayKey(now);
      final old = await session();
      final queue = <QueueEntry>[];
      final seen = <String>{};
      final active = (await db.rows("SELECT id FROM cards WHERE plan='active'"))
          .map((r) => r['id'] as String)
          .toSet();
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
      for (final d in await decks()) {
        final studied =
            (await db.rows(
                  'SELECT count(*) n FROM cards WHERE deck_id=? AND first_learned>=? AND first_learned<?',
                  [
                    d.id,
                    dayStart(now).millisecondsSinceEpoch,
                    dayEnd(now).millisecondsSinceEpoch,
                  ],
                )).first['n']
                as int;
        final fresh = await db.rows(
          "SELECT id FROM cards WHERE deck_id=? AND plan='active' AND first_learned IS NULL ORDER BY enrolled_at,rowid LIMIT ?",
          [d.id, math.max(0, d.newLimit - studied)],
        );
        final allowed = fresh.map((e) => e['id']).toSet();
        // Reducing the daily limit removes new cards that have not been studied yet.
        final deckIds = (await db.rows('SELECT id FROM cards WHERE deck_id=?', [
          d.id,
        ])).map((e) => e['id']).toSet();
        queue.removeWhere(
          (e) =>
              e.stage == 'new' &&
              deckIds.contains(e.cardId) &&
              !allowed.contains(e.cardId),
        );
        for (final r in fresh) {
          if (seen.add(r['id'])) queue.add(QueueEntry(r['id'], 'new'));
        }
      }
      final next = StudySession(
        day: today,
        queue: queue,
        completed: old?.day == today ? old!.completed : 0,
        started: old?.day == today ? old!.started : 0,
      );
      await setSetting('session', jsonEncode(next.toJson()));
      if (old?.day != today) await clearSetting('undo');
      return next;
    },
  );

  MmxAlgorithm algorithm(DeckData d, int version) => version == 5
      ? (d.params.length == 12 ? Mmx5(d.params) : const Mmx5())
      : (d.params.length == 21 ? Mmx6(d.params) : const Mmx6());
  Future<void> grade(
    RecallGrade grade, {
    required int elapsedMs,
    DateTime? at,
  }) async {
    if (_submitting) return;
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
  Future<Map<String, dynamic>> overview({DateTime? at}) async {
    final now = at ?? DateTime.now();
    final s = await prepareSession(at: now);
    final start = dayStart(now).millisecondsSinceEpoch,
        end = dayEnd(now).millisecondsSinceEpoch;
    final row = (await db.rows(
      "SELECT count(*) attempts, coalesce(sum(kind='formal'),0) formal, coalesce(sum(kind='practice'),0) practice, coalesce(sum(elapsed_ms),0) elapsed, coalesce(sum(kind='formal' AND grade IN (1,4)),0) recalled FROM reviews WHERE reviewed_at>=? AND reviewed_at<?",
      [start, end],
    )).first;
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

  Future<List<Map<String, dynamic>>> activity() => db.rows(
    "SELECT strftime('%Y-%m-%d',reviewed_at/1000,'unixepoch','localtime') day, sum(kind='formal') formal, sum(kind='practice') practice, sum(elapsed_ms) elapsed FROM reviews GROUP BY day ORDER BY day DESC LIMIT 365",
  );
  Future<List<int>> forecast({DateTime? at}) async {
    final now = at ?? DateTime.now();
    final values = <int>[];
    for (var i = 0; i < 7; i++) {
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
      for (final table in ['decks', 'cards', 'reviews', 'settings', 'media']) {
        var rows = await db.rows('SELECT * FROM $table');
        if (table == 'settings' && !includeRecovery) {
          rows = rows.where((r) => r['key'] != 'recoveryBackup').toList();
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
    await db.transaction(() async {
      for (final table in ['decks', 'cards', 'reviews', 'settings', 'media']) {
        await db.customStatement('DELETE FROM $table');
        for (final raw in data[table] as List) {
          final row = Map<String, dynamic>.from(raw);
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
            _ => ['key', 'value'],
          };
          if (table == 'media') row['bytes'] = base64Decode(row['bytes']);
          await db.customStatement(
            'INSERT INTO $table (${columns.join(',')}) VALUES (${List.filled(columns.length, '?').join(',')})',
            columns.map((c) => row[c]).toList(),
          );
        }
      }
      await setSetting('recoveryBackup', base64Encode(recovery));
      await setSetting('migrated', '1');
    });
    preferences = Preferences.fromJson(
      decodeObject(await setting('preferences') ?? '{}'),
    );
    changed();
  }

  Future<void> addExamples() async {
    final d = DeckData(
      id: newId(),
      name: '记忆的起点',
      description: '三张示例，认识你的新学习空间',
      group: '示例',
      chapters: ['开始使用'],
    );
    await putDeck(d, announce: false);
    await importCards(d.id, [
      '[P#H1#让知识，真正留下来]\n比起一次反复阅读，更有效的记忆方法是什么？\n---\n[T#B#主动回忆 + 间隔重复]。\n先尝试回忆，再揭晓答案。根据真实感受评分，下一次复习交给算法。',
      '[P#H1#微积分 · 基本定理]\n如果 F 是 f 的一个原函数，定积分如何计算？\n---\n[E##\\int_a^b f(x)\\,dx = F(b)-F(a)]',
      '[P#H1#一个小小的填空]\n记忆不是一次完成的，而是在[F#1#恰当的时间]进行[F#2#主动回忆]。\n---\n点开同一编号的空格会一起揭晓。所有空格共用这张卡的学习进度。',
    ], chapter: '开始使用');
  }

  @override
  void dispose() {
    _changes.close();
    super.dispose();
  }
}
