import 'package:material_ui/material_ui.dart';

import '../core/platform.dart';

/// Apple-TV-style focusable card. Dimmed and flat at rest; on mouse hover,
/// keyboard focus, or touch it scales to 1.05x and gains a soft glow.
///
/// Deliberately does NOT blur (a row can hold dozens of cards); the frosted
/// look comes from GlassPanel behind/around them.
class GlassCard extends StatefulWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.width,
    this.height,
    this.borderRadius = 18,
    this.scale = 1.05,
    this.autofocus = false,
    this.focusNode,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final double borderRadius;

  /// Size when hovered/focused. Wide cards should use a smaller value.
  final double scale;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _hover = false;
  bool _focus = false;
  bool _pressed = false;

  bool get _active => _hover || _focus || _pressed;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);
    final active = _active;
    // Desktop cards sit noticeably dimmed; on touch there is no hover, so keep
    // them brighter and let the press state do the work.
    final restDim = isDesktop ? 0.35 : 0.12;

    return FocusableActionDetector(
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      mouseCursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: active ? widget.scale : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: radius,
              // Opaque base: a translucent fill would let the glow show through
              // as a coloured wash inside the card.
              color: Color.alphaBlend(
                Colors.white.withValues(alpha: active ? 0.12 : 0.06),
                const Color(0xFF0B0F1A),
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: active ? 0.55 : 0.10),
                width: 1,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.35),
                        blurRadius: 28,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  widget.child,
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        color: Colors.black.withValues(
                          alpha: active ? 0.0 : restDim,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
