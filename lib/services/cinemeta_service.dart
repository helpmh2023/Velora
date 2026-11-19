import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/meta_item.dart';

class CinemetaException implements Exception {
  CinemetaException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thin client for the Cinemeta addon (Stremio's catalog + metadata source).
class CinemetaService {
  CinemetaService({http.Client? client}) : _client = client ?? http.Client();

  static const _base = 'https://v3-cinemeta.strem.io';
  static const _timeout = Duration(seconds: 15);

  final http.Client _client;

  Future<Map<String, dynamic>> _getJson(String path) async {
    try {
      final res = await _client.get(Uri.parse('$_base$path')).timeout(_timeout);
      if (res.statusCode != 200) {
        throw CinemetaException('Cinemeta returned ${res.statusCode}');
      }
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on CinemetaException {
      rethrow;
    } catch (e) {
      throw CinemetaException('Could not reach Cinemeta ($e)');
    }
  }

  /// [type] is `movie` or `series`; [id] a catalog id (`top`, `year`,
  /// `imdbRating`). Pages are 50 items; use [skip] for the next page.
  Future<List<MetaItem>> catalog(
    String type, {
    String id = 'top',
    String? genre,
    String? search,
    int skip = 0,
  }) async {
    final extras = <String>[
      if (search != null) 'search=${Uri.encodeComponent(search)}',
      if (genre != null) 'genre=${Uri.encodeComponent(genre)}',
      'skip=$skip',
    ];
    final json = await _getJson('/catalog/$type/$id/${extras.join('&')}.json');
    final metas = json['metas'];
    if (metas is! List) return const [];
    return metas
        .whereType<Map<String, dynamic>>()
        .map(MetaItem.fromJson)
        .toList();
  }

  /// Full metadata (cast, runtime, episode list for series).
  Future<MetaItem> meta(String type, String id) async {
    final json = await _getJson('/meta/$type/$id.json');
    final m = json['meta'];
    if (m is! Map<String, dynamic>) {
      throw CinemetaException('No metadata for $id');
    }
    return MetaItem.fromJson(m);
  }
}
