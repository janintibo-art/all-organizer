import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/media_meta.dart';
import '../models/episode_release.dart';
import 'http_client.dart';

export '../models/media_meta.dart';

/// Jikan (API publique de MyAnimeList), utilisee en secours d'AniList.
/// Ses limites sont strictes : 3 requetes par seconde et 60 par minute.
/// Le regulateur ci-dessous tient une fenetre glissante des derniers appels
/// plutot qu'un simple delai fixe, et respecte l'en-tete Retry-After.
class JikanApi {
  /// Derniere erreur rencontree, pour le diagnostic des reglages.
  static String? lastError;

  static const String _base = 'https://api.jikan.moe/v4';

  static const int _maxPerSecond = 3;
  static const int _maxPerMinute = 60;
  static const int _minGapMs = 380;

  static final List<DateTime> _calls = [];

  static Future<void> _gate() async {
    while (true) {
      final now = DateTime.now();
      _calls.removeWhere((t) => now.difference(t).inMilliseconds > 60000);

      final inLastSecond =
          _calls.where((t) => now.difference(t).inMilliseconds < 1000).toList();
      var waitMs = 0;

      if (_calls.isNotEmpty) {
        final sinceLast = now.difference(_calls.last).inMilliseconds;
        if (sinceLast < _minGapMs) waitMs = _minGapMs - sinceLast;
      }
      if (inLastSecond.length >= _maxPerSecond) {
        final w = 1000 - now.difference(inLastSecond.first).inMilliseconds + 5;
        if (w > waitMs) waitMs = w;
      }
      if (_calls.length >= _maxPerMinute) {
        final w = 60000 - now.difference(_calls.first).inMilliseconds + 5;
        if (w > waitMs) waitMs = w;
      }

      if (waitMs <= 0) {
        _calls.add(DateTime.now());
        return;
      }
      await Future<void>.delayed(Duration(milliseconds: waitMs));
    }
  }

  /// Identifiants de genres MyAnimeList, pour retrouver les memes rayons
  /// que sur AniList quand celui-ci ne repond pas.
  static const Map<String, int> genreIds = {
    'Action': 1, 'Adventure': 2, 'Comedy': 4, 'Drama': 8, 'Ecchi': 9,
    'Fantasy': 10, 'Horror': 14, 'Mahou Shoujo': 66, 'Mecha': 18,
    'Music': 19, 'Mystery': 7, 'Psychological': 40, 'Romance': 22,
    'Sci-Fi': 24, 'Slice of Life': 36, 'Sports': 30, 'Supernatural': 37,
    'Thriller': 41,
  };

  static const Map<String, String> _orderBy = {
    'TRENDING_DESC': 'members',
    'POPULARITY_DESC': 'members',
    'SCORE_DESC': 'score',
    'START_DATE_DESC': 'start_date',
    'FAVOURITES_DESC': 'favorites',
  };

