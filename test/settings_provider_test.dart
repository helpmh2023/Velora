import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:velora/providers/settings_provider.dart';

void main() {
  test('settings have defaults and persist across reopen', () async {
    final dir = await Directory.systemTemp.createTemp('velora_hive_test');
    addTearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });
    Hive.init(dir.path);

    var box = await Hive.openBox<dynamic>('settings');
    var s = SettingsProvider(box);
    expect(s.maxCacheGb, 8);
    expect(s.uploadKbps, 1); // minimum upload by default
    expect(s.allowUpload, isTrue);
    expect(s.remoteUrl, isNull);

    s.maxCacheGb = 12;
    s.uploadKbps = 512;
    s.allowUpload = false;
    s.remoteUrl = '  http://100.64.0.5:11470 ';
    await box.close();

    box = await Hive.openBox<dynamic>('settings');
    s = SettingsProvider(box);
    expect(s.maxCacheGb, 12);
    expect(s.uploadKbps, 512);
    expect(s.allowUpload, isFalse);
    expect(s.remoteUrl, 'http://100.64.0.5:11470');

    s.remoteUrl = '   ';
    expect(s.remoteUrl, isNull);
  });

  test('existing installs are moved to the minimum upload once', () async {
    final dir = await Directory.systemTemp.createTemp('velora_hive_test2');
    addTearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });
    Hive.init(dir.path);

    // An install from before the change: 256 KB/s saved, no version marker.
    var box = await Hive.openBox<dynamic>('settings');
    await box.put('uploadKbps', 256);
    var s = SettingsProvider(box);
    expect(s.uploadKbps, 1);

    // The user raises it afterwards; that choice must stick across restarts.
    s.uploadKbps = 64;
    await box.close();
    box = await Hive.openBox<dynamic>('settings');
    s = SettingsProvider(box);
    expect(s.uploadKbps, 64);

    // Adapter binding persists too.
    s.setBinding('10.2.0.2', 'ProtonVPN');
    await box.close();
    box = await Hive.openBox<dynamic>('settings');
    s = SettingsProvider(box);
    expect(s.bindIp, '10.2.0.2');
    expect(s.bindName, 'ProtonVPN');
    s.setBinding(null, null);
    expect(s.bindIp, isNull);
  });
}
