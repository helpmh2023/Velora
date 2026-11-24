import 'package:material_ui/material_ui.dart';

import '../models/prebuffer_entry.dart';
import '../services/engine_service.dart';
import 'continue_card.dart';
import 'glass_card.dart';
import 'net_image.dart';

/// Landscape card in Continue Watching for something that is pre-buffered but
/// not started: tap to play the downloaded copy straight away.
class PrebufferedCard extends StatelessWidget {
  const PrebufferedCard({
    super.key,
    required this.entry,
    required this.job,
    required this.onTap,
    required this.onRemove,
  });

  final PrebufferEntry entry;
  final PrebufferJob? job;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  static const double width = ContinueCard.width;
  static const double height = ContinueCard.height;

  @override
  Widget build(BuildContext context) {
    final ready = job?.isReady ?? false;
    final p = job?.progress;
    final color = ready ? const Color(0xFF69F0AE) : const Color(0xFF00E5FF);
    final badge = ready
        ? 'READY'
        : 'DOWNLOADING${p == null ? '' : ' ${(p * 100).round()}%'}';
    final title = entry.meta.name;
    final sub = entry.season == null
        ? (entry.partial ? 'Start is ready' : 'Pre-buffered')
        : 'S${entry.season} E${entry.episode}'
              '${entry.episodeTitle == null || entry.episodeTitle!.isEmpty ? '' : '  -  ${entry.episodeTitle}'}';

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassCard(
            width: width,
            height: height,
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                NetImage(
                  entry.meta.heroImage ?? entry.meta.posterImage,
                  alignment: Alignment.topCenter,
                  cacheWidth: 700,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xD9000000)],
                      stops: [0.4, 1],
                    ),
                  ),
                ),
                const Center(
                  child: Icon(
                    Icons.play_circle_outline_rounded,
                    size: 50,
                    color: Colors.white70,
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: color.withValues(alpha: 0.22),
                      border: Border.all(color: color.withValues(alpha: 0.7)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          ready
                              ? Icons.download_done_rounded
                              : Icons.downloading_rounded,
                          size: 13,
                          color: color,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          badge,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Tooltip(
                    message: 'Remove the pre-buffered copy',
                    child: GestureDetector(
                      onTap: onRemove,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                          child: const Icon(Icons.close_rounded, size: 16),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!ready && p != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: p,
                      minHeight: 3,
                      color: color,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}
