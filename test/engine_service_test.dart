import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:velora/services/engine_service.dart';

void main() {
  final exe = p.join(
    Directory.current.path,
    'native',
    'velora_engine',
    'velora_engine.exe',
  );
  final available = File(exe).existsSync();

  test(
    'engine starts, answers health, builds stream URLs',
    () async {
      final engine = EngineService(
        binaryPath: exe,
        cacheDir: p.join(Directory.systemTemp.path, 'velora-test-cache'),
      );
      addTearDown(engine.stop);

      await engine.start();
      expect(engine.state, EngineState.ready);
      expect(engine.baseUrl, startsWith('http://127.0.0.1:'));

      final url = engine.streamUrl(
        infoHash: 'DD8255ECDC7CA55FB0BBF81323D87062DB1F6D1C',
        fileIdx: 1,
        trackers: ['udp://tracker.example:1337/announce'],
        name: 'Big Buck Bunny',
      );
      final uri = Uri.parse(url);
      expect(uri.path, '/stream/dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c/1');
      expect(uri.queryParametersAll['tr'], [
        'udp://tracker.example:1337/announce',
      ]);
      expect(uri.queryParameters['dn'], 'Big Buck Bunny');

      expect(await engine.status('0' * 40), isNull); // unknown torrent
    },
    skip: available ? false : 'engine binary not built',
  );

  test(
    'restartWith applies new settings and engine still answers',
    () async {
      final engine = EngineService(
        binaryPath: exe,
        cacheDir: p.join(Directory.systemTemp.path, 'velora-test-cache2'),
      );
      addTearDown(engine.stop);
      await engine.start();
      final firstUrl = engine.baseUrl;

      expect(
        engine.matches(
          maxCacheGb: 8,
          uploadKbps: 128,
          noUpload: true,
          bindIp: null,
          remoteBaseUrl: null,
        ),
        isFalse,
      );
      await engine.restartWith(
        maxCacheGb: 8,
        uploadKbps: 128,
        noUpload: true,
        bindIp: null,
        remoteBaseUrl: null,
      );
      expect(engine.state, EngineState.ready);
      expect(
        engine.matches(
          maxCacheGb: 8,
          uploadKbps: 128,
          noUpload: true,
          bindIp: null,
          remoteBaseUrl: null,
        ),
        isTrue,
      );
      expect(engine.baseUrl, isNotNull);
      expect(engine.baseUrl, isNot(equals(firstUrl))); // new process, new port

      // The same engine, reached as a "remote" one.
      expect(await EngineService.checkRemote(engine.baseUrl!), isNull);
      expect(await EngineService.checkRemote('nonsense'), isNotNull);
    },
    skip: available ? false : 'engine binary not built',
  );
}
