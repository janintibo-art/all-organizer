import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'library_controller.dart';

/// Serveur de medias embarque dans l'application de bureau.
///
/// Reprend a l'identique le protocole de `serveur.py` : /api/ping,
/// /api/racines, /api/liste et /fichier avec les requetes partielles.
/// Un telephone qui parlait a la version Python n'a rien a changer.
class MediaServer {
  static const String version = '1.1';

  static const Set<String> _video = {
    '.mkv', '.mp4', '.avi', '.mov', '.m4v', '.wmv', '.flv', '.webm',
    '.mpg', '.mpeg', '.ts', '.m2ts', '.ogv', '.rmvb', '.divx',
  };

  static const Set<String> _audio = {
    '.mp3', '.flac', '.m4a', '.aac', '.ogg', '.opus', '.wav',
    '.wma', '.alac', '.aiff', '.ape', '.mpc', '.wv',
  };

  static const Set<String> _sousTitre = {
    '.srt', '.ass', '.ssa', '.sub', '.vtt', '.idx',
  };

  static const Set<String> _image = {'.jpg', '.jpeg', '.png', '.webp'};

  static HttpServer? _http;

  /// Racines publiees : nom affiche -> chemin reel sur le disque.
  static final Map<String, String> _racines = {};

  static String? _jeton;

  /// Derniere erreur de demarrage, affichee dans les reglages.
  static String? lastError;

  static bool get running => _http != null;
  static int get port => _http?.port ?? 0;
  static List<String> get racines => _racines.keys.toList();

  /// Le serveur n'a de sens que sur un ordinateur : un telephone n'a pas
  /// vocation a publier sa carte SD sur le reseau.
  static bool get supported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  // ------------------------------------------------------------- cycle de vie

  /// Demarre le serveur. Renvoie vrai si l'ecoute est ouverte.
  static Future<bool> start({
    required List<String> dossiers,
    int port = 8321,
    String jeton = '',
  }) async {
    await stop();
    lastError = null;

    if (!supported) {
      lastError = 'Le serveur ne fonctionne que sur ordinateur.';
      return false;
    }

    _racines.clear();
    for (final dossier in dossiers) {
      final chemin = _reel(dossier);
      if (chemin == null || !Directory(chemin).existsSync()) continue;
      // Deux dossiers de meme nom ne doivent pas s'ecraser.
      final base = p.basename(chemin).isEmpty
          ? chemin.replaceAll(':', '')
          : p.basename(chemin);
      var nom = base;
      var n = 2;
      while (_racines.containsKey(nom)) {
        nom = '$base ($n)';
        n++;
      }
      _racines[nom] = chemin;
    }

    if (_racines.isEmpty) {
      lastError = 'Aucun dossier valide à publier.';
      return false;
    }

    _jeton = jeton.trim().isEmpty ? null : jeton.trim();

    try {
      _http = await HttpServer.bind(InternetAddress.anyIPv4, port);
    } catch (e) {
      lastError = 'Port $port indisponible — $e';
      return false;
    }

    _http!.listen(_traiter, onError: (Object e) => lastError = '$e');
    return true;
  }

  static Future<void> stop() async {
    final serveur = _http;
    _http = null;
    if (serveur != null) {
      try {
        await serveur.close(force: true);
      } catch (_) {}
    }
  }

