import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/meta_item.dart';
import '../models/prebuffer_entry.dart';
import '../models/stream_source.dart';
import 'engine_service.dart';
import 'watch_tracker.dart';

/// One video that can be watched on another device.
class ShareItem {
  const ShareItem({
    required this.id,
    required this.label,
    required this.infoHash,
    required this.fileIdx,
    this.trackers = const [],
    this.name,
    this.meta,
    this.videoId,
    this.season,
    this.episode,
    this.episodeTitle,
    this.source,
  });

  /// With [meta] and [videoId], where the other device stops is saved to
  /// Continue Watching.
  final MetaItem? meta;
  final String? videoId;
  final int? season;
  final int? episode;
  final String? episodeTitle;
  final StreamSource? source;

  final String id;
  final String label;
  final String infoHash;
  final int fileIdx;
  final List<String> trackers;
  final String? name;
}

/// Lets another device on the same Wi-Fi (an iPad, say) watch what this PC is
/// downloading: a tiny web server that shows a page with "Open in VLC" /
/// "Open in Infuse" buttons and passes the video (and any subtitle files from
/// the torrent) through from the local engine. All the downloading stays on
/// this PC; the other device only plays. The engine itself is never exposed:
/// it stays on 127.0.0.1, and only paths under a random secret are served.
class ShareServer extends ChangeNotifier {
  ShareServer(
    this._engine,
    this._entries, {
    String? address,
    String? token,
    this.preferredPort = 0,
    this.idleAfter = const Duration(seconds: 90),
    this.reportEvery = const Duration(seconds: 60),
    this.checkEvery = const Duration(seconds: 10),
    int mainStreamMinBytes = 512 * 1024,
    Duration rewind = const Duration(seconds: 30),
  }) : _fixedAddress = address,
       _fixedToken = token,
       _mainMin = mainStreamMinBytes,
       _rewind = rewind;

  /// A port to try first, so the links stay the same between sessions (the
  /// iPad player then remembers where you were). Falls back to any free port.
  final int preferredPort;
  final Duration idleAfter;
  final Duration reportEvery;
  final Duration checkEvery;
  final int _mainMin;
  final Duration _rewind;
  final String? _fixedToken;

  /// How long the video is (the share server cannot see inside the file).
  Future<Duration?> Function(ShareItem item)? durationProbe;

  /// Called with the estimated position when the other device is watching or
  /// has stopped.
  Future<void> Function(ShareItem item, Duration position, Duration duration)?
  progressSink;

  /// For tests: use this address instead of looking for the LAN one.
  final String? _fixedAddress;

  final EngineService _engine;
  final List<PrebufferEntry> Function() _entries;

  /// Where the user stopped watching [item] elsewhere (shown on the page).
  Duration? Function(ShareItem item)? _positionFor;
  set positionLookup(Duration? Function(ShareItem item)? f) => _positionFor = f;

  HttpServer? _server;
  Timer? _timer;
  String _token = '';
  final _trackers = <String, WatchTracker>{};
  final _durations = <String, Duration>{};
  String? _ip;
  final _items = <String, ShareItem>{};

  bool get running => _server != null;
  String? get address => _ip;

  /// Link to open on the other device (the list of pre-buffered titles).
  String? get indexUrl => _server == null ? null : '$_base/';

  String get _base => 'http://$_ip:${_server!.port}/$_token';

  /// Link to the page for one video.
  String? pageUrl(ShareItem item) {
    if (_server == null) return null;
    _items[item.id] = item;
    return '$_base/w/${Uri.encodeComponent(item.id)}';
  }

  static ShareItem itemFor(PrebufferEntry e) => ShareItem(
    id: '${e.source.infoHash.toLowerCase()}-${e.fileIdx}',
    label: e.label,
    infoHash: e.source.infoHash,
    fileIdx: e.fileIdx,
    trackers: e.source.trackers,
    name: e.source.release,
    meta: e.meta,
    videoId: e.videoId,
    season: e.season,
    episode: e.episode,
    episodeTitle: e.episodeTitle,
    source: e.source,
  );

