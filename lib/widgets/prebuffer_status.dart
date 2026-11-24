import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/prebuffer_entry.dart';
import '../providers/library_provider.dart';
import '../providers/prebuffer_provider.dart';
import '../screens/player/open_player.dart';
import '../services/engine_service.dart';
import '../services/share_server.dart';
import 'glass_button.dart';
import 'share_dialog.dart';

String _size(num bytes) => bytes >= 1 << 30
    ? '${(bytes / (1 << 30)).toStringAsFixed(2)} GB'
    : '${(bytes / (1 << 20)).toStringAsFixed(0)} MB';

String _eta(double secs) {
  if (secs.isNaN || secs.isInfinite || secs < 0) return '';
  final m = (secs / 60).floor();
  if (m >= 60) return '${m ~/ 60} h ${m % 60} min left';
  if (m >= 1) return '$m min left';
  return '${secs.round()} s left';
}

/// Button that opens the pre-buffer status panel. Shows how many are still
/// downloading.
class PrebufferStatusButton extends StatelessWidget {
  const PrebufferStatusButton({super.key, this.preferType});

  /// 'movie' or 'series': that kind is listed first in the panel.
  final String? preferType;

  @override
  Widget build(BuildContext context) {
    PrebufferProvider pb;
    try {
      pb = context.watch<PrebufferProvider>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink(); // screens shown without downloads support
    }
    final total = pb.entries.length;
    final active = pb.activeCount;
    final label = total == 0
        ? 'Pre-buffer status'
        : active > 0
        ? 'Pre-buffer status  ($active downloading)'
        : 'Pre-buffer status  ($total ready)';
    return GlassButton(
      label: label,
      icon: active > 0
          ? Icons.downloading_rounded
          : Icons.download_done_rounded,
      onTap: () => showPrebufferStatus(context, preferType: preferType),
    );
  }
}

Future<void> showPrebufferStatus(BuildContext context, {String? preferType}) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => _StatusPanel(preferType: preferType),
      transitionBuilder: (_, a, _, child) => SlideTransition(
        position: Tween(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );

/// A solid panel that slides in from the right edge, full height.
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({this.preferType});

  final String? preferType;

  @override
  Widget build(BuildContext context) {
    final pb = context.watch<PrebufferProvider>();
    // Same list everywhere; the kind of tab you opened it from comes first.
    final items = [...pb.entries]
      ..sort((a, b) {
        final pa = a.meta.type == preferType ? 0 : 1;
        final pb2 = b.meta.type == preferType ? 0 : 1;
        return pa != pb2 ? pa - pb2 : a.label.compareTo(b.label);
      });
    final width = MediaQuery.sizeOf(context).width;
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: const Color(0xFF0A0F1E),
        child: Container(
          width: width < 560 ? width : 500,
          height: double.infinity,
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: Color(0x33FFFFFF))),
          ),
          padding: const EdgeInsets.fromLTRB(22, 22, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Pre-buffer status',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const _StorageLine(),
              const SizedBox(height: 12),
              if (items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlassButton(
                    label: 'Open the list on iPad',
                    icon: Icons.tablet_mac_rounded,
                    onTap: () => showShareDialog(context),
                  ),
                ),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Text(
                          'Nothing is being pre-buffered.\n\n'
                          'Use the download button next to an episode, or '
                          '"Pre-buffer season" on a show\'s page.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, height: 1.5),
                        ),
                      )
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _Item(entry: items[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "3.2 GB on disk . cache limit 8 GB . 120 GB free"
class _StorageLine extends StatefulWidget {
  const _StorageLine();

  @override
  State<_StorageLine> createState() => _StorageLineState();
}

class _StorageLineState extends State<_StorageLine> {
  DiskInfo? _disk;

  @override
  void initState() {
    super.initState();
    context.read<EngineService>().disk().then((d) {
      if (mounted) setState(() => _disk = d);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _disk;
    final text = d == null
        ? 'Reading disk usage...'
        : '${_size(d.cacheBytes)} in the cache (limit ${_size(d.maxCache)})'
              '${d.free >= 0 ? '  -  ${_size(d.free)} free on the disk' : ''}';
    return Text(
      text,
      style: const TextStyle(color: Colors.white54, fontSize: 12.5),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.entry});

  final PrebufferEntry entry;

  @override
  Widget build(BuildContext context) {
    final pb = context.watch<PrebufferProvider>();
    final job = pb.jobFor(entry.videoId);
    final ready = job?.isReady ?? false;
    final failed = job?.isError ?? false;
    final p = job?.progress;
    final speed = pb.speedFor(entry.videoId);
    final src = entry.source;

    final status = failed
        ? 'Failed: ${job!.error}'
        : ready
        ? (entry.partial
              ? 'Ready: the start of the episode is on disk'
              : 'Ready: plays instantly')
        : job == null || job.state == 'metadata'
        ? 'Finding the torrent and peers...'
        : [
            'Downloading ${p == null ? '' : '${(p * 100).round()}%'}',
            '${_size(job.done)} of ${_size(job.total)}',
            if (speed > 0) '${_size(speed)}/s',
            if (speed > 0 && job.total > job.done)
              _eta((job.total - job.done) / speed),
          ].where((e) => e.isNotEmpty).join('  -  ');

    final color = failed
        ? const Color(0xFFFFB74D)
        : ready
        ? const Color(0xFF69F0AE)
        : const Color(0xFF00E5FF);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                failed
                    ? Icons.error_outline_rounded
                    : ready
                    ? Icons.download_done_rounded
                    : Icons.downloading_rounded,
                color: color,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!failed)
                Tooltip(
                  message: 'Play now',
                  child: IconButton(
                    icon: const Icon(Icons.play_arrow_rounded),
                    onPressed: () {
                      final lib = context.read<LibraryProvider>();
                      final saved = lib.progressFor(entry.videoId);
                      Navigator.of(context).pop();
                      openPlayer(
                        context,
                        source: entry.source,
                        meta: entry.meta,
                        videoId: entry.videoId,
                        subtitle: entry.label,
                        season: entry.season,
                        episode: entry.episode,
                        episodeTitle: entry.episodeTitle,
                        resumeFrom: saved?.finished == true
                            ? null
                            : saved?.position,
                        knownDuration: saved?.duration,
                      );
                    },
                  ),
                ),
              if (!failed)
                Tooltip(
                  message: 'Play on iPad',
                  child: IconButton(
                    icon: const Icon(Icons.tablet_mac_rounded),
                    onPressed: () => showShareDialog(
                      context,
                      item: ShareServer.itemFor(entry),
                    ),
                  ),
                ),
              Tooltip(
                message: ready ? 'Remove from disk' : 'Cancel',
                child: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => pb.remove(entry.videoId),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Source: ${src.quality.label}  -  ${src.provider}  -  '
            '${src.seeders} seeders  -  ${src.sizeLabel}'
            '${entry.partial ? '  -  start only' : ''}',
            style: const TextStyle(fontSize: 12.5, color: Colors.white70),
          ),
          Text(
            src.release,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
          const SizedBox(height: 8),
          Text(status, style: TextStyle(fontSize: 13, color: color)),
          if (!ready && !failed && p != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: p,
              minHeight: 4,
              color: color,
              backgroundColor: Colors.white12,
            ),
          ],
        ],
      ),
    );
  }
}
