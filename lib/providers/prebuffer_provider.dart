import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

import '../models/meta_item.dart';
import '../models/prebuffer_entry.dart';
import 'library_provider.dart';
import '../models/stream_source.dart';
import '../services/engine_service.dart';
import '../services/next_episode.dart';
import 'settings_provider.dart';

/// Downloads episodes ahead of time through the engine, so they play with no
/// wait (and can be streamed from this PC to another device). Keeps the list
/// of what was requested; the engine keeps the data and reports progress.
class PrebufferProvider extends ChangeNotifier {
  PrebufferProvider(this._box, this._engine, this._settings, this._next) {
    for (final raw in _box.values) {
      try {
        final e = PrebufferEntry.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        _entries[e.key] = e;
      } catch (_) {
        // Skip an unreadable record.
      }
    }
    _engine.addListener(_onEngine);
    if (_entries.isNotEmpty) {
      // Resume what was pending last time: the engine reloads its own jobs.
      _engine.start().catchError((Object _) {});
    }
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
  }

  final Box<String> _box;
  final EngineService _engine;
  final SettingsProvider _settings;
  final NextEpisodeService _next;
  final _entries = <String, PrebufferEntry>{};
  var _jobs = <String, PrebufferJob>{};
  final _speed = <String, double>{};
  DateTime _lastPoll = DateTime.now();
  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;

  /// Everything requested, newest first by label.
  List<PrebufferEntry> get entries {
    final l = _entries.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    return l;
  }

  PrebufferEntry? entryFor(String videoId) => _entries[videoId];

  /// The engine's progress for [videoId], if it is being pre-buffered.
  PrebufferJob? jobFor(String videoId) {
    final e = _entries[videoId];
    if (e == null) return null;
    return _jobs['${e.source.infoHash.toLowerCase()}/${e.fileIdx}'];
  }

  /// Download speed (bytes/s) of [videoId], measured between refreshes.
  double speedFor(String videoId) {
    final e = _entries[videoId];
    if (e == null) return 0;
    return _speed['${e.source.infoHash.toLowerCase()}/${e.fileIdx}'] ?? 0;
  }

  /// How many are still downloading (not ready, not failed).
  int get activeCount => _entries.keys.where((id) {
    final j = jobFor(id);
    return j == null || !(j.isReady || j.isError);
  }).length;

  /// The exact source that was pre-buffered for [videoId] (even while it is
  /// still downloading: playing it is better than asking again). Null if
  /// nothing was queued or the download failed.
  StreamSource? sourceFor(String videoId) {
    final e = _entries[videoId];
    if (e == null) return null;
    if (jobFor(videoId)?.isError ?? false) return null;
    return e.source;
  }

  /// Pre-buffered items to offer under Continue Watching: the ones not started
  /// yet (a started one shows as a normal resume card) and not finished.
  List<PrebufferEntry> continueCandidates(LibraryProvider lib) => [
    for (final e in _entries.values)
      if (!(jobFor(e.videoId)?.isError ?? false) &&
          !lib.isWatched(e.videoId) &&
          !(lib.progressFor(e.videoId)?.resumable ?? false))
        e,
  ];

  bool isReady(String videoId) => jobFor(videoId)?.isReady ?? false;

  /// Size of everything pre-buffered so far (bytes already on disk).
  int get downloadedBytes => _jobs.values.fold(0, (a, j) => a + j.done);

  void _onEngine() {
    if (_engine.state == EngineState.ready) refresh();
  }

