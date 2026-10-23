import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerScrollEvent;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openmarkji/algorithms/mmx.dart';
import 'package:openmarkji/data/app_updates.dart';
import 'package:openmarkji/data/app_store.dart';
import 'package:openmarkji/data/database.dart';
import 'package:openmarkji/data/diagnostics.dart';
import 'package:openmarkji/domain/entities.dart';
import 'package:openmarkji/ui/app.dart';
import 'package:openmarkji/ui/content_view.dart';
import 'package:openmarkji/ui/glass/liquid_glass.dart';
import 'package:openmarkji/ui/glass/navigation_dock.dart';
import 'package:openmarkji/ui/glass/popup.dart';

final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

// 挂起真实的异步读写，让拖拽中的加载闪帧和写入前回跳可稳定复现。
class _InteractionStore extends AppStore {
  _InteractionStore(super.db) : super(loadOfficialDecks: false);
  int countQueries = 0, sessionQueries = 0;
  Completer<void>? countGate, reorderGate, bulkGate, cardsGate, gradeGate;
  int bulkCalls = 0, gradeCalls = 0;
  bool failBulk = false;
  final reorderGates = <Completer<void>>[];
  @override
  Future<Map<String, int>> counts(String deckId) async {
    countQueries++;
    await countGate?.future;
    return super.counts(deckId);
  }

  @override
  Future<void> reorderDecks(List<String> ids) async {
    final gate = reorderGates.isEmpty ? reorderGate : reorderGates.removeAt(0);
    await gate?.future;
    await super.reorderDecks(ids);
  }

  @override
  Future<PracticeSession?> practiceSession() {
    sessionQueries++;
    return super.practiceSession();
  }

  @override
  Future<void> bulkUpdate(
    Iterable<String> ids,
    Map<String, dynamic> values,
  ) async {
    bulkCalls++;
    await bulkGate?.future;
    if (failBulk) throw StateError('模拟写入失败');
    await super.bulkUpdate(ids, values);
  }

