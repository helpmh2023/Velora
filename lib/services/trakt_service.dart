import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class TraktException implements Exception {
  TraktException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;

  bool get unauthorized => statusCode == 401;
}

/// The Trakt "API app" the user registered at trakt.tv/oauth/applications.
class TraktCreds {
  const TraktCreds(this.clientId, [this.clientSecret]);
  final String clientId;

  /// Null for modern "public" apps (PKCE sign-in, no secret issued).
  final String? clientSecret;
}

class TraktTokens {
  const TraktTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  bool get expiringSoon =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(days: 7)));

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt.millisecondsSinceEpoch,
  };

  factory TraktTokens.fromJson(Map<String, dynamic> j) => TraktTokens(
    accessToken: '${j['access_token']}',
    refreshToken: '${j['refresh_token']}',
    expiresAt: DateTime.fromMillisecondsSinceEpoch(
      (j['expires_at'] as num).toInt(),
    ),
  );

  /// From Trakt's token response (`created_at` + `expires_in`, in seconds).
  factory TraktTokens.fromApi(Map<String, dynamic> j) {
    final created =
        (j['created_at'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final life = (j['expires_in'] as num?)?.toInt() ?? 7776000;
    return TraktTokens(
      accessToken: '${j['access_token']}',
      refreshToken: '${j['refresh_token']}',
      expiresAt: DateTime.fromMillisecondsSinceEpoch((created + life) * 1000),
    );
  }
}

class DeviceCode {
  const DeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.expiresIn,
    required this.interval,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final int expiresIn; // seconds
  final int interval; // seconds between polls

  factory DeviceCode.fromJson(Map<String, dynamic> j) => DeviceCode(
    deviceCode: '${j['device_code']}',
    userCode: '${j['user_code']}',
    verificationUrl: '${j['verification_url']}',
    expiresIn: (j['expires_in'] as num).toInt(),
    interval: (j['interval'] as num).toInt(),
  );
}

enum PollStatus { pending, slowDown, success, expired, denied, invalid }

class PollOutcome {
  const PollOutcome(this.status, [this.tokens]);
  final PollStatus status;
  final TraktTokens? tokens;
}

/// A title or episode as Trakt wants to be told about it.
class TraktMedia {
  const TraktMedia.movie(this.imdb) : season = null, episode = null;
  const TraktMedia.episode(this.imdb, int this.season, int this.episode);

  /// Movie IMDb id, or the SHOW's IMDb id for episodes.
  final String imdb;
  final int? season;
  final int? episode;

  bool get isEpisode => season != null;

  Map<String, dynamic> toScrobbleJson(double progress) => isEpisode
      ? {
          'show': {
            'ids': {'imdb': imdb},
          },
          'episode': {'season': season, 'number': episode},
          'progress': progress,
        }
      : {
          'movie': {
            'ids': {'imdb': imdb},
          },
          'progress': progress,
        };
}

class WatchedShow {
  const WatchedShow(this.imdb, this.episodes);
  final String imdb;

  /// `season:episode` pairs.
  final List<(int, int)> episodes;
}

class PlaybackEntry {
  const PlaybackEntry({
    required this.media,
    required this.progress,
    required this.title,
    this.episodeTitle,
  });

  final TraktMedia media;

  /// 0..100
  final double progress;
  final String title;
  final String? episodeTitle;
}

class WatchlistEntry {
  const WatchlistEntry(this.imdb, this.isShow, this.title);
  final String imdb;
  final bool isShow;
  final String title;
}

/// Thin client for api.trakt.tv (v2). Holds no state: callers pass creds/token.
class TraktService {
  TraktService({http.Client? client}) : _client = client ?? http.Client();

  static const base = 'https://api.trakt.tv';
  static const _timeout = Duration(seconds: 20);
  final http.Client _client;

  Map<String, String> _headers(TraktCreds c, [String? token]) => {
    'Content-Type': 'application/json',
    'trakt-api-version': '2',
    'trakt-api-key': c.clientId,
    'User-Agent': 'Velora',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<http.Response> _send(
    String method,
    String path,
    TraktCreds c, {
    String? token,
    Object? body,
  }) async {
    final uri = Uri.parse('$base$path');
    try {
      final req = http.Request(method, uri)..headers.addAll(_headers(c, token));
      if (body != null) req.body = jsonEncode(body);
      final streamed = await _client.send(req).timeout(_timeout);
      return await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw TraktException('Trakt did not answer in time.');
    } catch (e) {
      throw TraktException('Could not reach Trakt ($e)');
    }
  }

  dynamic _decode(http.Response r) {
    if (r.body.isEmpty) return null;
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  void _check(http.Response r, String what) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    final detail = switch (r.statusCode) {
      401 => 'not signed in (or the token expired)',
      403 => 'the Trakt app key was rejected',
      404 => 'not found',
      429 => 'too many requests, try again shortly',
      _ => 'HTTP ${r.statusCode}',
    };
    throw TraktException(
      'Trakt: $what failed - $detail',
      statusCode: r.statusCode,
    );
  }

  // ---- OAuth device flow ---------------------------------------------------

  Future<DeviceCode> requestDeviceCode(TraktCreds c) async {
    final r = await _send(
      'POST',
      '/oauth/device/code',
      c,
      body: {'client_id': c.clientId},
    );
    _check(r, 'requesting a login code');
    return DeviceCode.fromJson(_decode(r) as Map<String, dynamic>);
  }

  /// One poll. Call every [DeviceCode.interval] seconds until not pending.
  Future<PollOutcome> pollDeviceToken(DeviceCode d, TraktCreds c) async {
    final r = await _send(
      'POST',
      '/oauth/device/token',
      c,
      body: {
        'code': d.deviceCode,
        'client_id': c.clientId,
        'client_secret': ?c.clientSecret,
      },
    );
    switch (r.statusCode) {
      case 200:
        return PollOutcome(
          PollStatus.success,
          TraktTokens.fromApi(_decode(r) as Map<String, dynamic>),
        );
      case 400:
        return const PollOutcome(PollStatus.pending);
      case 429:
        return const PollOutcome(PollStatus.slowDown);
      case 410:
      case 409:
        return const PollOutcome(PollStatus.expired);
      case 418:
        return const PollOutcome(PollStatus.denied);
      case 404:
      case 401:
        return const PollOutcome(PollStatus.invalid);
      default:
        throw TraktException(
          'Trakt: login check failed (HTTP ${r.statusCode})',
          statusCode: r.statusCode,
        );
    }
  }

  // ---- OAuth authorization code + PKCE (apps without a client secret) -----

  /// The page the user opens in their browser to approve the app.
  Uri authorizeUrl(
    TraktCreds c,
    String redirectUri,
    String state,
    String codeChallenge,
  ) => Uri.https('auth.trakt.tv', '/oauth/authorize', {
    'response_type': 'code',
    'client_id': c.clientId,
    'redirect_uri': redirectUri,
    'state': state,
    'code_challenge': codeChallenge,
    'code_challenge_method': 'S256',
  });

  /// Trade the code from the redirect for tokens. No client secret is sent:
  /// the verifier proves it is the same app that started the sign-in.
  Future<TraktTokens> exchangeCode(
    TraktCreds c,
    String code,
    String codeVerifier,
    String redirectUri,
  ) async {
    final r = await _send(
      'POST',
      '/oauth/token',
      c,
      body: {
        'code': code,
        'client_id': c.clientId,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
        'code_verifier': codeVerifier,
      },
    );
    _check(r, 'finishing the login');
    return TraktTokens.fromApi(_decode(r) as Map<String, dynamic>);
  }

  Future<TraktTokens> refresh(TraktTokens t, TraktCreds c) async {
    final r = await _send(
      'POST',
      '/oauth/token',
      c,
      body: {
        'refresh_token': t.refreshToken,
        'client_id': c.clientId,
        'client_secret': ?c.clientSecret,
        'redirect_uri': 'urn:ietf:wg:oauth:2.0:oob',
        'grant_type': 'refresh_token',
      },
    );
    _check(r, 'refreshing the login');
    return TraktTokens.fromApi(_decode(r) as Map<String, dynamic>);
  }

  Future<void> revoke(TraktTokens t, TraktCreds c) async {
    try {
      await _send(
        'POST',
        '/oauth/revoke',
        c,
        body: {
          'token': t.accessToken,
          'client_id': c.clientId,
          'client_secret': ?c.clientSecret,
        },
      );
    } catch (_) {}
  }

  Future<String?> username(TraktCreds c, String token) async {
    final r = await _send('GET', '/users/settings', c, token: token);
    _check(r, 'reading the account');
    final j = _decode(r) as Map<String, dynamic>;
    return (j['user'] as Map?)?['username'] as String?;
  }

  // ---- scrobbling ------------------------------------------------------------

  /// [action] is `start`, `pause` or `stop`. [progress] is 0-100.
  Future<void> scrobble(
    String action,
    TraktMedia media,
    double progress,
    TraktCreds c,
    String token,
  ) async {
    final r = await _send(
      'POST',
      '/scrobble/$action',
      c,
      token: token,
      body: media.toScrobbleJson(progress.clamp(0, 100).toDouble()),
    );
    // 409 = "already scrobbled recently": harmless.
    if (r.statusCode == 409) return;
    _check(r, 'scrobble $action');
  }

  // ---- reading the account ---------------------------------------------------

  static String? _imdb(Object? node) =>
      ((node as Map?)?['ids'] as Map?)?['imdb'] as String?;

  Future<Set<String>> watchedMovies(TraktCreds c, String token) async {
    final r = await _send('GET', '/sync/watched/movies', c, token: token);
    _check(r, 'reading watched movies');
    final out = <String>{};
    for (final e in (_decode(r) as List? ?? const [])) {
      final id = _imdb((e as Map)['movie']);
      if (id != null) out.add(id);
    }
    return out;
  }

  Future<List<WatchedShow>> watchedShows(TraktCreds c, String token) async {
    final r = await _send('GET', '/sync/watched/shows', c, token: token);
    _check(r, 'reading watched shows');
    final out = <WatchedShow>[];
    for (final e in (_decode(r) as List? ?? const [])) {
      final id = _imdb((e as Map)['show']);
      if (id == null) continue;
      final eps = <(int, int)>[];
      for (final s in (e['seasons'] as List? ?? const [])) {
        final sn = ((s as Map)['number'] as num?)?.toInt();
        if (sn == null) continue;
        for (final ep in (s['episodes'] as List? ?? const [])) {
          final en = ((ep as Map)['number'] as num?)?.toInt();
          if (en != null) eps.add((sn, en));
        }
      }
      out.add(WatchedShow(id, eps));
    }
    return out;
  }

  /// Things partly watched on other devices.
  Future<List<PlaybackEntry>> playback(TraktCreds c, String token) async {
    final r = await _send('GET', '/sync/playback', c, token: token);
    _check(r, 'reading playback progress');
    final out = <PlaybackEntry>[];
    for (final e in (_decode(r) as List? ?? const [])) {
      final m = e as Map;
      final progress = (m['progress'] as num?)?.toDouble() ?? 0;
      if (m['type'] == 'movie') {
        final id = _imdb(m['movie']);
        if (id == null) continue;
        out.add(
          PlaybackEntry(
            media: TraktMedia.movie(id),
            progress: progress,
            title: '${(m['movie'] as Map)['title'] ?? ''}',
          ),
        );
      } else if (m['type'] == 'episode') {
        final show = _imdb(m['show']);
        final ep = m['episode'] as Map?;
        if (show == null || ep == null) continue;
        out.add(
          PlaybackEntry(
            media: TraktMedia.episode(
              show,
              (ep['season'] as num).toInt(),
              (ep['number'] as num).toInt(),
            ),
            progress: progress,
            title: '${(m['show'] as Map)['title'] ?? ''}',
            episodeTitle: ep['title'] as String?,
          ),
        );
      }
    }
    return out;
  }

  Future<List<WatchlistEntry>> watchlist(TraktCreds c, String token) async {
    final r = await _send('GET', '/sync/watchlist', c, token: token);
    _check(r, 'reading your watchlist');
    final out = <WatchlistEntry>[];
    for (final e in (_decode(r) as List? ?? const [])) {
      final m = e as Map;
      final isShow = m['type'] == 'show';
      final node = isShow ? m['show'] : m['movie'];
      final id = _imdb(node);
      if (id != null && (isShow || m['type'] == 'movie')) {
        out.add(WatchlistEntry(id, isShow, '${(node as Map)['title'] ?? ''}'));
      }
    }
    return out;
  }

  // ---- writing to the account ----------------------------------------------

  Future<void> addToHistory(
    TraktCreds c,
    String token, {
    Iterable<String> movies = const [],
    Iterable<WatchedShow> shows = const [],
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final body = {
      if (movies.isNotEmpty)
        'movies': [
          for (final id in movies)
            {
              'watched_at': now,
              'ids': {'imdb': id},
            },
        ],
      if (shows.isNotEmpty)
        'shows': [
          for (final s in shows)
            {
              'ids': {'imdb': s.imdb},
              'seasons': _seasons(s.episodes, now),
            },
        ],
    };
    if (body.isEmpty) return;
    final r = await _send('POST', '/sync/history', c, token: token, body: body);
    _check(r, 'saving watch history');
  }

  static List<Map<String, dynamic>> _seasons(
    List<(int, int)> episodes,
    String now,
  ) {
    final bySeason = <int, List<int>>{};
    for (final (s, e) in episodes) {
      bySeason.putIfAbsent(s, () => []).add(e);
    }
    return [
      for (final entry in bySeason.entries)
        {
          'number': entry.key,
          'episodes': [
            for (final e in entry.value) {'number': e, 'watched_at': now},
          ],
        },
    ];
  }

  /// Add or remove titles on the Trakt watchlist.
  Future<void> setWatchlist(
    TraktCreds c,
    String token, {
    Iterable<String> movies = const [],
    Iterable<String> shows = const [],
    required bool add,
  }) async {
    Map<String, dynamic> ids(String id) => {
      'ids': {'imdb': id},
    };
    final body = {
      if (movies.isNotEmpty) 'movies': [for (final m in movies) ids(m)],
      if (shows.isNotEmpty) 'shows': [for (final s in shows) ids(s)],
    };
    if (body.isEmpty) return;
    final r = await _send(
      'POST',
      add ? '/sync/watchlist' : '/sync/watchlist/remove',
      c,
      token: token,
      body: body,
    );
    _check(r, add ? 'adding to watchlist' : 'removing from watchlist');
  }
}
