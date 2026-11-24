import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:media_kit/media_kit.dart';

/// A snapshot of how playback is going, read from mpv. Shown by the `I`
/// overlay in the player and used by the playback benchmark.
class PlayerStats {
  const PlayerStats({
    this.hwdec,
    this.codec,
    this.width,
    this.height,
    this.containerFps,
    this.renderedFps,
    this.decoderDrops = 0,
    this.voDrops = 0,
    this.mistimed = 0,
    this.delayed = 0,
    this.cacheSpeedBytes,
    this.cacheAheadSecs,
    this.cacheAheadBytes,
    this.pausedForCache = false,
    this.videoBitrate,
    this.avsync,
    this.positionSecs,
  });

  /// Hardware decoder actually in use ("no" = software decoding).
  final String? hwdec;
  final String? codec;
  final int? width;
  final int? height;

  /// Frame rate the file says it has.
  final double? containerFps;

  /// Frame rate actually being produced/shown.
  final double? renderedFps;

  /// Frames the decoder gave up on (too slow to decode).
  final int decoderDrops;

  /// Frames dropped at display time (output could not keep up).
  final int voDrops;

  /// Frames shown at the wrong time (judder).
  final int mistimed;
  final int delayed;

  /// How fast data is arriving from the engine (bytes/s).
  final double? cacheSpeedBytes;

  /// Seconds of video already buffered ahead of the playhead.
  final double? cacheAheadSecs;
  final double? cacheAheadBytes;

  /// True while mpv has stopped to wait for data.
  final bool pausedForCache;

  /// Bits per second of the video stream.
  final double? videoBitrate;
  final double? avsync;
  final double? positionSecs;

  Map<String, Object?> toJson() => {
    'hwdec': hwdec,
    'codec': codec,
    'size': width == null ? null : '${width}x$height',
    'containerFps': containerFps,
    'renderedFps': renderedFps,
    'decoderDrops': decoderDrops,
    'voDrops': voDrops,
    'mistimed': mistimed,
    'delayed': delayed,
    'cacheMBps': cacheSpeedBytes == null
        ? null
        : double.parse((cacheSpeedBytes! / 1048576).toStringAsFixed(2)),
    'cacheAheadSecs': cacheAheadSecs == null
        ? null
        : double.parse(cacheAheadSecs!.toStringAsFixed(1)),
    'pausedForCache': pausedForCache,
    'videoMbps': videoBitrate == null
        ? null
        : double.parse((videoBitrate! / 1e6).toStringAsFixed(1)),
    'avsync': avsync,
    'positionSecs': positionSecs == null
        ? null
        : double.parse(positionSecs!.toStringAsFixed(1)),
  };

  /// Plain-language lines for the overlay.
  List<String> describe() {
    String f(double? v, [int d = 1]) => v == null ? '?' : v.toStringAsFixed(d);
    final hw = hwdec == null || hwdec == 'no'
        ? 'SOFTWARE (CPU)'
        : 'hardware ($hwdec)';
    return [
      'Video   ${codec ?? '?'}  ${width ?? '?'}x${height ?? '?'}  '
          '@ ${f(containerFps)} fps  ${f((videoBitrate ?? 0) / 1e6)} Mbit/s',
      'Decode  $hw',
      'Shown   ${f(renderedFps)} fps   dropped: $decoderDrops decoder, '
          '$voDrops display   mistimed: $mistimed',
      'Network ${f((cacheSpeedBytes ?? 0) / 1048576, 2)} MB/s   '
          'buffered ahead: ${f(cacheAheadSecs)} s',
      if (pausedForCache) 'WAITING FOR DATA (network too slow)',
      'A/V sync ${f(avsync, 3)} s',
    ];
  }

  static double? _d(String? s) => s == null ? null : double.tryParse(s);
  static int _i(String? s) => (double.tryParse(s ?? '') ?? 0).round();

