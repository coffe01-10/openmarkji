import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<void> saveBytes(String name, Uint8List bytes) async {
  await FilePicker.platform.saveFile(
    dialogTitle: '保存文件',
    fileName: name,
    bytes: bytes,
  );
}
