import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openmarkji/data/app_updates.dart';

void main() {
  test('读取更新源并区分新版本与当前版本', () async {
    for (final version in [appVersion, '1.1.0', '1.0.0']) {
      final release = await AppRelease.check(
        Uri.parse('https://example.com/releases.json'),
        client: MockClient((request) async {
          expect(request.method, 'GET');
          return http.Response(
            '{"version":"$version","notes":"更新说明","downloadUrl":"https://example.com/download"}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      expect(release.isNewer, version == '1.1.0');
      expect(release.notes, '更新说明');
    }
  });
  test('更新服务失败不误报最新版，不接受本地协议下载地址', () async {
    await expectLater(
      AppRelease.check(
        Uri.parse('https://example.com/releases.json'),
        client: MockClient((_) async => http.Response('', 503)),
      ),
      throwsException,
    );
    await expectLater(
      AppRelease.check(
        Uri.parse('https://example.com/releases.json'),
        client: MockClient(
          (_) async => http.Response(
            '{"version":"1.1.0","downloadUrl":"file:///test.exe"}',
            200,
          ),
        ),
      ),
      throwsFormatException,
    );
  });
}
