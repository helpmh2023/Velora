import 'dart:convert';

import 'meta_item.dart';
import 'stream_source.dart';

/// Something the user asked to download ahead of time: which title/episode, and
/// exactly which source + file, so it can be played (and shown) later.
class PrebufferEntry {
  const PrebufferEntry({
    required this.meta,
    required this.videoId,
    required this.label,
    required this.source,
    required this.fileIdx,
    this.season,
    this.episode,
    this.episodeTitle,
    this.size,
    this.partial = false,
    required this.addedAt,
  });

  final MetaItem meta;

  /// Movie id, or the episode id (`tt:season:episode`).
  final String videoId;

  /// "Show name  -  S1 E2  -  Title" style text for lists.
  final String label;
  final StreamSource source;

  /// Position of the video file inside the torrent.
  final int fileIdx;
  final int? season;
  final int? episode;
  final String? episodeTitle;
  final int? size;

  /// Only the start of the file was requested.
  final bool partial;

  /// When it was queued (orders it among Continue Watching cards).
  final DateTime addedAt;

  String get key => videoId;

  Map<String, dynamic> toJson() => {
    'meta': meta.toJson(),
    'videoId': videoId,
    'label': label,
    'source': source.toJson(),
    'fileIdx': fileIdx,
    'season': season,
    'episode': episode,
    'episodeTitle': episodeTitle,
    'size': size,
    'partial': partial,
    'addedAt': addedAt.millisecondsSinceEpoch,
  };

  String encode() => jsonEncode(toJson());

  factory PrebufferEntry.fromJson(Map<String, dynamic> j) => PrebufferEntry(
    meta: MetaItem.fromJson(Map<String, dynamic>.from(j['meta'] as Map)),
    videoId: '${j['videoId']}',
    label: '${j['label'] ?? ''}',
    source: StreamSource.fromStored(
      Map<String, dynamic>.from(j['source'] as Map),
    ),
    fileIdx: (j['fileIdx'] as num?)?.toInt() ?? 0,
    season: (j['season'] as num?)?.toInt(),
    episode: (j['episode'] as num?)?.toInt(),
    episodeTitle: j['episodeTitle'] as String?,
    size: (j['size'] as num?)?.toInt(),
    partial: j['partial'] == true,
    addedAt: DateTime.fromMillisecondsSinceEpoch(
      (j['addedAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    ),
  );
}
