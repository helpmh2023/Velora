import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../providers/prebuffer_provider.dart';

/// Small round control for one episode/movie showing its pre-buffer state:
/// download icon (tap to start), a progress ring (tap to cancel), a green tick
/// when ready (tap to remove), or a warning with the reason (tap to retry).
class PrebufferButton extends StatelessWidget {
  const PrebufferButton({
    super.key,
    required this.videoId,
    required this.onStart,
  });

  final String videoId;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final pb = context.watch<PrebufferProvider>();
    final entry = pb.entryFor(videoId);
    final job = pb.jobFor(videoId);

    String tip;
    Widget icon;
    VoidCallback tap;
    if (entry == null) {
      tip = 'Pre-buffer: download now, watch with no wait';
      icon = const Icon(Icons.download_rounded, size: 24);
      tap = onStart;
    } else if (job?.isError ?? false) {
      tip = '${job!.error}\n(tap to try again)';
      icon = const Icon(
        Icons.error_outline_rounded,
        size: 24,
        color: Color(0xFFFFB74D),
      );
      tap = () {
        pb.remove(videoId);
        onStart();
      };
    } else if (job?.isReady ?? false) {
      tip = entry.partial
          ? 'Start of the episode is ready (tap to remove)'
          : 'Ready: plays instantly (tap to remove)';
      icon = const Icon(
        Icons.download_done_rounded,
        size: 24,
        color: Color(0xFF69F0AE),
      );
      tap = () => pb.remove(videoId);
    } else {
      final p = job?.progress;
      tip =
          'Pre-buffering ${p == null ? '' : '${(p * 100).round()}%'} (tap to cancel)';
      icon = SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.6,
          value: (p == null || p <= 0) ? null : p,
          color: const Color(0xFF00E5FF),
        ),
      );
      tap = () => pb.remove(videoId);
    }

    return Tooltip(
      message: tip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(width: 28, height: 28, child: Center(child: icon)),
          ),
        ),
      ),
    );
  }
}
