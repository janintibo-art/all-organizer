import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/media_item.dart';

/// Parcourt les dossiers choisis par l'utilisateur et regroupe les fichiers
/// video en series.
/// Ce qu'un nom de fichier apprend, avant tout acces au disque.
class EpisodeInfo {
  final int? season;
  final int? number;
  final bool bonus;
  const EpisodeInfo({this.season, this.number, this.bonus = false});
}

class Scanner {
  /// Version destinee a `compute` : le scan tourne dans un isolate et
  /// renvoie du JSON, pour ne jamais figer l'interface.
  static Future<List<Map<String, dynamic>>> scanFoldersJson(
      List<String> roots) async {
    final found = await scanFolders(roots);
    return found.map((a) => a.toJson()).toList();
  }

  static const Set<String> videoExtensions = {
    '.mkv', '.mp4', '.avi', '.mov', '.webm', '.m4v',
    '.flv', '.ts', '.wmv', '.mpg', '.mpeg', '.ogv', '.3gp', '.m2ts',
  };

  static final RegExp _brackets = RegExp(r'\[[^\]]*\]|\([^)]*\)|\{[^}]*\}');
  static final RegExp _tags = RegExp(
    r'\b(vostfr|vosta|vf|vo|multi|hardsub|softsub|subfrench|french|truefrench|'
    r'web-?dl|webrip|bluray|blu-ray|bdrip|brrip|hdrip|dvdrip|hdtv|remux|'
    r'x264|x265|h ?264|h ?265|hevc|avc|aac|ac3|eac3|flac|opus|dts|'
    r'10 ?bits?|8 ?bits?|1080p|720p|480p|360p|2160p|4k|uhd|'
    r'uncensored|censored|repack|proper|final|complete|integrale|vostfr)\b',
    caseSensitive: false,
  );
  static final RegExp _episodeMarks = RegExp(
    r'\b(s\d{1,2} ?e\d{1,3}|saison ?\d{1,2}|season ?\d{1,2}|'
    r'[eé]pisode ?\d{1,3}|ep ?\d{1,3}|vol ?\d{1,3})\b',
    caseSensitive: false,
  );
  static final RegExp _trailingNumber = RegExp(r'[\s\-–—]+\d{1,3}\s*$');
  static final RegExp _spaces = RegExp(r'\s{2,}');
  static final RegExp _edges = RegExp(r'^[\s\-–—_]+|[\s\-–—_]+$');
  static final RegExp _digits = RegExp(r'\d+');

  // Numerotation : du plus explicite au plus approximatif.
  static final RegExp _sxxexx =
      RegExp(r's(\d{1,2})\s*[e_-]\s*(\d{1,3})', caseSensitive: false);
  static final RegExp _seasonWord =
      RegExp(r'(?:saison|season)\s*0*(\d{1,2})', caseSensitive: false);
  static final RegExp _episodeWord = RegExp(
      r'(?:[eé]pisode|ep|e)\s*0*(\d{1,3})\b',
      caseSensitive: false);
  static final RegExp _dashNumber = RegExp(r'[-–—_]\s*0*(\d{1,3})\s*(?:[^\d]|$)');
  static final RegExp _bracketNumber = RegExp(r'[\[(]\s*0*(\d{1,3})\s*[\])]');
  static const Set<String> subtitleExtensions = {
    '.srt', '.ass', '.ssa', '.vtt', '.sub', '.idx'
  };

  static const Set<String> audioExtensions = {
    '.mka', '.aac', '.ac3', '.eac3', '.dts', '.flac', '.mp3', '.opus', '.m4a'
  };

  static final RegExp _bonusWords = RegExp(
      r'\b(oav|ova|ona|nc(?:op|ed)|opening|ending|special|sp\d?|bonus|'
      r'making|pv|trailer|preview|teaser|omake|film|movie)\b',
      caseSensitive: false);

