import 'package:media_kit/media_kit.dart';

/// Finds out how long the video at [url] is by opening it in a throw-away,
/// invisible player (no window, no sound). Null if it cannot be read in time.
Future<Duration?> probeDuration(
  String url, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final player = Player(
    configuration: const PlayerConfiguration(title: 'Velora probe', vo: 'null'),
  );
  try {
    await player.open(Media(url), play: false);
    if (player.state.duration > Duration.zero) return player.state.duration;
    return await player.stream.duration
        .firstWhere((d) => d > Duration.zero)
        .timeout(timeout);
  } catch (_) {
    return null;
  } finally {
    await player.dispose();
  }
}
