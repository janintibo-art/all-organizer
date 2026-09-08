import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/track.dart';
import 'tag_reader.dart';

/// Parcourt les dossiers, lit les étiquettes et construit les morceaux.
class MusicScanner {
  static const Set<String> audioExtensions = {
    '.mp3', '.flac', '.m4a', '.aac', '.ogg', '.opus', '.wav',
    '.wma', '.alac', '.aiff', '.ape', '.mpc', '.wv',
  };

  /// Motifs courants dans les noms de fichiers, du plus précis au plus large.
  static final List<RegExp> _motifs = [
    // 03 - Artiste - Titre
    RegExp(r'^\s*(\d{1,3})\s*[-–_.]\s*(.+?)\s*[-–]\s*(.+)$'),
    // 03 - Titre
    RegExp(r'^\s*(\d{1,3})\s*[-–_.]\s*(.+)$'),
    // Artiste - Titre
    RegExp(r'^(.+?)\s+[-–]\s+(.+)$'),
  ];

  static const List<String> _nomsPochette = [
    'cover', 'folder', 'front', 'album', 'albumart', 'artwork', 'pochette',
  ];

  static const List<String> _extImages = ['.jpg', '.jpeg', '.png', '.webp'];

  /// Image déposée à côté des morceaux. Pure lecture de fichiers, donc
  /// utilisable dans un isolate.
  static String? findCoverBeside(String trackPath) {
    try {
      final dir = Directory(p.dirname(trackPath));
      final images = dir
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => _extImages.contains(p.extension(f.path).toLowerCase()))
          .toList();
      if (images.isEmpty) return null;
      for (final nom in _nomsPochette) {
        for (final f in images) {
          if (p.basenameWithoutExtension(f.path).toLowerCase() == nom) {
            return f.path;
          }
        }
      }
      return images.first.path;
    } catch (_) {
      return null;
    }
  }

  /// Version destinée à `compute` : le scan tourne dans un isolate.
  static Future<List<Map<String, dynamic>>> scanJson(
      List<String> roots) async {
    final found = await scan(roots);
    return found.map((t) => t.toJson()).toList();
  }

  static Future<List<Track>> scan(List<String> roots) async {
    final tracks = <Track>[];

    for (final root in roots) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;

      final stream = dir.list(recursive: true, followLinks: false).handleError(
            (dynamic _) {},
            test: (dynamic e) => e is FileSystemException,
          );

      await for (final entity in stream) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (!audioExtensions.contains(ext)) continue;
        tracks.add(await describe(entity.path, root));
      }
    }

    tracks.sort((a, b) => a.sortTitle.compareTo(b.sortTitle));
    return tracks;
  }

  /// Construit un morceau : les étiquettes priment, le chemin complète.
  ///
  /// C'est l'ordre qui compte pour une collection underground : beaucoup de
  /// fichiers n'ont aucune étiquette, mais leur arborescence dit tout —
  /// Artiste / Album / 03 Titre.mp3
  static Future<Track> describe(String path, String root) async {
    final tags = await TagReader.read(path);
    final nom = p.basenameWithoutExtension(path);

    // L'arborescence : le dossier parent est souvent l'album, celui
    // au-dessus l'artiste.
    final dossierAlbum = p.basename(p.dirname(path));
    final dossierArtiste = p.basename(p.dirname(p.dirname(path)));
    final sousRacine = p.equals(p.dirname(path), root);

    String? titreFichier;
    String? artisteFichier;
    int? pisteFichier;

    for (final motif in _motifs) {
      final m = motif.firstMatch(nom);
      if (m == null) continue;
      if (motif == _motifs[0]) {
        pisteFichier = int.tryParse(m.group(1)!);
        artisteFichier = m.group(2)!.trim();
        titreFichier = m.group(3)!.trim();
      } else if (motif == _motifs[1]) {
        pisteFichier = int.tryParse(m.group(1)!);
        titreFichier = m.group(2)!.trim();
      } else {
        artisteFichier = m.group(1)!.trim();
        titreFichier = m.group(2)!.trim();
      }
      break;
    }

    final titre = tags.title ?? titreFichier ?? nom;
    final artiste = tags.artist ??
        artisteFichier ??
        (sousRacine ? 'Artiste inconnu' : dossierArtiste);
    final album = tags.album ?? (sousRacine ? 'Sans album' : dossierAlbum);

    int? modifie;
    try {
      modifie = File(path).statSync().modified.millisecondsSinceEpoch;
    } catch (_) {}

    // Aucun appel de module ici : ce code tourne dans un isolate, où les
    // canaux de plateforme ne répondent pas. Une pochette intégrée est
    // seulement signalée ; elle sera extraite plus tard, une fois par album.
    final cover = findCoverBeside(path);

    return Track(
      path: path,
      title: titre,
      artist: artiste,
      albumArtist: tags.albumArtist ?? artiste,
      album: album,
      trackNumber: tags.trackNumber ?? pisteFichier,
      discNumber: tags.discNumber,
      year: tags.year,
      genre: tags.genre,
      durationMs: tags.duration?.inMilliseconds,
      coverPath: cover,
      embeddedArt: tags.artwork != null,
      taggedFromFile: tags.isEmpty,
      addedAtMs: modifie,
    );
  }
}
