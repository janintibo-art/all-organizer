import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';
import 'cover_cache.dart';
import 'music_scanner.dart';
import 'tag_reader.dart';

class MusicSettings {
  String themeId = 'encre';
  bool scanOnStart = true;
  String sortMode = 'alpha'; // alpha | artist | album | recent | played
  bool shuffle = false;
  String repeatMode = 'off'; // off | one | all

  Map<String, dynamic> toJson() => {
        'themeId': themeId,
        'scanOnStart': scanOnStart,
        'sortMode': sortMode,
        'shuffle': shuffle,
        'repeatMode': repeatMode,
      };

  static MusicSettings fromJson(Map<String, dynamic> j) {
    final s = MusicSettings();
    s.themeId = j['themeId'] as String? ?? 'encre';
    s.scanOnStart = j['scanOnStart'] as bool? ?? true;
    s.sortMode = j['sortMode'] as String? ?? 'alpha';
    s.shuffle = j['shuffle'] as bool? ?? false;
    s.repeatMode = j['repeatMode'] as String? ?? 'off';
    return s;
  }
}

final MusicController music = MusicController();

class MusicController extends ChangeNotifier {
  List<Track> tracks = [];
  List<Playlist> playlists = [];
  List<String> folders = [];
  MusicSettings settings = MusicSettings();

  bool busy = false;
  String status = '';
  double progress = 0;
  int lastNewCount = 0;
  List<String> unreachableFolders = [];
  String? saveError;

  File? _file;

