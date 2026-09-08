import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/media_meta.dart';
import '../models/episode_release.dart';
import '../models/labels.dart';
import '../services/anilist_api.dart';
import '../services/jikan_api.dart';
import '../services/animethemes_api.dart';
import '../services/kitsu_api.dart';
import '../services/tmdb_api.dart';
import '../services/library_controller.dart';
import '../services/metadata_service.dart';
import 'ai_search_screen.dart';
import 'discover_detail_screen.dart';

/// Onglet Découvrir : le catalogue AniList, filtrable, avec chargement au fil
/// du défilement. Ce que tu as déjà sur le disque est signalé d'un repère.
class AnimeDiscoverScreen extends StatefulWidget {
  const AnimeDiscoverScreen({super.key});

  @override
  State<AnimeDiscoverScreen> createState() => _AnimeDiscoverScreenState();
}

class _AnimeDiscoverScreenState extends State<AnimeDiscoverScreen> {
  static const Map<String, String> _sorts = {
    'TRENDING_DESC': 'Tendances',
    'POPULARITY_DESC': 'Populaires',
    'SCORE_DESC': 'Mieux notés',
    'START_DATE_DESC': 'Nouveautés',
    'FAVOURITES_DESC': 'Favoris du site',
  };

  static const Map<String, String> _formats = {
    '': 'Tout',
    'TV': 'Séries',
    'MOVIE': 'Films',
    'OVA': 'OAV',
    'ONA': 'ONA',
  };

  final _scroll = ScrollController();
  final _searchController = TextEditingController();

  String _sort = 'TRENDING_DESC';
  String _format = '';
  String _genre = '';
  String _tag = '';
  String _search = '';
  bool _seasonOnly = false;
  bool _wishlistOnly = false;
  bool _releasesMode = false;

  final List<EpisodeRelease> _releases = [];
  final Set<String> _releaseKeys = {};
  int _releasePage = 1;
  bool _releasesLoading = false;
  bool _releasesHasNext = true;
  String? _releasesNotice;

