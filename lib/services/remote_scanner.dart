import 'package:path/path.dart' as p;

import '../models/media_item.dart';
import '../models/server_profile.dart';
import '../models/track.dart';
import 'music_scanner.dart';
import 'remote_tag_reader.dart';
import 'scanner.dart';
import 'server_api.dart';

/// Résultat d'un parcours de serveur : les deux natures y cohabitent.
class RemoteScanResult {
  final List<MediaItem> items;
  final List<Track> tracks;
  final String? error;

  const RemoteScanResult({
    this.items = const [],
    this.tracks = const [],
    this.error,
  });
}

/// Parcourt un serveur et en tire une bibliothèque, exactement comme le
/// scan local le fait avec des dossiers.
///
/// La différence tient à un point : chaque niveau coûte une requête. On
/// limite donc la profondeur et on regroupe par dossier plutôt que
/// d'interroger fichier par fichier.
class RemoteScanner {
  /// Profondeur maximale. Au-delà, une bibliothèque mal rangée
  /// déclencherait des centaines de requêtes pour rien.
  static const int maxDepth = 4;

  static Future<RemoteScanResult> scan(
    ServerProfile server, {
    void Function(String message)? onProgress,
  }) async {
    final racines = await ServerApi.roots(server);
    if (racines.isEmpty) {
      return RemoteScanResult(
          error: ServerApi.lastError ?? 'Aucun dossier publié.');
    }

    final items = <MediaItem>[];
    final tracks = <Track>[];

    for (final racine in racines) {
      onProgress?.call('Analyse de ${racine.name}');
      // Le nom du dossier publié oriente la nature de ce qu'on y trouve.
      final natureProbable = _natureDepuisNom(racine.name);
      await _parcourir(
        server,
        racine.path,
        racine.name,
        natureProbable,
        items,
        tracks,
        0,
        onProgress,
      );
    }

    return RemoteScanResult(items: items, tracks: tracks);
  }

  /// Devine si un dossier publié contient des animes, des films, des séries
  /// ou de la musique. C'est un simple préréglage : la fiche récupérée
  /// ensuite fait autorité, et l'utilisateur peut corriger.
  static MediaKind? _natureDepuisNom(String nom) {
    final n = nom.toLowerCase();
    if (n.contains('anime') || n.contains('manga')) return MediaKind.anime;
    if (n.contains('film') || n.contains('movie')) return MediaKind.movie;
    if (n.contains('serie') || n.contains('série') || n.contains('show')) {
      return MediaKind.series;
    }
    return null;
  }

  static bool _estMusique(String nom) {
    final n = nom.toLowerCase();
    return n.contains('music') || n.contains('musique') || n.contains('audio');
  }

  static Future<void> _parcourir(
    ServerProfile server,
    String chemin,
    String racineNom,
    MediaKind? nature,
    List<MediaItem> items,
    List<Track> tracks,
    int profondeur,
    void Function(String message)? onProgress,
  ) async {
    if (profondeur > maxDepth) return;

    final entrees = await ServerApi.list(server, chemin);
    if (entrees.isEmpty) return;

    final videos = entrees.where((e) => e.kind == RemoteKind.video).toList();
    final audios = entrees.where((e) => e.kind == RemoteKind.audio).toList();
    final sousTitres =
        entrees.where((e) => e.kind == RemoteKind.subtitle).toList();
    final dossiers = entrees.where((e) => e.isFolder).toList();

    // Un dossier qui contient des vidéos forme un titre.
    if (videos.isNotEmpty) {
      final titre = p.basename(chemin.replaceAll('\\', '/'));
      final episodes = <Episode>[];

      for (final v in videos) {
        final base = v.name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
        final infos = Scanner.parseName(base, context: chemin);
        episodes.add(Episode(
          path: v.path,
          name: v.name,
          season: infos.season,
          number: infos.number,
          bonus: infos.bonus,
          subtitles: sousTitres
              .where((s) => s.name.startsWith(base))
              .map((s) => s.path)
              .toList(),
          addedAtMs: v.modifiedMs,
        ));
      }

      episodes.sort((a, b) {
        if (a.bonus != b.bonus) return a.bonus ? 1 : -1;
        final sa = a.season ?? 1;
        final sb = b.season ?? 1;
        if (sa != sb) return sa.compareTo(sb);
        final na = a.number ?? 9999;
        final nb = b.number ?? 9999;
        if (na != nb) return na.compareTo(nb);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      // Un fichier isolé sans numéro : c'est un film.
      final numerotes =
          episodes.where((e) => !e.bonus && e.number != null).length;
      final deduite = (episodes.length <= 1 && numerotes == 0)
          ? MediaKind.movie
          : MediaKind.series;

      items.add(MediaItem(
        id: '${server.id}|$chemin',
        serverId: server.id,
        kind: nature ?? deduite,
        folderTitle: titre,
        episodes: episodes,
      ));
    }

    // Un dossier qui contient de l'audio donne des morceaux.
    if (audios.isNotEmpty) {
      final pochette = entrees
          .where((e) => e.kind == RemoteKind.image)
          .map((e) => e.path)
          .toList();

      onProgress?.call('Lecture des étiquettes · ${p.basename(chemin)}');

      for (final a in audios) {
        // Les étiquettes se lisent par requête partielle : on ne
        // télécharge que le début du fichier.
        final tags = await RemoteTagReader.read(server, a.path);
        final nom = a.name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');

        tracks.add(Track(
          path: a.path,
          serverId: server.id,
          title: tags.title ?? nom,
          artist: tags.artist ?? _remonter(chemin, 2),
          albumArtist: tags.albumArtist ?? tags.artist,
          album: tags.album ?? _remonter(chemin, 1),
          trackNumber: tags.trackNumber,
          discNumber: tags.discNumber,
          year: tags.year,
          genre: tags.genre,
          durationMs: tags.duration?.inMilliseconds,
          coverPath: pochette.isEmpty ? null : pochette.first,
          embeddedArt: tags.artwork != null,
          taggedFromFile: tags.isEmpty,
          addedAtMs: a.modifiedMs,
        ));
      }
    }

    for (final d in dossiers) {
      await _parcourir(server, d.path, racineNom, nature, items, tracks,
          profondeur + 1, onProgress);
    }
  }

  /// Remonte de N niveaux dans un chemin distant.
  static String _remonter(String chemin, int niveaux) {
    final parts = chemin.replaceAll('\\', '/').split('/')
      ..removeWhere((e) => e.isEmpty);
    final index = parts.length - niveaux;
    if (index < 0 || index >= parts.length) return 'Inconnu';
    return parts[index];
  }

  /// Extensions reconnues côté musique, pour rester cohérent avec le local.
  static bool estAudio(String nom) => MusicScanner.audioExtensions
      .contains('.${nom.toLowerCase().split('.').last}');
}
