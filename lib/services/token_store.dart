import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where secrets live (Trakt client secret, access/refresh tokens).
/// Never Hive: those boxes are plain files.
abstract class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

/// OS-backed storage (Windows Credential Locker / Keychain / Keystore).
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) async {
    try {
      return await _s.read(key: key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String? value) async {
    try {
      if (value == null) {
        await _s.delete(key: key);
      } else {
        await _s.write(key: key, value: value);
      }
    } catch (_) {}
  }
}

/// For tests.
class MemoryTokenStore implements TokenStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }
}