  final List<MediaMeta> _items = [];
  final Set<int> _seen = {};
  int _page = 1;
  bool _loading = false;
  bool _hasNext = true;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >
          _scroll.position.maxScrollExtent - 600) {
        if (_releasesMode) {
          _loadReleases();
        } else {
          _loadMore();
        }
      }
    });
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _seen.clear();
      _page = 1;
      _hasNext = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasNext || _wishlistOnly) return;
    setState(() => _loading = true);

    // Une recherche passe aussi par les secours si AniList est coupe.
    final result = await AniListApi.browse(
      page: _page,
      perPage: 30,
      sort: _sort,
      genre: _genre.isEmpty ? null : _genre,
      tag: _tag.isEmpty ? null : _tag,
      format: _format.isEmpty ? null : _format,
      season: _seasonOnly ? AniListApi.currentSeason() : null,
      seasonYear: _seasonOnly ? DateTime.now().year : null,
      search: _search.length >= 2 ? _search : null,
    );

    // Une recherche doit aussi profiter des sources de secours.
    if (_search.length >= 2 && result.items.isEmpty) {
      final fallback = await MetadataService.searchMany(
        _search,
        source: 'auto',
        limit: 20,
        tmdbKey: library.settings.tmdbKey,
      );
      if (fallback.isNotEmpty && mounted) {
        setState(() {
          for (final item in fallback) {
            final id = item.sourceId;
            if (id != null && _seen.contains(id)) continue;
            if (id != null) _seen.add(id);
            _items.add(item);
          }
          _hasNext = false;
          _loading = false;
          _notice = 'Résultats fournis par les sources de secours.';
        });
        return;
      }
    }

    // AniList muet : on bascule sur MyAnimeList plutot que d'afficher un vide.
    var items = result.items;
    var hasNext = result.hasNext;
    String? notice;
    if (items.isEmpty) {
      final backup = await JikanApi.browse(
        page: _page,
        sort: _sort,
        genre: _genre.isEmpty ? null : _genre,
        format: _format.isEmpty ? null : _format,
      );
      if (backup.isNotEmpty) {
        items = backup;
        hasNext = backup.length >= 20;
        notice = 'AniList ne répond pas, liste fournie par MyAnimeList.';
      } else {
        final third = await KitsuApi.browse(
          page: _page,
          perPage: 20,
          sort: _sort,
          genre: _genre.isEmpty ? null : _genre,
          format: _format.isEmpty ? null : _format,
        );
        if (third.isNotEmpty) {
          items = third;
          hasNext = third.length >= 20;
          notice = 'AniList et MyAnimeList indisponibles, liste fournie par Kitsu.';
        } else {
          final fourth = await AnimeThemesApi.browse(
            page: _page,
            sort: _sort,
            format: _format.isEmpty ? null : _format,
          );
          if (fourth.isNotEmpty) {
            items = fourth;
            hasNext = fourth.length >= 15;
            notice = 'Liste fournie par AnimeThemes.';
          } else if (library.settings.tmdbKey.trim().isNotEmpty) {
            final fifth =
                await TmdbApi.browse(library.settings.tmdbKey, page: _page, sort: _sort);
            if (fifth.isNotEmpty) {
              items = fifth;
              hasNext = fifth.length >= 15;
              notice = 'Liste fournie par TMDB, en français.';
            }
          }
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _notice = notice;
      for (final item in items) {
        final id = item.sourceId;
        if (id != null && _seen.contains(id)) continue;
        if (id != null) _seen.add(id);
        _items.add(item);
      }
      _hasNext = hasNext;
      _page++;
      _loading = false;
      if (_items.isEmpty && !hasNext) {
        final details = [
          if (AniListApi.lastError != null) 'AniList : ${AniListApi.lastError}',
          if (JikanApi.lastError != null)
            'MyAnimeList : ${JikanApi.lastError}',
          if (KitsuApi.lastError != null) 'Kitsu : ${KitsuApi.lastError}',
          if (AnimeThemesApi.lastError != null)
            'AnimeThemes : ${AnimeThemesApi.lastError}',
          if (TmdbApi.lastError != null) 'TMDB : ${TmdbApi.lastError}',
        ].join('\n\n');

        _error = details.isEmpty
            ? 'Aucun résultat. Change de filtre ou réessaie plus tard.'
            : 'Les trois catalogues sont muets.\n\n$details\n\n'
                'Lance « Tester la connexion » dans les réglages.';
      }
    });
  }

  /// Derniers épisodes : AniList d'abord, puis MyAnimeList, puis Kitsu.
  Future<void> _loadReleases() async {
    if (_releasesLoading || !_releasesHasNext) return;
    setState(() => _releasesLoading = true);

    var found = await AniListApi.recentEpisodes(page: _releasePage);
    String? notice;

    if (found.isEmpty) {
      found = await JikanApi.recentEpisodes(page: _releasePage);
      if (found.isNotEmpty) notice = 'Liste fournie par MyAnimeList.';
    }
    if (found.isEmpty) {
      found = await KitsuApi.recentEpisodes(page: _releasePage);
      if (found.isNotEmpty) notice = 'Liste fournie par Kitsu.';
    }

    if (!mounted) return;
    setState(() {
      for (final item in found) {
        if (_releaseKeys.contains(item.key)) continue;
        _releaseKeys.add(item.key);
        _releases.add(item);
      }
      _releasesNotice = notice;
      _releasesHasNext = found.isNotEmpty;
      _releasePage++;
      _releasesLoading = false;
    });
  }

  void _open(MediaMeta meta) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DiscoverDetailScreen(meta: meta)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final items = _wishlistOnly ? library.wishlist : _items;

        if (_releasesMode) return _releasesScaffold();

        return Scaffold(
          appBar: darkAppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(width: 3, height: 18, color: Palette.shu),
                    const SizedBox(width: 8),
                    const Text('Découvrir'),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.only(left: 11, top: 1),
                  child: Text(
                    'AniList · MyAnimeList · Kitsu',
                    style: TextStyle(
                        color: Palette.muted,
                        fontSize: 10.5,
                        letterSpacing: 0.8),
                  ),
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              _filters(),
              if (_notice != null && !_wishlistOnly)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(_notice!,
                      style: TextStyle(
                          color: Palette.kin, fontSize: 11.5)),
                ),
              if (_loading && _items.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 3),
                  child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: Palette.raised,
                      color: Palette.shu),
                ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            _wishlistOnly
                                ? 'Ta liste « à voir » est vide. Ajoute des séries depuis le catalogue.'
                                : (_error ?? 'Chargement du catalogue…'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Palette.muted),
                          ),
                        ),
                      )
                    : _grid(items),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Vue dédiée aux sorties : une liste, pas une grille — la date et le
  /// numéro d'épisode comptent autant que l'affiche.
  Widget _releasesScaffold() {
    return Scaffold(
      appBar: darkAppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(width: 3, height: 18, color: Palette.shu),
                const SizedBox(width: 8),
                const Text('Derniers épisodes'),
              ],
            ),
            Padding(
              padding: EdgeInsets.only(left: 11, top: 1),
              child: Text('Sorties récentes',
                  style: TextStyle(
                      color: Palette.muted,
                      fontSize: 10.5,
                      letterSpacing: 0.8)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Retour au catalogue',
            onPressed: () => setState(() => _releasesMode = false),
            icon: const Icon(Icons.grid_view),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_releasesNotice != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(_releasesNotice!,
                  style: TextStyle(color: Palette.kin, fontSize: 11.5)),
            ),
          if (_releasesLoading && _releases.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Palette.raised,
                  color: Palette.shu),
            ),
          Expanded(
            child: _releases.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _releasesLoading
                            ? 'Recherche des sorties…'
                            : 'Aucune sortie récupérée. Les trois calendriers '
                                'sont peut-être indisponibles.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Palette.muted),
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: _releases.length + (_releasesLoading ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      if (i >= _releases.length) {
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Palette.shu),
                            ),
                          ),
                        );
                      }
                      return _releaseTile(_releases[i]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _releaseTile(EpisodeRelease release) {
    final meta = release.anime;
    final local = library.localMatch(meta);

    return InkWell(
      onTap: () => _open(meta),
      borderRadius: BorderRadius.circular(radiusMd),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(radiusSm),
            child: SizedBox(
              width: 54,
              height: 76,
              child: meta.imageUrl == null
                  ? Container(color: Palette.raised)
                  : CachedNetworkImage(
                      imageUrl: meta.imageUrl!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  meta.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, height: 1.2),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Palette.shu,
                        borderRadius: BorderRadius.circular(radiusSm),
                      ),
                      child: Text(
                        release.episodeLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (release.whenLabel.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(release.whenLabel,
                          style: TextStyle(
                              color: Palette.muted, fontSize: 11.5)),
                    ],
                  ],
                ),
                if (local != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Tu as ${local.episodes.length} fichier(s) de cette série',
                    style: TextStyle(color: Palette.kin, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: Palette.muted, size: 20),
        ],
      ),
    );
  }

  Widget _grid(List<MediaMeta> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 170).floor().clamp(2, 8);
        return GridView.builder(
          controller: _wishlistOnly ? null : _scroll,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 0.52,
            crossAxisSpacing: 14,
            mainAxisSpacing: 18,
          ),
          itemCount: items.length + (_loading && !_wishlistOnly ? columns : 0),
          itemBuilder: (context, i) {
            if (i >= items.length) {
              return Container(
                decoration: BoxDecoration(
                  color: Palette.surface,
                  borderRadius: BorderRadius.circular(radiusMd),
                ),
              );
            }
            return _tile(items[i]);
          },
        );
      },
    );
  }

  Widget _tile(MediaMeta meta) {
    final local = library.localMatch(meta);
    final wished = library.inWishlist(meta);

    return GestureDetector(
      onTap: () => _open(meta),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radiusMd),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (meta.imageUrl != null)
                    CachedNetworkImage(
                      imageUrl: meta.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: Palette.raised),
                      errorWidget: (_, __, ___) =>
                          Container(color: Palette.raised),
                    )
                  else
                    Container(color: Palette.raised),
                  if (meta.score != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Palette.shu,
                          borderRadius: BorderRadius.circular(radiusSm),
                        ),
                        child: Text(
                          meta.score!.toStringAsFixed(1),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  if (local != null)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: const Color(0xE6D6B86A),
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        alignment: Alignment.center,
                        child: Text(
                          'Dans ta bibliothèque',
                          style: TextStyle(
                              color: Palette.ink,
                              fontSize: 10,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  if (wished && local == null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(Icons.bookmark,
                          color: Palette.sakura, size: 20),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            meta.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 13,
                height: 1.25,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2),
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (meta.year != null) '${meta.year}',
              if (meta.genres.isNotEmpty) Labels.genre(meta.genres.first),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: Palette.kin),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- filtres

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) {
              setState(() {
                _search = v.trim();
                _wishlistOnly = false;
              });
              _reload();
            },
            decoration: fieldDecoration(
              hintText: 'Chercher dans le catalogue',
              prefixIcon:
                  Icon(Icons.search, color: Palette.muted, size: 20),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close,
                          color: Palette.muted, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _search = '');
                        _reload();
                      },
                    ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _menu<String>(
                  label: _wishlistOnly
                      ? 'Ma liste'
                      : (_sorts[_sort] ?? 'Tendances'),
                  items: _sorts,
                  onSelected: (v) {
                    setState(() {
                      _sort = v;
                      _wishlistOnly = false;
                    });
                    _reload();
                  },
                ),
                const SizedBox(width: 8),
                _menu<String>(
                  label: _formats[_format] ?? 'Tout',
                  items: _formats,
                  onSelected: (v) {
                    setState(() => _format = v);
                    _reload();
                  },
                ),
                const SizedBox(width: 8),
                _genreMenu(),
                const SizedBox(width: 8),
                _chip(
                  label: 'Saison en cours',
                  selected: _seasonOnly,
                  onTap: () {
                    setState(() => _seasonOnly = !_seasonOnly);
                    _reload();
                  },
                ),
                const SizedBox(width: 8),
                _chip(
                  label: 'Recherche IA',
                  selected: false,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AiSearchScreen()),
                  ),
                ),
                const SizedBox(width: 8),
                _chip(
                  label: 'Derniers épisodes',
                  selected: _releasesMode,
                  onTap: () {
                    setState(() {
                      _releasesMode = !_releasesMode;
                      if (_releasesMode) _wishlistOnly = false;
                    });
                    if (_releasesMode && _releases.isEmpty) _loadReleases();
                  },
                ),
                const SizedBox(width: 8),
                _chip(
                  label: 'Ma liste (${library.wishlist.length})',
                  selected: _wishlistOnly,
                  onTap: () => setState(() => _wishlistOnly = !_wishlistOnly),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Genres et étiquettes dans un seul menu déroulant.
  /// AniList sépare les deux : dix-huit genres figés d'un côté, des
  /// centaines d'étiquettes de l'autre — isekai en fait partie.
  Widget _genreMenu() {
    final current = _tag.isNotEmpty
        ? Labels.genre(_tag)
        : (_genre.isEmpty ? 'Tous genres' : Labels.genre(_genre));

    return PopupMenuButton<String>(
      color: Palette.surface,
      constraints: const BoxConstraints(maxHeight: 420, minWidth: 220),
      onSelected: (value) {
        setState(() {
          if (value == '') {
            _genre = '';
            _tag = '';
          } else if (value.startsWith('g:')) {
            _genre = value.substring(2);
            _tag = '';
          } else {
            _tag = value.substring(2);
            _genre = '';
          }
        });
        _reload();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: '', child: Text('Tous genres')),
        PopupMenuItem(
          enabled: false,
          height: 30,
          child: Text('Genres',
              style: TextStyle(color: Palette.muted, fontSize: 11.5)),
        ),
        for (final g in AniListApi.genreList)
          PopupMenuItem(
            value: 'g:$g',
            child: Text(
              Labels.genre(g),
              style: TextStyle(
                  color: _genre == g ? Palette.shu : Palette.text),
            ),
          ),
        PopupMenuItem(
          enabled: false,
          height: 30,
          child: Text('Thèmes',
              style: TextStyle(color: Palette.muted, fontSize: 11.5)),
        ),
        for (final t in AniListApi.tagList)
          PopupMenuItem(
            value: 't:$t',
            child: Text(
              Labels.genre(t),
              style:
                  TextStyle(color: _tag == t ? Palette.shu : Palette.text),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: (_genre.isEmpty && _tag.isEmpty) ? Palette.raised : Palette.shu,
          border: Border.all(
              color: (_genre.isEmpty && _tag.isEmpty)
                  ? Palette.line
                  : Palette.shu),
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              current,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: (_genre.isEmpty && _tag.isEmpty)
                    ? Palette.text
                    : Colors.white,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more,
                size: 16,
                color: (_genre.isEmpty && _tag.isEmpty)
                    ? Palette.muted
                    : Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _menu<T>({
    required String label,
    required Map<String, String> items,
    required ValueChanged<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      color: Palette.surface,
      onSelected: onSelected,
      itemBuilder: (_) => items.entries
          .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Palette.raised,
          border: Border.all(color: Palette.line),
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    color: Palette.text,
                    fontWeight: FontWeight.w500)),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 16, color: Palette.muted),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Palette.shu : Colors.transparent,
          border: Border.all(color: selected ? Palette.shu : Palette.line),
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : Palette.muted,
          ),
        ),
      ),
    );
  }
}
