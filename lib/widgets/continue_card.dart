import 'package:flutter/material.dart';

import '../models/watch_progress.dart';
import 'glass_card.dart';
import 'net_image.dart';

/// Landscape "resume" card: backdrop, title, episode, progress bar, and a
/// small remove button.
class ContinueCard extends StatelessWidget {
  const ContinueCard({
    super.key,
    required this.progress,
    required this.onTap,
    required this.onRemove,
  });

  final WatchProgress progress;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  static const double width = 300;
  static const double height = 169;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final left = p.duration - p.position;
    final leftLabel = left.inMinutes >= 60
        ? '${left.inHours}h ${left.inMinutes.remainder(60)}m left'
        : '${left.inMinutes.clamp(1, 59)}m left';

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
                  p.meta.heroImage ?? p.meta.posterImage,
                  alignment: Alignment.topCenter,
                  cacheWidth: 700,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xD9000000)],
                      stops: [0.45, 1],
                    ),
                  ),
                ),
                const Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    size: 46,
                    color: Colors.white70,
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Tooltip(
                    message: 'Remove from Continue Watching',
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
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: p.fraction,
                    minHeight: 4,
                    color: const Color(0xFF00E5FF),
                    backgroundColor: Colors.white24,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            p.meta.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          Text(
            [
              if (p.episodeLabel != null) p.episodeLabel!,
              leftLabel,
            ].join('  -  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}