  Future<void> refresh() async {
    if (_busy || _entries.isEmpty || _engine.baseUrl == null) return;
    _busy = true;
    try {
      final list = await _engine.prebufferJobs();
      if (_disposed) return;
      final next = {for (final j in list) '${j.hash}/${j.idx}': j};
      var changed = next.length != _jobs.length;
      if (!changed) {
        for (final e in next.entries) {
          final o = _jobs[e.key];
          if (o == null || o.done != e.value.done || o.state != e.value.state) {
            changed = true;
            break;
          }
        }
      }
      final now = DateTime.now();
      final dt = now.difference(_lastPoll).inMilliseconds / 1000;
      if (dt > 0.5) {
        for (final e in next.entries) {
          final before = _jobs[e.key]?.done;
          if (before == null) continue;
          final inst = (e.value.done - before) / dt;
          // Smooth it so the number does not jump around.
          _speed[e.key] = inst <= 0
              ? 0
              : ((_speed[e.key] ?? inst) * 0.6 + inst * 0.4);
        }
        _lastPoll = now;
      }
      _jobs = next;
      // Speed changes every poll, so keep the open panel live while anything downloads.
      if (changed || activeCount > 0) notifyListeners();
    } finally {
      _busy = false;
    }
  }

  /// Starts pre-buffering. Returns a message for the user if it cannot be
  /// done (cache limit, disk space, no peers), else null.
  Future<String?> start({
    required MetaItem meta,
    required String videoId,
    required String label,
    required StreamSource source,
    Episode? episode,
  }) async {
    if (_entries.containsKey(videoId) && !(jobFor(videoId)?.isError ?? false)) {
      return null; // already queued
    }
    try {
      await _engine.start();
    } catch (e) {
      return '$e';
    }
    final check = await _engine.inspect(
      infoHash: source.infoHash,
      fileIdx: source.fileIdx,
      trackers: source.trackers,
      name: source.release,
    );
    if (check.message != null) return check.message;
    final idx = check.idx;
    if (idx == null || idx < 0) {
      return 'Could not find this source on the network. Try another one.';
    }
    final size = check.size;
    final partial = _settings.prebufferStartOnly && size != null;
    // "Start only" = roughly the first 12 % of the file (about 7 minutes of an
    // hour-long episode): enough to start instantly while the rest streams in.
    final want = partial ? (size * 0.12).round() : null;
    final ok = await _engine.prebuffer(
      infoHash: source.infoHash,
      fileIdx: idx,
      label: label,
      want: want,
      trackers: source.trackers,
      name: source.release,
    );
    if (!ok) return 'The engine could not start the download.';
    final entry = PrebufferEntry(
      meta: meta,
      videoId: videoId,
      label: label,
      source: source,
      fileIdx: idx,
      season: episode?.season,
      episode: episode?.number,
      episodeTitle: episode?.title,
      size: size,
      partial: partial,
      addedAt: DateTime.now(),
    );
    _entries[entry.key] = entry;
    await _box.put(entry.key, entry.encode());
    notifyListeners();
    unawaited(refresh());
    return null;
  }

  Future<void> remove(String videoId) async {
    final e = _entries.remove(videoId);
    if (e == null) return;
    await _box.delete(videoId);
    _jobs.remove('${e.source.infoHash.toLowerCase()}/${e.fileIdx}');
    notifyListeners();
    await _engine.prebufferRemove(e.source.infoHash, e.fileIdx);
  }

  /// While watching [current], queue the next [Settings.prebufferAhead]
  /// episodes (each with a source matching [source]). Quiet: errors are ignored.
  Future<void> queueAhead({
    required MetaItem meta,
    required Episode current,
    required StreamSource source,
  }) async {
    var from = current;
    for (var i = 0; i < _settings.prebufferAhead; i++) {
      final ep = await _next.nextEpisode(meta, from.season, from.number);
      if (ep == null) return;
      final label =
          '${meta.name}  -  S${ep.season} E${ep.number}  -  ${ep.title}';
      if (!_entries.containsKey(ep.id)) {
        final src = await _next.sourceFor(ep, source);
        if (src == null) return;
        final msg = await start(
          meta: meta,
          videoId: ep.id,
          label: label,
          source: src,
          episode: ep,
        );
        if (msg != null) return; // out of room or no peers: stop quietly
      }
      from = ep;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _engine.removeListener(_onEngine);
    super.dispose();
  }
}
