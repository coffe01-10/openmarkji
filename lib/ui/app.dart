import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import '../algorithms/mmx.dart';
import '../content/markji.dart';
import '../data/app_store.dart';
import '../data/app_updates.dart';
import '../data/file_export.dart' as file_export;
import '../domain/entities.dart';
import '../domain/statistics.dart';
import 'content_view.dart';
import 'flclash/liquid_glass.dart';
import 'flclash/navigation_dock.dart';
import 'flclash/popup.dart';
part 'design.dart';
part 'home.dart';
part 'library.dart';
part 'editor.dart';
part 'study.dart';
part 'settings.dart';
part 'appearance.dart';
part 'support.dart';
part 'practice.dart';
part 'learning_settings.dart';
part 'statistics.dart';

class OpenMarkjiApp extends StatelessWidget {
  const OpenMarkjiApp({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => DynamicColorBuilder(
      builder: (light, dark) {
        final p = store.preferences;
        ThemeData theme(Brightness brightness, ColorScheme? dynamicScheme) {
          final generated =
              (p.dynamicColor ? dynamicScheme : null) ??
              ColorScheme.fromSeed(
                seedColor: Color(p.color),
                brightness: brightness,
                dynamicSchemeVariant: switch (p.colorStyle) {
                  'vibrant' => DynamicSchemeVariant.vibrant,
                  'neutral' => DynamicSchemeVariant.neutral,
                  _ => DynamicSchemeVariant.tonalSpot,
                },
              );
          final scheme = p.pureBlack && brightness == Brightness.dark
              ? generated.copyWith(
                  surface: Colors.black,
                  surfaceContainerLowest: Colors.black,
                )
              : generated;
          return ThemeData(
            useMaterial3: true,
            fontFamily: p.fontFamily == 'system' ? null : p.fontFamily,
            colorScheme: scheme,
            scaffoldBackgroundColor: scheme.surfaceContainerLowest,
            textTheme: Typography.material2021().black.apply(
              bodyColor: scheme.onSurface,
              displayColor: scheme.onSurface,
              fontFamily: p.fontFamily == 'system' ? null : p.fontFamily,
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: scheme.surfaceContainerLowest,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              centerTitle: false,
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              margin: EdgeInsets.zero,
              color: scheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: scheme.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 16,
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            bottomSheetTheme: BottomSheetThemeData(
              showDragHandle: true,
              backgroundColor: scheme.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
            ),
            dividerTheme: DividerThemeData(
              color: scheme.outlineVariant.withValues(alpha: .5),
            ),
          );
        }

        return MaterialApp(
          title: 'OpenMarkji',
          debugShowCheckedModeBanner: false,
          theme: theme(Brightness.light, light),
          darkTheme: theme(Brightness.dark, dark),
          themeMode: switch (p.theme) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          home: _Shell(store: store),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                MediaQuery.textScalerOf(context).scale(1) * p.textScale,
              ),
            ),
            child: LiquidGlassScope(
              dockOpacity: p.dockOpacity,
              dockBlur: p.dockBlur,
              enabled: p.liquidGlass != 'none',
              quality: p.liquidGlass == 'standard'
                  ? LiquidGlassQuality.standard
                  : LiquidGlassQuality.ultra,
              child: LiquidGlassHost(
                enabled: p.liquidGlass != 'none',
                child: child!,
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _Shell extends StatefulWidget {
  const _Shell({required this.store});
  final AppStore store;
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _index = 0;
  int _direction = 1;
  void _select(int index) {
    if (_index == index) return;
    setState(() {
      _direction = index > _index ? 1 : -1;
      _index = index;
    });
  }

  static const labels = ['今日', '牌组', '统计', '设置'];
  static const icons = [
    Icons.wb_sunny_outlined,
    Icons.layers_outlined,
    Icons.bar_chart_rounded,
    Icons.tune_rounded,
  ];
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final pages = [
      _TodayPage(store: widget.store, onLibrary: () => _select(1)),
      _LibraryPage(store: widget.store),
      _StatsPage(store: widget.store),
      _SettingsPage(store: widget.store),
    ];
    return Scaffold(
      body: Row(
        children: [
          if (wide)
            Container(
              width: 112,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant
                        .withValues(alpha: .4),
                  ),
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 28),
                    const _BrandMark(size: 44),
                    const SizedBox(height: 40),
                    Expanded(
                      child: NavigationRail(
                        backgroundColor: Colors.transparent,
                        selectedIndex: _index,
                        onDestinationSelected: (i) => _select(i),
                        labelType: NavigationRailLabelType.all,
                        destinations: List.generate(
                          4,
                          (i) => NavigationRailDestination(
                            icon: Icon(icons[i]),
                            label: Text(labels[i]),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Text(
                        'OPEN\nMARKJI',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9,
                          height: 1.6,
                          letterSpacing: 2,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                SafeArea(
                  bottom: false,
                  child: AnimatedSwitcher(
                    duration: _duration(context, 300),
                    transitionBuilder: (child, animation) =>
                        widget.store.preferences.tabAnimation == 'fade'
                        ? FadeTransition(opacity: animation, child: child)
                        : SlideTransition(
                            position:
                                Tween<Offset>(
                                  begin: Offset(
                                    (child.key == ValueKey(_index) ? 1 : -1) *
                                        _direction.toDouble(),
                                    0,
                                  ),
                                  end: Offset.zero,
                                ).animate(
                                  CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.fastOutSlowIn,
                                  ),
                                ),
                            child: child,
                          ),
                    child: KeyedSubtree(
                      key: ValueKey(_index),
                      child: pages[_index],
                    ),
                  ),
                ),
                if (!wide)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: widget.store.preferences.floatingNavigation
                        ? NavigationDock(
                            destinations: _navigationDestinations,
                            selectedIndex: _index,
                            onSelected: _select,
                          )
                        : NavigationBar(
                            selectedIndex: _index,
                            onDestinationSelected: _select,
                            destinations: [
                              for (var i = 0; i < labels.length; i++)
                                NavigationDestination(
                                  icon: Icon(icons[i]),
                                  label: labels[i],
                                ),
                            ],
                          ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        112 + MediaQuery.paddingOf(context).bottom,
      ),
    ),
  );
}

Future<void> _action(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) _toast(context, '$e');
  }
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String detail,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确认'),
          ),
        ],
      ),
    ) ??
    false;
Future<String?> _textPrompt(
  BuildContext context,
  String title, {
  String initial = '',
  String hint = '',
}) async {
  final ctrl = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(c, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(c, ctrl.text.trim()),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  Future.delayed(const Duration(milliseconds: 350), ctrl.dispose);
  return result;
}

Duration _duration(BuildContext context, int ms) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: ms);
String _short(String source, [int max = 80]) {
  final text = MarkjiParser()
      .parse(source)
      .plainText
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text.length > max ? '${text.substring(0, max)}…' : text;
}

String _dateLabel(DateTime? date) =>
    date == null ? '尚未学习' : '${date.month}月${date.day}日';