  @override
  Future<List<StudyCard>> cards({
    required String deckId,
    String search = '',
    String? chapter,
    String? plan,
    String? tag,
    String? focus,
    bool randomOrder = false,
    int offset = 0,
    int limit = 60,
  }) async {
    await cardsGate?.future;
    return super.cards(
      deckId: deckId,
      search: search,
      chapter: chapter,
      plan: plan,
      tag: tag,
      focus: focus,
      randomOrder: randomOrder,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<void> grade(
    RecallGrade grade, {
    required int elapsedMs,
    DateTime? at,
  }) async {
    gradeCalls++;
    await gradeGate?.future;
    await super.grade(grade, elapsedMs: elapsedMs, at: at);
  }
}

void main() {
  late AppStore store;
  setUp(() async {
    store = AppStore(
      AppDatabase(NativeDatabase.memory()),
      loadOfficialDecks: false,
    );
    await store.initialize(legacy: {});
  });
  tearDown(() async {
    store.dispose();
    await store.db.close();
  });

  Future<_InteractionStore> observedStore() async {
    store.dispose();
    await store.db.close();
    final observed = _InteractionStore(AppDatabase(NativeDatabase.memory()));
    store = observed;
    await store.initialize(legacy: {});
    return observed;
  }

  testWidgets('拖拽原位释放和异步保存期间每帧保持牌组高度、计数和目标顺序', (tester) async {
    final observed = await observedStore();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final id in ['a', 'b', 'c']) {
      await store.putDeck(DeckData(id: id, name: '稳定$id'));
    }
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    Finder tile(String id) => find
        .ancestor(of: find.text('稳定$id'), matching: find.byType(InkWell))
        .first;
    final height = tester.getSize(tile('a')).height;
    final initialY = tester.getTopLeft(tile('a')).dy;
    final countQueries = observed.countQueries;
    observed.countGate = Completer<void>();
    observed.reorderGate = Completer<void>();
    addTearDown(() {
      if (!observed.countGate!.isCompleted) observed.countGate!.complete();
      if (!observed.reorderGate!.isCompleted) observed.reorderGate!.complete();
    });

    void stableFrame() {
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.getSize(tile('a')).height, height);
      expect(find.textContaining('0 张卡片'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    }

    final start = tester.getCenter(tile('a'));
    final stationary = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600));
    stableFrame();
    await stationary.moveBy(const Offset(0, 24));
    await tester.pump(const Duration(milliseconds: 100));
    await stationary.moveTo(start);
    await stationary.up();
    for (var frame = 0; frame < 25; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      stableFrame();
    }
    expect(tester.getTopLeft(tile('a')).dy, initialY);
    expect(observed.countQueries, countQueries);

    final target = tester.getBottomLeft(tile('c')).dy + 20;
    final moving = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600));
    for (var step = 1; step <= 14; step++) {
      await moving.moveTo(
        Offset.lerp(start, Offset(start.dx, target), step / 14)!,
      );
      await tester.pump(const Duration(milliseconds: 40));
      stableFrame();
    }
    expect(observed.countQueries, countQueries);
    await moving.up();
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      stableFrame();
      expect(
        tester.getTopLeft(tile('a')).dy,
        greaterThan(tester.getTopLeft(tile('b')).dy),
      );
    }
    // 写入仍被挂起时，界面已经稳定停在新位置。
    expect((await store.decks()).map((d) => d.id), ['a', 'b', 'c']);
    observed.reorderGate!.complete();
    await tester.pumpAndSettle();
    observed.countGate!.complete();
    await tester.pumpAndSettle();
    expect((await store.decks()).map((d) => d.id), ['b', 'c', 'a']);
    stableFrame();

    // 第一笔写入尚未完成就拖回原顺序，旧写入的刷新不能覆盖第二次落点。
    final firstWrite = Completer<void>(), secondWrite = Completer<void>();
    observed.reorderGates.addAll([firstWrite, secondWrite]);
    addTearDown(() {
      if (!firstWrite.isCompleted) firstWrite.complete();
      if (!secondWrite.isCompleted) secondWrite.complete();
    });
    Future<void> dragA(double targetY) async {
      final origin = tester.getCenter(tile('a'));
      final gesture = await tester.startGesture(origin);
      await tester.pump(const Duration(milliseconds: 600));
      for (var step = 1; step <= 14; step++) {
        await gesture.moveTo(
          Offset.lerp(origin, Offset(origin.dx, targetY), step / 14)!,
        );
        await tester.pump(const Duration(milliseconds: 40));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await dragA(tester.getTopLeft(tile('b')).dy - 20);
    await dragA(tester.getBottomLeft(tile('c')).dy + 20);
    firstWrite.complete();
    await tester.pumpAndSettle();
    expect((await store.decks()).map((d) => d.id), ['a', 'b', 'c']);
    for (var frame = 0; frame < 25; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      stableFrame();
      expect(
        tester.getTopLeft(tile('a')).dy,
        greaterThan(tester.getTopLeft(tile('c')).dy),
      );
    }
    secondWrite.complete();
    await tester.pumpAndSettle();
    expect((await store.decks()).map((d) => d.id), ['b', 'c', 'a']);
    await store.importCards('a', ['新卡']);
    await tester.pumpAndSettle();
    expect(find.textContaining('1 张卡片'), findsOneWidget);
  });

  testWidgets('专项练习切换数量、范围及随机顺序时没有加载闪帧或表单位移', (tester) async {
    final observed = await observedStore();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await store.putDeck(DeckData(id: 'practice', name: '稳定练习'));
    await store.importCards('practice', List.generate(30, (i) => '内容$i'));
    final favorite = (await store.cards(deckId: 'practice', limit: 1)).single;
    await store.setFavorite(favorite.id, true);
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('稳定练习'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('专项练习'));
    await tester.pumpAndSettle();
    final position = tester.getTopLeft(find.text('练习范围'));
    final startButton = find.widgetWithText(FilledButton, '开始新一轮练习');
    final buttonRect = tester.getRect(startButton);
    final sessionQueries = observed.sessionQueries;
    Future<void> checkFrames() async {
      for (var frame = 0; frame < 35; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.getTopLeft(find.text('练习范围')), position);
        expect(tester.getRect(startButton), buttonRect);
        expect(tester.takeException(), isNull);
      }
    }

    await tester.tap(find.text('20 张'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 张'));
    await checkFrames();
    await tester.pumpAndSettle();
    expect(find.textContaining('本轮将练习 10 张卡片'), findsOneWidget);
    await tester.tap(find.text('全部卡片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏卡片'));
    await checkFrames();
    await tester.pumpAndSettle();
    expect(find.textContaining('本轮将练习 1 张卡片'), findsOneWidget);
    await tester.tap(find.text('收藏卡片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最近难卡'));
    await checkFrames();
    await tester.pumpAndSettle();
    expect(find.textContaining('当前范围没有卡片'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await checkFrames();
    expect(observed.sessionQueries, sessionQueries);
  });

  testWidgets('长按牌组拖到末尾、向上和原地松开，筛选排序保留其他牌组位置', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final id in ['a', 'hidden', 'b', 'c']) {
      await store.putDeck(
        DeckData(id: id, name: '牌组$id', group: id == 'hidden' ? '其他' : '测试'),
      );
    }
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试'));
    await tester.pumpAndSettle();

    Future<void> move(String from, String to, {bool below = false}) async {
      final start = tester.getCenter(find.text('牌组$from'));
      final target = tester.getRect(
        find.ancestor(
          of: find.text('牌组$to'),
          matching: find.byType(ReorderableDelayedDragStartListener),
        ),
      );
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 600));
      final end = Offset(
        start.dx,
        below ? target.bottom + 20 : target.top - 20,
      );
      for (var step = 1; step <= 12; step++) {
        await gesture.moveTo(Offset.lerp(start, end, step / 12)!);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await move('a', 'c', below: true);
    expect((await store.decks()).map((d) => d.id), ['b', 'hidden', 'c', 'a']);
    await move('a', 'b');
    expect((await store.decks()).map((d) => d.id), ['a', 'hidden', 'b', 'c']);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('牌组b')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();
    expect((await store.decks()).map((d) => d.id), ['a', 'hidden', 'b', 'c']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('牌组长按拖到屏幕边缘会继续滚动长列表', (tester) async {
    tester.view.physicalSize = const Size(390, 668);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (var i = 0; i < 10; i++) {
      await store.putDeck(DeckData(id: '$i', name: '长列表$i'));
    }
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    final start = tester.getCenter(find.text('长列表0'));
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600));
    for (var step = 1; step <= 12; step++) {
      await gesture.moveTo(
        Offset.lerp(start, Offset(start.dx, 650), step / 12)!,
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scroll.offset, greaterThan(100));
    await gesture.up();
    await tester.pumpAndSettle();
    expect((await store.decks()).first.id, isNot('0'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('官方牌组菜单没有删除入口，自建牌组保留删除', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await store.putDeck(DeckData(id: 'official-cet4', name: '官方测试'));
    await store.putDeck(DeckData(id: 'custom', name: '自建测试'));
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('官方测试'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多操作').first);
    await tester.pumpAndSettle();
    expect(find.text('新建章节'), findsOneWidget);
    expect(find.text('删除牌组'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自建测试'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多操作').first);
    await tester.pumpAndSettle();
    expect(find.text('删除牌组'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
  testWidgets('今日与累计用时分开，长数值等高对齐，学习月历按星期排布并可翻月', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final now = DateTime.now();
    for (final (id, date, elapsed) in [
      ('today', now, 60000),
      ('yesterday', now.subtract(const Duration(days: 1)), 200000000000),
    ]) {
      await store.db.customStatement(
        'INSERT INTO practice_activity VALUES (?,?,?)',
        [id, date.millisecondsSinceEpoch, elapsed],
      );
    }
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('今日学习时间 · 1 分 0 秒'), findsOneWidget);
    await tester.tap(find.text('统计').last);
    await tester.pumpAndSettle();
    final vertical = find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('累计学习时间'),
      300,
      scrollable: vertical,
    );
    await tester.pumpAndSettle();
    expect(find.text('55555:34'), findsOneWidget);
    final metrics = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_Metric',
    );
    expect(metrics, findsNWidgets(3));
    final numbers = ['0', '—', '55555:34']
        .map(
          (value) => find.descendant(of: metrics, matching: find.text(value)),
        )
        .toList();
    final fontSize = tester.widget<Text>(numbers.first).style!.fontSize;
    for (final number in numbers) {
      expect(tester.widget<Text>(number).style!.fontSize, fontSize);
      expect(
        find.ancestor(of: number, matching: find.byType(FittedBox)),
        findsNothing,
      );
    }
    final first = tester.getRect(metrics.first);
    for (var i = 1; i < 3; i++) {
      expect(tester.getRect(metrics.at(i)).top, first.top);
      expect(tester.getSize(metrics.at(i)).height, first.height);
    }
    await tester.scrollUntilVisible(
      find.byTooltip('下个月'),
      200,
      scrollable: vertical,
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, 160));
    await tester.pumpAndSettle();
    final calendar = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_StudyCalendar',
    );
    Finder date(DateTime d) => find.descendant(
      of: calendar,
      matching: find.bySemanticsLabel(RegExp('^${dayKey(d)}，')),
    );
    final firstDay = DateTime(now.year, now.month);
    final firstCell = date(firstDay);
    final weekday = find.descendant(
      of: calendar,
      matching: find.text(
        ['一', '二', '三', '四', '五', '六', '日'][firstDay.weekday - 1],
      ),
    );
    expect(
      tester.getCenter(firstCell).dx,
      closeTo(tester.getCenter(weekday).dx, .1),
    );
    final calendarSize = tester.getSize(calendar);
    await tester.tap(find.byTooltip('下个月'));
    await tester.pumpAndSettle();
    final nextMonth = DateTime(now.year, now.month + 1);
    expect(find.text('${nextMonth.year}年${nextMonth.month}月'), findsOneWidget);
    expect(tester.getSize(calendar), calendarSize);
    expect(find.text('回到本月'), findsNothing);
    await tester.tap(date(nextMonth));
    await tester.pumpAndSettle();
    expect(find.text('${nextMonth.month}月1日 · 0 次回忆 · 0 秒'), findsOneWidget);
    semantics.dispose();
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
  testWidgets('单行卡片沿选择栏拖选、回划和取消选择，边缘自动滚动', (tester) async {
    tester.view.physicalSize = const Size(390, 668);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await store.putDeck(DeckData(id: 'drag', name: '拖选测试'));
    for (var i = 0; i < 180; i++) {
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
    final list = find.byType(CustomScrollView).last;
    final controller = tester.widget<CustomScrollView>(list).controller!;
    final brush = await tester.startGesture(first);
    await brush.moveTo(Offset(first.dx, tester.getRect(list).bottom - 4));
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.offset, greaterThan(60 * 56));
    expect(
      find.byKey(const ValueKey('drag-0')),
      findsNothing,
      reason: '持续拖选跨过分页并回收起始行后，仍必须接收松手',
    );
    final count = int.parse(
      tester.widget<Text>(find.textContaining('取消 ')).data!.split(' ').last,
    );
    expect(count, greaterThan(5));
    await brush.up();
    final stopped = controller.offset;
    await tester.pump(const Duration(seconds: 1));
    expect(controller.offset, stopped);
    expect(find.text('取消 $count'), findsOneWidget);
    await tester.tap(find.text('取消 $count'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('全选筛选结果'), findsOneWidget);
    expect(controller.offset, stopped);

    // 系统取消触摸，以及第二根手指点击取消，都要立即结束自动滚动。
    for (final cancelPointer in [true, false]) {
      final next = await tester.startGesture(
        tester.getCenter(find.byType(Checkbox).hitTestable().first),
      );
      await next.moveTo(Offset(first.dx, tester.getRect(list).bottom - 4));
      await tester.pump(const Duration(milliseconds: 200));
      if (cancelPointer) {
        await next.cancel();
      } else {
        await tester.tap(find.textContaining('取消 '), pointer: 2);
      }
      final offset = controller.offset;
      await tester.pump(const Duration(seconds: 1));
      expect(controller.offset, offset);
      if (cancelPointer) {
        await tester.tap(find.textContaining('取消 '));
      } else {
        await next.moveBy(const Offset(0, -20));
        await next.up();
      }
      await tester.pumpAndSettle();
      expect(find.text('全选筛选结果'), findsOneWidget);
    }
    final footer = tester.getRect(find.text('全选筛选结果'));
    await tester.drag(list, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(find.text('写卡片').hitTestable(), findsNothing);
    expect(tester.getRect(find.text('全选筛选结果')), footer);
    final viewport = tester.getRect(list);
    final tools = find.text('写卡片', skipOffstage: false);
    final hiddenTop = tester.getTopLeft(tools).dy;
    final pull = await tester.startGesture(tester.getCenter(list));
    await pull.moveBy(const Offset(0, 24));
    await tester.pump();
    await pull.moveBy(const Offset(0, 20));
    await tester.pump();
    final partialTop = tester.getTopLeft(tools).dy;
    expect(partialTop, greaterThan(hiddenTop));
    await tester.pump(const Duration(milliseconds: 160));
    expect(tester.getTopLeft(tools).dy, partialTop, reason: '手指停住时不能自行弹出或缩回');
    await pull.moveBy(const Offset(0, -3));
    await tester.pump();
    expect(tester.getTopLeft(tools).dy, closeTo(partialTop - 3, .1));
    expect(tester.getRect(list), viewport);
    await pull.moveBy(const Offset(0, 30));
    await pull.up();
    await tester.pumpAndSettle();
    expect(find.text('写卡片').hitTestable(), findsOneWidget);

    controller.jumpTo(0);
    await tester.pumpAndSettle();
    var toolsTop = tester.getTopLeft(tools).dy;
    for (final delta in [24.0, 24.0, 24.0, -12.0, -12.0]) {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(list),
          scrollDelta: Offset(0, delta),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pump();
      toolsTop -= delta;
      expect(tester.getTopLeft(tools).dy, closeTo(toolsTop, .1));
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        tester.getTopLeft(tools).dy,
        closeTo(toolsTop, .1),
        reason: '滚轮每一格之间不能额外启动停靠动画',
      );
    }
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(tools).dy, closeTo(toolsTop, .1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统返回先退出子页面，其他主导航页先返回今日，今日才退出应用', (tester) async {
    tester.view.physicalSize = const Size(390, 668);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var exits = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') exits++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await store.putDeck(DeckData(id: 'back', name: '返回测试'));
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    for (final tab in ['牌组', '统计', '设置']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<NavigationDock>(find.byType(NavigationDock))
            .selectedIndex,
        0,
      );
      expect(exits, 0);
    }
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('返回测试'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationDock>(find.byType(NavigationDock)).selectedIndex,
      1,
    );
    expect(exits, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationDock>(find.byType(NavigationDock)).selectedIndex,
      0,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(exits, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('加入计划在玻璃按钮内收缩加载、打勾再展开，刷新不清空列表，失败保留选择', (tester) async {
    tester.view.physicalSize = const Size(390, 668);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final observed = await observedStore();
    await store.putDeck(DeckData(id: 'enroll', name: '加入测试'));
    await store.putCard(
      StudyCard(id: 'enroll-1', deckId: 'enroll', source: '待加入卡片\n---\n答案'),
    );
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入测试'));
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: find.text('全选筛选结果'),
        matching: find.byType(LiquidGlass),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('全选筛选结果'));
    await tester.pumpAndSettle();
    expect(
      find.ancestor(of: find.text('取消 1'), matching: find.byType(LiquidGlass)),
      findsOneWidget,
    );
    final progress = find.byKey(const ValueKey('enroll-progress'));
    final original = tester.getRect(progress);
    final cardRect = tester.getRect(find.byKey(const ValueKey('enroll-1')));
    observed.bulkGate = Completer<void>();
    observed.cardsGate = Completer<void>();
    addTearDown(() {
      if (!observed.bulkGate!.isCompleted) observed.bulkGate!.complete();
      if (!observed.cardsGate!.isCompleted) observed.cardsGate!.complete();
    });
    await tester.tap(find.text('加入计划'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    expect(
      tester.getRect(progress).width,
      inExclusiveRange(44, original.width),
    );
    await tester.pump(const Duration(milliseconds: 260));
    expect(tester.getSize(progress), const Size(44, 44));
    expect(tester.getRect(find.byKey(const ValueKey('enroll-1'))), cardRect);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(CircularProgressIndicator),
        matching: progress,
      ),
      findsOneWidget,
    );
    await tester.tapAt(original.center);
    await tester.pump();
    expect(observed.bulkCalls, 1);
    observed.bulkGate!.complete();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getRect(find.byKey(const ValueKey('enroll-1'))), cardRect);
      expect(find.byKey(const ValueKey('enroll-success')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    }
    observed.cardsGate!.complete();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byKey(const ValueKey('enroll-success')), findsOneWidget);
    expect(tester.getSize(progress), const Size(44, 44));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 130));
    expect(tester.getRect(progress).width, greaterThan(44));
    await tester.pumpAndSettle();
    expect(find.text('取消 1'), findsOneWidget);
    expect((await store.card('enroll-1'))!.plan, 'active');
    // 写入失败不能显示成功勾，必须保留所选卡片供重试。
    observed.failBulk = true;
    await tester.tap(find.text('加入计划'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('enroll-success')), findsNothing);
    expect(find.text('取消 1'), findsOneWidget);
    expect(find.text('加入计划'), findsOneWidget);
    observed.failBulk = false;
    observed.bulkGate = Completer<void>();
    final batch = find.byKey(const ValueKey('batch-progress'));
    final batchRect = tester.getRect(batch);
    final calls = observed.bulkCalls;
    await tester.tap(find.byTooltip('批量操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('暂停学习'));
    await tester.pump(const Duration(milliseconds: 140));
    expect(observed.bulkCalls, calls, reason: '菜单收回前不能开始写入和加载');
    expect(find.byKey(const ValueKey('batch-loading')), findsNothing);
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pump(const Duration(milliseconds: 380));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 380));
    expect(observed.bulkCalls, calls + 1);
    expect(find.byType(CommonPopupMenu), findsNothing);
    expect(find.byKey(const ValueKey('batch-loading')), findsOneWidget);
    expect(tester.getRect(batch), batchRect);
    await tester.tap(find.text('加入计划'));
    await tester.pump();
    expect(observed.bulkCalls, calls + 1, reason: '批量处理期间不能重复操作');
    observed.bulkGate!.complete();
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byKey(const ValueKey('batch-success')), findsOneWidget);
    expect(find.text('取消 1'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('全选筛选结果'), findsOneWidget);
    expect((await store.card('enroll-1'))!.plan, 'paused');
    tester.view.physicalSize = const Size(320, 668);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('评分保存期间按钮不变灰，下一张卡片与底部操作同步过渡且揭晓区不跳动', (tester) async {
    tester.view.physicalSize = const Size(390, 668);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final observed = await observedStore();
    await store.addExamples();
    final deck = (await store.decks()).single;
    await store.bulkUpdate(
      (await store.cards(deckId: deck.id)).map((c) => c.id),
      {'plan': 'active'},
    );
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始今日学习'));
    await tester.pumpAndSettle();
    final actions = find.byKey(const ValueKey('study-actions'));
    final initial = tester.getRect(actions);
    final first = tester.widget<ContentView>(find.byType(ContentView)).source;
    await tester.tap(find.text('揭晓答案'));
    await tester.pumpAndSettle();
    expect(tester.getRect(actions), initial);
    final rating = find.widgetWithText(FilledButton, '认识');
    final color = tester
        .widget<FilledButton>(rating)
        .style!
        .backgroundColor!
        .resolve({});
    observed.gradeGate = Completer<void>();
    addTearDown(() {
      if (!observed.gradeGate!.isCompleted) observed.gradeGate!.complete();
    });
    await tester.tap(rating);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.widget<FilledButton>(rating).onPressed, isNotNull);
      expect(
        tester.widget<FilledButton>(rating).style!.backgroundColor!.resolve({}),
        color,
      );
      expect(tester.getRect(actions), initial);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }
    await tester.tap(rating, warnIfMissed: false);
    expect(observed.gradeCalls, 1);
    observed.gradeGate!.complete();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (final area in actions.evaluate()) {
        final box = area.renderObject! as RenderBox;
        expect(box.localToGlobal(Offset.zero) & box.size, initial);
      }
    }
    await tester.pumpAndSettle();
    final next = tester.widget<ContentView>(find.byType(ContentView));
    expect(next.source, isNot(first));
    expect(next.revealed, isFalse);
    expect(tester.getRect(actions), initial);
    tester.view.physicalSize = const Size(320, 668);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    final enlarged = tester.getRect(actions);
    await tester.tap(find.text('揭晓答案'));
    await tester.pumpAndSettle();
    expect(tester.getRect(actions), enlarged);
    expect(tester.takeException(), isNull);
  });

  testWidgets('共享卡片可开始学习，完成后返回今日不再显示继续学习', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await store.putDeck(DeckData(id: 'limited', name: '额度已用完', newLimit: 0));
    await store.putDeck(DeckData(id: 'available', name: '还有额度', newLimit: 1));
    await store.putCard(
      StudyCard(
        id: 'shared',
        deckId: 'limited',
        source: '共享问题\n---\n答案',
        plan: 'active',
      ),
    );
    await store.db.customStatement('INSERT INTO card_decks VALUES (?,?)', [
      'shared',
      'available',
    ]);
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始今日学习'));
    await tester.pumpAndSettle();
    expect(find.text('揭晓答案'), findsOneWidget);
    await tester.tap(find.text('揭晓答案'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('认识'));
    await tester.pumpAndSettle();
    expect(find.text('今天，也进步了一点'), findsOneWidget);
    await tester.tap(find.text('回到今日'));
    await tester.pumpAndSettle();
    expect(find.text('继续学习'), findsNothing);
    expect(find.text('今天的任务已完成，让知识沉淀一下。'), findsOneWidget);
  });

  testWidgets('手机选卡、揭晓、评分、右滑撤销与重学完整链路', (tester) async {
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
    expect((await store.counts((await store.decks()).single.id))['active'], 3);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('今日').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始今日学习'));
    await tester.pumpAndSettle();
    final firstId = (await store.session())!.queue.first.cardId;
    expect(find.text('揭晓答案'), findsOneWidget);
    await tester.tap(find.text('揭晓答案'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('忘记'));
    await tester.pumpAndSettle();
    expect((await store.session())!.queue.last.stage, 'relearn');
    await tester.drag(find.byType(ContentView), const Offset(180, 0));
    await tester.pumpAndSettle();
    expect((await store.session())!.queue.first.cardId, firstId);
    expect((await store.session())!.queue.first.stage, 'new');
    expect(
      (await store.historyFor((await store.session())!.queue.first.cardId)),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('引用可预览和跳转，返回保持学习进度，编辑器可搜索插入引用', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await store.putDeck(DeckData(id: 'refs', name: '关联学习'));
    await store.putCard(
      StudyCard(
        id: 'origin',
        deckId: 'refs',
        source: '原问题 [Ref#ID/target#相关概念] [Ref#ID/missing#缺失引用]\n---\n原答案',
        plan: 'active',
      ),
    );
    await store.putCard(
      StudyCard(id: 'target', deckId: 'refs', source: '目标问题\n---\n目标答案'),
    );
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始今日学习'));
    await tester.pumpAndSettle();
    final session = (await store.session())!.toJson();
    await tester.tap(find.text('↗ 相关概念'));
    await tester.pumpAndSettle();
    expect(find.text('卡片预览'), findsOneWidget);
    expect(find.text('目标答案'), findsOneWidget);
    await tester.tap(find.text('打开卡片'));
    await tester.pumpAndSettle();
    expect(find.text('卡片详情'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('揭晓答案'), findsOneWidget);
    expect((await store.session())!.toJson(), session);
    expect(await store.historyFor('target'), isEmpty);
    await tester.tap(find.text('↗ 缺失引用'));
    await tester.pumpAndSettle();
    expect(find.text('引用的卡片不存在或已被删除。'), findsOneWidget);
    expect(find.text('打开卡片'), findsNothing);
    await tester.tap(find.byTooltip('关闭预览'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑当前卡片'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('引用卡片'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('引用卡片'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '搜索要引用的卡片'), '目标问题');
    await tester.pumpAndSettle();
    await tester.tap(find.text('目标问题 答案 目标答案'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(
      (await store.card('origin'))!.source,
      contains('[Ref#ID/target#目标问题'),
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

  testWidgets('写卡时光标在公式上弹出玻璃悬浮预览，随输入实时更新', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await store.putDeck(DeckData(id: 'd', name: '测试牌组'));
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试牌组'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('写卡片'));
    await tester.pumpAndSettle();
    final field = find.byType(TextField).last;
    await tester.tap(field);
    await tester.enterText(field, '问题 [E##x^2');
    await tester.pumpAndSettle();
    final bubble = find.byType(InlinePreview);
    expect(bubble, findsOneWidget);
    expect(tester.widget<InlinePreview>(bubble).token.body, 'x^2');
    expect(
      find.ancestor(of: bubble, matching: find.byType(LiquidGlass)),
      findsWidgets,
    );
    await tester.enterText(field, '问题 [E##x^2+y^2]');
    await tester.pumpAndSettle();
    expect(tester.widget<InlinePreview>(bubble).token.body, 'x^2+y^2');
    // 图片预览稳定显示，悬浮窗位于光标所在行上方。
    final id = await store.addMedia('dot.png', _onePixelPng);
    await tester.enterText(field, '问题\n\n\n\n\n\n[Pic#ID/$id#]');
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText).last)
        .renderEditable;
    final caret = editable.localToGlobal(
      editable
          .getLocalRectForCaret(
            TextPosition(offset: editable.text!.toPlainText().length),
          )
          .topLeft,
    );
    expect(tester.getRect(bubble).bottom, lessThan(caret.dy));
    final editor = tester.state<EditableTextState>(
      find.byType(EditableText).last,
    );
    editor.userUpdateTextEditingValue(
      const TextEditingValue(
        text: '问题 [E##x^2+y^2]',
        selection: TextSelection.collapsed(offset: 1),
      ),
      SelectionChangedCause.tap,
    );
    await tester.pumpAndSettle();
    expect(find.byType(InlinePreview), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('写卡页玻璃控件同步外观，窄屏长章节选择、草稿和保存正确', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const chapter = '一个用于验证长标题不会溢出的章节名称';
    await store.putDeck(DeckData(id: 'd', name: '测试牌组', chapters: [chapter]));
    await tester.pumpWidget(OpenMarkjiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试牌组'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('写卡片'));
    await tester.pumpAndSettle();
    for (final control in [
      find.byTooltip('选择章节'),
      find.byTooltip('预览卡片'),
      find.text('保存'),
      find.byTooltip('加粗'),
    ]) {
      expect(
        find.ancestor(of: control, matching: find.byType(LiquidGlass)),
        findsWidgets,
      );
    }
    expect(find.byType(DropdownButton<String>), findsNothing);
    store.updatePreferences((p) {
      p.dockOpacity = .35;
      p.dockBlur = 24;
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择章节'));
    await tester.pumpAndSettle();
    final menu = tester.widget<PopupMenuCard>(find.byType(PopupMenuCard));
    expect(menu.glass!.blur, 24);
    expect(menu.glass!.tint.a, closeTo(.35, .01));
    await tester.tap(find.text(chapter));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byTooltip('选择章节')).right,
      lessThanOrEqualTo(340),
    );
    await tester.enterText(find.byType(TextField).last, '问题\n---\n答案');
    await tester.pump(const Duration(milliseconds: 600));
    expect(decodeObject((await store.setting('draft:d'))!)['chapter'], chapter);
    await tester.tap(find.byTooltip('预览卡片'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回编辑'));
    await tester.pumpAndSettle();
    store.updatePreferences((p) => p.liquidGlass = 'none');
    await tester.pumpAndSettle();
    expect(find.byType(LiquidGlass), findsNothing);
    await tester.tap(find.byTooltip('选择章节'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PopupMenuCard>(find.byType(PopupMenuCard)).glass,
      isNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('写一张新卡'), findsNothing);
    expect((await store.cards(deckId: 'd')).single.source, '问题\n---\n答案');
    expect((await store.cards(deckId: 'd')).single.chapter, chapter);
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
    await tester.tap(find.byTooltip('搜索牌组或卡片'), kind: PointerDeviceKind.mouse);
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
    await tester.tap(find.byTooltip('搜索牌组或卡片'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '数学');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(title('英语'), findsOneWidget);
    await store.putCard(
      StudyCard(
        id: 'global-search',
        deckId: 'a',
        source: '如何主动回忆？\n---\n检索记忆中的答案',
        tags: ['检索练习'],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索牌组或卡片'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '记忆中的答案');
    await tester.pumpAndSettle();
    expect(find.text('牌组 · 0'), findsOneWidget);
    expect(find.text('卡片 · 1'), findsOneWidget);
    await tester.tap(find.textContaining('如何主动回忆？'));
    await tester.pumpAndSettle();
    expect(find.text('卡片详情'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '检索练习');
    await tester.pumpAndSettle();
    expect(find.text('卡片 · 1'), findsOneWidget);
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
    expect(find.widgetWithText(TextField, 'WebDAV 地址'), findsNothing);
    await tester.tap(find.text('WebDAV 备份'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'WebDAV 地址'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'WebDAV 地址'), findsNothing);
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
    await tester.pump(const Duration(milliseconds: 170));
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_RowExpandTransition',
      ),
      findsOneWidget,
    );
    // 卡片还盖着这一行时，列表里的真实行已经放回，收回结束不会露出空白。
    expect(find.text('外观与阅读').hitTestable(), findsOneWidget);
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
    await tester.tap(find.byTooltip('搜索牌组或卡片'));
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

  testWidgets('玻璃菜单从右侧值控件展开，选值后保存并收回', (tester) async {
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
    await http.runWithClient(
      () async {
        await tester.ensureVisible(find.text('检查更新'));
        await tester.tap(find.text('检查更新'));
        await tester.pumpAndSettle();
      },
      () => MockClient((request) async {
        expect(request.url.toString(), releaseFeed);
        return http.Response(
          '{"version":"$appVersion","notes":"$appDisplayVersion 更新说明","downloadUrl":"https://github.com/coffe01-10/openmarkji/releases/latest"}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    expect(find.text('当前已是最新版本'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('协议与政策'));
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
    await tester.ensureVisible(find.text('帮助与反馈'));
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
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('捕捉日志'), 200);
    await tester.tap(find.text('捕捉日志'));
    await tester.pumpAndSettle();
    final log = DiagnosticLog.instance;
    addTearDown(() {
      if (log.capturing) log.stop();
      log.clear();
    });
    await tester.ensureVisible(find.text('开始捕捉'));
    await tester.tap(find.text('开始捕捉'));
    await tester.pumpAndSettle();
    expect(log.capturing, isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('捕捉日志'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('停止捕捉'));
    await tester.tap(find.text('停止捕捉'));
    await tester.pumpAndSettle();
    expect(log.capturing, isFalse);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = call.arguments['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.ensureVisible(find.text('复制日志'));
    await tester.tap(find.text('复制日志'));
    await tester.pumpAndSettle();
    expect(copied, contains('日志 | 开始捕捉'));
    expect(copied, contains('页面 | 进入 捕捉日志'));
    expect(copied, contains('状态：已停止'));
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
