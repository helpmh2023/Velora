import 'package:flutter/foundation.dart';

import '../models/meta_item.dart';
import '../services/cinemeta_service.dart';

/// How a catalog is ordered/filtered. Each maps to a Cinemeta catalog id.
enum BrowseMode {
  /// Cinemeta `top`: what is popular now. Genre filter allowed.
  popular('Popular', 'top'),

  /// Cinemeta `imdbRating`: its featured/rated list. Genre filter allowed.
  featured('Featured', 'imdbRating'),

  /// Cinemeta `year`: titles from one year (the "genre" slot holds the year,
  /// so a genre cannot be combined with it).
  year('By year', 'year');

  const BrowseMode(this.label, this.catalogId);
  final String label;
  final String catalogId;
}

/// Pageable, filterable catalog for one type (movies or series).
/// Lives for the whole app session so switching tabs keeps your place.
class BrowseProvider extends ChangeNotifier {
  BrowseProvider(this.type, this._service, {DateTime? now})
    : _currentYear = (now ?? DateTime.now()).year;

  /// `movie` or `series`.
  final String type;
  final CinemetaService _service;
  final int _currentYear;

  static const _movieGenres = [
    'Action',
    'Adventure',
    'Animation',
    'Biography',
    'Comedy',
    'Crime',
    'Documentary',
    'Drama',
    'Family',
    'Fantasy',
    'History',
    'Horror',
    'Mystery',
    'Romance',
    'Sci-Fi',
    'Sport',
    'Thriller',
    'War',
    'Western',
  ];
  static const _seriesGenres = [
    ..._movieGenres,
    'Reality-TV',
    'Talk-Show',
    'Game-Show',
  ];

  /// Stop after this many titles per view (keeps memory and scrolling sane).
  static const maxItems = 600;

  List<String> get genres => type == 'series' ? _seriesGenres : _movieGenres;

  /// Years offered in "By year" mode, newest first.
  List<String> get years => [
    for (var y = _currentYear; y >= _currentYear - 40; y--) '$y',
  ];

  BrowseMode _mode = BrowseMode.popular;
  BrowseMode get mode => _mode;

  /// A genre (popular/featured) or a year (year mode); null = no filter.
  String? _filter;
  String? get filter => _filter;

  final List<MetaItem> _items = [];
  List<MetaItem> get items => List.unmodifiable(_items);
  final Set<String> _seen = {};

  bool _loading = false;
  bool get loading => _loading;

  bool _hasMore = true;
  bool get hasMore => _hasMore;

  String? _error;
  String? get error => _error;

  /// Where the user had scrolled to; restored when the tab is reopened.
  double scrollOffset = 0;

  /// Bumped on every reset so a slow response for an old filter is ignored.
  int _generation = 0;

  /// First visit: fetch page one.
  Future<void> ensureLoaded() async {
    if (_items.isEmpty && !_loading && _error == null) await _reset();
  }

  Future<void> setMode(BrowseMode m) async {
    if (m == _mode) return;
    _mode = m;
    _filter = m == BrowseMode.year ? '$_currentYear' : null;
    await _reset();
  }

  Future<void> setFilter(String? f) async {
    if (f == _filter) return;
    _filter = f;
    await _reset();
  }

  Future<void> retry() => _items.isEmpty ? _reset() : loadMore();

  Future<void> _reset() {
    _generation++;
    _items.clear();
    _seen.clear();
    _hasMore = true;
    _error = null;
    scrollOffset = 0;
    _loading = false; // a stale request may still be in flight; it is ignored
    return loadMore();
  }

  Future<void> loadMore() async {
    if (_loading || !_hasMore) return;
    final gen = _generation;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final page = await _service.catalog(
        type,
        id: _mode.catalogId,
        genre: _filter,
        skip: _items.length,
      );
      if (gen != _generation) return; // user changed the filter meanwhile
      var added = 0;
      for (final m in page) {
        if (_seen.add(m.id)) {
          _items.add(m);
          added++;
        }
      }
      // An empty (or all-duplicate) page means the catalog is exhausted.
      if (added == 0 || _items.length >= maxItems) _hasMore = false;
    } catch (e) {
      if (gen != _generation) return;
      _error = '$e';
    } finally {
      if (gen == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }
}

class MoviesBrowse extends BrowseProvider {
  MoviesBrowse(CinemetaService service, {DateTime? now})
    : super('movie', service, now: now);
}

class SeriesBrowse extends BrowseProvider {
  SeriesBrowse(CinemetaService service, {DateTime? now})
    : super('series', service, now: now);
}
