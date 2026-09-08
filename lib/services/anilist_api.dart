import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/media_meta.dart';
import '../models/episode_release.dart';
import 'http_client.dart';

export '../models/media_meta.dart';

/// AniList (GraphQL, gratuit, sans cle). Plus complet et plus rapide que
/// Jikan : une seule requete ramene image, description, genres, note,
/// popularite et studios. Limite officielle : 90 requetes par minute.
class BrowsePage {
  final List<MediaMeta> items;
  final bool hasNext;
  const BrowsePage(this.items, this.hasNext);
}

class AniListApi {
  /// Derniere erreur rencontree, pour le diagnostic des reglages.
  static String? lastError;

  /// Quand AniList repond 403, elle est coupee cote serveur. On evite de la
  /// solliciter en boucle : chaque appel couterait une seconde pour rien.
  static DateTime? _pausedUntil;

  static bool get isPaused =>
      _pausedUntil != null && DateTime.now().isBefore(_pausedUntil!);

  static void _pause() {
    _pausedUntil = DateTime.now().add(const Duration(minutes: 30));
  }

  static const String _url = 'https://graphql.anilist.co';
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minGap = Duration(milliseconds: 700);

  static const String _fields = r'''
      id
      title{romaji english native}
      coverImage{large medium}
      description(asHtml:false)
      genres episodes averageScore popularity seasonYear status format
      studios(isMain:true){nodes{name}}
''';

  /// Genres proposes par AniList, dans l'ordre du site.
  static const List<String> genreList = [
    'Action', 'Adventure', 'Comedy', 'Drama', 'Ecchi', 'Fantasy',
    'Horror', 'Mahou Shoujo', 'Mecha', 'Music', 'Mystery', 'Psychological',
    'Romance', 'Sci-Fi', 'Slice of Life', 'Sports', 'Supernatural', 'Thriller',
  ];

  /// Etiquettes AniList : bien plus fines que les genres, et c'est la que
  /// se trouvent isekai, reincarnation, voyage temporel et le reste.
  static const List<String> tagList = [
    'Isekai',
    'Reincarnation',
    'Time Manipulation',
    'Revenge',
    'Survival',
    'Super Power',
    'Martial Arts',
    'Magic',
    'Demons',
    'Gods',
    'Vampire',
    'Zombie',
    'Ninja',
    'Samurai',
    'Pirates',
    'Space',
    'Robots',
    'Cyberpunk',
    'Steampunk',
    'Kaiju',
    'Dragons',
    'Assassins',
    'Crime',
    'War',
    'Politics',
    'Cooking',
    'Idol',
    'Video Games',
    'Mythology',
    'Detective',
    'Post-Apocalyptic',
    'Coming of Age',
    'Tragedy',
    'Love Triangle',
    'Family Life',
    'Female Protagonist',
    'Male Protagonist',
    'Ensemble Cast',
    'Parody',
    'Philosophy',
  ];

  /// Saison en cours, au sens d'AniList.
  static String currentSeason([DateTime? now]) {
    final month = (now ?? DateTime.now()).month;
    if (month <= 3) return 'WINTER';
    if (month <= 6) return 'SPRING';
    if (month <= 9) return 'SUMMER';
    return 'FALL';
  }

  static const String _query = r'''
query($search:String,$perPage:Int){
  Page(page:1,perPage:$perPage){
    media(search:$search,type:ANIME,isAdult:false,sort:SEARCH_MATCH){
      id
      title{romaji english native}
      coverImage{large medium}
      description(asHtml:false)
      genres episodes averageScore popularity seasonYear status format
      studios(isMain:true){nodes{name}}
    }
  }
}''';

  static Future<void> _throttle() async {
    final elapsed = DateTime.now().difference(_last);
    if (elapsed < _minGap) await Future<void>.delayed(_minGap - elapsed);
    _last = DateTime.now();
  }

