import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/stream_source.dart';

class TorrentioException implements Exception {
  TorrentioException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Asks the Torrentio addon which torrents carry a title.
///
/// [type] is `movie` or `series`. [videoId] is the IMDb id, or for an episode
/// `tt0944947:<season>:<episode>` (that is exactly Cinemeta's episode id).
class TorrentioService {
  TorrentioService({http.Client? client}) : _client = client ?? http.Client();

  static const _base = 'https://torrentio.strem.fun';
  final http.Client _client;

  Future<List<StreamSource>> streams(String type, String videoId) async {
    final uri = Uri.parse(
      '$_base/stream/$type/${Uri.encodeComponent(videoId)}.json',
    );
    final http.Response res;
    try {
      res = await _client
          .get(uri, headers: {'User-Agent': 'Velora'})
          .timeout(const Duration(seconds: 25));
    } catch (e) {
      throw TorrentioException('Could not reach the stream source ($e)');
    }
    if (res.statusCode != 200) {
      throw TorrentioException('Stream source returned ${res.statusCode}');
    }

    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final raw = json['streams'];
    if (raw is! List) return const [];

    final out = <StreamSource>[];
    for (final s in raw.whereType<Map<String, dynamic>>()) {
      if (s['infoHash'] == null) continue; // debrid/redirect entries: skip
      try {
        final src = StreamSource.fromJson(s);
        if (src.seeders > 0) out.add(src);
      } catch (_) {}
    }
    // Best first: highest quality tier, then most seeders.
    out.sort((a, b) {
      final q = a.quality.index.compareTo(b.quality.index);
      return q != 0 ? q : b.seeders.compareTo(a.seeders);
    });
    return out;
  }
}
