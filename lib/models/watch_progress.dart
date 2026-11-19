import 'meta_item.dart';
import 'stream_source.dart';

/// Where the user is in one movie or episode. Also stores the source they
/// were watching, so "Continue Watching" can resume without the picker.
class WatchProgress {
  const WatchProgress({
    required this.videoId,
    required this.meta,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
    this.source,
    this.season,
    this.episode,
    this.episodeTitle,
  });

  /// Movie: IMDb id. Episode: `tt...:season:episode`.
  final String videoId;
  final MetaItem meta;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;
  final StreamSource? source;
  final int? season;
  final int? episode;
  final String? episodeTitle;

  Duration get position => Duration(milliseconds: positionMs);
  Duration get duration => Duration(milliseconds: durationMs);

  double get fraction =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);

  /// Watched to (nearly) the end: credits don't count.
  bool get finished =>
      durationMs > 0 &&
      (fraction >= 0.92 || durationMs - positionMs < 90 * 1000);

  /// Worth listing under Continue Watching (past the first minute, not done).
  bool get resumable => positionMs >= 60 * 1000 && !finished;

  String? get episodeLabel => season == null
      ? null
      : 'S$season E$episode${episodeTitle == null ? '' : '  -  $episodeTitle'}';

  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    'meta': meta.toJson(),
    'positionMs': positionMs,
    'durationMs': durationMs,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'source': source?.toJson(),
    'season': season,
    'episode': episode,
    'episodeTitle': episodeTitle,
  };

  factory WatchProgress.fromJson(Map<String, dynamic> j) => WatchProgress(
    videoId: '${j['videoId']}',
    meta: MetaItem.fromJson(Map<String, dynamic>.from(j['meta'] as Map)),
    positionMs: (j['positionMs'] as num).toInt(),
    durationMs: (j['durationMs'] as num).toInt(),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (j['updatedAt'] as num).toInt(),
    ),
    source: j['source'] == null
        ? null
        : StreamSource.fromStored(
            Map<String, dynamic>.from(j['source'] as Map),
          ),
    season: (j['season'] as num?)?.toInt(),
    episode: (j['episode'] as num?)?.toInt(),
    episodeTitle: j['episodeTitle'] as String?,
  );
}
