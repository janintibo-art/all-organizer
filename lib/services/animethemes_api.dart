import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/media_meta.dart';
import 'http_client.dart';

/// AnimeThemes : base communautaire, gratuite, sans clé et sans quota strict.
/// Elle fournit titre, synopsis, année et jaquette, mais pas les genres.
/// Sert de quatrième filet quand les trois autres se taisent.
class AnimeThemesApi {
  static const String _host = 'api.animethemes.moe';
  static String? lastError;

  static Future<Map<String, dynamic>?> _get(Map<String, String> params) async {
    try {
      final uri = Uri.https(_host, '/anime', params);
      final res = await http
          .get(uri, headers: AppHttp.headers())
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        lastError = 'HTTP ${res.statusCode}';
        return null;
      }
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  static Future<List<MediaMeta>> search(String title, {int limit = 8}) async {
    if (title.trim().isEmpty) return const [];
    final body = await _get({
      'filter[name]': title.trim(),
      'page[size]': '${limit.clamp(1, 15)}',
      'include': 'images,animesynonyms',
    });
    return _parse(body);
  }

  static const Map<String, String> _sorts = {
    'START_DATE_DESC': '-year',
    'TRENDING_DESC': '-year',
    'POPULARITY_DESC': '-year',
    'SCORE_DESC': '-year',
    'FAVOURITES_DESC': 'name',
  };

  static Future<List<MediaMeta>> browse({
    int page = 1,
    int perPage = 15,
    String sort = 'TRENDING_DESC',
    String? format,
  }) async {
    final body = await _get({
      'page[size]': '${perPage.clamp(1, 15)}',
      'page[number]': '$page',
      'sort': _sorts[sort] ?? '-year',
      'include': 'images',
      if (format != null && format.toUpperCase() == 'TV')
        'filter[media_format]': 'TV',
    });
    return _parse(body);
  }

  static List<MediaMeta> _parse(Map<String, dynamic>? body) {
    if (body == null) return const [];
    final list = body['anime'] as List? ?? const [];
    return list
        .map((e) => _map(Map<String, dynamic>.from(e as Map)))
        .whereType<MediaMeta>()
        .toList();
  }

  static MediaMeta? _map(Map<String, dynamic> item) {
    final name = item['name']?.toString();
    if (name == null || name.trim().isEmpty) return null;

    String? image;
    for (final img in item['images'] as List? ?? const []) {
      final facet = (img as Map)['facet']?.toString() ?? '';
      if (facet.toLowerCase().contains('cover')) {
        image = img['link']?.toString();
        if (facet.toLowerCase().contains('large')) break;
      }
    }

    // Les synonymes contiennent souvent le titre japonais ou une variante.
    String? synonym;
    final synonyms = item['animesynonyms'] as List? ?? const [];
    if (synonyms.isNotEmpty) {
      synonym = (synonyms.first as Map)['text']?.toString();
    }

    return MediaMeta(
      sourceId: item['id'] as int?,
      source: 'animethemes',
      title: name,
      titleRomaji: name,
      titleNative: synonym,
      imageUrl: image,
      synopsis: item['synopsis']?.toString(),
      year: item['year'] as int?,
      type: item['media_format']?.toString(),
      status: item['season']?.toString(),
    );
  }
}
