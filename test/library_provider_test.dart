import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:velora/models/meta_item.dart';
import 'package:velora/models/stream_source.dart';
import 'package:velora/models/watch_progress.dart';
import 'package:velora/providers/library_provider.dart';

MetaItem meta(String id, {String type = 'movie'}) =>
    MetaItem(id: id, type: type, name: 'Title $id', genres: const ['Drama']);

StreamSource source() => StreamSource.fromJson({
  'name': 'Torrentio\n1080p',
  'title': 'Some.Release.1080p\n\u{1F464} 40 \u{1F4BE} 2.1 GB ⚙️ YTS',
  'infoHash': 'a' * 40,
  'fileIdx': 2,
});

WatchProgress progress(
  String videoId,
  MetaItem m,
  int posMs, {
  int durMs = 6000000,
  DateTime? at,
  int? season,
  int? episode,
}) => WatchProgress(
  videoId: videoId,
  meta: m,
  positionMs: posMs,
  durationMs: durMs,
  updatedAt: at ?? DateTime.now(),
  source: source(),
  season: season,
  episode: episode,
);

void main() {
  group('WatchProgress', () {
    test('resumable / finished rules', () {
      final m = meta('tt1');
      expect(progress('tt1', m, 30 * 1000).resumable, isFalse); // too early
      expect(progress('tt1', m, 20 * 60 * 1000).resumable, isTrue);
      expect(progress('tt1', m, 5700000).finished, isTrue); // 95%
      expect(progress('tt1', m, 5990000).finished, isTrue); // <90s left
      expect(progress('tt1', m, 5700000).resumable, isFalse);
    });

    test('JSON round trip keeps the source and episode info', () {
      final p = progress(
        'tt9:1:3',
        meta('tt9', type: 'series'),
        123456,
        season: 1,
        episode: 3,
      );
      final q = WatchProgress.fromJson(p.toJson());
      expect(q.videoId, 'tt9:1:3');
      expect(q.positionMs, 123456);
      expect(q.source?.infoHash, 'a' * 40);
      expect(q.source?.fileIdx, 2);
      expect(q.source?.quality, Quality.fhd);
      expect(q.episodeLabel, 'S1 E3');
      expect(q.meta.name, 'Title tt9');
    });
  });

  group('LibraryProvider', () {
    late Directory dir;
    late Box<String> favs;
    late Box<String> prog;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('velora_lib_test');
      Hive.init(dir.path);
      favs = await Hive.openBox<String>('favourites');
      prog = await Hive.openBox<String>('progress');
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('favourites toggle, order and persistence', () async {
      var lib = LibraryProvider(favs, prog);
      await lib.toggleFavourite(meta('tt1'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await lib.toggleFavourite(meta('tt2'));
      expect(lib.isFavourite('tt1'), isTrue);
      expect(lib.favourites.map((m) => m.id), ['tt2', 'tt1']); // newest first

      await lib.toggleFavourite(meta('tt1')); // remove
      expect(lib.isFavourite('tt1'), isFalse);

      await favs.close();
      await prog.close();
      favs = await Hive.openBox<String>('favourites');
      prog = await Hive.openBox<String>('progress');
      lib = LibraryProvider(favs, prog);
      expect(lib.favourites.map((m) => m.id), ['tt2']);
    });

    test(
      'continue watching: one entry per title, newest, no finished',
      () async {
        final lib = LibraryProvider(favs, prog);
        final show = meta('tt5', type: 'series');
        final now = DateTime.now();

        await lib.saveProgress(
          progress(
            'tt5:1:1',
            show,
            20 * 60 * 1000,
            at: now.subtract(const Duration(hours: 2)),
            season: 1,
            episode: 1,
          ),
        );
        await lib.saveProgress(
          progress(
            'tt5:1:2',
            show,
            15 * 60 * 1000,
            at: now.subtract(const Duration(hours: 1)),
            season: 1,
            episode: 2,
          ),
        );
        await lib.saveProgress(
          progress('tt6', meta('tt6'), 5900000, at: now),
        ); // finished movie
        await lib.saveProgress(
          progress(
            'tt7',
            meta('tt7'),
            30 * 60 * 1000,
            at: now.subtract(const Duration(minutes: 5)),
          ),
        );

        final cw = lib.continueWatching;
        expect(cw.map((p) => p.videoId), ['tt7', 'tt5:1:2']);
        expect(lib.resumeFor('tt5')?.videoId, 'tt5:1:2');
        expect(lib.resumeFor('tt6'), isNull);

        await lib.clearProgressFor('tt5');
        expect(lib.continueWatching.map((p) => p.videoId), ['tt7']);
      },
    );

    test('ignores accidental very short first plays', () async {
      final lib = LibraryProvider(favs, prog);
      await lib.saveProgress(progress('tt8', meta('tt8'), 2000));
      expect(lib.progressFor('tt8'), isNull);
    });
  });
}
