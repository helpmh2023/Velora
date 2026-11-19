import 'package:material_ui/material_ui.dart';

class BreathingVeloraLogo extends StatefulWidget {
  final double fontSize;

  /// Optional external breath (0..1). When given, the logo follows it instead
  /// of running its own loop, so it can be synced with the aurora.
  final Animation<double>? breath;

  const BreathingVeloraLogo({super.key, this.fontSize = 24, this.breath});

  @override
  State<BreathingVeloraLogo> createState() => _BreathingVeloraLogoState();
}

class _BreathingVeloraLogoState extends State<BreathingVeloraLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.breath == null) _controller.repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 4.0, end: 22.0).animate(
      widget.breath ??
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Text(
          'VELORA',
          style: TextStyle(
            fontFamily: 'SF Pro Display',
            fontFamilyFallback: const ['Inter', 'Segoe UI'],
            fontWeight: FontWeight.w900,
            fontSize: widget.fontSize,
            letterSpacing: 2.5,
            color: Colors.white,
            decoration: TextDecoration.none,
            shadows: [
              Shadow(
                blurRadius: _glowAnimation.value,
                color: const Color(0xFF00E5FF).withValues(alpha: 0.55),
              ),
              Shadow(
                blurRadius: _glowAnimation.value * 1.6,
                color: Colors.white.withValues(alpha: 0.25),
              ),
            ],
          ),
        );
      },
    );
  }
}
