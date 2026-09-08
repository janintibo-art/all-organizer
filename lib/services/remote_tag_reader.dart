import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/server_profile.dart';
import 'http_client.dart';
import 'server_api.dart';
import 'tag_reader.dart';

/// Lit les étiquettes d'un fichier audio **sans le télécharger**.
///
/// Le serveur répondant aux requêtes partielles, on demande seulement le
/// début du fichier — là où se trouvent ID3, les commentaires Vorbis et les
/// atomes M4A. Deux mégaoctets suffisent, pochette comprise, contre parfois
/// cent pour le morceau entier.
class RemoteTagReader {
  static const int _tete = 2 * 1024 * 1024;

  static String? lastError;

  static Future<AudioTags> read(ServerProfile server, String path) async {
    lastError = null;
    try {
      final url = ServerApi.fileUrl(server, path);
      final res = await http.get(
        Uri.parse(url),
        headers: {
          ...AppHttp.headers(),
          // Sans cet en-tête, le serveur enverrait le fichier complet.
          'Range': 'bytes=0-${_tete - 1}',
        },
      ).timeout(const Duration(seconds: 30));

      // 206 : contenu partiel, ce qu'on espère. 200 : le serveur a ignoré
      // la demande et tout envoyé, ce qui reste exploitable.
      if (res.statusCode != 206 && res.statusCode != 200) {
        lastError = 'HTTP ${res.statusCode}';
        return const AudioTags();
      }

      return TagReader.readBytes(
        Uint8List.fromList(res.bodyBytes),
        path.split('.').last.toLowerCase(),
      );
    } catch (e) {
      lastError = e.toString();
      return const AudioTags();
    }
  }

  /// Récupère uniquement la pochette, une fois par album.
  static Future<Uint8List?> artwork(
      ServerProfile server, String path) async {
    final tags = await read(server, path);
    return tags.artwork;
  }
}
