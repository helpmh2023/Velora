import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/bench.dart';
import 'core/platform.dart';
import 'core/storage.dart';
import 'providers/browse_provider.dart';
import 'providers/home_provider.dart';
import 'providers/library_provider.dart';
import 'providers/nav_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/trakt_provider.dart';
import 'services/cinemeta_service.dart';
import 'services/engine_service.dart';
import 'services/token_store.dart';
import 'services/trakt_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 400 << 20
    ..maximumSize = 1500;

  if (isDesktop) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(960, 600),
      center: true,
      title: 'Velora',
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Colors.transparent,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  await initStorage();
  final settings = SettingsProvider(await Hive.openBox<dynamic>('settings'));
  final library = LibraryProvider(
    await Hive.openBox<String>('favourites'),
    await Hive.openBox<String>('progress'),
    await Hive.openBox<String>('watched'),
  );

  // Torrent engine: warm it up at launch so the first Play is fast.
  // Windows only for now; Android/iOS get an in-process engine later.
  final engine = EngineService(
    maxCacheGb: settings.maxCacheGb,
    uploadKbps: settings.uploadKbps,
    noUpload: !settings.allowUpload,
    bindIp: settings.bindIp,
    remoteBaseUrl: settings.remoteUrl,
  );
  if (Platform.isWindows) {
    engine.start().catchError((Object e) {
      debugPrint('Engine failed to start: $e');
    });
  }

  final trakt = TraktProvider(
    service: TraktService(),
    store: SecureTokenStore(),
    library: library,
    settings: settings,
  );
  // Loads saved login, wires watchlist sync, starts a background sync.
  await trakt.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NavProvider()),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: trakt),
        // One catalog browser per tab; they keep their place across tab switches.
        ChangeNotifierProvider(create: (_) => MoviesBrowse(CinemetaService())),
        ChangeNotifierProvider(create: (_) => SeriesBrowse(CinemetaService())),
        ChangeNotifierProvider.value(value: engine),
        // Starts fetching immediately so data loads while the intro plays.
        ChangeNotifierProvider(
          create: (_) => HomeProvider(CinemetaService())..load(),
        ),
      ],
      child: const VeloraApp(),
    ),
  );

  // Scripted perf run; does nothing unless VELORA_BENCH is set.
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => runBenchIfRequested(navigatorKey),
  );
}
