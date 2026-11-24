import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:velora/models/meta_item.dart';
import 'package:velora/models/prebuffer_entry.dart';
import 'package:velora/models/stream_source.dart';
import 'package:velora/models/watch_progress.dart';
import 'package:velora/providers/library_provider.dart';
import 'package:velora/providers/prebuffer_provider.dart';
import 'package:velora/providers/settings_provider.dart';
import 'package:velora/services/engine_service.dart';
import 'package:velora/services/next_episode.dart';

const hash = 'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c';
const show = MetaItem(id: 'tt1', type: 'series', name: 'The Show');

StreamSource source() => StreamSource.fromJson({
  'name': 'Torrentio\n1080p',
  'title': 'Show.S01E02.1080p\n\u{1F464} 30 \u{1F4BE} 1 GB ⚙️ X',
  'infoHash': hash,
  'behaviorHints': {'bingeGroup': 'torrentio|1080p'},
});

/// Pretends to be the engine's pre-buffer API.
class FakeEngine {
  late HttpServer server;
  String? checkMessage;
  final started = <Uri>[];
  final removed = <String>[];
  var state = 'downloading';
  var done = 10;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final res = req.response;
      res.headers.contentType = ContentType.json;
      final path = req.uri.path;
      if (path == '/health') {
        res.write('{"ok":true}');
      } else if (path.startsWith('/check/')) {
        res.write(
          jsonEncode({
            'ok': checkMessage == null,
            'message': checkMessage ?? '',
            'size': 1000,
            'idx': 3,
          }),
        );
      } else if (path == '/prebuffer') {
        res.write(
          jsonEncode([
            {
              'hash': hash,
              'idx': 3,
              'label': 'x',
              'want': 0,
              'state': state,
              'error': '',
              'done': done,
              'total': 100,
            },
          ]),
        );
      } else if (path.startsWith('/prebuffer/')) {
        if (req.uri.queryParameters['remove'] == '1') {
          removed.add(path);
        } else {
          started.add(req.uri);
        }
        res.write('{"ok":true}');
      } else {
        res.statusCode = 404;
      }
      await res.close();
    });
  }
}

