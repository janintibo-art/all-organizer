import 'dart:math';

import '../models/media_meta.dart';
import 'anilist_api.dart';
import 'jikan_api.dart';
import 'kitsu_api.dart';
import 'tmdb_api.dart';
import 'tvmaze_api.dart';

/// Choisit la source de métadonnées et retient le meilleur candidat.
///
/// En mode automatique : TMDB d'abord, qui couvre films et séries et rend les
/// textes en français, puis TVmaze pour les séries si elle se tait.
class MetadataService {
  static final RegExp _accents = RegExp('[\u00C0-\u017F]');

  static const Map<String, String> _accentMap = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a',
    'ç': 'c', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i',
    'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o',
    'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
    'ÿ': 'y', 'ñ': 'n', 'œ': 'oe', 'æ': 'ae',
  };

  static String stripAccents(String input) {
    final buffer = StringBuffer();
    for (final ch in input.toLowerCase().split('')) {
      buffer.write(_accentMap[ch] ?? ch);
    }
    return buffer.toString();
  }

  /// Un titre français ne correspond pas toujours au titre original :
  /// on le détecte pour tenter une traduction avant la recherche.
  static bool looksFrench(String title) {
    if (_accents.hasMatch(title)) return true;
    const words = [
      'les', 'des', 'une', 'dans', 'avec', 'pour', 'sont', 'seront',
      'mon', 'ma', 'mes', 'du', 'au', 'aux', 'chez', 'plus', 'tout',
    ];
    final lower = ' ${title.toLowerCase()} ';
    return words.any((w) => lower.contains(' $w '));
  }

  /// Variantes de recherche, de la plus fidèle à la plus large.
  static List<String> variants(String title) {
    final out = <String>[];
    void add(String value) {
      final v = value.trim().replaceAll(RegExp(r'\s{2,}'), ' ');
      if (v.length > 2 && !out.contains(v)) out.add(v);
    }

    add(title);
    final plain = stripAccents(title);
    add(plain);
    add(plain.replaceAll(
        RegExp(r"^(les|le|la|l'|the|un|une)\s+", caseSensitive: false), ''));
    final words = plain.split(RegExp(r'\s+'));
    if (words.length > 3) add(words.take(3).join(' '));
    return out.take(4).toList();
  }

  // ------------------------------------------------------- choix du candidat

  static String _normalize(String input) {
    final plain = stripAccents(input).toLowerCase();
    return plain
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Similarité de Dice sur les paires de lettres : tolérante aux fautes
  /// de frappe et aux mots en plus, contrairement à une égalité stricte.
  static double similarity(String a, String b) {
    final x = _normalize(a);
    final y = _normalize(b);
    if (x.isEmpty || y.isEmpty) return 0;
    if (x == y) return 1;
    if (x.contains(y) || y.contains(x)) return 0.9;

    Set<String> bigrams(String s) {
      final out = <String>{};
      for (var i = 0; i < s.length - 1; i++) {
        out.add(s.substring(i, i + 2));
      }
      return out;
    }

    final bx = bigrams(x);
    final by = bigrams(y);
    if (bx.isEmpty || by.isEmpty) return 0;
    final common = bx.intersection(by).length;
    return 2 * common / (bx.length + by.length);
  }

  /// Note un candidat : ressemblance du titre, nombre d'épisodes cohérent,
  /// et pénalité pour un film proposé face à une série de fichiers.
  static double score(MediaMeta meta, String query, int? fileCount) {
    var best = similarity(query, meta.title);
    if (meta.titleRomaji != null) {
      best = max<double>(best, similarity(query, meta.titleRomaji!));
    }
    if (meta.titleNative != null) {
      best = max<double>(best, similarity(query, meta.titleNative!));
    }

    var total = best * 100;

    final episodes = meta.episodes;
    if (fileCount != null && fileCount > 0 && episodes != null && episodes > 0) {
      final diff = (episodes - fileCount).abs();
      if (diff == 0) {
        total += 25;
      } else if (diff <= 2) {
        total += 12;
      } else if (diff > 12) {
        total -= 12;
      }
    }

    final type = (meta.type ?? '').toLowerCase();
    if (fileCount != null && fileCount > 3 && type.contains('film')) {
      total -= 25;
    }
    if (fileCount == 1 && type.contains('série')) total -= 8;

    if (meta.popularity != null) {
      total += min<double>(meta.popularity! / 40000, 5);
    }
    return total;
  }

  // ------------------------------------------------------------- recherches

  static Future<List<MediaMeta>> searchMany(
    String title, {
    String source = 'auto',
    int limit = 8,
    String tmdbKey = '',
    bool moviesOnly = false,
    bool seriesOnly = false,
    bool anime = false,
  }) async {
    // Un anime ne se cherche pas chez TMDB : AniList, MyAnimeList et Kitsu
    // connaissent les titres romaji, les saisons et les OAV, ce que les
    // bases generalistes rendent mal.
    if (anime) {
      final principal = await AniListApi.searchMany(title, limit: limit);
      if (principal.isNotEmpty) return principal;
      final secours = await JikanApi.searchMany(title, limit: limit);
      if (secours.isNotEmpty) return secours;
      final troisieme = await KitsuApi.search(title, limit: limit);
      if (troisieme.isNotEmpty) return troisieme;
      // Rien du cote japonais : TMDB reste un dernier recours.
    }

    switch (source) {
      case 'tmdb':
        return TmdbApi.search(title, tmdbKey,
            limit: limit, moviesOnly: moviesOnly, seriesOnly: seriesOnly);
      case 'tvmaze':
        return TvMazeApi.search(title, limit: limit);
      default:
        if (tmdbKey.trim().isNotEmpty) {
          final principal = await TmdbApi.search(title, tmdbKey,
              limit: limit, moviesOnly: moviesOnly, seriesOnly: seriesOnly);
          if (principal.isNotEmpty) return principal;
        }
        // TVmaze ne connaît que les séries.
        if (moviesOnly) return const [];
        return TvMazeApi.search(title, limit: limit);
    }
  }

  static Future<MediaMeta?> search(
    String title, {
    String source = 'auto',
    String tmdbKey = '',
    bool moviesOnly = false,
    bool seriesOnly = false,
  }) async {
    final results = await searchMany(
      title,
      source: source,
      limit: 1,
      tmdbKey: tmdbKey,
      moviesOnly: moviesOnly,
      seriesOnly: seriesOnly,
    );
    return results.isEmpty ? null : results.first;
  }

  /// Essaie plusieurs formulations, note tous les candidats et garde le
  /// meilleur. Renvoie null si aucun ne ressemble vraiment au titre.
  static Future<MediaMeta?> smartSearch(
    String title, {
    String source = 'auto',
    int? episodeCount,
    String tmdbKey = '',
    bool moviesOnly = false,
    bool seriesOnly = false,
    bool anime = false,
  }) async {
    MediaMeta? best;
    var bestScore = 0.0;
    var bestSimilarity = 0.0;

    for (final query in variants(title)) {
      final results = await searchMany(
        query,
        source: source,
        limit: 8,
        tmdbKey: tmdbKey,
        moviesOnly: moviesOnly,
        seriesOnly: seriesOnly,
        anime: anime,
      );

      for (final candidate in results) {
        final value = score(candidate, query, episodeCount);
        final sim = max<double>(
          similarity(query, candidate.title),
          candidate.titleRomaji == null
              ? 0.0
              : similarity(query, candidate.titleRomaji!),
        );
        if (value > bestScore) {
          bestScore = value;
          bestSimilarity = sim;
          best = candidate;
        }
      }

      // Une correspondance franche sur la première formulation suffit.
      if (bestSimilarity >= 0.75) return best;
    }

    return bestSimilarity >= 0.32 ? best : null;
  }
}
