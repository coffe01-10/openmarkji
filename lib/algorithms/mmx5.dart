/// MMX-5 —— 逐行移植自 APK `assets/mmx-5.js`（12 参数）。
///
/// 与 FSRS-4.5 同构：指数遗忘曲线 exp(ln(0.9)·t/s)，难度线性更新，
/// 成功/失败两条稳定性更新路径。
library;

import 'dart:math' as math;

import 'mmx.dart';

/// MMX-5 默认参数（12 个）。
///
/// 墨墨真实参数存储在 mmdb (SQLCipher 加密) 中未能提取；
/// 这里采用与 MMX-5 公式同构的 FSRS-4.5 公开默认参数前 12 项，
/// 语义对应：
///   [0..3]  初始稳定性 s0(again/hard/good/easy)
///   [4]     init_difficulty 基准 & 难度步长 w4
///   [5..8]  recall stability: e^w5 · d^w6 · s^w7 · (e^(w8(1-r))-1)
///   [9..11] forget stability: w9 · s^w10 · e^(w11(1-r))
const List<double> kMmx5DefaultParams = [
  0.40255, 1.18385, 3.173, 15.69105, // w0..w3 初始稳定性
  7.1949, // w4 难度步长
  0.5345, -0.787, 0.0839, 1.514, // w5..w8 回忆成功稳定性
  0.363, 1.0012, 0.0, // w9..w11 回忆失败稳定性（w11 未在JS中→取0）
];

class Mmx5 extends MmxAlgorithm {
  const Mmx5([super.params = kMmx5DefaultParams]);

  @override
  int get version => 5;

  @override
  int get paramCount => 12;

  /// `forgetting_curve(t, s) = exp(ln(0.9) * t / s)`
  @override
  double forgettingCurve(double t, double s) => math.exp(math.log(0.9) * t / s);

  /// `init_state`:
  ///   difficulty = w2 - (r-1)·w3  → 实为 params[2],[3]
  ///   stability  = 2^(w0 + (r-1)·w1) → 实为 params[0],[1]
  ///
  /// 注意 JS 中下标：user_params[0..3] 前两对用于 init，
  /// 不是 FSRS 的 s0[4]。这里按 JS 原样实现。
  @override
  MmxState initState(int score) {
    final d = params[2] - (score - 1) * params[3];
    final s = math.pow(2, params[0] + (score - 1) * params[1]).toDouble();
    return MmxState(
      difficulty: d,
      stability: s,
      repeatLong: 1,
      version: version,
    );
  }

  /// `next_state`：先更新难度，再按评分走成功/失败两条分支。
  @override
  MmxState nextState(MmxState state, int score, double intervalDays) {
    final r = forgettingCurve(intervalDays, state.stability);
    final difficulty = nextDifficulty(state.difficulty, score);
    final double stability = (score <= 2)
        ? nextForgetStability(difficulty, state.stability, r)
        : nextRecallStability(difficulty, state.stability, r);
    return MmxState(
      difficulty: difficulty,
      stability: stability,
      repeatLong: state.repeatLong + 1,
      version: version,
    );
  }

  /// `next_difficulty`: d' = d - (r-3)·w4，截断 [1,10]
  double nextDifficulty(double d, int score) {
    final nd = d - (score - 3) * params[4];
    return nd.clamp(1.0, 10.0);
  }

  /// `next_forget_stability`: s' = w9·s^w10·e^(w11·(1-r))
  double nextForgetStability(double d, double s, double r) => _round2(
    params[9] * math.pow(s, params[10]) * math.exp(params[11] * (1 - r)),
  );

  /// `next_recall_stability`:
  ///   s' = s · (e^w5 · d^w6 · s^w7 · (e^(w8(1-r)) - 1) + 1)
  double nextRecallStability(double d, double s, double r) => _round2(
    s *
        (math.exp(params[5]) *
                math.pow(d, params[6]) *
                math.pow(s, params[7]) *
                (math.exp(params[8] * (1 - r)) - 1) +
            1),
  );

  /// `next_interval`: clamp(round(s·ln(0.85)/ln(0.9)), 1, 36500)
  /// 稳定性为 0 / NaN 时返回 1。
  @override
  int nextInterval(double stability) {
    if (!stability.isFinite || stability <= 0) return 1;
    final v = (stability * math.log(targetRetention) / math.log(0.9)).round();
    return v.clamp(1, 36500);
  }

  double _round2(double v) => (v * 100).roundToDouble() / 100;
}
