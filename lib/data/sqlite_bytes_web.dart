import 'dart:typed_data';

import 'package:sqlite3/wasm.dart';

import 'sqlite_bytes_common.dart';

Future<WasmSqlite3>? _sqlite;

/// 复用随网页提供的 sqlite3.wasm，在内存中读取外部 SQLite 文件。
Future<T> readSqliteBytes<T>(
  Uint8List bytes,
  T Function(CommonDatabase db) read,
) async {
  final sqlite = await (_sqlite ??= WasmSqlite3.loadFromUrl(
    Uri.parse('sqlite3.wasm'),
  ));
  return readWithVfs(sqlite, bytes, read);
}
