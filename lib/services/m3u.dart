import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/track.dart';

/// Import et export au format M3U, celui que lisent tous les autres
/// lecteurs. C'est ce qui permet de sortir ses listes de l'application.
class M3u {
  /// Écrit une liste. Les chemins sont relatifs au fichier quand c'est
  /// possible, pour qu'une clé USB reste lisible sur une autre machine.
  static Future<String> export(
    Playlist playlist,
    List<Track> tracks,
    String dossier,
  ) async {
    final buffer = StringBuffer('#EXTM3U\n');
    for (final t in tracks) {
      final secondes = (t.durationMs ?? 0) ~/ 1000;
      buffer.writeln('#EXTINF:$secondes,${t.artist} - ${t.title}');
      buffer.writeln(_relatif(t.path, dossier));
    }

    final nom = playlist.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final fichier = File(p.join(dossier, '$nom.m3u8'));
    await fichier.writeAsString(buffer.toString(), flush: true);
    return fichier.path;
  }

  static String _relatif(String chemin, String dossier) {
    try {
      if (p.isWithin(dossier, chemin)) return p.relative(chemin, from: dossier);
    } catch (_) {}
    return chemin;
  }

  /// Lit une liste et renvoie les chemins existants.
  static Future<List<String>> import(String fichier) async {
    final base = p.dirname(fichier);
    final lignes = await File(fichier).readAsLines();
    final chemins = <String>[];

    for (final ligne in lignes) {
      final propre = ligne.trim();
      if (propre.isEmpty || propre.startsWith('#')) continue;

      // Les listes venues de Windows utilisent l'antislash.
      final normalise = propre.replaceAll('\\', p.separator);
      final absolu =
          p.isAbsolute(normalise) ? normalise : p.normalize(p.join(base, normalise));

      if (File(absolu).existsSync()) chemins.add(absolu);
    }
    return chemins;
  }

  static String nomDepuisFichier(String fichier) =>
      p.basenameWithoutExtension(fichier);
}
