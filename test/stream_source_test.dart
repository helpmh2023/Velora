import 'package:flutter_test/flutter_test.dart';
import 'package:velora/models/stream_source.dart';

void main() {
  test('parses a Torrentio 4K HDR entry', () {
    final s = StreamSource.fromJson({
      'name': 'Torrentio\n4k HDR',
      'title':
          'The Shawshank Redemption 1994 2160p BluRay\n'
          '\u{1F464} 191 \u{1F4BE} 6.91 GB \u2699\uFE0F YTS',
      'infoHash': 'C3DA9A3DC2CE14D0D4FC0E87D1B2023502F8DCD6',
      'fileIdx': 0,
    });
    expect(s.quality, Quality.uhd);
    expect(s.tags, ['HDR']);
    expect(s.seeders, 191);
    expect(s.sizeLabel, '6.91 GB');
    expect(s.sizeBytes, (6.91 * (1 << 30)).round());
    expect(s.provider, 'YTS');
    expect(s.infoHash, 'c3da9a3dc2ce14d0d4fc0e87d1b2023502f8dcd6');
    expect(s.fileIdx, 0);
    expect(s.trackers, isNotEmpty); // falls back to default trackers
  });

  test('parses multi-language entry with trackers and DV tags', () {
    final s = StreamSource.fromJson({
      'name': 'Torrentio\n4k DV | HDR',
      'title':
          'Release / Name [2160p]\n'
          '\u{1F464} 97 \u{1F4BE} 78.61 GB \u2699\uFE0F Rutracker\n'
          '\u{1F1EC}\u{1F1E7} / \u{1F1F7}\u{1F1FA}',
      'infoHash': '23dfd11259dd6435dce2fef48d6721ffa8c08664',
      'sources': [
        'tracker:udp://tracker.opentrackr.org:1337/announce',
        'dht:23dfd11259dd6435dce2fef48d6721ffa8c08664',
      ],
    });
    expect(s.quality, Quality.uhd);
    expect(s.tags, ['DV', 'HDR']);
    expect(s.languages, isNotEmpty);
    expect(s.trackers, ['udp://tracker.opentrackr.org:1337/announce']);
    expect(s.fileIdx, isNull);
  });

  test('quality tiers', () {
    Quality q(String l) => StreamSource.fromJson({
      'name': 'Torrentio\n$l',
      'title': 'x\n\u{1F464} 1 \u{1F4BE} 1 GB \u2699\uFE0F p',
      'infoHash': 'a' * 40,
    }).quality;
    expect(q('1080p'), Quality.fhd);
    expect(q('720p'), Quality.hd);
    expect(q('480p'), Quality.sd);
    expect(q('BRRip'), Quality.other);
  });
}
