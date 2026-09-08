import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/media_meta.dart';
import '../models/labels.dart';
import '../services/tmdb_api.dart';
import '../services/library_controller.dart';
import '../services/translate_api.dart';
import '../widgets/watch_links.dart';
import 'detail_screen.dart';

/// Fiche d'une série du catalogue, avant de l'avoir sur le disque.
class DiscoverDetailScreen extends StatefulWidget {
  final MediaMeta meta;
  const DiscoverDetailScreen({super.key, required this.meta});

  @override
  State<DiscoverDetailScreen> createState() => _DiscoverDetailScreenState();
}

class _DiscoverDetailScreenState extends State<DiscoverDetailScreen> {
  List<MediaMeta> _similar = [];
  String? _translated;
  bool _translating = false;

  MediaMeta get meta => widget.meta;

  @override
  void initState() {
    super.initState();
    _loadSimilar();
    // TMDB renvoie déjà le français : la traduction ne sert que pour
    // les fiches venant de TVmaze, qui sont en anglais.
    if (meta.source != 'tmdb' &&
        library.settings.autoTranslate &&
        library.settings.translationProvider != 'none') {
      _translate();
    }
  }

  Future<void> _loadSimilar() async {
    final id = meta.sourceId;
    if (id == null || meta.source != 'tmdb') return;
    final list = await TmdbApi.recommendations(
      id,
      meta.type == 'Série',
      library.settings.tmdbKey,
    );
    if (mounted) setState(() => _similar = list);
  }

