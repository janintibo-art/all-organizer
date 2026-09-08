import 'package:flutter/material.dart';

import '../main.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/music_controller.dart';
import '../services/m3u.dart';
import '../widgets/cover_image.dart';
import 'folder_picker_screen.dart';
import 'playlist_builder_screen.dart';

/// Listes de lecture : création, import M3U, et construction en parcourant
/// les disques.
class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  Future<String?> _demanderNom({String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: Text(initial.isEmpty ? 'Nouvelle liste' : 'Renommer'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: fieldDecoration(hintText: 'Sessions nocturnes'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.shu),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(initial.isEmpty ? 'Créer' : 'Renommer'),
          ),
        ],
      ),
    );
  }

  Future<void> _construireEnParcourant() async {
    final nom = await _demanderNom();
    if (nom == null || !mounted) return;

    final chemins = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => const PlaylistBuilderScreen()),
    );
    if (chemins == null || chemins.isEmpty) return;
    await music.createPlaylist(nom, paths: chemins);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${chemins.length} morceau(x) dans « $nom ».')),
    );
  }

  Future<void> _importerM3u() async {
    final fichier = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const FolderPickerScreen(pickExtension: '.m3u'),
      ),
    );
    if (fichier == null || !mounted) return;

    final chemins = await M3u.import(fichier);
    if (chemins.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Aucun fichier de cette liste n\'a été retrouvé.')),
      );
      return;
    }
    await music.createPlaylist(M3u.nomDepuisFichier(fichier),
        paths: chemins);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${chemins.length} morceau(x) importé(s).')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: music,
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
                    const Text('Listes'),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 11, top: 1),
                  child: Text('${music.playlists.length} listes de lecture',
                      style: TextStyle(
                          color: Palette.muted,
                          fontSize: 10.5,
                          letterSpacing: 0.8)),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Importer une liste M3U',
                onPressed: _importerM3u,
                icon: const Icon(Icons.file_download_outlined),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _construireEnParcourant,
            backgroundColor: Palette.shu,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.playlist_add),
            label: const Text('Parcourir les disques'),
          ),
          body: music.playlists.isEmpty
              ? _vide()
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: music.playlists.length,
                  itemBuilder: (context, i) =>
                      _ligne(music.playlists[i]),
                ),
        );
      },
    );
  }

  Widget _ligne(Playlist playlist) {
    final morceaux = music.tracksOf(playlist);
    final manquants = music.missingIn(playlist);

    return ListTile(
      leading: CoverImage(
        path: morceaux.isEmpty ? null : morceaux.first.coverPath,
        size: 50,
        icon: Icons.queue_music,
      ),
      title: Text(playlist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: Palette.text,
              fontSize: 14.5,
              fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${morceaux.length} morceaux'
        '${manquants.isEmpty ? '' : ' · ${manquants.length} introuvable(s)'}',
        style: TextStyle(
            color: manquants.isEmpty ? Palette.muted : Palette.shu,
            fontSize: 11.5),
      ),
      trailing: PopupMenuButton<String>(
        color: Palette.surface,
        icon: Icon(Icons.more_vert, color: Palette.muted),
        onSelected: (choix) async {
          switch (choix) {
            case 'lire':
              if (morceaux.isNotEmpty) audio.jouer(morceaux);
              break;
            case 'hasard':
              if (morceaux.isNotEmpty) {
                audio.jouer([...morceaux]..shuffle());
              }
              break;
            case 'renommer':
              final nom = await _demanderNom(initial: playlist.name);
              if (nom != null) music.renamePlaylist(playlist, nom);
              break;
            case 'exporter':
              await _exporter(playlist, morceaux);
              break;
            case 'supprimer':
              await _confirmerSuppression(playlist);
              break;
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'lire', child: Text('Écouter')),
          PopupMenuItem(value: 'hasard', child: Text('Écouter au hasard')),
          PopupMenuItem(value: 'renommer', child: Text('Renommer')),
          PopupMenuItem(value: 'exporter', child: Text('Exporter en M3U')),
          PopupMenuItem(value: 'supprimer', child: Text('Supprimer')),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PlaylistScreen(playlist: playlist)),
      ),
    );
  }

  Future<void> _exporter(Playlist playlist, List<Track> morceaux) async {
    final dossier = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const FolderPickerScreen()),
    );
    if (dossier == null) return;
    try {
      final chemin = await M3u.export(playlist, morceaux, dossier);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Liste écrite : $chemin')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Écriture impossible dans ce dossier.')),
      );
    }
  }

  Future<void> _confirmerSuppression(Playlist playlist) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: Text('Supprimer « ${playlist.name} » ?'),
        content: const Text(
            'La liste disparaît. Les fichiers audio ne sont pas touchés.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.shu),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true) await music.deletePlaylist(playlist);
  }

  Widget _vide() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.queue_music, size: 48, color: Palette.raised),
            const SizedBox(height: 16),
            Text('Aucune liste',
                style: TextStyle(
                    color: Palette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Parcours tes disques pour cocher des morceaux, ou importe une '
              'liste M3U existante depuis le bouton en haut.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Palette.muted, height: 1.4, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Contenu d'une liste, réordonnable par glissement.
class PlaylistScreen extends StatelessWidget {
  final Playlist playlist;
  const PlaylistScreen({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: music,
      builder: (context, _) {
        final morceaux = music.tracksOf(playlist);
        final manquants = music.missingIn(playlist);

        return Scaffold(
          appBar: darkAppBar(
            title: Text(playlist.name, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: 'Écouter',
                onPressed:
                    morceaux.isEmpty ? null : () => audio.jouer(morceaux),
                icon: const Icon(Icons.play_arrow),
              ),
            ],
          ),
          body: Column(
            children: [
              if (manquants.isNotEmpty)
                Container(
                  width: double.infinity,
                  color: Palette.raised,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${manquants.length} morceau(x) de cette liste sont '
                    'introuvables. Ils sont conservés au cas où le disque '
                    'reviendrait.',
                    style: TextStyle(
                        color: Palette.shu, fontSize: 12, height: 1.4),
                  ),
                ),
              Expanded(
                child: morceaux.isEmpty
                    ? Center(
                        child: Text('Liste vide.',
                            style: TextStyle(color: Palette.muted)))
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: morceaux.length,
                        onReorder: (from, to) => music.reorderPlaylist(
                            playlist, from, to > from ? to - 1 : to),
                        itemBuilder: (context, i) {
                          final t = morceaux[i];
                          return Dismissible(
                            key: ValueKey(t.path),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: Palette.shu,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(Icons.delete,
                                  color: Colors.white),
                            ),
                            onDismissed: (_) =>
                                music.removeFromPlaylist(playlist, t.path),
                            child: ListTile(
                              dense: true,
                              leading: CoverImage(path: t.coverPath, size: 44),
                              title: Text(t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: Palette.text, fontSize: 14)),
                              subtitle: Text(t.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: Palette.muted, fontSize: 11.5)),
                              trailing: Icon(Icons.drag_handle,
                                  color: Palette.muted, size: 20),
                              onTap: () {
                                audio.jouer(morceaux, index: i);
                                music.noteEcoute(t.path);
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
