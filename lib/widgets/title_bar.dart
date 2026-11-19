import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

/// Custom caption bar for the frameless desktop window.
/// Dragging the empty area moves the window; double-click toggles maximize.
class VeloraTitleBar extends StatefulWidget {
  const VeloraTitleBar({super.key, this.leading, this.center});

  final Widget? leading;

  /// Optional widget centred in the bar (e.g. the nav pill).
  final Widget? center;

  static const double height = 56;

  @override
  State<VeloraTitleBar> createState() => _VeloraTitleBarState();
}

class _VeloraTitleBarState extends State<VeloraTitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: VeloraTitleBar.height,
      child: Stack(
        children: [
          // Drag / double-click area fills the whole bar, behind everything.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: _toggleMaximize,
            ),
          ),
          if (widget.leading != null)
            Positioned(
              left: 20,
              top: 0,
              bottom: 0,
              child: Center(child: widget.leading),
            ),
          if (widget.center != null) Center(child: widget.center),
          Positioned(
            right: 0,
            top: 0,
            child: Row(
              children: [
                _CaptionButton(
                  icon: Icons.remove_rounded,
                  onTap: windowManager.minimize,
                ),
                _CaptionButton(
                  icon: _maximized
                      ? Icons.filter_none_rounded
                      : Icons.crop_square_rounded,
                  iconSize: _maximized ? 14 : 17,
                  onTap: _toggleMaximize,
                ),
                _CaptionButton(
                  icon: Icons.close_rounded,
                  hoverColor: const Color(0xFFE81123),
                  onTap: windowManager.close,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.onTap,
    this.hoverColor,
    this.iconSize = 17,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? hoverColor;
  final double iconSize;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 46,
          height: 40,
          color: _hover
              ? (widget.hoverColor ?? Colors.white.withValues(alpha: 0.12))
              : Colors.transparent,
          child: Icon(widget.icon, size: widget.iconSize, color: Colors.white),
        ),
      ),
    );
  }
}
