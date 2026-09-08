import 'package:http/http.dart' as http;

import 'http_client.dart';
import 'tmdb_api.dart';
import 'tvmaze_api.dart';

/// Test de connexion : des appels réels, et le message d'erreur affiché
/// tel quel. Sans permission réseau on obtient une SocketException ;
/// avec une clé refusée, un code 401.
class Diagnostics {
  static Future<List<String>> run(String tmdbKey) async {
    return [
      await _simple('Accès Internet', 'https://www.google.com/generate_204'),
      await _tmdb(tmdbKey),
      await _tvmaze(),
    ];
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
    return out;
  }
}
