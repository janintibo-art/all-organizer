import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';
import '../models/server_profile.dart';
import '../models/track.dart';
import 'http_client.dart';
import 'library_controller.dart';
import 'server_api.dart';

/// Copies locales des fichiers d'un serveur, pour les emporter hors connexion.
///
/// Rien n'est ecrit dans les fiches : la correspondance « fichier distant ->
/// fichier local » vit dans son propre fichier, pour qu'une bibliotheque
/// restauree sur un autre appareil ne promette pas des copies inexistantes.
class Downloads extends ChangeNotifier {
  /// Cle « serveur|chemin distant » -> chemin du fichier sur l'appareil.
  final Map<String, String> _copies = {};

  /// Telechargements en cours : meme cle -> avancement entre 0 et 1.
  final Map<String, double> _encours = {};

  String? lastError;

  static String cle(String serverId, String cheminDistant) =>
      '$serverId|$cheminDistant';

  bool has(String serverId, String chemin) {
    final local = _copies[cle(serverId, chemin)];
    return local != null && File(local).existsSync();
  }

  String? pathOf(String serverId, String chemin) {
    final local = _copies[cle(serverId, chemin)];
    if (local == null) return null;
    return File(local).existsSync() ? local : null;
  }

  double? progressOf(String serverId, String chemin) =>
      _encours[cle(serverId, chemin)];

  bool get busy => _encours.isNotEmpty;
  int get count => _copies.length;

  // -------------------------------------------------------------- persistance

