import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PKCE (RFC 7636): a one-time secret per sign-in, so a stolen authorization
/// code is useless on its own. Trakt only supports the S256 method.
class PkceChallenge {
  PkceChallenge._(this.verifier, this.challenge);

  /// Kept in memory for this sign-in only.
  final String verifier;

  /// base64url(SHA-256(verifier)), no padding. Sent in the authorize URL.
  final String challenge;

  static const _charset =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  static String randomString(int length, {Random? rng}) {
    final r = rng ?? Random.secure();
    return String.fromCharCodes(
      List.generate(
        length,
        (_) => _charset.codeUnitAt(r.nextInt(_charset.length)),
      ),
    );
  }

  static String challengeFor(String verifier) => base64Url
      .encode(sha256.convert(utf8.encode(verifier)).bytes)
      .replaceAll('=', '');

  factory PkceChallenge.generate({Random? rng}) {
    final v = randomString(64, rng: rng); // 43-128 chars allowed
    return PkceChallenge._(v, challengeFor(v));
  }
}

/// What the browser sent back to our redirect URI.
class LoopbackResult {
  const LoopbackResult({this.code, this.state, this.error});

  final String? code;
  final String? state;

  /// `access_denied`, `cancelled`, ...
  final String? error;
}

/// A one-shot web server on this machine that catches the redirect after the
/// user approves the app in their browser. Bound to loopback only, handles a
/// single `/callback` request, then stops.
class LoopbackReceiver {
  LoopbackReceiver._(this._servers) {
    for (final s in _servers) {
      s.listen(_handle);
    }
  }

  /// IPv4 loopback, plus IPv6 loopback when available: `localhost` can
  /// resolve to either, depending on the browser.
  final List<HttpServer> _servers;
  final _done = Completer<LoopbackResult>();

  /// Port actually in use (differs from the request when 0 was asked for).
  int get port => _servers.first.port;

  /// Completes with the callback's parameters, or `cancelled` after [close].
  Future<LoopbackResult> get result => _done.future;

  /// Throws [SocketException] if the port is taken.
  static Future<LoopbackReceiver> bind(int port) async {
    final v4 = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final servers = [v4];
    try {
      servers.add(await HttpServer.bind(InternetAddress.loopbackIPv6, v4.port));
    } on SocketException {
      // No IPv6 (or that port is taken on v6 only): IPv4 alone is fine.
    }
    return LoopbackReceiver._(servers);
  }

  void _handle(HttpRequest req) {
    if (req.uri.path != '/callback') {
      req.response
        ..statusCode = HttpStatus.notFound
        ..close();
      return;
    }
    final q = req.uri.queryParameters;
    final ok = q['code'] != null && q['error'] == null;
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(_page(ok))
      ..close();
    if (!_done.isCompleted) {
      _done.complete(
        LoopbackResult(
          code: q['code'],
          state: q['state'],
          error: q['error'] ?? (q['code'] == null ? 'no_code' : null),
        ),
      );
    }
  }

  Future<void> close() async {
    if (!_done.isCompleted) {
      _done.complete(const LoopbackResult(error: 'cancelled'));
    }
    for (final s in _servers) {
      await s.close(force: true);
    }
  }

  static String _page(bool ok) =>
      '''<!doctype html>
<html><head><meta charset="utf-8"><title>Velora</title>
<style>
body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;
background:#060912;color:#fff;font-family:Segoe UI,system-ui,sans-serif}
.card{text-align:center;padding:40px 56px;border-radius:24px;
background:rgba(255,255,255,.07);border:1px solid rgba(255,255,255,.14)}
h1{margin:0 0 8px;font-size:28px;letter-spacing:2px}
p{margin:0;color:#aab}
</style></head><body><div class="card">
<h1>VELORA</h1>
<p>${ok ? 'Trakt is connected. You can close this tab.' : 'Sign-in was not completed. You can close this tab and try again in Velora.'}</p>
</div></body></html>''';
}
