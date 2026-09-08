import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/media_meta.dart';
import 'http_client.dart';

/// TVmaze : base de séries télévisées, gratuite et sans clé.
/// Sert de secours quand TMDB ne répond pas ou n'est pas configurée.
/// Elle ne connaît que les séries, pas les films.
class TvMazeApi {
  static const String _host = 'api.tvmaze.com';
  static String? lastError;

  static Future<List<MediaMeta>> search(String query, {int limit = 8}) async {
    lastError = null;
    if (query.trim().isEmpty) return const [];
    try {
      final uri = Uri.https(_host, '/search/shows', {'q': query.trim()});
      final res = await http
          .get(uri, headers: AppHttp.headers())
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        lastError = 'HTTP ${res.statusCode}';
        return const [];
      }
      final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
      return list
          .map((e) => _map(Map<String, dynamic>.from(
              (e as Map)['show'] as Map)))
          .whereType<MediaMeta>()
          .take(limit)
          .toList();
    } catch (e) {
      lastError = e.toString();
      return const [];
    }
  }

  /// Séries diffusées aujourd'hui, pour la vue des sorties.
  static Future<List<MediaMeta>> airingToday() async {
    try {
      final uri = Uri.https(_host, '/schedule', {'country': 'FR'});
      final res = await http
          .get(uri, headers: AppHttp.headers())
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        lastError = 'HTTP ${res.statusCode}';
        return const [];
      }
      final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
      final vus = <int>{};
      final out = <MediaMeta>[];
      for (final entry in list) {
        final show = (entry as Map)['show'];
        if (show is! Map) continue;
        final id = show['id'] as int?;
        if (id == null || vus.contains(id)) continue;
        vus.add(id);
        final meta = _map(Map<String, dynamic>.from(show));
        if (meta != null) out.add(meta);
      }
      return out;
    } catch (e) {
      lastError = e.toString();
      return const [];
    }
  }

  static MediaMeta? _map(Map<String, dynamic> show) {
    final name = show['name']?.toString();
    if (name == null || name.trim().isEmpty) return null;

    final image = show['image'] as Map?;
    final premiered = show['premiered']?.toString();
    final rating = ((show['rating'] as Map?)?['average'] as num?)?.toDouble();

    // TVmaze ne fournit qu'un résumé en HTML.
    var resume = show['summary']?.toString();
    if (resume != null) {
      resume = resume.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (resume.isEmpty) resume = null;
    }

    return MediaMeta(
      sourceId: show['id'] as int?,
      source: 'tvmaze',
      title: name,
      imageUrl: (image?['original'] ?? image?['medium']) as String?,
      synopsis: resume,
      genres: (show['genres'] as List? ?? const [])
          .map((g) => g.toString())
          .toList(),
      score: rating,
      year: premiered == null || premiered.length < 4
          ? null
          : int.tryParse(premiered.substring(0, 4)),
      type: 'Série',
      status: show['status']?.toString(),
    );
  }
}
