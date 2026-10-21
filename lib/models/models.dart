/// 数据模型：卡片 / 牌组 / 复习记录。
library;

/// 一张记忆卡（正面/背面，支持纯文本与 Markdown）。
class Card {
  Card({
    required this.id,
    required this.deckId,
    required this.front,
    required this.back,
    DateTime? createdAt,
    this.tags = const [],
    this.srState,
    this.dueAt,
    this.algoVersion = 6,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  String deckId;
  String front;
  String back;
  List<String> tags;
  DateTime createdAt;

  /// 上次调度产出的算法状态（JSON 字符串），下次作为 `sr_state` 输入。
  String? srState;

  /// 下次到期时间；null 表示新卡。
  DateTime? dueAt;

  /// 这张卡使用的算法版本 (5|6)。
  int algoVersion;

  bool get isNew => srState == null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'deck_id': deckId,
    'front': front,
    'back': back,
    'tags': tags,
    'created_at': createdAt.toIso8601String(),
    'sr_state': srState,
    'due_at': dueAt?.toIso8601String(),
    'algo_version': algoVersion,
  };

  factory Card.fromJson(Map<String, dynamic> j) => Card(
    id: j['id'] as String,
    deckId: j['deck_id'] as String,
    front: j['front'] as String? ?? '',
    back: j['back'] as String? ?? '',
    createdAt:
        DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
    tags: (j['tags'] as List?)?.cast<String>() ?? const [],
    srState: j['sr_state'] as String?,
    dueAt: j['due_at'] != null
        ? DateTime.tryParse(j['due_at'] as String)
        : null,
    algoVersion: (j['algo_version'] as num?)?.toInt() ?? 6,
  );
}

/// 牌组。
class Deck {
  Deck({
    required this.id,
    required this.name,
    this.description = '',
    DateTime? createdAt,
    this.algoVersion = 6,
    this.newCardsPerDay = 20,
    this.targetRetention = 0.85,
    List<double>? params,
  }) : createdAt = createdAt ?? DateTime.now(),
       params = params ?? const [];

  final String id;
  String name;
  String description;
  DateTime createdAt;

  /// 该牌组默认算法版本。
  int algoVersion;

  int newCardsPerDay;
  double targetRetention;

  /// 牌组自定义 user_params；空则用算法默认。
  List<double> params;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'created_at': createdAt.toIso8601String(),
    'algo_version': algoVersion,
    'new_cards_per_day': newCardsPerDay,
    'target_retention': targetRetention,
    'params': params,
  };

  factory Deck.fromJson(Map<String, dynamic> j) => Deck(
    id: j['id'] as String,
    name: j['name'] as String,
    description: j['description'] as String? ?? '',
    createdAt:
        DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
    algoVersion: (j['algo_version'] as num?)?.toInt() ?? 6,
    newCardsPerDay: (j['new_cards_per_day'] as num?)?.toInt() ?? 20,
    targetRetention: (j['target_retention'] as num?)?.toDouble() ?? 0.85,
    params:
        (j['params'] as List?)?.map((e) => (e as num).toDouble()).toList() ??
        const [],
  );
}

/// 一次复习留下的记录（算法输入 `response_history` / `interval_history`）。
class ReviewLog {
  ReviewLog({
    required this.cardId,
    required this.grade,
    required this.reviewedAt,
    required this.intervalDays,
    required this.srStateAfter,
    required this.algoVersion,
    this.elapsedMs = 0,
  });

  final String cardId;

  /// appCode 1..4（认识/模糊/忘记/熟知）
  final int grade;
  final DateTime reviewedAt;

  /// 本次复习距上次的天数（JS `interval_history[i]`）。
  final double intervalDays;
  final String srStateAfter;
  final int algoVersion;
  final int elapsedMs;

  Map<String, dynamic> toJson() => {
    'card_id': cardId,
    'grade': grade,
    'reviewed_at': reviewedAt.toIso8601String(),
    'interval_days': intervalDays,
    'sr_state_after': srStateAfter,
    'algo_version': algoVersion,
    'elapsed_ms': elapsedMs,
  };

  factory ReviewLog.fromJson(Map<String, dynamic> j) => ReviewLog(
    cardId: j['card_id'] as String,
    grade: j['grade'] as int,
    reviewedAt: DateTime.parse(j['reviewed_at'] as String),
    intervalDays: (j['interval_days'] as num).toDouble(),
    srStateAfter: j['sr_state_after'] as String,
    algoVersion: (j['algo_version'] as num).toInt(),
    elapsedMs: (j['elapsed_ms'] as num?)?.toInt() ?? 0,
  );
}