  Future<File> _storeFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _file = File(p.join(dir.path, 'musique.json'));
    return _file!;
  }

  Future<void> load() async {
    final f = await _storeFile();
    final backup = File('${f.path}.bak');
    for (final candidat in [f, backup]) {
      if (!candidat.existsSync()) continue;
      if (await _loadFrom(candidat)) break;
    }
    notifyListeners();
  }

  Future<bool> _loadFrom(File file) async {
    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      folders = (data['folders'] as List?)?.map((e) => e.toString()).toList() ?? [];
      settings = MusicSettings.fromJson(
          Map<String, dynamic>.from(data['settings'] as Map? ?? {}));
      tracks = (data['tracks'] as List?)
              ?.map((e) => Track.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [];
      playlists = (data['playlists'] as List?)
              ?.map((e) => Playlist.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [];
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Écriture atomique, avec archivage de la version précédente.
  Future<void> save() async {
    try {
      final f = await _storeFile();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(snapshot()), flush: true);
      if (f.existsSync()) {
        try {
          await f.copy('${f.path}.bak');
        } catch (_) {}
      }
      await tmp.rename(f.path);
      saveError = null;
    } catch (_) {
      saveError = 'La bibliothèque n\'a pas pu être enregistrée.';
      notifyListeners();
    }
  }

  Map<String, dynamic> snapshot() => {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'folders': folders,
        'settings': settings.toJson(),
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'playlists': playlists.map((p) => p.toJson()).toList(),
      };

  void refresh() => notifyListeners();

  void _report(String message, [double value = 0]) {
    status = message;
    progress = value;
    notifyListeners();
  }

  Future<void> updateSettings(void Function(MusicSettings s) change) async {
    change(settings);
    await save();
    notifyListeners();
  }

  // ---------------------------------------------------------------- dossiers

  Future<void> addFolder(String path) async {
    if (folders.contains(path)) return;
    folders.add(path);
    await save();
    notifyListeners();
  }

  Future<void> removeFolder(String path) async {
    folders.remove(path);
    tracks.removeWhere((t) => p.isWithin(path, t.path) || p.equals(path, t.path));
    await save();
    notifyListeners();
  }

  // -------------------------------------------------------------------- scan

  Future<void> startupScan() async {
    if (!settings.scanOnStart || folders.isEmpty || busy) return;
    await scan();
  }

  /// Compte rendu du dernier scan, consultable dans les réglages.
  String scanReport = '';

  /// Verse les morceaux trouvés sur un serveur dans la bibliothèque.
  /// Le scan du serveur est fait ailleurs : ici on ne fait que fusionner.
  Future<void> mergeRemote(String serverId, List<Track> trouves) async {
    tracks.removeWhere((t) => t.serverId == serverId);
    tracks.addAll(trouves);
    tracks.sort((a, b) => a.sortTitle.compareTo(b.sortTitle));
    await save();
    notifyListeners();
  }

  Future<void> dropServer(String serverId) async {
    tracks.removeWhere((t) => t.serverId == serverId);
    await save();
    notifyListeners();
  }

  Future<void> scan() async {
    if (busy || folders.isEmpty) return;
    busy = true;
    scanReport = '';
    _report('Analyse des dossiers');

    try {
      final joignables = <String>[];
      final injoignables = <String>[];
      for (final f in folders) {
        (Directory(f).existsSync() ? joignables : injoignables).add(f);
      }
      unreachableFolders = injoignables;

      // La lecture des étiquettes est coûteuse : elle part dans un isolate.
      final raw = await compute(MusicScanner.scanJson, joignables);
      final trouves = raw
          .map((m) => Track.fromJson(Map<String, dynamic>.from(m)))
          .toList();

      final existants = {for (final t in tracks) t.path: t};
      final fusion = <Track>[];
      var nouveaux = 0;

      for (final trouve in trouves) {
        final ancien = existants[trouve.path];
        if (ancien != null) {
          // On garde l'écoute et les favoris, on rafraîchit les étiquettes.
          trouve.playCount = ancien.playCount;
          trouve.lastPlayedAtMs = ancien.lastPlayedAtMs;
          trouve.favorite = ancien.favorite;
        } else {
          nouveaux++;
        }
        fusion.add(trouve);
      }

      // Un dossier débranché ne doit pas effacer ses morceaux.
      for (final t in tracks) {
        if (fusion.any((f) => f.path == t.path)) continue;
        if (injoignables.any((f) => p.isWithin(f, t.path))) fusion.add(t);
      }

      lastNewCount = nouveaux;
      tracks = fusion;

      // Les pochettes intégrées sont extraites ici, dans l'isolate
      // principal : les modules n'y répondent que de ce côté.
      _report('Extraction des pochettes');
      await _extraireePochettes();

      final rapport = StringBuffer(
          '${tracks.length} morceau(x) au total, dont $nouveaux nouveau(x).');
      if (injoignables.isNotEmpty) {
        rapport.write(' ${injoignables.length} dossier(s) injoignable(s) : ');
        rapport.write(injoignables.join(', '));
      }
      scanReport = rapport.toString();
      await save();
    } catch (e) {
      // Sans ce filet, une erreur pendant le scan remontait jusqu'à
      // l'interface et la bibliothèque restait vide sans explication.
      scanReport = 'Le scan a échoué : $e';
    } finally {
      busy = false;
      _report('');
    }
  }

  /// Une pochette par dossier d'album, pas une par morceau.
  Future<void> _extraireePochettes() async {
    final traites = <String>{};
    for (final t in tracks) {
      if (t.coverPath != null || !t.embeddedArt) continue;
      final dossier = p.dirname(t.path);
      if (traites.contains(dossier)) continue;
      traites.add(dossier);

      final bytes = await TagReader.readArtwork(t.path);
      if (bytes == null) continue;
      final chemin = await CoverCache.saveEmbedded(t.path, bytes);
      if (chemin == null) continue;

      // La même image sert à tout le dossier.
      for (final autre in tracks) {
        if (autre.coverPath == null && p.dirname(autre.path) == dossier) {
          autre.coverPath = chemin;
        }
      }
    }
  }

  // ------------------------------------------------------------- regroupement

  int get totalDurationMs =>
      tracks.fold<int>(0, (sum, t) => sum + (t.durationMs ?? 0));

  List<Track> view({String query = '', bool favoritesOnly = false}) {
    final q = query.trim().toLowerCase();
    var list = tracks.where((t) {
      if (favoritesOnly && !t.favorite) return false;
      if (q.isEmpty) return true;
      return t.title.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q) ||
          t.album.toLowerCase().contains(q) ||
          (t.genre ?? '').toLowerCase().contains(q);
    }).toList();

    switch (settings.sortMode) {
      case 'artist':
        list.sort((a, b) {
          final c = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          return c != 0 ? c : a.sortTitle.compareTo(b.sortTitle);
        });
        break;
      case 'album':
        list.sort((a, b) {
          final c = a.album.toLowerCase().compareTo(b.album.toLowerCase());
          if (c != 0) return c;
          return (a.trackNumber ?? 9999).compareTo(b.trackNumber ?? 9999);
        });
        break;
      case 'recent':
        list.sort((a, b) => (b.addedAtMs ?? 0).compareTo(a.addedAtMs ?? 0));
        break;
      case 'played':
        list.sort((a, b) => b.playCount.compareTo(a.playCount));
        break;
      default:
        list.sort((a, b) => a.sortTitle.compareTo(b.sortTitle));
    }
    return list;
  }

  List<Album> get albums {
    final map = <String, List<Track>>{};
    for (final t in tracks) {
      map.putIfAbsent(t.albumKey, () => []).add(t);
    }
    final list = map.entries
        .map((e) => Album(
              key: e.key,
              title: e.value.first.album,
              artist: e.value.first.albumArtist,
              tracks: e.value,
            ))
        .toList();
    list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return list;
  }

  /// Artistes et leurs albums.
  Map<String, List<Album>> get artists {
    final map = <String, List<Album>>{};
    for (final album in albums) {
      map.putIfAbsent(album.artist, () => []).add(album);
    }
    return Map.fromEntries(map.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase())));
  }

  List<Track> tracksOf(Playlist playlist) {
    final index = {for (final t in tracks) t.path: t};
    return playlist.paths
        .map((path) => index[path])
        .whereType<Track>()
        .toList();
  }

  /// Chemins d'une liste qui ne correspondent plus à aucun fichier.
  List<String> missingIn(Playlist playlist) {
    final connus = {for (final t in tracks) t.path};
    return playlist.paths.where((path) => !connus.contains(path)).toList();
  }

  // --------------------------------------------------------------- playlists

  Future<Playlist> createPlaylist(String name, {List<String>? paths}) async {
    final playlist = Playlist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? 'Sans nom' : name.trim(),
      paths: paths,
    );
    playlists.insert(0, playlist);
    await save();
    notifyListeners();
    return playlist;
  }

  Future<void> renamePlaylist(Playlist playlist, String name) async {
    playlist.name = name.trim().isEmpty ? playlist.name : name.trim();
    await save();
    notifyListeners();
  }

  Future<void> deletePlaylist(Playlist playlist) async {
    playlists.remove(playlist);
    await save();
    notifyListeners();
  }

  Future<void> addToPlaylist(Playlist playlist, List<String> paths) async {
    for (final path in paths) {
      if (!playlist.paths.contains(path)) playlist.paths.add(path);
    }
    await save();
    notifyListeners();
  }

  Future<void> removeFromPlaylist(Playlist playlist, String path) async {
    playlist.paths.remove(path);
    await save();
    notifyListeners();
  }

  Future<void> reorderPlaylist(Playlist playlist, int from, int to) async {
    if (from < 0 || from >= playlist.paths.length) return;
    final path = playlist.paths.removeAt(from);
    playlist.paths.insert(to.clamp(0, playlist.paths.length), path);
    await save();
    notifyListeners();
  }

  // --------------------------------------------------------------- écoute

  Future<void> toggleFavorite(Track track) async {
    track.favorite = !track.favorite;
    await save();
    notifyListeners();
  }

  Future<void> noteEcoute(String path) async {
    for (final t in tracks) {
      if (t.path != path) continue;
      t.playCount++;
      t.lastPlayedAtMs = DateTime.now().millisecondsSinceEpoch;
      break;
    }
    await save();
    notifyListeners();
  }

  /// Ecrit une sauvegarde : listes de lecture, favoris et ecoutes. Les
  /// fichiers audio ne sont pas copies.
  Future<String> exportLibrary(String folder) async {
    String deux(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final stamp = '${now.year}${deux(now.month)}${deux(now.day)}'
        '-${deux(now.hour)}${deux(now.minute)}';
    final file =
        File(p.join(folder, 'music-organizer-sauvegarde-$stamp.json'));
    await file.writeAsString(jsonEncode(snapshot()), flush: true);
    return file.path;
  }

  /// Restaure une sauvegarde en fusionnant : les listes de lecture et les
  /// écoutes reviennent, la liste des fichiers reste celle du disque.
  /// Renvoie le nombre de morceaux repris, ou -1 si le fichier est illisible.
  Future<int> importFrom(String path) async {
    try {
      final data =
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;

      final entrants = (data['tracks'] as List? ?? [])
          .map((e) => Track.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      final index = {for (final t in tracks) t.path: t};
      for (final entrant in entrants) {
        final courant = index[entrant.path];
        if (courant == null) {
          tracks.add(entrant);
          continue;
        }
        courant.favorite = courant.favorite || entrant.favorite;
        if (entrant.playCount > courant.playCount) {
          courant.playCount = entrant.playCount;
        }
        if ((entrant.lastPlayedAtMs ?? 0) > (courant.lastPlayedAtMs ?? 0)) {
          courant.lastPlayedAtMs = entrant.lastPlayedAtMs;
        }
      }

      final connues = {for (final p in playlists) p.id};
      for (final entree in data['playlists'] as List? ?? []) {
        final pl = Playlist.fromJson(Map<String, dynamic>.from(entree as Map));
        if (!connues.contains(pl.id)) playlists.add(pl);
      }

      for (final dossier in data['folders'] as List? ?? []) {
        final chemin = dossier.toString();
        if (!folders.contains(chemin)) folders.add(chemin);
      }

      await save();
      notifyListeners();
      return entrants.length;
    } catch (_) {
      return -1;
    }
  }

  Future<void> clearLibrary() async {
    tracks = [];
    playlists = [];
    await CoverCache.clear();
    await save();
    notifyListeners();
  }
}
