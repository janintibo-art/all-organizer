import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';
import '../models/media_meta.dart';
import '../main.dart';
import '../models/labels.dart';
import '../models/library_folder.dart';
import '../models/server_profile.dart';
import 'anime_index.dart';
import 'metadata_service.dart';
import 'music_controller.dart';
import 'remote_scanner.dart';
import 'server_api.dart';
import 'wake.dart';
import 'tmdb_api.dart';
import 'ai_service.dart';
import 'poster_cache.dart';
import 'scanner.dart';
import 'seed_database.dart';
import 'translate_api.dart';

/// Instance unique utilisee par toute l'application.
final LibraryController library = LibraryController();

class AppSettings {
  String translationProvider = 'mymemory'; // none | mymemory | libretranslate | deepl
  String targetLang = 'fr';
  String apiKey = '';
  String libreEndpoint = 'https://libretranslate.com';
  String email = '';
  bool autoTranslate = true;
  bool autoFetch = true;
  bool scanOnStart = true;
  bool offlinePosters = true;

  // Lecteur
  bool autoNext = true;
  int skipIntroSeconds = 85;
  int seekStepSeconds = 10;
  double subtitleSize = 32;
  String videoFit = 'contain'; // contain | cover | fill
  bool hardwareDecoding = true;
  String preferredAudio = '';
  String preferredSubtitle = 'fr';
  bool autoFetchSubtitles = true;
  String subtitleKey = '';
  String subtitleUser = '';
  String subtitlePassword = '';

  // Assistant IA
  bool aiEnabled = true;
  String aiProvider = 'groq'; // groq | openrouter | custom
  String aiKey = '';
  String aiModel = 'llama-3.3-70b-versatile';
  String aiEndpoint = '';
  bool aiWebSearch = true;
  // auto | tmdb | tvmaze — films, séries et jeunesse
  String metaSource = 'auto';
  // auto | anilist | jikan | kitsu | animethemes | tmdb — animes japonais
  String animeSource = 'auto';
  bool useIndex = true;
  String indexRepo = AnimeIndex.defaultRepo;
  String tmdbKey = '';
  String themeId = 'encre';
  bool autoWake = true;
  bool scanServersOnStart = false;
  String viewMode = 'grid'; // grid | list | genre
  String sortMode = 'alpha'; // alpha | score | year | episodes | recent

  Map<String, dynamic> toJson() => {
        'translationProvider': translationProvider,
        'targetLang': targetLang,
        'apiKey': apiKey,
        'libreEndpoint': libreEndpoint,
        'email': email,
        'autoTranslate': autoTranslate,
        'autoFetch': autoFetch,
        'scanOnStart': scanOnStart,
        'offlinePosters': offlinePosters,
        'autoNext': autoNext,
        'skipIntroSeconds': skipIntroSeconds,
        'seekStepSeconds': seekStepSeconds,
        'subtitleSize': subtitleSize,
        'videoFit': videoFit,
        'hardwareDecoding': hardwareDecoding,
        'preferredAudio': preferredAudio,
        'preferredSubtitle': preferredSubtitle,
        'autoFetchSubtitles': autoFetchSubtitles,
        'subtitleKey': subtitleKey,
        'subtitleUser': subtitleUser,
        'subtitlePassword': subtitlePassword,
        'aiEnabled': aiEnabled,
        'aiProvider': aiProvider,
        'aiKey': aiKey,
        'aiModel': aiModel,
        'aiEndpoint': aiEndpoint,
        'aiWebSearch': aiWebSearch,
        'metaSource': metaSource,
        'animeSource': animeSource,
        'useIndex': useIndex,
        'indexRepo': indexRepo,
        'tmdbKey': tmdbKey,
        'themeId': themeId,
        'autoWake': autoWake,
        'scanServersOnStart': scanServersOnStart,
        'viewMode': viewMode,
        'sortMode': sortMode,
      };

