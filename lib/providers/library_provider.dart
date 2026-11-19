import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

import '../models/meta_item.dart';
import '../models/watch_progress.dart';

/// Favourites + watch progress, persisted in two Hive boxes.
/// Values are JSON strings (robust against schema changes).
class LibraryProvider extends ChangeNotifier {
  LibraryProvider(this._favBox, this._progressBox, [this._watchedBox]) {
    _load();
  }

  final Box<String> _favBox;
  final Box<String> _progressBox;

  /// Optional: ids of everything watched (movie imdb id, or `tt:season:ep`).
  final Box<String>? _watchedBox;
  final Set<String> _watched = {};

  /// Called when the user adds/removes a favourite (Trakt watchlist sync).
  void Function(MetaItem item, bool added)? onFavouriteChanged;

  /// Favourites, newest first.
  List<MetaItem> _favourites = const [];
  final Map<String, int> _favAdded = {};

  /// Every progress entry, keyed by videoId.
  final Map<String, WatchProgress> _progress = {};

  List<MetaItem> get favourites => _favourites;

  void _load() {
    final favs = <MapEntry<MetaItem, int>>[];
    for (final key in _favBox.keys) {
      try {
        final j = jsonDecode(_favBox.get(key)!) as Map<String, dynamic>;
        favs.add(
          MapEntry(
            MetaItem.fromJson(Map<String, dynamic>.from(j['meta'] as Map)),
            (j['added'] as num?)?.toInt() ?? 0,
          ),
        );
      } catch (_) {}
    }
    favs.sort((a, b) => b.value.compareTo(a.value));
    _favourites = favs.map((e) => e.key).toList();
    for (final e in favs) {
      _favAdded[e.key.id] = e.value;
    }

    for (final key in _watchedBox?.keys ?? const <dynamic>[]) {
      _watched.add('$key');
    }

    for (final key in _progressBox.keys) {
      try {
        final p = WatchProgress.fromJson(
          jsonDecode(_progressBox.get(key)!) as Map<String, dynamic>,
        );
        _progress[p.videoId] = p;
      } catch (_) {}
    }
  }

  // ---- favourites ---------------------------------------------------------

  bool isFavourite(String id) => _favAdded.containsKey(id);

  Future<void> toggleFavourite(MetaItem item) async {
    final wasFavourite = isFavourite(item.id);
    await _toggle(item);
    onFavouriteChanged?.call(item, !wasFavourite);
  }

  /// Add without notifying (used when importing from Trakt).
  Future<void> addFavouriteSilently(MetaItem item) async {
    if (!isFavourite(item.id)) await _toggle(item);
  }

  Future<void> removeFavouriteSilently(String id) async {
    if (!isFavourite(id)) return;
    final item = _favourites.firstWhere((m) => m.id == id);
    await _toggle(item);
  }

  Future<void> _toggle(MetaItem item) async {
    if (isFavourite(item.id)) {
      _favAdded.remove(item.id);
      _favourites = _favourites.where((m) => m.id != item.id).toList();
      await _favBox.delete(item.id);
    } else {
      final now = DateTime.now().millisecondsSinceEpoch;
      _favAdded[item.id] = now;
      _favourites = [item, ..._favourites];
      await _favBox.put(
        item.id,
        jsonEncode({'meta': item.toJson(), 'added': now}),
      );
    }
    notifyListeners();
  }

  // ---- progress -----------------------------------------------------------

  WatchProgress? progressFor(String videoId) => _progress[videoId];

  /// Items to resume, newest first. A series appears once, at the episode
  /// watched most recently.
  List<WatchProgress> get continueWatching {
    final latest = <String, WatchProgress>{};
    for (final p in _progress.values) {
      final cur = latest[p.meta.id];
      if (cur == null || p.updatedAt.isAfter(cur.updatedAt)) {
        latest[p.meta.id] = p;
      }
    }
    return latest.values.where((p) => p.resumable).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Most recently watched unfinished entry for a title (any episode).
  WatchProgress? resumeFor(String itemId) {
    WatchProgress? best;
    for (final p in _progress.values) {
      if (p.meta.id != itemId || !p.resumable) continue;
      if (best == null || p.updatedAt.isAfter(best.updatedAt)) best = p;
    }
    return best;
  }

  // ---- watched ------------------------------------------------------------

  /// Watched here (finished playback) or on Trakt.
  bool isWatched(String videoId) =>
      _watched.contains(videoId) || (_progress[videoId]?.finished ?? false);

  Future<void> markWatched(Iterable<String> ids) async {
    var changed = false;
    for (final id in ids) {
      if (_watched.add(id)) {
        changed = true;
        await _watchedBox?.put(id, '1');
      }
    }
    if (changed) notifyListeners();
  }

  /// Finished here, so Trakt may not know yet.
  List<WatchProgress> get finishedProgress =>
      _progress.values.where((p) => p.finished).toList();

  Future<void> saveProgress(WatchProgress p) async {
    // Don't litter the list with accidental 10-second plays.
    if (p.positionMs < 5000 && !_progress.containsKey(p.videoId)) return;
    _progress[p.videoId] = p;
    await _progressBox.put(p.videoId, jsonEncode(p.toJson()));
    if (p.finished) await markWatched([p.videoId]);
    notifyListeners();
  }

  /// Remove from Continue Watching (all episodes of that title).
  Future<void> clearProgressFor(String itemId) async {
    final ids = _progress.values
        .where((p) => p.meta.id == itemId)
        .map((p) => p.videoId)
        .toList();
    for (final id in ids) {
      _progress.remove(id);
    }
    await _progressBox.deleteAll(ids);
    notifyListeners();
  }
}
