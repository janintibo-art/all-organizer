import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// OpenSubtitles : recherche et téléchargement de sous-titres.
///
/// Une clé d'API gratuite suffit pour chercher. Le téléchargement est soumis
/// à un quota quotidien, plus généreux si l'on renseigne aussi un compte.
class OpenSubtitles {
  static const String _host = 'api.opensubtitles.com';
  static const String _agent = 'MediaOrganizer v1.0';

  static String? lastError;
  static String? _token;
  static int? remainingDownloads;

  static Map<String, String> _headers(String apiKey, {bool json = false}) => {
        'Api-Key': apiKey.trim(),
        'User-Agent': _agent,
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  /// Connexion facultative : elle augmente le quota de téléchargement.
  static Future<bool> login(String apiKey, String user, String password) async {
    if (user.trim().isEmpty || password.isEmpty) return false;
    try {
      final res = await http
          .post(
            Uri.https(_host, '/api/v1/login'),
            headers: _headers(apiKey, json: true),
            body: jsonEncode({'username': user.trim(), 'password': password}),
          )
          .timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) {
        lastError = 'Connexion refusée (HTTP ${res.statusCode}).';
        return false;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      _token = body['token']?.toString();
      return _token != null;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  /// Cherche des sous-titres. L'empreinte, quand elle est fournie, prime :
  /// elle désigne exactement ce fichier.
  static Future<List<SubtitleResult>> search({
    required String apiKey,
    required String query,
    String language = 'fr',
    int? season,
    int? episode,
    String? moviehash,
  }) async {
    lastError = null;
    if (apiKey.trim().isEmpty) {
      lastError = 'Aucune clé OpenSubtitles renseignée.';
      return const [];
    }

    final params = <String, String>{
      'languages': language,
      'query': query,
      if (season != null) 'season_number': '$season',
      if (episode != null) 'episode_number': '$episode',
      if (moviehash != null) 'moviehash': moviehash,
    };

    try {
      final res = await http
          .get(Uri.https(_host, '/api/v1/subtitles', params),
              headers: _headers(apiKey))
          .timeout(const Duration(seconds: 25));

      if (res.statusCode != 200) {
        lastError = 'HTTP ${res.statusCode}';
        return const [];
      }

      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = body['data'] as List? ?? const [];
      final results = <SubtitleResult>[];

      for (final item in data) {
        final attrs = (item as Map)['attributes'] as Map?;
        if (attrs == null) continue;
        final files = attrs['files'] as List? ?? const [];
        if (files.isEmpty) continue;
        final fileId = (files.first as Map)['file_id'];
        if (fileId is! int) continue;

        results.add(SubtitleResult(
          fileId: fileId,
          release: attrs['release']?.toString() ?? 'Sans nom',
          language: attrs['language']?.toString() ?? language,
          downloads: (attrs['download_count'] as num?)?.toInt() ?? 0,
          fromHash: attrs['moviehash_match'] == true,
        ));
      }

      // Une correspondance par empreinte passe devant tout le reste.
      results.sort((a, b) {
        if (a.fromHash != b.fromHash) return a.fromHash ? -1 : 1;
        return b.downloads.compareTo(a.downloads);
      });
      return results;
    } catch (e) {
      lastError = e.toString();
      return const [];
    }
  }

  /// Télécharge un sous-titre et renvoie le chemin du fichier local.
  static Future<String?> download({
    required String apiKey,
    required SubtitleResult result,
    required String episodePath,
  }) async {
    lastError = null;
    try {
      final res = await http
          .post(
            Uri.https(_host, '/api/v1/download'),
            headers: _headers(apiKey, json: true),
            body: jsonEncode({'file_id': result.fileId}),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode == 406) {
        lastError = 'Quota de téléchargement épuisé pour aujourd\'hui.';
        return null;
      }
      if (res.statusCode != 200) {
        lastError = 'HTTP ${res.statusCode} — ${res.body}';
        return null;
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      remainingDownloads = (body['remaining'] as num?)?.toInt();
      final link = body['link']?.toString();
      if (link == null) {
        lastError = 'Lien de téléchargement absent.';
        return null;
      }

      final file = await http
          .get(Uri.parse(link))
          .timeout(const Duration(seconds: 40));
      if (file.statusCode != 200) {
        lastError = 'Fichier inaccessible (HTTP ${file.statusCode}).';
        return null;
      }

      // On écrit à côté de la vidéo si possible, sinon dans l'application.
      final base = p.basenameWithoutExtension(episodePath);
      final target = File(p.join(
          p.dirname(episodePath), '$base.${result.language}.srt'));
      try {
        await target.writeAsBytes(file.bodyBytes, flush: true);
        return target.path;
      } catch (_) {
        final dir = await getApplicationSupportDirectory();
        final fallback = Directory(p.join(dir.path, 'sous-titres'));
        if (!fallback.existsSync()) fallback.createSync(recursive: true);
        final alt = File(p.join(fallback.path,
            '${base.hashCode.toUnsigned(32)}.${result.language}.srt'));
        await alt.writeAsBytes(file.bodyBytes, flush: true);
        return alt.path;
      }
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }
}

class SubtitleResult {
  final int fileId;
  final String release;
  final String language;
  final int downloads;
  final bool fromHash;

  const SubtitleResult({
    required this.fileId,
    required this.release,
    required this.language,
    required this.downloads,
    required this.fromHash,
  });

  String get label => fromHash
      ? 'Synchronisé avec ton fichier · $release'
      : '$release · $downloads téléchargements';
}
