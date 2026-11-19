// Dev-only tool: the scripted run deliberately reuses one navigator context
// across awaits.
// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../providers/home_provider.dart';
import 'bench_pacing.dart';
import 'bench_playback.dart';
import '../screens/home/home_screen.dart';
import 'glass.dart';

/// Scripted performance run, only active when the environment variable
/// `VELORA_BENCH` is set to a variant name:
///   baseline | noglass | smooth | noaurora
///
/// It plays through splash -> home idle -> mouse-wheel scrolling -> details
/// page -> back, records every frame's timing, writes
/// `%TEMP%/velora_bench_<variant>.json` and exits. Meant for release builds:
///   $env:VELORA_BENCH = 'baseline'; .\velora.exe
Future<void> runBenchIfRequested(GlobalKey<NavigatorState> navKey) async {
  final variant = Platform.environment['VELORA_BENCH'];
  if (variant == null || variant.isEmpty) return;
  try {
    await _runBench(variant, navKey);
  } catch (e, st) {
    File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}velora_bench_error.txt',
    ).writeAsStringSync('$e\n$st');
    exit(2);
  }
}

Future<void> _runBench(String variant, GlobalKey<NavigatorState> navKey) async {
  switch (variant) {
    case 'noglass':
      reduceGlass.value = true;
    case 'smooth':
      auroraQuality.value = AuroraQuality.smooth;
    case 'noaurora':
      auroraQuality.value = AuroraQuality.off;
  }

  final frames = <FrameTiming>[];
  SchedulerBinding.instance.addTimingsCallback(frames.addAll);

  final phases = <_Phase>[];
  Duration now() => SchedulerBinding.instance.currentSystemFrameTimeStamp;

  Future<void> phase(String name, Future<void> Function() body) async {
    final p = _Phase(name)..start = now();
    final sw = Stopwatch()..start();
    await body();
    p.end = now();
    p.wallMs = sw.elapsedMilliseconds;
    phases.add(p);
  }

  final view = PlatformDispatcher.instance.views.first;
  final size = view.physicalSize / view.devicePixelRatio;
  final center = Offset(size.width / 2, size.height / 2);

  Future<void> wheel(int ticks, double dy, {int everyMs = 40}) async {
    for (var i = 0; i < ticks; i++) {
      GestureBinding.instance.handlePointerEvent(
        PointerScrollEvent(position: center, scrollDelta: Offset(0, dy)),
      );
      await Future<void>.delayed(Duration(milliseconds: everyMs));
    }
  }

  BuildContext ctx() => navKey.currentContext!;

  // 1. Splash: from process start until the intro ends.
  await phase('splash', () async {
    await Future<void>.delayed(const Duration(milliseconds: 5800));
  });

  // Wait for data + the fade into the shell.
  final home = ctx().read<HomeProvider>();
  await home.ready.timeout(const Duration(seconds: 20), onTimeout: () {});
  await Future<void>.delayed(const Duration(milliseconds: 1500));

  // `pacing<N>`: move the window to display N and measure frame pacing there.
  if (variant.startsWith('pacing')) {
    final extra = await pacingProbe(
      int.tryParse(variant.substring(6)) ?? 0,
      () => now(),
      phase,
    );
    await _finish(variant, view, frames, phases, extra);
    return;
  }

  Map<String, Object?>? playback;
  if (variant == 'playback') {
    playback = await playbackBench(ctx, navKey, phase);
    await _finish(variant, view, frames, phases, playback);
    return;
  }

  await phase(
    'home_idle',
    () => Future<void>.delayed(const Duration(seconds: 4)),
  );

  await phase('home_scroll', () async {
    await wheel(45, 120); // down
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await wheel(45, -120); // and back up
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });

  if (home.hero.isNotEmpty) {
    await phase('details', () async {
      HomeScreen.openDetails(ctx(), home.hero.first);
      await Future<void>.delayed(const Duration(seconds: 3));
      await wheel(20, 100);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      navKey.currentState!.pop();
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
  }

  await phase(
    'home_again',
    () => Future<void>.delayed(const Duration(seconds: 3)),
  );

  await _finish(variant, view, frames, phases, null);
}

Future<void> _finish(
  String variant,
  FlutterView view,
  List<FrameTiming> frames,
  List<_Phase> phases,
  Map<String, Object?>? playback,
) async {
  // Let the last batch of timings arrive.
  await Future<void>.delayed(const Duration(seconds: 2));

  final out = <String, Object?>{
    'variant': variant,
    'mode': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
    'devicePixelRatio': view.devicePixelRatio,
    'physicalSize':
        '${view.physicalSize.width.round()}x${view.physicalSize.height.round()}',
    'framesTotal': frames.length,
    'playback': ?playback,
    'phases': {for (final p in phases) p.name: p.summarize(frames)},
  };
  final path =
      '${Directory.systemTemp.path}${Platform.pathSeparator}velora_bench_$variant.json';
  File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('VELORA_BENCH_DONE $path');
  exit(0);
}

class _Phase {
  _Phase(this.name);
  final String name;
  Duration start = Duration.zero;
  Duration end = Duration.zero;
  int wallMs = 0;

  Map<String, Object?> summarize(List<FrameTiming> all) {
    final mine = all.where((f) {
      final t = Duration(
        microseconds: f.timestampInMicroseconds(FramePhase.vsyncStart),
      );
      return t >= start && t < end;
    }).toList();
    if (mine.isEmpty) {
      return {'wallMs': wallMs, 'frames': 0};
    }
    double ms(Duration d) => d.inMicroseconds / 1000;
    double pct(List<double> sorted, double p) =>
        sorted[((sorted.length - 1) * p).round()];
    final total = mine.map((f) => ms(f.totalSpan)).toList()..sort();
    final build = mine.map((f) => ms(f.buildDuration)).toList()..sort();
    final raster = mine.map((f) => ms(f.rasterDuration)).toList()..sort();
    double avg(List<double> l) => l.reduce((a, b) => a + b) / l.length;
    // Gaps between consecutive frame starts: shows how frames are paced.
    final starts =
        mine
            .map((f) => f.timestampInMicroseconds(FramePhase.vsyncStart) / 1000)
            .toList()
          ..sort();
    final gaps = <double>[
      for (var i = 1; i < starts.length; i++) starts[i] - starts[i - 1],
    ]..sort();
    return {
      'wallMs': wallMs,
      'frames': mine.length,
      'fps': double.parse((mine.length / (wallMs / 1000)).toStringAsFixed(1)),
      'totalMs': {
        'avg': double.parse(avg(total).toStringAsFixed(2)),
        'p90': double.parse(pct(total, .9).toStringAsFixed(2)),
        'p99': double.parse(pct(total, .99).toStringAsFixed(2)),
        'worst': double.parse(total.last.toStringAsFixed(2)),
      },
      'buildMs': {
        'avg': double.parse(avg(build).toStringAsFixed(2)),
        'p99': double.parse(pct(build, .99).toStringAsFixed(2)),
      },
      'rasterMs': {
        'avg': double.parse(avg(raster).toStringAsFixed(2)),
        'p99': double.parse(pct(raster, .99).toStringAsFixed(2)),
        'worst': double.parse(raster.last.toStringAsFixed(2)),
      },
      if (gaps.isNotEmpty)
        'gapMs': {
          'p10': double.parse(pct(gaps, .1).toStringAsFixed(1)),
          'p50': double.parse(pct(gaps, .5).toStringAsFixed(1)),
          'p90': double.parse(pct(gaps, .9).toStringAsFixed(1)),
        },
      'over16ms': mine.where((f) => ms(f.totalSpan) > 16.7).length,
      'over33ms': mine.where((f) => ms(f.totalSpan) > 33.4).length,
    };
  }
}
