/// Metadonnees d'un titre, quelle que soit la source (TMDB ou TVmaze).
class MediaMeta {
  final int? sourceId;
  final String source; // 'anilist' ou 'jikan'
  final String title;
  final String? titleNative;
  final String? titleRomaji;
  final String? imageUrl;
  final String? synopsis;
  final List<String> genres;
  final double? score;
  final int? popularity;
  final int? year;
  final String? type;
  final String? status;
  final int? episodes;
  final String? studios;
  final String? certification;

  const MediaMeta({
    this.sourceId,
    required this.source,
    required this.title,
    this.titleNative,
    this.titleRomaji,
    this.imageUrl,
    this.synopsis,
    this.genres = const [],
    this.score,
    this.popularity,
    this.year,
    this.type,
    this.status,
    this.episodes,
    this.studios,
    this.certification,
  });

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'source': source,
        'title': title,
        'titleNative': titleNative,
        'titleRomaji': titleRomaji,
        'imageUrl': imageUrl,
        'synopsis': synopsis,
        'genres': genres,
        'score': score,
        'popularity': popularity,
        'year': year,
        'type': type,
        'status': status,
        'episodes': episodes,
        'studios': studios,
        'certification': certification,
      };

  factory MediaMeta.fromJson(Map<String, dynamic> j) => MediaMeta(
        sourceId: j['sourceId'] as int?,
        source: j['source'] as String? ?? 'anilist',
        title: j['title'] as String? ?? 'Sans titre',
        titleNative: j['titleNative'] as String?,
        titleRomaji: j['titleRomaji'] as String?,
        imageUrl: j['imageUrl'] as String?,
        synopsis: j['synopsis'] as String?,
        genres:
            (j['genres'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        score: (j['score'] as num?)?.toDouble(),
        popularity: j['popularity'] as int?,
        year: j['year'] as int?,
        type: j['type'] as String?,
        status: j['status'] as String?,
        episodes: j['episodes'] as int?,
        studios: j['studios'] as String?,
        certification: j['certification'] as String?,
      );

  /// Contenu destiné au jeune public.
  ///
  /// Deux conditions : de l'animation ou du familial, et une classification
  /// tous publics. L'animation seule ne suffit pas — beaucoup de films
  /// d'animation ne sont pas pour les enfants.
  bool get looksLikeKids {
    final douces = {
      'u', 'tous publics', 'g', 'tv-y', 'tv-y7', 'tv-g', 'pg',
      '0', '3', '6', '7', '10', 'ua',
    };
    final cert = (certification ?? '').toLowerCase().trim();
    final classee = cert.isNotEmpty && douces.contains(cert);

    final familial = genres.any((g) {
      final bas = g.toLowerCase();
      return bas.contains('animation') ||
          bas.contains('familial') ||
          bas.contains('family') ||
          bas.contains('enfant') ||
          bas.contains('kids');
    });

    // Sans classification connue, l'animation seule suffit à proposer le
    // classement — l'utilisateur corrigera d'un geste si besoin.
    return familial && (classee || cert.isEmpty);
  }

  /// Empreinte du titre, pour reperer une serie deja presente sur le disque.
  String get fingerprint =>
      title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Sous-titre affiche dans les listes de resultats.
  String get summaryLine => [
        if (year != null) '$year',
        if (type != null) type!,
        if (episodes != null) '$episodes ep.',
        source == 'tmdb' ? 'TMDB' : 'TVmaze',
      ].join(' · ');
}
