import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Range les pochettes : celles extraites des fichiers, et celles posées
/// à côté des morceaux sous forme d'image.
class CoverCache {
  static Directory? _dir;

  /// Noms usuels des pochettes déposées dans un dossier d'album.
  static const List<String> _nomsUsuels = [
    'cover', 'folder', 'front', 'album', 'albumart', 'artwork', 'pochette',
  ];

  static const List<String> _extensions = ['.jpg', '.jpeg', '.png', '.webp'];

  static Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'pochettes'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _dir = dir;
    return dir;
  }

  /// Une pochette par album plutôt que par morceau : douze fichiers d'un
  /// même disque portent la même image, inutile de la stocker douze fois.
  static Future<String?> saveEmbedded(String trackPath, Uint8List bytes) async {
    if (bytes.length < 512) return null;
    try {
      final dir = await _folder();
      final cle = p.dirname(trackPath).hashCode.toUnsigned(32).toRadixString(16);
      final file = File(p.join(dir.path, '$cle.img'));
      if (file.existsSync() && file.lengthSync() > 512) return file.path;
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Cherche une image déposée à côté des morceaux.
  static String? findBeside(String trackPath) {
    try {
      final dir = Directory(p.dirname(trackPath));
      final fichiers = dir
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => _extensions.contains(p.extension(f.path).toLowerCase()))
          .toList();
      if (fichiers.isEmpty) return null;

      for (final nom in _nomsUsuels) {
        for (final f in fichiers) {
          if (p.basenameWithoutExtension(f.path).toLowerCase() == nom) {
            return f.path;
          }
        }
      }
      // Aucun nom usuel : la première image fera l'affaire.
      return fichiers.first.path;
    } catch (_) {
      return null;
    }
  }

  static bool exists(String? path) =>
      path != null && path.isNotEmpty && File(path).existsSync();

  static Future<int> clear() async {
    try {
      final dir = await _folder();
      var count = 0;
      for (final f in dir.listSync()) {
        if (f is File) {
          f.deleteSync();
          count++;
        }
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> sizeInBytes() async {
    try {
      final dir = await _folder();
      var total = 0;
      for (final f in dir.listSync()) {
        if (f is File) total += f.lengthSync();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}
