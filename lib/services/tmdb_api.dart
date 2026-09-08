import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/media_meta.dart';
import 'http_client.dart';

/// TMDB : source principale de l'application.
///
/// Contrairement aux bases d'animation japonaise, elle couvre films et séries
/// du monde entier, et surtout elle renvoie **titres et synopsis directement
/// en français**, sans passer par un service de traduction.
class TmdbApi {
  static const String _host = 'api.themoviedb.org';
  static const String imageBase = 'https://image.tmdb.org/t/p/w500';
  static const String backdropBase = 'https://image.tmdb.org/t/p/w780';

  /// Page où récupérer une clé gratuite.
  static const String keyUrl = 'https://www.themoviedb.org/settings/api';

  static String? lastError;
  static Map<int, String> _movieGenres = {};
  static Map<int, String> _tvGenres = {};

  static Future<Map<String, dynamic>?> _get(
    String path,
    String apiKey,
    Map<String, String> params,
  ) async {
    lastError = null;
    if (apiKey.trim().isEmpty) {
      lastError = 'Aucune clé TMDB renseignée.';
      return null;
    }
    try {
      final uri = Uri.https(_host, path, {
        'api_key': apiKey.trim(),
        'language': 'fr-FR',
        ...params,
      });
      final res = await http
          .get(uri, headers: AppHttp.headers())
          .timeout(const Duration(seconds: 25));
      if (res.statusCode == 401) {
        lastError = 'Clé TMDB refusée.';
        return null;
      }
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

  static Future<void> ensureGenres(String apiKey) async {
    if (_movieGenres.isNotEmpty && _tvGenres.isNotEmpty) return;
    for (final entry in [
      ['/3/genre/movie/list', 'movie'],
      ['/3/genre/tv/list', 'tv'],
    ]) {
      final body = await _get(entry[0], apiKey, const {});
      final list = body?['genres'] as List? ?? const [];
      final map = {
        for (final g in list)
          (g as Map)['id'] as int: g['name']?.toString() ?? '',
      };
      if (entry[1] == 'movie') {
        _movieGenres = map;
      } else {
        _tvGenres = map;
      }
    }
  }

  /// Recherche tous types confondus, films et séries.
  static Future<List<MediaMeta>> search(
    String query,
    String apiKey, {
    int limit = 10,
    bool moviesOnly = false,
    bool seriesOnly = false,
  }) async {
    if (query.trim().isEmpty) return const [];
    await ensureGenres(apiKey);

    final path = moviesOnly
        ? '/3/search/movie'
        : (seriesOnly ? '/3/search/tv' : '/3/search/multi');

    final body = await _get(path, apiKey, {
      'query': query.trim(),
      'include_adult': 'false',
    });
    final results = body?['results'] as List? ?? const [];

    return results
        .map((e) => _map(Map<String, dynamic>.from(e as Map)))
        .whereType<MediaMeta>()
        .take(limit)
        .toList();
  }

  static const Map<String, String> sorts = {
    'popularity.desc': 'Populaires',
    'vote_average.desc': 'Mieux notés',
    'primary_release_date.desc': 'Nouveautés',
    'revenue.desc': 'Plus gros succès',
  };

  /// Parcours du catalogue, pour l'onglet Découvrir.
  static Future<List<MediaMeta>> discover(
    String apiKey, {
    bool series = false,
    int page = 1,
    String sort = 'popularity.desc',
    int? genreId,
    bool kidsOnly = false,
    int? year,
  }) async {
    await ensureGenres(apiKey);

    // TMDB n'accepte pas le même champ de tri pour les films et les séries.
    var effectiveSort = sort;
    if (series && sort == 'primary_release_date.desc') {
      effectiveSort = 'first_air_date.desc';
    }

    final body = await _get(
      series ? '/3/discover/tv' : '/3/discover/movie',
      apiKey,
      {
        'sort_by': effectiveSort,
        'page': '$page',
        'include_adult': 'false',
        'vote_count.gte': sort == 'vote_average.desc' ? '200' : '20',
        if (genreId != null) 'with_genres': '$genreId',
        if (year != null)
          series ? 'first_air_date_year' : 'primary_release_year': '$year',
        if (kidsOnly) 'certification_country': 'FR',
        if (kidsOnly && !series) 'certification.lte': 'U',
      },
    );

    final results = body?['results'] as List? ?? const [];
    return results
        .map((e) => _map(Map<String, dynamic>.from(e as Map), forceSeries: series))
        .whereType<MediaMeta>()
        .toList();
  }

  /// Séries diffusées ces jours-ci.
  static Future<List<MediaMeta>> onTheAir(String apiKey, {int page = 1}) async {
    await ensureGenres(apiKey);
    final body = await _get('/3/tv/on_the_air', apiKey, {'page': '$page'});
    final results = body?['results'] as List? ?? const [];
    return results
        .map((e) => _map(Map<String, dynamic>.from(e as Map), forceSeries: true))
        .whereType<MediaMeta>()
        .toList();
  }

  /// Détails complets, dont la classification d'âge française.
  static Future<MediaMeta?> details(
    int id,
    bool series,
    String apiKey,
  ) async {
    await ensureGenres(apiKey);
    final body = await _get(
      series ? '/3/tv/$id' : '/3/movie/$id',
      apiKey,
      {'append_to_response': series ? 'content_ratings' : 'release_dates'},
    );
    if (body == null) return null;

    final meta = _map(body, forceSeries: series);
    if (meta == null) return null;

    return MediaMeta(
      sourceId: meta.sourceId,
      source: meta.source,
      title: meta.title,
      titleRomaji: meta.titleRomaji,
      titleNative: meta.titleNative,
      imageUrl: meta.imageUrl,
      synopsis: meta.synopsis,
      genres: meta.genres,
      score: meta.score,
      popularity: meta.popularity,
      year: meta.year,
      type: series ? 'Série' : 'Film',
      status: body['status']?.toString(),
      episodes: body['number_of_episodes'] as int?,
      studios: (body['production_companies'] as List? ?? const [])
          .take(2)
          .map((c) => (c as Map)['name']?.toString() ?? '')
          .where((c) => c.isNotEmpty)
          .join(', '),
      certification: _certification(body, series),
    );
  }

  /// Cherche la classification française, sinon américaine.
  static String? _certification(Map<String, dynamic> body, bool series) {
    try {
      if (series) {
        final list =
            (body['content_ratings'] as Map?)?['results'] as List? ?? const [];
        String? fallback;
        for (final entry in list) {
          final map = entry as Map;
          final country = map['iso_3166_1']?.toString();
          final rating = map['rating']?.toString();
          if (rating == null || rating.isEmpty) continue;
          if (country == 'FR') return rating;
          if (country == 'US') fallback = rating;
        }
        return fallback;
      }

      final list =
          (body['release_dates'] as Map?)?['results'] as List? ?? const [];
      String? fallback;
      for (final entry in list) {
        final map = entry as Map;
        final country = map['iso_3166_1']?.toString();
        for (final release in map['release_dates'] as List? ?? const []) {
          final cert = (release as Map)['certification']?.toString();
          if (cert == null || cert.isEmpty) continue;
          if (country == 'FR') return cert;
          if (country == 'US') fallback ??= cert;
        }
      }
      return fallback;
    } catch (_) {
      return null;
    }
  }

  static MediaMeta? _map(Map<String, dynamic> item, {bool? forceSeries}) {
    // « multi » mélange films, séries et personnes.
    final mediaType = item['media_type']?.toString();
    if (mediaType == 'person') return null;

    final series = forceSeries ??
        (mediaType == 'tv' || item.containsKey('first_air_date'));

    final title =
        (series ? item['name'] : item['title'])?.toString() ??
            item['name']?.toString() ??
            item['title']?.toString();
    if (title == null || title.trim().isEmpty) return null;

    final date =
        (series ? item['first_air_date'] : item['release_date'])?.toString();
    final poster = item['poster_path']?.toString();
    final vote = (item['vote_average'] as num?)?.toDouble();

    final genreMap = series ? _tvGenres : _movieGenres;
    final genres = <String>[];
    for (final g in item['genre_ids'] as List? ?? const []) {
      final name = genreMap[g as int];
      if (name != null && name.isNotEmpty) genres.add(name);
    }
    for (final g in item['genres'] as List? ?? const []) {
      final name = (g as Map)['name']?.toString();
      if (name != null && name.isNotEmpty && !genres.contains(name)) {
        genres.add(name);
      }
    }

    return MediaMeta(
      sourceId: item['id'] as int?,
      source: 'tmdb',
      title: title,
      titleRomaji: item['original_title']?.toString() ??
          item['original_name']?.toString(),
      imageUrl:
          poster == null || poster.isEmpty ? null : '$imageBase$poster',
      synopsis: item['overview']?.toString(),
      genres: genres,
      score: vote == null || vote == 0 ? null : vote,
      popularity: (item['popularity'] as num?)?.round(),
      year: date == null || date.length < 4
          ? null
          : int.tryParse(date.substring(0, 4)),
      type: series ? 'Série' : 'Film',
    );
  }

  /// Titres proches, proposés par TMDB.
  static Future<List<MediaMeta>> recommendations(
    int id,
    bool series,
    String apiKey,
  ) async {
    await ensureGenres(apiKey);
    final body = await _get(
      series ? '/3/tv/$id/recommendations' : '/3/movie/$id/recommendations',
      apiKey,
      const {},
    );
    final results = body?['results'] as List? ?? const [];
    return results
        .map((e) => _map(Map<String, dynamic>.from(e as Map),
            forceSeries: series))
        .whereType<MediaMeta>()
        .take(12)
        .toList();
  }

  static Map<int, String> genresFor({required bool series}) =>
      series ? _tvGenres : _movieGenres;
}
