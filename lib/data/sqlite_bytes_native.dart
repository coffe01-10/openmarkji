import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'sqlite_bytes_common.dart';

/// 在内存虚拟文件系统中读取 SQLite 文件字节，不写临时文件。
Future<T> readSqliteBytes<T>(
  Uint8List bytes,
  T Function(CommonDatabase db) read,
) async => readWithVfs(sqlite3, bytes, read);
