import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:velora/models/meta_item.dart';
import 'package:velora/services/engine_service.dart';
import 'package:velora/services/share_server.dart';

const hash = 'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c';

/// Stands in for the real engine: /health, /status (file list) and /stream
/// with Range support.
Future<HttpServer> fakeEngine() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final video = List<int>.generate(1000, (i) => i % 256);
  server.listen((req) async {
    final path = req.uri.path;
    final res = req.response;
    if (path == '/health') {
      res.write('{"ok":true}');
    } else if (path.startsWith('/status/')) {
      res.headers.contentType = ContentType.json;
      res.write(
        jsonEncode({
          'files': [
            {'index': 0, 'path': 'Show/Show.S01E02.mkv', 'length': 1000},
            {'index': 1, 'path': 'Show/Subs/Show.S01E02.en.srt', 'length': 80},
            {'index': 2, 'path': 'Show/Subs/Show.S01E03.en.srt', 'length': 80},
          ],
        }),
      );
    } else if (path == '/stream/$hash/0') {
      final range = req.headers.value('range');
      res.headers.set('Accept-Ranges', 'bytes');
      res.headers.contentType = ContentType('video', 'x-matroska');
      if (range != null) {
        final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
        final a = int.parse(m[1]!);
        final b = m[2]!.isEmpty ? 999 : int.parse(m[2]!);
        res.statusCode = 206;
        res.headers.set('Content-Range', 'bytes $a-$b/1000');
        res.add(video.sublist(a, b + 1));
      } else {
        res.add(video);
      }
    } else if (path == '/stream/$hash/1') {
      res.write('1\n00:00:01,500 --> 00:00:02,000\nHello\n');
    } else {
      res.statusCode = 404;
    }
    await res.close();
  });
  return server;
}

Future<(int, String, HttpHeaders)> get(String url, {String? range}) async {
  final c = HttpClient();
  try {
    final req = await c.getUrl(Uri.parse(url));
    if (range != null) req.headers.set('Range', range);
    final res = await req.close();
    final body = await res.transform(latin1.decoder).join();
    return (res.statusCode, body, res.headers);
  } finally {
    c.close(force: true);
  }
}

