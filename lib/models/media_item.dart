import 'media_meta.dart';

class Episode {
  final String path;
  final String name;

  /// Saison et numero deduits du chemin et du nom de fichier.
  final int? season;
  final int? number;

  /// OAV, generique, making-of : compte a part, pas dans la numerotation.
  final bool bonus;

  /// Fichiers .srt ou .ass poses a cote de la video.
  final List<String> subtitles;

  /// Fichiers audio separes portant le meme nom : une piste de doublage
  /// livree a part se charge alors avec la video.
  final List<String> externalAudio;

  /// Date du fichier, pour le tri « recemment ajoute ».
  final int? addedAtMs;

  const Episode({
    required this.path,
    required this.name,
    this.season,
    this.number,
    this.bonus = false,
    List<String>? subtitles,
    List<String>? externalAudio,
    this.addedAtMs,
  })  : subtitles = subtitles ?? const [],
        externalAudio = externalAudio ?? const [];

  String get label {
    if (bonus) return name;
    if (number == null) return name;
    return 'Épisode $number';
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'season': season,
        'number': number,
        'bonus': bonus,
        'subtitles': subtitles,
        'externalAudio': externalAudio,
        'addedAtMs': addedAtMs,
      };

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        path: j['path'] as String,
        name: j['name'] as String,
        season: j['season'] as int?,
        number: j['number'] as int?,
        bonus: j['bonus'] as bool? ?? false,
        subtitles:
            (j['subtitles'] as List?)?.map((e) => e.toString()).toList(),
        externalAudio:
            (j['externalAudio'] as List?)?.map((e) => e.toString()).toList(),
        addedAtMs: j['addedAtMs'] as int?,
      );
}

/// Anomalies reperees dans une serie : trous dans la numerotation,
/// fichiers en double, contenus bonus.
class SeriesIssues {
  final Map<int, List<int>> missing;
  final Map<int, List<int>> duplicates;
  final int bonusCount;

  const SeriesIssues(this.missing, this.duplicates, this.bonusCount);

  bool get isEmpty =>
      missing.isEmpty && duplicates.isEmpty && bonusCount == 0;

  int get missingCount =>
      missing.values.fold<int>(0, (sum, l) => sum + l.length);
  int get duplicateCount =>
      duplicates.values.fold<int>(0, (sum, l) => sum + l.length);
}

/// Nature du contenu, qui décide de l'onglet où il apparaît.
enum MediaKind { movie, series, anime }

class MediaItem {
  /// Chemin du dossier : sert d'identifiant unique.
  final String id;

  /// Vrai quand le contenu vit sur un serveur.
  bool get remote => serverId != null;

  /// Film, série ou anime.
  MediaKind kind;

  /// Identifiant du serveur quand le titre est distant, nul s'il est local.
  ///
  /// La source est un attribut, pas une catégorie : un film reste un film
  /// qu'il vienne de la carte SD ou du PC.
  String? serverId;

  /// Contenu adapté au jeune public. Déduit du genre et de la
  /// classification d'âge, mais toujours corrigeable à la main.
  bool kids;

  /// Vrai quand le classement jeunesse a été forcé par l'utilisateur :
  /// une fiche récupérée plus tard ne doit pas écraser son choix.
  bool kidsManual;

  /// Classification d'âge telle que fournie par la source.
  String? certification;

  /// Titre deduit du nom de dossier / fichier.
  String folderTitle;

  /// Titre renvoye par l'API.
  String? apiTitle;
  String? nativeTitle;
  String? romajiTitle;
  String? frenchTitle;

  int? malId;
  String? imageUrl;
  String? posterPath;
  String? synopsisEn;
  String? synopsisTranslated;
  List<String> genres;
  double? score;
  int? popularity;
  String? studios;
  String? metaSource;
  int? year;
  String? type;
  String? status;
  int? episodesCount;

  bool metaFetched;
  bool metaFailed;
  int metaFailCount;
  bool favorite;

  /// Chemins des episodes deja regardes.
  List<String> watchedPaths;

  /// Dernier episode lu et position atteinte, pour la reprise.
  String? lastEpisodePath;
  int lastPositionMs;
  int? lastPlayedAtMs;

  List<Episode> episodes;

