import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/media_meta.dart';
import '../models/episode_release.dart';
import 'http_client.dart';

/// Troisième source, indépendante d'AniList et de MyAnimeList.
/// Gratuite, sans clé. Sert de filet quand les deux autres tombent.
class KitsuApi {
  /// Kitsu a changé de domaine : on essaie les deux.
  static const List<String> _hosts = ['kitsu.app', 'kitsu.io'];
  static String? lastError;

  static Future<Map<String, dynamic>?> _get(String path, Map<String, String> params) async {
    for (final host in _hosts) {
      try {
        final uri = Uri.https(host, '/api/edge/$path', params);
        final res = await http
            .get(uri, headers: AppHttp.headers(accept: 'application/vnd.api+json'))
            .timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) {
          lastError = 'HTTP ${res.statusCode} ($host)';
          continue;
        }
        return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      } catch (e) {
        lastError = e.toString();
      }
    }
    return null;
  }

  static Future<List<MediaMeta>> search(String title, {int limit = 8}) async {
    if (title.trim().isEmpty) return const [];
    final body = await _get('anime', {
      'filter[text]': title.trim(),
      'page[limit]': '${limit.clamp(1, 20)}',
      'include': 'categories',
    });
    return _parse(body);
  }

  static const Map<String, String> _sortFields = {
    'TRENDING_DESC': '-userCount',
    'POPULARITY_DESC': '-userCount',
    'SCORE_DESC': '-averageRating',
    'START_DATE_DESC': '-startDate',
    'FAVOURITES_DESC': '-favoritesCount',
  };

  /// Kitsu refuse toute page de plus de 20 elements : on borne au lieu de
  /// laisser la requete partir en erreur.
  static Future<List<MediaMeta>> browse({
    int page = 1,
    int perPage = 20,
    String sort = 'TRENDING_DESC',
    String? genre,
    String? format,
  }) async {
    final limit = perPage.clamp(1, 20);
    final params = <String, String>{
      'page[limit]': '$limit',
      'page[offset]': '${(page - 1) * limit}',
      'sort': _sortFields[sort] ?? '-userCount',
      'include': 'categories',
      if (format != null && format.isNotEmpty)
        'filter[subtype]': format.toLowerCase(),
      if (genre != null && genre.isNotEmpty)
        'filter[categories]': genre.toLowerCase().replaceAll(' ', '-'),
    };
    final body = await _get('anime', params);
    return _parse(body);
  }

  /// Derniers episodes diffuses, sur les trente derniers jours.
  static Future<List<EpisodeRelease>> recentEpisodes({int page = 1}) async {
    String jour(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    final today = DateTime.now();
    final from = today.subtract(const Duration(days: 30));

    for (final host in _hosts) {
      try {
        final uri = Uri.https(host, '/api/edge/episodes', {
          'sort': '-airdate',
          'page[limit]': '20',
          'page[offset]': '${(page - 1) * 20}',
          'filter[airdate]': '${jour(from)}..${jour(today)}',
          'include': 'media',
        });
        final res = await http
            .get(uri,
                headers: AppHttp.headers(accept: 'application/vnd.api+json'))
            .timeout(const Duration(seconds: 25));
        if (res.statusCode != 200) {
          lastError = 'HTTP ${res.statusCode} ($host)';
          continue;
        }

        final body =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;

        // Les series arrivent dans la section « included », par identifiant.
        final medias = <String, MediaMeta>{};
        for (final entry in body['included'] as List? ?? const []) {
          final map = entry as Map;
          if (map['type'] != 'anime') continue;
          final meta = _map(Map<String, dynamic>.from(map), const {});
          final id = map['id']?.toString();
          if (meta != null && id != null) medias[id] = meta;
        }

        final out = <EpisodeRelease>[];
        for (final entry in body['data'] as List? ?? const []) {
          final map = entry as Map;
          final attrs = map['attributes'] as Map?;
          final mediaId = (((map['relationships'] as Map?)?['media']
              as Map?)?['data'] as Map?)?['id']?.toString();
          final meta = medias[mediaId];
          if (meta == null) continue;

          out.add(EpisodeRelease(
            anime: meta,
            number: attrs?['number'] as int?,
            airedAt: DateTime.tryParse(attrs?['airdate']?.toString() ?? ''),
          ));
        }
        return out;
      } catch (e) {
        lastError = e.toString();
      }
    }
    return const [];
  }

  static List<MediaMeta> _parse(Map<String, dynamic>? body) {
    if (body == null) return const [];

    // Kitsu suit la norme JSON:API : les genres ne sont pas dans la fiche
    // mais dans une section « included », reliee par identifiant.
    final categories = <String, String>{};
    for (final entry in body['included'] as List? ?? const []) {
      final map = entry as Map;
      if (map['type'] != 'categories') continue;
      final title = (map['attributes'] as Map?)?['title']?.toString();
      final id = map['id']?.toString();
      if (title != null && id != null) categories[id] = title;
    }

    final data = body['data'] as List? ?? const [];
    return data
        .map((e) => _map(Map<String, dynamic>.from(e as Map), categories))
        .whereType<MediaMeta>()
        .toList();
  }

  static MediaMeta? _map(
      Map<String, dynamic> item, Map<String, String> categories) {
    final attrs = item['attributes'] as Map<String, dynamic>?;
    if (attrs == null) return null;

    final titles = attrs['titles'] as Map<String, dynamic>? ?? const {};
    final english = (titles['en'] ?? titles['en_us'])?.toString();
    final romaji = (titles['en_jp'] ?? attrs['canonicalTitle'])?.toString();
    final native = titles['ja_jp']?.toString();
    final name = (english != null && english.trim().isNotEmpty)
        ? english
        : (romaji ?? attrs['canonicalTitle']?.toString());
    if (name == null || name.trim().isEmpty) return null;

    final genres = <String>[];
    final linked = ((item['relationships'] as Map?)?['categories']
        as Map?)?['data'] as List?;
    for (final ref in linked ?? const []) {
      final name = categories[(ref as Map)['id']?.toString()];
      if (name != null && name != 'Hentai' && !genres.contains(name)) {
        genres.add(name);
      }
    }

    final poster = attrs['posterImage'] as Map<String, dynamic>?;
    final rating = double.tryParse(attrs['averageRating']?.toString() ?? '');
    final start = attrs['startDate']?.toString();

    return MediaMeta(
      sourceId: int.tryParse(item['id']?.toString() ?? ''),
      source: 'kitsu',
      title: name,
      titleRomaji: romaji,
      titleNative: native,
      imageUrl: (poster?['large'] ?? poster?['medium'] ?? poster?['original'])
          as String?,
      synopsis: attrs['synopsis']?.toString(),
      genres: genres,
      score: rating == null ? null : rating / 10.0,
      popularity: attrs['userCount'] as int?,
      year: start == null || start.length < 4
          ? null
          : int.tryParse(start.substring(0, 4)),
      type: attrs['subtype']?.toString(),
      status: attrs['status']?.toString(),
      episodes: attrs['episodeCount'] as int?,
    );
  }
}
