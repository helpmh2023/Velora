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

  test('engine starts, answers health, builds stream URLs', () async {
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
  }, skip: available ? false : 'engine binary not built');

  test('restartWith applies new settings and engine still answers', () async {
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
        keepCache: true,
        remoteBaseUrl: null,
      ),
      isFalse,
    );
    await engine.restartWith(
      maxCacheGb: 8,
      uploadKbps: 128,
      noUpload: true,
      bindIp: null,
      keepCache: true,
      remoteBaseUrl: null,
    );
    expect(engine.state, EngineState.ready);
    expect(
      engine.matches(
        maxCacheGb: 8,
        uploadKbps: 128,
        noUpload: true,
        bindIp: null,
        keepCache: true,
        remoteBaseUrl: null,
      ),
      isTrue,
    );
    expect(engine.baseUrl, isNotNull);
    expect(engine.baseUrl, isNot(equals(firstUrl))); // new process, new port

    // The same engine, reached as a "remote" one.
    expect(await EngineService.checkRemote(engine.baseUrl!), isNull);
    expect(await EngineService.checkRemote('nonsense'), isNotNull);
  }, skip: available ? false : 'engine binary not built');

  group('cache persistence', () {
    late Directory cache;
    late File marker;

    setUp(() async {
      cache = await Directory.systemTemp.createTemp('velora_cache_test');
      // Stands in for downloaded torrent data from an earlier session.
      final torrent = await Directory(
        p.join(cache.path, 'Some Movie'),
      ).create();
      marker = File(p.join(torrent.path, 'movie.mkv'))
        ..writeAsStringSync('data');
    });

    tearDown(() async {
      try {
        await cache.delete(recursive: true);
      } catch (_) {}
    });

    EngineService make({bool keep = true}) =>
        EngineService(binaryPath: exe, cacheDir: cache.path, keepCache: keep);

    test('data from an earlier session survives starting the engine', () async {
      final engine = make();
      addTearDown(engine.stop);
      await engine.start();
      expect(marker.existsSync(), isTrue);
      await engine.stop();

      final again = make(); // a second "launch"
      addTearDown(again.stop);
      await again.start();
      expect(marker.existsSync(), isTrue);
    }, skip: available ? false : 'engine binary not built');

    test('keepCache off wipes it at start', () async {
      final engine = make(keep: false);
      addTearDown(engine.stop);
      await engine.start();
      expect(marker.existsSync(), isFalse);
    }, skip: available ? false : 'engine binary not built');

    test('clearCache wipes once, then the cache is kept again', () async {
      final engine = make();
      addTearDown(engine.stop);
      await engine.start();
      expect(marker.existsSync(), isTrue);

      Future<void> restart({bool clear = false}) => engine.restartWith(
        maxCacheGb: 4,
        uploadKbps: 1,
        noUpload: false,
        keepCache: true,
        bindIp: null,
        remoteBaseUrl: null,
        clearCache: clear,
      );

      await restart(clear: true);
      expect(marker.existsSync(), isFalse); // cleared

      marker.parent.createSync(recursive: true);
      marker.writeAsStringSync('new data');
      await restart(); // an ordinary restart must not clear it
      expect(marker.existsSync(), isTrue);
    }, skip: available ? false : 'engine binary not built');

    test('stop() ends the engine process promptly', () async {
      final engine = make();
      await engine.start();
      final watch = Stopwatch()..start();
      await engine.stop();
      expect(watch.elapsed, lessThan(const Duration(seconds: 6)));
      expect(engine.state, EngineState.stopped);
    }, skip: available ? false : 'engine binary not built');

    test('over-cap data is trimmed at start, oldest first', () async {
      // Two "torrents"; the old one should go when the cap is tiny.
      final oldDir = await Directory(p.join(cache.path, 'Old')).create();
      File(
        p.join(oldDir.path, 'a.bin'),
      ).writeAsBytesSync(List.filled(2 * 1024 * 1024, 1));
      File(
        p.join(oldDir.path, 'a.bin'),
      ).setLastModifiedSync(DateTime.now().subtract(const Duration(days: 30)));
      final newDir = await Directory(p.join(cache.path, 'New')).create();
      File(
        p.join(newDir.path, 'b.bin'),
      ).writeAsBytesSync(List.filled(2 * 1024 * 1024, 2));

      final engine = EngineService(
        binaryPath: exe,
        cacheDir: cache.path,
        maxCacheGb: 0.003, // about 3 MB: room for one of the two
      );
      addTearDown(engine.stop);
      await engine.start();

      expect(oldDir.existsSync(), isFalse);
      expect(newDir.existsSync(), isTrue);
    }, skip: available ? false : 'engine binary not built');
  });
}
