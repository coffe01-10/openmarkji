import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'app_updates.dart';

class UpdateDownloadCancelled implements Exception {}

class AppUpdateInstaller {
  static const _channel = MethodChannel('openmarkji/app_update');
  http.Client? _client;
  bool _cancelled = false;
  bool get supported => defaultTargetPlatform == TargetPlatform.android;

  Future<String> download(
    AppRelease release, {
    required void Function(int received, int? total) onProgress,
  }) async {
    _cancelled = false;
    final client = _client = http.Client();
    File? partial;
    RandomAccessFile? file;
    try {
      final abi = (await _channel.invokeMethod<String>('getAbi'))!;
      final source = await release.androidDownload(abi, client: client);
      final path = (await _channel.invokeMethod<String>('prepareUpdate'))!;
      partial = File('$path.part');
      file = await partial.open(mode: FileMode.write);
      final response = await client
          .send(http.Request('GET', source))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException('下载安装包失败（${response.statusCode}）');
      }
      final total = response.contentLength;
      var received = 0;
      final throttle = Stopwatch()..start();
      onProgress(received, total);
      await for (final bytes in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        await file.writeFrom(bytes);
        received += bytes.length;
        if (throttle.elapsedMilliseconds >= 100) {
          onProgress(received, total);
          throttle.reset();
        }
      }
      if (_cancelled) throw UpdateDownloadCancelled();
      // 网络中断时不能把未完整收到的 APK 交给系统安装器。
      if (received == 0 || (total != null && received != total)) {
        throw const HttpException('安装包下载不完整，请重试');
      }
      await file.flush();
      await file.close();
      file = null;
      if (_cancelled) throw UpdateDownloadCancelled();
      await partial.rename(path);
      onProgress(received, total);
      return path;
    } catch (_) {
      if (_cancelled) throw UpdateDownloadCancelled();
      rethrow;
    } finally {
      await file?.close();
      if (partial != null && await partial.exists()) await partial.delete();
      client.close();
      _client = null;
    }
  }

  Future<void> install(String path) =>
      _channel.invokeMethod<void>('installUpdate', {'path': path});

  void cancel() {
    _cancelled = true;
    _client?.close();
  }
}
