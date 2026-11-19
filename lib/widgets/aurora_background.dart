import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_shaders/flutter_shaders.dart';

import '../core/glass.dart';

/// Global brightness of the aurora; the intro pulses it with the logo.
final ValueNotifier<double> auroraIntensity = ValueNotifier(0.55);

/// Screens that completely cover the aurora (video player, details page)
/// register here while they are open so it stops animating underneath them.
/// Count-based, so overlapping screens work.
final ValueNotifier<int> auroraHolds = ValueNotifier(0);

/// Full-area GPU aurora, with controls so it never wastes the GPU:
/// - quality: full / 30 fps / still (a setting)
/// - paused while something opaque covers it, or the app is hidden
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, required this.child});

  final Widget child;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);

  /// Animation time accumulated across pauses, so resuming never jumps.
  double _base = 0;
  Duration _lastEmit = Duration.zero;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick);
    auroraQuality.addListener(_sync);
    auroraHolds.addListener(_sync);
    _sync();
  }

  void _onTick(Duration elapsed) {
    // 30 fps mode: skip every other frame's repaint.
    if (auroraQuality.value == AuroraQuality.smooth &&
        elapsed - _lastEmit < const Duration(milliseconds: 30)) {
      return;
    }
    _lastEmit = elapsed;
    _time.value = _base + elapsed.inMicroseconds / 1e6;
  }

  bool get _shouldAnimate =>
      _visible &&
      auroraHolds.value == 0 &&
      auroraQuality.value != AuroraQuality.off;

  void _sync() {
    if (_shouldAnimate) {
      if (!_ticker.isActive) {
        _lastEmit = Duration.zero;
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
      _base = _time.value;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    auroraQuality.removeListener(_sync);
    auroraHolds.removeListener(_sync);
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF05070F)),
        RepaintBoundary(
          child: ShaderBuilder(
            assetKey: 'shaders/aurora.frag',
            (context, shader, _) => ValueListenableBuilder<double>(
              valueListenable: _time,
              builder: (context, t, _) => ValueListenableBuilder<double>(
                valueListenable: auroraIntensity,
                builder: (context, k, _) => CustomPaint(
                  painter: _AuroraPainter(shader, t, k),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.shader, this.time, this.intensity);

  final dynamic shader; // FragmentShader
  final double time;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(3, intensity);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.time != time || old.intensity != intensity;
}
