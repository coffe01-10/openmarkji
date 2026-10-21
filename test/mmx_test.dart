import 'package:flutter_test/flutter_test.dart';
import 'package:openmarkji/algorithms/mmx.dart';
import 'package:openmarkji/algorithms/mmx5.dart';
import 'package:openmarkji/algorithms/mmx6.dart';

void main() {
  group('MMX-5', () {
    const algo = Mmx5();

    test('评分映射正确', () {
      expect(scoreOf(1), 3);
      expect(scoreOf(2), 2);
      expect(scoreOf(3), 1);
      expect(scoreOf(4), 4);
    });

    test('初始状态 (rating=1→score=3)', () {
      final s = algo.initState(3);
      expect(s.repeatLong, 1);
      // difficulty = w2 - (3-1)·w3 = 3.173 - 2·15.69105
      expect(s.difficulty, closeTo(3.173 - 2 * 15.69105, 1e-6));
      expect(s.stability, greaterThan(0));
    });

    test('遗忘曲线 exp(ln0.9·t/s)', () {
      // t=0 → r=1
      expect(algo.forgettingCurve(0, 10), 1.0);
      // t=s → r=0.9
      expect(algo.forgettingCurve(10, 10), closeTo(0.9, 1e-9));
    });

    test('next_interval 用 ln(0.85)/ln(0.9)', () {
      // s=10 → 10·ln0.85/ln0.9 ≈ 15.42 → 15
      expect(algo.nextInterval(10), 15);
      expect(algo.nextInterval(0.001), 1);
      expect(algo.nextInterval(1e6), 36500);
    });

    test('schedule 冷启动 3 次评分', () {
      final res = algo.schedule(
        responseHistory: [1, 1, 1], // 认识×3
        intervalHistory: [0, 1, 3],
      );
      expect(res.success, isTrue);
      expect(res.state!.repeatLong, 3);
      expect(res.state!.version, 5);
      expect(res.nextInterval, greaterThan(0));
    });

    test('schedule 增量模式 (带 sr_state)', () {
      final r1 = algo.schedule(responseHistory: [1], intervalHistory: [0]);
      final r2 = algo.schedule(
        responseHistory: [1, 1],
        intervalHistory: [0, 3],
        srStateJson: r1.state!.toJsonString(),
      );
      expect(r2.success, isTrue);
      expect(r2.state!.repeatLong, 2);
    });
  });

  group('MMX-6', () {
    const algo = Mmx6();

    test('初始稳定性 = w[r-1]', () {
      expect(algo.initState(1).stability, 0.212); // again
      expect(algo.initState(2).stability, 1.2931); // hard
      expect(algo.initState(3).stability, 2.3065); // good
      expect(algo.initState(4).stability, 8.2956); // easy
    });

    test('遗忘曲线幂律', () {
      expect(algo.forgettingCurve(0, 10), closeTo(1.0, 1e-9));
      // s=10, t=10 → r≈0.9
      expect(algo.forgettingCurve(10, 10), closeTo(0.9, 1e-2));
    });

    test('难度随评分更新并被均值回归', () {
      final s0 = algo.initState(3);
      final s1 = algo.nextState(s0, 4, 1); // easy → 难度降
      expect(s1.difficulty, lessThan(s0.difficulty));
      final s2 = algo.nextState(s0, 1, 1); // again → 难度升
      expect(s2.difficulty, greaterThan(s0.difficulty));
    });

    test('易评分增加稳定性', () {
      final s0 = algo.initState(3);
      final s1 = algo.nextState(s0, 4, 3);
      expect(s1.stability, greaterThan(s0.stability));
    });

    test('忘记降低稳定性', () {
      final s0 = algo.initState(3);
      final s1 = algo.nextState(s0, 1, 5);
      expect(s1.stability, lessThan(s0.stability));
    });

    test('完整流程', () {
      final res = algo.schedule(
        responseHistory: [1, 1, 2, 1, 4],
        intervalHistory: [0, 1, 3, 7, 15],
      );
      expect(res.success, isTrue);
      expect(res.state!.repeatLong, 5);
      expect(res.state!.stability, greaterThan(0));
      expect(res.state!.difficulty, inInclusiveRange(1, 10));
    });
  });

  group('参数验证', () {
    test('MMX-5 参数个数', () => expect(const Mmx5().paramCount, 12));
    test('MMX-6 参数个数', () => expect(const Mmx6().paramCount, 21));
    test('非法参数 schedule 失败', () {
      const bad = Mmx6([1.0, 2.0]);
      final res = bad.schedule(responseHistory: [1], intervalHistory: [0]);
      expect(res.success, isFalse);
    });
  });
}
