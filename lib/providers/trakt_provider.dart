import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/meta_item.dart';
import '../models/watch_progress.dart';
import '../services/cinemeta_service.dart';
import '../services/pkce_login.dart';
import '../services/token_store.dart';
import '../services/trakt_service.dart';
import 'library_provider.dart';
import 'settings_provider.dart';

enum TraktState {
  /// No client id/secret entered yet.
  notConfigured,

  /// Credentials saved; not signed in.
  disconnected,

  /// Showing a code; waiting for the user to approve on trakt.tv.
  awaitingApproval,
  connected,
}

/// Trakt.tv: device-code login, scrobbling, and two-way sync of watch history,
/// in-progress playback and the watchlist (mapped to "My List").
class TraktProvider extends ChangeNotifier {
  TraktProvider({
    required TraktService service,
    required TokenStore store,
    required LibraryProvider library,
    required SettingsProvider settings,
    CinemetaService? cinemeta,
    Future<void> Function(Uri url)? openUrl,
    int loopbackPort = defaultLoopbackPort,
  }) : _api = service,
       _store = store,
       _library = library,
       _settings = settings,
       _cinemeta = cinemeta ?? CinemetaService(),
       _openUrl = openUrl ?? _defaultOpenUrl,
       _loopbackPort = loopbackPort;

  final TraktService _api;
  final TokenStore _store;
  final LibraryProvider _library;
  final SettingsProvider _settings;
  final CinemetaService _cinemeta;
  final Future<void> Function(Uri url) _openUrl;
  final int _loopbackPort;

  /// Redirect URI the user registers on their Trakt app (PKCE sign-in).
  static const defaultLoopbackPort = 8765;
  static const redirectUriHint =
      'http://localhost:$defaultLoopbackPort/callback';

