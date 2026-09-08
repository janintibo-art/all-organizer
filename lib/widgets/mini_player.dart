import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../screens/now_playing_screen.dart';
import '../services/audio_player_service.dart';
import 'cover_image.dart';

/// Barre de lecture permanente, au-dessus de la navigation.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: audio.mediaItem,
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (item == null) return const SizedBox.shrink();

        final index = audio.player.currentIndex ?? 0;
        final track = index < audio.tracks.length ? audio.tracks[index] : null;

        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NowPlayingScreen()),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Palette.surface,
              border: Border(top: BorderSide(color: Palette.line)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Progression fine : elle sert de repère sans encombrer.
                StreamBuilder<Duration>(
                  stream: audio.player.positionStream,
                  builder: (context, snap) {
                    final position = snap.data ?? Duration.zero;
                    final total = item.duration ?? Duration.zero;
                    final valeur = total.inMilliseconds == 0
                        ? 0.0
                        : position.inMilliseconds / total.inMilliseconds;
                    return LinearProgressIndicator(
                      value: valeur.clamp(0.0, 1.0),
                      minHeight: 2,
                      backgroundColor: Palette.raised,
                      color: Palette.shu,
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                  child: Row(
                    children: [
                      CoverImage(path: track?.coverPath, size: 42),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Palette.text,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600)),
                            Text(item.artist ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Palette.muted, fontSize: 11.5)),
                          ],
                        ),
                      ),
                      StreamBuilder<bool>(
                        stream: audio.player.playingStream,
                        builder: (context, snap) {
                          final joue = snap.data ?? false;
                          return IconButton(
                            iconSize: 30,
                            color: Palette.text,
                            onPressed: joue ? audio.pause : audio.play,
                            icon: Icon(joue
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled),
                          );
                        },
                      ),
                      IconButton(
                        iconSize: 26,
                        color: Palette.muted,
                        onPressed: audio.skipToNext,
                        icon: const Icon(Icons.skip_next),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