  /// Adresse du PC sur le reseau local, celle a saisir dans le telephone.
  static Future<String> localAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      for (final i in interfaces) {
        for (final a in i.addresses) {
          if (!a.isLoopback) return a.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  // ------------------------------------------------------------------ routage

  static Future<void> _traiter(HttpRequest requete) async {
    final reponse = requete.response;
    reponse.headers.set('Access-Control-Allow-Origin', '*');

    if (requete.method == 'OPTIONS') {
      reponse.statusCode = 204;
      reponse.headers.set('Access-Control-Allow-Headers', 'X-Jeton, Range');
      await reponse.close();
      return;
    }

    final route = requete.uri.path;
    final params = requete.uri.queryParameters;
    final enteteSeule = requete.method == 'HEAD';

    try {
      if (route == '/api/ping') {
        await _json(reponse, {
          'nom': 'Serveur Media Organizer',
          'version': version,
          'protege': _jeton != null,
        });
        return;
      }

      if (!_autorise(requete, params)) {
        await _json(reponse, {'erreur': 'Jeton absent ou invalide.'}, 401);
        return;
      }

      switch (route) {
        case '/api/racines':
          await _json(reponse, {
            'racines': [
              for (final e in _racines.entries)
                {'nom': e.key, 'chemin': e.value}
            ]
          });
          return;
        case '/api/bibliotheque':
          await _json(reponse, _bibliotheque());
          return;
        case '/api/liste':
          await _lister(reponse, params['chemin'] ?? '');
          return;
        case '/fichier':
          await _envoyerFichier(requete, reponse, params['chemin'] ?? '',
              enteteSeule);
          return;
        case '/':
          await _accueil(reponse);
          return;
      }

      await _json(reponse, {'erreur': 'Route inconnue.'}, 404);
    } catch (e) {
      lastError = '$e';
      try {
        await _json(reponse, {'erreur': '$e'}, 500);
      } catch (_) {}
    }
  }

  static bool _autorise(HttpRequest requete, Map<String, String> params) {
    if (_jeton == null) return true;
    final fourni =
        params['jeton'] ?? requete.headers.value('X-Jeton') ?? '';
    return fourni == _jeton;
  }

  static Future<void> _json(HttpResponse reponse, Object donnees,
      [int code = 200]) async {
    final corps = utf8.encode(jsonEncode(donnees));
    reponse.statusCode = code;
    reponse.headers.contentType =
        ContentType('application', 'json', charset: 'utf-8');
    reponse.headers.contentLength = corps.length;
    reponse.add(corps);
    await reponse.close();
  }

  // ------------------------------------------------------------- bibliotheque

  /// Fiches deja identifiees sur ce PC, rangees sous le chemin que le
  /// telephone voit. Il n'a plus qu'a les recopier au lieu de refaire les
  /// recherches TMDB et AniList.
  ///
  /// Aucun fichier n'est envoye : seulement les titres, affiches, synopsis,
  /// genres et numeros d'episodes.
  static Map<String, Object> _bibliotheque() {
    final fiches = <Map<String, Object?>>[];

    for (final item in library.items) {
      // Les fiches venues d'un autre serveur ne sont pas les notres.
      if (item.remote || !item.metaFetched) continue;

      final relatif = _relatif(item.id);
      if (relatif == null) continue;

      fiches.add({
        'chemin': relatif,
        'fiche': item.toMeta().toJson(),
        'titreDossier': item.folderTitle,
      });
    }

    return {
      'version': 1,
      'genereLe': DateTime.now().toIso8601String(),
      'fiches': fiches,
    };
  }

  /// Traduit un chemin disque en chemin publie, ou null s'il n'est sous
  /// aucune racine.
  static String? _relatif(String cheminDisque) {
    final cible = _reel(cheminDisque);
    if (cible == null) return null;

    for (final entree in _racines.entries) {
      final base = _reel(entree.value);
      if (base == null) continue;
      if (cible == base) return entree.key;
      if (cible.startsWith(base + Platform.pathSeparator)) {
        final reste = cible
            .substring(base.length + 1)
            .replaceAll('\\', '/');
        return '${entree.key}/$reste';
      }
    }
    return null;
  }

  // ------------------------------------------------------------------ listage

  /// Traduit un chemin de l'API en chemin disque, en refusant les evasions.
  ///
  /// Sans ce controle, un « ../../ » bien place donnerait acces a tout le
  /// disque. On verifie donc que le chemin resolu reste sous une racine
  /// declaree, apres resolution des liens symboliques.
  static String? _cheminReel(String demande) {
    if (demande.isEmpty) return null;

    final morceaux =
        demande.replaceAll('\\', '/').split('/').where((m) => m.isNotEmpty);
    if (morceaux.isEmpty) return null;

    final nomRacine = morceaux.first;
    final reste = morceaux.skip(1).join('/');

    final racine = _racines[nomRacine];
    if (racine == null) return null;

    final base = _reel(racine);
    final cible = _reel(reste.isEmpty ? racine : p.join(racine, reste));
    if (base == null || cible == null) return null;

    if (cible != base && !cible.startsWith(base + Platform.pathSeparator)) {
      return null;
    }
    return cible;
  }

  static String? _reel(String chemin) {
    try {
      return File(chemin).resolveSymbolicLinksSync();
    } catch (_) {
      try {
        return p.normalize(p.absolute(chemin));
      } catch (_) {
        return null;
      }
    }
  }

  static String _nature(String nom) {
    final ext = p.extension(nom).toLowerCase();
    if (_video.contains(ext)) return 'video';
    if (_audio.contains(ext)) return 'audio';
    if (_sousTitre.contains(ext)) return 'sous-titre';
    if (_image.contains(ext)) return 'image';
    return 'autre';
  }

  static Future<void> _lister(HttpResponse reponse, String demande) async {
    if (demande.isEmpty) {
      // Racine virtuelle : la liste des dossiers publies.
      await _json(reponse, {
        'chemin': '',
        'dossiers': [
          for (final nom in _racines.keys) {'nom': nom, 'chemin': nom}
        ],
        'fichiers': const [],
      });
      return;
    }

    final cible = _cheminReel(demande);
    if (cible == null || !Directory(cible).existsSync()) {
      await _json(reponse, {'erreur': 'Dossier introuvable.'}, 404);
      return;
    }

    final dossiers = <Map<String, Object>>[];
    final fichiers = <Map<String, Object>>[];

    try {
      for (final entree in Directory(cible).listSync(followLinks: false)) {
        final nom = p.basename(entree.path);
        if (nom.startsWith('.')) continue;

        final relatif = '${demande.replaceAll(RegExp(r'^/+|/+$'), '')}/$nom';

        if (entree is Directory) {
          dossiers.add({'nom': nom, 'chemin': relatif});
          continue;
        }
        if (entree is! File) continue;

        final nature = _nature(nom);
        if (nature == 'autre') continue;

        final info = entree.statSync();
        fichiers.add({
          'nom': nom,
          'chemin': relatif,
          'taille': info.size,
          'modifie': info.modified.millisecondsSinceEpoch,
          'nature': nature,
          'video': nature == 'video',
          'audio': nature == 'audio',
        });
      }
    } catch (_) {
      await _json(reponse, {'erreur': 'Dossier illisible.'}, 403);
      return;
    }

    int parNom(Map<String, Object> a, Map<String, Object> b) =>
        (a['nom']! as String)
            .toLowerCase()
            .compareTo((b['nom']! as String).toLowerCase());

    dossiers.sort(parNom);
    fichiers.sort(parNom);

    await _json(reponse, {
      'chemin': demande,
      'dossiers': dossiers,
      'fichiers': fichiers,
    });
  }

  // ----------------------------------------------------------------- fichiers

  static Future<void> _envoyerFichier(HttpRequest requete,
      HttpResponse reponse, String demande, bool enteteSeule) async {
    final cible = _cheminReel(demande);
    if (cible == null || !File(cible).existsSync()) {
      await _json(reponse, {'erreur': 'Fichier introuvable.'}, 404);
      return;
    }

    final fichier = File(cible);
    final taille = await fichier.length();

    var debut = 0;
    var fin = taille - 1;
    var partiel = false;

    // Requete partielle : c'est elle qui permet d'avancer dans un film sans
    // le telecharger en entier. Sans ce traitement, le lecteur redemarre le
    // telechargement a chaque deplacement.
    final entete = requete.headers.value(HttpHeaders.rangeHeader);
    if (entete != null) {
      final trouve = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(entete);
      if (trouve != null) {
        final g = trouve.group(1) ?? '';
        final d = trouve.group(2) ?? '';
        if (g.isNotEmpty) {
          debut = int.parse(g);
          if (d.isNotEmpty) fin = min(int.parse(d), taille - 1);
        } else if (d.isNotEmpty) {
          // Forme « bytes=-500 » : les derniers octets.
          debut = max(0, taille - int.parse(d));
        }
        partiel = true;
      }
    }

    if (debut >= taille) {
      reponse.statusCode = 416;
      reponse.headers.set('Content-Range', 'bytes */$taille');
      await reponse.close();
      return;
    }

    final longueur = fin - debut + 1;

    reponse.statusCode = partiel ? 206 : 200;
    reponse.headers.contentType = _mime(cible);
    reponse.headers.contentLength = longueur;
    reponse.headers.set('Accept-Ranges', 'bytes');
    if (partiel) {
      reponse.headers.set('Content-Range', 'bytes $debut-$fin/$taille');
    }

    if (enteteSeule) {
      await reponse.close();
      return;
    }

    try {
      await reponse.addStream(fichier.openRead(debut, fin + 1));
      await reponse.close();
    } catch (_) {
      // Le lecteur a coupe : c'est normal quand on change d'episode.
      try {
        await reponse.close();
      } catch (_) {}
    }
  }

  static ContentType _mime(String chemin) {
    switch (p.extension(chemin).toLowerCase()) {
      case '.mkv':
        return ContentType('video', 'x-matroska');
      case '.mp4':
      case '.m4v':
        return ContentType('video', 'mp4');
      case '.avi':
        return ContentType('video', 'x-msvideo');
      case '.webm':
        return ContentType('video', 'webm');
      case '.mp3':
        return ContentType('audio', 'mpeg');
      case '.flac':
        return ContentType('audio', 'flac');
      case '.m4a':
      case '.aac':
        return ContentType('audio', 'mp4');
      case '.ogg':
      case '.opus':
        return ContentType('audio', 'ogg');
      case '.wav':
        return ContentType('audio', 'wav');
      case '.srt':
      case '.vtt':
      case '.ass':
      case '.ssa':
        return ContentType('text', 'plain', charset: 'utf-8');
      case '.jpg':
      case '.jpeg':
        return ContentType('image', 'jpeg');
      case '.png':
        return ContentType('image', 'png');
      case '.webp':
        return ContentType('image', 'webp');
      default:
        return ContentType('application', 'octet-stream');
    }
  }

  static Future<void> _accueil(HttpResponse reponse) async {
    final lignes = _racines.entries
        .map((e) => '<li><b>${e.key}</b> — ${e.value}</li>')
        .join();
    final html = '<!doctype html><meta charset="utf-8">'
        '<title>Serveur Media Organizer</title>'
        '<body style="font-family:sans-serif;background:#0d0b0b;color:#eee;'
        'padding:24px"><h1>Serveur Media Organizer $version</h1>'
        '<p>Dossiers publiés :</p><ul>$lignes</ul>'
        '<p>Le serveur répond. Saisis cette adresse dans l\'application.</p>';
    final corps = utf8.encode(html);
    reponse.statusCode = 200;
    reponse.headers.contentType = ContentType('text', 'html', charset: 'utf-8');
    reponse.headers.contentLength = corps.length;
    reponse.add(corps);
    await reponse.close();
  }
}
