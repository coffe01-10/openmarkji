import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class WebDavConfig {
  const WebDavConfig({
    required this.address,
    required this.username,
    required this.password,
    this.folder = 'OpenMarkji',
  });

  final String address, username, password, folder;

  Uri get root {
    final uri = Uri.parse(address.trim());
    if (!['https', 'http'].contains(uri.scheme) || uri.host.isEmpty) {
      throw const FormatException('请填写完整的 HTTP 或 HTTPS WebDAV 地址');
    }
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const FormatException('地址只填写服务器路径，账号密码请填写在下方');
    }
    return uri.replace(
      path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
    );
  }

  List<String> get folders {
    final parts = folder.trim().split('/').where((s) => s.isNotEmpty).toList();
    if (parts.any((s) => s == '.' || s == '..')) {
      throw const FormatException('备份目录不能包含 . 或 ..');
    }
    return parts;
  }

  Uri get directory => root.replace(
    pathSegments: [
      ...root.pathSegments.where((s) => s.isNotEmpty),
      ...folders,
      '',
    ],
  );

  Map<String, dynamic> toJson() => {
    'address': address,
    'username': username,
    'password': password,
    'folder': folder,
  };

  factory WebDavConfig.fromJson(Map<String, dynamic> json) => WebDavConfig(
    address: json['address'] as String? ?? '',
    username: json['username'] as String? ?? '',
    password: json['password'] as String? ?? '',
    folder: json['folder'] as String? ?? 'OpenMarkji',
  );
}

class WebDavBackup {
  const WebDavBackup({
    required this.uri,
    required this.name,
    required this.bytes,
    required this.modified,
  });
  final Uri uri;
  final String name, modified;
  final int bytes;
}

class WebDavException implements Exception {
  const WebDavException(this.message);
  final String message;
  @override
  String toString() => message;
}

class WebDavClient {
  WebDavClient(this.config, {http.Client? client})
    : _client = client ?? http.Client();
  final WebDavConfig config;
  final http.Client _client;

  void close() => _client.close();

  Future<http.Response> _request(
    String method,
    Uri uri, {
    String? depth,
    List<int>? bytes,
  }) async {
    final request = http.Request(method, uri)..followRedirects = false;
    if (config.username.isNotEmpty || config.password.isNotEmpty) {
      request.headers['Authorization'] =
          'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}';
    }
    if (depth != null) {
      request.headers['Depth'] = depth;
      request.headers['Content-Type'] = 'application/xml; charset=utf-8';
      request.body = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>''';
    }
    if (bytes != null) {
      request.headers['Content-Type'] = 'application/zip';
      request.bodyBytes = bytes;
    }
    return _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 60));
  }

  void _check(http.Response response, List<int> accepted) {
    if (accepted.contains(response.statusCode)) return;
    throw WebDavException(switch (response.statusCode) {
      401 => 'WebDAV 认证失败，请检查用户名和密码',
      403 => 'WebDAV 没有访问或写入权限',
      404 => 'WebDAV 地址或备份目录不存在',
      301 || 302 || 307 || 308 => 'WebDAV 地址发生跳转，请填写服务器最终的目录地址',
      _ => 'WebDAV 请求失败（HTTP ${response.statusCode}）',
    });
  }

  Future<void> connect() async {
    var directory = config.root;
    _check(await _request('PROPFIND', directory, depth: '0'), [207]);
    for (final folder in config.folders) {
      directory = directory.replace(
        pathSegments: [
          ...directory.pathSegments.where((s) => s.isNotEmpty),
          folder,
          '',
        ],
      );
      var response = await _request('PROPFIND', directory, depth: '0');
      if (response.statusCode == 404) {
        _check(await _request('MKCOL', directory), [201, 405]);
        response = await _request('PROPFIND', directory, depth: '0');
      }
      _check(response, [207]);
    }
  }

  Future<List<WebDavBackup>> listBackups() async {
    final directory = config.directory;
    final response = await _request('PROPFIND', directory, depth: '1');
    _check(response, [207]);
    final document = XmlDocument.parse(utf8.decode(response.bodyBytes));
    final backups = <WebDavBackup>[];
    for (final item in document.findAllElements(
      'response',
      namespaceUri: 'DAV:',
    )) {
      if (item.findAllElements('collection', namespaceUri: 'DAV:').isNotEmpty) {
        continue;
      }
      final href = item
          .findElements('href', namespaceUri: 'DAV:')
          .firstOrNull
          ?.innerText;
      if (href == null) continue;
      final uri = directory.resolve(href);
      // 服务器返回的 href 只用于当前目录，避免把认证信息发往外站。
      if (uri.origin != directory.origin ||
          uri.resolve('.').path != directory.path ||
          !uri.path.toLowerCase().endsWith('.zip')) {
        continue;
      }
      String prop(String name) =>
          item
              .findAllElements(name, namespaceUri: 'DAV:')
              .firstOrNull
              ?.innerText ??
          '';
      backups.add(
        WebDavBackup(
          uri: uri,
          name: uri.pathSegments.last,
          bytes: int.tryParse(prop('getcontentlength')) ?? 0,
          modified: prop('getlastmodified'),
        ),
      );
    }
    backups.sort((a, b) => b.name.compareTo(a.name));
    return backups;
  }

  Future<void> upload(String name, Uint8List bytes) async {
    final uri = config.directory.replace(
      pathSegments: [
        ...config.directory.pathSegments.where((s) => s.isNotEmpty),
        name,
      ],
    );
    _check(await _request('PUT', uri, bytes: bytes), [200, 201, 204]);
  }

  Future<Uint8List> download(WebDavBackup backup) async {
    final directory = config.directory;
    if (backup.uri.origin != directory.origin ||
        backup.uri.resolve('.').path != directory.path) {
      throw const WebDavException('备份文件不在当前 WebDAV 目录中');
    }
    final response = await _request('GET', backup.uri);
    _check(response, [200]);
    return response.bodyBytes;
  }
}