  MediaItem({
    required this.id,
    this.kind = MediaKind.series,
    this.serverId,
    this.kids = false,
    this.kidsManual = false,
    this.certification,
    required this.folderTitle,
    this.apiTitle,
    this.nativeTitle,
    this.romajiTitle,
    this.frenchTitle,
    this.malId,
    this.imageUrl,
    this.posterPath,
    this.synopsisEn,
    this.synopsisTranslated,
    List<String>? genres,
    this.score,
    this.popularity,
    this.studios,
    this.metaSource,
    this.year,
    this.type,
    this.status,
    this.episodesCount,
    this.metaFetched = false,
    this.metaFailed = false,
    this.metaFailCount = 0,
    this.favorite = false,
    List<String>? watchedPaths,
    this.lastEpisodePath,
    this.lastPositionMs = 0,
    this.lastPlayedAtMs,
    List<Episode>? episodes,
  })  : genres = genres ?? <String>[],
        watchedPaths = watchedPaths ?? <String>[],
        episodes = episodes ?? <Episode>[];

  String get title =>
      (apiTitle != null && apiTitle!.trim().isNotEmpty) ? apiTitle! : folderTitle;

  String? get synopsis =>
      (synopsisTranslated != null && synopsisTranslated!.trim().isNotEmpty)
          ? synopsisTranslated
          : synopsisEn;

  /// Date du fichier le plus recent de la serie.
  int get newestFileMs {
    var newest = 0;
    for (final e in episodes) {
      if ((e.addedAtMs ?? 0) > newest) newest = e.addedAtMs!;
    }
    return newest;
  }

  /// Titre reduit a l'essentiel, pour reperer les doublons entre dossiers.
  String get fingerprint => (apiTitle ?? folderTitle)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Reprend la progression d'une ancienne version de la meme fiche.
  /// Utilise apres un rescan : le contenu du disque peut changer, ce que
  /// l'utilisateur a deja regarde ne doit pas disparaitre.
  void copyProgressFrom(MediaItem ancien) {
    watchedPaths = [...ancien.watchedPaths];
    lastPlayedAtMs = ancien.lastPlayedAtMs;
    lastEpisodePath = ancien.lastEpisodePath;
    lastPositionMs = ancien.lastPositionMs;
  }

  /// Reconstitue une fiche de metadonnees a partir de ce qui est enregistre.
  MediaMeta toMeta() => MediaMeta(
        sourceId: malId,
        source: metaSource ?? '',
        title: apiTitle ?? folderTitle,
        titleRomaji: romajiTitle,
        titleNative: nativeTitle,
        imageUrl: imageUrl,
        synopsis: synopsisEn,
        genres: genres,
        score: score,
        popularity: popularity,
        year: year,
        type: type,
        status: status,
        episodes: episodesCount,
        studios: studios,
        certification: certification,
      );

  int get watchedCount =>
      episodes.where((e) => watchedPaths.contains(e.path)).length;

  double get progress =>
      episodes.isEmpty ? 0 : watchedCount / episodes.length;

  bool get started => lastPlayedAtMs != null || watchedCount > 0;
  bool get finished => episodes.isNotEmpty && watchedCount == episodes.length;

  bool isWatched(Episode e) => watchedPaths.contains(e.path);

  /// Index du premier episode non vu, ou 0 si la serie est terminee.
  int get firstUnwatchedIndex {
    for (var i = 0; i < episodes.length; i++) {
      if (!watchedPaths.contains(episodes[i].path)) return i;
    }
    return 0;
  }

  /// Episode a relancer : celui qu'on a laisse en cours, sinon le suivant.
  int get resumeIndex {
    if (lastEpisodePath != null) {
      final i = episodes.indexWhere((e) => e.path == lastEpisodePath);
      if (i >= 0 && !watchedPaths.contains(episodes[i].path)) return i;
    }
    return firstUnwatchedIndex;
  }

  Duration get resumePosition {
    if (lastEpisodePath == null) return Duration.zero;
    final i = episodes.indexWhere((e) => e.path == lastEpisodePath);
    if (i < 0 || i != resumeIndex) return Duration.zero;
    return Duration(milliseconds: lastPositionMs);
  }

  /// Saisons presentes, dans l'ordre. La saison 0 regroupe les fichiers
  /// dont aucune saison n'a pu etre deduite.
  List<int> get seasons {
    final set = <int>{};
    for (final e in episodes) {
      if (!e.bonus) set.add(e.season ?? 1);
    }
    final list = set.toList()..sort();
    return list;
  }

