/// MMX-6 —— 逐行移植自 APK `assets/mmx-6.js`（21 参数）。
///
/// 与 FSRS-6 同构：幂律遗忘曲线 (1+factor·t/s)^decay，
/// 难度带线性阻尼 + 均值回归，稳定化含 easy bonus / again penalty。
library;

import 'dart:math' as math;

import 'mmx.dart';

/// MMX-6 默认参数（21 个）= FSRS-6 官方默认值 + FSRS6_DEFAULT_DECAY。
const List<double> kMmx6DefaultParams = [
  0.212, 1.2931, 2.3065, 8.2956, // w0..w3 各评分初始稳定性
  6.4133, 0.8334, 3.0194, 0.001, // w4..w7 难度/均值回归
  1.8722, 0.1666, 0.796, 1.4835, // w8..w11
  0.0614, 0.2629, 1.6483, 0.6014, // w12..w15
  1.8729, 0.5425, 0.0912, 0.0658, // w16..w19
  0.1542, // w20 = -decay（遗忘曲线指数）
];

class Mmx6 extends MmxAlgorithm {
  const Mmx6([super.params = kMmx6DefaultParams]);

  @override
  int get version => 6;

  @override
  int get paramCount => 21;

  /// decay = -params[20]
  double get decay => -params[20];

  /// `forgetting_curve(t,s,decay)`:
  ///   factor = 0.9^(1/decay) - 1
  ///   r = (1 + factor·t/s)^decay
  @override
  double forgettingCurve(double t, double s) {
    final factor = math.pow(0.9, 1 / decay) - 1;
    return math.pow(1 + factor * t / s, decay).toDouble();
  }

  /// `init_state`: s = w[r-1]; d = clamp(init_difficulty,1,10)
  @override
  MmxState initState(int score) {
    final s = params[score - 1];
    final d = initDifficulty(score).clamp(1.0, 10.0);
    return MmxState(
      difficulty: d,
      stability: s,
      repeatLong: 1,
      version: version,
    );
  }

  /// `init_difficulty`: w4 - e^(w5·(r-1)) + 1
  double initDifficulty(int score) =>
      params[4] - math.exp(params[5] * (score - 1)) + 1;

  /// `next_state`
  @override
  MmxState nextState(MmxState state, int score, double intervalDays) {
    final r = forgettingCurve(intervalDays, state.stability);
    final difficulty = nextDifficulty(state.difficulty, score);
    final double stability = (score <= 2)
        ? nextForgetStability(difficulty, state.stability, r, score)
        : nextRecallStability(difficulty, state.stability, r, score);
    return MmxState(
      difficulty: difficulty,
      stability: stability,
      repeatLong: state.repeatLong + 1,
      version: version,
    );
  }

  /// `linear_damping`: delta_d·(10-d)/9
  double _linearDamping(double deltaD, double oldD) => deltaD * (10 - oldD) / 9;

  /// `mean_reversion`: w7·init + (1-w7)·current
  double _meanReversion(double initValue, double current) =>
      params[7] * initValue + (1 - params[7]) * current;

  /// `next_difficulty`:
  ///   delta = -w6·(r-3)
  ///   d' = d + linear_damping(delta, d)
  ///   d' = mean_reversion(init_difficulty(again), d')
  double nextDifficulty(double d, int score) {
    final delta = -params[6] * (score - 3);
    var nd = d + _linearDamping(delta, d);
    nd = _meanReversion(initDifficulty(1), nd);
    return _round2(nd).clamp(1.0, 10.0);
  }

  /// `next_recall_stability`:
  ///   easy_bonus = r==4 ? w16 : 1
  ///   s' = s·(1 + e^w8·(11-d)·s^(-w9)·(e^((1-r)·w10)-1)·easy_bonus)
  double nextRecallStability(double d, double s, double r, int score) {
    final ss = s > 0 ? s : 1e-6;
    final rr = r.isFinite ? r.clamp(0.0, 1.0) : 0.0;
    final easyBonus = score == 4 ? params[16] : 1.0;
    final ns =
        ss *
        (1 +
            math.exp(params[8]) *
                (11 - d) *
                math.pow(ss, -params[9]) *
                (math.exp((1 - rr) * params[10]) - 1) *
                easyBonus);
    final v = _round2(ns);
    return v.isFinite ? math.max(v, 0.01) : 0.01;
  }

  /// `next_forget_stability`:
  ///   again_penalty = r==1 ? w15 : 1
  ///   s' = w11·d^(-w12)·((s+1)^w13 - 1)·e^((1-r)·w14)·again_penalty
  /// s ≤ 0 时视为极小正数避免 0^0.26 形式的不稳定。
  double nextForgetStability(double d, double s, double r, int score) {
    final ss = s > 0 ? s : 1e-6;
    final rr = r.isFinite ? r.clamp(0.0, 1.0) : 0.0;
    final againPenalty = score == 1 ? params[15] : 1.0;
    final ns =
        params[11] *
        math.pow(d, -params[12]) *
        (math.pow(ss + 1, params[13]) - 1) *
        math.exp((1 - rr) * params[14]) *
        againPenalty;
    final v = _round2(ns);
    return v.isFinite ? math.max(v, 0.01) : 0.01;
  }

  /// `next_interval`: 同 MMX-5。稳定性为 0 / NaN 时返回 1。
  @override
  int nextInterval(double stability) {
    if (!stability.isFinite || stability <= 0) return 1;
    final v = (stability * math.log(targetRetention) / math.log(0.9)).round();
    return v.clamp(1, 36500);
  }

  double _round2(double v) => (v * 100).roundToDouble() / 100;
}
