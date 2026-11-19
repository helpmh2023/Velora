import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:velora/models/meta_item.dart';
import 'package:velora/models/next_up.dart';
import 'package:velora/models/stream_source.dart';
import 'package:velora/models/watch_progress.dart';
import 'package:velora/providers/library_provider.dart';
import 'package:velora/screens/player/up_next_card.dart';

const show = MetaItem(id: 'tt1', type: 'series', name: 'The Show');

Episode ep(int s, int n, {String? title}) => Episode(
  id: 'tt1:$s:$n',
  season: s,
  number: n,
  title: title ?? 'Episode $s.$n',
  released: DateTime(2020, 1, 1),
);

StreamSource source() => StreamSource.fromJson({
  'name': 'Torrentio\n1080p',
  'title': 'Show.S01E03.1080p\n\u{1F464} 30 \u{1F4BE} 1 GB ⚙️ X',
  'infoHash': 'a' * 40,
  'fileIdx': 2,
  'behaviorHints': {'bingeGroup': 'torrentio|1080p'},
});

NextUp nextUp(Episode e, {DateTime? at}) => NextUp(
  meta: show,
  episode: e,
  reference: source(),
  updatedAt: at ?? DateTime.now(),
);

WatchProgress progress(
  String videoId,
  int pos, {
  DateTime? at,
  int? s,
  int? e,
}) => WatchProgress(
  videoId: videoId,
  meta: show,
  positionMs: pos,
  durationMs: 2700000,
  updatedAt: at ?? DateTime.now(),
  season: s,
  episode: e,
);

void main() {
  late Directory dir;
  late Box<String> fav, prog, watched, nextBox;

  Future<LibraryProvider> make() async =>
      LibraryProvider(fav, prog, watched, nextBox);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('velora_nextup_test');
    Hive.init(dir.path);
    fav = await Hive.openBox<String>('fav');
    prog = await Hive.openBox<String>('prog');
    watched = await Hive.openBox<String>('watched');
    nextBox = await Hive.openBox<String>('nextup');
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  group('NextUp storage', () {
    test('round trips, including the reference source', () {
      final n = NextUp.fromJson(
        nextUp(ep(1, 4, title: 'The Wedding')).toJson(),
      );
      expect(n.episode.id, 'tt1:1:4');
      expect(n.label, 'S1 E4  -  The Wedding');
      expect(n.meta.name, 'The Show');
      expect(n.reference?.bingeGroup, 'torrentio|1080p');
      expect(n.videoId, 'tt1:1:4');
    });

    test('is saved, listed newest first, and survives a restart', () async {
      var lib = await make();
      await lib.setNextUp(nextUp(ep(1, 4), at: DateTime(2026, 1, 1)));
      await lib.setNextUp(
        NextUp(
          meta: const MetaItem(id: 'tt2', type: 'series', name: 'Other'),
          episode: ep(2, 1),
          updatedAt: DateTime(2026, 2, 1),
        ),
      );
      expect(lib.nextUp.map((n) => n.meta.id), ['tt2', 'tt1']);
      expect(lib.nextUpFor('tt1')?.episode.number, 4);

      await nextBox.close();
      nextBox = await Hive.openBox<String>('nextup');
      lib = await make();
      expect(lib.nextUp.map((n) => n.meta.id), ['tt2', 'tt1']);
    });

    test('one suggestion per series: a newer one replaces the old', () async {
      final lib = await make();
      await lib.setNextUp(nextUp(ep(1, 4)));
      await lib.setNextUp(nextUp(ep(1, 5)));
      expect(lib.nextUp.length, 1);
      expect(lib.nextUpFor('tt1')?.episode.number, 5);
    });

    test('starting to watch something clears the suggestion', () async {
      final lib = await make();
      await lib.setNextUp(nextUp(ep(1, 4)));
      await lib.saveProgress(progress('tt1:1:4', 120000, s: 1, e: 4));
      expect(lib.nextUpFor('tt1'), isNull);
    });

    test('finishing an episode does NOT clear it', () async {
      final lib = await make();
      await lib.setNextUp(nextUp(ep(1, 4)));
      await lib.saveProgress(
        progress('tt1:1:3', 2650000, s: 1, e: 3),
      ); // finished
      expect(lib.nextUpFor('tt1'), isNotNull);
      expect(lib.isWatched('tt1:1:3'), isTrue);
    });

    test('removing the series from Continue Watching clears it too', () async {
      final lib = await make();
      await lib.setNextUp(nextUp(ep(1, 4)));
      await lib.saveProgress(progress('tt1:1:3', 600000, s: 1, e: 3));
      await lib.setNextUp(nextUp(ep(1, 4)));
      await lib.clearProgressFor('tt1');
      expect(lib.nextUpFor('tt1'), isNull);
    });

    test('dismissing clears one series only', () async {
      final lib = await make();
      await lib.setNextUp(nextUp(ep(1, 4)));
      await lib.setNextUp(
        NextUp(
          meta: const MetaItem(id: 'tt2', type: 'series', name: 'Other'),
          episode: ep(1, 2),
          updatedAt: DateTime.now(),
        ),
      );
      await lib.clearNextUp('tt1');
      expect(lib.nextUp.map((n) => n.meta.id), ['tt2']);
    });
  });

  group('UpNextCard', () {
    Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

    testWidgets('shows the episode, a countdown, and works', (tester) async {
      var played = 0, cancelled = 0;
      await tester.pumpWidget(
        host(
          UpNextCard(
            episode: ep(2, 5, title: 'Hold the Door'),
            seriesName: 'The Show',
            sourceReady: true,
            countdown: 7,
            onPlay: () => played++,
            onCancel: () => cancelled++,
          ),
        ),
      );
      expect(find.text('UP NEXT'), findsOneWidget);
      expect(find.text('S2 E5  -  Hold the Door'), findsOneWidget);
      expect(find.text('Playing in 7 s'), findsOneWidget);
      await tester.tap(find.text('Play now'));
      await tester.tap(find.text('Cancel'));
      expect([played, cancelled], [1, 1]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('autoplay off with no source offers to choose one', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          UpNextCard(
            episode: ep(1, 2),
            seriesName: 'The Show',
            sourceReady: false,
            onPlay: () {},
            onCancel: () {},
          ),
        ),
      );
      expect(find.text('Choose source'), findsOneWidget);
      expect(find.text('Pick a source'), findsOneWidget);
      expect(find.textContaining('Playing in'), findsNothing);
    });
  });
}