  /// Parcourt le catalogue : c'est ce qui alimente l'onglet Decouvrir.
  static Future<BrowsePage> browse({
    int page = 1,
    int perPage = 30,
    String sort = 'TRENDING_DESC',
    String? genre,
    String? tag,
    String? format,
    String? season,
    int? seasonYear,
    String? search,
  }) async {
    const query = r'''
query($page:Int,$perPage:Int,$sort:[MediaSort],$genre:String,$tag:String,$format:MediaFormat,$season:MediaSeason,$seasonYear:Int,$search:String){
  Page(page:$page,perPage:$perPage){
    pageInfo{hasNextPage}
    media(type:ANIME,isAdult:false,sort:$sort,genre:$genre,tag:$tag,format:$format,season:$season,seasonYear:$seasonYear,search:$search){
      id
      title{romaji english native}
      coverImage{large medium}
      description(asHtml:false)
      genres episodes averageScore popularity seasonYear status format
      studios(isMain:true){nodes{name}}
    }
  }
}''';

    if (isPaused) return const BrowsePage([], false);

    final variables = <String, dynamic>{
      'page': page,
      'perPage': perPage,
      'sort': [search != null && search.isNotEmpty ? 'SEARCH_MATCH' : sort],
      if (genre != null && genre.isNotEmpty) 'genre': genre,
      if (tag != null && tag.isNotEmpty) 'tag': tag,
      if (format != null && format.isNotEmpty) 'format': format,
      if (season != null && season.isNotEmpty) 'season': season,
      if (seasonYear != null) 'seasonYear': seasonYear,
      if (search != null && search.isNotEmpty) 'search': search,
    };

    for (var attempt = 0; attempt < 3; attempt++) {
      await _throttle();
      try {
        final res = await http
            .post(
              Uri.parse(_url),
              headers: AppHttp.headers(json: true),
              body: jsonEncode({'query': query, 'variables': variables}),
            )
            .timeout(const Duration(seconds: 25));

        if (res.statusCode == 429) {
          final retry =
              double.tryParse(res.headers['retry-after'] ?? '') ?? (2 + attempt);
          if (retry > 25) return const BrowsePage([], false);
          await Future<void>.delayed(
              Duration(milliseconds: (retry * 1000).round()));
          continue;
        }
        if (res.statusCode != 200) {
          lastError = 'HTTP ${res.statusCode} : ${res.body}';
          if (res.statusCode == 403) _pause();
          return const BrowsePage([], false);
        }

        final body =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final pageData = (body['data'] as Map?)?['Page'] as Map?;
        final media = pageData?['media'] as List? ?? const [];
        final hasNext =
            (pageData?['pageInfo'] as Map?)?['hasNextPage'] as bool? ?? false;
        final items = media
            .map((e) => _map(Map<String, dynamic>.from(e as Map)))
            .whereType<MediaMeta>()
            .toList();
        return BrowsePage(items, hasNext);
      } catch (e) {
        lastError = e.toString();
        await Future<void>.delayed(Duration(seconds: 1 + attempt));
      }
    }
    return const BrowsePage([], false);
  }

