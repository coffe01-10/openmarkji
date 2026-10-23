import 'dart:convert';

import 'package:http/http.dart' as http;

// Keep semantic versions for update comparisons; the release label is 1.04.
const appVersion = '1.0.4';
const appDisplayVersion = '1.04';
const appBuild = '5';
const releaseFeed = String.fromEnvironment(
  'OPENMARKJI_UPDATE_URL',
  defaultValue: 'https://gist.githubusercontent.com/coffe01-10/d395a32c92cdabf8454bb6dd2403c76a/raw/releases.json',
);

class AppRelease {
  const AppRelease(
    this.version,
    this.notes,
    this.download, {
    this.android = const {},
  });
  final String version, notes;
  final Uri download;
  final Map<String, Uri> android;

  Future<Uri> androidDownload(String abi, {required http.Client client}) async {
    final direct = android[abi];
    if (direct != null) return direct;
    if (download.path.toLowerCase().endsWith('.apk')) return download;
    // 兼容已发布的旧更新源：它只有发布页地址，需读取实际 APK 资源。
    final parts = download.pathSegments;
    if (download.host == 'github.com' &&
        parts.length >= 3 &&
        parts[2] == 'releases') {
      final suffix = parts.length >= 5 && parts[3] == 'tag'
          ? 'tags/${Uri.encodeComponent(parts[4])}'
          : 'latest';
      final response = await client
          .get(
            Uri.parse(
              'https://api.github.com/repos/${parts[0]}/${parts[1]}/releases/$suffix',
            ),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('读取安装包失败（${response.statusCode}）');
      }
      final release =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      for (final asset in release['assets'] as List) {
        if ((asset['name'] as String).endsWith('-$abi.apk')) {
          return _downloadUri(asset['browser_download_url'] as String);
        }
      }
    }
    throw const FormatException('这个版本没有适合当前设备的 Android 安装包');
  }

  static Uri _downloadUri(String value) {
    final uri = Uri.parse(value);
    if (!['https', 'http'].contains(uri.scheme) || uri.host.isEmpty) {
      throw const FormatException('更新下载地址无效');
    }
    return uri;
  }

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
      return AppRelease(
        version,
        json['notes'] as String? ?? '',
        _downloadUri(json['downloadUrl'] as String),
        android: {
          for (final entry
              in (json['android'] as Map<String, dynamic>? ?? {}).entries)
            entry.key: _downloadUri(entry.value as String),
        },
      );
    } finally {
      if (client == null) connection.close();
    }
  }
}
