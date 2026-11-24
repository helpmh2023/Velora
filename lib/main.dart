import 'dart:io' show Platform;

import 'package:material_ui/material_ui.dart';
import 'package:hive_ce/hive.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/bench.dart';
import 'core/platform.dart';
import 'core/storage.dart';
import 'models/watch_progress.dart';
import 'providers/browse_provider.dart';
import 'providers/home_provider.dart';
import 'providers/library_provider.dart';
import 'providers/nav_provider.dart';
import 'providers/prebuffer_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/trakt_provider.dart';
import 'services/cinemeta_service.dart';
import 'services/duration_probe.dart';
import 'services/engine_service.dart';
import 'services/next_episode.dart';
import 'services/share_server.dart';
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
    await Hive.openBox<String>('nextup'),
  );

  // Torrent engine: warm it up at launch so the first Play is fast.
  // Windows only for now; Android/iOS get an in-process engine later.
  final engine = EngineService(
    cacheDir: (await engineCacheDir()).path,
    keepCache: settings.keepCache,
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

  final nextEpisodes = NextEpisodeService();
  final prebuffer = PrebufferProvider(
    await Hive.openBox<String>('prebuffer'),
    engine,
    settings,
    nextEpisodes,
  );

  // "Play on iPad": a fixed port and saved secret keep each episode's link the
  // same between sessions (so VLC remembers where you were).
  final share = ShareServer(
    engine,
    () => prebuffer.entries,
    token: settings.shareToken,
    preferredPort: 47321,
  );
  // Where the iPad stopped is estimated from how far it has read the file, and
  // saved so the episode shows up in Continue Watching on this PC.
  share.durationProbe = (it) => probeDuration(
    engine.streamUrl(
      infoHash: it.infoHash,
      fileIdx: it.fileIdx,
      trackers: it.trackers,
      name: it.name,
    ),
  );
  share.progressSink = (it, position, duration) async {
    final meta = it.meta;
    final videoId = it.videoId;
    if (meta == null || videoId == null) return;
    await library.saveProgress(
      WatchProgress(
        videoId: videoId,
        meta: meta,
        positionMs: position.inMilliseconds,
        durationMs: duration.inMilliseconds,
        updatedAt: DateTime.now(),
        source: it.source,
        season: it.season,
        episode: it.episode,
        episodeTitle: it.episodeTitle,
        device: 'iPad',
      ),
    );
  };
  // ...and the page tells you where you stopped on this PC.
  share.positionLookup = (it) =>
      it.videoId == null ? null : library.progressFor(it.videoId!)?.position;

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
        // Finds the next episode + a matching source (shared cache of show data).
        Provider.value(value: nextEpisodes),
        ChangeNotifierProvider.value(value: prebuffer),
        ChangeNotifierProvider.value(value: share),
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
