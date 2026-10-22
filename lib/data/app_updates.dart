import 'dart:convert';

import 'package:http/http.dart' as http;

const appVersion = '1.0.0';
const appBuild = '1';
const releaseFeed = String.fromEnvironment('OPENMARKJI_UPDATE_URL');

class AppRelease {
  const AppRelease(this.version, this.notes, this.download);
  final String version, notes;
  final Uri download;
  bool get isNewer {
    final next = _parts(version);
    final current = _parts(appVersion);
    for (var i = 0; i < 3; i++) {
      if (next[i] != current[i]) return next[i] > current[i];
    }
    return false;
  }

  static List<int> _parts(String version) {
    final parts = version.split('+').first.split('.');
    if (parts.length != 3 || parts.any((p) => int.tryParse(p) == null)) {
      throw const FormatException('更新信息中的版本号无效');
    }
    return parts.map(int.parse).toList();
  }

  static Future<AppRelease> check(Uri feed, {http.Client? client}) async {
    final connection = client ?? http.Client();
    try {
      final response = await connection
          .get(feed)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('更新服务暂时不可用（${response.statusCode}）');
      }
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final version = json['version'] as String;
      _parts(version);
      final download = Uri.parse(json['downloadUrl'] as String);
      // 更新源只允许打开网页下载地址，避免将远端内容解释为本机协议。
      if (!['https', 'http'].contains(download.scheme) ||
          download.host.isEmpty) {
        throw const FormatException('更新下载地址无效');
      }
      return AppRelease(version, json['notes'] as String? ?? '', download);
    } finally {
      if (client == null) connection.close();
    }
  }
}
