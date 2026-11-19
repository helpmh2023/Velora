import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Names of the Hive boxes the app uses (files are `<name>.hive`).
const hiveBoxNames = ['settings', 'favourites', 'progress', 'watched'];

/// Points Hive at the app's own data folder
/// (`%APPDATA%\<company>\<app>\data` on Windows) instead of the user's
/// Documents folder, moving any data an earlier version left there.
Future<Directory> initStorage() async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory(p.join(support.path, 'data'));
  await dir.create(recursive: true);

  final docs = await getApplicationDocumentsDirectory();
  migrateLegacyData(from: docs, to: dir);

  Hive.init(dir.path);
  return dir;
}

/// Folder for the torrent engine's downloaded data: the app's cache
/// directory (`%LOCALAPPDATA%\Velora\Velora\engine` on Windows), so
/// it survives restarts and is not swept like the temp folder.
Future<Directory> engineCacheDir() async {
  final base = await getApplicationCacheDirectory();
  final dir = Directory(p.join(base.path, 'engine'));
  await dir.create(recursive: true);
  // Version 1.0.1 and earlier kept it in the temp folder; remove that copy.
  try {
    final old = Directory(p.join(Directory.systemTemp.path, 'velora-cache'));
    if (old.existsSync()) old.deleteSync(recursive: true);
  } catch (_) {}
  return dir;
}

/// Early builds stored the boxes directly in Documents. Move them over
/// (never overwriting data that is already in [to]) and tidy up lock files.
/// Returns the names that were moved.
List<String> migrateLegacyData({
  required Directory from,
  required Directory to,
  List<String> names = hiveBoxNames,
}) {
  final moved = <String>[];
  for (final name in names) {
    final src = File(p.join(from.path, '$name.hive'));
    final dst = File(p.join(to.path, '$name.hive'));
    if (!src.existsSync() || dst.existsSync()) continue;
    try {
      try {
        src.renameSync(dst.path); // same volume: instant
      } on FileSystemException {
        src.copySync(dst.path); // different volume
        src.deleteSync();
      }
      moved.add(name);
    } catch (_) {
      continue; // leave it; the app just starts with defaults for that box
    }
    for (final ext in ['lock', 'hive.lock']) {
      final lock = File(p.join(from.path, '$name.$ext'));
      if (lock.existsSync()) {
        try {
          lock.deleteSync();
        } catch (_) {}
      }
    }
  }
  return moved;
}
