import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/media_meta.dart';
import 'metadata_service.dart';

/// Base locale embarquee dans l'application : une centaine de series parmi
/// les plus repandues, avec leurs titres en romaji, anglais, francais et
/// japonais. Elle repond instantanement, sans reseau et sans quota, et sert
/// surtout a traduire un nom de dossier francais en titre que les bases
/// en ligne savent reconnaitre.
class SeedDatabase {
  static List<SeedEntry> _entries = [];
  static bool _loaded = false;

  static int get count => _entries.length;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await rootBundle.loadString('assets/seed_anime.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _entries = (data['anime'] as List? ?? [])
          .map((e) => SeedEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      _entries = [];
    }
  }

  /// Cherche la serie correspondant a un nom de dossier.
  /// Renvoie null si aucune entree ne ressemble suffisamment.
  static SeedEntry? match(String folderTitle, {int? episodeCount}) {
    if (_entries.isEmpty || folderTitle.trim().isEmpty) return null;

    SeedEntry? best;
    var bestScore = 0.0;

    for (final entry in _entries) {
      var score = 0.0;
      for (final candidate in entry.allTitles) {
        final value = MetadataService.similarity(folderTitle, candidate);
        if (value > score) score = value;
      }

      // Un nombre de fichiers coherent departage deux titres proches.
      if (episodeCount != null &&
          episodeCount > 0 &&
          entry.episodes != null &&
          entry.episodes! > 0) {
        final diff = (entry.episodes! - episodeCount).abs();
        if (diff == 0) score += 0.08;
        else if (diff <= 2) score += 0.04;
      }

      if (score > bestScore) {
        bestScore = score;
        best = entry;
      }
    }

    return bestScore >= 0.62 ? best : null;
  }
}

class SeedEntry {
  final String romaji;
  final String english;
  final String french;
  final String japanese;
  final List<String> synonyms;
  final int? year;
  final String format;
  final int? episodes;
  final List<String> genres;
  final String summary;

  const SeedEntry({
    required this.romaji,
    required this.english,
    required this.french,
    required this.japanese,
    required this.synonyms,
    required this.year,
    required this.format,
    required this.episodes,
    required this.genres,
    required this.summary,
  });

  factory SeedEntry.fromJson(Map<String, dynamic> j) => SeedEntry(
        romaji: j['romaji'] as String? ?? '',
        english: j['english'] as String? ?? '',
        french: j['french'] as String? ?? '',
        japanese: j['japanese'] as String? ?? '',
        synonyms:
            (j['synonyms'] as List?)?.map((e) => e.toString()).toList() ?? [],
        year: j['year'] as int?,
        format: j['format'] as String? ?? 'TV',
        episodes: j['episodes'] as int?,
        genres: (j['genres'] as List?)?.map((e) => e.toString()).toList() ?? [],
        summary: j['summary'] as String? ?? '',
      );

  List<String> get allTitles => [
        romaji,
        english,
        french,
        japanese,
        ...synonyms,
      ].where((t) => t.trim().isNotEmpty).toList();

  /// Requete a envoyer aux bases en ligne : le romaji donne les meilleurs
  /// resultats, c'est la forme qu'elles indexent toutes.
  String get searchQuery => romaji.isNotEmpty ? romaji : english;

  MediaMeta toMeta() => MediaMeta(
        source: 'local',
        title: english.isNotEmpty ? english : romaji,
        titleRomaji: romaji,
        titleNative: japanese,
        synopsis: summary,
        genres: genres,
        year: year,
        type: format,
        episodes: episodes,
      );
}
