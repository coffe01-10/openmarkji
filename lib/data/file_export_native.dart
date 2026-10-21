import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<void> saveBytes(String name, Uint8List bytes) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: '保存文件',
    fileName: name,
    bytes: bytes,
  );
  // Mobile and Web implementations write the bytes themselves. Desktop returns a path.
  if (path != null && !Platform.isAndroid && !Platform.isIOS) {
    await File(path).writeAsBytes(bytes, flush: true);
  }
}
