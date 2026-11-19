import 'package:material_ui/material_ui.dart';

/// Pill button. [primary] = solid white (main action); otherwise frosted.
class GlassButton extends StatefulWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = false,
    this.autofocus = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool primary;
  final bool autofocus;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final lit = _hover || _focus;
    final fg = widget.primary ? const Color(0xFF05070F) : Colors.white;

    return FocusableActionDetector(
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: lit ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 160),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: widget.primary
                  ? Colors.white.withValues(alpha: lit ? 1.0 : 0.9)
                  : Colors.white.withValues(alpha: lit ? 0.22 : 0.12),
              border: Border.all(
                color: Colors.white.withValues(alpha: _focus ? 0.7 : 0.18),
              ),
              boxShadow: lit
                  ? [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.35),
                        blurRadius: 22,
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 20, color: fg),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