  static AppSettings fromJson(Map<String, dynamic> j) {
    final s = AppSettings();
    s.translationProvider = j['translationProvider'] as String? ?? 'mymemory';
    s.targetLang = j['targetLang'] as String? ?? 'fr';
    s.apiKey = j['apiKey'] as String? ?? '';
    s.libreEndpoint = j['libreEndpoint'] as String? ?? 'https://libretranslate.com';
    s.email = j['email'] as String? ?? '';
    s.autoTranslate = j['autoTranslate'] as bool? ?? true;
    s.autoFetch = j['autoFetch'] as bool? ?? true;
    s.scanOnStart = j['scanOnStart'] as bool? ?? true;
    s.offlinePosters = j['offlinePosters'] as bool? ?? true;
    s.autoNext = j['autoNext'] as bool? ?? true;
    s.skipIntroSeconds = j['skipIntroSeconds'] as int? ?? 85;
    s.seekStepSeconds = j['seekStepSeconds'] as int? ?? 10;
    s.subtitleSize = (j['subtitleSize'] as num?)?.toDouble() ?? 32;
    s.videoFit = j['videoFit'] as String? ?? 'contain';
    s.hardwareDecoding = j['hardwareDecoding'] as bool? ?? true;
    s.preferredAudio = j['preferredAudio'] as String? ?? '';
    s.preferredSubtitle = j['preferredSubtitle'] as String? ?? 'fr';
    s.autoFetchSubtitles = j['autoFetchSubtitles'] as bool? ?? true;
    s.subtitleKey = j['subtitleKey'] as String? ?? '';
    s.subtitleUser = j['subtitleUser'] as String? ?? '';
    s.subtitlePassword = j['subtitlePassword'] as String? ?? '';
    s.aiEnabled = j['aiEnabled'] as bool? ?? true;
    s.aiProvider = j['aiProvider'] as String? ?? 'groq';
    s.aiKey = j['aiKey'] as String? ?? '';
    s.aiModel = j['aiModel'] as String? ?? 'llama-3.3-70b-versatile';
    s.aiEndpoint = j['aiEndpoint'] as String? ?? '';
    s.aiWebSearch = j['aiWebSearch'] as bool? ?? true;
    s.metaSource = j['metaSource'] as String? ?? 'auto';
    s.animeSource = j['animeSource'] as String? ?? 'auto';
    s.useIndex = j['useIndex'] as bool? ?? true;
    s.indexRepo = j['indexRepo'] as String? ?? AnimeIndex.defaultRepo;
    s.tmdbKey = j['tmdbKey'] as String? ?? '';
    s.themeId = j['themeId'] as String? ?? 'encre';
    s.autoWake = j['autoWake'] as bool? ?? true;
    s.scanServersOnStart = j['scanServersOnStart'] as bool? ?? false;
    s.viewMode = j['viewMode'] as String? ?? 'grid';
    s.sortMode = j['sortMode'] as String? ?? 'alpha';
    return s;
  }
}

class LibraryController extends ChangeNotifier {
  List<MediaItem> items = [];
  List<LibraryFolder> folders = [];
  List<ServerProfile> servers = [];

  /// Series reperees dans l'onglet Decouvrir et mises de cote.
  List<MediaMeta> wishlist = [];

  /// Ta propre base : chaque correction manuelle ou par l'IA est retenue.
  /// Un dossier deja identifie ne sera plus jamais recherche.
  Map<String, String> knownTitles = {};

  String _key(String folderTitle) =>
      MetadataService.stripAccents(folderTitle).replaceAll(
          RegExp(r'[^a-z0-9]'), '');

  void remember(String folderTitle, String resolvedQuery) {
    final key = _key(folderTitle);
    if (key.length < 3 || resolvedQuery.trim().isEmpty) return;
    knownTitles[key] = resolvedQuery.trim();
  }

  String? recall(String folderTitle) => knownTitles[_key(folderTitle)];
  AppSettings settings = AppSettings();

  bool busy = false;
  String status = '';
  double progress = 0;

  /// Nombre de series decouvertes lors du dernier scan.
  int lastNewCount = 0;

  /// Dossiers injoignables au dernier scan (disque debranche, permission
  /// refusee). Leurs fiches sont conservees plutot que supprimees.
  List<String> unreachableFolders = [];

  File? _file;

