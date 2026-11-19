import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:velora/models/meta_item.dart';
import 'package:velora/models/next_up.dart';
import 'package:velora/models/watch_progress.dart';
import 'package:velora/providers/library_provider.dart';
import 'package:velora/widgets/continue_row.dart';

void main() {
  // Disk I/O (Hive) needs real time, so it all runs inside runAsync.
  Future<(Directory, LibraryProvider)> openLibrary() async {
    final dir = await Directory.systemTemp.createTemp('velora_row_test');
    Hive.init(dir.path);
    final lib = LibraryProvider(
      await Hive.openBox<String>('fav'),
      await Hive.openBox<String>('prog'),
      await Hive.openBox<String>('watched'),
      await Hive.openBox<String>('nextup'),
    );
    final now = DateTime.now();
    await lib.saveProgress(
      WatchProgress(
        videoId: 'tt9',
        meta: const MetaItem(id: 'tt9', type: 'movie', name: 'Some Movie'),
        positionMs: 1800000,
        durationMs: 6000000,
        updatedAt: now.subtract(const Duration(days: 2)),
      ),
    );
    await lib.setNextUp(
      NextUp(
        meta: const MetaItem(id: 'tt1', type: 'series', name: 'The Show'),
        episode: Episode(
          id: 'tt1:1:4',
          season: 1,
          number: 4,
          title: 'The Wedding',
          released: DateTime(2020, 1, 1),
        ),
        updatedAt: now,
      ),
    );
    return (dir, lib);
  }

  group('Continue Watching row with Up next', () {
    testWidgets('lists both kinds, newest first, and dismiss works', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final (dir, lib) = (await tester.runAsync(openLibrary))!;

      await tester.pumpWidget(
        ChangeNotifierProvider<LibraryProvider>.value(
          value: lib,
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  ContinueRow(
                    items: lib.continueWatching,
                    nextUp: lib.nextUp,
                    onOpenDetails: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Continue Watching'), findsOneWidget);
      expect(find.text('UP NEXT'), findsOneWidget);
      expect(find.text('S1 E4  -  The Wedding'), findsOneWidget);
      expect(find.text('Some Movie'), findsOneWidget);
      // Newest first: the show's card sits to the left of the movie's.
      expect(
        tester.getTopLeft(find.text('The Show')).dx,
        lessThan(tester.getTopLeft(find.text('Some Movie')).dx),
      );
      expect(tester.takeException(), isNull);

      await tester.runAsync(() => tester.tap(find.byTooltip('Dismiss')));
      // The write behind the tap needs real time to finish.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      expect(lib.nextUpFor('tt1'), isNull);

      await tester.runAsync(() async {
        await Hive.close();
        await dir.delete(recursive: true);
      });
    });
  });
}
