import 'package:material_ui/material_ui.dart';

import '../models/next_up.dart';
import 'continue_card.dart';
import 'glass_card.dart';
import 'net_image.dart';

/// Landscape card for "you finished an episode, this is next". Same size as
/// the Continue Watching card so they share a row.
class NextUpCard extends StatelessWidget {
  const NextUpCard({
    super.key,
    required this.nextUp,
    required this.onTap,
    required this.onRemove,
  });

  final NextUp nextUp;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  static const double width = ContinueCard.width;
  static const double height = ContinueCard.height;

  @override
  Widget build(BuildContext context) {
    final n = nextUp;
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
                // The episode's own still if there is one, else the show backdrop.
                NetImage(
                  n.episode.thumbnail ?? n.meta.heroImage ?? n.meta.posterImage,
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
                    Icons.skip_next_rounded,
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
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.22),
                      border: Border.all(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.7),
                      ),
                    ),
                    child: const Text(
                      'UP NEXT',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: Color(0xFF00E5FF),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Tooltip(
                    message: 'Dismiss',
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
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            n.meta.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          Text(
            n.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}
