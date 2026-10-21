import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmarkji/data/app_store.dart';
import 'package:openmarkji/data/database.dart';
import 'package:openmarkji/domain/entities.dart';
import 'package:openmarkji/ui/app.dart';
import 'package:openmarkji/ui/content_view.dart';

void main() {
  late AppStore store;
  setUp(() async {
    store = AppStore(AppDatabase(NativeDatabase.memory()));
    await store.initialize(legacy: {});
  });
  tearDown(() async {
    store.dispose();
    await store.db.close();
  });

  testWidgets('手机选卡、揭晓、评分、撤销与重学完整链路', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await store.addExamples();
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('记忆的起点'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选筛选结果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入计划'));
    await tester.pumpAndSettle();
    expect(find.text('已更新 3 张卡片'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('今日').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始今日学习'));
    await tester.pumpAndSettle();
    expect(find.text('揭晓答案'), findsOneWidget);
    await tester.tap(find.text('揭晓答案'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('忘记'));
    await tester.pumpAndSettle();
    expect((await store.session())!.queue.last.stage, 'relearn');
    await tester.tap(find.byTooltip('撤销上一次评分'));
    await tester.pumpAndSettle();
    expect((await store.session())!.queue.first.stage, 'new');
    expect(
      (await store.historyFor((await store.session())!.queue.first.cardId)),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑保存关闭页面并清除草稿', (tester) async {
    await store.putDeck(DeckData(id: 'd', name: '测试牌组'));
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试牌组'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('写卡片'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '问题\n---\n答案');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('写一张新卡'), findsNothing);
    expect((await store.cards(deckId: 'd')).single.source, '问题\n---\n答案');
    expect(await store.setting('draft:d'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏放大字体和深色主题不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    store.preferences.theme = 'dark';
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final label in ['牌组', '统计', '设置']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label 页不应溢出');
    }
  });

  testWidgets('文本导入预览可以排除卡片，导入后不自动入计划', (tester) async {
    await store.putDeck(DeckData(id: 'd', name: '导入测试'));
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入测试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).at(0),
      '甲\n---\n乙\n===CARD===\n丙\n---\n丁',
    );
    await tester.scrollUntilVisible(
      find.text('卡片之间的独立分隔行'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.widgetWithText(TextField, '卡片之间的独立分隔行'),
      '===CARD===',
    );
    await tester.ensureVisible(find.text('预览卡片'));
    await tester.tap(find.text('预览卡片'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('卡片 2'),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('卡片 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入 1 张卡片'));
    await tester.pumpAndSettle();
    final cards = await store.cards(deckId: 'd');
    expect(cards.length, 1);
    expect(cards.single.source, '甲\n---\n乙');
    expect(cards.single.plan, 'library');
    expect(tester.takeException(), isNull);
  });

  testWidgets('840 起宽屏双栏可查看详情', (tester) async {
    tester.view.physicalSize = const Size(900, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await store.addExamples();
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('记忆的起点'));
    await tester.pumpAndSettle();
    expect(find.text('写卡片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同编号挖空逐组揭晓，不提前暴露答案区', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContentView(
            source: '[F#1#甲]与[F#1#乙]、[F#2#丙]\n---\n最终答案',
            store: store,
            revealed: false,
          ),
        ),
      ),
    );
    expect(find.text('最终答案'), findsNothing);
    expect(find.text('甲'), findsNothing);
    await tester.tap(find.text('  ··· 1  ').first);
    await tester.pump();
    expect(find.text('甲'), findsOneWidget);
    expect(find.text('乙'), findsOneWidget);
    expect(find.text('丙'), findsNothing);
  });
}
