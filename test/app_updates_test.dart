import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openmarkji/data/app_updates.dart';
import 'package:openmarkji/data/app_update_installer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('默认更新源已配置，仓库发布信息可识别当前版本', () async {
    expect(releaseFeed, isNotEmpty);
    final body = await File('releases.json').readAsString();
    final release = await AppRelease.check(
      Uri.parse(releaseFeed),
      client: MockClient(
        (_) async => http.Response(
          body,
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    expect(release.version, appVersion);
    expect(release.isNewer, isFalse);
    expect(
      release.download.toString(),
      'https://github.com/coffe01-10/openmarkji/releases/latest',
    );
  });

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

  test('旧发布页自动解析对应架构的 APK，新更新源使用直接下载地址', () async {
    final release = AppRelease(
      '1.0.4',
      '',
      Uri.parse('https://github.com/coffe01-10/openmarkji/releases/latest'),
    );
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.github.com/repos/coffe01-10/openmarkji/releases/latest',
      );
      return http.Response(
        jsonEncode({
          'assets': [
            for (final abi in ['armeabi-v7a', 'arm64-v8a', 'x86_64'])
              {
                'name': 'OpenMarkji-1.04-android-$abi.apk',
                'browser_download_url': 'https://example.com/$abi.apk',
              },
          ],
        }),
        200,
      );
    });
    expect(
      (await release.androidDownload('arm64-v8a', client: client)).path,
      '/arm64-v8a.apk',
    );
    final direct = AppRelease(
      '1.0.4',
      '',
      release.download,
      android: {'arm64-v8a': Uri.parse('https://example.com/direct.apk')},
    );
    expect(
      (await direct.androidDownload('arm64-v8a', client: client)).path,
      '/direct.apk',
    );
    client.close();
  });

  test('安装包流式落盘后调用安装，取消与下载不完整时清理残片', () async {
    final directory = await Directory.systemTemp.createTemp(
      'openmarkji-update-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/update.apk';
    const channel = MethodChannel('openmarkji/app_update');
    String? installed;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getAbi':
              return 'arm64-v8a';
            case 'prepareUpdate':
              return path;
            case 'installUpdate':
              installed = call.arguments['path'] as String;
              return null;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final installer = AppUpdateInstaller();
    final release = AppRelease(
      '1.0.4',
      '',
      Uri.parse('https://example.com/update.apk'),
    );
    final progress = <int>[];
    Future<String> download({bool truncated = false, bool cancel = false}) =>
        http.runWithClient(
          () => installer.download(
            release,
            onProgress: (received, total) {
              progress.add(received);
              if (cancel) installer.cancel();
            },
          ),
          () => MockClient.streaming(
            (request, body) async => http.StreamedResponse(
              Stream.value([1, 2, 3, 4]),
              200,
              contentLength: truncated ? 10 : 4,
            ),
          ),
        );
    final downloaded = await download();
    expect(await File(downloaded).readAsBytes(), [1, 2, 3, 4]);
    expect(progress, [0, 4]);
    await installer.install(downloaded);
    expect(installed, path);
    await expectLater(download(truncated: true), throwsA(isA<HttpException>()));
    expect(await File('$path.part').exists(), isFalse);
    await expectLater(
      download(cancel: true),
      throwsA(isA<UpdateDownloadCancelled>()),
    );
    expect(await File('$path.part').exists(), isFalse);
  });
}
