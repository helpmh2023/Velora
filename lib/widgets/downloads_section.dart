import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/prebuffer_entry.dart';
import '../providers/library_provider.dart';
import '../providers/prebuffer_provider.dart';
import '../screens/player/open_player.dart';
import '../services/share_server.dart';
import 'glass_button.dart';
import 'glass_card.dart';
import 'share_dialog.dart';

String _gb(num bytes) => bytes >= 1 << 30
    ? '${(bytes / (1 << 30)).toStringAsFixed(1)} GB'
    : '${(bytes / (1 << 20)).toStringAsFixed(0)} MB';

/// "Pre-buffered" list in the Library: what is downloaded or downloading, with
/// progress, play and remove.
class DownloadsSection extends StatelessWidget {
  const DownloadsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final pb = context.watch<PrebufferProvider>();
    final items = pb.entries;
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 12, 40, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Pre-buffered',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${_gb(pb.downloadedBytes)} on disk',
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(width: 14),
              GlassButton(
                label: 'Open on iPad',
                icon: Icons.tablet_mac_rounded,
                onTap: () => showShareDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final e in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _Row(entry: e),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry});

  final PrebufferEntry entry;

  @override
  Widget build(BuildContext context) {
    final pb = context.watch<PrebufferProvider>();
    final job = pb.jobFor(entry.videoId);
    final ready = job?.isReady ?? false;
    final failed = job?.isError ?? false;
    final p = job?.progress;

    final status = failed
        ? job!.error
        : ready
        ? (entry.partial ? 'Start of the episode is ready' : 'Ready')
        : p == null
        ? 'Finding peers...'
        : 'Downloading ${(p * 100).round()}%  (${_gb(job!.done)} of ${_gb(job.total)})';

    return GlassCard(
      height: 76,
      onTap: failed ? () {} : () => _play(context, entry),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: [
            Icon(
              failed
                  ? Icons.error_outline_rounded
                  : ready
                  ? Icons.download_done_rounded
                  : Icons.downloading_rounded,
              color: failed
                  ? const Color(0xFFFFB74D)
                  : ready
                  ? const Color(0xFF69F0AE)
                  : const Color(0xFF00E5FF),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.white60,
                    ),
                  ),
                  if (!ready && !failed && p != null) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: p,
                      minHeight: 3,
                      color: const Color(0xFF00E5FF),
                      backgroundColor: Colors.white12,
                    ),
                  ],
                ],
              ),
            ),
            Tooltip(
              message: 'Play here',
              child: IconButton(
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: failed ? null : () => _play(context, entry),
              ),
            ),
            Tooltip(
              message: 'Play on iPad (stream from this PC)',
              child: IconButton(
                icon: const Icon(Icons.tablet_mac_rounded),
                onPressed: failed
                    ? null
                    : () => showShareDialog(
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
      ),
    );
  }
}

void _play(BuildContext context, PrebufferEntry entry) {
  final saved = context.read<LibraryProvider>().progressFor(entry.videoId);
  openPlayer(
    context,
    source: entry.source,
    meta: entry.meta,
    videoId: entry.videoId,
    subtitle: entry.label,
    season: entry.season,
    episode: entry.episode,
    episodeTitle: entry.episodeTitle,
    resumeFrom: saved?.finished == true ? null : saved?.position,
    knownDuration: saved?.duration,
  );
}
