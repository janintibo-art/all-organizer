import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/media_meta.dart';
import '../models/server_profile.dart';
import 'http_client.dart';

/// Dialogue avec le serveur de médias.
class ServerApi {
  static String? lastError;

  static Map<String, String> _headers(ServerProfile s) => {
        ...AppHttp.headers(),
        if (s.token.trim().isNotEmpty) 'X-Jeton': s.token.trim(),
      };

  /// Vérifie que le serveur répond. Sans jeton : c'est la seule route
  /// ouverte, ce qui permet de distinguer « éteint » de « jeton refusé ».
  static Future<String?> ping(ServerProfile s,
      {Duration timeout = const Duration(seconds: 8)}) async {
    lastError = null;
    if (s.baseUrl.isEmpty) {
      lastError = 'Adresse vide.';
      return null;
    }
    try {
      final res = await http
          .get(Uri.parse('${s.baseUrl}/api/ping'), headers: _headers(s))
          .timeout(timeout);
      if (res.statusCode != 200) {
        lastError = 'HTTP ${res.statusCode}';
        return null;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return '${body['nom'] ?? 'Serveur'} · version ${body['version'] ?? '?'}';
    } catch (e) {
      lastError = _lisible(e);
      return null;
    }
  }

  /// Dossiers publiés par le serveur.
  static Future<List<RemoteEntry>> roots(ServerProfile s) async {
    lastError = null;
    try {
      final res = await http
          .get(Uri.parse('${s.baseUrl}/api/racines'), headers: _headers(s))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 401) {
        lastError = 'Jeton refusé par le serveur.';
        return const [];
      }
      if (res.statusCode != 200) {
        lastError = 'HTTP ${res.statusCode}';
        return const [];
      }
      final body =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return (body['racines'] as List? ?? const [])
          .map((e) => RemoteEntry(
                name: (e as Map)['nom']?.toString() ?? 'Dossier',
                path: e['nom']?.toString() ?? '',
                kind: RemoteKind.folder,
              ))
          .toList();
    } catch (e) {
      lastError = _lisible(e);
      return const [];
    }
  }

  /// Contenu d'un dossier.
  static Future<List<RemoteEntry>> list(
      ServerProfile s, String path) async {
    lastError = null;
    try {
      final uri = Uri.parse('${s.baseUrl}/api/liste')
          .replace(queryParameters: {'chemin': path});
      final res = await http
          .get(uri, headers: _headers(s))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 401) {
        lastError = 'Jeton refusé par le serveur.';
        return const [];
      }
      if (res.statusCode != 200) {
        lastError = 'HTTP ${res.statusCode}';
        return const [];
      }

      final body =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final out = <RemoteEntry>[];

      for (final d in body['dossiers'] as List? ?? const []) {
        final map = d as Map;
        out.add(RemoteEntry(
          name: map['nom']?.toString() ?? '',
          path: map['chemin']?.toString() ?? '',
          kind: RemoteKind.folder,
        ));
      }
      for (final f in body['fichiers'] as List? ?? const []) {
        final map = f as Map;
        // Un serveur ancien n'annonce pas la nature : on retombe sur
        // l'ancien champ « video ».
        final nature = map['nature']?.toString() ??
            (map['video'] == true ? 'video' : 'autre');
        out.add(RemoteEntry(
          name: map['nom']?.toString() ?? '',
          path: map['chemin']?.toString() ?? '',
          kind: RemoteEntry.kindFrom(nature),
          size: (map['taille'] as num?)?.toInt() ?? 0,
          modifiedMs: (map['modifie'] as num?)?.toInt(),
        ));
      }
      return out;
    } catch (e) {
      lastError = _lisible(e);
      return const [];
    }
  }

  /// Adresse de lecture d'un fichier.
  ///
  /// Le jeton passe par l'adresse et non par un en-tête : les lecteurs
  /// vidéo et audio ouvrent l'adresse eux-mêmes, sans nos en-têtes.
  /// Fiches deja identifiees par le PC. Chaque entree donne le chemin
  /// publie et les metadonnees a recopier. Renvoie null si le serveur ne
  /// connait pas cette route — une version anterieure, par exemple.
  static Future<List<RemoteFiche>?> library(ServerProfile s) async {
    lastError = null;
    try {
      final res = await http
          .get(Uri.parse('${s.baseUrl}/api/bibliotheque'), headers: _headers(s))
          .timeout(const Duration(seconds: 30));

      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) {
        lastError = 'HTTP ${res.statusCode}';
        return null;
      }

      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return (body['fiches'] as List? ?? [])
          .map((e) => RemoteFiche.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      lastError = _lisible(e);
      return null;
    }
  }

  static String fileUrl(ServerProfile s, String path) {
    final uri = Uri.parse('${s.baseUrl}/fichier').replace(queryParameters: {
      'chemin': path,
      if (s.token.trim().isNotEmpty) 'jeton': s.token.trim(),
    });
    return uri.toString();
  }

  static String _lisible(Object e) {
    final texte = e.toString();
    if (texte.contains('SocketException') ||
        texte.contains('Connection refused')) {
      return 'Serveur injoignable. Il est peut-être éteint, ou le pare-feu '
          'bloque la connexion.';
    }
    if (texte.contains('TimeoutException')) {
      return 'Pas de réponse dans le délai imparti.';
    }
    return texte;
  }
}


/// Une fiche publiee par le serveur, rangee sous le chemin que le client voit.
class RemoteFiche {
  final String chemin;
  final String titreDossier;
  final MediaMeta fiche;

  const RemoteFiche({
    required this.chemin,
    required this.titreDossier,
    required this.fiche,
  });

  factory RemoteFiche.fromJson(Map<String, dynamic> j) => RemoteFiche(
        chemin: j['chemin'] as String? ?? '',
        titreDossier: j['titreDossier'] as String? ?? '',
        fiche: MediaMeta.fromJson(
            Map<String, dynamic>.from(j['fiche'] as Map? ?? {})),
      );
}
