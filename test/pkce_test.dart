import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:velora/providers/library_provider.dart';
import 'package:velora/providers/settings_provider.dart';
import 'package:velora/providers/trakt_provider.dart';
import 'package:velora/services/pkce_login.dart';
import 'package:velora/services/token_store.dart';
import 'package:velora/services/trakt_service.dart';

http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Future<void> hit(Uri uri) async {
  final c = HttpClient();
  try {
    final r = await (await c.getUrl(uri)).close();
    await r.drain<void>();
  } finally {
    c.close(force: true);
  }
}

void main() {
  group('PKCE', () {
    test('challenge matches the RFC 7636 test vector', () {
      expect(
        PkceChallenge.challengeFor(
          'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
        ),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('generated verifier is valid and fresh each time', () {
      final a = PkceChallenge.generate();
      final b = PkceChallenge.generate();
      expect(a.verifier.length, inInclusiveRange(43, 128));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(a.verifier), isTrue);
      expect(a.verifier, isNot(b.verifier));
      expect(a.challenge, PkceChallenge.challengeFor(a.verifier));
      expect(a.challenge.contains('='), isFalse);
    });

    test('authorize URL carries the S256 challenge and no secret', () {
      final url = TraktService().authorizeUrl(
        const TraktCreds('cid'),
        'http://localhost:8765/callback',
        'st',
        'chal',
      );
      expect(url.host, 'auth.trakt.tv');
      expect(url.path, '/oauth/authorize');
      expect(url.queryParameters['code_challenge'], 'chal');
      expect(url.queryParameters['code_challenge_method'], 'S256');
      expect(
        url.queryParameters['redirect_uri'],
        'http://localhost:8765/callback',
      );
      expect(url.queryParameters.containsKey('client_secret'), isFalse);
    });
  });

  group('LoopbackReceiver', () {
    test('catches the code and state, ignores other paths', () async {
      final r = await LoopbackReceiver.bind(0);
      await hit(Uri.parse('http://127.0.0.1:${r.port}/favicon.ico'));
      await hit(
        Uri.parse('http://127.0.0.1:${r.port}/callback?code=abc&state=xyz'),
      );
      final res = await r.result;
      expect(res.code, 'abc');
      expect(res.state, 'xyz');
      expect(res.error, isNull);
      await r.close();
    });

    test('reports denial and cancellation', () async {
      final r = await LoopbackReceiver.bind(0);
      await hit(
        Uri.parse('http://127.0.0.1:${r.port}/callback?error=access_denied'),
      );
      expect((await r.result).error, 'access_denied');
      await r.close();

      final r2 = await LoopbackReceiver.bind(0);
      await r2.close();
      expect((await r2.result).error, 'cancelled');
    });

    test('a busy port raises SocketException', () async {
      final a = await LoopbackReceiver.bind(0);
      await expectLater(
        LoopbackReceiver.bind(a.port),
        throwsA(isA<SocketException>()),
      );
      await a.close();
    });
  });

  group('Browser sign-in (no client secret)', () {
    late Directory dir;
    late LibraryProvider library;
    late SettingsProvider settings;
    late MemoryTokenStore store;
    final tokenBodies = <Map>[];

    MockClient trakt() => MockClient((req) async {
      expect(req.headers['trakt-api-key'], 'cid');
      if (req.url.path == '/oauth/token') {
        tokenBodies.add(jsonDecode(req.body) as Map);
        return json({
          'access_token': 'acc',
          'refresh_token': 'ref',
          'expires_in': 7776000,
          'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        });
      }
      if (req.url.path == '/users/settings') {
        return json({
          'user': {'username': 'pat'},
        });
      }
      return json([]); // every sync endpoint: empty
    });

    TraktProvider make(Future<void> Function(Uri) opener) => TraktProvider(
      service: TraktService(client: trakt()),
      store: store,
      library: library,
      settings: settings,
      openUrl: opener,
      loopbackPort: 0,
    );

    setUp(() async {
      tokenBodies.clear();
      store = MemoryTokenStore();
      dir = await Directory.systemTemp.createTemp('velora_pkce_test');
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
      'Client ID alone is enough; full sign-in works without a secret',
      () async {
        late Uri authUrl;
        final p = make((url) async {
          authUrl = url;
          // Play the browser: approve, then follow the redirect back to us.
          final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
          await hit(
            redirect.replace(
              queryParameters: {
                'code': 'the-code',
                'state': url.queryParameters['state']!,
              },
            ),
          );
        });

        await p.saveCredentials('cid'); // no secret
        expect(p.state, TraktState.disconnected);
        expect(p.usesBrowserLogin, isTrue);
        expect(await store.read('trakt.clientSecret'), isNull);

        await p.startLogin();

        expect(p.state, TraktState.connected);
        expect(p.username, 'pat');
        expect(authUrl.queryParameters['code_challenge_method'], 'S256');

        // The token request: code + verifier, and NO client secret.
        final body = tokenBodies.first;
        expect(body['grant_type'], 'authorization_code');
        expect(body['code'], 'the-code');
        expect(body.containsKey('client_secret'), isFalse);
        expect(
          PkceChallenge.challengeFor(body['code_verifier'] as String),
          authUrl.queryParameters['code_challenge'],
        );
        expect(await store.read('trakt.tokens'), contains('acc'));
      },
    );

    test('a response with the wrong state is rejected', () async {
      final p = make((url) async {
        final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
        await hit(
          redirect.replace(queryParameters: {'code': 'x', 'state': 'forged'}),
        );
      });
      await p.saveCredentials('cid');
      await p.startLogin();
      expect(p.state, TraktState.disconnected);
      expect(p.message, contains('did not match'));
      expect(tokenBodies, isEmpty); // never traded the code
    });

    test('denying on trakt.tv shows a clear message', () async {
      final p = make((url) async {
        final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
        await hit(
          redirect.replace(queryParameters: {'error': 'access_denied'}),
        );
      });
      await p.saveCredentials('cid');
      await p.startLogin();
      expect(p.state, TraktState.disconnected);
      expect(p.message, contains('denied'));
    });

    test('cancelling while waiting returns to disconnected', () async {
      final p = make((url) async {});
      await p.saveCredentials('cid');
      final login = p.startLogin();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(p.state, TraktState.awaitingApproval);
      expect(p.authUrl, isNotNull);
      p.cancelLogin();
      await login;
      expect(p.state, TraktState.disconnected);
      expect(p.authUrl, isNull);
    });

    test('a saved Client ID alone survives a restart', () async {
      await make((_) async {}).saveCredentials('cid');
      final again = make((_) async {});
      await again.init();
      expect(again.state, TraktState.disconnected);
      expect(again.clientId, 'cid');
    });
  });
}
