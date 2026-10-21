/// 原生端存储：用 dart:io 读写 JSON 文件。
library;

import 'dart:io';

Future<void> ensureDir(String path) => Directory(path).create(recursive: true);

Future<String?> readText(String path) async {
  final f = File(path);
  if (!await f.exists()) return null;
  return f.readAsString();
}

Future<void> writeText(String path, String content) =>
    File(path).writeAsString(content);