void main() {
  late HttpServer engineServer;
  late EngineService engine;
  late ShareServer share;
  const item = ShareItem(
    id: 'abc-0',
    label: 'The Show  -  S1 E2  -  Pilot',
    infoHash: hash,
    fileIdx: 0,
  );

  setUp(() async {
    engineServer = await fakeEngine();
    engine = EngineService(
      remoteBaseUrl: 'http://127.0.0.1:${engineServer.port}',
    );
    await engine.start();
    share = ShareServer(engine, () => [], address: '127.0.0.1');
    expect(await share.start(), isNull);
  });

  tearDown(() async {
    await share.stop();
    await engineServer.close(force: true);
  });

  test('only answers under the secret token', () async {
    final url = share.pageUrl(item)!;
    final bad = url.replaceFirst(
      RegExp(r'/[a-z0-9]{12}/w/'),
      '/wrongtoken123/w/',
    );
    expect((await get(bad)).$1, 404);
    expect((await get('http://127.0.0.1:${Uri.parse(url).port}/')).$1, 404);
    expect((await get(url)).$1, 200);
  });

  test('the watch page offers VLC, Infuse and the matching subtitle', () async {
    final (code, body, _) = await get(share.pageUrl(item)!);
    expect(code, 200);
    expect(body, contains('Open in VLC'));
    expect(body, contains('Open in VLC'));
    expect(
      body,
      isNot(contains('<video')),
      reason: 'VLC only, no Safari player',
    );
    expect(body, contains('location.href'), reason: 'opens VLC by itself');
    expect(body, contains('vlc-x-callback://x-callback-url/stream?url='));
    // The subtitle for this episode is offered; the one for S01E03 is not.
    expect(body, contains('Show.S01E02.en.srt'));
    expect(body, isNot(contains('S01E03.en.srt')));
    // VLC is also told which subtitle to load.
    expect(body, contains('&amp;sub=http'));
  });

  test('the video passes through, with Range support for seeking', () async {
    final page = Uri.parse(share.pageUrl(item)!);
    final base = '${page.origin}/${page.pathSegments.first}';
    final (c1, b1, h1) = await get('$base/v/abc-0/Show.S01E02.mkv');
    expect(c1, 200);
    expect(b1.length, 1000);
    expect(h1.value('accept-ranges'), 'bytes');

    final (c2, b2, h2) = await get(
      '$base/v/abc-0/Show.S01E02.mkv',
      range: 'bytes=100-199',
    );
    expect(c2, 206);
    expect(b2.length, 100);
    expect(h2.value('content-range'), 'bytes 100-199/1000');
  });

  test('subtitles are served, and srt becomes WebVTT for Safari', () async {
    final page = Uri.parse(share.pageUrl(item)!);
    final base = '${page.origin}/${page.pathSegments.first}';
    final (c, vtt, _) = await get('$base/sub/abc-0/1/Show.S01E02.en.vtt');
    expect(c, 200);
    expect(vtt, startsWith('WEBVTT'));
    expect(vtt, contains('00:00:01.500 --> 00:00:02.000'));
    final (_, raw, _) = await get('$base/sub/abc-0/1/Show.S01E02.en.srt');
    expect(raw, contains('00:00:01,500'));
  });

  test('stopping closes the server', () async {
    final url = share.pageUrl(item)!;
    await share.stop();
    expect(share.running, isFalse);
    expect(() => get(url), throwsA(isA<SocketException>()));
    expect(await share.start(), isNull); // can be started again
  });

  group('subtitle matching', () {
    ({int idx, String path}) f(int i, String p) => (idx: i, path: p);

    test('a single-video torrent offers all its subtitles', () {
      final subs = ShareServer.matchSubs('Movie/Movie.mkv', [
        f(0, 'Movie/Movie.mkv'),
        f(1, 'Movie/English.srt'),
        f(2, 'Movie/French.srt'),
      ]);
      expect(subs.map((s) => s.idx), [1, 2]);
    });

    test('in a season pack only that episode\'s subtitles', () {
      final files = [
        f(0, 'S/S.S01E01.mkv'),
        f(1, 'S/S.S01E02.mkv'),
        f(2, 'S/Subs/S.S01E01.srt'),
        f(3, 'S/Subs/S.S01E02.srt'),
      ];
      expect(ShareServer.matchSubs('S/S.S01E02.mkv', files).map((s) => s.idx), [
        3,
      ]);
    });

    test('no subtitle files gives an empty list', () {
      expect(
        ShareServer.matchSubs('a.mkv', [f(0, 'a.mkv'), f(1, 'a.nfo')]),
        isEmpty,
      );
    });
  });

  test('srtToVtt adds the header and fixes timestamps', () {
    final v = ShareServer.srtToVtt(
      '﻿1\r\n00:01:02,003 --> 00:01:04,500\r\nHi\r\n',
    );
    expect(v, startsWith('WEBVTT'));
    expect(v, contains('00:01:02.003 --> 00:01:04.500'));
    expect(v, isNot(contains('\r')));
  });

  group('syncing what the iPad watched', () {
    test(
      'estimates the stop position and saves it, with where it was',
      () async {
        await share.stop();
        final saved = <({ShareItem item, Duration pos, Duration dur})>[];
        share = ShareServer(
          engine,
          () => [],
          address: '127.0.0.1',
          idleAfter: const Duration(milliseconds: 300),
          checkEvery: const Duration(milliseconds: 100),
          reportEvery: const Duration(minutes: 10),
          mainStreamMinBytes: 100,
          rewind: const Duration(seconds: 30),
        );
        share.durationProbe = (_) async => const Duration(minutes: 100);
        share.progressSink = (item, pos, dur) async =>
            saved.add((item: item, pos: pos, dur: dur));
        await share.start();

        const watched = ShareItem(
          id: 'abc-0',
          label: 'The Show  -  S1 E2',
          infoHash: hash,
          fileIdx: 0,
          meta: MetaItem(id: 'tt1', type: 'series', name: 'The Show'),
          videoId: 'tt1:1:2',
          season: 1,
          episode: 2,
        );
        final page = Uri.parse(share.pageUrl(watched)!);
        final base = '${page.origin}/${page.pathSegments.first}';

        // The iPad reads the first half of the file, then stops.
        await get('$base/v/abc-0/x.mkv', range: 'bytes=0-499');
        await Future<void>.delayed(const Duration(milliseconds: 900));

        expect(saved, hasLength(1));
        expect(saved.single.item.videoId, 'tt1:1:2');
        expect(saved.single.dur, const Duration(minutes: 100));
        // Half way = 50:00, less the 30 s safety rewind.
        expect(saved.single.pos, const Duration(minutes: 49, seconds: 30));
      },
    );

    test(
      'items without a title (nothing to save it under) are not tracked',
      () async {
        final saved = <Duration>[];
        share.durationProbe = (_) async => const Duration(minutes: 100);
        share.progressSink = (_, pos, _) async => saved.add(pos);
        final page = Uri.parse(share.pageUrl(item)!);
        await get('${page.origin}/${page.pathSegments.first}/v/abc-0/x.mkv');
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(saved, isEmpty);
      },
    );

    test('the page says where you stopped on the PC', () async {
      share.positionLookup = (_) => const Duration(minutes: 23, seconds: 40);
      final (_, body, _) = await get(share.pageUrl(item)!);
      expect(body, contains('You stopped at'));
      expect(body, contains('23:40'));
    });

    test('a saved secret and port give the same link every session', () async {
      await share.stop();
      final probe = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      final port = probe.port;
      await probe.close();
      share = ShareServer(
        engine,
        () => [],
        address: '127.0.0.1',
        token: 'mysavedsecret1234',
        preferredPort: port,
      );
      await share.start();
      final first = share.pageUrl(item)!;
      await share.stop();
      await share.start();
      expect(share.pageUrl(item), first);
      expect(first, contains('/mysavedsecret1234/'));
      expect(first, contains(':$port/'));
    });
  });
}
