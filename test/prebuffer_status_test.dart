import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:velora/models/meta_item.dart';
import 'package:velora/models/stream_source.dart';
import 'package:velora/providers/library_provider.dart';
import 'package:velora/providers/prebuffer_provider.dart';
import 'package:velora/providers/settings_provider.dart';
import 'package:velora/services/engine_service.dart';
import 'package:velora/services/next_episode.dart';
import 'package:velora/services/share_server.dart';
import 'package:velora/widgets/prebuffer_status.dart';

import 'prebuffer_test.dart' show FakeEngine;

/// Real HTTP cannot run inside a widget test's fake clock, so the disk
/// lookup the panel makes is answered directly.
class StubEngine extends EngineService {
  StubEngine(String url) : super(remoteBaseUrl: url);

  @override
  Future<DiskInfo?> disk() async => const DiskInfo(
    free: 50 << 30,
    cacheBytes: 3 << 30,
    maxCache: 8 << 30,
    pinned: 1 << 30,
  );
}

void main() {
  testWidgets('status panel shows episode, source and download progress', (
    tester,
  ) async {
    // Allow the real local HTTP calls to the fake engine below.
    HttpOverrides.global = null;
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fake = FakeEngine();
    late Directory dir;
    late PrebufferProvider pb;
    late StubEngine engine;
    late ShareServer share;
    late LibraryProvider lib;

    // Disk and network need real time: do all of that outside the fake clock.
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('velora_status_test');
      Hive.init(dir.path);
      await fake.start();
      engine = StubEngine('http://127.0.0.1:${fake.server.port}');
      await engine.start();
      final settings = SettingsProvider(
        await Hive.openBox<dynamic>('settings'),
      );
      pb = PrebufferProvider(
        await Hive.openBox<String>('prebuffer'),
        engine,
        settings,
        NextEpisodeService(),
      );
      lib = LibraryProvider(
        await Hive.openBox<String>('fav'),
        await Hive.openBox<String>('prog'),
      );
      share = ShareServer(engine, () => pb.entries);
      final source = StreamSource.fromJson({
        'name': 'Torrentio\n1080p',
        'title': 'Show.S01E02.1080p.WEB\n\u{1F464} 42 \u{1F4BE} 1.4 GB ⚙️ EZTV',
        'infoHash': hashOf,
      });
      await pb.start(
        meta: const MetaItem(id: 'tt1', type: 'series', name: 'The Show'),
        videoId: 'tt1:1:2',
        label: 'The Show  -  S1 E2  -  Pilot',
        source: source,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await pb.refresh();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PrebufferProvider>.value(value: pb),
          ChangeNotifierProvider<EngineService>.value(value: engine),
          ChangeNotifierProvider<ShareServer>.value(value: share),
          ChangeNotifierProvider<LibraryProvider>.value(value: lib),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Center(child: PrebufferStatusButton())),
        ),
      ),
    );

    // The button says how many are downloading.
    expect(find.text('Pre-buffer status  (1 downloading)'), findsOneWidget);

    await tester.tap(find.byType(PrebufferStatusButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('The Show  -  S1 E2  -  Pilot'), findsOneWidget);
    expect(find.textContaining('1080p'), findsWidgets);
    expect(find.textContaining('42 seeders'), findsOneWidget);
    expect(find.textContaining('Downloading 10%'), findsOneWidget);
    expect(find.textContaining('in the cache (limit 8.00 GB)'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      pb.dispose();
      await fake.server.close(force: true);
      await Hive.close();
      await dir.delete(recursive: true);
    });
  });
}

const hashOf = 'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c';
