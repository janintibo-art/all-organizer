import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/music_controller.dart';
import '../widgets/cover_image.dart';
import 'folder_picker_screen.dart';
import 'settings_screen.dart';

/// Tous les morceaux, avec recherche, tri et sélection multiple.
class TracksScreen extends StatefulWidget {
  const TracksScreen({super.key});

  @override
  State<TracksScreen> createState() => _TracksScreenState();
}

class _TracksScreenState extends State<TracksScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _favoritesOnly = false;

  /// Sélection en cours, pour l'ajout groupé à une liste de lecture.
  final Set<String> _selection = {};
  bool get _selecting => _selection.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startupScan());
  }

  Future<void> _startupScan() async {
    if (music.folders.isEmpty) return;
    await music.startupScan();
    if (!mounted || music.lastNewCount == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${music.lastNewCount} morceau(x) ajouté(s)')),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addFolder() async {
    if (Platform.isAndroid) {
      await Permission.audio.request();
      await Permission.storage.request();
      if (!await Permission.manageExternalStorage.isGranted) {
        await Permission.manageExternalStorage.request();
      }
    }
    if (!mounted) return;
    final dir = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const FolderPickerScreen()),
    );
    if (dir == null) return;
    await music.addFolder(dir);
    await music.scan();
  }

  Future<void> _ajouterALaListe() async {
    final chemins = _selection.toList();
    final choix = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Palette.surface,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: Icon(Icons.add, color: Palette.shu),
              title: const Text('Nouvelle liste'),
              onTap: () => Navigator.pop(ctx, '__nouvelle__'),
            ),
            Divider(color: Palette.line),
            for (final pl in music.playlists)
              ListTile(
                leading: Icon(Icons.queue_music, color: Palette.kin),
                title: Text(pl.name),
                subtitle: Text('${pl.paths.length} morceaux',
                    style: TextStyle(color: Palette.muted, fontSize: 11.5)),
                onTap: () => Navigator.pop(ctx, pl.id),
              ),
          ],
        ),
      ),
    );
    if (choix == null || !mounted) return;

    if (choix == '__nouvelle__') {
      final nom = await _demanderNom();
      if (nom == null) return;
      await music.createPlaylist(nom, paths: chemins);
    } else {
      final pl = music.playlists.firstWhere((p) => p.id == choix);
      await music.addToPlaylist(pl, chemins);
    }

    setState(_selection.clear);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${chemins.length} morceau(x) ajouté(s).')),
    );
  }

  Future<String?> _demanderNom() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Nom de la liste'),
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
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: music,
      builder: (context, _) {
        final items = music.view(
          query: _query,
          favoritesOnly: _favoritesOnly,
        );

        return Scaffold(
          appBar: _selecting ? _barreSelection() : _barreNormale(),
          floatingActionButton: music.tracks.isEmpty
              ? null
              : FloatingActionButton(
                  onPressed: music.busy ? null : _addFolder,
                  backgroundColor: Palette.shu,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.create_new_folder_outlined),
                ),
          body: music.tracks.isEmpty && !music.busy
              ? _vide()
              : Column(
                  children: [
                    if (music.busy)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(music.status,
                                style: TextStyle(
                                    color: Palette.muted, fontSize: 12)),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                                minHeight: 3,
                                backgroundColor: Palette.raised,
                                color: Palette.shu),
                          ],
                        ),
                      ),
                    _filtres(),
                    Expanded(
                      child: items.isEmpty
                          ? Center(
                              child: Text('Aucun morceau ne correspond.',
                                  style: TextStyle(color: Palette.muted)),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 90),
                              itemCount: items.length,
                              itemBuilder: (context, i) =>
                                  _ligne(items, i),
                            ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  PreferredSizeWidget _barreNormale() {
    final total = Duration(milliseconds: music.totalDurationMs);
    return darkAppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(radiusSm),
                child: Image.asset('assets/logo_music.png',
                    width: 24, height: 24, fit: BoxFit.cover),
              ),
              const SizedBox(width: 9),
              const Text('Morceaux'),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 33, top: 1),
            child: Text(
              music.tracks.isEmpty
                  ? 'Ta collection'
                  : '${music.tracks.length} morceaux · ${total.inHours} h '
                      '${total.inMinutes.remainder(60)} min',
              style: TextStyle(
                  color: Palette.muted, fontSize: 10.5, letterSpacing: 0.8),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Relancer le scan',
          onPressed: music.busy ? null : () => music.scan(),
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Réglages',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
          icon: const Icon(Icons.tune),
        ),
      ],
    );
  }

  PreferredSizeWidget _barreSelection() {
    return darkAppBar(
      title: Text('${_selection.length} sélectionné(s)'),
      actions: [
        IconButton(
          tooltip: 'Lire la sélection',
          onPressed: () {
            final choisis = music.tracks
                .where((t) => _selection.contains(t.path))
                .toList();
            audio.jouer(choisis);
            setState(_selection.clear);
          },
          icon: const Icon(Icons.play_arrow),
        ),
        IconButton(
          tooltip: 'Ajouter à une liste',
          onPressed: _ajouterALaListe,
          icon: const Icon(Icons.playlist_add),
        ),
        IconButton(
          tooltip: 'Annuler',
          onPressed: () => setState(_selection.clear),
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }

  Widget _filtres() {
    const tris = {
      'alpha': 'A → Z',
      'artist': 'Par artiste',
      'album': 'Par album',
      'recent': 'Récemment ajoutés',
      'played': 'Les plus écoutés',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            decoration: fieldDecoration(
              hintText: 'Chercher un titre, un artiste, un album',
              prefixIcon:
                  Icon(Icons.search, color: Palette.muted, size: 20),
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
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                PopupMenuButton<String>(
                  color: Palette.surface,
                  onSelected: (v) =>
                      music.updateSettings((s) => s.sortMode = v),
                  itemBuilder: (_) => tris.entries
                      .map((e) =>
                          PopupMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  child: _puce(
                      tris[music.settings.sortMode] ?? 'A → Z', false,
                      fleche: true),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () =>
                      setState(() => _favoritesOnly = !_favoritesOnly),
                  child: _puce('Favoris', _favoritesOnly),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    final liste = music.view(
                        query: _query, favoritesOnly: _favoritesOnly);
                    if (liste.isEmpty) return;
                    final melange = [...liste]..shuffle();
                    audio.jouer(melange);
                  },
                  child: _puce('Tout lire au hasard', false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _puce(String label, bool actif, {bool fleche = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: actif ? Palette.shu : (fleche ? Palette.raised : Colors.transparent),
        border: Border.all(color: actif ? Palette.shu : Palette.line),
        borderRadius: BorderRadius.circular(radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: actif ? Colors.white : Palette.text)),
          if (fleche) ...[
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 16, color: Palette.muted),
          ],
        ],
      ),
    );
  }

  Widget _ligne(List<Track> items, int index) {
    final t = items[index];
    final choisi = _selection.contains(t.path);

    return ListTile(
      dense: true,
      leading: choisi
          ? Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Palette.shu,
                borderRadius: BorderRadius.circular(radiusSm),
              ),
              child: const Icon(Icons.check, color: Colors.white),
            )
          : CoverImage(path: t.coverPath, size: 46),
      title: Text(t.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 14, color: Palette.text, fontWeight: FontWeight.w500)),
      subtitle: Text(
        '${t.artist}${t.album == 'Sans album' ? '' : ' · ${t.album}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, color: Palette.muted),
      ),
      trailing: t.favorite
          ? Icon(Icons.favorite, size: 16, color: Palette.sakura)
          : (t.durationMs == null
              ? null
              : Text(
                  _duree(Duration(milliseconds: t.durationMs!)),
                  style: TextStyle(color: Palette.muted, fontSize: 11.5),
                )),
      onTap: () {
        if (_selecting) {
          setState(() => choisi
              ? _selection.remove(t.path)
              : _selection.add(t.path));
        } else {
          audio.jouer(items, index: index);
          music.noteEcoute(t.path);
        }
      },
      onLongPress: () => setState(() => _selection.add(t.path)),
    );
  }

  static String _duree(Duration d) =>
      '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  Widget _vide() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo_music.png', width: 250, fit: BoxFit.contain),
            const SizedBox(height: 24),
            Text('Ta bibliothèque est vide',
                style: TextStyle(
                    color: Palette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              music.scanReport.isEmpty
                  ? 'Choisis un dossier de musique. Les étiquettes des '
                      'fichiers sont lues en premier, et le chemin sert de '
                      'secours quand elles manquent.'
                  : music.scanReport,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: music.scanReport.startsWith('Le scan')
                      ? Palette.shu
                      : Palette.muted,
                  height: 1.45,
                  fontSize: 13.5),
            ),
            if (music.folders.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Dossiers suivis : ${music.folders.join(', ')}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Palette.muted, fontSize: 11.5, height: 1.4),
              ),
            ],
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
