import 'package:material_ui/material_ui.dart';

/// Network image that fades in when it arrives and degrades to a flat tile on
/// failure. [cacheWidth] keeps decoded bitmaps small for rows of posters.
class NetImage extends StatelessWidget {
  const NetImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.cacheWidth,
  });

  final String? url;
  final BoxFit fit;
  final Alignment alignment;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    if (url == null) return const _Fallback();
    return Image.network(
      url!,
      fit: fit,
      alignment: alignment,
      cacheWidth: cacheWidth,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
        opacity: (frame != null || sync) ? 1 : 0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        child: child,
      ),
      errorBuilder: (_, _, _) => const _Fallback(),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white.withValues(alpha: 0.05),
    child: const Center(
      child: Icon(Icons.movie_outlined, color: Colors.white24, size: 32),
    ),
  );
}
