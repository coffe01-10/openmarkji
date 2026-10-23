import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app_updates.dart';

/// 用户主动开启的本次运行诊断记录，不采集卡片正文、密码或网络请求内容。
class DiagnosticLog extends ChangeNotifier {
  static final instance = DiagnosticLog();
  final _entries = ListQueue<String>();
  bool _capturing = false;
  DateTime? _started;
  int _discarded = 0;
  bool get capturing => _capturing;
  int get count => _entries.length;

  void installErrorHandlers() {
    final flutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      error(
        'Flutter / ${details.library ?? 'framework'}',
        details.exception,
        details.stack ?? StackTrace.empty,
      );
      flutterHandler?.call(details);
    };
    final platformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (exception, stack) {
      error('未处理异常', exception, stack);
      return platformHandler?.call(exception, stack) ?? false;
    };
  }

  void start() {
    _entries.clear();
    _discarded = 0;
    _started = DateTime.now();
    _capturing = true;
    event('日志', '开始捕捉');
  }

  void stop() {
    event('日志', '停止捕捉');
    _capturing = false;
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    _discarded = 0;
    notifyListeners();
  }

  void event(String category, String message) {
    if (!_capturing) return;
    // 长时间复现时只保留最近 500 条，避免诊断本身持续占用内存。
    if (_entries.length == 500) {
      _entries.removeFirst();
      _discarded++;
    }
    final safeMessage = message.replaceAllMapped(
      RegExp(r'(https?://)[^/\s@]+@'),
      (m) => '${m[1]}[已隐藏]@',
    );
    _entries.add(
      '[${DateTime.now().toIso8601String()}] $category | $safeMessage',
    );
    // 框架可能在绘制期间报告异常，预览更新放到当前同步工作之后。
    scheduleMicrotask(notifyListeners);
  }

  void error(String category, Object exception, StackTrace stack) =>
      event(category, 'ERROR $exception\n$stack');

  String get report => [
    'OpenMarkji 诊断日志',
    '版本：$appDisplayVersion ($appVersion+$appBuild)',
    '平台：${kIsWeb ? 'Web' : defaultTargetPlatform.name}',
    '语言：${PlatformDispatcher.instance.locale}',
    '显示：${PlatformDispatcher.instance.views.first.physicalSize} / DPR ${PlatformDispatcher.instance.views.first.devicePixelRatio}',
    '开始时间：${_started?.toIso8601String() ?? '未开始'}',
    '状态：${_capturing ? '捕捉中' : '已停止'}',
    if (_discarded > 0) '较早的 $_discarded 条记录已省略',
    '',
    ..._entries,
  ].join('\n');
}

class DiagnosticNavigationObserver extends NavigatorObserver {
  void _record(String action, Route<dynamic>? route) {
    if (route is PageRoute) {
      DiagnosticLog.instance.event(
        '页面',
        '$action ${route.settings.name ?? route.runtimeType}',
      );
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record('进入', route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record('返回', previousRoute);
}
