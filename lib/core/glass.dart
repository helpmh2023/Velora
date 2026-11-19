import 'package:flutter/foundation.dart';

/// "Reduce glass" setting: turns off BackdropFilter blur (for weak GPUs).
final ValueNotifier<bool> reduceGlass = ValueNotifier(false);

/// How hard the animated aurora background works.
enum AuroraQuality {
  /// Redrawn every frame (60+ fps).
  full('Full'),

  /// Redrawn at ~30 fps: the motion is slow, so it looks the same at half
  /// the GPU cost.
  smooth('Smooth (30 fps)'),

  /// A still frame; no per-frame cost at all.
  off('Off (still)');

  const AuroraQuality(this.label);
  final String label;
}

final ValueNotifier<AuroraQuality> auroraQuality = ValueNotifier(
  AuroraQuality.full,
);
