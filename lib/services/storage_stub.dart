/// Web 存储桩：无 dart:io，全部返回 null / no-op。
library;

Future<void> ensureDir(String path) async {}
Future<String?> readText(String path) async => null;
Future<void> writeText(String path, String content) async {}
