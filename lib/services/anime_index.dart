import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/media_meta.dart';
import 'http_client.dart';
import 'metadata_service.dart';

/// Index complet, derive de anime-offline-database (MyAnimeList, AniDB,
/// AniList, Kitsu), reconstruit chaque semaine par le depot GitHub du projet
/// et publie en release. Une fois telecharge, il repond hors connexion.
///
/// Licence des donnees : ODbL 1.0 et CC BY-SA 4.0, manami-project.
class AnimeIndex {
  static const String defaultRepo = 'janintibo-art/anime-organizer';

  static List<IndexEntry> _entries = [];
  static Map<String, dynamic> meta = {};
  static bool _loaded = false;
  static String? lastError;

  static bool get isLoaded => _loaded && _entries.isNotEmpty;
  static int get count => _entries.length;

  static String downloadUrl(String repo) =>
      'https://github.com/$repo/releases/download/index-latest/anime-index.json.gz';

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(p.join(dir.path, 'anime-index.json.gz'));
  }

  static Future<bool> exists() async => (await _file()).existsSync();

  static Future<int> sizeInBytes() async {
    final f = await _file();
    return f.existsSync() ? f.lengthSync() : 0;
  }

  /// Telecharge l'index. Le fichier reste compresse sur le disque.
  static Future<bool> download({
    String repo = defaultRepo,
    void Function(int received, int total)? onProgress,
  }) async {
    lastError = null;
    try {
      final request = http.Request('GET', Uri.parse(downloadUrl(repo)));
      request.headers.addAll(AppHttp.headers(accept: '*/*'));
      final response = await request.send().timeout(const Duration(minutes: 5));

      if (response.statusCode != 200) {
        lastError = 'HTTP ${response.statusCode}. '
            'L\'index n\'a peut-être pas encore été construit sur le dépôt.';
        return false;
      }

      final total = response.contentLength ?? 0;
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        onProgress?.call(bytes.length, total);
      }

      final file = await _file();
      await file.writeAsBytes(bytes, flush: true);
      _loaded = false;
      _entries = [];
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  /// Decompresse et analyse l'index dans un isolate : le fichier fait
  /// plusieurs megaoctets, l'interface ne doit pas se figer.
  static Future<bool> load() async {
    if (_loaded) return _entries.isNotEmpty;
    _loaded = true;
    try {
      final file = await _file();
      if (!file.existsSync()) return false;
      final parsed = await compute(_parseIndex, file.path);
      meta = Map<String, dynamic>.from(parsed['meta'] as Map);
      _entries = (parsed['anime'] as List)
          .map((e) => IndexEntry.fromCompact(Map<String, dynamic>.from(e as Map)))
          .toList();
      return _entries.isNotEmpty;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  static Future<void> remove() async {
    final file = await _file();
    if (file.existsSync()) file.deleteSync();
    _entries = [];
    _loaded = false;
    meta = {};
  }

  /// Cherche la serie correspondant a un nom de dossier.
  ///
  /// Un filtre grossier ecarte d'abord la quasi-totalite des entrees :
  /// comparer finement 40 000 titres a chaque dossier serait trop lent.
  static IndexEntry? match(String folderTitle, {int? episodeCount}) {
    if (_entries.isEmpty) return null;
    final query = MetadataService.stripAccents(folderTitle)
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .trim();
    if (query.length < 3) return null;

    final tokens = query
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 4)
        .toSet();

    IndexEntry? best;
    var bestScore = 0.0;

    for (final entry in _entries) {
      // Filtre : au moins un mot en commun, ou un titre tres court.
      if (tokens.isNotEmpty) {
        var shares = false;
        for (final token in tokens) {
          if (entry.haystack.contains(token)) {
            shares = true;
            break;
          }
        }
        if (!shares) continue;
      }

      var score = 0.0;
      for (final candidate in entry.titles) {
        final value = MetadataService.similarity(folderTitle, candidate);
        if (value > score) score = value;
        if (score >= 0.97) break;
      }

      if (episodeCount != null &&
          episodeCount > 0 &&
          entry.episodes != null &&
          entry.episodes! > 0) {
        final diff = (entry.episodes! - episodeCount).abs();
        if (diff == 0) score += 0.06;
        else if (diff <= 2) score += 0.03;
      }

      if (score > bestScore) {
        bestScore = score;
        best = entry;
      }
    }

    return bestScore >= 0.66 ? best : null;
  }
}

/// Execute dans un isolate.
Map<String, dynamic> _parseIndex(String path) {
  final compressed = File(path).readAsBytesSync();
  final raw = gzip.decode(compressed);
  final data = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
  return {
    'meta': {
      'generated': data['generated'],
      'count': data['count'],
      'source': data['source'],
      'license': data['license'],
    },
    'anime': data['anime'] ?? [],
  };
}

class IndexEntry {
  final String title;
  final List<String> synonyms;
  final String format;
  final int? episodes;
  final int? year;
  final String? picture;
  final List<String> tags;
  final int? anilistId;
  final int? malId;

  /// Tous les titres reunis en minuscules sans accent, pour le filtre rapide.
  final String haystack;

  IndexEntry({
    required this.title,
    required this.synonyms,
    required this.format,
    this.episodes,
    this.year,
    this.picture,
    this.tags = const [],
    this.anilistId,
    this.malId,
  }) : haystack = MetadataService.stripAccents(
          [title, ...synonyms].join(' '),
        ).replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');

  factory IndexEntry.fromCompact(Map<String, dynamic> j) => IndexEntry(
        title: j['t'] as String? ?? '',
        synonyms:
            (j['s'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        format: j['f'] as String? ?? 'UNKNOWN',
        episodes: j['e'] as int?,
        year: j['y'] as int?,
        picture: j['p'] as String?,
        tags: (j['g'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        anilistId: j['a'] as int?,
        malId: j['m'] as int?,
      );

  List<String> get titles => [title, ...synonyms];

  /// Le titre le plus susceptible d'etre reconnu par les bases en ligne.
  String get searchQuery => title;

  MediaMeta toMeta() => MediaMeta(
        sourceId: anilistId ?? malId,
        source: 'index',
        title: title,
        titleRomaji: title,
        imageUrl: picture,
        genres: tags
            .map((t) => t.isEmpty ? t : t[0].toUpperCase() + t.substring(1))
            .toList(),
        year: year,
        type: format,
        episodes: episodes,
      );
}
