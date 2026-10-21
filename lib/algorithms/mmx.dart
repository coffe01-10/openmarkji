/// MMX 算法公共类型定义。
///
/// 移植自墨墨记忆卡 (com.maimemo.markji.android) APK 中 assets/mmx-5.js 与
/// assets/mmx-6.js 暴露的调度算法。两者均为墨墨自研 MMX 系列，学术渊源为
/// KDD'22 论文提出的 DHP (Difficulty-Halflife-P) 记忆模型，与开源 FSRS 同源。
library;

import 'dart:convert';

/// 复习时用户的四个自评按钮。
///
/// APK JS 中的映射表：`ratings = {1:3, 2:2, 3:1, 4:4}`
/// 界面按钮编码(appCode 1..4) → 算法内部评分(score 1..4，类 FSRS)：
///   认识(1)→3(Good)  模糊(2)→2(Hard)  忘记(3)→1(Again)  熟知(4)→4(Easy)
enum RecallGrade {
  know(appCode: 1, score: 3, label: '认识'),
  vague(appCode: 2, score: 2, label: '模糊'),
  forgot(appCode: 3, score: 1, label: '忘记'),
  familiar(appCode: 4, score: 4, label: '熟知');

  const RecallGrade({
    required this.appCode,
    required this.score,
    required this.label,
  });

  /// APK `response_history` 里存储的编码 (1..4)。
  final int appCode;

  /// 算法内部评分 (1..4)，等价 FSRS 的 Again/Hard/Good/Easy。
  final int score;

  /// 中文标签。
  final String label;

  static RecallGrade? fromAppCode(int code) {
    for (final g in values) {
      if (g.appCode == code) return g;
    }
    return null;
  }
}

/// JS 端 ratings 表：appCode → 内部评分。
int scoreOf(int appCode) =>
    const {1: 3, 2: 2, 3: 1, 4: 4}[appCode] ??
    (throw ArgumentError('非法 response code: $appCode'));

/// 记忆状态 —— 对应 JS `new State(difficulty, stability, repeat_long)`。
class MmxState {
  MmxState({
    required this.difficulty,
    required this.stability,
    required this.repeatLong,
    required this.version,
  });

  /// 难度 d ∈ [1,10]
  double difficulty;

  /// 稳定性/半衰期 s（天）
  double stability;

  /// 已完成的长期复习次数
  int repeatLong;

  /// 产生该状态的算法版本
  int version;

  Map<String, dynamic> toJson() => {
    'difficulty': difficulty,
    'stability': stability,
    'repeat_long': repeatLong,
    'version': version,
  };

  String toJsonString() => jsonEncode(toJson());

  factory MmxState.fromJson(Map<String, dynamic> j) => MmxState(
    difficulty: (j['difficulty'] as num).toDouble(),
    stability: (j['stability'] as num).toDouble(),
    repeatLong: (j['repeat_long'] as num).toInt(),
    version: (j['version'] as num).toInt(),
  );

  factory MmxState.fromJsonString(String s) =>
      MmxState.fromJson(jsonDecode(s) as Map<String, dynamic>);

  MmxState copy() => MmxState(
    difficulty: difficulty,
    stability: stability,
    repeatLong: repeatLong,
    version: version,
  );
}

/// `main()` 的返回值 —— `{success, next_interval, sr_state}`。
class ScheduleResult {
  const ScheduleResult({required this.success, this.nextInterval, this.state});

  final bool success;

  /// 下次复习间隔（天）
  final int? nextInterval;
  final MmxState? state;

  Map<String, dynamic> toJson() => {
    'success': success,
    if (nextInterval != null) 'next_interval': nextInterval,
    if (state != null) 'sr_state': state!.toJsonString(),
  };
}

/// 遗忘曲线采样点 —— `card_forgetting_curves()` 的 data 元素。
class ForgettingCurvePoint {
  const ForgettingCurvePoint({
    required this.date,
    required this.daysSinceFirstLearn,
    required this.elapsedDaysSinceLastReview,
    required this.retrievability,
    required this.stability,
    required this.reviewTh,
    this.difficulty,
  });

  final double date;
  final double daysSinceFirstLearn;
  final double elapsedDaysSinceLastReview;

  /// 0..100
  final double retrievability;
  final double stability;
  final double? difficulty;
  final int reviewTh;
}

/// MMX 算法抽象：子类按版本实现状态转移。
abstract class MmxAlgorithm {
  const MmxAlgorithm(this.params);

  /// user_params —— MMX-5 为 12 个、MMX-6 为 21 个。
  /// 开源实现默认填充公开参数（FSRS-6 官方默认值 / 依 DHP 论文拟合的估计值），
  /// 可通过导入个人学习记录重新拟合。
  final List<double> params;

  int get version;
  int get paramCount;

  /// 目标保留率，APK 中为常量 0.85。
  double get targetRetention => 0.85;

  double forgettingCurve(double t, double s);
  MmxState initState(int score);
  MmxState nextState(MmxState state, int score, double intervalDays);
  int nextInterval(double stability);

  bool get valid => params.length == paramCount;

  /// 是否需要冷启动 —— 对应 JS `need_cold_start()`。
  bool needColdStart(MmxState? srState, List<double> intervalHistory) {
    if (srState == null) return true;
    if (srState.version != version) return true;
    if (intervalHistory.length != srState.repeatLong + 1) return true;
    return false;
  }

  /// 校验输入 —— 对应 JS `validate_input()`（不含 content_params 占位校验）。
  bool validateInput(List<int> responseHistory, List<double> intervalHistory) {
    if (params.length != paramCount) return false;
    if (responseHistory.isEmpty) return false;
    if (intervalHistory.isEmpty) return false;
    if (responseHistory.length != intervalHistory.length) return false;
    for (final t in intervalHistory) {
      if (t < 0) return false;
    }
    return true;
  }

  /// 等价 JS `main(response_history, interval_history, sr_state, …)`。
  ScheduleResult schedule({
    required List<int> responseHistory,
    required List<double> intervalHistory,
    String? srStateJson,
  }) {
    if (!validateInput(responseHistory, intervalHistory)) {
      return const ScheduleResult(success: false);
    }

    MmxState? last;
    if (srStateJson != null) {
      try {
        last = MmxState.fromJsonString(srStateJson);
      } catch (_) {
        last = null;
      }
    }

    late MmxState state;
    if (needColdStart(last, intervalHistory)) {
      // 冷启动：从头重放全部历史
      MmxState? cur;
      for (var i = 0; i < responseHistory.length; i++) {
        final r = scoreOf(responseHistory[i]);
        cur = (i == 0) ? initState(r) : nextState(cur!, r, intervalHistory[i]);
      }
      state = cur!;
    } else {
      state = nextState(
        last!,
        scoreOf(responseHistory.last),
        intervalHistory.last,
      );
    }

    final interval = nextInterval(state.stability);
    return ScheduleResult(success: true, nextInterval: interval, state: state);
  }
}
