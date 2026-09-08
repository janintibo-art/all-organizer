import 'package:flutter/material.dart';

import '../main.dart';
import '../models/media_item.dart';
import '../services/library_controller.dart';
import '../services/music_controller.dart';
import '../widgets/mini_player.dart';
import 'albums_screen.dart';
import 'artists_screen.dart';
import 'home_screen.dart';
import 'playlists_screen.dart';
import 'servers_screen.dart';
import 'tracks_screen.dart';

/// Navigation principale.
///
/// Les onglets suivent la **nature** du contenu, jamais sa source : un film
/// reste un film qu'il vienne de la carte SD ou du serveur.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _index = 0;

  /// Sous-onglet de la section vidéo.
  int _videoTab = 0;

  /// Sous-onglet de la section musique.
  int _musicTab = 0;

  static const List<Widget> _videoPages = [
    HomeScreen(
      kind: MediaKind.anime,
      title: 'Animes',
      subtitle: 'Animation japonaise',
      logo: 'assets/logo_anime.png',
    ),
    HomeScreen(
      kind: MediaKind.movie,
      title: 'Films',
      subtitle: 'Longs métrages',
      logo: 'assets/logo_media.png',
    ),
    HomeScreen(
      kind: MediaKind.series,
      title: 'Séries',
      subtitle: 'Séries et feuilletons',
      logo: 'assets/logo_media.png',
    ),
    HomeScreen(
      kidsOnly: true,
      title: 'Jeunesse',
      subtitle: 'Tous publics',
      logo: 'assets/logo_media.png',
    ),
  ];

  static const List<Widget> _musicPages = [
    TracksScreen(),
    AlbumsScreen(),
    ArtistsScreen(),
    PlaylistsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([library, music]),
      builder: (context, _) {
        return Scaffold(
          body: IndexedStack(
            index: _index,
            children: [
              _sectionVideo(),
              _sectionMusique(),
              const ServersScreen(),
            ],
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MiniPlayer(),
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Palette.line)),
                ),
                child: BottomNavigationBar(
                  currentIndex: _index,
                  onTap: (i) => setState(() => _index = i),
                  backgroundColor: Palette.ink,
                  selectedItemColor: Palette.shu,
                  unselectedItemColor: Palette.muted,
                  selectedFontSize: 11,
                  unselectedFontSize: 11,
                  type: BottomNavigationBarType.fixed,
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.movie_outlined),
                      activeIcon: Icon(Icons.movie),
                      label: 'Vidéo',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.music_note_outlined),
                      activeIcon: Icon(Icons.music_note),
                      label: 'Musique',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.dns_outlined),
                      activeIcon: Icon(Icons.dns),
                      label: 'Serveurs',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionVideo() {
    return Column(
      children: [
        Expanded(
          child: IndexedStack(index: _videoTab, children: _videoPages),
        ),
        _sousOnglets(
          courant: _videoTab,
          onChange: (i) => setState(() => _videoTab = i),
          entrees: [
            _Sous('Animes', library.countOf(MediaKind.anime)),
            _Sous('Films', library.countOf(MediaKind.movie)),
            _Sous('Séries', library.countOf(MediaKind.series)),
            _Sous('Jeunesse', library.kidsCount),
          ],
        ),
      ],
    );
  }

  Widget _sectionMusique() {
    return Column(
      children: [
        Expanded(
          child: IndexedStack(index: _musicTab, children: _musicPages),
        ),
        _sousOnglets(
          courant: _musicTab,
          onChange: (i) => setState(() => _musicTab = i),
          entrees: [
            _Sous('Morceaux', music.tracks.length),
            _Sous('Albums', music.albums.length),
            _Sous('Artistes', music.artists.length),
            _Sous('Listes', music.playlists.length),
          ],
        ),
      ],
    );
  }

  /// Bande de sous-onglets, placée en bas pour rester à portée du pouce.
  Widget _sousOnglets({
    required int courant,
    required ValueChanged<int> onChange,
    required List<_Sous> entrees,
  }) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Palette.surface,
        border: Border(top: BorderSide(color: Palette.line)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < entrees.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChange(i),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: courant == i ? Palette.shu : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entrees[i].label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color:
                              courant == i ? Palette.shu : Palette.muted,
                        ),
                      ),
                      Text(
                        '${entrees[i].count}',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: courant == i ? Palette.kin : Palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Sous {
  final String label;
  final int count;
  const _Sous(this.label, this.count);
}
