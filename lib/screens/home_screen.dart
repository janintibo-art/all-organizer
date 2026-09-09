import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';
import '../models/media_item.dart';
import '../services/library_controller.dart';
import '../widgets/media_card.dart';
import 'detail_screen.dart';
import 'anime_discover_screen.dart';
import 'discover_screen.dart';
import 'folder_picker_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  /// Nature affichée par cet onglet. Nul pour l'onglet Jeunesse,
  /// qui mélange films et séries.
  final MediaKind? kind;
  final bool kidsOnly;
  final String title;
  final String subtitle;

  /// Bannière propre à la section : on retrouve l'identité de l'application
  /// d'origine en entrant dans Animes, Films ou Séries.
  final String logo;

  const HomeScreen({
    super.key,
    this.kind,
    this.kidsOnly = false,
    this.title = 'All Organizer',
    this.subtitle = '',
    this.logo = 'assets/logo.png',
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String _genre = '';
  bool _favoritesOnly = false;
  String _collection = ''; // '' | todo | watching | done

  bool get _filtering =>
      _query.isNotEmpty ||
      _genre.isNotEmpty ||
      _favoritesOnly ||
      _collection.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startupScan());
  }

  Future<void> _startupScan() async {
    if (library.folders.isEmpty) return;
    await library.startupScan();
    if (!mounted) return;

    final messages = <String>[];
    if (library.lastNewCount > 0) {
      messages.add(library.lastNewCount == 1
          ? '1 nouvelle série ajoutée'
          : '${library.lastNewCount} nouvelles séries ajoutées');
    }
    if (library.unreachableFolders.isNotEmpty) {
      messages.add(
          '${library.unreachableFolders.length} dossier(s) injoignable(s), fiches conservées');
    }
    if (messages.isEmpty) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(messages.join(' · '))));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _ensurePermissions() async {
    if (!Platform.isAndroid) return;
    await Permission.videos.request();
    await Permission.storage.request();
    if (!await Permission.manageExternalStorage.isGranted) {
      await Permission.manageExternalStorage.request();
    }
  }

  Future<void> _addFolder() async {
    await _ensurePermissions();
    if (!mounted) return;
    final dir = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const FolderPickerScreen()),
    );
    if (dir == null) return;
    await library.addFolder(dir,
        kind: widget.kind ?? MediaKind.movie, kids: widget.kidsOnly);
    await library.scan();
  }

  void _open(MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailScreen(item: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
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
                    Text(widget.title),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 11, top: 1),
                  child: Text(
                    _countLabel(),
                    style: TextStyle(
                      color: Palette.muted,
                      fontSize: 10.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Relancer le scan',
                onPressed: library.busy ? null : () => library.scan(),
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Découvrir',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => widget.kind == MediaKind.anime
                        ? const AnimeDiscoverScreen()
                        : DiscoverScreen(
                            series: widget.kind == MediaKind.series,
                            kidsOnly: widget.kidsOnly,
                          ),
                  ),
                ),
                icon: const Icon(Icons.explore_outlined),
              ),
              IconButton(
                tooltip: 'Réglages',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                      section: widget.kind == MediaKind.anime
                          ? SettingsSection.anime
                          : SettingsSection.video,
                    ),
                  ),
                ),
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
          floatingActionButton: library.items.isEmpty
              ? null
              : FloatingActionButton(
                  onPressed: library.busy ? null : _addFolder,
                  backgroundColor: Palette.shu,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.create_new_folder_outlined),
                ),
          body: library.items.isEmpty && !library.busy
              ? _emptyState()
              : Column(
                  children: [
                    if (library.busy) _progressBar(),
                    if (library.items.isNotEmpty) _filters(),
                    Expanded(child: _content()),
                  ],
                ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- contenu

  /// Décompte propre à l'onglet, plutôt qu'un total global trompeur.
  String _countLabel() {
    final total = library.view(
      kind: widget.kind,
      kidsOnly: widget.kidsOnly,
      excludeKids: !widget.kidsOnly,
    ).length;
    if (total == 0) return widget.subtitle;
    final fichiers = library
        .view(
          kind: widget.kind,
          kidsOnly: widget.kidsOnly,
          excludeKids: !widget.kidsOnly,
        )
        .fold<int>(0, (sum, a) => sum + a.episodes.length);
    final nom = widget.kidsOnly
        ? 'titre'
        : (widget.kind == MediaKind.movie ? 'film' : 'série');
    final pluriel = total > 1 ? (nom == 'série' ? 's' : 's') : '';
    return '$total $nom$pluriel · $fichiers fichier${fichiers > 1 ? 's' : ''}';
  }

  Widget _content() {
    var items = library.view(
      query: _query,
      genre: _genre,
      favoritesOnly: _favoritesOnly,
      kind: widget.kind,
      kidsOnly: widget.kidsOnly,
      excludeKids: !widget.kidsOnly,
    );
    if (_collection.isNotEmpty) {
      items = items.where((a) => a.collection == _collection).toList();
    }

    if (items.isEmpty) {
      return Center(
        child: Text('Aucune série ne correspond à ce filtre.',
            style: TextStyle(color: Palette.muted)),
      );
    }

    final resume = library.continueWatching;
    final favorites = library.favorites;
    final showSections = !_filtering && library.settings.viewMode != 'genre';

    return CustomScrollView(
      slivers: [
        if (showSections && resume.isNotEmpty) ...[
          _sectionHeader('Continuer à regarder', resume.length),
          _shelf(resume),
        ],
        if (showSections && favorites.isNotEmpty) ...[
          _sectionHeader('Favoris', favorites.length),
          _shelf(favorites),
        ],
        if (showSections && (resume.isNotEmpty || favorites.isNotEmpty))
          _sectionHeader('Toute la collection', items.length),
        if (library.settings.viewMode == 'genre' && !_filtering)
          ..._genreSections()
        else if (library.settings.viewMode == 'list')
          _list(items)
        else
          _grid(items),
        const SliverToBoxAdapter(child: SizedBox(height: 90)),
      ],
    );
  }

  Widget _sectionHeader(String title, int count) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
        child: Row(
          children: [
            Container(width: 3, height: 15, color: Palette.shu),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text('$count',
                style: TextStyle(color: Palette.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  /// Rangee horizontale : les series en cours et les favoris.
  Widget _shelf(List<MediaItem> items) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 232,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) => SizedBox(
            width: 118,
            child: MediaCard(
              item: items[i],
              titleSize: 12.5,
              onTap: () => _open(items[i]),
              onFavorite: () => library.toggleFavorite(items[i]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _grid(List<MediaItem> items) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.crossAxisExtent;
          final columns = (width / 170).floor().clamp(2, 8);
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: 0.52,
              crossAxisSpacing: 14,
              mainAxisSpacing: 18,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => MediaCard(
                item: items[i],
                onTap: () => _open(items[i]),
                onFavorite: () => library.toggleFavorite(items[i]),
              ),
              childCount: items.length,
            ),
          );
        },
      ),
    );
  }

  Widget _list(List<MediaItem> items) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => MediaRow(item: items[i], onTap: () => _open(items[i])),
          childCount: items.length,
        ),
      ),
    );
  }

  List<Widget> _genreSections() {
    final grouped = library.groupedByGenre(query: _query);
    final keys = grouped.keys.toList()..sort();
    final slivers = <Widget>[];
    for (final g in keys) {
      slivers.add(_sectionHeader(g, grouped[g]!.length));
      slivers.add(_shelf(grouped[g]!));
    }
    return slivers;
  }

  // ---------------------------------------------------------------- filtres

  Widget _progressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(library.status,
              style: TextStyle(color: Palette.muted, fontSize: 12)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(radiusSm),
            child: LinearProgressIndicator(
              value: library.progress > 0 ? library.progress : null,
              minHeight: 4,
              backgroundColor: Palette.raised,
              color: Palette.shu,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: fieldDecoration(
                    hintText: 'Chercher un titre ou un genre',
                    prefixIcon: Icon(Icons.search,
                        color: Palette.muted, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: Icon(Icons.close,
                                color: Palette.muted, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _viewModeButton(),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _sortChip(),
                const SizedBox(width: 8),
                _chip(
                  label: 'Favoris',
                  selected: _favoritesOnly,
                  onTap: () => setState(() => _favoritesOnly = !_favoritesOnly),
                ),
                const SizedBox(width: 8),
                for (final c in const [
                  ['todo', 'À voir'],
                  ['watching', 'En cours'],
                  ['done', 'Terminés'],
                ]) ...[
                  _chip(
                    label: c[1],
                    selected: _collection == c[0],
                    onTap: () => setState(() =>
                        _collection = _collection == c[0] ? '' : c[0]),
                  ),
                  const SizedBox(width: 8),
                ],
                _chip(
                  label: 'Tous les genres',
                  selected: _genre.isEmpty,
                  onTap: () => setState(() => _genre = ''),
                ),
                for (final g in library.allGenres) ...[
                  const SizedBox(width: 8),
                  _chip(
                    label: g,
                    selected: _genre == g,
                    onTap: () => setState(() => _genre = g),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewModeButton() {
    const modes = {
      'grid': [Icons.grid_view, 'Grille'],
      'list': [Icons.view_list, 'Liste compacte'],
      'genre': [Icons.category_outlined, 'Par genre'],
    };
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Palette.line),
        borderRadius: BorderRadius.circular(radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in modes.entries)
            IconButton(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              tooltip: entry.value[1] as String,
              onPressed: () =>
                  library.updateSettings((s) => s.viewMode = entry.key),
              icon: Icon(
                entry.value[0] as IconData,
                color: library.settings.viewMode == entry.key
                    ? Palette.shu
                    : Palette.muted,
              ),
            ),
        ],
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

  Widget _sortChip() {
    const labels = {
      'alpha': 'A → Z',
      'genre': 'Par genre',
      'score': 'Mieux notés',
      'popularity': 'Les plus connus',
      'recent': 'Récemment ajoutés',
      'year': 'Année de sortie',
      'episodes': 'Plus d\'épisodes',
    };
    return PopupMenuButton<String>(
      color: Palette.surface,
      onSelected: (v) => library.updateSettings((s) => s.sortMode = v),
      itemBuilder: (_) => labels.entries
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
            Text(
              labels[library.settings.sortMode] ?? 'A → Z',
              style: TextStyle(
                  fontSize: 12.5,
                  color: Palette.text,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 16, color: Palette.muted),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(widget.logo, width: 250, fit: BoxFit.contain),
            const SizedBox(height: 24),
            const Text(
              'Ta bibliothèque est vide',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Choisis un dossier contenant tes vidéos. Chaque sous-dossier devient une série, '
              'et les fiches se complètent toutes seules.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Palette.muted, height: 1.4, fontSize: 13.5),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _addFolder,
              style: FilledButton.styleFrom(backgroundColor: Palette.shu),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Choisir un dossier'),
            ),
          ],
        ),
      ),
    );
  }
}