  /// Derniers episodes mis en ligne, vus par MyAnimeList.
  static Future<List<EpisodeRelease>> recentEpisodes({int page = 1}) async {
    await _gate();
    try {
      final uri = Uri.https('api.jikan.moe', '/v4/watch/episodes', {
        'page': '$page',
      });
      final res = await http
          .get(uri, headers: AppHttp.headers())
          .timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) {
        lastError = 'HTTP ${res.statusCode}';
        return const [];
      }

      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = body['data'] as List? ?? const [];
      final out = <EpisodeRelease>[];

      for (final item in data) {
        final map = item as Map;
        final entry = map['entry'] as Map?;
        if (entry == null) continue;

        final images = entry['images'] as Map?;
        final jpg = images?['jpg'] as Map?;
        final title = entry['title']?.toString();
        if (title == null || title.isEmpty) continue;

        final meta = MediaMeta(
          sourceId: entry['mal_id'] as int?,
          source: 'jikan',
          title: title,
          titleRomaji: title,
          imageUrl: (jpg?['large_image_url'] ?? jpg?['image_url']) as String?,
        );

        // Le premier element de la liste est l'episode le plus recent.
        final episodes = map['episodes'] as List? ?? const [];
        int? number;
        if (episodes.isNotEmpty) {
          final label = (episodes.first as Map)['mal_id'];
          if (label is int) number = label;
        }

        out.add(EpisodeRelease(anime: meta, number: number));
      }
      return out;
    } catch (e) {
      lastError = e.toString();
      return const [];
    }
  }

  /// Liste de secours : meme role que le parcours AniList, en moins riche.
  static Future<List<MediaMeta>> browse({
    int page = 1,
    String sort = 'TRENDING_DESC',
    String? genre,
    String? format,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'limit': '24',
      'sfw': 'true',
      'order_by': _orderBy[sort] ?? 'members',
      'sort': 'desc',
      if (format != null && format.isNotEmpty) 'type': format.toLowerCase(),
      if (genre != null && genreIds.containsKey(genre))
        'genres': '${genreIds[genre]}',
    };

    for (var attempt = 0; attempt < 3; attempt++) {
      await _gate();
      try {
        final uri = Uri.https('api.jikan.moe', '/v4/anime', params);
        final res = await http
            .get(uri, headers: AppHttp.headers())
            .timeout(const Duration(seconds: 25));
        if (res.statusCode == 429) {
          final retry = double.tryParse(res.headers['retry-after'] ?? '') ?? 2;
          await Future<void>.delayed(
              Duration(milliseconds: (retry * 1000).round()));
          continue;
        }
        if (res.statusCode != 200) {
          lastError = 'HTTP ${res.statusCode}';
          return const [];
        }
        final body =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final data = body['data'] as List? ?? const [];
        return data
            .map((e) => _map(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (e) {
        lastError = e.toString();
        await Future<void>.delayed(Duration(seconds: 1 + attempt));
      }
    }
    return const [];
  }

  static Future<MediaMeta?> search(String title) async {
    final list = await searchMany(title, limit: 1);
    return list.isEmpty ? null : list.first;
  }

  static Future<List<MediaMeta>> searchMany(String title, {int limit = 8}) async {
    final query = title.trim();
    if (query.isEmpty) return const [];

    for (var attempt = 0; attempt < 4; attempt++) {
      await _gate();
      try {
        final uri = Uri.parse(
          '$_base/anime?q=${Uri.encodeQueryComponent(query)}'
          '&limit=$limit&sfw=true&order_by=members&sort=desc',
        );
        final res = await http
            .get(uri, headers: AppHttp.headers())
            .timeout(const Duration(seconds: 20));

        if (res.statusCode == 429) {
          final retry = double.tryParse(res.headers['retry-after'] ?? '') ?? 2;
          await Future<void>.delayed(
              Duration(milliseconds: (retry * 1000).round() + attempt * 500));
          continue;
        }
        if (res.statusCode != 200) {
          lastError = 'HTTP ${res.statusCode}';
          return const [];
        }

        final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final data = body['data'] as List? ?? const [];
        return data
            .map((e) => _map(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (e) {
        lastError = e.toString();
        await Future<void>.delayed(Duration(seconds: 1 + attempt));
      }
    }
    return const [];
  }

  static MediaMeta _map(Map<String, dynamic> j) {
    final images = j['images'] as Map<String, dynamic>?;
    final jpg = images?['jpg'] as Map<String, dynamic>?;
    final webp = images?['webp'] as Map<String, dynamic>?;

    final genres = <String>[];
    for (final field in ['genres', 'themes', 'demographics']) {
      for (final g in j[field] as List? ?? const []) {
        final name = (g as Map)['name']?.toString();
        if (name != null && name != 'Hentai' && !genres.contains(name)) {
          genres.add(name);
        }
      }
    }

    final studios = (j['studios'] as List? ?? const [])
        .map((s) => (s as Map)['name']?.toString())
        .whereType<String>()
        .toList();

    final english = j['title_english'] as String?;

    return MediaMeta(
      sourceId: j['mal_id'] as int?,
      source: 'jikan',
      title: (english != null && english.trim().isNotEmpty)
          ? english
          : (j['title'] as String? ?? 'Sans titre'),
      titleNative: j['title_japanese'] as String?,
      titleRomaji: j['title'] as String?,
      imageUrl: (webp?['large_image_url'] ??
          jpg?['large_image_url'] ??
          jpg?['image_url']) as String?,
      synopsis: j['synopsis'] as String?,
      genres: genres,
      score: (j['score'] as num?)?.toDouble(),
      popularity: j['members'] as int?,
      year: j['year'] as int? ??
          int.tryParse(
            ((j['aired'] as Map?)?['from'] as String? ?? '').split('-').first,
          ),
      type: j['type'] as String?,
      status: j['status'] as String?,
      episodes: j['episodes'] as int?,
      studios: studios.isEmpty ? null : studios.join(', '),
    );
  }
}
