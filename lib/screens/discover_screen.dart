import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/media_meta.dart';
import '../services/library_controller.dart';
import '../services/tmdb_api.dart';
import '../services/tvmaze_api.dart';
import 'ai_search_screen.dart';
import 'discover_detail_screen.dart';

/// Catalogue TMDB : films et séries, avec un mode « sorties » pour les
/// séries en cours de diffusion et une liste « à voir ».
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _scroll = ScrollController();
  final _searchController = TextEditingController();

  bool _series = false;
  String _sort = 'popularity.desc';
  int? _genreId;
  bool _kidsOnly = false;
  String _search = '';
  bool _wishlistOnly = false;
  bool _releasesMode = false;

  final List<MediaMeta> _items = [];
  final Set<String> _seen = {};
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
        _loadMore();
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

  String get _apiKey => library.settings.tmdbKey;

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _seen.clear();
      _page = 1;
      _hasNext = true;
      _error = null;
      _notice = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasNext || _wishlistOnly) return;
    setState(() => _loading = true);

    List<MediaMeta> found = const [];
    String? notice;

    if (_apiKey.trim().isEmpty) {
      setState(() {
        _loading = false;
        _hasNext = false;
        _error = 'Renseigne ta clé TMDB dans les réglages pour explorer '
            'le catalogue. Elle est gratuite et prend deux minutes.';
      });
      return;
    }

    if (_search.length >= 2) {
      found = await TmdbApi.search(_search, _apiKey,
          limit: 20, moviesOnly: !_series, seriesOnly: _series);
      _hasNext = false;
    } else if (_releasesMode) {
      found = await TmdbApi.onTheAir(_apiKey, page: _page);
      if (found.isEmpty) {
        found = await TvMazeApi.airingToday();
        if (found.isNotEmpty) notice = 'Liste fournie par TVmaze.';
        _hasNext = false;
      }
    } else {
      found = await TmdbApi.discover(
        _apiKey,
        series: _series,
        page: _page,
        sort: _sort,
        genreId: _genreId,
        kidsOnly: _kidsOnly,
      );
    }

    if (!mounted) return;
    setState(() {
      for (final item in found) {
        final key = '${item.source}-${item.sourceId}-${item.title}';
        if (_seen.contains(key)) continue;
        _seen.add(key);
        _items.add(item);
      }
      _notice = notice;
      if (found.isEmpty) _hasNext = false;
      _page++;
      _loading = false;
      if (_items.isEmpty && !_hasNext) {
        _error = TmdbApi.lastError == null
            ? 'Aucun résultat. Change de filtre ou réessaie plus tard.'
            : 'Catalogue injoignable.\n\n${TmdbApi.lastError}';
      }
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
                  padding: const EdgeInsets.only(left: 11, top: 1),
                  child: Text(
                    _notice ?? 'Catalogue TMDB',
                    style: TextStyle(
                        color: _notice == null ? Palette.muted : Palette.kin,
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
              if (_loading && _items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
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
                                ? 'Ta liste « à voir » est vide.'
                                : (_error ?? 'Chargement du catalogue…'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Palette.muted, height: 1.5),
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
          itemCount: items.length,
          itemBuilder: (context, i) => _tile(items[i]),
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
                        color: Palette.kin,
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        alignment: Alignment.center,
                        child: Text(
                          'Déjà chez toi',
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
              if (meta.genres.isNotEmpty) meta.genres.first,
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
                _releasesMode = false;
              });
              _reload();
            },
            decoration: fieldDecoration(
              hintText: 'Chercher un film ou une série',
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
                _chip(
                  label: _series ? 'Séries' : 'Films',
                  selected: true,
                  onTap: () {
                    setState(() {
                      _series = !_series;
                      _genreId = null;
                      _releasesMode = false;
                    });
                    _reload();
                  },
                ),
                const SizedBox(width: 8),
                _menu(
                  label: TmdbApi.sorts[_sort] ?? 'Populaires',
                  items: TmdbApi.sorts,
                  onSelected: (v) {
                    setState(() {
                      _sort = v;
                      _releasesMode = false;
                    });
                    _reload();
                  },
                ),
                const SizedBox(width: 8),
                _genreMenu(),
                const SizedBox(width: 8),
                _chip(
                  label: 'Jeunesse',
                  selected: _kidsOnly,
                  onTap: () {
                    setState(() {
                      _kidsOnly = !_kidsOnly;
                      _releasesMode = false;
                    });
                    _reload();
                  },
                ),
                const SizedBox(width: 8),
                _chip(
                  label: 'À l\'antenne',
                  selected: _releasesMode,
                  onTap: () {
                    setState(() {
                      _releasesMode = !_releasesMode;
                      _series = true;
                      _wishlistOnly = false;
                    });
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

  Widget _genreMenu() {
    final genres = TmdbApi.genresFor(series: _series);
    final current = _genreId == null
        ? 'Tous genres'
        : (genres[_genreId] ?? 'Tous genres');

    return PopupMenuButton<int>(
      color: Palette.surface,
      constraints: const BoxConstraints(maxHeight: 420, minWidth: 200),
      onSelected: (value) {
        setState(() => _genreId = value == -1 ? null : value);
        _reload();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: -1, child: Text('Tous genres')),
        for (final entry in genres.entries)
          PopupMenuItem(
            value: entry.key,
            child: Text(
              entry.value,
              style: TextStyle(
                  color: _genreId == entry.key ? Palette.shu : Palette.text),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: _genreId == null ? Palette.raised : Palette.shu,
          border:
              Border.all(color: _genreId == null ? Palette.line : Palette.shu),
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(current,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: _genreId == null ? Palette.text : Colors.white)),
            const SizedBox(width: 4),
            Icon(Icons.expand_more,
                size: 16,
                color: _genreId == null ? Palette.muted : Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _menu({
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
