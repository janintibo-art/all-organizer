import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'http_client.dart';

/// Enregistre les affiches sur le disque pour que la bibliothèque reste
/// illustrée sans connexion, et pour éviter de retélécharger à chaque écran.
class PosterCache {
  static Directory? _dir;

  static Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'affiches'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _dir = dir;
    return dir;
  }

  static String _fileName(String id, String url) {
    final a = id.hashCode.toUnsigned(32).toRadixString(16);
    final b = url.hashCode.toUnsigned(32).toRadixString(16);
    return '$a-$b.img';
  }

  /// Télécharge l'affiche si elle n'est pas déjà là. Renvoie le chemin local.
  static Future<String?> ensure(String id, String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final dir = await _folder();
      final file = File(p.join(dir.path, _fileName(id, url)));
      if (file.existsSync() && await file.length() > 1024) return file.path;

      final res =
          await http
          .get(Uri.parse(url), headers: AppHttp.headers(accept: 'image/*'))
          .timeout(const Duration(seconds: 25));
      if (res.statusCode != 200 || res.bodyBytes.length < 1024) return null;
      await file.writeAsBytes(res.bodyBytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Enregistre une image fournie par le lecteur comme affiche.
  static Future<String?> saveBytes(String id, Uint8List bytes) async {
    if (bytes.length < 1024) return null;
    try {
      final dir = await _folder();
      final file = File(p.join(dir.path,
          'capture-${id.hashCode.toUnsigned(32).toRadixString(16)}.png'));
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
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
