import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/platform.dart';
import '../../models/meta_item.dart';
import '../../models/stream_source.dart';
import '../../models/watch_progress.dart';
import '../../providers/library_provider.dart';
import '../../providers/trakt_provider.dart';
import '../../services/engine_service.dart';
import '../../widgets/aurora_background.dart' show auroraHolds;
import '../../widgets/glass_button.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/title_bar.dart';
import 'seek_bar.dart';

/// Plays one torrent source through the local engine with glass controls.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.source,
    required this.title,
    required this.meta,
    required this.videoId,
    this.subtitle,
    this.season,
    this.episode,
    this.episodeTitle,
    this.startAt,
  });

  final StreamSource source;
  final String title;
  final String? subtitle;

  /// What is being watched (for saving progress).
  final MetaItem meta;
  final String videoId;
  final int? season;
  final int? episode;
  final String? episodeTitle;

  /// Resume point; null starts from the beginning.
  final Duration? startAt;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player(
    configuration: const PlayerConfiguration(
      title: 'Velora',
      bufferSize: 128 * 1024 * 1024,
    ),
  );
  late final VideoController _video = VideoController(_player);
  final _subs = <StreamSubscription<dynamic>>[];
  final _focus = FocusNode();

  late final LibraryProvider _library;
  late final TraktProvider _trakt;
  Timer? _hideTimer;
  Timer? _statusTimer;
  Timer? _saveTimer;

  bool _controlsVisible = true;
  bool _fullscreen = false;
  bool _playing = false;
  bool _buffering = true;
  bool _started = false; // first frame / duration known
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  double _volume = 100;
  double _lastVolume = 100;
  Tracks _tracks = const Tracks();
  Track _track = const Track();
  String? _error;
  EngineStatus? _status;

  @override
  void initState() {
    super.initState();
    auroraHolds.value++; // video is opaque: stop animating behind it
    _library = context.read<LibraryProvider>();
    _trakt = context.read<TraktProvider>();
    _saveTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _saveProgress(),
    );
    _subs.addAll([
      _player.stream.playing.listen((v) {
        setState(() => _playing = v);
        if (!v) _saveProgress(); // paused or stopped: remember the spot
        if (v) {
          _scrobble('start');
        } else if (_started) {
          _scrobble('pause');
        }
        _poke();
      }),
      _player.stream.buffering.listen((v) => setState(() => _buffering = v)),
      _player.stream.position.listen((v) => setState(() => _position = v)),
      _player.stream.duration.listen(
        (v) => setState(() {
          _duration = v;
          if (v > Duration.zero) _started = true;
        }),
      ),
      _player.stream.buffer.listen((v) => setState(() => _buffered = v)),
      _player.stream.volume.listen((v) => setState(() => _volume = v)),
      _player.stream.tracks.listen((v) => setState(() => _tracks = v)),
      _player.stream.track.listen((v) => setState(() => _track = v)),
      _player.stream.error.listen((e) => setState(() => _error = e)),
    ]);
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _error = null;
      _started = false;
    });
    try {
      final engine = context.read<EngineService>();
      await engine.start();
      final url = engine.streamUrl(
        infoHash: widget.source.infoHash,
        fileIdx: widget.source.fileIdx,
        trackers: widget.source.trackers,
        name: widget.source.release,
      );

      // The engine may need a while to find peers: be patient, and reconnect
      // if the HTTP range stream hiccups.
      final native = _player.platform;
      if (native is NativePlayer) {
        await native.setProperty('network-timeout', '120');
        await native.setProperty(
          'stream-lavf-o',
          'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5',
        );
      }
      await _player.open(Media(url, start: widget.startAt));

      _statusTimer?.cancel();
      _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (!mounted) return;
        if (_started && !_buffering) return;
        final s = await engine.status(widget.source.infoHash);
        if (mounted) setState(() => _status = s);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// Tell Trakt (if connected): start / pause / stop. Never blocks playback.
  void _scrobble(String action) {
    _trakt.scrobble(
      action,
      widget.meta,
      season: widget.season,
      episode: widget.episode,
      position: _position,
      duration: _duration,
    );
  }

  /// Persist where we are. Cheap enough to call every 10s and on pause.
  void _saveProgress() {
    if (_duration <= Duration.zero || _position <= Duration.zero) return;
    _library.saveProgress(
      WatchProgress(
        videoId: widget.videoId,
        meta: widget.meta,
        positionMs: _position.inMilliseconds,
        durationMs: _duration.inMilliseconds,
        updatedAt: DateTime.now(),
        source: widget.source,
        season: widget.season,
        episode: widget.episode,
        episodeTitle: widget.episodeTitle,
      ),
    );
  }

  @override
  void dispose() {
    auroraHolds.value--;
    _scrobble('stop'); // >=80% watched also lands in Trakt history
    _saveProgress();
    _saveTimer?.cancel();
    _hideTimer?.cancel();
    _statusTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    if (_fullscreen && isDesktop) windowManager.setFullScreen(false);
    _focus.dispose();
    _player.dispose();
    super.dispose();
  }

  // ---- controls -----------------------------------------------------------

  void _poke() {
    _hideTimer?.cancel();
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    if (_playing) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _playing) setState(() => _controlsVisible = false);
      });
    }
  }

  void _seekBy(Duration d) {
    var t = _position + d;
    if (t < Duration.zero) t = Duration.zero;
    if (_duration > Duration.zero && t > _duration) t = _duration;
    _player.seek(t);
    _poke();
  }

  void _setVolume(double v) {
    _player.setVolume(v.clamp(0, 100));
    _poke();
  }

  void _toggleMute() {
    if (_volume > 0) {
      _lastVolume = _volume;
      _player.setVolume(0);
    } else {
      _player.setVolume(_lastVolume == 0 ? 100 : _lastVolume);
    }
    _poke();
  }

  Future<void> _toggleFullscreen() async {
    if (!isDesktop) return;
    _fullscreen = !_fullscreen;
    await windowManager.setFullScreen(_fullscreen);
    if (mounted) setState(() {});
    _poke();
  }

  Future<void> _exit() async {
    if (_fullscreen && isDesktop) {
      _fullscreen = false;
      await windowManager.setFullScreen(false);
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  // ---- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final showSpinner = !_started || _buffering;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): _player.playOrPause,
        const SingleActivator(LogicalKeyboardKey.keyK): _player.playOrPause,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _seekBy(const Duration(seconds: -10)),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _seekBy(const Duration(seconds: 10)),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): () =>
            _seekBy(const Duration(seconds: -30)),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): () =>
            _seekBy(const Duration(seconds: 30)),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _setVolume(_volume + 5),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _setVolume(_volume - 5),
        const SingleActivator(LogicalKeyboardKey.keyM): _toggleMute,
        const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
        const SingleActivator(LogicalKeyboardKey.f11): _toggleFullscreen,
        const SingleActivator(LogicalKeyboardKey.escape): _exit,
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: MouseRegion(
            onHover: (_) => _poke(),
            cursor: _controlsVisible
                ? MouseCursor.defer
                : SystemMouseCursors.none,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Click = play/pause, double-click = fullscreen.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _player.playOrPause();
                    _poke();
                  },
                  onDoubleTap: _toggleFullscreen,
                  child: Video(
                    controller: _video,
                    controls: NoVideoControls,
                    fit: BoxFit.contain,
                    fill: Colors.black,
                  ),
                ),
                if (_error == null && showSpinner)
                  IgnorePointer(
                    child: _LoadingOverlay(status: _status, started: _started),
                  ),
                if (_error != null)
                  _ErrorOverlay(
                    message: _error!,
                    onRetry: _open,
                    onBack: _exit,
                  ),
                _controlsLayer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controlsLayer() {
    final visible = _controlsVisible || !_playing;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Soft scrims top and bottom (never absorb clicks).
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xCC000000),
                      Color(0x00000000),
                      Color(0x00000000),
                      Color(0xE6000000),
                    ],
                    stops: [0, 0.22, 0.65, 1],
                  ),
                ),
              ),
            ),
            Positioned(top: 0, left: 0, right: 0, child: _topBar()),
            Positioned(left: 0, right: 0, bottom: 0, child: _bottomBar()),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    final lead = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassButton(
          label: 'Back',
          icon: Icons.arrow_back_rounded,
          onTap: _exit,
        ),
        const SizedBox(width: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (widget.subtitle != null)
                Text(
                  widget.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: Colors.white60),
                ),
            ],
          ),
        ),
      ],
    );

    if (isDesktop && !_fullscreen) return VeloraTitleBar(leading: lead);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Align(alignment: Alignment.centerLeft, child: lead),
      ),
    );
  }

  Widget _bottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 22),
      child: GlassPanel(
        borderRadius: 24,
        blur: 26,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  _fmt(_position),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SeekBar(
                    position: _position,
                    duration: _duration,
                    buffered: _buffered,
                    onSeek: (d) {
                      _player.seek(d);
                      _poke();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _fmt(_duration),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Colors.white70,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _IconBtn(
                  icon: Icons.replay_10_rounded,
                  tooltip: 'Back 10s',
                  onTap: () => _seekBy(const Duration(seconds: -10)),
                ),
                _IconBtn(
                  icon: _playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 38,
                  tooltip: _playing ? 'Pause' : 'Play',
                  onTap: () {
                    _player.playOrPause();
                    _poke();
                  },
                ),
                _IconBtn(
                  icon: Icons.forward_10_rounded,
                  tooltip: 'Forward 10s',
                  onTap: () => _seekBy(const Duration(seconds: 10)),
                ),
                const SizedBox(width: 8),
                _IconBtn(
                  icon: _volume == 0
                      ? Icons.volume_off_rounded
                      : (_volume < 50
                            ? Icons.volume_down_rounded
                            : Icons.volume_up_rounded),
                  tooltip: 'Mute',
                  onTap: _toggleMute,
                ),
                SizedBox(
                  width: 96,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: SliderComponentShape.noOverlay,
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: _volume.clamp(0, 100),
                      min: 0,
                      max: 100,
                      onChanged: _setVolume,
                    ),
                  ),
                ),
                const Spacer(),
                _trackMenu<AudioTrack>(
                  icon: Icons.audiotrack_rounded,
                  tooltip: 'Audio',
                  tracks: [
                    for (final t in _tracks.audio)
                      if (t.id != 'auto' && t.id != 'no') t,
                  ],
                  current: _track.audio,
                  label: _trackLabel,
                  onPick: _player.setAudioTrack,
                ),
                _trackMenu<SubtitleTrack>(
                  icon: Icons.subtitles_rounded,
                  tooltip: 'Subtitles',
                  tracks: [
                    SubtitleTrack.no(),
                    for (final t in _tracks.subtitle)
                      if (t.id != 'auto' && t.id != 'no') t,
                  ],
                  current: _track.subtitle,
                  label: (t) => t.id == 'no' ? 'Off' : _trackLabel(t),
                  onPick: _player.setSubtitleTrack,
                ),
                if (isDesktop)
                  _IconBtn(
                    icon: _fullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    tooltip: 'Fullscreen (F)',
                    onTap: _toggleFullscreen,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _trackMenu<T extends Object>({
    required IconData icon,
    required String tooltip,
    required List<T> tracks,
    required T current,
    required String Function(T) label,
    required void Function(T) onPick,
  }) {
    if (tracks.isEmpty || (tracks.length == 1 && T == AudioTrack)) {
      return const SizedBox.shrink();
    }
    bool same(T a, T b) => (a as dynamic).id == (b as dynamic).id;
    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: const Color(0xF2141826),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
          ),
        ),
      ),
      child: PopupMenuButton<T>(
        tooltip: tooltip,
        icon: Icon(icon, size: 24),
        onOpened: _poke,
        onSelected: onPick,
        itemBuilder: (_) => [
          for (final t in tracks)
            PopupMenuItem<T>(
              value: t,
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: same(t, current)
                        ? const Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: Color(0xFF00E5FF),
                          )
                        : null,
                  ),
                  Flexible(child: Text(label(t))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _trackLabel(dynamic t) {
    final title = t.title as String?;
    final lang = t.language as String?;
    final parts = [
      if (lang != null && lang.isNotEmpty) lang.toUpperCase(),
      if (title != null && title.isNotEmpty) title,
    ];
    return parts.isEmpty ? 'Track ${t.id}' : parts.join('  -  ');
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.size = 26,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    tooltip: tooltip,
    iconSize: size,
    icon: Icon(icon),
    color: Colors.white,
    focusNode: FocusNode(skipTraversal: true),
  );
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({required this.status, required this.started});

  final EngineStatus? status;
  final bool started;

  @override
  Widget build(BuildContext context) {
    final s = status;
    String line;
    if (s == null) {
      line = 'Starting engine...';
    } else if (!s.hasMetadata) {
      line = s.peers == 0
          ? 'Looking for peers...'
          : 'Connected to ${s.peers} peers, fetching file info...';
    } else {
      final pct = s.progress == null
          ? ''
          : '  -  ${(s.progress! * 100).toStringAsFixed(1)}% on disk';
      line =
          '${started ? 'Buffering' : 'Starting'}  -  ${s.peers} peers'
          '${s.seeders > 0 ? ' (${s.seeders} seeders)' : ''}$pct';
    }
    return Center(
      child: GlassPanel(
        borderRadius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 16),
            Text(line, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: GlassPanel(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 38),
            const SizedBox(height: 12),
            const Text(
              "Couldn't play this source",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassButton(label: 'Pick another', onTap: onBack),
                const SizedBox(width: 12),
                GlassButton(
                  label: 'Retry',
                  icon: Icons.refresh_rounded,
                  primary: true,
                  autofocus: true,
                  onTap: onRetry,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
