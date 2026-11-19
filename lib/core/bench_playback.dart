import 'dart:async';
import 'dart:io' show ProcessInfo;

import 'package:material_ui/material_ui.dart';

import '../models/meta_item.dart';
import '../models/stream_source.dart';
import '../screens/player/open_player.dart';
import '../screens/player/player_stats.dart';

/// Plays Big Buck Bunny (an openly licensed film) through the real engine and
/// player, then reports how playback went. Needs internet and a few peers.
/// Used by `VELORA_BENCH=playback`.
Future<Map<String, Object?>> playbackBench(
  BuildContext Function() ctx,
  GlobalKey<NavigatorState> navKey,
  Future<void> Function(String, Future<void> Function()) phase,
) async {
  collectPlayerStats = true;
  final source = StreamSource.fromJson({
    'name': 'Torrentio\n1080p',
    'title': 'Big Buck Bunny (bench)\n\u{1F464} 100 \u{1F4BE} 276 MB ⚙️ test',
    'infoHash': 'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c',
    'fileIdx': 1,
  });
  const meta = MetaItem(id: 'ttbench', type: 'movie', name: 'Big Buck Bunny');

  final samples = <Map<String, Object?>>[];
  var startedAfterMs = -1;
  final wall = Stopwatch()..start();

  // 1) Open the player; wait (up to 2 min) until video is actually playing.
  unawaited(openPlayer(ctx(), source: source, meta: meta, videoId: 'ttbench'));
  while (wall.elapsed < const Duration(minutes: 2)) {
    await Future<void>.delayed(const Duration(seconds: 1));
    final st = latestPlayerStats.value;
    if (st != null && (st.positionSecs ?? 0) > 1) {
      startedAfterMs = wall.elapsedMilliseconds;
      break;
    }
  }
  if (startedAfterMs < 0) {
    navKey.currentState!.pop();
    collectPlayerStats = false;
    return {'error': 'playback never started within 2 minutes'};
  }

  // 2) Steady playback: sample once a second for 45 s.
  PlayerStats? first;
  PlayerStats? last;
  var waits = 0;
  var maxMBps = 0.0;
  var sumMBps = 0.0;
  var n = 0;
  await phase('playback_steady', () async {
    final steady = Stopwatch()..start();
    while (steady.elapsed < const Duration(seconds: 45)) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final st = latestPlayerStats.value;
      if (st == null) continue;
      first ??= st;
      last = st;
      if (st.pausedForCache) waits++;
      final mb = (st.cacheSpeedBytes ?? 0) / 1048576;
      sumMBps += mb;
      if (mb > maxMBps) maxMBps = mb;
      n++;
      if (n % 5 == 0) {
        samples.add({'t': steady.elapsed.inSeconds, ...st.toJson()});
      }
    }
  });

  navKey.currentState!.pop();
  collectPlayerStats = false;

  final l = last;
  final f = first;
  return {
    'startedAfterSeconds': double.parse(
      (startedAfterMs / 1000).toStringAsFixed(1),
    ),
    'secondsWaitingForData': waits,
    'appMemoryMB': (ProcessInfo.currentRss / 1048576).round(),
    'networkMBps': {
      'avg': n == 0 ? null : double.parse((sumMBps / n).toStringAsFixed(2)),
      'max': double.parse(maxMBps.toStringAsFixed(2)),
    },
    if (l != null && f != null) ...{
      'hwdec': l.hwdec,
      'codec': l.codec,
      'size': '${l.width}x${l.height}',
      'containerFps': l.containerFps,
      'renderedFps': l.renderedFps,
      'decoderDropsDuring': l.decoderDrops - f.decoderDrops,
      'displayDropsDuring': l.voDrops - f.voDrops,
      'mistimedDuring': l.mistimed - f.mistimed,
    },
    'samples': samples,
  };
}