  /// Reads the stats from a running mpv. Any property that is unavailable
  /// simply comes back null.
  static Future<PlayerStats> read(NativePlayer p) async {
    Future<String?> g(String name) async {
      try {
        final v = await p.getProperty(name);
        return v.isEmpty ? null : v;
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait([
      g('hwdec-current'), // 0
      g('video-codec'), // 1
      g('width'), // 2
      g('height'), // 3
      g('container-fps'), // 4
      g('estimated-vf-fps'), // 5
      g('decoder-frame-drop-count'), // 6
      g('frame-drop-count'), // 7
      g('mistimed-frame-count'), // 8
      g('vo-delayed-frame-count'), // 9
      g('cache-speed'), // 10
      g('demuxer-cache-duration'), // 11
      g('paused-for-cache'), // 12
      g('video-bitrate'), // 13
      g('avsync'), // 14
      g('time-pos'), // 15
      g('demuxer-cache-state'), // 16 (unused text, keeps indexes obvious)
    ]);
    return PlayerStats(
      hwdec: results[0],
      codec: results[1],
      width: _d(results[2])?.round(),
      height: _d(results[3])?.round(),
      containerFps: _d(results[4]),
      renderedFps: _d(results[5]),
      decoderDrops: _i(results[6]),
      voDrops: _i(results[7]),
      mistimed: _i(results[8]),
      delayed: _i(results[9]),
      cacheSpeedBytes: _d(results[10]),
      cacheAheadSecs: _d(results[11]),
      pausedForCache: results[12] == 'yes',
      videoBitrate: _d(results[13]),
      avsync: _d(results[14]),
      positionSecs: _d(results[15]),
    );
  }
}

/// Latest stats from the open player, for the benchmark to read. Null when no
/// player is open or stats are off.
final ValueNotifier<PlayerStats?> latestPlayerStats = ValueNotifier(null);

/// Set by the benchmark so the player collects stats even without the overlay.
bool collectPlayerStats = false;

/// Measures how fast the app itself is drawing (separate from the video's own
/// frame rate): a laggy-looking video with perfect mpv stats means the screen
/// is not being updated in time. Shown as a line in the `I` overlay.
class UiFrameMeter {
  UiFrameMeter._();
  static final instance = UiFrameMeter._();

  int _frames = 0;
  double _worstBuild = 0;
  double _worstRaster = 0;
  DateTime _since = DateTime.now();
  bool _on = false;

  void start() {
    if (_on) return;
    _on = true;
    _reset();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void stop() {
    if (!_on) return;
    _on = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  void _reset() {
    _frames = 0;
    _worstBuild = 0;
    _worstRaster = 0;
    _since = DateTime.now();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _frames++;
      final b = t.buildDuration.inMicroseconds / 1000;
      final r = t.rasterDuration.inMicroseconds / 1000;
      if (b > _worstBuild) _worstBuild = b;
      if (r > _worstRaster) _worstRaster = r;
    }
  }

  /// Frame rate the app drew during the last measured second.
  double lastFps = 0;

  /// The display's refresh rate in Hz (0 if unknown).
  static double get displayHz {
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      return views.isEmpty ? 0 : views.first.display.refreshRate;
    } catch (_) {
      return 0;
    }
  }

  /// One overlay line covering the time since the last call.
  String line() {
    final secs = DateTime.now().difference(_since).inMilliseconds / 1000;
    final fps = secs > 0 ? _frames / secs : 0.0;
    lastFps = fps;
    final hz = displayHz;
    final text =
        'Screen  app draws ${fps.toStringAsFixed(0)} fps'
        '${hz > 0 ? ' (display ${hz.toStringAsFixed(0)} Hz)' : ''}   '
        'slowest frame: build ${_worstBuild.toStringAsFixed(0)} ms, '
        'raster ${_worstRaster.toStringAsFixed(0)} ms';
    _reset();
    return text;
  }

  /// Compares what is drawn on screen with the video's own frame rate. Null
  /// while there is nothing to compare yet. [problem] is true when the screen
  /// shows noticeably fewer frames than the video has (what you see as lag).
  ({String text, bool problem})? verdict(double? videoFps) {
    if (videoFps == null || videoFps <= 0 || lastFps <= 0) return null;
    if (lastFps < videoFps * 0.9) {
      return (
        text:
            'CHECK   PROBLEM: screen shows ${lastFps.toStringAsFixed(0)} fps but '
            'the video has ${videoFps.toStringAsFixed(0)} fps: frames are being lost '
            'in drawing (not decoding)',
        problem: true,
      );
    }
    return (
      text:
          'CHECK   OK: screen (${lastFps.toStringAsFixed(0)} fps) keeps up with '
          'the ${videoFps.toStringAsFixed(0)} fps video',
      problem: false,
    );
  }
}
