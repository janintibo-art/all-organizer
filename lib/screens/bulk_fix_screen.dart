import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/media_item.dart';
import '../models/media_meta.dart';
import '../services/library_controller.dart';
import '../services/metadata_service.dart';

/// Correction groupée : toutes les séries non identifiées au même endroit,
/// avec un champ de recherche par ligne. Elles disparaissent une fois réglées.
class BulkFixScreen extends StatefulWidget {
  const BulkFixScreen({super.key});

  @override
  State<BulkFixScreen> createState() => _BulkFixScreenState();
}

class _BulkFixScreenState extends State<BulkFixScreen> {
  final Map<String, TextEditingController> _controllers = {};
  String? _searchingId;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(MediaItem item) {
    return _controllers.putIfAbsent(
      item.id,
      () => TextEditingController(text: item.folderTitle),
    );
  }

  Future<void> _search(MediaItem item) async {
    final query = _controllerFor(item).text.trim();
    if (query.isEmpty) return;

    setState(() => _searchingId = item.id);
    final results = await MetadataService.searchMany(
      query,
      source: library.settings.metaSource,
    );
    if (!mounted) return;
    setState(() => _searchingId = null);

    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun résultat pour ce titre.')),
      );
      return;
    }

    final chosen = await showModalBottomSheet<MediaMeta>(
      context: context,
      backgroundColor: Palette.surface,
      builder: (ctx) => ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: results.length,
        itemBuilder: (_, i) {
          final r = results[i];
          return ListTile(
            leading: r.imageUrl == null
                ? Icon(Icons.movie_outlined, color: Palette.muted)
                : SizedBox(
                    width: 40,
                    child: CachedNetworkImage(
                        imageUrl: r.imageUrl!, fit: BoxFit.cover)),
            title: Text(r.title, style: const TextStyle(fontSize: 14)),
            subtitle: Text(r.summaryLine,
                style: TextStyle(color: Palette.muted, fontSize: 12)),
            onTap: () => Navigator.pop(ctx, r),
          );
        },
      ),
    );
    if (chosen == null) return;

    library.applyMeta(item, chosen);
    library.remember(item.folderTitle, chosen.titleRomaji ?? chosen.title);
    await library.save();
    if (library.settings.autoTranslate) {
      await library.translateOne(item);
    }
    library.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final items = library.unmatched;

        return Scaffold(
          appBar: darkAppBar(title: const Text('Fiches à corriger')),
          body: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Toutes les séries ont été identifiées.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Palette.muted),
                    ),
                  ),
                )
              : Column(
                  children: [
                    if (library.busy)
                      LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: Palette.raised,
                          color: Palette.shu),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${items.length} série${items.length > 1 ? 's' : ''} sans fiche',
                              style: TextStyle(
                                  color: Palette.muted, fontSize: 12.5),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: library.busy
                                ? null
                                : () => library.retryFailed(),
                            icon: const Icon(Icons.auto_mode, size: 16),
                            label: const Text('Tout relancer',
                                style: TextStyle(fontSize: 12.5)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) => _row(items[i]),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _row(MediaItem item) {
    final searching = _searchingId == item.id;
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
          Text(
            item.id,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Palette.muted, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controllerFor(item),
                  onSubmitted: (_) => _search(item),
                  decoration: fieldDecoration(hintText: 'Titre à rechercher'),
                ),
              ),
              const SizedBox(width: 8),
              searching
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Palette.shu),
                    )
                  : IconButton(
                      onPressed: () => _search(item),
                      icon: Icon(Icons.search, color: Palette.shu),
                    ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${item.episodes.length} fichier${item.episodes.length > 1 ? 's' : ''}'
            '${item.metaFailCount > 0 ? ' · ${item.metaFailCount} tentative(s)' : ''}',
            style: TextStyle(color: Palette.muted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
