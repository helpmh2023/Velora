import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:velora/providers/browse_provider.dart';
import 'package:velora/services/cinemeta_service.dart';

http.Response metas(List<String> ids) => http.Response(
  jsonEncode({
    'metas': [
      for (final id in ids) {'id': id, 'type': 'movie', 'name': 'T $id'},
    ],
  }),
  200,
);

/// Pages of `total` titles, 50 per page, like Cinemeta.
MockClient pagedCatalog(
  int total, {
  List<String>? log,
  Map<String, Completer<void>>? gates,
}) => MockClient((req) async {
  // /catalog/<type>/<id>/<extras>.json
  final path = req.url.path;
  log?.add(path);
  final gate = gates?[path];
  if (gate != null) await gate.future;
  final skip = int.parse(RegExp(r'skip=(\d+)').firstMatch(path)!.group(1)!);
  final tag = path.contains('year')
      ? 'y'
      : (path.contains('genre=') ? 'g' : 'p');
  final ids = [for (var i = skip; i < skip + 50 && i < total; i++) '$tag$i'];
  return metas(ids);
});

BrowseProvider make(MockClient client) =>
    MoviesBrowse(CinemetaService(client: client), now: DateTime(2026, 6, 1));

void main() {
  test('first load fetches page one; loadMore pages by item count', () async {
    final log = <String>[];
    final b = make(pagedCatalog(120, log: log));

    await b.ensureLoaded();
    expect(b.items.length, 50);
    expect(log.single, contains('/catalog/movie/top/'));
    expect(log.single, contains('skip=0'));

    await b.loadMore();
    expect(b.items.length, 100);
    expect(log.last, contains('skip=50'));

    await b.loadMore(); // only 20 left
    expect(b.items.length, 120);
    expect(b.hasMore, isTrue); // not known to be done until an empty page

    await b.loadMore(); // empty page
    expect(b.hasMore, isFalse);
    final calls = log.length;
    await b.loadMore(); // no more requests once exhausted
    expect(log.length, calls);
  });

  test('ensureLoaded is a no-op once loaded', () async {
    final log = <String>[];
    final b = make(pagedCatalog(10, log: log));
    await b.ensureLoaded();
    await b.ensureLoaded();
    expect(log.length, 1);
  });

  test('changing the genre restarts from the top with that genre', () async {
    final log = <String>[];
    final b = make(pagedCatalog(200, log: log));
    await b.ensureLoaded();
    await b.loadMore();
    b.scrollOffset = 1234;

    await b.setFilter('Comedy');
    expect(b.filter, 'Comedy');
    expect(b.scrollOffset, 0);
    expect(b.items.length, 50);
    expect(b.items.first.id, startsWith('g')); // came from the genre catalog
    expect(log.last, contains('genre=Comedy'));
    expect(log.last, contains('skip=0'));

    await b.setFilter(null); // back to everything
    expect(b.items.first.id, startsWith('p'));
  });

  test('featured and year modes use their own catalogs', () async {
    final log = <String>[];
    final b = make(pagedCatalog(100, log: log));
    await b.ensureLoaded();

    await b.setMode(BrowseMode.featured);
    expect(log.last, contains('/catalog/movie/imdbRating/'));
    expect(b.filter, isNull);

    await b.setMode(BrowseMode.year);
    expect(b.filter, '2026'); // defaults to the current year
    expect(log.last, contains('/catalog/movie/year/'));
    expect(log.last, contains('genre=2026'));

    await b.setFilter('2019');
    expect(log.last, contains('genre=2019'));
    expect(b.years.first, '2026');
    expect(b.years.contains('2019'), isTrue);

    await b.setMode(BrowseMode.popular); // leaving year mode clears the year
    expect(b.filter, isNull);
  });

  test('a slow response for an old filter is ignored', () async {
    final slow = Completer<void>();
    // Hold back the very first request (no filter) until we say so.
    final log = <String>[];
    final b = make(
      pagedCatalog(
        100,
        log: log,
        gates: {'/catalog/movie/top/skip=0.json': slow},
      ),
    );
    final first = b.ensureLoaded(); // stuck waiting on the gate
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await b.setFilter('Horror'); // the user moved on; this one completes
    expect(b.items.first.id, startsWith('g'));

    slow.complete();
    await first;
    // The stale "popular" page must not have been mixed in.
    expect(b.items.every((m) => m.id.startsWith('g')), isTrue);
    expect(b.items.length, 50);
  });

  test(
    'duplicates across pages are dropped; failures can be retried',
    () async {
      var call = 0;
      final b = make(
        MockClient((req) async {
          call++;
          if (call == 1) return metas(['a', 'b', 'c']);
          if (call == 2) return http.Response('boom', 500);
          return metas(['c', 'd']); // 'c' repeats
        }),
      );

      await b.ensureLoaded();
      expect(b.items.map((m) => m.id), ['a', 'b', 'c']);

      await b.loadMore(); // fails
      expect(b.error, isNotNull);
      expect(b.items.length, 3); // what we had is kept

      await b.retry();
      expect(b.error, isNull);
      expect(b.items.map((m) => m.id), ['a', 'b', 'c', 'd']);
    },
  );

  test('series list has the extra TV genres', () {
    final s = SeriesBrowse(CinemetaService(client: pagedCatalog(1)));
    expect(s.genres, containsAll(['Reality-TV', 'Talk-Show', 'Game-Show']));
    final m = MoviesBrowse(CinemetaService(client: pagedCatalog(1)));
    expect(m.genres.contains('Reality-TV'), isFalse);
    expect(s.type, 'series');
    expect(m.type, 'movie');
  });
}
