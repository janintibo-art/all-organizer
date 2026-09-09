import 'dart:convert';

import 'package:http/http.dart' as http;

import 'anilist_api.dart';
import 'animethemes_api.dart';
import 'http_client.dart';
import 'jikan_api.dart';
import 'kitsu_api.dart';
import 'tmdb_api.dart';
import 'tvmaze_api.dart';

/// Test de connexion : des appels réels, et le message d'erreur affiché
/// tel quel. Sans permission réseau on obtient une SocketException ;
/// avec une clé refusée, un code 401.
class Diagnostics {
  /// [anime] interroge les bases japonaises a la place de TVmaze : ce sont
  /// elles qui repondent sur l'onglet Animes.
  static Future<List<String>> run(String tmdbKey, {bool anime = false}) async {
    final lines = <String>[
      await _simple('Accès Internet', 'https://www.google.com/generate_204'),
    ];

    if (anime) {
      lines.add(await _anilist());
      lines.add(await _jikan());
      lines.add(await _kitsu());
      lines.add(await _animeThemes());
      lines.add(await _tmdb(tmdbKey));
      return lines;
    }

    lines.add(await _tmdb(tmdbKey));
    lines.add(await _tvmaze());
    return lines;
  }

  static Future<String> _anilist() async {
    try {
      final res = await http
          .post(
            Uri.parse('https://graphql.anilist.co'),
            headers: AppHttp.headers(json: true),
            body: jsonEncode({
              'query':
                  '{Page(page:1,perPage:1){media(type:ANIME){id title{romaji}}}}'
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) {
        return 'AniList : ÉCHEC — HTTP ${res.statusCode} ${res.body}';
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['errors'] != null) {
        return 'AniList : réponse en erreur — ${body['errors']}';
      }
      final media = ((body['data'] as Map?)?['Page'] as Map?)?['media'] as List?;
      if (media == null || media.isEmpty) {
        return 'AniList : répond mais renvoie une liste vide.';
      }
      final title = ((media.first as Map)['title'] as Map)['romaji'];
      return 'AniList : OK — exemple reçu « $title »';
    } catch (e) {
      return 'AniList : ÉCHEC — $e';
    }
  }

  static Future<String> _jikan() async {
    try {
      final res = await http
          .get(Uri.parse('https://api.jikan.moe/v4/anime?q=naruto&limit=1'),
              headers: AppHttp.headers())
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        return 'MyAnimeList : ÉCHEC — HTTP ${res.statusCode}';
      }
      final data =
          (jsonDecode(res.body) as Map<String, dynamic>)['data'] as List?;
      if (data == null || data.isEmpty) {
        return 'MyAnimeList : répond mais renvoie une liste vide.';
      }
      return 'MyAnimeList : OK';
    } catch (e) {
      return 'MyAnimeList : ÉCHEC — $e';
    }
  }

  static Future<String> _kitsu() async {
    final results = await KitsuApi.search('naruto', limit: 1);
    if (results.isEmpty) {
      return 'Kitsu : ÉCHEC — ${KitsuApi.lastError ?? 'aucun résultat'}';
    }
    return 'Kitsu : OK — exemple reçu « ${results.first.title} »';
  }

  static Future<String> _animeThemes() async {
    final results = await AnimeThemesApi.search('naruto', limit: 1);
    if (results.isEmpty) {
      return 'AnimeThemes : ÉCHEC — ${AnimeThemesApi.lastError ?? 'aucun résultat'}';
    }
    return 'AnimeThemes : OK — exemple reçu « ${results.first.title} »';
  }

  static Future<String> _simple(String label, String url) async {
    try {
      final res = await http
          .get(Uri.parse(url), headers: AppHttp.headers())
          .timeout(const Duration(seconds: 15));
      return '$label : OK (HTTP ${res.statusCode})';
    } catch (e) {
      return '$label : ÉCHEC — $e';
    }
  }

  static Future<String> _tmdb(String key) async {
    if (key.trim().isEmpty) {
      return 'TMDB : aucune clé renseignée. C\'est la source principale, '
          'l\'application ne peut presque rien faire sans elle.';
    }
    final results = await TmdbApi.search('matrix', key, limit: 1);
    if (results.isEmpty) {
      return 'TMDB : ÉCHEC — ${TmdbApi.lastError ?? 'aucun résultat'}';
    }
    return 'TMDB : OK — exemple reçu « ${results.first.title} »';
  }

  static Future<String> _tvmaze() async {
    final results = await TvMazeApi.search('breaking bad', limit: 1);
    if (results.isEmpty) {
      return 'TVmaze : ÉCHEC — ${TvMazeApi.lastError ?? 'aucun résultat'}';
    }
    return 'TVmaze : OK — exemple reçu « ${results.first.title} »';
  }

  /// Dernières erreurs mémorisées pendant l'usage normal.
  static List<String> lastErrors() {
    final out = <String>[];
    if (TmdbApi.lastError != null) {
      out.add('Dernière erreur TMDB : ${TmdbApi.lastError}');
    }
    if (TvMazeApi.lastError != null) {
      out.add('Dernière erreur TVmaze : ${TvMazeApi.lastError}');
    }
    if (AniListApi.lastError != null) {
      out.add('Dernière erreur AniList : ${AniListApi.lastError}');
    }
    if (JikanApi.lastError != null) {
      out.add('Dernière erreur MyAnimeList : ${JikanApi.lastError}');
    }
    if (KitsuApi.lastError != null) {
      out.add('Dernière erreur Kitsu : ${KitsuApi.lastError}');
    }
    if (AnimeThemesApi.lastError != null) {
      out.add('Dernière erreur AnimeThemes : ${AnimeThemesApi.lastError}');
    }
    return out;
  }
}
