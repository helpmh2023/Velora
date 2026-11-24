import 'package:flutter_test/flutter_test.dart';
import 'package:velora/screens/player/player_stats.dart';

void main() {
  final meter = UiFrameMeter.instance;

  test('screen keeping up with the video is OK', () {
    meter.lastFps = 59;
    final v = meter.verdict(24)!;
    expect(v.problem, isFalse);
    expect(v.text, contains('OK'));
  });

  test('screen drawing fewer frames than the video is flagged', () {
    meter.lastFps = 15;
    final v = meter.verdict(24)!;
    expect(v.problem, isTrue);
    expect(v.text, contains('PROBLEM'));
    expect(v.text, contains('15 fps'));
    expect(v.text, contains('24 fps'));
  });

  test('nothing to compare yet gives no verdict', () {
    meter.lastFps = 0;
    expect(meter.verdict(24), isNull);
    meter.lastFps = 30;
    expect(meter.verdict(null), isNull);
  });
}
