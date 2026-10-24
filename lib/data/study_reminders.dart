import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Android 负责定时与发送时读取数量，应用无需常驻。
abstract final class StudyReminders {
  static const _channel = MethodChannel('openmarkji/study_reminders');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> sync() async {
    if (!supported) return;
    final directory = await getApplicationSupportDirectory();
    await _channel.invokeMethod<void>('sync', {
      'databasePath': '${directory.path}/openmarkji.sqlite',
    });
  }

  static Future<bool> isAllowed() async =>
      supported && (await _channel.invokeMethod<bool>('isAllowed'))!;

  static Future<bool> requestPermission() async =>
      supported && (await _channel.invokeMethod<bool>('requestPermission'))!;

  static Future<void> openSettings() async {
    if (supported) await _channel.invokeMethod<void>('openSettings');
  }

  static Future<bool> preview() async =>
      supported && (await _channel.invokeMethod<bool>('preview'))!;
}
