import 'dart:async';
import 'dart:ui';

import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// Moves the window onto one display and lets the (animated) home screen run
/// there, so frame pacing can be compared between monitors/GPUs.
/// Used by `VELORA_BENCH=pacing0`, `pacing1`, ...
Future<Map<String, Object?>> pacingProbe(
  int displayIndex,
  Duration Function() now,
  Future<void> Function(String, Future<void> Function()) phase,
) async {
  final displays = await screenRetriever.getAllDisplays();
  final info = <Map<String, Object?>>[
    for (final (i, d) in displays.indexed)
      {
        'index': i,
        'name': d.name,
        'size': '${d.size.width.round()}x${d.size.height.round()}',
        'scale': d.scaleFactor,
        'position':
            '${d.visiblePosition?.dx.round()},${d.visiblePosition?.dy.round()}',
      },
  ];
  final d = displays[displayIndex % displays.length];
  await windowManager.setPosition(
    (d.visiblePosition ?? Offset.zero) + const Offset(80, 80),
  );
  await Future<void>.delayed(
    const Duration(seconds: 2),
  ); // settle on the new display
  await phase(
    'pacing_idle',
    () => Future<void>.delayed(const Duration(seconds: 8)),
  );
  return {'testedDisplay': displayIndex % displays.length, 'displays': info};
}
