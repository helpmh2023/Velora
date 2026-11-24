import 'package:flutter_test/flutter_test.dart';
import 'package:velora/services/watch_tracker.dart';

void main() {
  const hour = Duration(hours: 1);

  test('position follows how far into the file was read', () {
    final t = WatchTracker(mainStreamMinBytes: 100, rewind: Duration.zero);
    final c = t.open();
    t.bytes(c, 0, 5000, 10000);
    expect(t.estimate(hour), const Duration(minutes: 30));
  });

  test('a rewind is taken off so resuming never skips unseen video', () {
    final t = WatchTracker(
      mainStreamMinBytes: 100,
      rewind: const Duration(seconds: 30),
    );
    t.bytes(t.open(), 0, 5000, 10000);
    expect(t.estimate(hour), const Duration(minutes: 29, seconds: 30));
  });

  test('a seek (new connection from the middle) moves the position', () {
    final t = WatchTracker(mainStreamMinBytes: 100, rewind: Duration.zero);
    t.bytes(t.open(), 0, 2000, 10000); // watched the first 20 %
    final seek = t.open();
    t.bytes(seek, 7000, 1000, 10000); // jumped to 70 %, read 10 % more
    expect(t.estimate(hour), const Duration(minutes: 48)); // 80 %
  });

  test('short header / index probes are ignored', () {
    final t = WatchTracker(mainStreamMinBytes: 1000, rewind: Duration.zero);
    final main = t.open();
    t.bytes(main, 0, 4000, 10000);
    // The player peeks at the end of the file for the index: tiny read.
    final probe = t.open();
    t.bytes(probe, 9900, 100, 10000);
    expect(t.estimate(hour), const Duration(minutes: 24)); // still 40 %
  });

  test('nothing read yet gives no estimate', () {
    final t = WatchTracker();
    expect(t.estimate(hour), isNull);
    expect(
      t.shouldReport(
        now: DateTime.now(),
        idle: const Duration(seconds: 1),
        every: const Duration(seconds: 1),
      ),
      isFalse,
    );
  });

  test('reports once it goes quiet, and not again until it moves', () {
    final t = WatchTracker(mainStreamMinBytes: 1, rewind: Duration.zero);
    final t0 = DateTime(2026, 1, 1, 12);
    const idle = Duration(seconds: 90);
    const every = Duration(seconds: 60);
    t.bytes(t.open(), 0, 1000, 10000, now: t0);

    // Playing: first report is due straight away, then every minute.
    expect(t.shouldReport(now: t0, idle: idle, every: every), isTrue);
    t.reported(now: t0);
    expect(
      t.shouldReport(
        now: t0.add(const Duration(seconds: 10)),
        idle: idle,
        every: every,
      ),
      isFalse,
    );

    // It moved on and was read some more.
    t.bytes(0, 0, 3000, 10000, now: t0.add(const Duration(seconds: 70)));
    expect(
      t.shouldReport(
        now: t0.add(const Duration(seconds: 70)),
        idle: idle,
        every: every,
      ),
      isTrue,
    );
    t.reported(now: t0.add(const Duration(seconds: 70)));

    // Then silence: stopped -> reported once; nothing new -> not again.
    expect(
      t.shouldReport(
        now: t0.add(const Duration(seconds: 200)),
        idle: idle,
        every: every,
      ),
      isFalse,
      reason: 'already reported this exact position',
    );
  });
}
