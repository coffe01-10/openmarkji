import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmarkji/data/app_store.dart';
import 'package:openmarkji/data/database.dart';
import 'package:openmarkji/domain/entities.dart';
import 'package:openmarkji/ui/app.dart';
import 'package:openmarkji/ui/content_view.dart';
import 'package:openmarkji/ui/flclash/liquid_glass.dart';
import 'package:openmarkji/ui/flclash/navigation_dock.dart';
import 'package:openmarkji/ui/flclash/popup.dart';

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

  testWidgets('收藏筛选后可专项练习，中途续练并查看巩固结果', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await store.putDeck(DeckData(id: 'p', name: '专项测试'));
    await store.putCard(
      StudyCard(id: 'pa', deckId: 'p', source: '练习问题甲\n---\n练习答案甲'),
    );
    await store.putCard(
      StudyCard(id: 'pb', deckId: 'p', source: '练习问题乙\n---\n练习答案乙'),
    );
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('专项测试'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('收藏卡片').first);
    await tester.pumpAndSettle();
    expect((await store.card('pa'))!.favorite, isTrue);
    await tester.tap(find.widgetWithText(FilterChip, '收藏'));
    await tester.pumpAndSettle();
    expect(find.textContaining('练习问题乙'), findsNothing);
    await tester.tap(find.byTooltip('专项练习'));
    await tester.pumpAndSettle();
    expect(find.text('收藏卡片'), findsOneWidget);
    await tester.ensureVisible(find.text('开始新一轮练习'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始新一轮练习'));
    await tester.pumpAndSettle();
    expect(find.text('揭晓答案'), findsOneWidget);
    await tester.tap(find.text('揭晓答案'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('忘记'));
    await tester.pumpAndSettle();
    expect((await store.practiceSession())!.attempts, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('继续上次练习'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续上次练习'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('揭晓答案'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('认识'));
    await tester.pumpAndSettle();
    expect(find.text('又巩固了一轮'), findsOneWidget);
    expect(find.text('首次回忆正确 0 / 1 张'), findsOneWidget);
    expect((await store.session())!.queue, isEmpty);
    expect((await store.card('pa'))!.state, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('收藏筛选里取消一张，不串改下一张的星标', (tester) async {
    await store.putDeck(DeckData(id: 'f', name: '收藏测试'));
    for (final id in ['fa', 'fb']) {
      await store.putCard(
        StudyCard(id: id, deckId: 'f', source: '问题$id', favorite: true),
      );
    }
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏测试'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('取消收藏').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('取消收藏'), findsOneWidget);
    expect(find.byTooltip('收藏卡片'), findsNothing);
    expect((await store.card('fa'))!.favorite, isFalse);
    expect((await store.card('fb'))!.favorite, isTrue);
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
    for (final section in ['外观与阅读', '学习偏好', '资料与备份', '关于']) {
      await tester.scrollUntilVisible(find.text(section), 120);
      await tester.tap(find.text(section));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$section 不应溢出');
      await tester.pageBack();
      await tester.pumpAndSettle();
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

  testWidgets('返回今日后，全部牌组仍向左推进，与底部导航方向一致', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('今日').last);
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('全部牌组 →')),
      alignment: .3,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部牌组 →'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    SlideTransition transitionFor(String type) =>
        tester.widget<SlideTransition>(
          find
              .ancestor(
                of: find.byWidgetPredicate(
                  (widget) => widget.runtimeType.toString() == type,
                ),
                matching: find.byType(SlideTransition),
              )
              .first,
        );
    expect(
      transitionFor('_LibraryPage').position.value.dx,
      greaterThan(0),
      reason: '右侧牌组应从右侧进入，整页向左推进',
    );
    expect(
      transitionFor('_TodayPage').position.value.dx,
      lessThan(0),
      reason: '今日应向左离开',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置页只显示入口，点开后才展开具体选项', (tester) async {
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(find.text('主题模式'), findsNothing);
    expect(find.text('导出完整备份'), findsNothing);
    await tester.scrollUntilVisible(find.text('外观与阅读'), 120);
    await tester.tap(find.text('外观与阅读'));
    await tester.pumpAndSettle();
    expect(find.text('主题模式'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('卡片阅读字号'), 300);
    expect(find.text('卡片阅读字号'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('资料与备份'), 120);
    await tester.tap(find.text('资料与备份'));
    await tester.pumpAndSettle();
    expect(find.text('导出完整备份'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置展开完成与收回时保留二级页状态，收回前不重复显示入口', (tester) async {
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('外观与阅读'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final page = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_AppearancePage',
    );
    final state = tester.state(page);
    await tester.pumpAndSettle();
    expect(tester.state(page), same(state));

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.state(page), same(state));
    // 返回动画结束前，只应绘制动画中的那一行。
    expect(find.text('外观与阅读'), findsNWidgets(2));
    await tester.pumpAndSettle();
    expect(find.text('外观与阅读'), findsOneWidget);
    await tester.tap(find.text('外观与阅读'));
    await tester.pumpAndSettle();
    expect(find.text('主题模式'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('玻璃三档和导航样式即时生效，返回后保留选择', (tester) async {
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('外观与阅读'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('标准'), 250);
    await tester.tap(find.text('标准'));
    await tester.pumpAndSettle();
    expect(store.preferences.liquidGlass, 'standard');
    expect(
      tester
          .widget<LiquidGlassScope>(find.byType(LiquidGlassScope).first)
          .quality,
      LiquidGlassQuality.standard,
    );
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<LiquidGlassScope>(find.byType(LiquidGlassScope).first)
          .enabled,
      isFalse,
    );
    await tester.tap(find.text('超高'));
    await tester.pumpAndSettle();
    expect(store.preferences.liquidGlass, 'ultra');
    await tester.scrollUntilVisible(find.text('固定'), -250);
    await tester.tap(find.text('固定'));
    await tester.pumpAndSettle();
    expect(store.preferences.floatingNavigation, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.text('外观与阅读'));
    await tester.pumpAndSettle();
    expect(store.preferences.floatingNavigation, isFalse);
    expect(store.preferences.liquidGlass, 'ultra');
    expect(tester.takeException(), isNull);
  });

  testWidgets('FlClash 菜单从右侧值控件展开，选值后保存并收回', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('外观与阅读'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('色彩风格'), 200);
    await tester.ensureVisible(find.text('柔和'));
    await tester.pumpAndSettle();
    final anchor = tester.getRect(find.text('柔和'));
    await tester.tap(find.text('柔和'));
    await tester.pumpAndSettle();
    expect(find.byType(CommonPopupMenu), findsOneWidget);
    final menu = tester.getRect(find.byType(CommonPopupMenu));
    expect(menu.right, greaterThan(anchor.left));
    expect(menu.right, lessThanOrEqualTo(390));
    await tester.tap(find.text('鲜明'));
    await tester.pumpAndSettle();
    expect(store.preferences.colorStyle, 'vibrant');
    expect(find.byType(CommonPopupMenu), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('关于页支持更新状态、政策、帮助与反馈表单', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('关于'), 150);
    await tester.pumpAndSettle();
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '检查更新'));
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未配置更新源'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('协议与政策'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐私与数据说明'));
    await tester.pumpAndSettle();
    expect(find.text('本地保存'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('帮助与反馈'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('问题反馈与功能建议'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('问题反馈与功能建议'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '复制反馈报告'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), '界面建议：调整菜单留白');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '复制反馈报告'))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('实时预览的导航栏不遮挡卡片，放大字体和固定导航也能完整排版', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('外观与阅读'));
    await tester.pumpAndSettle();
    for (final scale in [1.0, 1.6]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      for (final floating in [true, false]) {
        store.preferences.floatingNavigation = floating;
        await store.savePreferences();
        await tester.pumpAndSettle();
        final card = find
            .ancestor(
              of: find.text('知识属于你，记忆也是。'),
              matching: find.byType(Container),
            )
            .first;
        final bar = floating
            ? find.byType(NavigationDock).last
            : find.byType(NavigationBar).last;
        expect(
          tester.getRect(card).bottom,
          lessThanOrEqualTo(tester.getRect(bar).top),
          reason: '字号 $scale、悬浮 $floating 时卡片不应与导航栏相交',
        );
        expect(tester.takeException(), isNull);
      }
    }
  });
}