void main() {
  late Directory dir;
  late FakeEngine fake;
  late EngineService engine;
  late SettingsProvider settings;
  late Box<String> box;
  late PrebufferProvider pb;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('velora_pb_test');
    Hive.init(dir.path);
    box = await Hive.openBox<String>('prebuffer');
    settings = SettingsProvider(await Hive.openBox<dynamic>('settings'));
    fake = FakeEngine();
    await fake.start();
    engine = EngineService(
      remoteBaseUrl: 'http://127.0.0.1:${fake.server.port}',
    );
    await engine.start();
    pb = PrebufferProvider(box, engine, settings, NextEpisodeService());
  });

  tearDown(() async {
    pb.dispose();
    await fake.server.close(force: true);
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('settings: pre-buffer is off by default and persists', () {
    expect(settings.prebufferAhead, 0);
    expect(settings.prebufferStartOnly, isFalse);
    expect(settings.maxCacheGb, 8);
    settings.prebufferAhead = 2;
    settings.prebufferStartOnly = true;
    expect(settings.prebufferAhead, 2);
    expect(settings.prebufferStartOnly, isTrue);
  });

  test('entries round trip through storage', () {
    final e = PrebufferEntry(
      meta: show,
      videoId: 'tt1:1:2',
      label: 'The Show  -  S1 E2',
      source: source(),
      fileIdx: 3,
      season: 1,
      episode: 2,
      episodeTitle: 'Pilot',
      size: 1000,
      partial: true,
      addedAt: DateTime(2026, 1, 1),
    );
    final back = PrebufferEntry.fromJson(
      jsonDecode(e.encode()) as Map<String, dynamic>,
    );
    expect(back.videoId, 'tt1:1:2');
    expect(back.fileIdx, 3);
    expect(back.partial, isTrue);
    expect(back.source.infoHash, hash);
    expect(back.source.bingeGroup, 'torrentio|1080p');
  });

  test('start asks the engine, remembers the entry, tracks progress', () async {
    final msg = await pb.start(
      meta: show,
      videoId: 'tt1:1:2',
      label: 'The Show  -  S1 E2',
      source: source(),
    );
    expect(msg, isNull);
    expect(fake.started.single.path, '/prebuffer/$hash/3'); // the resolved file
    expect(fake.started.single.queryParameters.containsKey('want'), isFalse);
    expect(pb.entryFor('tt1:1:2'), isNotNull);
    expect(box.length, 1); // saved, so it survives a restart

    // start() already kicked off a refresh in the background; let it finish.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await pb.refresh();
    expect(pb.jobFor('tt1:1:2')?.progress, 0.1);
    expect(pb.isReady('tt1:1:2'), isFalse);
    fake.state = 'ready';
    fake.done = 100;
    await pb.refresh();
    expect(pb.isReady('tt1:1:2'), isTrue);
  });

  test('"start only" asks for the first part of the file', () async {
    settings.prebufferStartOnly = true;
    await pb.start(
      meta: show,
      videoId: 'tt1:1:2',
      label: 'x',
      source: source(),
    );
    expect(fake.started.single.queryParameters['want'], '120'); // 12% of 1000
    expect(pb.entryFor('tt1:1:2')?.partial, isTrue);
  });

  test('a refusal from the engine is returned and nothing is saved', () async {
    fake.checkMessage = 'Not enough free disk space: need about 1.0 GB.';
    final msg = await pb.start(
      meta: show,
      videoId: 'tt1:1:2',
      label: 'x',
      source: source(),
    );
    expect(msg, contains('Not enough free disk space'));
    expect(pb.entryFor('tt1:1:2'), isNull);
    expect(fake.started, isEmpty);
    expect(box.isEmpty, isTrue);
  });

  test('remove forgets it and tells the engine to delete the data', () async {
    await pb.start(
      meta: show,
      videoId: 'tt1:1:2',
      label: 'x',
      source: source(),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await pb.remove('tt1:1:2');
    expect(pb.entryFor('tt1:1:2'), isNull);
    expect(box.isEmpty, isTrue);
    expect(fake.removed.single, '/prebuffer/$hash/3');
  });

  test('queued twice only starts once', () async {
    await pb.start(
      meta: show,
      videoId: 'tt1:1:2',
      label: 'x',
      source: source(),
    );
    await pb.start(
      meta: show,
      videoId: 'tt1:1:2',
      label: 'x',
      source: source(),
    );
    expect(fake.started.length, 1);
  });

  test(
    'a pre-buffered episode is played from its own source, no picker',
    () async {
      expect(pb.sourceFor('tt1:1:2'), isNull); // nothing queued yet
      final src = source();
      await pb.start(meta: show, videoId: 'tt1:1:2', label: 'x', source: src);
      // Even while still downloading it is the source to play.
      expect(pb.sourceFor('tt1:1:2')?.infoHash, hash);
      expect(pb.sourceFor('tt1:1:3'), isNull); // other episodes still ask

      // A failed download falls back to asking for a source.
      fake.state = 'error';
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await pb.refresh();
      expect(pb.sourceFor('tt1:1:2'), isNull);

      await pb.remove('tt1:1:2');
      expect(pb.sourceFor('tt1:1:2'), isNull);
    },
  );

  test('pre-buffered but not started shows under Continue Watching', () async {
    final lib = LibraryProvider(
      await Hive.openBox<String>('fav'),
      await Hive.openBox<String>('prog'),
      await Hive.openBox<String>('watched'),
      await Hive.openBox<String>('nextup'),
    );
    await pb.start(
      meta: show,
      videoId: 'tt1:1:2',
      label: 'x',
      source: source(),
    );
    expect(pb.continueCandidates(lib).map((e) => e.videoId), ['tt1:1:2']);

    // Started for more than a minute: the normal resume card takes over.
    await lib.saveProgress(
      WatchProgress(
        videoId: 'tt1:1:2',
        meta: show,
        positionMs: 5 * 60 * 1000,
        durationMs: 40 * 60 * 1000,
        updatedAt: DateTime.now(),
      ),
    );
    expect(pb.continueCandidates(lib), isEmpty);

    // Finished: gone for good.
    await lib.markWatched(['tt1:1:2']);
    expect(pb.continueCandidates(lib), isEmpty);
  });
}
