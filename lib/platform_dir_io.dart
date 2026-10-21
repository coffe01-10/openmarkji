/// 原生端数据目录解析。
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String> dataDir() async {
  if (Platform.isAndroid || Platform.isIOS) {
    final d = await getApplicationDocumentsDirectory();
    return d.path;
  }
  return '${Directory.current.path}/data';
}