  Future<void> _translate() async {
    final source = meta.synopsis;
    if (source == null || source.isEmpty || _translating) return;
    setState(() => _translating = true);
    final result = await TranslateApi.translate(
      source,
      provider: library.settings.translationProvider,
      targetLang: library.settings.targetLang,
      apiKey: library.settings.apiKey,
      endpoint: library.settings.libreEndpoint,
      email: library.settings.email,
    );
    if (!mounted) return;
    setState(() {
      _translated = result;
      _translating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final local = library.localMatch(meta);
        final wished = library.inWishlist(meta);
        final synopsis = _translated ?? meta.synopsis;

        return Scaffold(
          body: CustomScrollView(
            slivers: [
              _banner(),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (local != null)
                        _localBanner(local)
                      else
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  wished ? Palette.raised : Palette.shu,
                              foregroundColor:
                                  wished ? Palette.text : Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(radiusSm)),
                            ),
                            onPressed: () => library.toggleWishlist(meta),
                            icon: Icon(wished
                                ? Icons.bookmark_remove
                                : Icons.bookmark_add_outlined),
                            label: Text(wished
                                ? 'Retirer de ma liste'
                                : 'Ajouter à ma liste « à voir »'),
                          ),
                        ),
                      const SizedBox(height: 16),
                      _titles(),
                      const SizedBox(height: 14),
                      _badges(),
                      if (meta.genres.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _genres(),
                      ],
                      const SizedBox(height: 18),
                      if (_translating)
                        Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: LinearProgressIndicator(
                              minHeight: 3,
                              backgroundColor: Palette.raised,
                              color: Palette.shu),
                        ),
                      Text(
                        synopsis == null || synopsis.isEmpty
                            ? 'Pas de synopsis pour cette série.'
                            : synopsis,
                        style: TextStyle(
                            height: 1.55, fontSize: 14.5, color: Palette.text),
                      ),
                      if (_translated == null && meta.synopsis != null) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _translating ? null : _translate,
                          icon: const Icon(Icons.translate, size: 18),
                          label: const Text('Traduire'),
                        ),
                      ],
                      const SizedBox(height: 26),
                      WatchLinks(
                        title: meta.titleRomaji?.isNotEmpty == true
                            ? meta.titleRomaji!
                            : meta.title,
                        year: meta.year,
                      ),
                      if (_similar.isNotEmpty) ...[
                        const SizedBox(height: 26),
                        Row(
                          children: [
                            Container(width: 3, height: 15, color: Palette.shu),
                            const SizedBox(width: 8),
                            const Text('Dans le même esprit',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 196,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _similar.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, i) =>
                                _similarTile(_similar[i]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _banner() {
    return SliverAppBar(
      expandedHeight: 320,
      pinned: true,
      backgroundColor: Palette.ink,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (meta.imageUrl != null)
              CachedNetworkImage(
                imageUrl: meta.imageUrl!,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorWidget: (_, __, ___) => Container(color: Palette.surface),
              )
            else
              Container(color: Palette.surface),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 110,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xB3000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  stops: [0.0, 0.30, 0.62],
                  colors: [
                    Palette.ink,
                    Color(0xE60D0B0B),
                    Color(0x000D0B0B),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (meta.imageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(radiusMd),
                      child: SizedBox(
                        width: 84,
                        height: 118,
                        child: CachedNetworkImage(
                            imageUrl: meta.imageUrl!, fit: BoxFit.cover),
                      ),
                    ),
                  if (meta.imageUrl != null) const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (meta.titleNative != null &&
                            meta.titleNative!.trim().isNotEmpty)
                          Text(
                            meta.titleNative!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Palette.muted, fontSize: 12),
                          ),
                        const SizedBox(height: 3),
                        Text(
                          meta.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            color: Palette.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _localBanner(local) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Palette.surface,
        border: Border.all(color: Palette.kin),
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: Palette.kin, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Déjà dans ta bibliothèque',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => DetailScreen(item: local)),
            ),
            child: const Text('Ouvrir'),
          ),
        ],
      ),
    );
  }

  Widget _titles() {
    final rows = <List<String>>[
      if (meta.titleRomaji != null && meta.titleRomaji!.isNotEmpty)
        ['Romaji', meta.titleRomaji!],
      ['Anglais', meta.title],
      if (meta.titleNative != null && meta.titleNative!.isNotEmpty)
        ['日本語', meta.titleNative!],
    ];
    if (rows.length < 2) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.surface,
        border: Border.all(color: Palette.line),
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 68,
                    child: Text(row[0],
                        style: TextStyle(
                            color: Palette.muted, fontSize: 11.5)),
                  ),
                  Expanded(
                    child: Text(row[1],
                        style: const TextStyle(fontSize: 13, height: 1.35)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _badges() {
    final items = <List<String>>[
      if (meta.year != null) ['Année', '${meta.year}'],
      if (Labels.format(meta.type) != null)
        ['Format', Labels.format(meta.type)!],
      if (meta.episodes != null) ['Épisodes', '${meta.episodes}'],
      if (meta.score != null) ['Note', meta.score!.toStringAsFixed(2)],
      if (Labels.status(meta.status) != null)
        ['Statut', Labels.status(meta.status)!],
      if (meta.studios != null) ['Studio', meta.studios!],
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Palette.surface,
              border: Border.all(color: Palette.line),
              borderRadius: BorderRadius.circular(radiusSm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item[0],
                    style: TextStyle(
                        color: Palette.muted,
                        fontSize: 9.5,
                        letterSpacing: 0.8)),
                const SizedBox(height: 2),
                Text(item[1],
                    style: TextStyle(
                        color: item[0] == 'Note' ? Palette.kin : Palette.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _genres() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: Labels.genres(meta.genres)
          .map((g) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0x73D6B86A)),
                  borderRadius: BorderRadius.circular(radiusSm),
                ),
                child: Text(g,
                    style: TextStyle(color: Palette.kin, fontSize: 12)),
              ))
          .toList(),
    );
  }

  Widget _similarTile(MediaMeta other) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => DiscoverDetailScreen(meta: other)),
      ),
      child: SizedBox(
        width: 108,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(radiusMd),
              child: SizedBox(
                height: 152,
                width: 108,
                child: other.imageUrl == null
                    ? Container(color: Palette.raised)
                    : CachedNetworkImage(
                        imageUrl: other.imageUrl!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              other.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}