  Future<File> _fichier() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'telechargements.json'));
  }

  Future<void> load() async {
    try {
      final f = await _fichier();
      if (!f.existsSync()) return;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _copies
        ..clear()
        ..addAll((data['copies'] as Map? ?? {})
            .map((k, v) => MapEntry(k.toString(), v.toString())));
    } catch (_) {
      // Un fichier illisible ne doit pas empecher l'application d'ouvrir :
      // au pire les copies seront a refaire.
    }
  }

  Future<void> _save() async {
    try {
      final f = await _fichier();
      await f.writeAsString(jsonEncode({'copies': _copies}), flush: true);
    } catch (e) {
      lastError = '$e';
    }
  }

  // ------------------------------------------------------------ telechargement

  /// Dossier ou deposer les fichiers. Celui choisi dans les reglages, sinon
  /// un dossier de l'application.
  Future<String?> _destination(MediaItem item) async {
    var racine = library.settings.dossierTelechargements.trim();
    if (racine.isEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      racine = p.join(dir.path, 'Telechargements');
    }
    final dossier = Directory(p.join(racine, _assainir(item.title)));
    try {
      await dossier.create(recursive: true);
      return dossier.path;
    } catch (e) {
      lastError = 'Dossier inaccessible — $e';
      return null;
    }
  }

  /// Retire ce qu'un nom de fichier ne supporte pas sur Android et Windows.
  static String _assainir(String nom) {
    final propre = nom.replaceAll(RegExp(r'[<>:"/\\|?*]'), ' ').trim();
    return propre.isEmpty ? 'Sans titre' : propre;
  }

  ServerProfile? _serveur(String? id) {
    if (id == null) return null;
    for (final s in library.servers) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Telecharge un episode. Renvoie vrai si le fichier est arrive entier.
  Future<bool> episode(MediaItem item, Episode ep) async {
    final serveur = _serveur(item.serverId);
    if (serveur == null) {
      lastError = 'Ce titre ne vient pas d\'un serveur.';
      return false;
    }
    return _recuperer(
      serveur: serveur,
      cheminDistant: ep.path,
      nomFichier: ep.name,
      dossier: await _destination(item),
    );
  }

  /// Telecharge une saison entiere, episode par episode. S'arrete au premier
  /// echec : inutile d'insister si le serveur s'est endormi.
  Future<int> episodes(MediaItem item, List<Episode> liste) async {
    var faits = 0;
    for (final ep in liste) {
      if (has(item.serverId ?? '', ep.path)) continue;
      final ok = await episode(item, ep);
      if (!ok) break;
      faits++;
    }
    return faits;
  }

  /// Telecharge un morceau.
  Future<bool> track(Track t) async {
    final serveur = _serveur(t.serverId);
    if (serveur == null) {
      lastError = 'Ce morceau ne vient pas d\'un serveur.';
      return false;
    }

    var racine = library.settings.dossierTelechargements.trim();
    if (racine.isEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      racine = p.join(dir.path, 'Telechargements');
    }
    final dossier = Directory(
        p.join(racine, _assainir(t.albumArtist), _assainir(t.album)));
    try {
      await dossier.create(recursive: true);
    } catch (e) {
      lastError = 'Dossier inaccessible — $e';
      return false;
    }

    return _recuperer(
      serveur: serveur,
      cheminDistant: t.path,
      nomFichier: p.basename(t.path),
      dossier: dossier.path,
    );
  }

  /// Telecharge un album entier.
  Future<int> tracks(List<Track> liste) async {
    var faits = 0;
    for (final t in liste) {
      if (has(t.serverId ?? '', t.path)) continue;
      final ok = await track(t);
      if (!ok) break;
      faits++;
    }
    return faits;
  }

  Future<bool> _recuperer({
    required ServerProfile serveur,
    required String cheminDistant,
    required String nomFichier,
    required String? dossier,
  }) async {
    if (dossier == null) return false;

    final k = cle(serveur.id, cheminDistant);
    if (_encours.containsKey(k)) return false;

    lastError = null;
    _encours[k] = 0;
    notifyListeners();

    // On ecrit d'abord a cote : un telechargement coupe ne doit pas laisser
    // un fichier tronque qui passerait pour complet.
    final cible = File(p.join(dossier, _assainir(nomFichier)));
    final partiel = File('${cible.path}.part');
    IOSink? sortie;

    try {
      final requete =
          http.Request('GET', Uri.parse(ServerApi.fileUrl(serveur, cheminDistant)));
      requete.headers.addAll(AppHttp.headers(accept: '*/*'));
      if (serveur.token.trim().isNotEmpty) {
        requete.headers['X-Jeton'] = serveur.token.trim();
      }

      final reponse = await http.Client().send(requete);
      if (reponse.statusCode != 200) {
        lastError = 'HTTP ${reponse.statusCode}';
        _encours.remove(k);
        notifyListeners();
        return false;
      }

      final total = reponse.contentLength ?? 0;
      var recus = 0;
      sortie = partiel.openWrite();

      await for (final morceau in reponse.stream) {
        sortie.add(morceau);
        recus += morceau.length;
        if (total > 0) {
          final avance = recus / total;
          // On ne rafraichit qu'au pourcentage : sinon l'interface passe son
          // temps a se redessiner au lieu d'ecrire.
          if ((avance * 100).floor() != ((_encours[k] ?? 0) * 100).floor()) {
            _encours[k] = avance;
            notifyListeners();
          }
        }
      }

      await sortie.flush();
      await sortie.close();
      sortie = null;

      if (cible.existsSync()) await cible.delete();
      await partiel.rename(cible.path);

      _copies[k] = cible.path;
      _encours.remove(k);
      await _save();
      notifyListeners();
      return true;
    } catch (e) {
      lastError = '$e';
      try {
        await sortie?.close();
      } catch (_) {}
      if (partiel.existsSync()) {
        try {
          await partiel.delete();
        } catch (_) {}
      }
      _encours.remove(k);
      notifyListeners();
      return false;
    }
  }

  // ---------------------------------------------------------------- effacement

  Future<void> remove(String serverId, String cheminDistant) async {
    final k = cle(serverId, cheminDistant);
    final local = _copies.remove(k);
    if (local != null && File(local).existsSync()) {
      try {
        await File(local).delete();
      } catch (e) {
        lastError = '$e';
      }
    }
    await _save();
    notifyListeners();
  }

  /// Supprime toutes les copies et renvoie leur nombre.
  Future<int> clear() async {
    final n = _copies.length;
    for (final local in _copies.values) {
      try {
        final f = File(local);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
    _copies.clear();
    await _save();
    notifyListeners();
    return n;
  }

  /// Place occupee par les copies, en octets.
  Future<int> sizeInBytes() async {
    var total = 0;
    for (final local in _copies.values) {
      try {
        final f = File(local);
        if (f.existsSync()) total += await f.length();
      } catch (_) {}
    }
    return total;
  }
}

final Downloads downloads = Downloads();

/// Traduit un fichier de la bibliotheque en source lisible par le lecteur.
///
/// Un fichier local se lit sur le disque ; un fichier distant se lit par le
/// reseau, sauf si on en a gardé une copie, auquel cas la copie gagne.
class MediaSource {
  static String forEpisode(MediaItem item, Episode ep) {
    final serverId = item.serverId;
    if (serverId == null) return Uri.file(ep.path).toString();

    final local = downloads.pathOf(serverId, ep.path);
    if (local != null) return Uri.file(local).toString();

    for (final s in library.servers) {
      if (s.id == serverId) return ServerApi.fileUrl(s, ep.path);
    }
    return Uri.file(ep.path).toString();
  }

  /// Chemin ou URL d'un morceau, pour le lecteur audio.
  static String forTrack(Track t) {
    final serverId = t.serverId;
    if (serverId == null) return t.path;

    final local = downloads.pathOf(serverId, t.path);
    if (local != null) return local;

    for (final s in library.servers) {
      if (s.id == serverId) return ServerApi.fileUrl(s, t.path);
    }
    return t.path;
  }

  static bool isRemote(Track t) =>
      t.serverId != null && downloads.pathOf(t.serverId!, t.path) == null;
}
