import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../platform_dir_io.dart' as legacy;

QueryExecutor openConnection() => LazyDatabase(() async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return NativeDatabase.createInBackground(
    File(p.join(directory.path, 'openmarkji.sqlite')),
  );
});
Future<Map<String, String>> legacyFiles() async {
  final dir = await legacy.dataDir();
  final result = <String, String>{};
  for (final name in ['cards', 'decks', 'logs']) {
    final file = File(p.join(dir, '$name.json'));
    if (await file.exists()) result[name] = await file.readAsString();
  }
  return result;
}
