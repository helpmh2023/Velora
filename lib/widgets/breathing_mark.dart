import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// The Velora "V" mark. It breathes: gently scales and radiates a soft glow
/// of its own colours. Pass [breath] (0..1) to sync it with something else
/// (the aurora); otherwise it runs its own loop.
class BreathingVeloraMark extends StatefulWidget {
  const BreathingVeloraMark({super.key, this.size = 200, this.breath});

  final double size;
  final Animation<double>? breath;

  static const asset = 'assets/icon/velora_logo.png';

  @override
  State<BreathingVeloraMark> createState() => _BreathingVeloraMarkState();
}

class _BreathingVeloraMarkState extends State<BreathingVeloraMark>
    with SingleTickerProviderStateMixin {
  AnimationController? _own;
  late final Animation<double> _breath;

  @override
  void initState() {
    super.initState();
    if (widget.breath != null) {
      _breath = widget.breath!;
    } else {
      _own = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2500),
      )..repeat(reverse: true);
      _breath = CurvedAnimation(parent: _own!, curve: Curves.easeInOut);
    }
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: _breath,
      builder: (context, _) {
        final b = _breath.value;
        final image = Image.asset(
          BreathingVeloraMark.asset,
          width: s,
          height: s,
          filterQuality: FilterQuality.high,
        );
        return SizedBox(
          width: s * 1.8,
          height: s * 1.8,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Outer halo: the mark's own colours, blurred wide.
                Opacity(
                  opacity: 0.25 + 0.6 * b,
                  child: Transform.scale(
                    scale: 1.08 + 0.18 * b,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(
                        sigmaX: s * 0.10 + s * 0.12 * b,
                        sigmaY: s * 0.10 + s * 0.12 * b,
                        tileMode: TileMode.decal,
                      ),
                      child: image,
                    ),
                  ),
                ),
                // The crisp mark.
                Transform.scale(scale: 1.0 + 0.05 * b, child: image),
              ],
            ),
          ),
        );
      },
    );
  }
}
