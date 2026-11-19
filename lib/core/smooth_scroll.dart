import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Mouse wheel scrolling that glides instead of jumping.
///
/// Each wheel notch moves a *target*; every frame the position eases toward
/// it (exponential smoothing, frame-rate independent). Rapid notches stack
/// into one long smooth glide. Dragging, keyboard focus scrolling and
/// programmatic animateTo keep working and cancel any pending glide.
class SmoothScrollController extends ScrollController {
  SmoothScrollController({
    super.initialScrollOffset,
    this.speed = 1.0,
    this.stiffness = 22,
  });

  /// Multiplier on the wheel delta (Windows sends ~100px per notch).
  final double speed;

  /// Higher = snappier. ~22 settles in about a tenth of a second.
  final double stiffness;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SmoothPosition(
    physics: physics,
    context: context,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
    speed: speed,
    stiffness: stiffness,
  );
}

class _SmoothPosition extends ScrollPositionWithSingleContext {
  _SmoothPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
    required this.speed,
    required this.stiffness,
  });

  final double speed;
  final double stiffness;

  Ticker? _ticker;
  double? _target;
  double _lastSet = 0;
  Duration _last = Duration.zero;

  @override
  void pointerScroll(double delta) {
    if (delta == 0) return;
    // If something else moved us (drag, focus, animateTo), restart from here.
    if (_target == null || (pixels - _lastSet).abs() > 1) _target = pixels;
    _target = (_target! + delta * speed).clamp(
      minScrollExtent,
      maxScrollExtent,
    );
    _lastSet = pixels;
    _last = Duration.zero;
    _ticker ??= context.vsync.createTicker(_tick);
    if (!_ticker!.isActive) _ticker!.start();
  }

  void _tick(Duration elapsed) {
    final target = _target;
    if (target == null) {
      _ticker?.stop();
      return;
    }
    // Something else took over (user dragged, focus scrolled): stand down.
    if ((pixels - _lastSet).abs() > 1) {
      _stop();
      return;
    }
    final dt = _last == Duration.zero
        ? 1 / 60
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;

    final remaining = target - pixels;
    if (remaining.abs() < 0.4) {
      jumpTo(target);
      _stop();
      return;
    }
    final next = pixels + remaining * (1 - math.exp(-stiffness * dt));
    jumpTo(next);
    _lastSet = pixels;
  }

  void _stop() {
    _target = null;
    _ticker?.stop();
  }

  @override
  void beginActivity(ScrollActivity? newActivity) {
    // jumpTo() goes idle every frame; only a real user/animation activity
    // should cancel the glide.
    if (newActivity is DragScrollActivity ||
        newActivity is BallisticScrollActivity ||
        newActivity is DrivenScrollActivity) {
      _target = null;
    }
    super.beginActivity(newActivity);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}

/// Lets the mouse (and trackpad) drag-scroll like touch, app-wide.
class VeloraScrollBehavior extends MaterialScrollBehavior {
  const VeloraScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  // No overscroll glow / no scrollbar chrome over the glass UI.
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
