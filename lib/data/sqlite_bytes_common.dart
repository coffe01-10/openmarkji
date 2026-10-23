import 'dart:typed_data';

import 'package:sqlite3/common.dart';

export 'package:sqlite3/common.dart' show CommonDatabase;

var _vfsSequence = 0;

T readWithVfs<T>(
  CommonSqlite3 sqlite,
  Uint8List bytes,
  T Function(CommonDatabase db) read,
) {
  if (bytes.length < 100 ||
      String.fromCharCodes(bytes.sublist(0, 15)) != 'SQLite format 3') {
    throw const FormatException('数据库文件已损坏或格式不正确');
  }
  final data = Uint8List.fromList(bytes);
  // 内存文件系统没有 WAL 所需的共享内存，按回滚日志模式读取。
  if (data[18] == 2) data[18] = 1;
  if (data[19] == 2) data[19] = 1;
  final vfs = InMemoryFileSystem(name: 'openmarkji-import-${_vfsSequence++}');
  final file = vfs
      .xOpen(
        Sqlite3Filename('/import.sqlite'),
        SqlFlag.SQLITE_OPEN_CREATE | SqlFlag.SQLITE_OPEN_READWRITE,
      )
      .file;
  file.xWrite(data, 0);
  file.xClose();
  sqlite.registerVirtualFileSystem(vfs);
  CommonDatabase? db;
  try {
    db = sqlite.open('/import.sqlite', vfs: vfs.name);
    // Anki 新版数据库的名称列使用 unicase 排序规则。
    db.createCollation(
      name: 'unicase',
      function: (a, b) =>
          (a ?? '').toLowerCase().compareTo((b ?? '').toLowerCase()),
    );
    return read(db);
  } finally {
    db?.close();
    sqlite.unregisterVirtualFileSystem(vfs);
  }
}