  /// Cherche les sous-titres poses a cote de la video : meme nom de base,
  /// eventuellement suffixe de la langue (« episode 03.fr.srt »).
  static List<String> findSubtitles(String filePath) {
    try {
      final dir = Directory(p.dirname(filePath));
      final base = p.basenameWithoutExtension(filePath).toLowerCase();
      final found = <String>[];
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (!subtitleExtensions.contains(ext)) continue;
        final name = p.basenameWithoutExtension(entity.path).toLowerCase();
        if (name == base || name.startsWith('$base.')) found.add(entity.path);
      }
      found.sort();
      return found;
    } catch (_) {
      return const [];
    }
  }

  /// Cherche les pistes audio livrees a part, meme nom de base.
  static List<String> findExternalAudio(String filePath) {
    try {
      final dir = Directory(p.dirname(filePath));
      final base = p.basenameWithoutExtension(filePath).toLowerCase();
      final found = <String>[];
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (!audioExtensions.contains(ext)) continue;
        final name = p.basenameWithoutExtension(entity.path).toLowerCase();
        if (name == base || name.startsWith('$base.')) found.add(entity.path);
      }
      found.sort();
      return found;
    } catch (_) {
      return const [];
    }
  }

  /// Analyse d'un nom, sans aucun acces au disque.
  ///
  /// Separee de `describe` pour servir aussi aux fichiers distants, dont on
  /// ne connait que le nom et le chemin annonces par le serveur.
  static EpisodeInfo parseName(String name, {String context = ''}) {
    final haystack = '$context $name';
    final bonus = _bonusWords.hasMatch(name);

    int? season;
    int? number;

    final full = _sxxexx.firstMatch(haystack);
    if (full != null) {
      season = int.tryParse(full.group(1)!);
      number = int.tryParse(full.group(2)!);
    } else {
      final seasonMatch = _seasonWord.firstMatch(haystack);
      if (seasonMatch != null) season = int.tryParse(seasonMatch.group(1)!);

      // On cherche le numero dans le nom de fichier seul : un dossier
      // « Naruto 2003 » ne doit pas donner l'episode 2003.
      final cleaned = name.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ');
      final match = _episodeWord.firstMatch(cleaned) ??
          _dashNumber.firstMatch(cleaned) ??
          _bracketNumber.firstMatch(cleaned);
      if (match != null) number = int.tryParse(match.group(1)!);
    }

    return EpisodeInfo(
      season: season,
      number: bonus ? null : number,
      bonus: bonus,
    );
  }

  /// Deduit saison, numero et nature du fichier.
  static Episode describe(String filePath, String rootPath) {
    final name = p.basenameWithoutExtension(filePath);
    final relative = p.relative(filePath, from: rootPath);
    final infos = parseName(name, context: relative);
    final season = infos.season;
    final number = infos.number;
    final bonus = infos.bonus;

    int? modified;
    try {
      modified = File(filePath).statSync().modified.millisecondsSinceEpoch;
    } catch (_) {}

    return Episode(
      path: filePath,
      name: name,
      season: season,
      number: number,
      bonus: bonus,
      subtitles: findSubtitles(filePath),
      externalAudio: findExternalAudio(filePath),
      addedAtMs: modified,
    );
  }

  /// Transforme `[HorribleSubs] Made.in.Abyss - 03 [1080p].mkv`
  /// en `Made in Abyss`.
  static String cleanTitle(String raw) {
    var s = raw;
    s = s.replaceAll(_brackets, ' ');
    s = s.replaceAll(RegExp(r'[._]+'), ' ');
    s = s.replaceAll(_tags, ' ');
    s = s.replaceAll(_episodeMarks, ' ');
    s = s.replaceAll(_trailingNumber, ' ');
    s = s.replaceAll(_spaces, ' ');
    s = s.replaceAll(_edges, '');
    s = s.trim();
    return s.isEmpty ? raw.trim() : s;
  }

  /// Tri naturel : « Episode 2 » avant « Episode 10 ».
  static int naturalCompare(String a, String b) {
    final ma = _digits.allMatches(a).toList();
    final mb = _digits.allMatches(b).toList();
    if (ma.isNotEmpty && mb.isNotEmpty) {
      final pa = a.substring(0, ma.last.start).toLowerCase();
      final pb = b.substring(0, mb.last.start).toLowerCase();
      if (pa == pb) {
        final na = int.tryParse(ma.last.group(0)!) ?? 0;
        final nb = int.tryParse(mb.last.group(0)!) ?? 0;
        if (na != nb) return na.compareTo(nb);
      }
    }
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  /// Dossier de serie : premier niveau sous la racine scannee.
  static String _seriesFolder(String root, String filePath) {
    final rel = p.relative(p.dirname(filePath), from: root);
    if (rel == '.' || rel.isEmpty) return root;
    final first = p.split(rel).first;
    return p.join(root, first);
  }

  static Future<List<MediaItem>> scanFolders(
    List<String> roots, {
    void Function(String message)? onProgress,
  }) async {
    final Map<String, List<File>> groups = {};
    final Map<String, String> titles = {};

    for (final root in roots) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      onProgress?.call('Lecture de ${p.basename(root)}');

      final stream = dir.list(recursive: true, followLinks: false).handleError(
            (Object _) {},
            test: (dynamic e) => e is FileSystemException,
          );

      await for (final entity in stream) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (!videoExtensions.contains(ext)) continue;

        final parent = p.dirname(entity.path);
        String key;
        String title;
        if (p.equals(parent, root)) {
          // Fichier isole a la racine : une entree par fichier.
          title = cleanTitle(p.basenameWithoutExtension(entity.path));
          key = p.join(root, '::$title');
        } else {
          key = _seriesFolder(root, entity.path);
          title = cleanTitle(p.basename(key));
        }
        groups.putIfAbsent(key, () => <File>[]).add(entity);
        titles[key] = title;
      }
    }

    final result = <MediaItem>[];
    groups.forEach((key, files) {
      files.sort((a, b) => naturalCompare(p.basename(a.path), p.basename(b.path)));
      final root = roots.firstWhere(
        (r) => p.isWithin(r, key) || p.equals(r, key),
        orElse: () => key,
      );
      final episodes = files.map((f) => describe(f.path, root)).toList();

      // Tri final : saison, puis numero, puis nom. Les bonus ferment la marche.
      episodes.sort((a, b) {
        if (a.bonus != b.bonus) return a.bonus ? 1 : -1;
        final sa = a.season ?? 1;
        final sb = b.season ?? 1;
        if (sa != sb) return sa.compareTo(sb);
        final na = a.number ?? 9999;
        final nb = b.number ?? 9999;
        if (na != nb) return na.compareTo(nb);
        return naturalCompare(a.name, b.name);
      });

      result.add(
        MediaItem(
          id: key,
          folderTitle: titles[key] ?? p.basename(key),
          episodes: episodes,
        ),
      );
    });

    // Film ou série : un seul fichier sans numéro d'épisode, c'est un film.
    for (final item in result) {
      final numerotes =
          item.episodes.where((e) => !e.bonus && e.number != null).length;
      final saisons = item.episodes
          .where((e) => e.season != null)
          .map((e) => e.season)
          .toSet();
      item.kind = (item.episodes.length <= 1 && numerotes == 0 && saisons.isEmpty)
          ? MediaKind.movie
          : MediaKind.series;
    }

    result.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return result;
  }
}
