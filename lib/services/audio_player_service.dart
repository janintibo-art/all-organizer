import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import 'cover_cache.dart';
import 'downloads.dart';

/// Lecture audio, y compris écran éteint et depuis l'écran verrouillé.
///
/// C'est ce que le lecteur vidéo ne savait pas faire : une session média
/// déclarée au système, avec sa notification et ses commandes.
class AudioHandlerMusique extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer player = AudioPlayer();

  /// La file réelle : les morceaux tels qu'on les connaît.
  List<Track> tracks = [];

  AudioHandlerMusique() {
    _relayer();
  }

  /// Fait remonter l'état du lecteur vers le système.
  void _relayer() {
    player.playbackEventStream.listen((event) {
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (player.playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: player.playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: player.currentIndex,
      ));
    });

    player.currentIndexStream.listen((index) {
      if (index == null || index >= tracks.length) return;
      mediaItem.add(_versMediaItem(tracks[index]));
    });
  }

  MediaItem _versMediaItem(Track t) => MediaItem(
        id: t.path,
        title: t.title,
        artist: t.artist,
        album: t.album,
        duration: t.duration,
        artUri: CoverCache.exists(t.coverPath)
            ? Uri.file(t.coverPath!)
            : null,
      );

  /// Remplace la file et démarre à l'index demandé.
  Future<void> jouer(List<Track> liste, {int index = 0}) async {
    if (liste.isEmpty) return;
    tracks = liste;
    queue.add(liste.map(_versMediaItem).toList());

    await player.setAudioSource(
      ConcatenatingAudioSource(
        children: liste
            .map((t) => MediaSource.isRemote(t)
                ? AudioSource.uri(Uri.parse(MediaSource.forTrack(t)),
                    tag: _versMediaItem(t))
                : AudioSource.file(MediaSource.forTrack(t),
                    tag: _versMediaItem(t)))
            .toList(),
      ),
      initialIndex: index.clamp(0, liste.length - 1),
    );
    await player.play();
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> stop() async {
    await player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() => player.seekToNext();

  @override
  Future<void> skipToPrevious() async {
    // Comportement attendu d'un lecteur : revenir au début du morceau si
    // on est déjà entré dedans, passer au précédent sinon.
    if (player.position.inSeconds > 3) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= tracks.length) return;
    await player.seek(Duration.zero, index: index);
  }

  Future<void> setShuffle(bool actif) async {
    await player.setShuffleModeEnabled(actif);
    if (actif) await player.shuffle();
  }

  Future<void> setRepeat(LoopMode mode) => player.setLoopMode(mode);

  Future<void> setSpeed(double vitesse) => player.setSpeed(vitesse);
}

/// Instance unique, mise en place au démarrage.
late AudioHandlerMusique audio;

/// Message d'erreur si la session média n'a pas pu être ouverte.
/// Affiché dans les réglages plutôt que perdu dans les journaux.
String? audioInitError;

Future<void> initAudio() async {
  try {
    audio = await AudioService.init(
      builder: () => AudioHandlerMusique(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.allorganizer.audio',
        androidNotificationChannelName: 'Lecture',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (e) {
    // La session média a échoué : plutôt que de bloquer le démarrage sur
    // un écran vide, on continue sans notification ni écran verrouillé.
    // La lecture, elle, fonctionne toujours.
    audioInitError = e.toString();
    audio = AudioHandlerMusique();
  }
}
