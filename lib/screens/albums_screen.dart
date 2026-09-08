import 'package:flutter/material.dart';

import '../main.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/music_controller.dart';
import '../widgets/cover_image.dart';

/// Grille des albums, et détail d'un album.
class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({super.key});

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: music,
      builder: (context, _) {
        final q = _query.trim().toLowerCase();
        final albums = music.albums
            .where((a) =>
                q.isEmpty ||
                a.title.toLowerCase().contains(q) ||
                a.artist.toLowerCase().contains(q))
            .toList();

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
                    const Text('Albums'),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 11, top: 1),
                  child: Text('${music.albums.length} albums',
                      style: TextStyle(
                          color: Palette.muted,
                          fontSize: 10.5,
                          letterSpacing: 0.8)),
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: fieldDecoration(
                    hintText: 'Chercher un album',
                    prefixIcon:
                        Icon(Icons.search, color: Palette.muted, size: 20),
                  ),
                ),
              ),
              Expanded(
                child: albums.isEmpty
                    ? Center(
                        child: Text('Aucun album.',
                            style: TextStyle(color: Palette.muted)))
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final colonnes =
                              (constraints.maxWidth / 170).floor().clamp(2, 8);
                          return GridView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 90),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: colonnes,
                              childAspectRatio: 0.74,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 18,
                            ),
                            itemCount: albums.length,
                            itemBuilder: (context, i) => _tuile(albums[i]),
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

  Widget _tuile(Album album) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AlbumScreen(album: album)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => CoverImage(
                path: album.coverPath,
                size: c.maxWidth,
                radius: radiusMd,
                icon: Icons.album,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(album.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Palette.text,
                  fontSize: 13,
                  height: 1.25,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            '${album.artist}${album.year == null ? '' : ' · ${album.year}'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: Palette.kin),
          ),
        ],
      ),
    );
  }
}

/// Détail d'un album : ses morceaux dans l'ordre du disque.
class AlbumScreen extends StatelessWidget {
  final Album album;
  const AlbumScreen({super.key, required this.album});

  @override
  Widget build(BuildContext context) {
    final morceaux = album.ordered;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: Palette.ink,
            surfaceTintColor: Colors.transparent,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CoverImage(
                      path: album.coverPath,
                      size: 400,
                      radius: 0,
                      icon: Icons.album),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        stops: const [0.0, 0.32, 0.65],
                        colors: [
                          Palette.ink,
                          Palette.ink.withAlpha(230),
                          Palette.ink.withAlpha(0),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(album.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Palette.text,
                                fontSize: 22,
                                height: 1.15,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          '${album.artist} · ${morceaux.length} morceaux · '
                          '${album.duration.inMinutes} min'
                          '${album.year == null ? '' : ' · ${album.year}'}',
                          style: TextStyle(
                              color: Palette.muted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Palette.shu,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(radiusSm)),
                      ),
                      onPressed: () => audio.jouer(morceaux),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Écouter'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      final melange = [...morceaux]..shuffle();
                      audio.jouer(melange);
                    },
                    icon: const Icon(Icons.shuffle, size: 18),
                    label: const Text('Au hasard'),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final t = morceaux[i];
                return ListTile(
                  dense: true,
                  leading: SizedBox(
                    width: 32,
                    child: Center(
                      child: Text('${t.trackNumber ?? i + 1}',
                          style: TextStyle(
                              color: Palette.muted, fontSize: 12.5)),
                    ),
                  ),
                  title: Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: Palette.text, fontSize: 14)),
                  subtitle: t.artist == album.artist
                      ? null
                      : Text(t.artist,
                          style: TextStyle(
                              color: Palette.muted, fontSize: 11.5)),
                  onTap: () {
                    audio.jouer(morceaux, index: i);
                    music.noteEcoute(t.path);
                  },
                );
              },
              childCount: morceaux.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ],
      ),
    );
  }
}
