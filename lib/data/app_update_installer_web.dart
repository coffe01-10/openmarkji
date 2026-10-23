import 'app_updates.dart';

class UpdateDownloadCancelled implements Exception {}

class AppUpdateInstaller {
  bool get supported => false;
  Future<String> download(
    AppRelease release, {
    required void Function(int received, int? total) onProgress,
  }) async => throw UnsupportedError('网页版不需要安装 APK');
  Future<void> install(String path) async =>
      throw UnsupportedError('网页版不需要安装 APK');
  void cancel() {}
}
