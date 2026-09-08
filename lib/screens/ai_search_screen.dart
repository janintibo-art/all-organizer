import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/media_meta.dart';
import '../services/ai_service.dart';
import '../services/library_controller.dart';
import '../services/metadata_service.dart';
import 'discover_detail_screen.dart';

/// Recherche en langage naturel.
///
/// L'IA propose des titres, mais rien n'est affiché tel quel : chaque titre
/// est confronté à l'index local puis aux bases en ligne. Ce qui n'existe
/// pas disparaît, ce qui explique le décompte affiché en fin de recherche.
class AiSearchScreen extends StatefulWidget {
  const AiSearchScreen({super.key});

  @override
  State<AiSearchScreen> createState() => _AiSearchScreenState();
}

class _AiSearchScreenState extends State<AiSearchScreen> {
  final _controller = TextEditingController();

  final List<_Found> _results = [];
  bool _busy = false;
  String? _message;
  int _discarded = 0;

  static const List<List<String>> _presets = [
    ['Nouveautés de la saison', 'Quelles séries commencent cette saison ?'],
    [
      'Comme ma bibliothèque',
      'Propose des séries proches de celles que je possède déjà.'
    ],
    ['Court et drôle', 'Une comédie de moins de treize épisodes, légère.'],
    ['À pleurer', 'Un drame bouleversant, bien écrit, fin comprise.'],
    ['Vieux classiques', 'Des classiques d\'avant 2005 qui tiennent encore.'],
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _webAvailable =>
      library.settings.aiWebSearch &&
      AiService.supportsWeb(library.settings.aiModel);

  Future<void> _run(String request) async {
    if (request.trim().isEmpty || _busy) return;

    final settings = library.settings;
    if (settings.aiKey.trim().isEmpty) {
      setState(() => _message =
          'Renseigne une clé IA dans Réglages → Assistant IA.');
      return;
    }

    setState(() {
      _busy = true;
      _results.clear();
      _discarded = 0;
      _message = _webAvailable
          ? 'Recherche en cours, le modèle peut consulter le web…'
          : 'Recherche en cours…';
    });

    final owned = library.items
        .where((a) => a.metaFetched)
        .map((a) => a.romajiTitle ?? a.title)
        .toList();

    final suggestions = await AiService.suggest(
      request: request,
      provider: settings.aiProvider,
      apiKey: settings.aiKey,
      model: settings.aiModel,
      custom: settings.aiEndpoint,
      ownedTitles: owned,
      webSearch: _webAvailable,
    );

    if (!mounted) return;

    if (suggestions.isEmpty) {
      setState(() {
        _busy = false;
        _message = AiService.lastError ?? 'Aucune proposition.';
      });
      return;
    }

    setState(() => _message = 'Vérification de ${suggestions.length} titres…');

    var discarded = 0;
    for (final suggestion in suggestions) {
      // Chaque titre proposé est vérifié auprès de TMDB avant d'être montré.
      final meta = await MetadataService.smartSearch(
        suggestion.title,
        source: settings.metaSource,
        tmdbKey: settings.tmdbKey,
      );

      if (meta == null) {
        discarded++;
        continue;
      }
      if (!mounted) return;
      setState(() => _results.add(_Found(meta!, suggestion.reason)));
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _discarded = discarded;
      final tools = AiService.lastTools;
      _message = _results.isEmpty
          ? 'Aucun titre proposé n\'a pu être vérifié.'
          : '${_results.length} série(s) vérifiée(s)'
              '${discarded > 0 ? ', $discarded écartée(s) faute de correspondance' : ''}'
              '${tools.contains('web_search') ? ' · le modèle a consulté le web' : ''}.';
    });
  }

  @override
  Widget build(BuildContext context) {
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
                _webAvailable
                    ? 'Avec accès au web'
                    : 'Sans accès au web · connaissance figée',
                style: TextStyle(
                  color: _webAvailable ? Palette.kin : Palette.muted,
                  fontSize: 10.5,
                  letterSpacing: 0.8,
                ),
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
              children: [
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
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _presets.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => GestureDetector(
                      onTap: () {
                        _controller.text = _presets[i][1];
                        _run(_presets[i][1]);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          border: Border.all(color: Palette.line),
                          borderRadius: BorderRadius.circular(radiusSm),
                        ),
                        child: Text(_presets[i][0],
                            style: TextStyle(
                                fontSize: 12.5, color: Palette.muted)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_busy)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Palette.raised,
                  color: Palette.shu),
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
                        _webAvailable
                            ? 'Pose ta question en français. Le modèle peut aller '
                                'vérifier les sorties récentes en ligne.'
                            : 'Pose ta question en français. Pour les nouveautés, '
                                'choisis un modèle « compound » dans les réglages : '
                                'sans accès au web, le modèle ignore ce qui est '
                                'sorti après son entraînement.',
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

  Widget _tile(_Found found) {
    final meta = found.meta;
    final local = library.localMatch(meta);

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
                    if (meta.episodes != null) '${meta.episodes} ép.',
                  ].join(' · '),
                  style:
                      TextStyle(color: Palette.muted, fontSize: 11.5),
                ),
                if (found.reason.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(found.reason,
                      style: TextStyle(
                          color: Palette.kin, fontSize: 12, height: 1.35)),
                ],
                if (local != null) ...[
                  const SizedBox(height: 4),
                  Text('Déjà dans ta bibliothèque',
                      style: TextStyle(color: Palette.sakura, fontSize: 11)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Found {
  final MediaMeta meta;
  final String reason;
  const _Found(this.meta, this.reason);
}
