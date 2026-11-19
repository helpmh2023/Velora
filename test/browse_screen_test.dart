import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:velora/core/smooth_scroll.dart';
import 'package:velora/providers/browse_provider.dart';
import 'package:velora/screens/browse/browse_screen.dart';
import 'package:velora/services/cinemeta_service.dart';

void main() {
  final requests = <String>[];

  MoviesBrowse makeProvider() => MoviesBrowse(
    CinemetaService(
      client: MockClient((req) async {
        requests.add(req.url.path);
        final skip = int.parse(
          RegExp(r'skip=(\d+)').firstMatch(req.url.path)!.group(1)!,
        );
        final genre = RegExp(
          r'genre=([^&]+)',
        ).firstMatch(req.url.path)?.group(1);
        return http.Response(
          jsonEncode({
            'metas': [
              for (var i = skip; i < skip + 50 && i < 150; i++)
                {
                  'id': 'tt${genre ?? 'p'}$i',
                  'type': 'movie',
                  'name': 'Movie ${genre ?? 'p'} $i',
                  'releaseInfo': '2026',
                },
            ],
          }),
          200,
        );
      }),
    ),
  );

  Widget app(MoviesBrowse p) => ChangeNotifierProvider<MoviesBrowse>.value(
    value: p,
    child: const MaterialApp(
      scrollBehavior: VeloraScrollBehavior(),
      home: Scaffold(body: BrowseScreen<MoviesBrowse>(title: 'Movies')),
    ),
  );

  setUp(requests.clear);

  testWidgets('shows filters and a grid of titles without layout errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = makeProvider();
    await tester.pumpWidget(app(p));
    await tester.pump(); // post-frame: starts loading
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Movies'), findsOneWidget);
    for (final label in [
      'Popular',
      'Featured',
      'By year',
      'All genres',
      'Comedy',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(p.items.length, 50);
    expect(find.text('Movie p 0'), findsOneWidget);
    expect(tester.takeException(), isNull); // no overflow etc.
  });

  testWidgets('tapping a genre reloads; scrolling to the end loads more', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = makeProvider();
    await tester.pumpWidget(app(p));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Comedy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(p.filter, 'Comedy');
    expect(requests.last, contains('genre=Comedy'));
    expect(find.text('Movie Comedy 0'), findsOneWidget);

    // Fling to the bottom of the first page: the next page is requested.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(requests.any((r) => r.contains('skip=50')), isTrue);
    expect(p.items.length, greaterThan(50));
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the loaded list when the tab is reopened', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = makeProvider();
    await tester.pumpWidget(app(p));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final before = requests.length;

    // Leave the tab and come back.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(p));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(requests.length, before); // no refetch
    expect(find.text('Movie p 0'), findsOneWidget);
  });
}
