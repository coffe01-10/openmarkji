import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openmarkji/data/app_updates.dart';
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

  testWidgets('三个统计视图支持切换和日周月，窄屏大字体零数据不溢出', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('统计').last);
    await tester.pumpAndSettle();
    expect(find.text('你的学习遗忘曲线'), findsOneWidget);
    expect(find.text('LEARNING INSIGHTS'), findsNothing);
    expect(find.text('看见每一份积累'), findsNothing);
    expect(find.text('艾宾浩斯遗忘曲线'), findsOneWidget);
    expect(find.text('完成首次学习后显示你的个人曲线。'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel(RegExp('^今天，')))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    semantics.dispose();
    Future<void> select(String label) async {
      await tester.drag(find.byType(ListView).first, const Offset(0, 1600));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
    }

    await select('学习情况');
    expect(find.text('认知情况'), findsOneWidget);
    await select('周');
    final horizontal = find.byType(SingleChildScrollView).first;
    await tester.ensureVisible(horizontal);
    await tester.pumpAndSettle();
    final offsetBeforeDrag = tester
        .widget<SingleChildScrollView>(horizontal)
        .controller!
        .offset;
    await tester.drag(
      horizontal,
      const Offset(-180, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<SingleChildScrollView>(horizontal).controller!.offset,
      greaterThan(offsetBeforeDrag),
    );
    final scroller = tester
        .widget<SingleChildScrollView>(horizontal)
        .controller!;
    final now = DateTime.now();
    final index = ((scroller.offset + 80) / (46 * 1.6)).floor();
    final date = DateTime(
      now.year,
      now.month,
      now.day - now.weekday + 1 + (index - 8) * 7,
    );
    await tester.tapAt(tester.getTopLeft(horizontal) + const Offset(80, 100));
    await tester.pumpAndSettle();
    expect(
      find.text(index == 8 ? '本周' : '${date.month}/${date.day}周'),
      findsOneWidget,
    );
    await select('复习新学');
    expect(find.text('新学'), findsOneWidget);
    await select('记忆持久度');
    expect(find.text('记忆持久度 ≥ 90 天'), findsOneWidget);
    await select('月');
    expect(tester.takeException(), isNull);
  });
  testWidgets('状态栏区域延续页面背景，标题避让安全区，浅深色和二级页系统栏同步', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 36, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 36, bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();

    void verifyBars(Brightness icons) {
      final style = SystemChrome.latestStyle!;
      expect(style.statusBarColor, Colors.transparent);
      expect(style.systemStatusBarContrastEnforced, isFalse);
      expect(style.statusBarIconBrightness, icons);
      expect(style.systemNavigationBarColor, Colors.transparent);
      expect(style.systemNavigationBarIconBrightness, icons);
      expect(style.systemNavigationBarContrastEnforced, isFalse);
    }

    for (final dark in [false, true]) {
      store.updatePreferences((p) {
        p.theme = dark ? 'dark' : 'light';
        p.pureBlack = dark;
      });
      await tester.pumpAndSettle();
      final settings = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_SettingsPage',
      );
      final canvas = find
          .descendant(of: settings, matching: find.byType(ColoredBox))
          .first;
      expect(
        tester.getTopLeft(canvas).dy,
        0,
        reason: '背景必须覆盖状态栏，不能被外层 SafeArea 推到状态栏下方',
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('pinned-backdrop-设置'))).dy,
        0,
      );
      if (dark) expect(tester.widget<ColoredBox>(canvas).color, Colors.black);
      final title = find.byKey(const ValueKey('pinned-heading-设置'));
      final titlePosition = tester.getTopLeft(title);
      expect(titlePosition.dy, greaterThanOrEqualTo(36));
      verifyBars(dark ? Brightness.light : Brightness.dark);
      await tester.drag(
        find.descendant(of: settings, matching: find.byType(ListView)).first,
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(title), titlePosition);
      await tester.ensureVisible(find.text('关于'));
      await tester.tap(find.text('关于'));
      await tester.pumpAndSettle();
      verifyBars(dark ? Brightness.light : Brightness.dark);
      expect(tester.getTopLeft(find.byType(AppBar)).dy, 0);
      await tester.pageBack();
      await tester.pumpAndSettle();
      verifyBars(dark ? Brightness.light : Brightness.dark);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('内容滚动后标题保持原位，顶栏遮罩平滑衰减到透明', (tester) async {
    tester.view.physicalSize = const Size(390, 668);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('统计').last);
    await tester.pumpAndSettle();
    final title = find.byKey(const ValueKey('pinned-heading-统计'));
    final originalPosition = tester.getTopLeft(title);
    LinearGradient headerGradient() =>
        (tester
                        .widget<DecoratedBox>(
                          find
                              .descendant(
                                of: find.byKey(
                                  const ValueKey('pinned-backdrop-统计'),
                                ),
                                matching: find.byType(DecoratedBox),
                              )
                              .first,
                        )
                        .decoration
                    as BoxDecoration)
                .gradient!
            as LinearGradient;
    final gradient = headerGradient();
    expect(gradient.colors.first.a, closeTo(.9, .01));
    expect(gradient.colors.last.a, 0);
    for (var i = 1; i < gradient.colors.length; i++) {
      expect(gradient.colors[i].a, lessThanOrEqualTo(gradient.colors[i - 1].a));
    }
    await tester.drag(find.byType(ListView).first, const Offset(0, -340));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title), originalPosition);
    expect(headerGradient(), gradient);
    expect(tester.takeException(), isNull);
  });

  testWidgets('工具栏组合按钮一起弹动，返回和菜单共用玻璃组件', (tester) async {
    tester.view.physicalSize = const Size(390, 668);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await store.addExamples();
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();

    Future<void> verifyGroup(Finder first, Finder second) async {
      final press = find.ancestor(
        of: first,
        matching: find.byType(ElasticPress),
      );
      final siblingPress = find.ancestor(
        of: second,
        matching: find.byType(ElasticPress),
      );
      expect(press, findsOneWidget);
      expect(siblingPress, findsOneWidget);
      expect(tester.state(press), same(tester.state(siblingPress)));
      Offset paintedCenter(Finder finder) {
        final box = tester.renderObject<RenderBox>(finder);
        return box.localToGlobal(ElasticPress.paintBoundsOf(box).center);
      }

      final beforeFirst = paintedCenter(first);
      final beforeSecond = paintedCenter(second);
      final gesture = await tester.startGesture(tester.getCenter(first));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 400));
      final dy = paintedCenter(first).dy - beforeFirst.dy;
      expect(dy, greaterThan(4));
      expect(paintedCenter(second).dy - beforeSecond.dy, closeTo(dy, .1));
      await gesture.cancel();
      await tester.pumpAndSettle();
    }

    await verifyGroup(find.byTooltip('刷新牌组'), find.byTooltip('新建牌组'));
    final searchPress = find.ancestor(
      of: find.byTooltip('搜索牌组'),
      matching: find.byType(ElasticPress),
    );
    final actionsPress = find.ancestor(
      of: find.byTooltip('刷新牌组'),
      matching: find.byType(ElasticPress),
    );
    expect(tester.state(searchPress), isNot(same(tester.state(actionsPress))));
    expect(tester.getSize(find.byTooltip('搜索牌组')), const Size(44, 44));
    expect(tester.getSize(actionsPress).width, 88);
    await tester.tap(find.text('记忆的起点'));
    await tester.pumpAndSettle();
    await verifyGroup(find.byTooltip('专项练习'), find.byTooltip('牌组设置'));
    final practicePress = find.ancestor(
      of: find.byTooltip('专项练习'),
      matching: find.byType(ElasticPress),
    );
    final morePress = find.ancestor(
      of: find.byTooltip('更多操作').first,
      matching: find.byType(ElasticPress),
    );
    expect(tester.state(morePress), isNot(same(tester.state(practicePress))));
    expect(tester.getSize(find.byTooltip('更多操作').first), const Size(44, 44));
    expect(
      find.ancestor(
        of: find.byTooltip('按章节筛选'),
        matching: find.byType(LiquidGlass),
      ),
      findsWidgets,
    );
    await tester.tap(find.textContaining('微积分').first);
    await tester.pumpAndSettle();
    await verifyGroup(find.byTooltip('收藏卡片'), find.byTooltip('编辑卡片'));
    expect(
      find.descendant(
        of: find.widgetWithIcon(IconButton, Icons.arrow_back_rounded),
        matching: find.byType(LiquidGlass),
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('分段栏按住浮起导航同款玻璃透镜，拖动松开确认，取消与纵向滑动不误切换', (tester) async {
    final semantics = tester.ensureSemantics();
    await store.addExamples();
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    final bar = find.ancestor(
      of: find.text('全部'),
      matching: find.byType(FloatingNavigationBar),
    );
    final panes = find.descendant(of: bar, matching: find.byType(LiquidGlass));
    final resting = panes.evaluate().length;
    final all = tester.getCenter(find.text('全部'));
    final example = tester.getCenter(find.text('示例'));
    bool selected(String label) =>
        tester
            .getSemantics(find.bySemanticsLabel(label).first)
            .getSemanticsData()
            .flagsCollection
            .isSelected
            .toBoolOrNull() ==
        true;
    final gesture = await tester.startGesture(all);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      panes.evaluate().length,
      greaterThan(resting),
      reason: '按住时必须出现实际折射透镜',
    );
    await gesture.moveTo(example);
    await tester.pump(const Duration(milliseconds: 100));
    expect(selected('全部'), isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected('示例'), isTrue);
    final cancel = await tester.startGesture(
      example,
      kind: PointerDeviceKind.mouse,
    );
    await cancel.moveTo(all);
    await cancel.cancel();
    await tester.pumpAndSettle();
    expect(selected('示例'), isTrue);
    final vertical = await tester.startGesture(all);
    await vertical.moveBy(const Offset(0, 80));
    await vertical.up();
    await tester.pumpAndSettle();
    expect(selected('示例'), isTrue);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部').first);
    await tester.pumpAndSettle();
    expect(selected('全部'), isTrue);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
  testWidgets('搜索玻璃从图标原位连续延展，收回时沿原路径合拢', (tester) async {
    tester.view.physicalSize = const Size(390, 668);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    final pane = find.byKey(const ValueKey('search-morph-pane'));
    final original = tester.getRect(pane);
    expect(original.width, 44);
    await tester.tap(find.byTooltip('搜索牌组'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final expanding = tester.getRect(pane);
    expect(expanding.width, greaterThan(original.width));
    expect(expanding.left, lessThan(original.left));
    await tester.pumpAndSettle();
    final expanded = tester.getRect(pane);
    expect(expanding.width, lessThan(expanded.width));
    expect(expanded.left, 24);
    expect(expanded.height, 44);
    expect(tester.getCenter(find.byTooltip('关闭搜索')).dy, expanded.center.dy);
    expect(tester.getCenter(find.byTooltip('搜索牌组')).dy, expanded.center.dy);
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    expect(
      editable.localToGlobal(editable.size.center(Offset.zero)).dy,
      closeTo(expanded.center.dy, 1),
      reason: '输入文字应与搜索图标和关闭按钮共用垂直中心',
    );
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getRect(pane).width, lessThan(expanded.width));
    expect(tester.getRect(pane).width, greaterThan(original.width));
    await tester.pumpAndSettle();
    expect(tester.getRect(pane), original);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('单行卡片沿选择栏拖选、回划和取消选择，边缘自动滚动', (tester) async {
    tester.view.physicalSize = const Size(390, 668);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await store.putDeck(DeckData(id: 'drag', name: '拖选测试'));
    for (var i = 0; i < 24; i++) {
      await store.putCard(
        StudyCard(
          id: 'drag-$i',
          deckId: 'drag',
          source: '卡片预览 $i：较长的文字也始终只占一行\n---\n答案',
        ),
      );
    }
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('拖选测试'));
    await tester.pumpAndSettle();
    final plan = tester.getRect(find.text('全部'));
    for (final label in ['未加入', '计划内', '暂停']) {
      final option = tester.getRect(find.text(label));
      expect(option.center.dy, plan.center.dy);
      expect(option.right, lessThanOrEqualTo(370));
    }
    expect(tester.getRect(find.text('收藏')).top, greaterThan(plan.bottom));
    expect(tester.getSize(find.byKey(const ValueKey('drag-0'))).height, 56);
    expect(tester.widget<Text>(find.textContaining('卡片预览 0：')).maxLines, 1);
    final first = tester.getCenter(find.byType(Checkbox).at(0));
    final second = tester.getCenter(find.byType(Checkbox).at(1));
    final third = tester.getCenter(find.byType(Checkbox).at(2));
    final gesture = await tester.startGesture(first);
    await gesture.moveTo(third);
    await tester.pump();
    expect(find.text('取消 3'), findsOneWidget);
    expect(
      tester.getCenter(find.byType(Checkbox).at(0)),
      first,
      reason: '开始拖选不能推移列表',
    );
    await gesture.moveTo(second);
    await tester.pump();
    expect(find.text('取消 2'), findsOneWidget);
    await gesture.moveTo(third);
    await gesture.up();
    await tester.pumpAndSettle();
    final deselect = await tester.startGesture(first);
    await deselect.moveTo(third);
    await deselect.up();
    await tester.pumpAndSettle();
    expect(find.text('全选筛选结果'), findsOneWidget);
    final list = find.byType(ListView).last;
    final controller = tester.widget<ListView>(list).controller!;
    final brush = await tester.startGesture(first);
    await brush.moveTo(Offset(first.dx, tester.getRect(list).bottom - 4));
    await tester.pump(const Duration(milliseconds: 700));
    expect(controller.offset, greaterThan(100));
    final count = int.parse(
      tester.widget<Text>(find.textContaining('取消 ')).data!.split(' ').last,
    );
    expect(count, greaterThan(5));
    await brush.up();
    await tester.pumpAndSettle();
    final stopped = controller.offset;
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.offset, stopped);
    expect(tester.takeException(), isNull);
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
    await tester.tap(find.text('收藏'));
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
    await tester.tap(find.text('收藏'));
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

  testWidgets('返回按钮下拉超出工具栏时，绘制区域不被工具栏裁掉', (tester) async {
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
    final back = find.widgetWithIcon(IconButton, Icons.arrow_back_rounded);
    final gesture = await tester.startGesture(tester.getCenter(back));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, 70));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 400));
    final box = tester.renderObject<RenderBox>(back);
    final painted = ElasticPress.paintBoundsOf(box);
    expect(
      box.localToGlobal(painted.bottomCenter).dy,
      greaterThan(tester.getRect(find.byType(AppBar)).bottom),
    );
    RenderObject child = box;
    for (var parent = box.parent; parent != null; parent = parent.parent) {
      if (parent is RenderClipRect) {
        final clip = parent.describeApproximatePaintClip(child);
        if (clip != null) {
          final bounds = MatrixUtils.transformRect(
            box.getTransformTo(parent),
            painted,
          );
          expect(
            clip.contains(bounds.bottomCenter - const Offset(0, 1)),
            isTrue,
            reason: '弹性按钮拖出工具栏后应完整显示',
          );
        }
      }
      child = parent;
    }
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('学习偏好选择算法，可统一应用并用于新建牌组', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await store.putDeck(DeckData(id: 'old', name: '旧牌组'));
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('学习偏好'));
    await tester.pumpAndSettle();
    expect(find.text('学习计划卡片数'), findsOneWidget);
    expect(find.text('平均每天新学卡片数'), findsOneWidget);
    expect(find.text('平均每天复习卡片数'), findsOneWidget);
    await tester.tap(find.text('MMX-6.0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MMX-5.0'));
    await tester.pumpAndSettle();
    expect(store.preferences.defaultAlgorithm, 5);
    expect((await store.deck('old'))!.algorithm, 6);
    await tester.tap(find.text('全部牌组使用 MMX-5'));
    await tester.pumpAndSettle();
    expect((await store.deck('old'))!.algorithm, 5);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建牌组'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '牌组名称'), '新算法牌组');
    await tester.ensureVisible(find.text('保存牌组'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存牌组'));
    await tester.pumpAndSettle();
    expect((await store.decks()).last.algorithm, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('独立搜索图标展开输入并聚焦，支持清空、关闭与 Escape', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Finder title(String value) => find.byWidgetPredicate(
      (widget) => widget is Text && widget.data == value,
    );
    await store.putDeck(DeckData(id: 'a', name: '英语'));
    await store.putDeck(DeckData(id: 'b', name: '数学'));
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('刷新牌组'));
    await tester.pumpAndSettle();
    expect(find.text('牌组已刷新'), findsOneWidget);
    await tester.tap(find.byTooltip('搜索牌组'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
    await tester.enterText(find.byType(TextField), '数学');
    await tester.pumpAndSettle();
    expect(title('英语'), findsNothing);
    expect(title('数学'), findsOneWidget);
    await store.putDeck(DeckData(id: 'c', name: '数学补充'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '数学',
    );
    expect(title('英语'), findsNothing);
    expect(title('数学补充'), findsOneWidget);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(title('英语'), findsOneWidget);
    store.preferences.liquidGlass = 'none';
    await store.savePreferences();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '英语');
    await tester.pumpAndSettle();
    expect(title('数学'), findsNothing);
    expect(title('英语'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(title('数学'), findsOneWidget);
    expect(find.byTooltip('刷新牌组'), findsOneWidget);
    await tester.tap(find.byTooltip('搜索牌组'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '数学');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(title('英语'), findsOneWidget);
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

  testWidgets('设置展开未完成时点另一行会立刻反向切换', (tester) async {
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();

    Finder row(String title) => find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.data == title &&
          widget.style?.fontWeight == FontWeight.w500,
    );

    Future<void> interrupt(String from, String to) async {
      await tester.tap(row(from));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(row(to), findsOneWidget);
      await tester.tap(row(to));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.allWidgets
            .whereType<Text>()
            .where((text) => text.data == to)
            .length,
        greaterThanOrEqualTo(2),
      );
    }

    await interrupt('外观与阅读', '学习偏好');
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(row('卡片与交互'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester.allWidgets
          .whereType<Text>()
          .where((text) => text.data == '卡片与交互')
          .length,
      greaterThanOrEqualTo(2),
    );
    await tester.pumpAndSettle();
    expect(find.text('学习触感反馈'), findsOneWidget);
    expect(find.text('主题模式'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('固定导航下玻璃质感可调，滑块实时同步切换栏、按钮、搜索和菜单', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    store.preferences.floatingNavigation = false;
    await store.addExamples();
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('外观与阅读'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('背景模糊'), 250);
    expect(find.text('全局玻璃质感'), findsOneWidget);

    Slider slider(String title) => tester.widget<Slider>(
      find.descendant(
        of: find.ancestor(
          of: find.text(title),
          matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_PreferenceSlider',
          ),
        ),
        matching: find.byType(Slider),
      ),
    );
    final revision = store.revision;
    expect(slider('透明度').onChanged, isNotNull);
    slider('透明度').onChanged!(.75);
    slider('背景模糊').onChanged!(24);
    await tester.pumpAndSettle();
    final scope = tester.widget<LiquidGlassScope>(
      find.byType(LiquidGlassScope).first,
    );
    expect(scope.dockOpacity, .25, reason: '拖动中全局范围也更新，不能只改本页预览');
    expect(scope.dockBlur, 24);
    expect(store.revision, revision, reason: '预览不触发学习数据重新查询');

    void verifyMaterial() {
      final surfaces = tester
          .widgetList<LiquidGlass>(find.byType(LiquidGlass))
          .where((pane) => pane.style.refraction == 60);
      expect(surfaces, isNotEmpty);
      for (final pane in surfaces) {
        expect(pane.style.tint.a, closeTo(.25, .01));
        expect(pane.style.blur, 24);
      }
    }

    verifyMaterial();
    slider('背景模糊').onChangeEnd!(24);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    verifyMaterial();
    await tester.tap(find.byTooltip('搜索牌组'));
    await tester.pumpAndSettle();
    verifyMaterial();
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记忆的起点'));
    await tester.pumpAndSettle();
    verifyMaterial();
    await tester.tap(find.byTooltip('按章节筛选'));
    await tester.pumpAndSettle();
    final menus = tester.widgetList<PopupMenuCard>(find.byType(PopupMenuCard));
    expect(menus, isNotEmpty);
    for (final menu in menus) {
      expect(menu.glass!.tint.a, closeTo(.25, .01));
      expect(menu.glass!.blur, 24);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    store.updatePreferences((p) => p.liquidGlass = 'none');
    await tester.pumpAndSettle();
    expect(find.byType(LiquidGlass), findsNothing);
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
    expect(find.textContaining('尚未配置更新源'), findsNothing);
    await http.runWithClient(
      () async {
        await tester.tap(find.widgetWithText(FilledButton, '检查更新'));
        await tester.pumpAndSettle();
      },
      () => MockClient((request) async {
        expect(request.url.toString(), releaseFeed);
        return http.Response(
          '{"version":"$appVersion","notes":"1.01 更新说明","downloadUrl":"https://github.com/coffe01-10/openmarkji/releases/latest"}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    expect(find.text('当前已是最新版本'), findsOneWidget);
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
