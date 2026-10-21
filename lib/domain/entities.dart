import 'dart:convert';

String newId() => '${DateTime.now().microsecondsSinceEpoch}_${_sequence++}';
int _sequence = 0;
String dayKey(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
DateTime dayStart(DateTime value) =>
    DateTime(value.year, value.month, value.day);
DateTime dayEnd(DateTime value) =>
    DateTime(value.year, value.month, value.day + 1);

class DeckData {
  DeckData({
    required this.id,
    required this.name,
    this.description = '',
    this.group = '',
    this.newLimit = 20,
    this.algorithm = 6,
    this.params = const [],
    this.chapters = const [],
  });
  final String id;
  final String name, description, group;
  final int newLimit, algorithm;
  final List<double> params;
  final List<String> chapters;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'group': group,
    'newLimit': newLimit,
    'algorithm': algorithm,
    'params': params,
    'chapters': chapters,
  };
  factory DeckData.fromJson(Map<String, dynamic> j) => DeckData(
    id: j['id'],
    name: j['name'],
    description: j['description'] ?? '',
    group: j['group'] ?? '',
    newLimit: j['newLimit'] ?? j['new_cards_per_day'] ?? 20,
    algorithm: j['algorithm'] ?? j['algo_version'] ?? 6,
    params: (j['params'] as List? ?? [])
        .map((e) => (e as num).toDouble())
        .toList(),
    chapters: List<String>.from(j['chapters'] ?? []),
  );
}

class StudyCard {
  StudyCard({
    required this.id,
    required this.deckId,
    required this.source,
    this.chapter = '',
    this.tags = const [],
    this.plan = 'library',
    this.enrolledAt,
    this.state,
    this.dueAt,
    this.lastReview,
    this.firstLearned,
    this.algorithm = 6,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  final String id, deckId, source, chapter, plan;
  final List<String> tags;
  final String? state;
  final DateTime? dueAt, lastReview, firstLearned, enrolledAt;
  final DateTime createdAt;
  final int algorithm;
  bool get isNew => state == null;
  Map<String, dynamic> toJson() => {
    'id': id,
    'deckId': deckId,
    'source': source,
    'chapter': chapter,
    'tags': tags,
    'plan': plan,
    'enrolledAt': enrolledAt?.toIso8601String(),
    'state': state,
    'dueAt': dueAt?.toIso8601String(),
    'lastReview': lastReview?.toIso8601String(),
    'firstLearned': firstLearned?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'algorithm': algorithm,
  };
  factory StudyCard.fromJson(Map<String, dynamic> j) => StudyCard(
    id: j['id'],
    deckId: j['deckId'],
    source: j['source'],
    chapter: j['chapter'] ?? '',
    tags: List<String>.from(j['tags'] ?? []),
    plan: j['plan'] ?? 'library',
    enrolledAt: _date(j['enrolledAt']),
    state: j['state'],
    dueAt: _date(j['dueAt']),
    lastReview: _date(j['lastReview']),
    firstLearned: _date(j['firstLearned']),
    createdAt: _date(j['createdAt']),
    algorithm: j['algorithm'] ?? 6,
  );
  StudyCard withValues(Map<String, dynamic> values) =>
      StudyCard.fromJson({...toJson(), ...values});
}

DateTime? _date(dynamic value) => value == null ? null : DateTime.parse(value);

class QueueEntry {
  const QueueEntry(this.cardId, this.stage);
  final String cardId, stage;
  Map<String, dynamic> toJson() => {'cardId': cardId, 'stage': stage};
  factory QueueEntry.fromJson(Map<String, dynamic> j) =>
      QueueEntry(j['cardId'], j['stage']);
}

class StudySession {
  StudySession({
    required this.day,
    required this.queue,
    this.completed = 0,
    this.started = 0,
  });
  final String day;
  final List<QueueEntry> queue;
  final int completed, started;
  Map<String, dynamic> toJson() => {
    'day': day,
    'queue': queue.map((e) => e.toJson()).toList(),
    'completed': completed,
    'started': started,
  };
  factory StudySession.fromJson(Map<String, dynamic> j) => StudySession(
    day: j['day'],
    queue: (j['queue'] as List)
        .map((e) => QueueEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    completed: j['completed'] ?? 0,
    started: j['started'] ?? 0,
  );
}

class Preferences {
  Preferences({
    this.theme = 'system',
    this.color = 0xff5479bc,
    this.dynamicColor = true,
    this.fontSize = 18,
    this.defaultLimit = 20,
  });
  String theme;
  int color, defaultLimit;
  bool dynamicColor;
  double fontSize;
  Map<String, dynamic> toJson() => {
    'theme': theme,
    'color': color,
    'dynamicColor': dynamicColor,
    'fontSize': fontSize,
    'defaultLimit': defaultLimit,
  };
  factory Preferences.fromJson(Map<String, dynamic> j) => Preferences(
    theme: j['theme'] ?? 'system',
    color: j['color'] ?? 0xff5479bc,
    dynamicColor: j['dynamicColor'] ?? true,
    fontSize: (j['fontSize'] as num? ?? 18).toDouble(),
    defaultLimit: j['defaultLimit'] ?? 20,
  );
}

Map<String, dynamic> decodeObject(String json) =>
    Map<String, dynamic>.from(jsonDecode(json));
