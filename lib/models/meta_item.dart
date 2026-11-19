import '../core/images.dart';

class Episode {
  const Episode({
    required this.id,
    required this.season,
    required this.number,
    required this.title,
    this.overview,
    this.thumbnail,
    this.released,
  });

  final String id; // e.g. tt0944947:1:1  (what Torrentio wants)
  final int season;
  final int number;
  final String title;
  final String? overview;
  final String? thumbnail;
  final DateTime? released;

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
    id: '${j['id']}',
    season: (j['season'] as num?)?.toInt() ?? 0,
    number: ((j['number'] ?? j['episode']) as num?)?.toInt() ?? 0,
    title: '${j['name'] ?? j['title'] ?? 'Episode'}',
    overview: (j['overview'] ?? j['description']) as String?,
    thumbnail: j['thumbnail'] as String?,
    released: DateTime.tryParse('${j['released'] ?? j['firstAired'] ?? ''}'),
  );
}

class MetaItem {
  const MetaItem({
    required this.id,
    required this.type,
    required this.name,
    this.poster,
    this.background,
    this.logo,
    this.description,
    this.releaseInfo,
    this.runtime,
    this.rating,
    this.genres = const [],
    this.cast = const [],
    this.directors = const [],
    this.episodes = const [],
  });

  final String id; // IMDb id, e.g. tt1234567
  final String type; // movie | series
  final String name;
  final String? poster;
  final String? background;
  final String? logo;
  final String? description;
  final String? releaseInfo;
  final String? runtime;
  final double? rating;
  final List<String> genres;
  final List<String> cast;
  final List<String> directors;
  final List<Episode> episodes;

  bool get isSeries => type == 'series';

  /// Sharp images (see core/images.dart).
  String? get posterImage => upscalePoster(poster);
  String? get heroImage => upscaleBackground(background);
  String? get logoImage => upscaleLogo(logo);

  List<int> get seasons {
    final s = {for (final e in episodes) e.season}.toList()..sort();
    final real = s.where((n) => n > 0).toList();
    return real.isEmpty ? s : real;
  }

  List<Episode> episodesOf(int season) =>
      episodes.where((e) => e.season == season).toList()
        ..sort((a, b) => a.number.compareTo(b.number));

  static List<String> _strings(dynamic v) {
    if (v is List) return v.map((e) => '$e').toList();
    if (v is String && v.isNotEmpty) return [v];
    return const [];
  }

  /// Compact form for storing favourites / continue-watching entries.
  /// (Episodes are omitted: the details page re-fetches them.)
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'name': name,
    'poster': poster,
    'background': background,
    'logo': logo,
    'description': description,
    'releaseInfo': releaseInfo,
    'runtime': runtime,
    'imdbRating': rating?.toString(),
    'genres': genres,
  };

  factory MetaItem.fromJson(Map<String, dynamic> j) {
    final videos = j['videos'];
    return MetaItem(
      id: '${j['id'] ?? j['imdb_id']}',
      type: '${j['type']}',
      name: '${j['name']}',
      poster: j['poster'] as String?,
      background: j['background'] as String?,
      logo: j['logo'] as String?,
      description: j['description'] as String?,
      releaseInfo: (j['releaseInfo'] ?? j['year'])?.toString(),
      runtime: j['runtime'] as String?,
      rating: double.tryParse('${j['imdbRating']}'),
      genres: _strings(j['genres'] ?? j['genre']),
      cast: _strings(j['cast']),
      directors: _strings(j['director']),
      episodes: videos is List
          ? videos
                .whereType<Map<String, dynamic>>()
                .map(Episode.fromJson)
                .toList()
          : const [],
    );
  }
}
