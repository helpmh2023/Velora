import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class EngineException implements Exception {
  EngineException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A local network adapter (used to pick the VPN to bind to).
class NetAdapter {
  const NetAdapter(this.name, this.address, this.vpnLikely);
  final String name;
  final String address;

  /// Name looks like a VPN/tunnel adapter.
  final bool vpnLikely;
}

enum EngineState { stopped, starting, ready, failed }

class EngineStatus {
  const EngineStatus({
    required this.name,
    required this.peers,
    required this.seeders,
    required this.hasMetadata,
    this.length,
    this.completed,
  });

  final String name;
  final int peers;
  final int seeders;
  final bool hasMetadata;
  final int? length;
  final int? completed;

  double? get progress => (length == null || length == 0 || completed == null)
      ? null
      : completed! / length!;

  factory EngineStatus.fromJson(Map<String, dynamic> j) => EngineStatus(
    name: '${j['name'] ?? ''}',
    peers: (j['peers'] as num?)?.toInt() ?? 0,
    seeders: (j['seeders'] as num?)?.toInt() ?? 0,
    hasMetadata: j['hasMetadata'] == true,
    length: (j['length'] as num?)?.toInt(),
    completed: (j['completed'] as num?)?.toInt(),
  );
}

/// Starts and talks to `velora_engine` (the Go torrent-streaming helper).
///
/// The player never touches torrents: it asks [streamUrl] for a plain
/// `http://127.0.0.1:<port>/stream/...` link and plays that.
///
/// A remote engine (e.g. an always-on box reached over Tailscale) can be used
/// instead by passing [remoteBaseUrl]; the URL shape is identical.
class EngineService extends ChangeNotifier {
  EngineService({
    this.cacheDir,
    this.maxCacheGb = 4,
    this.uploadKbps = 1,
    this.noUpload = false,
    this.bindIp,
    this.remoteBaseUrl,
    this.binaryPath,
  });

  /// Where torrent data is cached. Defaults to `<temp>/velora-cache`.
  final String? cacheDir;
  double maxCacheGb;
  int uploadKbps;
  bool noUpload;

  /// Local address (a VPN adapter) all torrent traffic is bound to. If that
  /// address disappears the engine refuses to run instead of leaking.
  String? bindIp;
  String? remoteBaseUrl;

  /// Override for the engine binary (tests, custom installs).
  final String? binaryPath;

  static const _binaryName = 'velora_engine.exe';

  EngineState _state = EngineState.stopped;
  EngineState get state => _state;

  String? _error;
  String? get error => _error;

  Process? _process;
  String? _baseUrl;
  Future<void>? _starting;

  /// `http://host:port` of the running engine, or null if not ready.
  String? get baseUrl => _baseUrl;

  void _set(EngineState s, [String? err]) {
    _state = s;
    _error = err;
    notifyListeners();
  }

  /// Idempotent. Completes when the engine is ready; throws if it cannot be.
  Future<void> start() => _starting ??= _start().whenComplete(() {
    if (_state != EngineState.ready) _starting = null; // allow retry
  });

  Future<void> _start() async {
    _set(EngineState.starting);
    try {
      if (remoteBaseUrl != null) {
        _baseUrl = remoteBaseUrl!.replaceAll(RegExp(r'/+$'), '');
        await _health();
        _set(EngineState.ready);
        return;
      }

      final exe = binaryPath ?? _findBinary();
      if (exe == null) {
        throw StateError('$_binaryName not found next to the app.');
      }

      final dir = cacheDir ?? p.join(Directory.systemTemp.path, 'velora-cache');
      final process = await Process.start(exe, [
        '--data-dir',
        dir,
        '--max-cache-gb',
        '$maxCacheGb',
        '--upload-kbps',
        '$uploadKbps',
        if (noUpload) '--no-upload',
        if (bindIp != null) ...['--bind-ip', bindIp!],
      ]);
      _process = process;

      final ready = Completer<int>();
      String? engineError; // a reason the engine printed before exiting
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            final m = RegExp(
              r'VELORA_ENGINE_READY port=(\d+)',
            ).firstMatch(line);
            if (m != null && !ready.isCompleted) {
              ready.complete(int.parse(m.group(1)!));
            }
            const tag = 'VELORA_ENGINE_ERROR ';
            if (line.startsWith(tag)) engineError = line.substring(tag.length);
          });
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((l) => debugPrint('[engine] $l'));
      unawaited(
        process.exitCode.then((code) async {
          // Let any final stdout line (the reason) arrive first.
          await Future<void>.delayed(const Duration(milliseconds: 150));
          if (!ready.isCompleted) {
            ready.completeError(
              EngineException(
                engineError ?? 'Engine exited early (code $code).',
              ),
            );
          }
          if (_state == EngineState.ready) {
            _baseUrl = null;
            _starting = null;
            _set(
              EngineState.failed,
              'Engine stopped unexpectedly (code $code).',
            );
          }
        }),
      );

      final port = await ready.future.timeout(const Duration(seconds: 15));
      _baseUrl = 'http://127.0.0.1:$port';
      await _health();
      _set(EngineState.ready);
    } catch (e) {
      _process?.kill();
      _process = null;
      _baseUrl = null;
      _set(EngineState.failed, e is EngineException ? e.message : '$e');
      rethrow;
    }
  }

  Future<void> _health() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(Uri.parse('$_baseUrl/health'));
      final res = await req.close().timeout(const Duration(seconds: 5));
      await res.drain<void>();
      if (res.statusCode != 200) {
        throw StateError('Engine health check returned ${res.statusCode}.');
      }
    } finally {
      client.close(force: true);
    }
  }

  /// Playable URL for one file of a torrent. [fileIdx] null = largest video.
  /// [trackers] are tracker URLs (Torrentio's `tracker:` sources).
  String streamUrl({
    required String infoHash,
    int? fileIdx,
    List<String> trackers = const [],
    String? name,
  }) {
    final base = _baseUrl;
    if (base == null) throw StateError('Engine is not ready.');
    final uri = Uri.parse(base).replace(
      path: '/stream/${infoHash.toLowerCase()}/${fileIdx ?? 'auto'}',
      queryParameters: {if (trackers.isNotEmpty) 'tr': trackers, 'dn': ?name},
    );
    return uri.toString();
  }

  /// Peer / progress info for the "buffering..." UI. Null if unknown.
  Future<EngineStatus?> status(String infoHash) async {
    final base = _baseUrl;
    if (base == null) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.getUrl(
        Uri.parse('$base/status/${infoHash.toLowerCase()}'),
      );
      final res = await req.close().timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final body = await res.transform(utf8.decoder).join();
      return EngineStatus.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Bundled next to the app exe; in development, the freshly built copy
  /// under native/velora_engine/.
  String? _findBinary() {
    final bundled = p.join(p.dirname(Platform.resolvedExecutable), _binaryName);
    if (File(bundled).existsSync()) return bundled;

    var dir = Directory.current;
    for (var i = 0; i < 6; i++) {
      final dev = p.join(dir.path, 'native', 'velora_engine', _binaryName);
      if (File(dev).existsSync()) return dev;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  /// Whether the running engine was started with these exact settings.
  bool matches({
    required double maxCacheGb,
    required int uploadKbps,
    required bool noUpload,
    required String? bindIp,
    required String? remoteBaseUrl,
  }) =>
      this.maxCacheGb == maxCacheGb &&
      this.uploadKbps == uploadKbps &&
      this.noUpload == noUpload &&
      this.bindIp == bindIp &&
      this.remoteBaseUrl == remoteBaseUrl;

  /// Stop, adopt new settings, start again. Also wipes the local cache,
  /// because the engine clears it on every launch.
  Future<void> restartWith({
    required double maxCacheGb,
    required int uploadKbps,
    required bool noUpload,
    required String? bindIp,
    required String? remoteBaseUrl,
  }) async {
    await stop();
    this.maxCacheGb = maxCacheGb;
    this.uploadKbps = uploadKbps;
    this.noUpload = noUpload;
    this.bindIp = bindIp;
    this.remoteBaseUrl = remoteBaseUrl;
    await start();
  }

  /// The public IP the engine's traffic leaves from (what peers see), or
  /// null if it could not be determined.
  Future<String?> publicIp() async {
    final base = _baseUrl;
    if (base == null) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(Uri.parse('$base/myip'));
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return null;
      return (jsonDecode(body) as Map<String, dynamic>)['ip'] as String?;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// IPv4 adapters on this machine, VPN-looking ones first.
  static Future<List<NetAdapter>> adapters() async {
    final vpn = RegExp(
      r'wireguard|\bwg\d|tun|tap|vpn|proton|nord|mullvad|openvpn|wintun|ppp|tailscale|zerotier|surfshark|express|cyberghost|pia',
      caseSensitive: false,
    );
    final out = <NetAdapter>[];
    try {
      final list = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final i in list) {
        for (final a in i.addresses) {
          out.add(NetAdapter(i.name, a.address, vpn.hasMatch(i.name)));
        }
      }
    } catch (_) {}
    out.sort((a, b) {
      if (a.vpnLikely != b.vpnLikely) return a.vpnLikely ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return out;
  }

  /// Bytes currently used by the local cache (0 for a remote engine).
  Future<int> cacheBytes() async {
    if (remoteBaseUrl != null) return 0;
    final dir = Directory(
      cacheDir ?? p.join(Directory.systemTemp.path, 'velora-cache'),
    );
    if (!await dir.exists()) return 0;
    var total = 0;
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) total += await e.length();
      }
    } catch (_) {}
    return total;
  }

  /// Null if a Velora engine answers at [url], otherwise an error message.
  static Future<String?> checkRemote(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !(uri.isScheme('http') || uri.isScheme('https'))) {
      return 'Enter a full address like http://100.64.0.5:11470';
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(uri.replace(path: '/health'));
      final res = await req.close().timeout(const Duration(seconds: 6));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 200 && body.contains('"ok"')) return null;
      return 'Reached the server, but it is not a Velora engine.';
    } catch (e) {
      return 'Could not connect ($e)';
    } finally {
      client.close(force: true);
    }
  }

  Future<void> stop() async {
    _process?.kill();
    _process = null;
    _baseUrl = null;
    _starting = null;
    if (_state != EngineState.stopped) _set(EngineState.stopped);
  }

  @override
  void dispose() {
    _process?.kill();
    _process = null;
    super.dispose();
  }
}
