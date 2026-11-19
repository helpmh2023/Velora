import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../core/glass.dart';

/// Frosted-glass surface: blurs whatever is behind it (the aurora), adds a
/// faint white gradient tint and a hairline border.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.blur = 24,
    this.padding,
    this.opacity = 1.0,
  });

  final Widget child;
  final double borderRadius;
  final double blur;
  final EdgeInsetsGeometry? padding;

  /// Scales the tint strength (0 = invisible glass, 1 = default).
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    final surface = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.12 * opacity),
            Colors.white.withValues(alpha: 0.04 * opacity),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14 * opacity),
          width: 1,
        ),
      ),
      child: child,
    );

    return ValueListenableBuilder<bool>(
      valueListenable: reduceGlass,
      builder: (context, reduced, _) {
        if (reduced) return ClipRRect(borderRadius: radius, child: surface);
        return ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: surface,
          ),
        );
      },
    );
  }
}
