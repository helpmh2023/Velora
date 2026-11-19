import 'package:material_ui/material_ui.dart';

import '../../models/meta_item.dart';
import '../../models/stream_source.dart';
import '../../models/watch_progress.dart';
import 'player_screen.dart';

/// Builds the route to the player on [source]. If [resumeFrom] is meaningful
/// (past the first 30s and not within the last 60s) playback starts there.
/// [fullscreen] opens already fullscreen (used when moving to the next episode
/// while watching fullscreen).
Route<void> playerRoute({
  required StreamSource source,
  required MetaItem meta,
  required String videoId,
  String? subtitle,
  int? season,
  int? episode,
  String? episodeTitle,
  Duration? resumeFrom,
  Duration? knownDuration,
  bool fullscreen = false,
}) {
  Duration? start = resumeFrom;
  if (start != null) {
    final nearEnd =
        knownDuration != null &&
        knownDuration - start < const Duration(seconds: 60);
    if (start < const Duration(seconds: 30) || nearEnd) start = null;
  }
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, _, _) => PlayerScreen(
      source: source,
      title: meta.name,
      subtitle: subtitle,
      meta: meta,
      videoId: videoId,
      season: season,
      episode: episode,
      episodeTitle: episodeTitle,
      startAt: start,
      startFullscreen: fullscreen,
    ),
    transitionsBuilder: (_, a, _, child) =>
        FadeTransition(opacity: a, child: child),
  );
}

/// Opens the player on [source]; completes when the player is closed.
Future<void> openPlayer(
  BuildContext context, {
  required StreamSource source,
  required MetaItem meta,
  required String videoId,
  String? subtitle,
  int? season,
  int? episode,
  String? episodeTitle,
  Duration? resumeFrom,
  Duration? knownDuration,
  bool fullscreen = false,
}) {
  return Navigator.of(context).push(
    playerRoute(
      source: source,
      meta: meta,
      videoId: videoId,
      subtitle: subtitle,
      season: season,
      episode: episode,
      episodeTitle: episodeTitle,
      resumeFrom: resumeFrom,
      knownDuration: knownDuration,
      fullscreen: fullscreen,
    ),
  );
}

/// Resume a Continue Watching entry with its saved source and position.
/// Returns false if no source was saved (caller should open the details page).
Future<bool> resumeWatching(BuildContext context, WatchProgress p) async {
  final source = p.source;
  if (source == null) return false;
  await openPlayer(
    context,
    source: source,
    meta: p.meta,
    videoId: p.videoId,
    subtitle:
        p.episodeLabel ??
        [
          if (p.meta.releaseInfo != null) p.meta.releaseInfo!,
          'Movie',
        ].join('  -  '),
    season: p.season,
    episode: p.episode,
    episodeTitle: p.episodeTitle,
    resumeFrom: p.position,
    knownDuration: p.duration,
  );
  return true;
}
