import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../services/ai_search.dart';
import '../services/ai_service.dart';
import '../services/library_controller.dart';
import 'discover_detail_screen.dart';

/// Recherche en langage naturel.
///
/// Le modèle traduit la demande en filtres, les catalogues répondent avec
/// des titres réels, puis le modèle choisit parmi eux. Rien d'inventé ne
/// peut apparaître, et les nouveautés sont là puisque les catalogues sont
/// à jour — sans dépendre d'une recherche web chez le fournisseur d'IA.
class AiSearchScreen extends StatefulWidget {
  /// Onglet d'où l'on vient : il fixe la catégorie proposée par défaut.
  final AiScope scope;

  const AiSearchScreen({super.key, this.scope = AiScope.anime});

  @override
  State<AiSearchScreen> createState() => _AiSearchScreenState();
}

class _AiSearchScreenState extends State<AiSearchScreen> {
  final _controller = TextEditingController();

  late AiScope _scope = widget.scope;
  List<AiPick> _results = [];
  bool _busy = false;
  String? _message;
  String _understood = '';

  static const Map<AiScope, List<List<String>>> _presets = {
    AiScope.anime: [
      ['Nouveautés de la saison', 'Les séries qui passent cette saison.'],
      ['Comme ma bibliothèque', 'Des séries proches de celles que je possède.'],
      ['Court et drôle', 'Une comédie de treize épisodes au plus, légère.'],
      ['À pleurer', 'Un drame bouleversant, bien écrit, fin comprise.'],
      ['Vieux classiques', 'Des classiques d\'avant 2005 qui tiennent encore.'],
    ],
    AiScope.movie: [
      ['Sorties récentes', 'Les films sortis ces derniers mois.'],
      ['Comme ma bibliothèque', 'Des films proches de ceux que je possède.'],
      ['Comédie légère', 'Une comédie légère pour se détendre, moins de deux heures.'],
      ['Suspense', 'Un thriller haletant avec un bon retournement.'],
      ['Grands classiques', 'Des grands classiques du cinéma, très bien notés.'],
    ],
    AiScope.series: [
      ['En ce moment', 'Les séries récentes dont on parle.'],
      ['Comme ma bibliothèque', 'Des séries proches de celles que je possède.'],
      ['Mini-série', 'Une mini-série courte, huit épisodes au plus.'],
      ['Policier', 'Une série policière ou d\'enquête prenante.'],
      ['Incontournables', 'Les séries les mieux notées de tous les temps.'],
    ],
    AiScope.kids: [
      ['Pour les petits', 'Des dessins animés doux pour les tout-petits.'],
      ['En famille', 'Un film d\'animation à regarder en famille.'],
      ['Aventure', 'Une grande aventure pour enfants.'],
      ['Rire ensemble', 'Une comédie familiale drôle pour tous les âges.'],
    ],
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _webActive =>
      library.settings.aiWebSearch &&
      AiService.supportsWeb(library.settings.aiProvider);

  Future<void> _run(String request) async {
    if (request.trim().isEmpty || _busy) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _busy = true;
      _results = [];
      _understood = '';
      _message = 'Analyse de la demande…';
    });

    final outcome = await AiSearch.run(
      request: request.trim(),
      scope: _scope,
      onProgress: (m) {
        if (mounted) setState(() => _message = m);
      },
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _results = outcome.picks;
      _understood = outcome.understood;
      if (outcome.error != null) {
        _message = outcome.error;
      } else if (outcome.picks.isEmpty) {
        _message = 'Aucun titre ne correspond vraiment. Reformule ou élargis.';
      } else {
        _message = '${outcome.picks.length} proposition(s) choisie(s) parmi '
            '${outcome.candidates} titres réels'
            '${outcome.usedWeb ? ' · web consulté' : ''}.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final presets = _presets[_scope] ?? const [];

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
                const Text('Recherche IA'),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 11, top: 1),
              child: Text(
                _scope == AiScope.anime
                    ? 'Titres réels d\'AniList, à jour'
                    : 'Titres réels de TMDB, à jour',
                style: TextStyle(
                    color: Palette.kin, fontSize: 10.5, letterSpacing: 0.8),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Catégorie : on peut chercher un film depuis l'onglet Animes.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final sc in AiScope.values) ...[
                        _chip(
                          label: sc.label,
                          selected: _scope == sc,
                          onTap: _busy
                              ? null
                              : () => setState(() {
                                    _scope = sc;
                                    _results = [];
                                    _understood = '';
                                    _message = null;
                                  }),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _run,
                  decoration: fieldDecoration(
                    hintText: 'Décris ce que tu cherches',
                    prefixIcon: Icon(Icons.auto_awesome,
                        color: Palette.muted, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.send, color: Palette.shu, size: 20),
                      onPressed: () => _run(_controller.text),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Hauteur libre : une hauteur fixe coupe le texte sous Windows,
                // dont la police est plus haute que celle d'Android.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final p in presets) ...[
                        _chip(
                          label: p[0],
                          selected: false,
                          outlined: true,
                          onTap: _busy
                              ? null
                              : () {
                                  _controller.text = p[1];
                                  _run(p[1]);
                                },
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Palette.raised,
                  color: Palette.shu),
            ),
          if (_understood.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.psychology_outlined,
                      size: 15, color: Palette.kin),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Compris : $_understood',
                        style: TextStyle(
                            color: Palette.kin, fontSize: 12, height: 1.4)),
                  ),
                ],
              ),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: Text(_message!,
                  style: TextStyle(
                      color: Palette.muted, fontSize: 12, height: 1.4)),
            ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Pose ta question en français : une ambiance, une '
                        'durée, une époque, un titre que tu as aimé. '
                        'L\'IA la traduit en critères, le catalogue répond '
                        'avec des titres qui existent, puis elle choisit '
                        'les plus proches de ta demande.'
                        '${_webActive ? '\n\nRecherche web OpenRouter active : '
                            'elle est facturée à la requête.' : ''}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Palette.muted, height: 1.5, fontSize: 13),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => _tile(_results[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
    bool outlined = false,
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
            fontWeight: outlined ? FontWeight.w400 : FontWeight.w500,
            color: selected ? Colors.white : Palette.muted,
          ),
        ),
      ),
    );
  }

  Widget _tile(AiPick found) {
    final meta = found.meta;

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DiscoverDetailScreen(meta: meta)),
      ),
      borderRadius: BorderRadius.circular(radiusMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(radiusSm),
            child: SizedBox(
              width: 62,
              height: 88,
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
              children: [
                Text(meta.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.2)),
                const SizedBox(height: 3),
                Text(
                  [
                    if (meta.year != null) '${meta.year}',
                    if (meta.type != null) meta.type!,
                    if (meta.episodes != null && meta.episodes! > 1)
                      '${meta.episodes} ép.',
                    if (meta.score != null)
                      '★ ${meta.score!.toStringAsFixed(1)}',
                  ].join(' · '),
                  style: TextStyle(color: Palette.muted, fontSize: 11.5),
                ),
                if (found.reason.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(found.reason,
                      style: TextStyle(
                          color: Palette.kin, fontSize: 12, height: 1.35)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
