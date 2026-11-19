import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/meta_item.dart';
import '../services/cinemeta_service.dart';

enum LoadState { loading, ready, error }

class HomeRow {
  const HomeRow(this.title, this.items);
  final String title;
  final List<MetaItem> items;
}

class _RowSpec {
  const _RowSpec(this.title, this.type, this.catalog, [this.genre]);
  final String title;
  final String type;
  final String catalog;
  final String? genre;
}

class HomeProvider extends ChangeNotifier {
  HomeProvider(this._service);

  final CinemetaService _service;

  static const _specs = [
    _RowSpec('Trending Movies', 'movie', 'top'),
    _RowSpec('Trending Series', 'series', 'top'),
    _RowSpec('Top Rated Movies', 'movie', 'imdbRating'),
    _RowSpec('Top Rated Series', 'series', 'imdbRating'),
    _RowSpec('Action', 'movie', 'top', 'Action'),
    _RowSpec('Sci-Fi', 'movie', 'top', 'Sci-Fi'),
    _RowSpec('Comedy', 'movie', 'top', 'Comedy'),
    _RowSpec('Drama Series', 'series', 'top', 'Drama'),
  ];

  LoadState _state = LoadState.loading;
  LoadState get state => _state;

  String? _error;
  String? get error => _error;

  List<MetaItem> _hero = const [];
  List<MetaItem> get hero => _hero;

  List<HomeRow> _rows = const [];
  List<HomeRow> get rows => _rows;

  Completer<void> _ready = Completer<void>();

  /// Completes when the first load has finished (success or failure), so the
  /// splash can wait on it without ever hanging.
  Future<void> get ready => _ready.future;

  Future<void> load() async {
    if (_state != LoadState.loading) {
      _state = LoadState.loading;
      _error = null;
      notifyListeners();
    }
    if (_ready.isCompleted) _ready = Completer<void>();

    final results = await Future.wait(
      _specs.map((s) async {
        try {
          final items = await _service.catalog(
            s.type,
            id: s.catalog,
            genre: s.genre,
          );
          return HomeRow(s.title, items);
        } catch (e) {
          _error = '$e';
          return HomeRow(s.title, const []);
        }
      }),
    );

    _rows = results.where((r) => r.items.isNotEmpty).toList();
    _hero = _pickHero(_rows);

    if (_rows.isEmpty) {
      _state = LoadState.error;
      _error ??= 'Nothing came back from Cinemeta.';
    } else {
      _state = LoadState.ready;
      _error = null;
    }
    notifyListeners();
    if (!_ready.isCompleted) _ready.complete();
  }

  /// A few trending movies and series with a backdrop and a blurb,
  /// interleaved so the carousel alternates between the two.
  static List<MetaItem> _pickHero(List<HomeRow> rows) {
    bool good(MetaItem m) =>
        m.heroImage != null && (m.description?.isNotEmpty ?? false);

    List<MetaItem> from(String title) => rows
        .where((r) => r.title == title)
        .expand((r) => r.items)
        .where(good)
        .take(4)
        .toList();

    final movies = from('Trending Movies');
    final series = from('Trending Series');
    final out = <MetaItem>[];
    for (var i = 0; i < 4; i++) {
      if (i < movies.length) out.add(movies[i]);
      if (i < series.length) out.add(series[i]);
    }
    return out;
  }
}
