import '../models/meta_item.dart';
import '../models/stream_source.dart';
import 'cinemeta_service.dart';
import 'torrentio_service.dart';

/// The episode that follows [season]x[episode] in [show], or null if there is
/// none yet (last episode, or the next one has not aired).
///
/// - Specials (season 0) are skipped unless you are currently in them.
/// - An episode with no air date is assumed to be available.
Episode? nextEpisodeAfter(
  MetaItem show,
  int season,
  int episode, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final all = [...show.episodes]
    ..sort((a, b) {
      final s = a.season.compareTo(b.season);
      return s != 0 ? s : a.number.compareTo(b.number);
    });

  for (final e in all) {
    final after =
        e.season > season || (e.season == season && e.number > episode);
    if (!after) continue;
    if (e.season == 0 && season != 0) continue; // never jump into specials
    if (e.number <= 0) continue;
    final aired = e.released == null || !e.released!.isAfter(today);
    // The very next episode not having aired means: nothing to play yet. Do
    // not skip ahead to a later one.
    return aired ? e : null;
  }
  return null;
}

/// Chooses the source for the next episode that best matches [reference], the
/// one you were just watching, so quality and release group stay consistent.
///
/// Order of preference:
///  1. same Torrentio "binge group" (same show release/encode), most seeded
///  2. the very same torrent (a season pack already downloading)
///  3. same quality tier and provider, then same quality tier
///  4. otherwise the most seeded source overall
/// With no [reference], the most seeded 1080p, else the most seeded overall.
StreamSource? pickSimilarSource(
  List<StreamSource> candidates,
  StreamSource? reference,
) {
  final usable = candidates.where((s) => s.seeders > 0).toList();
  if (usable.isEmpty) return null;

  StreamSource? best(Iterable<StreamSource> list) {
    StreamSource? top;
    for (final s in list) {
      if (top == null ||
          s.seeders > top.seeders ||
          (s.seeders == top.seeders && s.quality.index < top.quality.index)) {
        top = s;
      }
    }
    return top;
  }

  if (reference != null) {
    final group = reference.bingeGroup;
    if (group != null && group.isNotEmpty) {
      final same = usable.where((s) => s.bingeGroup == group);
      final b = best(same);
      if (b != null) return b;
    }
    final samePack = usable.where((s) => s.infoHash == reference.infoHash);
    final pack = best(samePack);
    if (pack != null) return pack;

    final sameQ = usable.where((s) => s.quality == reference.quality);
    final sameQP = sameQ.where((s) => s.provider == reference.provider);
    final q = best(sameQP) ?? best(sameQ);
    if (q != null) return q;
    return best(usable);
  }

  return best(usable.where((s) => s.quality == Quality.fhd)) ?? best(usable);
}

/// Finds what plays next and where to get it. Network calls are cached/cheap
/// enough to run in the background while an episode is still playing.
class NextEpisodeService {
  NextEpisodeService({CinemetaService? cinemeta, TorrentioService? torrentio})
    : _cinemeta = cinemeta ?? CinemetaService(),
      _torrentio = torrentio ?? TorrentioService();

  final CinemetaService _cinemeta;
  final TorrentioService _torrentio;
  final Map<String, MetaItem> _full = {};

  /// [show] may be a summary without episodes (e.g. from Continue Watching).
  Future<MetaItem> _withEpisodes(MetaItem show) async {
    if (show.episodes.isNotEmpty) return show;
    return _full[show.id] ??= await _cinemeta.meta('series', show.id);
  }

  Future<Episode?> nextEpisode(MetaItem show, int season, int episode) async {
    final full = await _withEpisodes(show);
    return nextEpisodeAfter(full, season, episode);
  }

  /// Best source for [next], matched to [reference]. Null if none has seeders.
  Future<StreamSource?> sourceFor(Episode next, StreamSource? reference) async {
    final list = await _torrentio.streams('series', next.id);
    return pickSimilarSource(list, reference);
  }
}
