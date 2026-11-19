import 'meta_item.dart';
import 'stream_source.dart';

/// "You finished an episode; this is what to watch next." Kept per series.
/// Shown on Home and in the Library, and used by the details page's
/// "Play next" button.
class NextUp {
  const NextUp({
    required this.meta,
    required this.episode,
    required this.updatedAt,
    this.reference,
  });

  /// The series (a summary is enough).
  final MetaItem meta;

  /// The episode to watch next.
  final Episode episode;

  /// The source of the episode just finished. The next episode's source is
  /// matched to it (same quality/release group) when you press play.
  final StreamSource? reference;
  final DateTime updatedAt;

  String get videoId => episode.id;

  /// "S2 E4  -  Episode title"
  String get label =>
      'S${episode.season} E${episode.number}  -  ${episode.title}';

  Map<String, dynamic> toJson() => {
    'meta': meta.toJson(),
    'episode': episode.toJson(),
    'reference': reference?.toJson(),
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory NextUp.fromJson(Map<String, dynamic> j) => NextUp(
    meta: MetaItem.fromJson(Map<String, dynamic>.from(j['meta'] as Map)),
    episode: Episode.fromJson(Map<String, dynamic>.from(j['episode'] as Map)),
    reference: j['reference'] == null
        ? null
        : StreamSource.fromStored(
            Map<String, dynamic>.from(j['reference'] as Map),
          ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (j['updatedAt'] as num).toInt(),
    ),
  );
}
