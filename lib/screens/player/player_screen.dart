import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/platform.dart';
import '../../models/meta_item.dart';
import '../../models/next_up.dart';
import '../../models/stream_source.dart';
import '../../models/watch_progress.dart';
import '../../providers/library_provider.dart';
import '../../providers/prebuffer_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/trakt_provider.dart';
import '../../services/engine_service.dart';
import '../../services/next_episode.dart';
import '../../widgets/aurora_background.dart' show auroraHolds;
import '../../widgets/glass_button.dart';
import '../../widgets/share_dialog.dart';
import '../../services/share_server.dart';
import '../details/stream_picker.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/title_bar.dart';
import 'open_player.dart';
import 'play_next.dart';
import 'player_stats.dart';
import 'up_next_card.dart';
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
    this.startFullscreen = false,
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

  /// Open already fullscreen (carried over when moving to the next episode).
  final bool startFullscreen;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player(
    configuration: const PlayerConfiguration(
      title: 'Velora',
      bufferSize: 256 * 1024 * 1024,
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
  Timer? _statsTimer;
  bool _showStats = false;
  PlayerStats? _stats;
  String _uiLine = '';
  late final PrebufferProvider _prebuffer;
  late final SettingsProvider _settings;
  bool _aheadQueued = false;

  // --- next episode ---
  late final NextEpisodeService _nextSvc;
  late final EngineService _engine;
  Episode? _nextEp;
  StreamSource? _nextSource;
  bool _nextLookedUp = false;
  bool _upNextVisible = false;
  bool _upNextDismissed = false;
  bool _handoff = false; // moving on to the next episode
  bool _stopSent = false; // Trakt "stop" already sent for this episode
  int _countdown = 10;
  Timer? _countdownTimer;

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
    _nextSvc = context.read<NextEpisodeService>();
    _prebuffer = context.read<PrebufferProvider>();
    _settings = context.read<SettingsProvider>();
    _engine = context.read<EngineService>();
    _fullscreen = widget.startFullscreen;
    UiFrameMeter.instance.start();
    _statsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _pollStats(),
    );
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
      _player.stream.position.listen((v) {
        setState(() => _position = v);
        _onPosition(v);
      }),
      _player.stream.completed.listen(_onCompleted),
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

      // Refuse early, with a clear reason, if the file cannot fit (cache
      // limit or free disk space) instead of failing mid-stream.
      final problem = await engine.checkPlayable(
        infoHash: widget.source.infoHash,
        fileIdx: widget.source.fileIdx,
        trackers: widget.source.trackers,
        name: widget.source.release,
      );
      if (problem != null) {
        if (mounted) setState(() => _error = problem);
        return;
      }

      // The engine may need a while to find peers: be patient, and reconnect
      // if the HTTP range stream hiccups.
      final native = _player.platform;
      if (native is NativePlayer) {
        await native.setProperty('network-timeout', '120');
        // Torrent sources arrive in bursts. If data runs short, stop and refill
        // a decent amount before resuming: one clear pause instead of many tiny
        // stop-start stutters (mpv's default resumes after just 1 second).
        await native.setProperty('cache-pause-wait', '6');
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

  /// Read mpv's playback stats (overlay with `I`, or the benchmark).
  Future<void> _pollStats() async {
    if (!_showStats && !collectPlayerStats) return;
    final native = _player.platform;
    if (native is! NativePlayer || !_started) return;
    final s = await PlayerStats.read(native);
    if (!mounted) return;
    latestPlayerStats.value = s;
    if (_showStats) {
      setState(() {
        _stats = s;
        _uiLine = UiFrameMeter.instance.line();
      });
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
    if (!_stopSent) {
      _scrobble('stop'); // >=80% watched also lands in Trakt history
    }
    _saveProgress();
    _countdownTimer?.cancel();
    if (!_handoff) unawaited(_recordNextUp());
    _saveTimer?.cancel();
    _statsTimer?.cancel();
    UiFrameMeter.instance.stop();
    latestPlayerStats.value = null;
    _hideTimer?.cancel();
    _statusTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    // Staying fullscreen when handing over to the next episode.
    if (_fullscreen && isDesktop && !_handoff) {
      windowManager.setFullScreen(false);
    }
    _focus.dispose();
    _player.dispose();
    super.dispose();
  }

  // ---- next episode -------------------------------------------------------

  bool get _isSeries =>
      widget.meta.isSeries && widget.season != null && widget.episode != null;

  bool get _autoplay => context.read<SettingsProvider>().autoplayNext;

  /// Called on every position update.
  void _onPosition(Duration p) {
    if (!_isSeries || _duration <= Duration.zero) return;
    final frac = p.inMilliseconds / _duration.inMilliseconds;

    // With "pre-buffer next episodes" on, start downloading them early: a
    // whole episode needs far longer than the last few minutes.
    if (!_aheadQueued && _settings.prebufferAhead > 0 && frac >= 0.08) {
      _aheadQueued = true;
      final ep = _currentEpisode;
      if (ep != null) {
        unawaited(
          _prebuffer.queueAhead(
            meta: widget.meta,
            current: ep,
            source: widget.source,
          ),
        );
      }
    }

    // Look up what is next once we are well into the episode, so it is ready.
    if (!_nextLookedUp && frac >= 0.55) {
      _nextLookedUp = true;
      unawaited(_prepareNext());
    }

    // Credits: the last ~35 seconds (or the last 3%) of a normal episode.
    final remaining = _duration - p;
    final inCredits =
        _duration > const Duration(minutes: 3) &&
        (remaining <= const Duration(seconds: 35) || frac >= 0.97);
    if (inCredits && _nextEp != null && !_upNextDismissed && !_handoff) {
      if (!_upNextVisible) _showUpNext();
    } else if (_upNextVisible && !inCredits && !_handoff) {
      _hideUpNext(); // the user skipped back
    }
  }

  /// Watch on another device (iPad): shows a QR code that opens this video
  /// from this PC's engine.
  Future<void> _shareToIpad() async {
    var idx = widget.source.fileIdx;
    if (idx == null) {
      final c = await _engine.inspect(
        infoHash: widget.source.infoHash,
        trackers: widget.source.trackers,
        name: widget.source.release,
      );
      idx = c.idx;
    }
    if (idx == null || !mounted) return;
    final label = [
      widget.meta.name,
      if ((widget.subtitle ?? '').isNotEmpty) widget.subtitle!,
    ].join('  -  ');
    await showShareDialog(
      context,
      item: ShareItem(
        id: '${widget.source.infoHash.toLowerCase()}-$idx',
        label: label,
        infoHash: widget.source.infoHash,
        fileIdx: idx,
        trackers: widget.source.trackers,
        name: widget.source.release,
        meta: widget.meta,
        videoId: widget.videoId,
        season: widget.season,
        episode: widget.episode,
        episodeTitle: widget.episodeTitle,
        source: widget.source,
      ),
    );
  }

  /// Pick another source for what is playing and carry on from the exact same
  /// moment: the new one only downloads from here on (the engine fetches only
  /// what the player asks for), and the old one stops.
  Future<void> _switchSource() async {
    if (_handoff) return;
    final pos = _position;
    final dur = _duration;
    final wasPlaying = _player.state.playing;
    _player.pause();
    final picked = await showStreamPicker(
      context,
      type: widget.meta.type,
      videoId: widget.videoId,
      title: widget.meta.name,
      subtitle: widget.subtitle,
    );
    if (!mounted) return;
    final same =
        picked != null &&
        picked.infoHash == widget.source.infoHash &&
        picked.fileIdx == widget.source.fileIdx;
    if (picked == null || same) {
      if (wasPlaying) _player.play();
      return;
    }
    _handoff = true;
    _saveProgress();
    _scrobble('stop');
    _stopSent = true;
    Navigator.of(context).pushReplacement(
      playerRoute(
        source: picked,
        meta: widget.meta,
        videoId: widget.videoId,
        subtitle: widget.subtitle,
        season: widget.season,
        episode: widget.episode,
        episodeTitle: widget.episodeTitle,
        resumeFrom: pos,
        knownDuration: dur,
        fullscreen: _fullscreen,
      ),
    );
  }

  Episode? get _currentEpisode =>
      widget.season == null || widget.episode == null
      ? null
      : Episode(
          id: widget.videoId,
          season: widget.season!,
          number: widget.episode!,
          title: widget.episodeTitle ?? '',
        );

  /// Finds the next episode and a matching source, and warms the engine up.
  Future<void> _prepareNext() async {
    try {
      final ep = await _nextSvc.nextEpisode(
        widget.meta,
        widget.season!,
        widget.episode!,
      );
      if (!mounted) return;
      setState(() => _nextEp = ep);
      if (ep == null) return; // last episode of the series, or not aired yet
      final src =
          _prebuffer.sourceFor(ep.id) ??
          await _nextSvc.sourceFor(ep, widget.source);
      if (!mounted) return;
      setState(() => _nextSource = src);
      if (src != null && _settings.prebufferAhead == 0) {
        unawaited(
          _engine.prefetch(
            infoHash: src.infoHash,
            fileIdx: src.fileIdx,
            trackers: src.trackers,
            name: src.release,
          ),
        );
      }
    } catch (_) {
      // No suggestion; the card falls back to the source picker.
    }
  }

  void _showUpNext() {
    setState(() {
      _upNextVisible = true;
      _countdown = 10;
    });
    _countdownTimer?.cancel();
    if (_autoplay) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (!_playing) return; // paused: wait
        if (_countdown <= 1) {
          t.cancel();
          _playNext();
        } else {
          setState(() => _countdown--);
        }
      });
    }
  }

  void _hideUpNext() {
    _countdownTimer?.cancel();
    if (mounted) setState(() => _upNextVisible = false);
  }

  void _dismissUpNext() {
    _upNextDismissed = true;
    _hideUpNext();
  }

  /// The player reached the end of the file.
  void _onCompleted(bool done) {
    if (!done || !_isSeries || _handoff || _duration <= Duration.zero) return;
    // A stalled stream can report "end" early; only trust it near the end.
    if (_duration - _position > const Duration(seconds: 90)) return;
    if (_nextEp == null) return;
    if (!_upNextDismissed && _autoplay) {
      _playNext();
    } else if (mounted) {
      setState(() => _upNextVisible = true);
    }
  }

  /// Switch to the next episode now.
  Future<void> _playNext() async {
    final ep = _nextEp;
    if (ep == null || _handoff || !mounted) return;
    _handoff = true;
    _countdownTimer?.cancel();

    // Moving on counts as having watched this one.
    _player.pause();
    _library.markWatched([widget.videoId]);
    _saveProgress();
    _scrobble('stop');
    _stopSent = true;

    final keepFullscreen = _fullscreen;
    final src = _nextSource;
    final label = 'S${ep.season} E${ep.number}  -  ${ep.title}';
    if (src != null) {
      Navigator.of(context).pushReplacement(
        playerRoute(
          source: src,
          meta: widget.meta,
          videoId: ep.id,
          subtitle: label,
          season: ep.season,
          episode: ep.number,
          episodeTitle: ep.title,
          fullscreen: keepFullscreen,
        ),
      );
      return;
    }

    // No matching source was found automatically: let the user pick.
    final opened = await playEpisodeAuto(
      context,
      meta: widget.meta,
      next: ep,
      reference: widget.source,
      replace: true,
      fullscreen: keepFullscreen,
    );
    if (!opened && mounted) {
      // They backed out of the picker: stay here, quietly.
      _handoff = false;
      _stopSent = false;
      _upNextDismissed = true;
      setState(() => _upNextVisible = false);
    }
  }

  /// Leaving an episode that is (nearly) finished: remember what comes next so
  /// Home, the Library and the title page can offer it.
  Future<void> _recordNextUp() async {
    if (!_isSeries || _duration <= Duration.zero) return;
    final finished =
        _position.inMilliseconds / _duration.inMilliseconds >= 0.92 ||
        _duration - _position < const Duration(seconds: 90);
    if (!finished) return;
    try {
      final ep =
          _nextEp ??
          await _nextSvc.nextEpisode(
            widget.meta,
            widget.season!,
            widget.episode!,
          );
      if (ep == null) {
        await _library.clearNextUp(widget.meta.id); // series finished
        return;
      }
      if (_library.isWatched(ep.id)) return; // already seen: nothing to suggest
      await _library.setNextUp(
        NextUp(
          meta: widget.meta,
          episode: ep,
          reference: widget.source,
          updatedAt: DateTime.now(),
        ),
      );
    } catch (_) {}
  }

  Widget _upNextOverlay() {
    final ep = _nextEp;
    if (!_upNextVisible || ep == null) return const SizedBox.shrink();
    return Positioned(
      right: 28,
      bottom: 136, // above the control bar
      child: UpNextCard(
        episode: ep,
        seriesName: widget.meta.name,
        sourceReady: _nextSource != null,
        countdown: _autoplay ? _countdown : null,
        onPlay: _playNext,
        onCancel: _dismissUpNext,
      ),
    );
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
        const SingleActivator(LogicalKeyboardKey.keyI): () {
          setState(() => _showStats = !_showStats);
          if (_showStats) _pollStats();
        },
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
                if (_showStats && _stats != null)
                  Positioned(
                    left: 16,
                    top: 70,
                    child: IgnorePointer(
                      child: _StatsOverlay(_stats!, _uiLine),
                    ),
                  ),
                _controlsLayer(),
                _upNextOverlay(),
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
                _IconBtn(
                  icon: Icons.swap_horiz_rounded,
                  tooltip: 'Switch source (keeps your place)',
                  onTap: _switchSource,
                ),
                if (isDesktop)
                  _IconBtn(
                    icon: Icons.tablet_mac_rounded,
                    tooltip: 'Play on iPad',
                    onTap: _shareToIpad,
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

class _StatsOverlay extends StatelessWidget {
  const _StatsOverlay(this.stats, this.uiLine);

  final PlayerStats stats;
  final String uiLine;

  @override
  Widget build(BuildContext context) {
    final verdict = UiFrameMeter.instance.verdict(stats.containerFps);
    final bad =
        (verdict?.problem ?? false) ||
        stats.pausedForCache ||
        stats.decoderDrops > 0 ||
        stats.voDrops > 0 ||
        (stats.hwdec == null || stats.hwdec == 'no');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (bad ? const Color(0xFFFFB74D) : const Color(0xFF69F0AE))
              .withValues(alpha: 0.6),
        ),
      ),
      child: Text(
        [
          ...stats.describe(),
          if (uiLine.isNotEmpty) uiLine,
          if (verdict != null) verdict.text,
        ].join('\n'),
        style: const TextStyle(
          fontFamily: 'Consolas',
          fontSize: 12.5,
          height: 1.4,
          color: Colors.white,
        ),
      ),
    );
  }
}
