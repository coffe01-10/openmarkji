import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openmarkji/data/app_store.dart';
import 'package:openmarkji/data/database.dart';
import 'package:openmarkji/data/webdav.dart';
import 'package:openmarkji/domain/entities.dart';

void main() {
  test('WebDAV 创建目录、解析命名空间，上传下载完整备份后能在新库恢复', () async {
    const config = WebDavConfig(
      address: 'https://dav.example.com/dav/',
      username: 'user',
      password: 'test-password',
      folder: '备份/OpenMarkji',
    );
    final directories = {'/dav/'};
    final files = <Uri, List<int>>{};
    final client = WebDavClient(
      config,
      client: MockClient((request) async {
        expect(
          request.headers['Authorization'],
          'Basic ${base64Encode(utf8.encode('user:test-password'))}',
        );
        if (request.method == 'MKCOL') {
          directories.add(request.url.path);
          return http.Response('', 201);
        }
        if (request.method == 'PUT') {
          files[request.url] = request.bodyBytes;
          return http.Response('', 201);
        }
        if (request.method == 'GET') {
          return http.Response.bytes(files[request.url]!, 200);
        }
        expect(request.method, 'PROPFIND');
        if (!directories.contains(request.url.path)) {
          return http.Response('', 404);
        }
        if (request.headers['Depth'] == '0') return http.Response('', 207);
        return http.Response(
          '''<multistatus xmlns="DAV:">
        <response><href>${config.directory}</href><propstat><prop><resourcetype><collection/></resourcetype></prop></propstat></response>
        ${files.entries.map((e) => '<response><href>${e.key}</href><propstat><prop><getcontentlength>${e.value.length}</getcontentlength><getlastmodified>Fri, 23 Oct 2026 00:00:00 GMT</getlastmodified></prop><status>HTTP/1.1 200 OK</status></propstat></response>').join()}
        <response><href>https://other.example.com/private.zip</href></response>
      </multistatus>''',
          207,
          headers: {'content-type': 'application/xml; charset=utf-8'},
        );
      }),
    );
    final source = AppStore(
      AppDatabase(NativeDatabase.memory()),
      loadOfficialDecks: false,
    );
    final restored = AppStore(
      AppDatabase(NativeDatabase.memory()),
      loadOfficialDecks: false,
    );
    try {
      await source.initialize(legacy: {});
      await source.putDeck(DeckData(id: 'd', name: '远端备份'));
      await source.putCard(
        StudyCard(id: 'c', deckId: 'd', source: '问题\n---\n答案'),
      );
      await client.connect();
      expect(directories.length, 3);
      expect(await client.listBackups(), isEmpty);
      await client.upload('资料 & 图片.zip', await source.backup());
      final backup = (await client.listBackups()).single;
      expect(backup.name, '资料 & 图片.zip');
      expect(backup.bytes, greaterThan(0));
      await restored.initialize(legacy: {});
      await restored.restore(await client.download(backup));
      expect((await restored.cards(deckId: 'd')).single.source, '问题\n---\n答案');
    } finally {
      client.close();
      source.dispose();
      restored.dispose();
      await source.db.close();
      await restored.db.close();
    }
  });

  test('WebDAV 认证失败显示可操作的错误', () async {
    final client = WebDavClient(
      const WebDavConfig(
        address: 'https://dav.example.com/',
        username: 'user',
        password: 'wrong',
      ),
      client: MockClient((_) async => http.Response('', 401)),
    );
    try {
      await expectLater(
        client.connect(),
        throwsA(
          isA<WebDavException>().having(
            (e) => e.message,
            'message',
            contains('认证失败'),
          ),
        ),
      );
    } finally {
      client.close();
    }
  });
}
