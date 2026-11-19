import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:velora/models/meta_item.dart';
import 'package:velora/models/watch_progress.dart';
import 'package:velora/providers/library_provider.dart';
import 'package:velora/providers/settings_provider.dart';
import 'package:velora/providers/trakt_provider.dart';
import 'package:velora/services/cinemeta_service.dart';
import 'package:velora/services/token_store.dart';
import 'package:velora/services/trakt_service.dart';

http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> tokenJson({int? expiresIn}) => {
  'access_token': 'access-1',
  'refresh_token': 'refresh-1',
  'expires_in': expiresIn ?? 7776000,
  'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
};

void main() {
  const creds = TraktCreds('cid', 'secret');

  group('TraktService', () {
    test('device code + poll statuses', () async {
      var polls = 0;
      final api = TraktService(
        client: MockClient((req) async {
          expect(req.headers['trakt-api-key'], 'cid');
          expect(req.headers['trakt-api-version'], '2');
          if (req.url.path == '/oauth/device/code') {
            return json({
              'device_code': 'dc',
              'user_code': 'ABCD1234',
              'verification_url': 'https://trakt.tv/activate',
              'expires_in': 600,
              'interval': 5,
            });
          }
          expect(req.url.path, '/oauth/device/token');
          final body = jsonDecode(req.body) as Map;
          expect(body['code'], 'dc');
          expect(body['client_secret'], 'secret');
          polls++;
          return switch (polls) {
            1 => http.Response('', 400),
            2 => http.Response('', 429),
            3 => http.Response('', 418),
            4 => http.Response('', 410),
            5 => http.Response('', 404),
            _ => json(tokenJson()),
          };
        }),
      );

      final code = await api.requestDeviceCode(creds);
      expect(code.userCode, 'ABCD1234');
      expect(code.interval, 5);

      Future<PollStatus> poll() async =>
          (await api.pollDeviceToken(code, creds)).status;
      expect(await poll(), PollStatus.pending);
      expect(await poll(), PollStatus.slowDown);
      expect(await poll(), PollStatus.denied);
      expect(await poll(), PollStatus.expired);
      expect(await poll(), PollStatus.invalid);
      final ok = await api.pollDeviceToken(code, creds);
      expect(ok.status, PollStatus.success);
      expect(ok.tokens!.accessToken, 'access-1');
      expect(ok.tokens!.expiringSoon, isFalse);
    });

    test('scrobble bodies for a movie and an episode', () async {
      final seen = <String, Map>{};
      final api = TraktService(
        client: MockClient((req) async {
          seen[req.url.path] = jsonDecode(req.body) as Map;
          expect(req.headers['Authorization'], 'Bearer tok');
          return json({});
        }),
      );
      await api.scrobble(
        'start',
        const TraktMedia.movie('tt1'),
        12.5,
        creds,
        'tok',
      );
      expect(seen['/scrobble/start'], {
        'movie': {
          'ids': {'imdb': 'tt1'},
        },
        'progress': 12.5,
      });
      await api.scrobble(
        'stop',
        const TraktMedia.episode('tt2', 1, 3),
        150, // clamped
        creds,
        'tok',
      );
      expect(seen['/scrobble/stop'], {
        'show': {
          'ids': {'imdb': 'tt2'},
        },
        'episode': {'season': 1, 'number': 3},
        'progress': 100.0,
      });
    });

    test(
      '409 on scrobble is ignored; 401 is surfaced as unauthorized',
      () async {
        var status = 409;
        final api = TraktService(
          client: MockClient((_) async => http.Response('', status)),
        );
        await api.scrobble(
          'start',
          const TraktMedia.movie('tt1'),
          1,
          creds,
          't',
        );
        status = 401;
        await expectLater(
          api.scrobble('start', const TraktMedia.movie('tt1'), 1, creds, 't'),
          throwsA(
            isA<TraktException>().having(
              (e) => e.unauthorized,
              'unauthorized',
              isTrue,
            ),
          ),
        );
      },
    );
  });

  group('TraktProvider', () {
    late Directory dir;
    late LibraryProvider library;
    late SettingsProvider settings;
    late MemoryTokenStore store;
    final calls = <String>[]; // "METHOD path"
    final bodies = <String, Object?>{};

    // What the fake Trakt returns, per test.
    var watchedMovies = <Map<String, dynamic>>[];
    var watchedShows = <Map<String, dynamic>>[];
    var playback = <Map<String, dynamic>>[];
    var watchlist = <Map<String, dynamic>>[];

    MockClient fakeTrakt() => MockClient((req) async {
      final key = '${req.method} ${req.url.path}';
      calls.add(key);
      if (req.body.isNotEmpty) bodies[key] = jsonDecode(req.body);
      switch (req.url.path) {
        case '/oauth/device/code':
          return json({
            'device_code': 'dc',
            'user_code': 'ZZZ999',
            'verification_url': 'https://trakt.tv/activate',
            'expires_in': 60,
            'interval': 1,
          });
        case '/oauth/device/token':
          return json(tokenJson());
        case '/oauth/token':
          return json(tokenJson());
        case '/oauth/revoke':
          return json({});
        case '/users/settings':
          return json({
            'user': {'username': 'tester'},
          });
        case '/sync/watched/movies':
          return json(watchedMovies);
        case '/sync/watched/shows':
          return json(watchedShows);
        case '/sync/playback':
          return json(playback);
        case '/sync/watchlist':
          return req.method == 'GET' ? json(watchlist) : json({});
        default:
          return json({});
      }
    });

    CinemetaService fakeCinemeta() => CinemetaService(
      client: MockClient((req) async {
        final m = RegExp(
          r'/meta/(movie|series)/(tt\d+)\.json',
        ).firstMatch(req.url.path)!;
        return json({
          'meta': {
            'id': m.group(2),
            'type': m.group(1),
            'name': 'Name ${m.group(2)}',
            'runtime': '100 min',
          },
        });
      }),
    );

    MetaItem movie(String id) => MetaItem(id: id, type: 'movie', name: id);

    Future<TraktProvider> make({
      bool connected = true,
      TraktTokens? tokens,
      MockClient? client,
    }) async {
      store = MemoryTokenStore();
      await store.write('trakt.clientId', 'cid');
      await store.write('trakt.clientSecret', 'secret');
      if (connected) {
        final t =
            tokens ??
            TraktTokens(
              accessToken: 'access-old',
              refreshToken: 'refresh-old',
              expiresAt: DateTime.now().add(const Duration(days: 60)),
            );
        await store.write('trakt.tokens', jsonEncode(t.toJson()));
      }
      final p = TraktProvider(
        service: TraktService(client: client ?? fakeTrakt()),
        store: store,
        library: library,
        settings: settings,
        cinemeta: fakeCinemeta(),
      );
      return p;
    }

    setUp(() async {
      calls.clear();
      bodies.clear();
      watchedMovies = [];
      watchedShows = [];
      playback = [];
      watchlist = [];
      dir = await Directory.systemTemp.createTemp('velora_trakt_test');
      Hive.init(dir.path);
      library = LibraryProvider(
        await Hive.openBox<String>('fav'),
        await Hive.openBox<String>('prog'),
        await Hive.openBox<String>('watched'),
      );
      settings = SettingsProvider(await Hive.openBox<dynamic>('settings'));
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test(
      'device login: shows code, polls, stores tokens, loads username',
      () async {
        final p = await make(connected: false);
        await p.init();
        expect(p.state, TraktState.disconnected);

        await p.startLogin(); // interval 1s -> one poll -> success
        expect(p.state, TraktState.connected);
        expect(p.username, 'tester');
        expect(await store.read('trakt.tokens'), contains('access-1'));
        expect(
          calls,
          containsAll(['POST /oauth/device/code', 'POST /oauth/device/token']),
        );

        await p.logout();
        expect(p.state, TraktState.disconnected);
        expect(await store.read('trakt.tokens'), isNull);
        expect(calls, contains('POST /oauth/revoke'));
      },
    );

    test('expiring token is refreshed before use', () async {
      final p = await make(
        tokens: TraktTokens(
          accessToken: 'access-old',
          refreshToken: 'refresh-old',
          expiresAt: DateTime.now().add(const Duration(days: 2)),
        ),
      );
      await p.init();
      await p.sync(quiet: true);
      expect(calls.first, 'POST /oauth/token'); // refreshed first
      expect(await store.read('trakt.tokens'), contains('access-1'));
    });

    test(
      'history: remote watched is imported, local finished is pushed',
      () async {
        watchedMovies = [
          {
            'movie': {
              'ids': {'imdb': 'tt1'},
            },
          },
        ];
        watchedShows = [
          {
            'show': {
              'ids': {'imdb': 'tt2'},
            },
            'seasons': [
              {
                'number': 1,
                'episodes': [
                  {'number': 2},
                  {'number': 3},
                ],
              },
            ],
          },
        ];
        // Finished locally, unknown to Trakt: a movie and an episode.
        await library.saveProgress(
          WatchProgress(
            videoId: 'tt3',
            meta: movie('tt3'),
            positionMs: 5950000,
            durationMs: 6000000,
            updatedAt: DateTime.now(),
          ),
        );
        await library.saveProgress(
          WatchProgress(
            videoId: 'tt4:2:5',
            meta: MetaItem(id: 'tt4', type: 'series', name: 'Show'),
            positionMs: 2650000,
            durationMs: 2700000,
            updatedAt: DateTime.now(),
            season: 2,
            episode: 5,
          ),
        );

        final p = await make();
        await p.init();
        await p.sync(quiet: true);

        expect(library.isWatched('tt1'), isTrue);
        expect(library.isWatched('tt2:1:2'), isTrue);
        expect(library.isWatched('tt2:1:3'), isTrue);
        expect(library.isWatched('tt2:1:4'), isFalse);

        final pushed = bodies['POST /sync/history'] as Map;
        expect((pushed['movies'] as List).single['ids'], {'imdb': 'tt3'});
        final show = (pushed['shows'] as List).single as Map;
        expect(show['ids'], {'imdb': 'tt4'});
        expect(show['seasons'][0]['number'], 2);
        expect(show['seasons'][0]['episodes'][0]['number'], 5);
      },
    );

    test(
      'playback: partly watched elsewhere becomes Continue Watching',
      () async {
        playback = [
          {
            'type': 'movie',
            'progress': 40.0,
            'movie': {
              'title': 'Away',
              'ids': {'imdb': 'tt9'},
            },
          },
        ];
        final p = await make();
        await p.init();
        await p.sync(quiet: true);

        final got = library.progressFor('tt9')!;
        expect(got.meta.name, 'Name tt9');
        expect(got.durationMs, 100 * 60 * 1000); // runtime "100 min"
        expect(got.positionMs, 40 * 60 * 1000); // 40%
        expect(library.continueWatching.map((e) => e.videoId), contains('tt9'));
      },
    );

    test('watchlist: pull, push and removal both ways', () async {
      // On Trakt: tt10 (new) and tt12 (we know it, still there).
      watchlist = [
        {
          'type': 'movie',
          'movie': {
            'title': 'Ten',
            'ids': {'imdb': 'tt10'},
          },
        },
        {
          'type': 'movie',
          'movie': {
            'title': 'Twelve',
            'ids': {'imdb': 'tt12'},
          },
        },
      ];
      await library.addFavouriteSilently(movie('tt11')); // only local
      await library.addFavouriteSilently(movie('tt12'));
      await library.addFavouriteSilently(
        movie('tt13'),
      ); // was on Trakt, removed there
      settings.traktWatchlistIds = {'tt12', 'tt13'}; // snapshot of last sync

      final p = await make();
      await p.init();
      await p.sync(quiet: true);

      expect(library.isFavourite('tt10'), isTrue); // pulled
      expect(library.isFavourite('tt13'), isFalse); // removed remotely
      expect(library.isFavourite('tt11'), isTrue);
      final push = bodies['POST /sync/watchlist'] as Map;
      expect((push['movies'] as List).map((m) => m['ids']['imdb']), ['tt11']);
      expect(settings.traktWatchlistIds, {'tt10', 'tt12', 'tt11'});
    });

    test('toggling My List pushes to the Trakt watchlist', () async {
      final p = await make();
      await p.init();
      await p.sync(quiet: true);
      calls.clear();

      await library.toggleFavourite(movie('tt20'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(calls, contains('POST /sync/watchlist'));
      expect(
        (bodies['POST /sync/watchlist'] as Map)['movies'][0]['ids']['imdb'],
        'tt20',
      );

      calls.clear();
      await library.toggleFavourite(movie('tt20')); // remove
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(calls, contains('POST /sync/watchlist/remove'));
    });

    test('scrobble respects the setting and needs an IMDb id', () async {
      final p = await make();
      await p.init();
      await p.sync(quiet: true);
      calls.clear();

      p.scrobble(
        'start',
        movie('tt30'),
        position: const Duration(minutes: 10),
        duration: const Duration(minutes: 100),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(calls, contains('POST /scrobble/start'));
      expect(
        (bodies['POST /scrobble/start'] as Map)['progress'],
        closeTo(10, 0.01),
      );

      calls.clear();
      settings.traktScrobble = false;
      p.scrobble(
        'stop',
        movie('tt30'),
        position: const Duration(minutes: 10),
        duration: const Duration(minutes: 100),
      );
      p.scrobble(
        'stop',
        movie('kitsu:1'), // not an IMDb id
        position: const Duration(minutes: 10),
        duration: const Duration(minutes: 100),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(calls, isEmpty);
    });
  });
}
