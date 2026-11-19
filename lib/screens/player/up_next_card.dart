import 'package:material_ui/material_ui.dart';

import '../../models/meta_item.dart';
import '../../widgets/glass_button.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/net_image.dart';

/// "Up next" card shown in the player near the end of an episode.
class UpNextCard extends StatelessWidget {
  const UpNextCard({
    super.key,
    required this.episode,
    required this.seriesName,
    required this.sourceReady,
    required this.onPlay,
    required this.onCancel,
    this.countdown,
  });

  final Episode episode;
  final String seriesName;

  /// A matching source has been found (starts instantly) vs. still looking or
  /// not found (the picker will open).
  final bool sourceReady;

  /// Seconds until it starts by itself; null when autoplay is off.
  final int? countdown;
  final VoidCallback onPlay;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final status = countdown != null
        ? 'Playing in $countdown s'
        : (sourceReady ? 'Ready to play' : 'Pick a source');

    return SizedBox(
      width: 380,
      child: GlassPanel(
        borderRadius: 20,
        blur: 26,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 124,
                    height: 70,
                    child: NetImage(episode.thumbnail, cacheWidth: 300),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'UP NEXT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: Color(0xFF00E5FF),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'S${episode.season} E${episode.number}  -  ${episode.title}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        status,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: sourceReady || countdown != null
                        ? 'Play now'
                        : 'Choose source',
                    icon: Icons.play_arrow_rounded,
                    primary: true,
                    onTap: onPlay,
                  ),
                ),
                const SizedBox(width: 10),
                GlassButton(label: 'Cancel', onTap: onCancel),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
