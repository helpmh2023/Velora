import 'package:flutter_test/flutter_test.dart';
import 'package:velora/models/meta_item.dart';
import 'package:velora/models/stream_source.dart';
import 'package:velora/services/next_episode.dart';

Episode ep(int s, int n, {DateTime? released, String? title}) => Episode(
  id: 'tt1:$s:$n',
  season: s,
  number: n,
  title: title ?? 'E$s.$n',
  released: released,
);

MetaItem show(List<Episode> eps) =>
    MetaItem(id: 'tt1', type: 'series', name: 'Show', episodes: eps);

StreamSource src(
  String hash, {
  Quality q = Quality.fhd,
  int seeders = 10,
  String provider = 'P',
  String? group,
}) => StreamSource(
  infoHash: hash,
  fileIdx: 0,
  release: 'rel $hash',
  quality: q,
  tags: const [],
  seeders: seeders,
  sizeLabel: '1 GB',
  sizeBytes: 1,
  provider: provider,
  languages: '',
  trackers: const [],
  bingeGroup: group,
);

void main() {
  group('nextEpisodeAfter', () {
    final now = DateTime(2026, 6, 1);
    final past = DateTime(2025, 1, 1);

    test('next episode in the same season', () {
      final s = show([ep(1, 1), ep(1, 2), ep(1, 3)]);
      expect(nextEpisodeAfter(s, 1, 1, now: now)?.id, 'tt1:1:2');
      expect(nextEpisodeAfter(s, 1, 2, now: now)?.id, 'tt1:1:3');
    });

    test('rolls over into the next season', () {
      final s = show([ep(1, 1), ep(1, 2), ep(2, 1), ep(2, 2)]);
      expect(nextEpisodeAfter(s, 1, 2, now: now)?.id, 'tt1:2:1');
    });

    test('works from unsorted lists and with gaps in numbering', () {
      final s = show([ep(2, 1), ep(1, 3), ep(1, 1), ep(1, 5)]);
      expect(nextEpisodeAfter(s, 1, 1, now: now)?.id, 'tt1:1:3');
      expect(nextEpisodeAfter(s, 1, 3, now: now)?.id, 'tt1:1:5');
      expect(nextEpisodeAfter(s, 1, 5, now: now)?.id, 'tt1:2:1');
    });

    test('never jumps into specials (season 0), unless already there', () {
      final s = show([ep(0, 1), ep(0, 2), ep(1, 1), ep(1, 2)]);
      expect(nextEpisodeAfter(s, 1, 2, now: now), isNull);
      expect(nextEpisodeAfter(s, 0, 1, now: now)?.id, 'tt1:0:2');
    });

    test('null at the end of the series', () {
      final s = show([ep(1, 1), ep(1, 2)]);
      expect(nextEpisodeAfter(s, 1, 2, now: now), isNull);
      expect(nextEpisodeAfter(s, 5, 9, now: now), isNull);
    });

    test('an episode that has not aired yet is not offered', () {
      final s = show([
        ep(1, 1, released: past),
        ep(1, 2, released: DateTime(2027, 1, 1)),
        ep(1, 3, released: DateTime(2027, 2, 1)),
      ]);
      expect(
        nextEpisodeAfter(s, 1, 1, now: now),
        isNull,
      ); // and no skipping ahead
    });

    test('missing air dates count as available', () {
      final s = show([ep(1, 1), ep(1, 2)]);
      expect(nextEpisodeAfter(s, 1, 1, now: now)?.id, 'tt1:1:2');
    });

    test('a show with no episode list has no next episode', () {
      expect(nextEpisodeAfter(show(const []), 1, 1, now: now), isNull);
    });
  });

  group('pickSimilarSource', () {
    test('nothing usable gives null', () {
      expect(pickSimilarSource([], null), isNull);
      expect(pickSimilarSource([src('a', seeders: 0)], null), isNull);
    });

    test('prefers the same binge group, even over more seeders elsewhere', () {
      final ref = src('r', group: 'torrentio|g1');
      final pick = pickSimilarSource([
        src('big', seeders: 900, group: 'torrentio|other'),
        src('match-low', seeders: 5, group: 'torrentio|g1'),
        src('match-high', seeders: 40, group: 'torrentio|g1'),
      ], ref);
      expect(pick?.infoHash, 'match-high');
    });

    test('a season pack you are already in is the next choice', () {
      final ref = src('pack'); // no binge group
      final pick = pickSimilarSource([
        src('other', seeders: 500),
        src('pack', seeders: 3),
      ], ref);
      expect(pick?.infoHash, 'pack');
    });

    test('then same quality and provider, then same quality', () {
      final ref = src('r', q: Quality.hd, provider: 'EZTV');
      final list = [
        src('fhd-big', q: Quality.fhd, seeders: 300),
        src('hd-other', q: Quality.hd, seeders: 50, provider: 'YTS'),
        src('hd-same', q: Quality.hd, seeders: 20, provider: 'EZTV'),
      ];
      expect(pickSimilarSource(list, ref)?.infoHash, 'hd-same');
      expect(pickSimilarSource(list.sublist(0, 2), ref)?.infoHash, 'hd-other');
    });

    test('falls back to the most seeded when nothing matches', () {
      final ref = src('r', q: Quality.uhd);
      final pick = pickSimilarSource([
        src('a', q: Quality.fhd, seeders: 10),
        src('b', q: Quality.hd, seeders: 70),
      ], ref);
      expect(pick?.infoHash, 'b');
    });

    test('without a reference: best 1080p, else best overall', () {
      expect(
        pickSimilarSource([
          src('uhd', q: Quality.uhd, seeders: 99),
          src('fhd', q: Quality.fhd, seeders: 10),
          src('fhd2', q: Quality.fhd, seeders: 30),
        ], null)?.infoHash,
        'fhd2',
      );
      expect(
        pickSimilarSource([
          src('uhd', q: Quality.uhd, seeders: 99),
          src('hd', q: Quality.hd, seeders: 10),
        ], null)?.infoHash,
        'uhd',
      );
    });

    test('seeder ties go to the higher quality', () {
      final pick = pickSimilarSource([
        src('hd', q: Quality.hd, seeders: 10),
        src('fhd', q: Quality.fhd, seeders: 10),
      ], src('r', q: Quality.sd));
      expect(pick?.infoHash, 'fhd');
    });
  });

  test('binge group survives parsing and storage', () {
    final s = StreamSource.fromJson({
      'name': 'Torrentio\n1080p',
      'title': 'Show.S01E01.1080p\n\u{1F464} 12 \u{1F4BE} 1 GB ⚙️ X',
      'infoHash': 'a' * 40,
      'fileIdx': 3,
      'behaviorHints': {'bingeGroup': 'torrentio|1080p'},
    });
    expect(s.bingeGroup, 'torrentio|1080p');
    expect(StreamSource.fromStored(s.toJson()).bingeGroup, 'torrentio|1080p');
  });
}
