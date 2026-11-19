import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:velora/core/storage.dart';

void main() {
  late Directory from;
  late Directory to;

  setUp(() async {
    final root = await Directory.systemTemp.createTemp('velora_storage_test');
    from = await Directory(p.join(root.path, 'docs')).create();
    to = await Directory(p.join(root.path, 'appdata')).create();
    addTearDown(() => root.delete(recursive: true));
  });

  test('moves old boxes out of Documents and keeps their contents', () {
    File(p.join(from.path, 'settings.hive')).writeAsStringSync('S');
    File(p.join(from.path, 'favourites.hive')).writeAsStringSync('F');
    File(p.join(from.path, 'favourites.lock')).writeAsStringSync('');
    File(p.join(from.path, 'unrelated.txt')).writeAsStringSync('keep me');

    final moved = migrateLegacyData(from: from, to: to);

    expect(moved, unorderedEquals(['settings', 'favourites']));
    expect(File(p.join(to.path, 'settings.hive')).readAsStringSync(), 'S');
    expect(File(p.join(to.path, 'favourites.hive')).readAsStringSync(), 'F');
    expect(File(p.join(from.path, 'settings.hive')).existsSync(), isFalse);
    expect(File(p.join(from.path, 'favourites.lock')).existsSync(), isFalse);
    // Other files in Documents are never touched.
    expect(
      File(p.join(from.path, 'unrelated.txt')).readAsStringSync(),
      'keep me',
    );
  });

  test('never overwrites data already in the new location', () {
    File(p.join(from.path, 'progress.hive')).writeAsStringSync('OLD');
    File(p.join(to.path, 'progress.hive')).writeAsStringSync('NEW');

    final moved = migrateLegacyData(from: from, to: to);

    expect(moved, isEmpty);
    expect(File(p.join(to.path, 'progress.hive')).readAsStringSync(), 'NEW');
    expect(File(p.join(from.path, 'progress.hive')).readAsStringSync(), 'OLD');
  });

  test('nothing to migrate is fine', () {
    expect(migrateLegacyData(from: from, to: to), isEmpty);
  });
}