  /// Derniers episodes diffuses, le plus recent en tete.
  static Future<List<EpisodeRelease>> recentEpisodes({int page = 1}) async {
    if (isPaused) return const [];

    const query = r'''
query($page:Int,$perPage:Int,$before:Int){
  Page(page:$page,perPage:$perPage){
    airingSchedules(airingAt_lesser:$before,sort:TIME_DESC){
      episode
      airingAt
      media{
        id
        title{romaji english native}
        coverImage{large medium}
        description(asHtml:false)
        genres episodes averageScore popularity seasonYear status format
        isAdult
        studios(isMain:true){nodes{name}}
      }
    }
  }
}''';

    await _throttle();
    try {
      final res = await http
          .post(
            Uri.parse(_url),
            headers: AppHttp.headers(json: true),
            body: jsonEncode({
              'query': query,
              'variables': {
                'page': page,
                'perPage': 30,
                'before': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              },
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode != 200) {
        lastError = 'HTTP ${res.statusCode}';
        if (res.statusCode == 403) _pause();
        return const [];
      }

      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final schedules =
          ((body['data'] as Map?)?['Page'] as Map?)?['airingSchedules'] as List? ??
              const [];

      final out = <EpisodeRelease>[];
      for (final item in schedules) {
        final map = item as Map;
        final media = map['media'] as Map?;
        if (media == null || media['isAdult'] == true) continue;
        final meta = _map(Map<String, dynamic>.from(media));
        if (meta == null) continue;
        final airing = map['airingAt'];
        out.add(EpisodeRelease(
          anime: meta,
          number: map['episode'] as int?,
          airedAt: airing is int
              ? DateTime.fromMillisecondsSinceEpoch(airing * 1000)
              : null,
        ));
      }
      return out;
    } catch (e) {
      lastError = e.toString();
      return const [];
    }
  }

  /// Series proches, proposees par AniList.
  static Future<List<MediaMeta>> recommendations(int id) async {
    const query = r'''
query($id:Int){
  Media(id:$id,type:ANIME){
    recommendations(perPage:12,sort:RATING_DESC){
      nodes{
        mediaRecommendation{
          id
          title{romaji english native}
          coverImage{large medium}
          description(asHtml:false)
          genres episodes averageScore popularity seasonYear status format
          studios(isMain:true){nodes{name}}
        }
      }
    }
  }
}''';
    await _throttle();
    try {
      final res = await http
          .post(
            Uri.parse(_url),
            headers: AppHttp.headers(json: true),
            body: jsonEncode({
              'query': query,
              'variables': {'id': id}
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final nodes = (((body['data'] as Map?)?['Media'] as Map?)?['recommendations']
              as Map?)?['nodes'] as List? ??
          const [];
      return nodes
          .map((n) => (n as Map)['mediaRecommendation'])
          .whereType<Map>()
          .map((m) => _map(Map<String, dynamic>.from(m)))
          .whereType<MediaMeta>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<MediaMeta?> search(String title) async {
    final list = await searchMany(title, limit: 1);
    return list.isEmpty ? null : list.first;
  }

  static Future<List<MediaMeta>> searchMany(String title, {int limit = 8}) async {
    final query = title.trim();
    if (query.isEmpty || isPaused) return const [];

    for (var attempt = 0; attempt < 3; attempt++) {
      await _throttle();
      try {
        final res = await http
            .post(
              Uri.parse(_url),
              headers: AppHttp.headers(json: true),
              body: jsonEncode({
                'query': _query,
                'variables': {'search': query, 'perPage': limit},
              }),
            )
            .timeout(const Duration(seconds: 20));

        if (res.statusCode == 429) {
          final retry =
              double.tryParse(res.headers['retry-after'] ?? '') ?? (2 + attempt);
          if (retry > 20) return const [];
          await Future<void>.delayed(
              Duration(milliseconds: (retry * 1000).round()));
          continue;
        }
        if (res.statusCode != 200) {
          lastError = 'HTTP ${res.statusCode}';
          if (res.statusCode == 403) _pause();
          return const [];
        }

        final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final page = (body['data'] as Map?)?['Page'] as Map?;
        final media = page?['media'] as List? ?? const [];
        return media
            .map((e) => _map(Map<String, dynamic>.from(e as Map)))
            .whereType<MediaMeta>()
            .toList();
      } catch (e) {
        lastError = e.toString();
        await Future<void>.delayed(Duration(seconds: 1 + attempt));
      }
    }
    return const [];
  }

  static const Map<String, String> _statusLabels = {
    'FINISHED': 'Terminé',
    'RELEASING': 'En cours',
    'NOT_YET_RELEASED': 'À venir',
    'CANCELLED': 'Annulé',
    'HIATUS': 'En pause',
  };

  static MediaMeta? _map(Map<String, dynamic> m) {
    final titles = m['title'] as Map<String, dynamic>? ?? const {};
    final romaji = titles['romaji'] as String?;
    final english = titles['english'] as String?;
    final name = (english != null && english.trim().isNotEmpty) ? english : romaji;
    if (name == null || name.trim().isEmpty) return null;

    final genres = (m['genres'] as List? ?? const [])
        .map((e) => e.toString())
        .where((g) => g != 'Hentai')
        .toList();

    final cover = m['coverImage'] as Map<String, dynamic>?;
    final studioNodes =
        ((m['studios'] as Map?)?['nodes'] as List? ?? const []).map((e) => (e as Map)['name']).toList();
    final score = (m['averageScore'] as num?);

    return MediaMeta(
      sourceId: m['id'] as int?,
      source: 'anilist',
      title: name,
      titleNative: titles['native'] as String?,
      titleRomaji: romaji,
      imageUrl: (cover?['large'] ?? cover?['medium']) as String?,
      synopsis: _stripHtml(m['description'] as String?),
      genres: genres,
      score: score == null ? null : score / 10.0,
      popularity: m['popularity'] as int?,
      year: m['seasonYear'] as int?,
      type: m['format'] as String?,
      status: _statusLabels[m['status'] as String? ?? ''] ?? m['status'] as String?,
      episodes: m['episodes'] as int?,
      studios: studioNodes.isEmpty ? null : studioNodes.join(', '),
    );
  }

  /// AniList renvoie parfois des balises <br> et <i> dans la description.
  static String? _stripHtml(String? raw) {
    if (raw == null) return null;
    var s = raw.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    s = s.replaceAll('&quot;', '"').replaceAll('&amp;', '&');
    s = s.replaceAll('&#039;', "'").replaceAll('&mdash;', '—');
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return s.isEmpty ? null : s;
  }
}
