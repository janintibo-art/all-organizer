import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../main.dart';
import '../services/audio_player_service.dart';
import '../services/music_controller.dart';
import '../widgets/cover_image.dart';

/// Écran de lecture : pochette, progression, commandes et file d'attente.
class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  static String duree(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:${m.padLeft(2, '0')}:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: audio.mediaItem,
      builder: (context, snapshot) {
        final item = snapshot.data;
        final index = audio.player.currentIndex ?? 0;
        final track =
            index < audio.tracks.length ? audio.tracks[index] : null;

        return Scaffold(
          appBar: darkAppBar(
            title: const Text('Lecture'),
            actions: [
              IconButton(
                tooltip: 'File d\'attente',
                onPressed: () => _fileAttente(context),
                icon: const Icon(Icons.queue_music),
              ),
            ],
          ),
          body: item == null
              ? Center(
                  child: Text('Rien en cours.',
                      style: TextStyle(color: Palette.muted)),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                  children: [
                    Center(
                      child: CoverImage(
                        path: track?.coverPath,
                        size: 280,
                        radius: radiusMd,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(item.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Palette.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            height: 1.2)),
                    const SizedBox(height: 6),
                    Text(item.artist ?? '',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Palette.kin, fontSize: 14)),
                    if (item.album != null) ...[
                      const SizedBox(height: 3),
                      Text(item.album!,
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Palette.muted, fontSize: 12.5)),
                    ],
                    const SizedBox(height: 24),
                    _progression(item),
                    const SizedBox(height: 12),
                    _commandes(),
                    const SizedBox(height: 20),
                    _options(context, track),
                  ],
                ),
        );
      },
    );
  }

  Widget _progression(MediaItem item) {
    return StreamBuilder<Duration>(
      stream: audio.player.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final total = item.duration ?? Duration.zero;
        final max = total.inMilliseconds.toDouble();
        final valeur =
            position.inMilliseconds.clamp(0, total.inMilliseconds).toDouble();

        return Column(
          children: [
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: Palette.shu,
                inactiveTrackColor: Palette.raised,
                thumbColor: Palette.shu,
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: max == 0 ? 0 : valeur,
                max: max == 0 ? 1 : max,
                onChanged: (v) =>
                    audio.seek(Duration(milliseconds: v.round())),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(duree(position),
                      style:
                          TextStyle(color: Palette.muted, fontSize: 11.5)),
                  Text(duree(total),
                      style:
                          TextStyle(color: Palette.muted, fontSize: 11.5)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _commandes() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        StreamBuilder<bool>(
          stream: audio.player.shuffleModeEnabledStream,
          builder: (context, snap) {
            final actif = snap.data ?? false;
            return IconButton(
              iconSize: 22,
              color: actif ? Palette.shu : Palette.muted,
              onPressed: () => audio.setShuffle(!actif),
              icon: const Icon(Icons.shuffle),
            );
          },
        ),
        IconButton(
          iconSize: 34,
          color: Palette.text,
          onPressed: audio.skipToPrevious,
          icon: const Icon(Icons.skip_previous),
        ),
        StreamBuilder<bool>(
          stream: audio.player.playingStream,
          builder: (context, snap) {
            final joue = snap.data ?? false;
            return IconButton(
              iconSize: 64,
              color: Palette.shu,
              onPressed: joue ? audio.pause : audio.play,
              icon: Icon(joue
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled),
            );
          },
        ),
        IconButton(
          iconSize: 34,
          color: Palette.text,
          onPressed: audio.skipToNext,
          icon: const Icon(Icons.skip_next),
        ),
        StreamBuilder<LoopMode>(
          stream: audio.player.loopModeStream,
          builder: (context, snap) {
            final mode = snap.data ?? LoopMode.off;
            return IconButton(
              iconSize: 22,
              color: mode == LoopMode.off ? Palette.muted : Palette.shu,
              onPressed: () => audio.setRepeat(switch (mode) {
                LoopMode.off => LoopMode.all,
                LoopMode.all => LoopMode.one,
                LoopMode.one => LoopMode.off,
              }),
              icon: Icon(mode == LoopMode.one
                  ? Icons.repeat_one
                  : Icons.repeat),
            );
          },
        ),
      ],
    );
  }

  Widget _options(BuildContext context, track) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (track != null)
          TextButton.icon(
            onPressed: () => music.toggleFavorite(track),
            icon: Icon(
              track.favorite ? Icons.favorite : Icons.favorite_border,
              size: 18,
              color: track.favorite ? Palette.sakura : Palette.muted,
            ),
            label: Text('Favori',
                style: TextStyle(color: Palette.muted, fontSize: 12.5)),
          ),
        StreamBuilder<double>(
          stream: audio.player.speedStream,
          builder: (context, snap) {
            final vitesse = snap.data ?? 1.0;
            return PopupMenuButton<double>(
              color: Palette.surface,
              onSelected: audio.setSpeed,
              itemBuilder: (_) => [
                for (final v in [0.75, 1.0, 1.25, 1.5, 2.0])
                  PopupMenuItem(value: v, child: Text('${v}x')),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                child: Text('Vitesse ${vitesse}x',
                    style:
                        TextStyle(color: Palette.muted, fontSize: 12.5)),
              ),
            );
          },
        ),
      ],
    );
  }

  void _fileAttente(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(width: 3, height: 16, color: Palette.shu),
                    const SizedBox(width: 8),
                    Text('File d\'attente · ${audio.tracks.length} morceaux',
                        style: TextStyle(
                            color: Palette.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: audio.tracks.length,
                  itemBuilder: (context, i) {
                    final t = audio.tracks[i];
                    final courant = audio.player.currentIndex == i;
                    return ListTile(
                      dense: true,
                      leading: CoverImage(path: t.coverPath, size: 38),
                      title: Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              color: courant ? Palette.shu : Palette.text)),
                      subtitle: Text(t.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11, color: Palette.muted)),
                      onTap: () {
                        audio.skipToQueueItem(i);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
