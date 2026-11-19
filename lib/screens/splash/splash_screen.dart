import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../../providers/home_provider.dart';
import '../../widgets/aurora_background.dart';
import '../../widgets/breathing_mark.dart';
import '../shell/shell_screen.dart';

/// 5-second intro: the logo fades in, breathes twice in sync with the aurora
/// (which swells and relaxes with it), then fades away into the home screen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const duration = Duration(seconds: 5);
  static const ambientIntensity = 0.55; // aurora brightness on the home page

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _breath;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: SplashScreen.duration);

    // Two full breaths over the 5 seconds (0 -> 1 -> 0, twice).
    _breath = _c.drive(CurveTween(curve: const _TwoBreaths()));

    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 14,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 70),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 16,
      ),
    ]).animate(_c);

    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.9,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 20,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 64),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.06,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 16,
      ),
    ]).animate(_c);

    // Aurora swells with each breath, and ends where the home page begins.
    _breath.addListener(_pulseAurora);
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _goHome();
    });
    _c.forward();
  }

  void _pulseAurora() {
    auroraIntensity.value =
        SplashScreen.ambientIntensity + 0.35 * _breath.value * _opacity.value;
  }

  Future<void> _goHome() async {
    // Intro is 5s; if Cinemeta is still loading, give it a few more seconds
    // (never hangs: ready completes on failure too).
    await context.read<HomeProvider>().ready.timeout(
      const Duration(seconds: 4),
      onTimeout: () {},
    );
    if (!mounted) return;
    auroraIntensity.value = SplashScreen.ambientIntensity;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (_, _, _) => const ShellScreen(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _breath.removeListener(_pulseAurora);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: ScaleTransition(
            scale: _scale,
            child: BreathingVeloraMark(size: 220, breath: _breath),
          ),
        ),
      ),
    );
  }
}

/// 0 -> 1 -> 0 -> 1 -> 0 over t in [0,1], smooth (cosine).
class _TwoBreaths extends Curve {
  const _TwoBreaths();

  @override
  double transformInternal(double t) => 0.5 - 0.5 * math.cos(4 * math.pi * t);
}
