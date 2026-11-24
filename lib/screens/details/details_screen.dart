import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/platform.dart';
import '../../core/smooth_scroll.dart';
import '../../models/meta_item.dart';
import '../../models/watch_progress.dart';
import '../../providers/library_provider.dart';
import '../../providers/prebuffer_provider.dart';
import '../../services/next_episode.dart';
import '../../widgets/prebuffer_button.dart';
import '../../widgets/toast.dart';
import '../../services/cinemeta_service.dart';
import '../../widgets/aurora_background.dart' show auroraHolds;
import '../../widgets/glass_button.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/net_image.dart';
import '../../widgets/title_bar.dart';
import '../../models/next_up.dart';
import '../player/open_player.dart';
import '../player/play_next.dart';
import 'stream_picker.dart';

/// Title page: backdrop, poster, facts, and (for series) season + episodes.
/// Picking something to play lands in Phase 4 (streams + player).
class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key, required this.item});

  final MetaItem item;

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  late MetaItem _item = widget.item;
  int? _season;
  final _scroll = SmoothScrollController();

  @override
  void initState() {
    super.initState();
    auroraHolds.value++; // this page is opaque: pause the aurora under it
    _loadFull();
  }

  /// The catalog entry is a summary; fetch cast, runtime and episodes.
  Future<void> _loadFull() async {
    try {
      final full = await CinemetaService().meta(_item.type, _item.id);
      if (!mounted) return;
      setState(() {
        _item = full;
        final seasons = full.seasons;
        _season = seasons.isEmpty ? null : seasons.first;
      });
    } catch (_) {
      // Keep showing the summary; the page is still useful.
    }
  }

  /// Choose a source for [videoId] in the picker, then play (resuming if we
  /// have a saved position for it).
  Future<void> _pick({
    required String videoId,
    required String subtitle,
    Episode? episode,
    bool forcePicker = false,
  }) async {
    final lib = context.read<LibraryProvider>();
    // Already pre-buffered: play that copy, no need to choose again.
    final pre = forcePicker
        ? null
        : context.read<PrebufferProvider>().sourceFor(videoId);
    final source =
        pre ??
        await showStreamPicker(
          context,
          type: _item.type,
          videoId: videoId,
          title: _item.name,
          subtitle: subtitle,
        );
    if (source == null || !mounted) return;
    final saved = lib.progressFor(videoId);
    await openPlayer(
      context,
      source: source,
      meta: _item,
      videoId: videoId,
      subtitle: subtitle,
      season: episode?.season,
      episode: episode?.number,
      episodeTitle: episode?.title,
      resumeFrom: saved?.finished == true ? null : saved?.position,
      knownDuration: saved?.duration,
    );
  }

  String _episodeLabel(Episode e) =>
      '${_item.name}  -  S${e.season} E${e.number}  -  ${e.title}';

  /// Pick a source, then download it ahead of time (episode, or the movie).
  Future<void> _prebuffer(Episode? e) async {
    final pb = context.read<PrebufferProvider>();
    final id = e?.id ?? _item.id;
    final label = e == null ? _item.name : _episodeLabel(e);
    final source = await showStreamPicker(
      context,
      type: _item.type,
      videoId: id,
      title: _item.name,
      subtitle: e == null
          ? _movieSubtitle
          : 'S${e.season} E${e.number}  -  ${e.title}',
    );
    if (source == null || !mounted) return;
    showToast(context, 'Starting pre-buffer: $label');
    final msg = await pb.start(
      meta: _item,
      videoId: id,
      label: label,
      source: source,
      episode: e,
    );
    if (!mounted) return;
    showToast(
      context,
      msg ?? 'Pre-buffering $label. It keeps going while you browse.',
      error: msg != null,
    );
  }

  /// Pre-buffer every aired episode of [season] that is not watched yet: pick a
  /// source once, the rest use a matching one.
  Future<void> _prebufferSeason(int season) async {
    final pb = context.read<PrebufferProvider>();
    final lib = context.read<LibraryProvider>();
    final svc = context.read<NextEpisodeService>();
    final now = DateTime.now();
    final eps = _item
        .episodesOf(season)
        .where((e) => e.released == null || e.released!.isBefore(now))
        .where((e) => !lib.isWatched(e.id) && pb.entryFor(e.id) == null)
        .toList();
    if (eps.isEmpty) {
      showToast(context, 'Nothing left to pre-buffer in this season.');
      return;
    }
    final first = eps.first;
    final ref = await showStreamPicker(
      context,
      type: _item.type,
      videoId: first.id,
      title: _item.name,
      subtitle:
          'Season $season: pick the source to use (the other episodes get a matching one)',
    );
    if (ref == null || !mounted) return;
    showToast(
      context,
      'Pre-buffering ${eps.length} episodes of season $season',
    );
    var started = 0;
    String? stopped;
    for (final e in eps) {
      final src = e == first ? ref : await svc.sourceFor(e, ref);
      if (src == null) {
        stopped = 'No matching source for S${e.season} E${e.number}.';
        break;
      }
      final msg = await pb.start(
        meta: _item,
        videoId: e.id,
        label: _episodeLabel(e),
        source: src,
        episode: e,
      );
      if (msg != null) {
        stopped = msg;
        break;
      }
      started++;
    }
    if (!mounted) return;
    showToast(
      context,
      stopped == null
          ? 'Started $started episodes. They download in the background.'
          : 'Started $started episodes, then stopped: $stopped',
      error: stopped != null,
    );
  }

  String get _movieSubtitle => [
    if (_item.releaseInfo != null) _item.releaseInfo!,
    'Movie',
  ].join('  -  ');

  void _playMovie({bool forcePicker = false}) => _pick(
    videoId: _item.id,
    subtitle: _movieSubtitle,
    forcePicker: forcePicker,
  );

  void _playEpisode(Episode e, {bool forcePicker = false}) => _pick(
    videoId: e.id,
    subtitle: 'S${e.season} E${e.number}  -  ${e.title}',
    episode: e,
    forcePicker: forcePicker,
  );

  /// Continue exactly where we left off, with the same source if we have it.
  Future<void> _resume(WatchProgress p) async {
    final source = p.source;
    final subtitle = p.episodeLabel ?? _movieSubtitle;
    if (source == null) {
      return _pick(videoId: p.videoId, subtitle: subtitle);
    }
    await openPlayer(
      context,
      source: source,
      meta: _item,
      videoId: p.videoId,
      subtitle: subtitle,
      season: p.season,
      episode: p.episode,
      episodeTitle: p.episodeTitle,
      resumeFrom: p.position,
      knownDuration: p.duration,
    );
  }

  /// Series main button: first episode of the first real season.
  Episode? get _firstEpisode {
    final seasons = _item.seasons;
    if (seasons.isEmpty) return null;
    final eps = _item.episodesOf(seasons.first);
    return eps.isEmpty ? null : eps.first;
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final lib = context.watch<LibraryProvider>();
    final resume = lib.resumeFor(item.id);
    // After finishing an episode: what to watch next (only when not mid-episode).
    final NextUp? nextUp = resume == null ? lib.nextUpFor(item.id) : null;
    final wide = MediaQuery.sizeOf(context).width >= 820;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xFF060912),
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Backdrop, top-anchored, fading into the page.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 560,
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (r) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.transparent],
                    stops: [0.4, 1.0],
                  ).createShader(r),
                  child: NetImage(
                    item.heroImage,
                    alignment: Alignment.topCenter,
                    cacheWidth: 1600,
                  ),
                ),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xE6060912), Color(0x66060912)],
                    ),
                  ),
                ),
              ),
              Column(
                children: [
                  if (isDesktop)
                    VeloraTitleBar(leading: _BackButton(onTap: _pop))
                  else
                    SafeArea(
                      bottom: false,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: _BackButton(onTap: _pop),
                        ),
                      ),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(
                        wide ? 48 : 20,
                        12,
                        wide ? 48 : 20,
                        48,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Header(
                            item: item,
                            wide: wide,
                            playLabel: item.isSeries
                                ? (_firstEpisode == null
                                      ? 'Loading episodes...'
                                      : 'Play S${_firstEpisode!.season} E${_firstEpisode!.number}')
                                : 'Watch now',
                            onChoose: () => nextUp != null
                                ? _playEpisode(
                                    nextUp.episode,
                                    forcePicker: true,
                                  )
                                : (item.isSeries
                                      ? (_firstEpisode == null
                                            ? null
                                            : _playEpisode(
                                                _firstEpisode!,
                                                forcePicker: true,
                                              ))
                                      : _playMovie(forcePicker: true)),
                            onPlay: nextUp != null
                                ? () => _playEpisode(nextUp.episode)
                                : (item.isSeries
                                      ? (_firstEpisode == null
                                            ? null
                                            : () =>
                                                  _playEpisode(_firstEpisode!))
                                      : _playMovie),
                            resumeLabel: resume != null
                                ? (item.isSeries
                                      ? 'Resume S${resume.season} E${resume.episode}  ${_fmt(resume.position)}'
                                      : 'Resume  ${_fmt(resume.position)}')
                                : (nextUp != null
                                      ? 'Play next  S${nextUp.episode.season} E${nextUp.episode.number}'
                                      : null),
                            onResume: resume != null
                                ? () => _resume(resume)
                                : (nextUp != null
                                      ? () => playEpisodeAuto(
                                          context,
                                          meta: _item,
                                          next: nextUp.episode,
                                          reference: nextUp.reference,
                                        )
                                      : null),
                            isFavourite: lib.isFavourite(item.id),
                            onToggleFavourite: () => lib.toggleFavourite(item),
                            prebufferId: item.isSeries ? null : item.id,
                            onPrebuffer: item.isSeries
                                ? null
                                : () => _prebuffer(null),
                          ),
                          if (item.isSeries && item.seasons.isNotEmpty) ...[
                            const SizedBox(height: 36),
                            _Episodes(
                              item: item,
                              season: _season ?? item.seasons.first,
                              onSeason: (s) => setState(() => _season = s),
                              onPlay: _playEpisode,
                              onPrebuffer: (e) => _prebuffer(e),
                              onPrebufferSeason: _prebufferSeason,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    auroraHolds.value--;
    _scroll.dispose();
    super.dispose();
  }

  void _pop() => Navigator.of(context).maybePop();
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      GlassButton(label: 'Back', icon: Icons.arrow_back_rounded, onTap: onTap);
}

class _Header extends StatelessWidget {
  const _Header({
    required this.item,
    required this.wide,
    required this.playLabel,
    required this.onPlay,
    this.onChoose,
    required this.resumeLabel,
    required this.onResume,
    required this.isFavourite,
    required this.onToggleFavourite,
    this.prebufferId,
    this.onPrebuffer,
  });

  final MetaItem item;
  final bool wide;
  final String playLabel;
  final VoidCallback? onPlay;

  /// "Choose source" (always opens the picker, even if pre-buffered).
  final VoidCallback? onChoose;
  final String? resumeLabel;
  final VoidCallback? onResume;
  final bool isFavourite;
  final VoidCallback onToggleFavourite;

  /// Movies only: where the pre-buffer state lives, and how to start one.
  final String? prebufferId;
  final VoidCallback? onPrebuffer;

  @override
  Widget build(BuildContext context) {
    final poster = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        width: wide ? 250 : 170,
        height: wide ? 375 : 255,
        child: NetImage(item.posterImage, cacheWidth: 600),
      ),
    );

    final facts = [
      if (item.releaseInfo != null) item.releaseInfo!,
      if (item.runtime != null) item.runtime!,
      item.isSeries ? 'Series' : 'Movie',
    ].join('  -  ');

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.logoImage != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 110, maxWidth: 420),
            child: Image.network(
              item.logoImage!,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              errorBuilder: (_, _, _) => _Name(item.name),
            ),
          )
        else
          _Name(item.name),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (item.rating != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.star_rounded,
                    size: 18,
                    color: Color(0xFFFFD54F),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    item.rating!.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            Text(facts, style: const TextStyle(color: Colors.white70)),
          ],
        ),
        if (item.genres.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in item.genres)
                GlassPanel(
                  borderRadius: 999,
                  blur: 10,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  child: Text(g, style: const TextStyle(fontSize: 12.5)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Text(
            item.description ?? '',
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            if (onResume != null) ...[
              GlassButton(
                label: resumeLabel!,
                icon: Icons.play_arrow_rounded,
                primary: true,
                autofocus: true,
                onTap: onResume!,
              ),
              GlassButton(
                label: 'Choose source',
                icon: Icons.list_rounded,
                onTap: onChoose ?? onPlay ?? () {},
              ),
            ] else
              GlassButton(
                label: playLabel,
                icon: Icons.play_arrow_rounded,
                primary: true,
                autofocus: true,
                onTap: onPlay ?? () {},
              ),
            GlassButton(
              label: isFavourite ? 'In My List' : 'My List',
              icon: isFavourite ? Icons.check_rounded : Icons.add_rounded,
              onTap: onToggleFavourite,
            ),
            if (prebufferId != null && onPrebuffer != null)
              _MoviePrebuffer(videoId: prebufferId!, onStart: onPrebuffer!),
          ],
        ),
        if (item.directors.isNotEmpty || item.cast.isNotEmpty) ...[
          const SizedBox(height: 24),
          if (item.directors.isNotEmpty)
            _Credit('Director', item.directors.join(', ')),
          if (item.cast.isNotEmpty)
            _Credit('Cast', item.cast.take(8).join(', ')),
        ],
      ],
    );

    return wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              poster,
              const SizedBox(width: 40),
              Expanded(child: info),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [poster, const SizedBox(height: 20), info],
          );
  }
}

