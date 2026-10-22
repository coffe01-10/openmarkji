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
    this.sortOrder = 0,
  });
  final String id;
  final String name, description, group;
  final int newLimit, algorithm, sortOrder;
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
    'sortOrder': sortOrder,
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
    sortOrder: j['sortOrder'] ?? 0,
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
    this.favorite = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  final String id, deckId, source, chapter, plan;
  final List<String> tags;
  final String? state;
  final DateTime? dueAt, lastReview, firstLearned, enrolledAt;
  final DateTime createdAt;
  final int algorithm;
  final bool favorite;
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
    'favorite': favorite,
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
    favorite: j['favorite'] ?? false,
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

class PracticeSession {
  PracticeSession({
    required this.deckId,
    required this.queue,
    required this.total,
    this.completed = 0,
    this.skipped = 0,
    this.attempts = 0,
    this.firstRecalled = 0,
    this.answered = const [],
    this.mistakes = const [],
  });
  final String deckId;
  final List<String> queue, answered, mistakes;
  final int total, completed, skipped, attempts, firstRecalled;
  Map<String, dynamic> toJson() => {
    'deckId': deckId,
    'queue': queue,
    'total': total,
    'completed': completed,
    'skipped': skipped,
    'attempts': attempts,
    'firstRecalled': firstRecalled,
    'answered': answered,
    'mistakes': mistakes,
  };
  factory PracticeSession.fromJson(Map<String, dynamic> j) => PracticeSession(
    deckId: j['deckId'],
    queue: List<String>.from(j['queue']),
    total: j['total'],
    completed: j['completed'],
    skipped: j['skipped'],
    attempts: j['attempts'],
    firstRecalled: j['firstRecalled'],
    answered: List<String>.from(j['answered']),
    mistakes: List<String>.from(j['mistakes']),
  );
}

class Preferences {
  Preferences({
    this.theme = 'system',
    this.color = 0xff5479bc,
    this.dynamicColor = true,
    this.fontSize = 18,
    this.defaultLimit = 20,
    this.defaultAlgorithm = 6,
    this.liquidGlass = 'ultra',
    this.floatingNavigation = true,
    this.tabAnimation = 'slide',
    this.pureBlack = false,
    this.colorStyle = 'tonalSpot',
    this.textScale = 1,
    this.fontFamily = 'system',
    this.dockOpacity = .58,
    this.dockBlur = 16,
    this.relearnGap = 3,
    this.studyHaptics = true,
    this.showStudyProgress = true,
    this.showRecallHint = true,
  });
  String theme;
  int color, defaultLimit, defaultAlgorithm;
  bool dynamicColor;
  double fontSize;
  String liquidGlass, tabAnimation, colorStyle, fontFamily;
  bool floatingNavigation, pureBlack;
  double textScale;
  double dockOpacity, dockBlur;
  int relearnGap;
  bool studyHaptics, showStudyProgress, showRecallHint;
  Map<String, dynamic> toJson() => {
    'theme': theme,
    'color': color,
    'dynamicColor': dynamicColor,
    'fontSize': fontSize,
    'defaultLimit': defaultLimit,
    'defaultAlgorithm': defaultAlgorithm,
    'liquidGlass': liquidGlass,
    'floatingNavigation': floatingNavigation,
    'tabAnimation': tabAnimation,
    'pureBlack': pureBlack,
    'colorStyle': colorStyle,
    'textScale': textScale,
    'fontFamily': fontFamily,
    'dockOpacity': dockOpacity,
    'dockBlur': dockBlur,
    'relearnGap': relearnGap,
    'studyHaptics': studyHaptics,
    'showStudyProgress': showStudyProgress,
    'showRecallHint': showRecallHint,
  };
  factory Preferences.fromJson(Map<String, dynamic> j) => Preferences(
    theme: j['theme'] ?? 'system',
    color: j['color'] ?? 0xff5479bc,
    dynamicColor: j['dynamicColor'] ?? true,
    fontSize: (j['fontSize'] as num? ?? 18).toDouble(),
    defaultLimit: j['defaultLimit'] ?? 20,
    defaultAlgorithm: j['defaultAlgorithm'] ?? 6,
    liquidGlass: j['liquidGlass'] ?? 'ultra',
    floatingNavigation: j['floatingNavigation'] ?? true,
    tabAnimation: j['tabAnimation'] ?? 'slide',
    pureBlack: j['pureBlack'] ?? false,
    colorStyle: j['colorStyle'] ?? 'tonalSpot',
    textScale: (j['textScale'] as num? ?? 1).toDouble(),
    fontFamily: j['fontFamily'] ?? 'system',
    dockOpacity: (j['dockOpacity'] as num? ?? .58).toDouble(),
    dockBlur: (j['dockBlur'] as num? ?? 16).toDouble(),
    relearnGap: j['relearnGap'] ?? 3,
    studyHaptics: j['studyHaptics'] ?? true,
    showStudyProgress: j['showStudyProgress'] ?? true,
    showRecallHint: j['showRecallHint'] ?? true,
  );
}

Map<String, dynamic> decodeObject(String json) =>
    Map<String, dynamic>.from(jsonDecode(json));
