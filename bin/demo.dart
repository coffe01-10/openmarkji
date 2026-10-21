/// CLI 演示：走一遍 MMX-6 调度流程。
import 'dart:io';

import 'package:openmarkji/algorithms/mmx.dart';
import 'package:openmarkji/algorithms/mmx6.dart';
import 'package:openmarkji/models/models.dart' as m;
import 'package:openmarkji/services/scheduler.dart';

Future<void> main() async {
  final tmp = Directory.systemTemp.createTempSync('openmarkji');
  final sch = Scheduler(tmp);
  await sch.load();

  // 建牌组
  final deck = sch.createDeck('英语四级', algoVersion: 6);

  // 加 3 张卡
  sch.createCard(deckId: deck.id, front: 'abandon', back: '放弃');
  sch.createCard(deckId: deck.id, front: 'abate', back: '减弱');
  sch.createCard(deckId: deck.id, front: 'abdicate', back: '退位');

  print('=== 初始 due 卡片 ===');
  final due0 = sch.dueCards(deck);
  for (final c in due0) {
    print('  ${c.front} (new=${c.isNew})');
  }

  // 模拟 3 天复习
  var now = DateTime.now();
  print('\n=== 模拟复习 ===');
  for (var day = 0; day < 5; day++) {
    print('\n-- Day $day (${now.toString().substring(0, 10)}) --');
    final due = sch.dueCards(deck, now: now);
    if (due.isEmpty) {
      print('  无到期卡片');
      now = now.add(const Duration(days: 1));
      continue;
    }
    for (final c in due.toList()) {
      // 模拟评分：第一张总忘记，第二张总认识，第三张总熟知
      final g = c.front == 'abandon'
          ? RecallGrade.forgot
          : c.front == 'abate'
              ? RecallGrade.know
              : RecallGrade.familiar;
      final elapsed = c.isNew || c.dueAt == null
          ? 0.0
          : now.difference(c.dueAt!).inSeconds / 86400.0;
      final r = sch.review(c, g, elapsedDays: elapsed.abs(), now: now);
      print('  ${c.front.padRight(10)} → ${g.label}  '
          '稳定性=${r.state?.stability.toStringAsFixed(2)}  '
          '难度=${r.state?.difficulty.toStringAsFixed(2)}  '
          '下次=${r.nextInterval}天');
    }
    now = now.add(const Duration(days: 1));
  }

  await sch.save();
  print('\n存储目录: ${tmp.path}');
}