  SeriesIssues get issues {
    final bySeason = <int, List<int>>{};
    var bonus = 0;

    for (final e in episodes) {
      if (e.bonus) {
        bonus++;
        continue;
      }
      if (e.number == null) continue;
      bySeason.putIfAbsent(e.season ?? 1, () => []).add(e.number!);
    }

    final missing = <int, List<int>>{};
    final duplicates = <int, List<int>>{};

    bySeason.forEach((season, numbers) {
      final counts = <int, int>{};
      for (final n in numbers) {
        counts[n] = (counts[n] ?? 0) + 1;
      }
      final doubled = counts.entries
          .where((e) => e.value > 1)
          .map((e) => e.key)
          .toList()
        ..sort();
      if (doubled.isNotEmpty) duplicates[season] = doubled;

      final present = counts.keys.toList()..sort();
      if (present.length < 2) return;
      final holes = <int>[];
      for (var n = present.first; n < present.last; n++) {
        if (!counts.containsKey(n)) holes.add(n);
      }
      if (holes.isNotEmpty) missing[season] = holes;
    });

    return SeriesIssues(missing, duplicates, bonus);
  }

  /// Collection a laquelle la serie appartient.
  String get collection {
    if (finished) return 'done';
    if (started) return 'watching';
    return 'todo';
  }

  String get sortKey => title.toLowerCase().replaceAll(RegExp(r'^(the|le|la|les|a|an) '), '');

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'serverId': serverId,
        'kids': kids,
        'kidsManual': kidsManual,
        'certification': certification,
        'folderTitle': folderTitle,
        'apiTitle': apiTitle,
        'nativeTitle': nativeTitle,
        'romajiTitle': romajiTitle,
        'frenchTitle': frenchTitle,
        'malId': malId,
        'imageUrl': imageUrl,
        'posterPath': posterPath,
        'synopsisEn': synopsisEn,
        'synopsisTranslated': synopsisTranslated,
        'genres': genres,
        'score': score,
        'popularity': popularity,
        'studios': studios,
        'metaSource': metaSource,
        'year': year,
        'type': type,
        'status': status,
        'episodesCount': episodesCount,
        'metaFetched': metaFetched,
        'metaFailed': metaFailed,
        'metaFailCount': metaFailCount,
        'favorite': favorite,
        'watchedPaths': watchedPaths,
        'lastEpisodePath': lastEpisodePath,
        'lastPositionMs': lastPositionMs,
        'lastPlayedAtMs': lastPlayedAtMs,
        'episodes': episodes.map((e) => e.toJson()).toList(),
      };

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
        id: j['id'] as String,
        kind: switch (j['kind']) {
          'movie' => MediaKind.movie,
          'anime' => MediaKind.anime,
          _ => MediaKind.series,
        },
        serverId: j['serverId'] as String?,
        kids: j['kids'] as bool? ?? false,
        kidsManual: j['kidsManual'] as bool? ?? false,
        certification: j['certification'] as String?,
        folderTitle: j['folderTitle'] as String? ?? '',
        apiTitle: j['apiTitle'] as String?,
        nativeTitle: j['nativeTitle'] as String?,
        romajiTitle: j['romajiTitle'] as String?,
        frenchTitle: j['frenchTitle'] as String?,
        malId: j['malId'] as int?,
        imageUrl: j['imageUrl'] as String?,
        posterPath: j['posterPath'] as String?,
        synopsisEn: j['synopsisEn'] as String?,
        synopsisTranslated: j['synopsisTranslated'] as String?,
        genres: (j['genres'] as List?)?.map((e) => e.toString()).toList() ?? [],
        score: (j['score'] as num?)?.toDouble(),
        popularity: j['popularity'] as int?,
        studios: j['studios'] as String?,
        metaSource: j['metaSource'] as String?,
        year: j['year'] as int?,
        type: j['type'] as String?,
        status: j['status'] as String?,
        episodesCount: j['episodesCount'] as int?,
        metaFetched: j['metaFetched'] as bool? ?? false,
        metaFailed: j['metaFailed'] as bool? ?? false,
        metaFailCount: j['metaFailCount'] as int? ?? 0,
        favorite: j['favorite'] as bool? ?? false,
        watchedPaths:
            (j['watchedPaths'] as List?)?.map((e) => e.toString()).toList(),
        lastEpisodePath: j['lastEpisodePath'] as String?,
        lastPositionMs: j['lastPositionMs'] as int? ?? 0,
        lastPlayedAtMs: j['lastPlayedAtMs'] as int?,
        episodes: (j['episodes'] as List?)
                ?.map((e) => Episode.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
      );
}