  static Future<void> _defaultOpenUrl(Uri url) async {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  static const _kId = 'trakt.clientId';
  static const _kSecret = 'trakt.clientSecret';
  static const _kTokens = 'trakt.tokens';

  TraktCreds? _creds;
  TraktTokens? _tokens;

  TraktState _state = TraktState.notConfigured;
  TraktState get state => _state;

  DeviceCode? _code;
  DeviceCode? get deviceCode => _code;

  String? _message; // last status / error for the UI
  String? get message => _message;

  bool _syncing = false;
  bool get syncing => _syncing;

  bool _cancelLogin = false;

  String? get username => _settings.traktUser;
  bool get connected => _state == TraktState.connected;

  /// Saved client id (for showing in the form); the secret is never exposed.
  String? get clientId => _creds?.clientId;

  // ---- startup -------------------------------------------------------------

  Future<void> init() async {
    final id = await _store.read(_kId);
    final secret = await _store.read(_kSecret);
    if (id != null && id.isNotEmpty) {
      _creds = TraktCreds(
        id,
        (secret == null || secret.isEmpty) ? null : secret,
      );
    }
    final raw = await _store.read(_kTokens);
    if (raw != null) {
      try {
        _tokens = TraktTokens.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      } catch (_) {
        _tokens = null;
      }
    }
    _state = _creds == null
        ? TraktState.notConfigured
        : (_tokens == null ? TraktState.disconnected : TraktState.connected);
    notifyListeners();

    _wireLibrary();
    if (connected) unawaited(sync(quiet: true));
  }

  void _wireLibrary() {
    _library.onFavouriteChanged = (item, added) {
      if (connected && _settings.traktWatchlist) {
        unawaited(_pushWatchlist(item, added));
      }
    };
  }

  // ---- credentials -----------------------------------------------------------

  /// [clientSecret] is optional: apps created on Trakt today have none and
  /// sign in with PKCE. Older apps with a secret use the device-code flow.
  Future<void> saveCredentials(
    String clientId, [
    String clientSecret = '',
  ]) async {
    final id = clientId.trim();
    final secret = clientSecret.trim();
    if (id.isEmpty) {
      _message = 'Enter the Client ID from your Trakt app.';
      notifyListeners();
      return;
    }
    await _store.write(_kId, id);
    await _store.write(_kSecret, secret.isEmpty ? null : secret);
    _creds = TraktCreds(id, secret.isEmpty ? null : secret);
    _message = null;
    if (_state == TraktState.notConfigured) _state = TraktState.disconnected;
    notifyListeners();
  }

  // ---- login -----------------------------------------------------------------

  /// True when sign-in uses a browser redirect (no client secret saved).
  bool get usesBrowserLogin => _creds != null && _creds!.clientSecret == null;

  /// The Trakt approval page for the current browser sign-in, if any.
  Uri? get authUrl => _authUrl;
  Uri? _authUrl;
  LoopbackReceiver? _receiver;

  Future<void> startLogin() async {
    final creds = _creds;
    if (creds == null || _state == TraktState.awaitingApproval) return;
    _cancelLogin = false;
    _message = null;
    if (creds.clientSecret == null) return _loginBrowser(creds);
    return _loginDevice(creds);
  }

  /// Authorization code + PKCE, catching the redirect on a loopback port.
  Future<void> _loginBrowser(TraktCreds creds) async {
    LoopbackReceiver? receiver;
    try {
      final pkce = PkceChallenge.generate();
      final state = PkceChallenge.randomString(24);
      receiver = await LoopbackReceiver.bind(_loopbackPort);
      _receiver = receiver;
      final redirect = 'http://localhost:${receiver.port}/callback';
      _authUrl = _api.authorizeUrl(creds, redirect, state, pkce.challenge);
      _state = TraktState.awaitingApproval;
      notifyListeners();

      await _openUrl(_authUrl!);
      final cb = await receiver.result.timeout(const Duration(minutes: 5));
      if (cb.error == 'cancelled') return _failLogin(null);
      if (cb.error != null) {
        return _failLogin(
          cb.error == 'access_denied'
              ? 'Login was denied on trakt.tv.'
              : 'Trakt did not return a login code (${cb.error}).',
        );
      }
      if (cb.state != state) {
        return _failLogin(
          'The login response did not match this request. Try again.',
        );
      }
      final tokens = await _api.exchangeCode(
        creds,
        cb.code!,
        pkce.verifier,
        redirect,
      );
      await _finishLogin(tokens);
    } on TimeoutException {
      _failLogin('Login timed out. Start again.');
    } on SocketException {
      _failLogin(
        'Could not listen on port $_loopbackPort for the Trakt redirect. '
        'Close whatever is using it and try again.',
      );
    } catch (e) {
      _failLogin('$e');
    } finally {
      _receiver = null;
      await receiver?.close();
    }
  }

  /// Device-code flow (apps that have a client secret).
  Future<void> _loginDevice(TraktCreds creds) async {
    try {
      final code = await _api.requestDeviceCode(creds);
      _code = code;
      _state = TraktState.awaitingApproval;
      notifyListeners();

      final deadline = DateTime.now().add(Duration(seconds: code.expiresIn));
      var interval = code.interval;
      while (!_cancelLogin && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(Duration(seconds: interval));
        if (_cancelLogin) break;
        final out = await _api.pollDeviceToken(code, creds);
        switch (out.status) {
          case PollStatus.success:
            await _finishLogin(out.tokens!);
            return;
          case PollStatus.pending:
            break;
          case PollStatus.slowDown:
            interval += 1;
          case PollStatus.expired:
            return _failLogin('The code expired. Start again.');
          case PollStatus.denied:
            return _failLogin('Login was denied on trakt.tv.');
          case PollStatus.invalid:
            return _failLogin(
              'Trakt rejected the Client ID/Secret. Check them and try again.',
            );
        }
      }
      if (_cancelLogin) {
        _failLogin(null);
      } else {
        _failLogin('The code expired. Start again.');
      }
    } catch (e) {
      _failLogin('$e');
    }
  }

  void cancelLogin() {
    _cancelLogin = true;
    _receiver?.close(); // unblocks the browser flow, which then resets state
    _failLogin(null);
  }

  void _failLogin(String? msg) {
    _code = null;
    _authUrl = null;
    _message = msg;
    _state = _creds == null
        ? TraktState.notConfigured
        : TraktState.disconnected;
    notifyListeners();
  }

  Future<void> _finishLogin(TraktTokens t) async {
    await _setTokens(t);
    _code = null;
    _authUrl = null;
    _state = TraktState.connected;
    _message = null;
    try {
      _settings.traktUser = await _api.username(_creds!, t.accessToken);
    } catch (_) {}
    notifyListeners();
    unawaited(sync());
  }

  Future<void> _setTokens(TraktTokens t) async {
    _tokens = t;
    await _store.write(_kTokens, jsonEncode(t.toJson()));
  }

  Future<void> logout() async {
    final creds = _creds;
    final tokens = _tokens;
    _tokens = null;
    await _store.write(_kTokens, null);
    _settings.traktUser = null;
    _settings.traktLastSync = null;
    _settings.traktWatchlistIds = {};
    _state = creds == null ? TraktState.notConfigured : TraktState.disconnected;
    notifyListeners();
    if (creds != null && tokens != null) await _api.revoke(tokens, creds);
  }

  /// Remove the saved Client ID/Secret as well.
  Future<void> forgetCredentials() async {
    await logout();
    await _store.write(_kId, null);
    await _store.write(_kSecret, null);
    _creds = null;
    _state = TraktState.notConfigured;
    notifyListeners();
  }

  // ---- authenticated calls ------------------------------------------------------

  /// Runs [call] with a valid token, refreshing it first when it is about to
  /// expire and once more if Trakt answers 401.
  Future<T> _authed<T>(
    Future<T> Function(TraktCreds c, String token) call,
  ) async {
    final creds = _creds;
    if (creds == null || _tokens == null) {
      throw TraktException('Not connected to Trakt.');
    }
    if (_tokens!.expiringSoon) await _refresh();
    try {
      return await call(creds, _tokens!.accessToken);
    } on TraktException catch (e) {
      if (!e.unauthorized) rethrow;
      await _refresh();
      return call(creds, _tokens!.accessToken);
    }
  }

  Future<void> _refresh() async {
    try {
      await _setTokens(await _api.refresh(_tokens!, _creds!));
    } on TraktException catch (e) {
      // A dead refresh token means signing in again.
      if (e.statusCode == 400 || e.statusCode == 401) {
        _tokens = null;
        await _store.write(_kTokens, null);
        _state = TraktState.disconnected;
        _message = 'Your Trakt login expired. Connect again.';
        notifyListeners();
      }
      rethrow;
    }
  }

  // ---- scrobbling ----------------------------------------------------------

  TraktMedia? _mediaFor(MetaItem meta, int? season, int? episode) {
    if (!meta.id.startsWith('tt')) return null; // Trakt needs an IMDb id
    return meta.isSeries
        ? (season != null && episode != null
              ? TraktMedia.episode(meta.id, season, episode)
              : null)
        : TraktMedia.movie(meta.id);
  }

  /// [action]: `start`, `pause` or `stop`. Never throws; scrobbling must not
  /// get in the way of playback.
  void scrobble(
    String action,
    MetaItem meta, {
    int? season,
    int? episode,
    required Duration position,
    required Duration duration,
  }) {
    if (!connected || !_settings.traktScrobble) return;
    if (duration <= Duration.zero) return;
    final media = _mediaFor(meta, season, episode);
    if (media == null) return;
    final pct = position.inMilliseconds / duration.inMilliseconds * 100;
    unawaited(
      _authed((c, t) => _api.scrobble(action, media, pct, c, t)).catchError(
        (Object e) => debugPrint('[trakt] scrobble $action failed: $e'),
      ),
    );
  }

  Future<void> _pushWatchlist(MetaItem item, bool added) async {
    if (!item.id.startsWith('tt')) return;
    try {
      await _authed(
        (c, t) => _api.setWatchlist(
          c,
          t,
          movies: item.isSeries ? const [] : [item.id],
          shows: item.isSeries ? [item.id] : const [],
          add: added,
        ),
      );
      // Keep our "known remote" snapshot in step so the next sync does not
      // think this was a remote change.
      final ids = _settings.traktWatchlistIds;
      added ? ids.add(item.id) : ids.remove(item.id);
      _settings.traktWatchlistIds = ids;
    } catch (e) {
      debugPrint('[trakt] watchlist push failed: $e');
    }
  }

  // ---- sync ----------------------------------------------------------------

  /// Two-way sync. [quiet] hides the success message (background startup run).
  /// A second call while one is running waits for it instead of starting
  /// another.
  Future<void> sync({bool quiet = false}) {
    if (!connected) return Future.value();
    return _inflight ??= _runSync(quiet).whenComplete(() => _inflight = null);
  }

  Future<void>? _inflight;

  Future<void> _runSync(bool quiet) async {
    _syncing = true;
    _message = null;
    notifyListeners();
    try {
      await _syncHistory();
      await _syncPlayback();
      if (_settings.traktWatchlist) await _syncWatchlist();
      _settings.traktLastSync = DateTime.now();
      if (!quiet) _message = 'Synced.';
    } catch (e) {
      _message = 'Sync problem: $e';
    }
    _syncing = false;
    notifyListeners();
  }

  /// Trakt -> here: mark watched. Here -> Trakt: send what we finished.
  Future<void> _syncHistory() async {
    final movies = await _authed((c, t) => _api.watchedMovies(c, t));
    final shows = await _authed((c, t) => _api.watchedShows(c, t));

    final remote = <String>{...movies};
    for (final s in shows) {
      for (final (sn, ep) in s.episodes) {
        remote.add('${s.imdb}:$sn:$ep');
      }
    }
    await _library.markWatched(remote);

    // Finished here but unknown to Trakt (e.g. watched while offline/disconnected).
    final newMovies = <String>[];
    final newEpisodes = <String, List<(int, int)>>{};
    for (final p in _library.finishedProgress) {
      if (remote.contains(p.videoId)) continue;
      if (p.season != null && p.episode != null) {
        newEpisodes.putIfAbsent(p.meta.id, () => []).add((
          p.season!,
          p.episode!,
        ));
      } else if (p.meta.id.startsWith('tt')) {
        newMovies.add(p.meta.id);
      }
    }
    if (newMovies.isNotEmpty || newEpisodes.isNotEmpty) {
      await _authed(
        (c, t) => _api.addToHistory(
          c,
          t,
          movies: newMovies,
          shows: [
            for (final e in newEpisodes.entries) WatchedShow(e.key, e.value),
          ],
        ),
      );
    }
  }

  /// Things partly watched elsewhere appear under Continue Watching here.
  Future<void> _syncPlayback() async {
    final entries = await _authed((c, t) => _api.playback(c, t));
    var added = 0;
    for (final e in entries) {
      if (added >= 15) break;
      final m = e.media;
      final videoId = m.isEpisode
          ? '${m.imdb}:${m.season}:${m.episode}'
          : m.imdb;
      final local = _library.progressFor(videoId);
      if (local != null) continue; // we know better (and have a source)
      try {
        final meta = await _cinemeta.meta(
          m.isEpisode ? 'series' : 'movie',
          m.imdb,
        );
        final runtime = _runtime(meta.runtime, m.isEpisode);
        await _library.saveProgress(
          WatchProgress(
            videoId: videoId,
            meta: meta,
            positionMs: (runtime.inMilliseconds * (e.progress / 100)).round(),
            durationMs: runtime.inMilliseconds,
            updatedAt: DateTime.now(),
            season: m.season,
            episode: m.episode,
            episodeTitle: e.episodeTitle,
          ),
        );
        added++;
      } catch (_) {}
    }
  }

  static Duration _runtime(String? text, bool episode) {
    final minutes = int.tryParse(
      RegExp(r'\d+').firstMatch(text ?? '')?.group(0) ?? '',
    );
    return Duration(minutes: minutes ?? (episode ? 45 : 110));
  }

  /// Watchlist <-> My List, with removal detection via the last-seen snapshot.
  Future<void> _syncWatchlist() async {
    final remote = await _authed((c, t) => _api.watchlist(c, t));
    final remoteIds = {for (final e in remote) e.imdb};
    final lastRemote = _settings.traktWatchlistIds;
    final localIds = {for (final m in _library.favourites) m.id};

    // Removed on Trakt since last sync -> remove here.
    for (final id in lastRemote.difference(remoteIds)) {
      if (localIds.contains(id)) await _library.removeFavouriteSilently(id);
    }

    // On Trakt, not here -> add here (needs poster etc. from Cinemeta).
    var imported = 0;
    for (final e in remote) {
      if (imported >= 40) break;
      if (_library.isFavourite(e.imdb)) continue;
      // We removed it locally since the last sync; the removal is pushed below.
      if (lastRemote.contains(e.imdb)) continue;
      try {
        final meta = await _cinemeta.meta(
          e.isShow ? 'series' : 'movie',
          e.imdb,
        );
        await _library.addFavouriteSilently(meta);
        imported++;
      } catch (_) {}
    }

    // Here, not on Trakt -> add there.
    final toPushMovies = <String>[];
    final toPushShows = <String>[];
    for (final m in _library.favourites) {
      if (!m.id.startsWith('tt') || remoteIds.contains(m.id)) continue;
      (m.isSeries ? toPushShows : toPushMovies).add(m.id);
    }
    if (toPushMovies.isNotEmpty || toPushShows.isNotEmpty) {
      await _authed(
        (c, t) => _api.setWatchlist(
          c,
          t,
          movies: toPushMovies,
          shows: toPushShows,
          add: true,
        ),
      );
    }

    // Titles we removed locally while they were still on Trakt -> remove there.
    final toRemoveMovies = <String>[];
    final toRemoveShows = <String>[];
    for (final e in remote) {
      if (lastRemote.contains(e.imdb) && !_library.isFavourite(e.imdb)) {
        (e.isShow ? toRemoveShows : toRemoveMovies).add(e.imdb);
      }
    }
    if (toRemoveMovies.isNotEmpty || toRemoveShows.isNotEmpty) {
      await _authed(
        (c, t) => _api.setWatchlist(
          c,
          t,
          movies: toRemoveMovies,
          shows: toRemoveShows,
          add: false,
        ),
      );
    }

    _settings.traktWatchlistIds = {
      ...remoteIds.where(
        (id) => !toRemoveMovies.contains(id) && !toRemoveShows.contains(id),
      ),
      ...toPushMovies,
      ...toPushShows,
    };
  }
}