  Future<File> _storeFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _file = File(p.join(dir.path, 'library.json'));
    return _file!;
  }

  /// Message affiche si la derniere sauvegarde a echoue.
  String? saveError;

  Future<void> load() async {
    final f = await _storeFile();
    final backup = File('${f.path}.bak');
    for (final candidate in [f, backup]) {
      if (!candidate.existsSync()) continue;
      if (await _loadFrom(candidate)) {
        notifyListeners();
        return;
      }
    }
    notifyListeners();
  }

  Future<bool> _loadFrom(File file) async {
    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      // Les anciennes sauvegardes ne stockaient qu'un chemin : on les
      // reprend en les classant en séries, à charge de corriger.
      folders = (data['folders'] as List? ?? []).map((e) {
        if (e is String) {
          return LibraryFolder(path: e, kind: MediaKind.series);
        }
        return LibraryFolder.fromJson(Map<String, dynamic>.from(e as Map));
      }).toList();
      servers = (data['servers'] as List? ?? [])
          .map((e) =>
              ServerProfile.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      settings = AppSettings.fromJson(
          Map<String, dynamic>.from(data['settings'] as Map? ?? {}));
      items = (data['items'] as List?)
              ?.map((e) => MediaItem.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [];
      knownTitles = ((data['knownTitles'] as Map?) ?? const {})
          .map((k, v) => MapEntry(k.toString(), v.toString()));
      wishlist = (data['wishlist'] as List?)
              ?.map((e) =>
                  MediaMeta.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [];
      // Le thème doit être en place avant le premier rendu.
      Palette.apply(settings.themeId);
      return true;
    } catch (_) {
      // Fichier illisible : on tentera la copie de secours.
      return false;
    }
  }

  /// Ecriture atomique : on ecrit un fichier temporaire, on archive la version
  /// precedente, puis on renomme. Une coupure ne peut pas laisser un JSON
  /// tronque a la place de la bibliotheque.
  Future<void> save() async {
    try {
      final f = await _storeFile();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'folders': folders.map((f) => f.toJson()).toList(),
        'servers': servers.map((s) => s.toJson()).toList(),
        'settings': settings.toJson(),
        'items': items.map((a) => a.toJson()).toList(),
        'wishlist': wishlist.map((w) => w.toJson()).toList(),
        'knownTitles': knownTitles,
      }), flush: true);

      if (f.existsSync()) {
        try {
          await f.copy('${f.path}.bak');
        } catch (_) {}
      }
      await tmp.rename(f.path);
      saveError = null;
    } catch (e) {
      saveError = 'La bibliothèque n\'a pas pu être enregistrée.';
      notifyListeners();
    }
  }

  /// Rafraichit les ecrans qui ecoutent le controleur.
  void refresh() => notifyListeners();

  void _report(String message, [double value = 0]) {
    status = message;
    progress = value;
    notifyListeners();
  }

  Future<void> addFolder(String path,
      {required MediaKind kind, bool kids = false}) async {
    if (folders.any((f) => f.path == path)) return;
    folders.add(LibraryFolder(path: path, kind: kind, kids: kids));
    await save();
    notifyListeners();
  }

  /// Dossiers d'une section donnée.
  List<LibraryFolder> foldersOf({MediaKind? kind, bool kidsOnly = false}) {
    return folders.where((f) {
      if (kidsOnly) return f.kids;
      if (f.kids) return false;
      return kind == null || f.kind == kind;
    }).toList();
  }

  Future<void> removeFolder(String path, {bool dropEntries = true}) async {
    folders.removeWhere((f) => f.path == path);
    if (dropEntries) {
      items.removeWhere((a) => p.isWithin(path, a.id) || p.equals(path, a.id));
    }
    await save();
    notifyListeners();
  }

  /// Dossier surveillé auquel appartient un chemin.
  LibraryFolder? _folderOf(String chemin) {
    LibraryFolder? meilleur;
    for (final f in folders) {
      if (!p.equals(f.path, chemin) && !p.isWithin(f.path, chemin)) continue;
      // Le dossier le plus profond gagne : deux dossiers imbriqués peuvent
      // être déclarés dans des sections différentes.
      if (meilleur == null || f.path.length > meilleur.path.length) {
        meilleur = f;
      }
    }
    return meilleur;
  }

  /// Scanne les dossiers, fusionne avec l'existant, puis complete les fiches.
  Future<void> scan({bool fetchMetadata = true}) async {
    if (busy || folders.isEmpty) return;
    busy = true;
    _report('Analyse des dossiers');

    try {
      // Un dossier injoignable ne doit pas effacer les fiches deja connues.
      final reachable = <String>[];
      final unreachable = <String>[];
      for (final f in folders) {
        (Directory(f.path).existsSync() ? reachable : unreachable).add(f.path);
      }
      unreachableFolders = unreachable;

      // Le parcours des dossiers part dans un isolate : sur une carte SD
      // bien remplie, l'interface reste fluide.
      _report('Analyse des dossiers');
      final raw = await compute(Scanner.scanFoldersJson, reachable);
      final found = raw
          .map((m) => MediaItem.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      final existing = {for (final a in items) a.id: a};
      final merged = <MediaItem>[];
      var discovered = 0;

      for (final item in found) {
        // La nature vient du dossier surveillé, pas d'une déduction sur les
        // fichiers : un dossier ajouté depuis Animes ne donne que des animes.
        final dossier = _folderOf(item.id);
        if (dossier != null) {
          item.kind = dossier.kind;
          if (dossier.kids && !item.kidsManual) item.kids = true;
        }

        final old = existing[item.id];
        if (old != null) {
          old.episodes = item.episodes;
          old.folderTitle = item.folderTitle;
          old.kind = item.kind;
          if (!old.kidsManual) old.kids = item.kids;
          merged.add(old);
        } else {
          merged.add(item);
          discovered++;
        }
      }

      // Series appartenant a un dossier momentanement inaccessible.
      for (final a in items) {
        if (merged.any((m) => m.id == a.id)) continue;
        final orphan = unreachable.any(
            (f) => p.equals(f, a.id) || p.isWithin(f, a.id));
        if (orphan) merged.add(a);
      }

      lastNewCount = discovered;
      items = merged;
      await save();
      notifyListeners();

      if (fetchMetadata && settings.autoFetch) {
        final todo = items
            .where((a) => !a.metaFetched && a.metaFailCount < 3)
            .toList();
        for (var i = 0; i < todo.length; i++) {
          _report('Fiche ${i + 1}/${todo.length} : ${todo[i].folderTitle}',
              (i + 1) / todo.length);
          await fetchOne(todo[i], persist: false);
        }
        await save();
      }
    } finally {
      busy = false;
      _report('');
    }
  }

  /// Scan lance a l'ouverture de l'application : detecte les nouveaux
  /// dossiers sans retoucher aux fiches deja enregistrees.
  Future<void> startupScan() async {
    if (!settings.scanOnStart || folders.isEmpty || busy) return;
    await scan();
  }

  /// Recupere image, synopsis et genres pour une serie.
  Future<void> fetchOne(MediaItem item, {String? overrideQuery, bool persist = true}) async {
    final query = overrideQuery ?? item.folderTitle;
    final count = item.episodes.where((e) => !e.bonus).length;

    // 1. Ta memoire : ce dossier a deja ete identifie une fois.
    var resolved = overrideQuery ?? recall(item.folderTitle);

    // 2. La base locale : elle traduit un titre francais en romaji,
    //    ce que les bases en ligne savent chercher. Reservee aux animes :
    //    elle ne connait que des series japonaises.
    SeedEntry? seed;
    IndexEntry? indexed;
    if (resolved == null && item.kind == MediaKind.anime) {
      seed = SeedDatabase.match(item.folderTitle, episodeCount: count);
      if (seed != null) {
        resolved = seed.searchQuery;
      } else if (settings.useIndex && AnimeIndex.isLoaded) {
        // 40 000 series connues hors connexion, affiche comprise.
        indexed = AnimeIndex.match(item.folderTitle, episodeCount: count);
        if (indexed != null) resolved = indexed.searchQuery;
      }
    }

    var meta = await MetadataService.smartSearch(
      resolved ?? query,
      source: settings.metaSource,
      episodeCount: count,
      tmdbKey: settings.tmdbKey,
      moviesOnly: item.kind == MediaKind.movie,
      seriesOnly: item.kind == MediaKind.series,
      anime: item.kind == MediaKind.anime,
      animeSource: settings.animeSource,
    );

    // 3. Rien en ligne mais la base locale connait la serie : on l'applique
    //    telle quelle, quitte a completer l'affiche plus tard.
    if (meta == null && seed != null) {
      applyMeta(item, seed.toMeta());
      item.frenchTitle = seed.french;
      remember(item.folderTitle, seed.searchQuery);
      if (persist) await save();
      notifyListeners();
      return;
    }

    // L'index porte deja l'affiche : la fiche est utilisable telle quelle.
    if (meta == null && indexed != null) {
      applyMeta(item, indexed.toMeta());
      remember(item.folderTitle, indexed.searchQuery);
      if (settings.offlinePosters) {
        item.posterPath = await PosterCache.ensure(item.id, item.imageUrl);
      }
      if (persist) await save();
      notifyListeners();
      return;
    }

    // Titre francais : on le traduit en anglais et on retente.
    if (meta == null &&
        settings.translationProvider != 'none' &&
        MetadataService.looksFrench(query)) {
      final english = await TranslateApi.translate(
        query,
        provider: settings.translationProvider,
        targetLang: 'en',
        sourceLang: 'fr',
        apiKey: settings.apiKey,
        endpoint: settings.libreEndpoint,
        email: settings.email,
      );
      if (english != null && english.trim().isNotEmpty) {
        meta = await MetadataService.smartSearch(english,
            source: settings.metaSource,
            episodeCount: item.episodes.where((e) => !e.bonus).length,
            anime: item.kind == MediaKind.anime,
            animeSource: settings.animeSource);
      }
    }

    // Dernier recours : l'IA identifie la serie et donne son vrai titre.
    AiTitles? ai;
    if (meta == null && settings.aiEnabled && settings.aiKey.isNotEmpty) {
      ai = await AiService.identify(
        folderTitle: query,
        provider: settings.aiProvider,
        apiKey: settings.aiKey,
        model: settings.aiModel,
        custom: settings.aiEndpoint,
      );
      if (ai != null && ai.usable) {
        meta = await MetadataService.smartSearch(
          ai.searchQuery,
          source: settings.metaSource,
          episodeCount: count,
          tmdbKey: settings.tmdbKey,
          anime: item.kind == MediaKind.anime,
          animeSource: settings.animeSource,
        );
        if (meta == null && ai.english.isNotEmpty) {
          meta = await MetadataService.smartSearch(
            ai.english,
            source: settings.metaSource,
            episodeCount: count,
            tmdbKey: settings.tmdbKey,
            anime: item.kind == MediaKind.anime,
            animeSource: settings.animeSource,
          );
        }
      }
    }
    if (meta == null) {
      // Une panne reseau ne doit pas condamner la fiche : on retentera
      // aux prochains demarrages, jusqu'a trois fois.
      item.metaFailCount++;
      item.metaFailed = item.metaFailCount >= 3;
    } else {
      // Les détails apportent la classification d'âge, absente des
      // résultats de recherche : c'est elle qui décide de l'onglet Jeunesse.
      if (meta.source == 'tmdb' && meta.sourceId != null) {
        final complet = await TmdbApi.details(
          meta.sourceId!,
          item.kind == MediaKind.series,
          settings.tmdbKey,
        );
        if (complet != null) meta = complet;
      }
      applyMeta(item, meta);
      remember(item.folderTitle, meta.titleRomaji ?? meta.title);
      if (ai != null && ai.usable) {
        if (ai.french.isNotEmpty) item.frenchTitle = ai.french;
        if (ai.japanese.isNotEmpty) item.nativeTitle ??= ai.japanese;
        if (ai.romaji.isNotEmpty) item.romajiTitle ??= ai.romaji;
      }
      if (settings.offlinePosters) {
        item.posterPath = await PosterCache.ensure(item.id, item.imageUrl);
      }
      if (settings.autoTranslate && settings.translationProvider != 'none') {
        await translateOne(item, persist: false);
      }
    }
    if (persist) await save();
    notifyListeners();
  }

  void applyMeta(MediaItem item, MediaMeta meta) {
    item.malId = meta.sourceId;
    item.metaSource = meta.source;
    item.apiTitle = meta.title;
    item.nativeTitle = meta.titleNative;
    item.romajiTitle = meta.titleRomaji;
    item.imageUrl = meta.imageUrl;
    item.posterPath = null;
    item.synopsisEn = meta.synopsis;
    item.synopsisTranslated = null;
    item.genres = Labels.genres(meta.genres);
    item.score = meta.score;
    item.popularity = meta.popularity;
    item.studios = meta.studios;
    item.year = meta.year;
    item.type = Labels.format(meta.type);
    item.status = Labels.status(meta.status);
    item.episodesCount = meta.episodes;
    item.metaFetched = true;
    item.metaFailed = false;
  }

  Future<bool> translateOne(MediaItem item, {bool persist = true}) async {
    if (item.synopsisEn == null || item.synopsisEn!.trim().isEmpty) return false;
    final result = await TranslateApi.translate(
      item.synopsisEn!,
      provider: settings.translationProvider,
      targetLang: settings.targetLang,
      apiKey: settings.apiKey,
      endpoint: settings.libreEndpoint,
      email: settings.email,
    );
    if (result != null && result.trim().isNotEmpty) {
      item.synopsisTranslated = result;
      if (persist) await save();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Traduit toutes les fiches qui ne le sont pas encore.
  Future<void> translateAll() async {
    if (busy) return;
    busy = true;
    final todo = items
        .where((a) =>
            a.synopsisEn != null &&
            a.synopsisEn!.isNotEmpty &&
            (a.synopsisTranslated == null || a.synopsisTranslated!.isEmpty))
        .toList();
    try {
      for (var i = 0; i < todo.length; i++) {
        _report('Traduction ${i + 1}/${todo.length}', (i + 1) / todo.length);
        await translateOne(todo[i], persist: false);
      }
      await save();
    } finally {
      busy = false;
      _report('');
    }
  }

  /// Relance la recherche pour toutes les fiches sans metadonnees.
  Future<void> retryFailed() async {
    if (busy) return;
    busy = true;
    final todo = items.where((a) => !a.metaFetched).toList();
    try {
      for (var i = 0; i < todo.length; i++) {
        todo[i].metaFailed = false;
        todo[i].metaFailCount = 0;
        _report('Fiche ${i + 1}/${todo.length}', (i + 1) / todo.length);
        await fetchOne(todo[i], persist: false);
      }
      await save();
    } finally {
      busy = false;
      _report('');
    }
  }

  /// Marque un episode comme vu ou non vu.
  Future<void> setWatched(MediaItem item, Episode episode, bool watched) async {
    if (watched) {
      if (!item.watchedPaths.contains(episode.path)) {
        item.watchedPaths.add(episode.path);
      }
    } else {
      item.watchedPaths.remove(episode.path);
    }
    await save();
    notifyListeners();
  }

  Future<void> markAllWatched(MediaItem item, bool watched) async {
    item.watchedPaths = watched ? item.episodes.map((e) => e.path).toList() : [];
    await save();
    notifyListeners();
  }

  /// Enregistre la position de lecture. Au-dela de 92 % l'episode est
  /// considere comme vu : le generique de fin ne merite pas d'etre subi.
  Future<void> savePlayback(
    MediaItem item,
    Episode episode,
    Duration position,
    Duration duration,
  ) async {
    item.lastEpisodePath = episode.path;
    item.lastPositionMs = position.inMilliseconds;
    item.lastPlayedAtMs = DateTime.now().millisecondsSinceEpoch;

    if (duration.inSeconds > 0 &&
        position.inMilliseconds / duration.inMilliseconds > 0.92 &&
        !item.watchedPaths.contains(episode.path)) {
      item.watchedPaths.add(episode.path);
      item.lastPositionMs = 0;
    }
    await save();
    notifyListeners();
  }

  /// Series commencees mais pas terminees, la plus recente en tete.
  List<MediaItem> get continueWatching {
    final list = items
        .where((a) => a.started && !a.finished && a.episodes.isNotEmpty)
        .toList()
      ..sort((a, b) =>
          (b.lastPlayedAtMs ?? 0).compareTo(a.lastPlayedAtMs ?? 0));
    return list.take(12).toList();
  }

  List<MediaItem> get favorites =>
      items.where((a) => a.favorite).toList()
        ..sort((a, b) => a.sortKey.compareTo(b.sortKey));

  int get totalEpisodes =>
      items.fold<int>(0, (sum, a) => sum + a.episodes.length);

  Future<void> toggleFavorite(MediaItem item) async {
    item.favorite = !item.favorite;
    await save();
    notifyListeners();
  }

  Map<String, dynamic> _snapshot() => {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'folders': folders.map((f) => f.toJson()).toList(),
        'settings': settings.toJson(),
        'items': items.map((a) => a.toJson()).toList(),
        'wishlist': wishlist.map((w) => w.toJson()).toList(),
        'knownTitles': knownTitles,
      };

  String _two(int v) => v.toString().padLeft(2, '0');

  /// Écrit une sauvegarde lisible dans le dossier choisi.
  Future<String> exportLibrary(String folder) async {
    final now = DateTime.now();
    final stamp =
        '${now.year}${_two(now.month)}${_two(now.day)}-${_two(now.hour)}${_two(now.minute)}';
    final file =
        File(p.join(folder, 'item-organizer-sauvegarde-$stamp.json'));
    await file.writeAsString(jsonEncode(_snapshot()), flush: true);
    return file.path;
  }

  /// Restaure une sauvegarde. En mode fusion, les fiches et la progression
  /// sont reprises mais la liste des fichiers reste celle du disque.
  Future<int> importLibrary(String path, {bool merge = true}) async {
    final data =
        jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    final incoming = (data['items'] as List? ?? [])
        .map((e) => MediaItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    if (!merge) {
      items = incoming;
      folders = (data['folders'] as List? ?? [])
          .map((e) => e is String
              ? LibraryFolder(path: e, kind: MediaKind.series)
              : LibraryFolder.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } else {
      final byId = {for (final a in items) a.id: a};
      for (final b in incoming) {
        final current = byId[b.id];
        if (current == null) {
          items.add(b);
          continue;
        }
        current.apiTitle = b.apiTitle ?? current.apiTitle;
        current.nativeTitle = b.nativeTitle ?? current.nativeTitle;
        current.malId = b.malId ?? current.malId;
        current.imageUrl = b.imageUrl ?? current.imageUrl;
        current.posterPath = b.posterPath ?? current.posterPath;
        current.synopsisEn = b.synopsisEn ?? current.synopsisEn;
        current.synopsisTranslated =
            b.synopsisTranslated ?? current.synopsisTranslated;
        if (b.genres.isNotEmpty) current.genres = b.genres;
        current.score = b.score ?? current.score;
        current.popularity = b.popularity ?? current.popularity;
        current.studios = b.studios ?? current.studios;
        current.year = b.year ?? current.year;
        current.type = b.type ?? current.type;
        current.status = b.status ?? current.status;
        current.episodesCount = b.episodesCount ?? current.episodesCount;
        current.metaFetched = current.metaFetched || b.metaFetched;
        current.favorite = current.favorite || b.favorite;
        for (final w in b.watchedPaths) {
          if (!current.watchedPaths.contains(w)) current.watchedPaths.add(w);
        }
        if ((b.lastPlayedAtMs ?? 0) > (current.lastPlayedAtMs ?? 0)) {
          current.lastPlayedAtMs = b.lastPlayedAtMs;
          current.lastEpisodePath = b.lastEpisodePath;
          current.lastPositionMs = b.lastPositionMs;
        }
      }
    }

    await save();
    notifyListeners();
    return incoming.length;
  }

  /// Demande à l'IA d'identifier une série, puis relance la recherche
  /// de fiche avec le titre qu'elle donne. Renvoie un message à afficher.
  Future<String> identifyWithAi(MediaItem item) async {
    if (!settings.aiEnabled || settings.aiKey.isEmpty) {
      return 'Renseigne une clé IA dans les réglages.';
    }
    final ai = await AiService.identify(
      folderTitle: item.folderTitle,
      provider: settings.aiProvider,
      apiKey: settings.aiKey,
      model: settings.aiModel,
      custom: settings.aiEndpoint,
    );
    if (ai == null) {
      return AiService.lastError ?? 'L\'IA n\'a pas répondu.';
    }
    if (!ai.usable) return 'L\'IA n\'a pas reconnu cette série.';

    if (ai.french.isNotEmpty) item.frenchTitle = ai.french;
    if (ai.japanese.isNotEmpty) item.nativeTitle = ai.japanese;
    if (ai.romaji.isNotEmpty) item.romajiTitle = ai.romaji;

    final meta = await MetadataService.smartSearch(ai.searchQuery,
        source: settings.metaSource, tmdbKey: settings.tmdbKey);
    if (meta != null) {
      final french = item.frenchTitle;
      final japanese = item.nativeTitle;
      applyMeta(item, meta);
      item.frenchTitle = french;
      item.nativeTitle ??= japanese;
      if (settings.offlinePosters) {
        item.posterPath = await PosterCache.ensure(item.id, item.imageUrl);
      }
      if (settings.autoTranslate && settings.translationProvider != 'none') {
        await translateOne(item, persist: false);
      }
      remember(item.folderTitle, ai.searchQuery);
      await save();
      notifyListeners();
      return 'Identifiée : ${meta.title}';
    }

    await save();
    notifyListeners();
    return 'Titres mis à jour, mais aucune fiche trouvée pour ${ai.searchQuery}.';
  }

  /// Télécharge les affiches manquantes pour un usage hors connexion.
  Future<int> cachePosters() async {
    if (busy) return 0;
    busy = true;
    var done = 0;
    final todo = items
        .where((a) =>
            a.imageUrl != null &&
            a.imageUrl!.isNotEmpty &&
            !PosterCache.exists(a.posterPath))
        .toList();
    try {
      for (var i = 0; i < todo.length; i++) {
        _report('Affiche ${i + 1}/${todo.length}', (i + 1) / todo.length);
        final path = await PosterCache.ensure(todo[i].id, todo[i].imageUrl);
        if (path != null) {
          todo[i].posterPath = path;
          done++;
        }
      }
      await save();
    } finally {
      busy = false;
      _report('');
    }
    return done;
  }

  // ------------------------------------------------------------- Decouvrir

  bool inWishlist(MediaMeta meta) =>
      wishlist.any((w) => w.source == meta.source && w.sourceId == meta.sourceId);

  Future<void> toggleWishlist(MediaMeta meta) async {
    if (inWishlist(meta)) {
      wishlist.removeWhere(
          (w) => w.source == meta.source && w.sourceId == meta.sourceId);
    } else {
      wishlist.insert(0, meta);
    }
    await save();
    notifyListeners();
  }

  /// Serie du disque correspondant a une fiche du catalogue, s'il y en a une.
  MediaItem? localMatch(MediaMeta meta) {
    final keys = <String>{
      meta.fingerprint,
      if (meta.titleRomaji != null)
        meta.titleRomaji!.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''),
    }..removeWhere((k) => k.length < 4);

    for (final a in items) {
      if (a.malId != null && a.malId == meta.sourceId && a.metaSource == meta.source) {
        return a;
      }
      if (keys.contains(a.fingerprint)) return a;
    }
    return null;
  }

  /// Autres dossiers contenant apparemment la même série.
  List<MediaItem> duplicatesOf(MediaItem item) {
    final key = item.fingerprint;
    if (key.length < 4) return const [];
    return items
        .where((a) => a.id != item.id && a.fingerprint == key)
        .toList();
  }

  // ------------------------------------------------------------- serveurs

  ServerProfile? serverOf(MediaItem item) {
    if (item.serverId == null) return null;
    for (final s in servers) {
      if (s.id == item.serverId) return s;
    }
    return null;
  }

  Future<ServerProfile> addServer({
    required String name,
    required String url,
    String token = '',
    String wakeUrl = '',
    int wakeWaitSeconds = 60,
  }) async {
    final serveur = ServerProfile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? 'Serveur' : name.trim(),
      url: url,
      token: token,
      wakeUrl: wakeUrl,
      wakeWaitSeconds: wakeWaitSeconds,
    );
    servers.add(serveur);
    await save();
    notifyListeners();
    return serveur;
  }

  Future<void> updateServer(ServerProfile serveur) async {
    await save();
    notifyListeners();
  }

  /// Retire un serveur et tout ce qu'il apportait à la bibliothèque.
  Future<void> removeServer(ServerProfile serveur) async {
    servers.remove(serveur);
    items.removeWhere((a) => a.serverId == serveur.id);
    await music.dropServer(serveur.id);
    await save();
    notifyListeners();
  }

  /// Interroge un serveur et fusionne son contenu dans la bibliothèque.
  ///
  /// Les titres distants coexistent avec les locaux : la source est une
  /// marque sur la fiche, pas une catégorie séparée.
  Future<String> scanServer(ServerProfile serveur) async {
    if (busy) return 'Un scan est déjà en cours.';
    busy = true;
    _report('Connexion à ${serveur.name}');

    try {
      var reponse = await ServerApi.ping(serveur);

      // Serveur muet : on tente le réveil si une adresse est enregistrée.
      if (reponse == null && settings.autoWake && serveur.hasWake) {
        _report('Réveil de ${serveur.name}');
        final ok = await Wake.wakeAndWait(serveur,
            onProgress: (m) => _report(m));
        if (!ok) return Wake.lastError ?? 'Serveur injoignable.';
        reponse = await ServerApi.ping(serveur);
      }
      if (reponse == null) {
        return ServerApi.lastError ?? 'Serveur injoignable.';
      }

      final resultat = await RemoteScanner.scan(serveur,
          onProgress: (m) => _report(m));
      if (resultat.error != null) return resultat.error!;

      // On remplace ce qui venait de ce serveur, sans toucher au reste.
      final anciens = {
        for (final a in items.where((a) => a.serverId == serveur.id))
          a.id: a
      };
      items.removeWhere((a) => a.serverId == serveur.id);

      for (final trouve in resultat.items) {
        final ancien = anciens[trouve.id];
        if (ancien != null) {
          // La progression et les fiches déjà récupérées sont conservées.
          trouve.favorite = ancien.favorite;
          trouve.kids = ancien.kids;
          trouve.kidsManual = ancien.kidsManual;
          if (ancien.metaFetched) applyMeta(trouve, ancien.toMeta());
          trouve.copyProgressFrom(ancien);
        }
        items.add(trouve);
      }

      await music.mergeRemote(serveur.id, resultat.tracks);
      await save();
      return '${resultat.items.length} titre(s) et '
          '${resultat.tracks.length} morceau(x) trouvés sur ${serveur.name}.';
    } catch (e) {
      return 'Le scan du serveur a échoué : $e';
    } finally {
      busy = false;
      _report('');
    }
  }

  /// Repasse les fiches déjà enregistrées dans la table de traduction.
  /// Utile après une mise à jour du vocabulaire : sans ça, les anciennes
  /// fiches gardent leurs genres en anglais.
  Future<int> relabelAll() async {
    var changed = 0;
    for (final a in items) {
      final genres = Labels.genres(a.genres);
      final type = Labels.format(a.type);
      final status = Labels.status(a.status);
      if (genres.join('|') != a.genres.join('|') ||
          type != a.type ||
          status != a.status) {
        a.genres = genres;
        a.type = type;
        a.status = status;
        changed++;
      }
    }
    if (changed > 0) await save();
    notifyListeners();
    return changed;
  }

  /// Séries dont la fiche n'a pas pu être identifiée.
  List<MediaItem> get unmatched =>
      items.where((a) => !a.metaFetched).toList()
        ..sort((a, b) => a.folderTitle.compareTo(b.folderTitle));

  Future<void> clearLibrary() async {
    items = [];
    await PosterCache.clear();
    await save();
    notifyListeners();
  }

  List<String> get allGenres {
    final set = <String>{};
    for (final a in items) {
      set.addAll(a.genres);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// Bascule manuelle du classement jeunesse.
  Future<void> toggleKids(MediaItem item) async {
    item.kids = !item.kids;
    item.kidsManual = true;
    await save();
    notifyListeners();
  }

  /// Corrige la nature d'un titre quand la déduction s'est trompée.
  Future<void> setKind(MediaItem item, MediaKind kind) async {
    item.kind = kind;
    await save();
    notifyListeners();
  }

  int countOf(MediaKind kind) =>
      items.where((a) => a.kind == kind && !a.kids).length;

  /// Titres venant d'un serveur, toutes natures confondues.
  int get remoteCount => items.where((a) => a.remote).length;

  int get kidsCount => items.where((a) => a.kids).length;

  /// Liste filtrée et triée, restreinte à un onglet.
  List<MediaItem> view({
    String query = '',
    String genre = '',
    bool favoritesOnly = false,
    MediaKind? kind,
    bool kidsOnly = false,
    bool excludeKids = false,
  }) {
    final q = query.trim().toLowerCase();
    var list = items.where((a) {
      if (kidsOnly && !a.kids) return false;
      if (excludeKids && a.kids) return false;
      if (kind != null && a.kind != kind) return false;
      if (favoritesOnly && !a.favorite) return false;
      if (genre.isNotEmpty && !a.genres.contains(genre)) return false;
      if (q.isEmpty) return true;
      return a.title.toLowerCase().contains(q) ||
          a.folderTitle.toLowerCase().contains(q) ||
          a.genres.any((g) => g.toLowerCase().contains(q));
    }).toList();

    switch (settings.sortMode) {
      case 'score':
        list.sort((a, b) => (b.score ?? -1).compareTo(a.score ?? -1));
        break;
      case 'recent':
        list.sort((a, b) => b.newestFileMs.compareTo(a.newestFileMs));
        break;
      case 'popularity':
        list.sort((a, b) => (b.popularity ?? -1).compareTo(a.popularity ?? -1));
        break;
      case 'year':
        list.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
        break;
      case 'episodes':
        list.sort((a, b) => b.episodes.length.compareTo(a.episodes.length));
        break;
      case 'genre':
        list.sort((a, b) {
          final ga = a.genres.isEmpty ? 'zzz' : a.genres.first.toLowerCase();
          final gb = b.genres.isEmpty ? 'zzz' : b.genres.first.toLowerCase();
          final c = ga.compareTo(gb);
          return c != 0 ? c : a.sortKey.compareTo(b.sortKey);
        });
        break;
      default:
        list.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    }
    return list;
  }

  /// Regroupement par genre pour l'affichage en rayons.
  Map<String, List<MediaItem>> groupedByGenre({String query = ''}) {
    final map = <String, List<MediaItem>>{};
    for (final a in view(query: query)) {
      if (a.genres.isEmpty) {
        map.putIfAbsent('Sans genre', () => []).add(a);
      }
      for (final g in a.genres) {
        map.putIfAbsent(g, () => []).add(a);
      }
    }
    return map;
  }

  Future<void> updateSettings(void Function(AppSettings s) change) async {
    change(settings);
    await save();
    notifyListeners();
  }

  bool episodeExists(Episode e) => File(e.path).existsSync();
}
