import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

import '../core/glass.dart';

/// User settings, persisted in a Hive box. Every setter saves immediately.
/// Engine-related values take effect when the engine is restarted (the
/// Settings screen has an "Apply" button for that).
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._box) {
    _maxCacheGb = (_box?.get('maxCacheGb', defaultValue: 4.0) as num)
        .toDouble();
    _uploadKbps = (_box?.get('uploadKbps', defaultValue: 1) as num).toInt();
    _allowUpload = _box?.get('allowUpload', defaultValue: true) as bool;
    _wifiOnly = _box?.get('wifiOnly', defaultValue: true) as bool;
    final url = (_box?.get('remoteUrl', defaultValue: '') as String).trim();
    _remoteUrl = url.isEmpty ? null : url;
    _reduceGlass = _box?.get('reduceGlass', defaultValue: false) as bool;
    reduceGlass.value = _reduceGlass;
    final q = _box?.get('auroraQuality') as String?;
    auroraQuality.value = AuroraQuality.values.firstWhere(
      (e) => e.name == q,
      orElse: () => AuroraQuality.full,
    );
    _bindIp = (_box?.get('bindIp') as String?);
    _bindName = (_box?.get('bindName') as String?);

    // v2: upload now defaults to the minimum (1 KB/s). Apply once to existing
    // installs, then respect whatever the user picks.
    final version = (_box?.get('settingsVersion', defaultValue: 1) as num)
        .toInt();
    if (version < 2) {
      _uploadKbps = 1;
      _box?.put('uploadKbps', 1);
      _box?.put('settingsVersion', 2);
    }
  }

  /// Null in tests.
  final Box<dynamic>? _box;

  late double _maxCacheGb;
  late int _uploadKbps;
  late bool _allowUpload;
  late bool _wifiOnly;
  String? _remoteUrl;
  late bool _reduceGlass;
  String? _bindIp;
  String? _bindName;

  double get maxCacheGb => _maxCacheGb;
  int get uploadKbps => _uploadKbps;
  bool get allowUpload => _allowUpload;
  bool get wifiOnly => _wifiOnly;

  /// Base URL of a remote engine, or null to run the engine on this device.
  String? get remoteUrl => _remoteUrl;
  bool get reduceGlassEnabled => _reduceGlass;

  /// Local address of the adapter (VPN) the engine is bound to, or null.
  String? get bindIp => _bindIp;
  String? get bindName => _bindName;

  void setBinding(String? ip, String? name) {
    _bindIp = ip;
    _bindName = name;
    _box?.put('bindIp', ip);
    _box?.put('bindName', name);
    notifyListeners();
  }

  void _save(String key, Object? value) {
    _box?.put(key, value);
    notifyListeners();
  }

  set maxCacheGb(double v) {
    _maxCacheGb = v;
    _save('maxCacheGb', v);
  }

  set uploadKbps(int v) {
    _uploadKbps = v;
    _save('uploadKbps', v);
  }

  set allowUpload(bool v) {
    _allowUpload = v;
    _save('allowUpload', v);
  }

  set wifiOnly(bool v) {
    _wifiOnly = v;
    _save('wifiOnly', v);
  }

  set remoteUrl(String? v) {
    final t = v?.trim();
    _remoteUrl = (t == null || t.isEmpty) ? null : t;
    _save('remoteUrl', _remoteUrl ?? '');
  }

  // ---- Trakt preferences (credentials/tokens live in secure storage) ------

  bool get traktScrobble =>
      (_box?.get('traktScrobble', defaultValue: true) as bool?) ?? true;
  set traktScrobble(bool v) {
    _box?.put('traktScrobble', v);
    notifyListeners();
  }

  bool get traktWatchlist =>
      (_box?.get('traktWatchlist', defaultValue: true) as bool?) ?? true;
  set traktWatchlist(bool v) {
    _box?.put('traktWatchlist', v);
    notifyListeners();
  }

  String? get traktUser => _box?.get('traktUser') as String?;
  set traktUser(String? v) {
    _box?.put('traktUser', v);
    notifyListeners();
  }

  DateTime? get traktLastSync {
    final ms = _box?.get('traktLastSync') as num?;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms.toInt());
  }

  set traktLastSync(DateTime? v) {
    _box?.put('traktLastSync', v?.millisecondsSinceEpoch);
    notifyListeners();
  }

  /// Titles that were on the Trakt watchlist at the last sync. Lets us tell
  /// "removed on Trakt" from "never synced".
  Set<String> get traktWatchlistIds =>
      ((_box?.get('traktWatchlistIds') as List?) ?? const [])
          .map((e) => '$e')
          .toSet();
  set traktWatchlistIds(Set<String> v) =>
      _box?.put('traktWatchlistIds', v.toList());

  AuroraQuality get auroraQualityValue => auroraQuality.value;
  set auroraQualityValue(AuroraQuality v) {
    auroraQuality.value = v;
    _save('auroraQuality', v.name);
  }

  /// Keep downloaded video between sessions (the cache survives restarts).
  bool get keepCache =>
      (_box?.get('keepCache', defaultValue: true) as bool?) ?? true;
  set keepCache(bool v) {
    _box?.put('keepCache', v);
    notifyListeners();
  }

  /// At the end of an episode, show "Up next" and start the next one.
  bool get autoplayNext =>
      (_box?.get('autoplayNext', defaultValue: true) as bool?) ?? true;
  set autoplayNext(bool v) {
    _box?.put('autoplayNext', v);
    notifyListeners();
  }

  set reduceGlassEnabled(bool v) {
    _reduceGlass = v;
    reduceGlass.value = v;
    _save('reduceGlass', v);
  }
}
