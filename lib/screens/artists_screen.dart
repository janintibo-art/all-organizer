import 'package:flutter/material.dart';

import '../main.dart';
import '../services/audio_player_service.dart';
import '../services/music_controller.dart';
import '../widgets/cover_image.dart';
import 'albums_screen.dart';

/// Artistes, avec leurs albums repliés dessous.
class ArtistsScreen extends StatefulWidget {
  const ArtistsScreen({super.key});

  @override
  State<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends State<ArtistsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: music,
      builder: (context, _) {
        final q = _query.trim().toLowerCase();
        final artistes = music.artists.entries
            .where((e) => q.isEmpty || e.key.toLowerCase().contains(q))
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
                    const Text('Artistes'),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 11, top: 1),
                  child: Text('${music.artists.length} artistes',
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
                    hintText: 'Chercher un artiste',
                    prefixIcon:
                        Icon(Icons.search, color: Palette.muted, size: 20),
                  ),
                ),
              ),
              Expanded(
                child: artistes.isEmpty
                    ? Center(
                        child: Text('Aucun artiste.',
                            style: TextStyle(color: Palette.muted)))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: artistes.length,
                        itemBuilder: (context, i) {
                          final entree = artistes[i];
                          final albums = entree.value;
                          final morceaux =
                              albums.expand((a) => a.tracks).toList();

                          return ExpansionTile(
                            leading: CoverImage(
                                path: albums.first.coverPath,
                                size: 46,
                                icon: Icons.person),
                            title: Text(entree.key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Palette.text,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500)),
                            subtitle: Text(
                                '${albums.length} album(s) · '
                                '${morceaux.length} morceaux',
                                style: TextStyle(
                                    color: Palette.muted, fontSize: 11.5)),
                            iconColor: Palette.shu,
                            collapsedIconColor: Palette.muted,
                            childrenPadding:
                                const EdgeInsets.only(left: 16, bottom: 8),
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () => audio.jouer(morceaux),
                                  icon: const Icon(Icons.play_arrow, size: 18),
                                  label: const Text('Tout écouter'),
                                ),
                              ),
                              for (final album in albums)
                                ListTile(
                                  dense: true,
                                  leading: CoverImage(
                                      path: album.coverPath,
                                      size: 38,
                                      icon: Icons.album),
                                  title: Text(album.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: Palette.text, fontSize: 13)),
                                  subtitle: Text(
                                      '${album.tracks.length} morceaux'
                                      '${album.year == null ? '' : ' · ${album.year}'}',
                                      style: TextStyle(
                                          color: Palette.muted,
                                          fontSize: 11)),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            AlbumScreen(album: album)),
                                  ),
                                ),
                            ],
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