class _Name extends StatelessWidget {
  const _Name(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => Text(
    name,
    style: const TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.w900,
      height: 1.05,
    ),
  );
}

class _Credit extends StatelessWidget {
  const _Credit(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 13.5, height: 1.4),
        children: [
          TextSpan(
            text: '$label   ',
            style: const TextStyle(color: Colors.white54),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    ),
  );
}

class _Episodes extends StatelessWidget {
  const _Episodes({
    required this.item,
    required this.season,
    required this.onSeason,
    required this.onPlay,
    required this.onPrebuffer,
    required this.onPrebufferSeason,
  });

  final MetaItem item;
  final int season;
  final ValueChanged<int> onSeason;
  final ValueChanged<Episode> onPlay;
  final ValueChanged<Episode> onPrebuffer;
  final ValueChanged<int> onPrebufferSeason;

  @override
  Widget build(BuildContext context) {
    final eps = item.episodesOf(season);
    final lib = context.watch<LibraryProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Episodes',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ),
            GlassButton(
              label: 'Pre-buffer season',
              icon: Icons.download_rounded,
              onTap: () => onPrebufferSeason(season),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final s in item.seasons)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _SeasonChip(
                    label: s == 0 ? 'Specials' : 'Season $s',
                    selected: s == season,
                    onTap: () => onSeason(s),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (final e in eps)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _EpisodeTile(
              episode: e,
              progress: lib.progressFor(e.id),
              watched: lib.isWatched(e.id),
              onTap: () => onPlay(e),
              onPrebuffer: () => onPrebuffer(e),
            ),
          ),
      ],
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.progress,
    required this.watched,
    required this.onTap,
    required this.onPrebuffer,
  });

  final Episode episode;
  final WatchProgress? progress;

  /// Watched here or on Trakt.
  final bool watched;
  final VoidCallback onTap;
  final VoidCallback onPrebuffer;

  @override
  Widget build(BuildContext context) {
    final e = episode;
    final p = progress;
    return GlassCard(
      height: 104,
      onTap: onTap,
      child: Stack(
        children: [
          Row(
            children: [
              SizedBox(
                width: 184,
                height: 104,
                child: NetImage(e.thumbnail, cacheWidth: 400),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${e.number}.  ${e.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(
                          e.overview ?? '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.white60,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              PrebufferButton(videoId: e.id, onStart: onPrebuffer),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Icon(
                  watched
                      ? Icons.check_circle_rounded
                      : Icons.play_circle_outline_rounded,
                  size: 30,
                ),
              ),
            ],
          ),
          if (p != null && !p.finished && p.fraction > 0.01)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                value: p.fraction,
                minHeight: 3,
                color: const Color(0xFF00E5FF),
                backgroundColor: Colors.transparent,
              ),
            ),
        ],
      ),
    );
  }
}

class _SeasonChip extends StatelessWidget {
  const _SeasonChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      GlassButton(label: label, primary: selected, onTap: onTap);
}

/// "Pre-buffer" button for a movie: shows progress / ready like the episode ones.
class _MoviePrebuffer extends StatelessWidget {
  const _MoviePrebuffer({required this.videoId, required this.onStart});

  final String videoId;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final pb = context.watch<PrebufferProvider>();
    final entry = pb.entryFor(videoId);
    final job = pb.jobFor(videoId);
    if (entry == null) {
      return GlassButton(
        label: 'Pre-buffer',
        icon: Icons.download_rounded,
        onTap: onStart,
      );
    }
    final label = (job?.isReady ?? false)
        ? 'Ready  (remove)'
        : (job?.isError ?? false)
        ? 'Failed  (retry)'
        : 'Pre-buffering ${((job?.progress ?? 0) * 100).round()}%  (cancel)';
    return GlassButton(
      label: label,
      icon: (job?.isReady ?? false)
          ? Icons.download_done_rounded
          : Icons.downloading_rounded,
      onTap: () async {
        final failed = job?.isError ?? false;
        await pb.remove(videoId);
        if (failed) onStart();
      },
    );
  }
}