  /// Starts sharing. Returns a message if it could not.
  Future<String?> start() async {
    if (_server != null) return null;
    final ip = _fixedAddress ?? await lanAddress();
    if (ip == null) {
      return 'No local network found. Connect this PC to Wi-Fi or Ethernet.';
    }
    try {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, preferredPort);
      } catch (_) {
        if (preferredPort == 0) rethrow;
        _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      }
    } catch (e) {
      return 'Could not open a network port: $e';
    }
    _ip = ip;
    if (_fixedToken != null && _fixedToken.length >= 8) {
      _token = _fixedToken;
    } else {
      final r = Random.secure();
      _token = List.generate(
        12,
        (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[r.nextInt(36)],
      ).join();
    }
    _server!.listen(_handle, onError: (_) {});
    _timer = Timer.periodic(checkEvery, (_) => _checkProgress());
    notifyListeners();
    return null;
  }

  Future<void> stop() async {
    await _checkProgress(final_: true);
    _timer?.cancel();
    _timer = null;
    final s = _server;
    _server = null;
    _items.clear();
    _trackers.clear();
    await s?.close(force: true);
    notifyListeners();
  }

  /// This PC's address on the local network (what the iPad can reach).
  static Future<String?> lanAddress() async {
    final all = await NetworkInterface.list(type: InternetAddressType.IPv4);
    String? best;
    var bestScore = -1;
    for (final i in all) {
      final n = i.name.toLowerCase();
      for (final a in i.addresses) {
        final ip = a.address;
        if (a.isLoopback || ip.startsWith('169.254.')) continue;
        final private =
            ip.startsWith('192.168.') ||
            ip.startsWith('10.') ||
            RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);
        if (!private) continue;
        var score = 1;
        if (n.contains('wi-fi') || n.contains('wlan') || n.contains('wifi')) {
          score += 3;
        }
        if (n.contains('ethernet')) score += 2;
        if (RegExp(
          r'vpn|tun|tap|virtual|vmware|vbox|hyper-v|vethernet|wsl|tailscale|zerotier|loopback',
        ).hasMatch(n)) {
          score -= 3;
        }
        if (score > bestScore) {
          bestScore = score;
          best = ip;
        }
      }
    }
    return best;
  }

  // ---- request handling ----

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final segs = req.uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.isEmpty || segs.first != _token) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
      final kind = segs.length > 1 ? segs[1] : '';
      switch (kind) {
        case '':
          await _html(res, _indexPage());
        case 'w':
          final it = _items[Uri.decodeComponent(segs[2])] ?? _byId(segs[2]);
          if (it == null) {
            await _notFound(res);
            return;
          }
          await _html(res, await _watchPage(it));
        case 'v':
          final it = _items[Uri.decodeComponent(segs[2])] ?? _byId(segs[2]);
          if (it == null) {
            await _notFound(res);
            return;
          }
          await _proxy(req, it, it.fileIdx);
        case 'sub':
          // /sub/<id>/<fileIdx>/<name>.vtt|.srt
          final it = _items[Uri.decodeComponent(segs[2])] ?? _byId(segs[2]);
          if (it == null || segs.length < 5) {
            await _notFound(res);
            return;
          }
          await _subtitle(req, it, int.tryParse(segs[3]) ?? -1, segs[4]);
        default:
          await _notFound(res);
      }
    } catch (_) {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  ShareItem? _byId(String id) {
    final d = Uri.decodeComponent(id);
    for (final e in _entries()) {
      final it = itemFor(e);
      if (it.id == d) {
        _items[it.id] = it;
        return it;
      }
    }
    return null;
  }

  Future<void> _notFound(HttpResponse res) async {
    res.statusCode = HttpStatus.notFound;
    await res.close();
  }

  Future<void> _html(HttpResponse res, String body) async {
    res.headers.contentType = ContentType.html;
    res.headers.set('Cache-Control', 'no-store');
    res.write(body);
    await res.close();
  }

  /// Passes the engine's video stream through, including Range requests (so
  /// seeking works in the iPad player).
  Future<void> _proxy(HttpRequest req, ShareItem it, int fileIdx) async {
    final url = _engine.streamUrl(
      infoHash: it.infoHash,
      fileIdx: fileIdx,
      trackers: it.trackers,
      name: it.name,
    );
    final client = HttpClient();
    try {
      final creq = await client.openUrl(req.method, Uri.parse(url));
      final range = req.headers.value('range');
      if (range != null) creq.headers.set('Range', range);
      final cres = await creq.close();
      final res = req.response;
      res.statusCode = cres.statusCode;
      for (final h in const [
        'content-type',
        'content-length',
        'content-range',
        'accept-ranges',
      ]) {
        final v = cres.headers.value(h);
        if (v != null) res.headers.set(h, v);
      }
      res.bufferOutput = false;
      unawaited(
        res.done.then(
          (_) => client.close(force: true),
          onError: (_) => client.close(force: true),
        ),
      );
      Stream<List<int>> body = cres;
      if (req.method == 'GET' && it.meta != null && it.videoId != null) {
        body = _tracked(it, cres, range);
      }
      await res.addStream(body);
    } catch (_) {
      // The player went away mid-stream; nothing to report.
    } finally {
      client.close(force: true);
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  /// Wraps the video stream to see how far into the file the other device is.
  Stream<List<int>> _tracked(
    ShareItem it,
    HttpClientResponse cres,
    String? range,
  ) {
    final tracker = _trackers.putIfAbsent(
      it.id,
      () => WatchTracker(mainStreamMinBytes: _mainMin, rewind: _rewind),
    );
    final conn = tracker.open();
    final start =
        int.tryParse(
          RegExp(r'bytes=(\d+)-').firstMatch(range ?? '')?[1] ?? '',
        ) ??
        0;
    // Whole-file size: from Content-Range ("bytes a-b/total") or the length.
    final cr = cres.headers.value('content-range');
    final total =
        int.tryParse(RegExp(r'/(\d+)$').firstMatch(cr ?? '')?[1] ?? '') ??
        (cres.contentLength > 0 ? start + cres.contentLength : 0);
    if (total <= 0) return cres;
    // Start working out how long the video is, once.
    if (!_durations.containsKey(it.id) && durationProbe != null) {
      _durations[it.id] = Duration.zero; // marks "asked"
      unawaited(
        durationProbe!(it).then((d) {
          if (d != null && d > Duration.zero) {
            _durations[it.id] = d;
          } else {
            _durations.remove(it.id); // try again on the next request
          }
        }, onError: (_) => _durations.remove(it.id)),
      );
    }
    var sent = 0;
    return cres.map((chunk) {
      sent += chunk.length;
      tracker.bytes(conn, start, sent, total);
      return chunk;
    });
  }

  /// Every few seconds: save where the other device is (while it plays, and
  /// once it has gone quiet = stopped).
  Future<void> _checkProgress({bool final_ = false}) async {
    final sink = progressSink;
    if (sink == null) return;
    final now = DateTime.now();
    for (final entry in _trackers.entries.toList()) {
      final it = _items[entry.key];
      final d = _durations[entry.key];
      if (it == null || d == null || d <= Duration.zero) continue;
      final t = entry.value;
      if (!t.shouldReport(
        now: now,
        idle: final_ ? Duration.zero : idleAfter,
        every: reportEvery,
      )) {
        continue;
      }
      final pos = t.estimate(d);
      if (pos == null) continue;
      t.reported(now: now);
      try {
        await sink(it, pos, d);
      } catch (_) {}
    }
  }

  /// Subtitle file from the torrent; `.vtt` converts SubRip (srt) on the fly
  /// because Safari's own player only understands WebVTT.
  Future<void> _subtitle(
    HttpRequest req,
    ShareItem it,
    int fileIdx,
    String name,
  ) async {
    final url = _engine.streamUrl(
      infoHash: it.infoHash,
      fileIdx: fileIdx,
      trackers: it.trackers,
      name: it.name,
    );
    final client = HttpClient();
    try {
      final creq = await client.getUrl(Uri.parse(url));
      final cres = await creq.close().timeout(const Duration(seconds: 30));
      final bytes = await cres.fold<List<int>>([], (a, b) => a..addAll(b));
      final res = req.response;
      res.headers.set('Access-Control-Allow-Origin', '*');
      if (name.toLowerCase().endsWith('.vtt')) {
        res.headers.contentType = ContentType('text', 'vtt', charset: 'utf-8');
        res.write(srtToVtt(utf8.decode(bytes, allowMalformed: true)));
      } else {
        res.headers.contentType = ContentType(
          'text',
          'plain',
          charset: 'utf-8',
        );
        res.add(bytes);
      }
    } catch (_) {
      req.response.statusCode = HttpStatus.badGateway;
    } finally {
      client.close(force: true);
      await req.response.close();
    }
  }

  /// SubRip -> WebVTT: header line, and `,` -> `.` in the timestamps.
  static String srtToVtt(String srt) {
    final body = srt
        .replaceAll('\r\n', '\n')
        .replaceAllMapped(
          RegExp(r'(\d{2}:\d{2}:\d{2}),(\d{3})'),
          (m) => '${m[1]}.${m[2]}',
        );
    return 'WEBVTT\n\n${body.replaceFirst('﻿', '')}';
  }

  // ---- subtitle discovery ----

  static const _subExt = {'srt', 'ass', 'ssa', 'vtt', 'sub'};

  /// Subtitle files in the torrent that belong to [videoPath].
  static List<({int idx, String path})> matchSubs(
    String videoPath,
    List<({int idx, String path})> files,
  ) {
    String ext(String p) => p.contains('.')
        ? p.substring(p.lastIndexOf('.') + 1).toLowerCase()
        : '';
    String stem(String p) {
      final base = p.split('/').last;
      final dot = base.lastIndexOf('.');
      return (dot > 0 ? base.substring(0, dot) : base).toLowerCase();
    }

    final subs = files.where((f) => _subExt.contains(ext(f.path))).toList();
    if (subs.isEmpty) return const [];
    final vs = stem(videoPath);
    final videos = files
        .where(
          (f) => const {
            'mkv',
            'mp4',
            'avi',
            'mov',
            'm4v',
            'webm',
            'ts',
          }.contains(ext(f.path)),
        )
        .length;

    // 1. Named after the video (movie.mkv -> movie.en.srt, Subs/movie/2_English.srt)
    final named = subs
        .where(
          (f) =>
              f.path.toLowerCase().contains(vs) || stem(f.path).startsWith(vs),
        )
        .toList();
    if (named.isNotEmpty) return named;
    // 2. Same episode number (S01E02) in a pack.
    final tok = RegExp(r'[sS](\d{1,2})[eE](\d{1,3})').firstMatch(videoPath);
    if (tok != null) {
      final key = '${int.parse(tok[1]!)}x${int.parse(tok[2]!)}';
      final byEp = subs.where((f) {
        final m = RegExp(r'[sS](\d{1,2})[eE](\d{1,3})').firstMatch(f.path);
        return m != null && '${int.parse(m[1]!)}x${int.parse(m[2]!)}' == key;
      }).toList();
      if (byEp.isNotEmpty) return byEp;
    }
    // 3. A torrent with a single video: every subtitle is for it.
    return videos <= 1 ? subs : const [];
  }

  Future<({String video, List<({int idx, String path})> subs})> _files(
    ShareItem it,
  ) async {
    final all = await _engine.files(it.infoHash);
    final video = all.where((f) => f.idx == it.fileIdx).toList();
    final vpath = video.isEmpty ? '' : video.first.path;
    final subs = matchSubs(vpath, [
      for (final f in all) (idx: f.idx, path: f.path),
    ]);
    return (video: vpath, subs: subs);
  }

  static String _fmtTime(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0
        ? '$h:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}'
        : '${d.inMinutes}:${two(d.inSeconds.remainder(60))}';
  }

  // ---- pages ----

  static final _esc = const HtmlEscape(HtmlEscapeMode.attribute);
  static const _style = '''
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
 body{margin:0;padding:24px;font-family:-apple-system,system-ui,sans-serif;background:#05070f;color:#eef;}
 h1{font-size:22px;margin:0 0 6px} .sub{color:#9aa;margin-bottom:22px}
 a.btn{display:block;margin:10px 0;padding:16px 18px;border-radius:14px;background:#13203a;color:#fff;text-decoration:none;font-weight:600;border:1px solid #2a3b60}
 a.btn.main{background:#00c2d6;color:#04121a;border-color:#00c2d6}
 a.item{display:block;padding:16px;margin:10px 0;border-radius:14px;background:#0d1426;color:#fff;text-decoration:none;border:1px solid #1d2a48}
 .muted{color:#8a96b0;font-size:13px;line-height:1.5} video{width:100%;border-radius:12px;background:#000}
 .tag{display:inline-block;font-size:12px;padding:2px 8px;border-radius:8px;background:#12351f;color:#69f0ae;margin-left:8px}
</style>''';

  String _indexPage() {
    final entries = _entries();
    final b = StringBuffer(
      '<!doctype html><meta charset="utf-8"><title>Velora</title>$_style',
    );
    b.write(
      '<h1>Velora</h1><div class="sub">Pre-buffered on the PC. Tap one to watch.</div>',
    );
    if (entries.isEmpty) {
      b.write(
        '<p class="muted">Nothing pre-buffered yet. On the PC, tap the download icon next to an episode.</p>',
      );
    }
    for (final e in entries) {
      final it = itemFor(e);
      _items[it.id] = it;
      b.write(
        '<a class="item" href="$_base/w/${Uri.encodeComponent(it.id)}">${_esc.convert(e.label)}</a>',
      );
    }
    return b.toString();
  }

  Future<String> _watchPage(ShareItem it) async {
    final resumeAt = _positionFor?.call(it);
    final f = await _files(it);
    final name = f.video.isEmpty ? 'video' : f.video.split('/').last;
    final enc = Uri.encodeComponent(name);
    final video = '$_base/v/${Uri.encodeComponent(it.id)}/$enc';
    final subLinks = [
      for (final s in f.subs)
        '$_base/sub/${Uri.encodeComponent(it.id)}/${s.idx}/${Uri.encodeComponent(s.path.split('/').last)}',
    ];
    final firstSub = subLinks.isEmpty ? null : subLinks.first;
    final eVideo = Uri.encodeComponent(video);
    final vlc = firstSub == null
        ? 'vlc-x-callback://x-callback-url/stream?url=$eVideo'
        : 'vlc-x-callback://x-callback-url/stream?url=$eVideo&sub=${Uri.encodeComponent(firstSub)}';
    final infuse = 'infuse://x-callback-url/play?url=$eVideo';

    final b = StringBuffer(
      '<!doctype html><meta charset="utf-8"><title>${_esc.convert(it.label)}</title>$_style',
    );
    b.write('<h1>${_esc.convert(it.label)}</h1>');
    b.write('<div class="sub">Streaming from your PC over Wi-Fi</div>');
    b.write(
      '<a class="btn main" id="vlc" href="${_esc.convert(vlc)}">Open in VLC</a>',
    );
    if (resumeAt != null) {
      b.write(
        '<p class="muted">You stopped at <b>${_fmtTime(resumeAt)}</b> on the PC. '
        'In VLC, drag the bar to that time to carry on.</p>',
      );
    }
    // Scanning the code should land straight in VLC: try once on load (Safari
    // asks "Open in VLC?"); the button above is the fallback.
    b.write(
      '<script>if(!sessionStorage.getItem("o${_esc.convert(it.id)}")){'
      'sessionStorage.setItem("o${_esc.convert(it.id)}","1");'
      'setTimeout(function(){location.href=document.getElementById("vlc").href},350);}</script>',
    );
    b.write('<h3>Subtitles</h3>');
    if (f.subs.isEmpty) {
      b.write(
        '<p class="muted">No separate subtitle files came with this download. '
        'Many files have subtitles built in: in VLC, tap the speech-bubble icon '
        'to pick one.</p>',
      );
    } else {
      b.write(
        '<p class="muted">VLC is told to load the first of these. Built-in '
        'tracks, if any, are in its speech-bubble menu. Other files:</p>',
      );
      for (final l in subLinks) {
        b.write(
          '<a class="btn" href="${_esc.convert(l)}">${_esc.convert(Uri.decodeComponent(l.split('/').last))}</a>',
        );
      }
    }
    b.write('<h3>Other ways to open it</h3>');
    b.write(
      '<a class="btn" href="vlc://${_esc.convert(video)}">VLC (alternative link)</a>',
    );
    b.write('<a class="btn" href="${_esc.convert(infuse)}">Infuse</a>');
    b.write(
      '<p class="muted" style="word-break:break-all">Or in VLC: Network &rarr; '
      'Open Network Stream, and paste:<br>${_esc.convert(video)}</p>',
    );
    return b.toString();
  }
}
