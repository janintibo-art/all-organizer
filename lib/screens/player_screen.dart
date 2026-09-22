import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../main.dart';
import '../models/vf.dart';
import '../services/downloads.dart';
import '../models/media_item.dart';
import '../services/library_controller.dart';
import '../services/opensubtitles_api.dart';
import '../services/poster_cache.dart';
import '../services/video_hash.dart';

class PlayerScreen extends StatefulWidget {
  final String title;
  final List<Episode> episodes;
  final int startIndex;
  final MediaItem? item;
  final Duration startAt;

  const PlayerScreen({
    super.key,
    required this.title,
    required this.episodes,
    this.startIndex = 0,
    this.item,
    this.startAt = Duration.zero,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player();
  // Le décodage matériel se décide à la construction : le changer suppose
  // de relancer la lecture, ce que le réglage annonce.
  late final VideoController _controller = VideoController(
    _player,
    configuration: VideoControllerConfiguration(
      enableHardwareAcceleration: library.settings.hardwareDecoding,
    ),
  );
  final FocusNode _focus = FocusNode();

  final List<StreamSubscription<dynamic>> _subs = [];
  int _index = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _seeked = false;
  double _rate = 1.0;
  Tracks? _tracks;
  Timer? _autoSave;
  bool _langApplied = false;
  String? _notice;
  Timer? _noticeTimer;

  bool _locked = false;
  // Minuterie d'arrêt. L'échéance est une heure réelle, vérifiée chaque
  // seconde et à chaque avancée de la lecture : un minuteur unique pouvait
  // être retardé sans que rien ne le montre.
  Timer? _sleepTick;
  DateTime? _sleepAt;
  String _sleepChoice = '0';
  bool _stopAtEnd = false;
  double? _volumeAvantFondu;
  final ValueNotifier<String?> _sleepLabel = ValueNotifier(null);
  PlaylistMode _loopMode = PlaylistMode.none;
  bool _subtitleSearchDone = false;
  bool _searchingSubtitles = false;

  @override
  void initState() {
    super.initState();
    _index = widget.startIndex;

    // Plein écran automatique : le lecteur prend tout l'espace disponible.
    if (Platform.isAndroid) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }

    _player.open(
      Playlist(
        widget.episodes
            .map((e) => Media(widget.item == null
                ? Uri.file(e.path).toString()
                : MediaSource.forEpisode(widget.item!, e)))
            .toList(),
        index: widget.startIndex,
      ),
    );
    _applyEndMode();

    _subs.add(_player.stream.playlist.listen((event) {
      if (!mounted || event.index == _index) return;
      _persist();
      setState(() {
        _index = event.index;
        _position = Duration.zero;
        _duration = Duration.zero;
        _seeked = true;
        _langApplied = false;
        _subtitleSearchDone = false;
      });
      _loadExternalSubtitle();
      _loadExternalAudio();
      _flash('Épisode ${event.index + 1}');
    }));

    _subs.add(_player.stream.position.listen((p) {
      _position = p;
      _checkSleep();
    }));

    _subs.add(_player.stream.duration.listen((d) {
      _duration = d;
      if (!_seeked && d.inSeconds > 0 && widget.startAt.inSeconds > 5) {
        _seeked = true;
        _player.seek(widget.startAt);
      }
    }));

    _subs.add(_player.stream.tracks.listen((t) {
      if (!mounted) return;
      setState(() => _tracks = t);
      _applyPreferredLanguages(t);
      _noteAudioLanguage(t);
    }));

    // Sans ça, un codec absent se traduit par un écran noir muet.
    _subs.add(_player.stream.error.listen((message) {
      if (message.trim().isEmpty) return;
      _flash('Erreur de lecture : $message');
    }));

    _subs.add(_player.stream.completed.listen((done) {
      if (!done) return;
      _persist(forceWatched: true);
      if (_stopAtEnd) {
        // Minuterie « fin de l'épisode » : servie, on revient au réglage.
        _stopAtEnd = false;
        _sleepChoice = '0';
        _sleepLabel.value = null;
        _applyEndMode();
        _flash('Fin de l\'épisode : lecture arrêtée.');
      } else if (!library.settings.autoNext &&
          _index < widget.episodes.length - 1) {
        _flash('Fin de l\'épisode. Suivant : touche N ou ⏭.');
      }
    }));

    _autoSave = Timer.periodic(const Duration(seconds: 20), (_) => _persist());
    _loadExternalSubtitle();
    _loadExternalAudio();
  }

  void _flash(String message) {
    _noticeTimer?.cancel();
    setState(() => _notice = message);
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  /// Charge le .srt ou .ass posé à côté de la vidéo, s'il y en a un.
  void _loadExternalSubtitle() {
    if (widget.episodes.isEmpty) return;
    final episode = widget.episodes[_index.clamp(0, widget.episodes.length - 1)];
    if (episode.subtitles.isEmpty) return;

    final preferred = library.settings.preferredSubtitle.toLowerCase();
    final chosen = episode.subtitles.firstWhere(
      (path) => preferred.isNotEmpty && path.toLowerCase().contains(preferred),
      orElse: () => episode.subtitles.first,
    );
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _player.setSubtitleTrack(SubtitleTrack.uri(Uri.file(chosen).toString()));
    });
  }

  /// Charge une piste audio livrée dans un fichier séparé, si elle existe.
  void _loadExternalAudio() {
    if (widget.episodes.isEmpty) return;
    final episode = widget.episodes[_index.clamp(0, widget.episodes.length - 1)];
    if (episode.externalAudio.isEmpty) return;

    final preferred = library.settings.preferredAudio.toLowerCase();
    final chosen = episode.externalAudio.firstWhere(
      (path) => preferred.isNotEmpty && path.toLowerCase().contains(preferred),
      orElse: () => episode.externalAudio.first,
    );
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _player.setAudioTrack(AudioTrack.uri(Uri.file(chosen).toString()));
      _flash('Piste audio externe chargée.');
    });
  }

  /// Applique les langues préférées dès que les pistes sont connues.
  /// Pistes réelles, sans les choix « automatique » et « aucune ».
  static List<T> _vraies<T>(List<T> pistes) => pistes.where((p) {
        final id = (p as dynamic).id as String;
        return id != 'auto' && id != 'no';
      }).toList();

  /// Retient si l'épisode en cours a une piste française, d'après les
  /// étiquettes que le lecteur lit réellement dans le fichier. C'est ce qui
  /// alimente le filtre VF de la bibliothèque, plus sûr que le nom.
  void _noteAudioLanguage(Tracks t) {
    final item = widget.item;
    if (item == null || widget.episodes.isEmpty) return;
    final pistes = _vraies(t.audio);
    if (pistes.isEmpty) return;

    final fr = pistes.any((a) =>
        Vf.isFrench(a.language) ||
        Vf.isFrench(a.title) ||
        Vf.inName(a.title ?? ''));
    // Sans étiquette de langue, on ne sait rien : le nom du fichier reste
    // juge, plutôt que de conclure à tort « pas de VF ».
    final toutesEtiquetees =
        pistes.every((a) => (a.language ?? '').trim().isNotEmpty);
    if (!fr && !toutesEtiquetees) return;

    final episode =
        widget.episodes[_index.clamp(0, widget.episodes.length - 1)];
    library.noteAudio(item, episode, fr);
  }

  void _applyPreferredLanguages(Tracks tracks) {
    if (_langApplied) return;
    // Le lecteur signale souvent ses pistes avant de les connaître : on
    // attend qu'il y en ait de vraies, sinon la langue préférée ne serait
    // jamais appliquée à cet épisode.
    if (_vraies(tracks.audio).isEmpty && _vraies(tracks.subtitle).isEmpty) {
      return;
    }
    _langApplied = true;
    final audioPref = library.settings.preferredAudio.toLowerCase();
    final subPref = library.settings.preferredSubtitle.toLowerCase();

    if (audioPref.isNotEmpty) {
      for (final t in tracks.audio) {
        final lang = t.language ?? '';
        final title = t.title ?? '';
        final tag = '$lang $title'.toLowerCase();
        if (tag.contains(audioPref)) {
          _player.setAudioTrack(t);
          break;
        }
      }
    }
    var subtitleFound = false;
    if (subPref.isNotEmpty) {
      for (final t in tracks.subtitle) {
        final lang = t.language ?? '';
        final title = t.title ?? '';
        final tag = '$lang $title'.toLowerCase();
        if (tag.contains(subPref)) {
          _player.setSubtitleTrack(t);
          subtitleFound = true;
          break;
        }
      }
    }

    _reportMissing(tracks, audioPref, subtitleFound, subPref);
  }

  /// Signale ce que le fichier ne contient pas, et va chercher les
  /// sous-titres en ligne si la recherche automatique est activée.
  void _reportMissing(
    Tracks tracks,
    String audioPref,
    bool subtitleFound,
    String subPref,
  ) {
    final episode = widget.episodes.isEmpty
        ? null
        : widget.episodes[_index.clamp(0, widget.episodes.length - 1)];

    final hasLocalSubtitle =
        episode != null && episode.subtitles.isNotEmpty;

    if (!subtitleFound && !hasLocalSubtitle && subPref.isNotEmpty) {
      if (library.settings.autoFetchSubtitles &&
          library.settings.subtitleKey.trim().isNotEmpty) {
        _fetchSubtitles(auto: true);
      } else {
        _flash('Aucun sous-titre « $subPref » dans ce fichier.');
      }
    }

    if (audioPref.isNotEmpty) {
      final languages = tracks.audio
          .where((t) => t.id != 'auto')
          .map((t) => (t.language ?? t.title ?? '').toLowerCase())
          .where((l) => l.isNotEmpty)
          .toList();
      final hasPreferred = languages.any((l) => l.contains(audioPref));
      if (!hasPreferred && languages.isNotEmpty) {
        _flash('Audio disponible : ${languages.join(', ')}.');
      }
    }
  }

  /// Cherche des sous-titres sur OpenSubtitles pour l'épisode en cours.
  Future<void> _fetchSubtitles({bool auto = false}) async {
    if (_searchingSubtitles || widget.episodes.isEmpty) return;
    if (auto && _subtitleSearchDone) return;
    _subtitleSearchDone = true;

    final key = library.settings.subtitleKey.trim();
    if (key.isEmpty) {
      _flash('Renseigne une clé OpenSubtitles dans les réglages.');
      return;
    }

    setState(() => _searchingSubtitles = true);
    _flash('Recherche de sous-titres…');

    final episode = widget.episodes[_index.clamp(0, widget.episodes.length - 1)];
    final item = widget.item;
    final query = item?.romajiTitle?.isNotEmpty == true
        ? item!.romajiTitle!
        : (item?.title ?? widget.title);

    if (library.settings.subtitleUser.trim().isNotEmpty) {
      await OpenSubtitles.login(key, library.settings.subtitleUser,
          library.settings.subtitlePassword);
    }

    final hash = await VideoHash.compute(episode.path);
    final results = await OpenSubtitles.search(
      apiKey: key,
      query: query,
      language: library.settings.preferredSubtitle.isEmpty
          ? 'fr'
          : library.settings.preferredSubtitle,
      season: episode.season,
      episode: episode.number,
      moviehash: hash,
    );

    if (!mounted) return;
    setState(() => _searchingSubtitles = false);

    if (results.isEmpty) {
      _flash(OpenSubtitles.lastError ?? 'Aucun sous-titre trouvé.');
      return;
    }

    // En automatique on prend le meilleur, sinon on laisse choisir.
    if (auto) {
      await _applySubtitle(results.first, key);
    } else {
      _pickSubtitle(results, key);
    }
  }

  Future<void> _applySubtitle(SubtitleResult result, String key) async {
    _flash('Téléchargement du sous-titre…');
    final episode = widget.episodes[_index.clamp(0, widget.episodes.length - 1)];
    final path = await OpenSubtitles.download(
      apiKey: key,
      result: result,
      episodePath: episode.path,
    );
    if (!mounted) return;
    if (path == null) {
      _flash(OpenSubtitles.lastError ?? 'Téléchargement impossible.');
      return;
    }
    _player.setSubtitleTrack(SubtitleTrack.uri(Uri.file(path).toString()));
    final left = OpenSubtitles.remainingDownloads;
    _flash(left == null
        ? 'Sous-titre chargé.'
        : 'Sous-titre chargé · $left téléchargement(s) restant(s) aujourd\'hui.');
  }

  void _pickSubtitle(List<SubtitleResult> results, String key) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      builder: (ctx) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: results.length,
          itemBuilder: (_, i) {
            final r = results[i];
            return ListTile(
              dense: true,
              leading: Icon(
                r.fromHash ? Icons.verified : Icons.subtitles_outlined,
                color: r.fromHash ? Palette.kin : Palette.muted,
                size: 20,
              ),
              title: Text(r.release,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                r.fromHash
                    ? 'Synchronisé avec ton fichier'
                    : '${r.downloads} téléchargements',
                style: TextStyle(
                    fontSize: 11.5,
                    color: r.fromHash ? Palette.kin : Palette.muted),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _applySubtitle(r, key);
              },
            );
          },
        ),
      ),
    );
  }

  /// Capture l'image affichée et la garde comme affiche de la série.
  Future<void> _useFrameAsPoster() async {
    final item = widget.item;
    if (item == null) return;
    final bytes = await _player.screenshot();
    if (bytes == null) {
      _flash('Capture impossible sur cette vidéo.');
      return;
    }
    final path = await PosterCache.saveBytes(item.id, bytes);
    if (path == null) {
      _flash('Enregistrement impossible.');
      return;
    }
    item.posterPath = path;
    await library.save();
    library.refresh();
    _flash('Affiche mise à jour.');
  }

  void _persist({bool forceWatched = false}) {
    final item = widget.item;
    if (item == null || widget.episodes.isEmpty) return;
    final episode = widget.episodes[_index.clamp(0, widget.episodes.length - 1)];
    library.savePlayback(
      item,
      episode,
      forceWatched ? _duration : _position,
      _duration,
    );
  }

  @override
  void dispose() {
    _autoSave?.cancel();
    _noticeTimer?.cancel();
    _sleepTick?.cancel();
    _sleepLabel.dispose();
    _persist();
    for (final s in _subs) {
      s.cancel();
    }
    _focus.dispose();
    _player.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ------------------------------------------------------------- commandes

  void _seekBy(int seconds) {
    final target = _position + Duration(seconds: seconds);
    _player.seek(target < Duration.zero ? Duration.zero : target);
  }

  BoxFit get _fit {
    switch (library.settings.videoFit) {
      case 'cover':
        return BoxFit.cover;
      case 'fill':
        return BoxFit.fill;
      default:
        return BoxFit.contain;
    }
  }

  /// Apparence des sous-titres, d'après les réglages. Sert au lecteur et à
  /// l'aperçu du panneau d'options, qui restent ainsi identiques.
  TextStyle _subtitleTextStyle({double? size}) {
    final s = library.settings;
    const noir = Color(0xFF000000);
    final taille = size ?? s.subtitleSize;

    List<Shadow>? ombres;
    Color? fond;
    if (s.subtitleStyle == 'outline') {
      // Contour : huit ombres nettes, sans flou, autour de chaque lettre.
      final double e = (taille / 16).clamp(1.5, 4.0).toDouble();
      ombres = [
        for (final dx in [-e, 0.0, e])
          for (final dy in [-e, 0.0, e])
            if (dx != 0 || dy != 0)
              Shadow(offset: Offset(dx, dy), color: noir),
      ];
    } else if (s.subtitleStyle == 'box') {
      fond = const Color(0xAA000000);
    } else if (s.subtitleStyle == 'solid') {
      fond = noir;
    } else {
      ombres = const [
        Shadow(blurRadius: 6, color: noir),
        Shadow(blurRadius: 12, color: noir),
      ];
    }

    return TextStyle(
      fontSize: taille,
      height: 1.3,
      color: Color(s.subtitleColor),
      fontWeight: s.subtitleBold ? FontWeight.w700 : FontWeight.w400,
      backgroundColor: fond,
      shadows: ombres,
    );
  }

  /// Enchaîner ou s'arrêter à la fin de chaque épisode.
  ///
  /// L'ancienne méthode laissait le lecteur passer à l'épisode suivant puis
  /// le mettait en pause en catastrophe : le suivant démarrait une fraction
  /// de seconde et devenait « le dernier regardé ». mpv sait faire mieux :
  /// avec keep-open=always, il ne passe jamais tout seul au fichier suivant
  /// et reste sur la dernière image. « yes » garde l'enchaînement normal.
  Future<void> _applyEndMode() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final stop = _stopAtEnd || !library.settings.autoNext;
    try {
      await platform.setProperty('keep-open', stop ? 'always' : 'yes');
    } catch (_) {
      // Sans ce réglage, la lecture continue simplement comme avant.
    }
  }

  /// Minuterie d'arrêt. [choice] vaut « 0 », « end » ou un nombre de minutes.
  void _setSleep(String choice) {
    _sleepTick?.cancel();
    _restaurerVolume();
    _sleepAt = null;
    _stopAtEnd = false;
    _sleepChoice = choice;

    if (choice == '0') {
      _sleepLabel.value = null;
      _applyEndMode();
      _flash('Minuterie annulée.');
      return;
    }

    if (choice == 'end') {
      _stopAtEnd = true;
      _sleepLabel.value = 'Fin d\'épisode';
      _applyEndMode();
      _flash('Arrêt à la fin de l\'épisode.');
      return;
    }

    final minutes = int.parse(choice);
    _applyEndMode();
    _sleepAt = DateTime.now().add(Duration(minutes: minutes));
    _sleepTick =
        Timer.periodic(const Duration(seconds: 1), (_) => _checkSleep());
    _checkSleep();
    _flash('Arrêt automatique dans ${_duree(Duration(minutes: minutes))}.');
  }

  /// Compare l'heure à l'échéance, met à jour le compte à rebours et baisse
  /// le son pendant les vingt dernières secondes.
  void _checkSleep() {
    final at = _sleepAt;
    if (at == null) return;
    final reste = at.difference(DateTime.now());

    if (reste <= Duration.zero) {
      _sleepExpire();
      return;
    }

    _sleepLabel.value = reste.inSeconds < 60
        ? '${reste.inSeconds} s'
        : '${(reste.inSeconds / 60).ceil()} min';

    if (reste.inSeconds <= 20) {
      _volumeAvantFondu ??= _player.state.volume;
      final base = _volumeAvantFondu!;
      _player.setVolume(
          (base * reste.inMilliseconds / 20000).clamp(0, base).toDouble());
    }
  }

  void _sleepExpire() {
    _sleepTick?.cancel();
    _sleepAt = null;
    _sleepChoice = '0';
    _sleepLabel.value = null;
    _player.pause();
    // Le son revient à son niveau après la pause : la prochaine lecture ne
    // repartira pas muette.
    _restaurerVolume();
    _persist();
    if (mounted) _flash('Minuterie écoulée, lecture en pause.');
  }

  void _restaurerVolume() {
    final v = _volumeAvantFondu;
    if (v == null) return;
    _volumeAvantFondu = null;
    _player.setVolume(v);
  }

  static String _duree(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    final m = d.inMinutes % 60;
    return '${d.inHours} h${m == 0 ? '' : ' ${m.toString().padLeft(2, '0')}'}';
  }

  void _setLoop(PlaylistMode mode) {
    setState(() => _loopMode = mode);
    _player.setPlaylistMode(mode);
    _flash(mode == PlaylistMode.single
        ? 'Épisode en boucle.'
        : (mode == PlaylistMode.loop
            ? 'Série en boucle.'
            : 'Lecture normale.'));
  }

  void _setRate(double rate) {
    setState(() => _rate = rate);
    _player.setRate(rate);
  }

  /// Raccourcis clavier, surtout utiles sous Windows.
  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      _player.playOrPause();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(library.settings.seekStepSeconds);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-library.settings.seekStepSeconds);
    } else if (key == LogicalKeyboardKey.keyS) {
      _seekBy(library.settings.skipIntroSeconds);
    } else if (key == LogicalKeyboardKey.keyN) {
      _player.next();
    } else if (key == LogicalKeyboardKey.keyP) {
      _player.previous();
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _player.setVolume((_player.state.volume + 10).clamp(0, 100));
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _player.setVolume((_player.state.volume - 10).clamp(0, 100));
    }
  }

  @override
  Widget build(BuildContext context) {
    final episode =
        widget.episodes[_index.clamp(0, widget.episodes.length - 1)];

    return KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          surfaceTintColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            widget.episodes.isEmpty ? widget.title : episode.label,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Passer l\'intro (S)',
              onPressed: () => _seekBy(library.settings.skipIntroSeconds),
              icon: const Icon(Icons.fast_forward),
            ),
            _rateMenu(),
            if (widget.episodes.length > 1)
              IconButton(
                tooltip: 'Épisode précédent (P)',
                onPressed: () => _player.previous(),
                icon: const Icon(Icons.skip_previous),
              ),
            if (widget.episodes.length > 1)
              IconButton(
                tooltip: 'Épisode suivant (N)',
                onPressed: () => _player.next(),
                icon: const Icon(Icons.skip_next),
              ),
            IconButton(
              tooltip: 'Options',
              onPressed: _openOptions,
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Video(
                      controller: _controller,
                      controls: _locked ? NoVideoControls : AdaptiveVideoControls,
                      fit: _fit,
                      subtitleViewConfiguration: SubtitleViewConfiguration(
                        style: _subtitleTextStyle(),
                        padding: EdgeInsets.fromLTRB(
                            16, 0, 16, library.settings.subtitleBottom),
                      ),
                    ),
                  ),
                  // Compte à rebours de la minuterie : visible sans ouvrir
                  // les options, et une touche l'annule.
                  Positioned(
                    top: 12,
                    left: 12,
                    child: ValueListenableBuilder<String?>(
                      valueListenable: _sleepLabel,
                      builder: (context, label, _) {
                        if (label == null) return const SizedBox.shrink();
                        return GestureDetector(
                          onTap: () => _setSleep('0'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xCC0D0B0B),
                              border: Border.all(color: Palette.kin),
                              borderRadius: BorderRadius.circular(radiusSm),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.bedtime_outlined,
                                    size: 15, color: Palette.kin),
                                const SizedBox(width: 6),
                                Text(label,
                                    style: TextStyle(
                                        color: Palette.kin,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(width: 6),
                                const Icon(Icons.close,
                                    size: 14, color: Colors.white70),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (_locked)
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xCC0D0B0B),
                        ),
                        onPressed: () => setState(() => _locked = false),
                        icon: const Icon(Icons.lock_open,
                            color: Colors.white),
                      ),
                    ),
                  if (_notice != null)
                    Positioned(
                      left: 16,
                      top: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xE60D0B0B),
                          border: Border.all(color: Palette.shu),
                          borderRadius: BorderRadius.circular(radiusSm),
                        ),
                        child: Text(_notice!,
                            style: TextStyle(
                                color: Palette.text, fontSize: 12.5)),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.episodes.length > 1) _episodeStrip(),
          ],
        ),
      ),
    );
  }

  /// Panneau d'options : tout ce qui ne merite pas un bouton permanent.
  void _openOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) {
          void update(VoidCallback action) {
            action();
            refresh(() {});
            setState(() {});
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(width: 3, height: 16, color: Palette.shu),
                      const SizedBox(width: 8),
                      const Text('Options de lecture',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  _optionTitle('Ajustement de l\'image'),
                  _choices(
                    values: const {
                      'contain': 'Entière',
                      'cover': 'Remplir l\'écran',
                      'fill': 'Étirer',
                    },
                    selected: library.settings.videoFit,
                    onSelected: (v) => update(
                        () => library.updateSettings((s) => s.videoFit = v)),
                  ),

                  _optionTitle('Sous-titres'),
                  // Aperçu : le lecteur est souvent en pause pendant qu'on
                  // règle, et une réplique n'est pas toujours à l'écran.
                  Container(
                    width: double.infinity,
                    height: 110,
                    alignment: Alignment.bottomCenter,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF3A4A5C), Color(0xFF8A6A4A)],
                      ),
                      borderRadius: BorderRadius.circular(radiusMd),
                    ),
                    child: Text(
                      'Voici tes sous-titres.',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      // L'aperçu est plafonné : une taille « énorme » ne tient
                      // pas dans le cadre, mais les proportions restent vraies.
                      style: _subtitleTextStyle(
                          size: library.settings.subtitleSize.clamp(14, 44).toDouble()),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Taille : ${library.settings.subtitleSize.round()}',
                    style: TextStyle(color: Palette.muted, fontSize: 12),
                  ),
                  Slider(
                    value: library.settings.subtitleSize.clamp(16, 80).toDouble(),
                    min: 16,
                    max: 80,
                    divisions: 32,
                    activeColor: Palette.shu,
                    inactiveColor: Palette.raised,
                    label: '${library.settings.subtitleSize.round()}',
                    // Pendant le glissement, seul l'écran change ; la
                    // bibliothèque n'est enregistrée qu'au lâcher.
                    onChanged: (v) =>
                        update(() => library.settings.subtitleSize = v),
                    onChangeEnd: (v) =>
                        library.updateSettings((s) => s.subtitleSize = v),
                  ),
                  _choices(
                    values: const {
                      '20': 'Très petite',
                      '26': 'Petite',
                      '32': 'Normale',
                      '40': 'Grande',
                      '52': 'Très grande',
                      '64': 'Énorme',
                    },
                    selected:
                        library.settings.subtitleSize.round().toString(),
                    onSelected: (v) => update(() => library.updateSettings(
                        (s) => s.subtitleSize = double.parse(v))),
                  ),
                  const SizedBox(height: 12),
                  Text('Style',
                      style: TextStyle(color: Palette.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  _choices(
                    values: const {
                      'shadow': 'Ombre',
                      'outline': 'Contour',
                      'box': 'Bandeau',
                      'solid': 'Bandeau opaque',
                    },
                    selected: library.settings.subtitleStyle,
                    onSelected: (v) => update(() =>
                        library.updateSettings((s) => s.subtitleStyle = v)),
                  ),
                  const SizedBox(height: 12),
                  Text('Couleur',
                      style: TextStyle(color: Palette.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  _choices(
                    values: const {
                      '4294967295': 'Blanc', // 0xFFFFFFFF
                      '4294961979': 'Jaune', // 0xFFFFEB3B
                      '4286644223': 'Cyan', // 0xFF80FFFF
                      '4288479098': 'Vert', // 0xFF9CFF7A
                      '4294942678': 'Rose', // 0xFFFF9FD6
                    },
                    selected: library.settings.subtitleColor.toString(),
                    onSelected: (v) => update(() => library.updateSettings(
                        (s) => s.subtitleColor = int.parse(v))),
                  ),
                  const SizedBox(height: 12),
                  Text('Épaisseur',
                      style: TextStyle(color: Palette.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  _choices(
                    values: const {'normal': 'Normale', 'bold': 'Grasse'},
                    selected:
                        library.settings.subtitleBold ? 'bold' : 'normal',
                    onSelected: (v) => update(() => library.updateSettings(
                        (s) => s.subtitleBold = v == 'bold')),
                  ),
                  const SizedBox(height: 12),
                  Text('Position',
                      style: TextStyle(color: Palette.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  _choices(
                    values: const {
                      '8': 'Tout en bas',
                      '24': 'Bas',
                      '72': 'Relevée',
                      '140': 'Haute',
                    },
                    selected:
                        library.settings.subtitleBottom.round().toString(),
                    onSelected: (v) => update(() => library.updateSettings(
                        (s) => s.subtitleBottom = double.parse(v))),
                  ),

                  _optionTitle('Saut des flèches'),
                  _choices(
                    values: const {
                      '5': '5 s',
                      '10': '10 s',
                      '30': '30 s',
                      '60': '1 min',
                    },
                    selected: library.settings.seekStepSeconds.toString(),
                    onSelected: (v) => update(() => library
                        .updateSettings((s) => s.seekStepSeconds = int.parse(v))),
                  ),

                  _optionTitle('Répétition'),
                  _choices(
                    values: const {
                      'none': 'Aucune',
                      'single': 'Épisode',
                      'loop': 'Série',
                    },
                    selected: _loopMode.name,
                    onSelected: (v) => update(() => _setLoop(
                          v == 'single'
                              ? PlaylistMode.single
                              : v == 'loop'
                                  ? PlaylistMode.loop
                                  : PlaylistMode.none,
                        )),
                  ),

                  _optionTitle('À la fin de l\'épisode'),
                  _choices(
                    values: const {
                      'next': 'Enchaîner',
                      'stop': 'S\'arrêter',
                    },
                    selected: library.settings.autoNext ? 'next' : 'stop',
                    onSelected: (v) => update(() {
                      library.updateSettings((s) => s.autoNext = v == 'next');
                      _applyEndMode();
                    }),
                  ),

                  _optionTitle('Minuterie d\'arrêt'),
                  _choices(
                    values: const {
                      '0': 'Aucune',
                      'end': 'Fin de l\'épisode',
                      '15': '15 min',
                      '30': '30 min',
                      '45': '45 min',
                      '60': '1 h',
                      '90': '1 h 30',
                      '120': '2 h',
                    },
                    // On retient le choix lui-même : recalculer le temps
                    // restant donnait « 14 », qu'aucune case ne portait, et
                    // la minuterie semblait ne pas avoir été prise.
                    selected: _sleepChoice,
                    onSelected: (v) => update(() => _setSleep(v)),
                  ),
                  if (_sleepChoice != '0' && _sleepChoice != 'end')
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Le son baisse doucement pendant les vingt dernières '
                        'secondes, puis la lecture se met en pause.',
                        style: TextStyle(
                            color: Palette.muted, fontSize: 11.5, height: 1.4),
                      ),
                    ),

                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() => _locked = true);
                          _flash('Commandes verrouillées.');
                        },
                        icon: const Icon(Icons.lock_outline, size: 18),
                        label: const Text('Verrouiller l\'écran'),
                      ),
                      if (widget.item != null)
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _useFrameAsPoster();
                          },
                          icon: const Icon(Icons.image_outlined, size: 18),
                          label: const Text('Image comme affiche'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showTracks();
                        },
                        icon: const Icon(Icons.subtitles_outlined, size: 18),
                        label: const Text('Pistes audio et sous-titres'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showTechnical();
                        },
                        icon: const Icon(Icons.memory, size: 18),
                        label: const Text('Informations techniques'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _searchingSubtitles
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _fetchSubtitles();
                              },
                        icon: const Icon(Icons.travel_explore, size: 18),
                        label: const Text('Chercher des sous-titres en ligne'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Raccourcis clavier : espace pause, flèches déplacement et volume, '
                    'S passer l\'intro, N et P changer d\'épisode, Échap quitter.',
                    style: TextStyle(
                        color: Palette.muted, fontSize: 11.5, height: 1.4),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _optionTitle(String label) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Text(label,
            style: TextStyle(
                color: Palette.muted, fontSize: 12, letterSpacing: 0.5)),
      );

  Widget _choices({
    required Map<String, String> values,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in values.entries)
          GestureDetector(
            onTap: () => onSelected(entry.key),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected == entry.key
                    ? Palette.shu
                    : Colors.transparent,
                border: Border.all(
                    color: selected == entry.key
                        ? Palette.shu
                        : Palette.line),
                borderRadius: BorderRadius.circular(radiusSm),
              ),
              child: Text(
                entry.value,
                style: TextStyle(
                  fontSize: 12.5,
                  color: selected == entry.key
                      ? Colors.white
                      : Palette.muted,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Ce que le lecteur voit réellement du fichier. À consulter quand une
  /// vidéo refuse de se lire ou que l'image saccade.
  void _showTechnical() {
    final episode = widget.episodes.isEmpty
        ? null
        : widget.episodes[_index.clamp(0, widget.episodes.length - 1)];
    final state = _player.state;
    final tracks = _tracks;

    String duree(Duration d) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return h > 0 ? '$h:$m:$sec' : '$m:$sec';
    }

    final lignes = <List<String>>[
      if (episode != null)
        ['Fichier', episode.name],
      if (episode != null)
        ['Format du conteneur', episode.path.split('.').last.toUpperCase()],
      [
        'Résolution',
        (state.width == null || state.height == null)
            ? 'inconnue'
            : '${state.width} × ${state.height}'
      ],
      ['Durée', duree(state.duration)],
      [
        'Débit audio',
        state.audioBitrate == null
            ? 'inconnu'
            : '${(state.audioBitrate! / 1000).round()} kbit/s'
      ],
      [
        'Pistes audio',
        tracks == null
            ? 'en cours de lecture'
            : '${tracks.audio.where((t) => t.id != 'auto').length}'
      ],
      [
        'Pistes de sous-titres',
        tracks == null ? 'en cours de lecture' : '${tracks.subtitle.length}'
      ],
      if (episode != null && episode.subtitles.isNotEmpty)
        ['Sous-titres externes', '${episode.subtitles.length} fichier(s)'],
      if (episode != null && episode.externalAudio.isNotEmpty)
        ['Audio externe', '${episode.externalAudio.length} fichier(s)'],
      [
        'Décodage matériel',
        library.settings.hardwareDecoding ? 'activé' : 'désactivé'
      ],
      ['Vitesse', '${_rate}x'],
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(width: 3, height: 16, color: Palette.shu),
                  const SizedBox(width: 8),
                  const Text('Informations techniques',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 14),
              for (final ligne in lignes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 150,
                        child: Text(ligne[0],
                            style: TextStyle(
                                color: Palette.muted, fontSize: 12)),
                      ),
                      Expanded(
                        child: SelectableText(
                          ligne[1],
                          style: TextStyle(
                              color: Palette.text, fontSize: 12.5, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              Text(
                'Si la vidéo reste noire ou saccade, essaie de désactiver le '
                'décodage matériel dans les réglages du lecteur, puis relance '
                'l\'épisode. Certains fichiers HEVC 10 bits et les pistes DTS '
                'ne sont pas gérés par tous les appareils.',
                style: TextStyle(
                    color: Palette.muted, fontSize: 11.5, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Les pistes restent dans une feuille dediee : leur nombre varie.
  void _showTracks() {
    final tracks = _tracks;
    if (tracks == null) {
      _flash('Pistes pas encore connues.');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('Audio',
                  style: TextStyle(color: Palette.muted, fontSize: 12)),
            ),
            for (final t in tracks.audio.where((t) => t.id != 'auto'))
              ListTile(
                dense: true,
                title: Text(_trackLabel(t, 'Piste ${t.id}'),
                    style: const TextStyle(fontSize: 13.5)),
                trailing: _player.state.track.audio.id == t.id
                    ? Icon(Icons.check, color: Palette.shu, size: 18)
                    : null,
                onTap: () {
                  _player.setAudioTrack(t);
                  Navigator.pop(ctx);
                },
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text('Sous-titres',
                  style: TextStyle(color: Palette.muted, fontSize: 12)),
            ),
            for (final t in tracks.subtitle)
              ListTile(
                dense: true,
                title: Text(
                    t.id == 'no' ? 'Aucun' : _trackLabel(t, 'Piste ${t.id}'),
                    style: const TextStyle(fontSize: 13.5)),
                trailing: _player.state.track.subtitle.id == t.id
                    ? Icon(Icons.check, color: Palette.shu, size: 18)
                    : null,
                onTap: () {
                  _player.setSubtitleTrack(t);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _rateMenu() {
    const rates = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    return PopupMenuButton<double>(
      color: Palette.surface,
      tooltip: 'Vitesse de lecture',
      onSelected: _setRate,
      itemBuilder: (_) => [
        for (final r in rates)
          PopupMenuItem(
            value: r,
            child: Row(
              children: [
                Icon(
                  r == _rate ? Icons.check : Icons.speed,
                  size: 16,
                  color: r == _rate ? Palette.shu : Palette.muted,
                ),
                const SizedBox(width: 10),
                Text('${r}x'),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: Text(
            '${_rate}x',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ),
    );
  }

  String _trackLabel(dynamic track, String fallback) {
    final title = track.title as String?;
    final language = track.language as String?;
    if (title != null && title.isNotEmpty) {
      return language == null ? title : '$title ($language)';
    }
    if (language != null && language.isNotEmpty) return language;
    return fallback;
  }

  Widget _episodeStrip() {
    return SizedBox(
      height: 62,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: widget.episodes.length,
        itemBuilder: (context, i) {
          final e = widget.episodes[i];
          final selected = i == _index;
          final seen = widget.item?.isWatched(e) ?? false;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: GestureDetector(
              onTap: () => _player.jump(i),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: selected ? Palette.shu : Colors.transparent,
                  border: Border.all(
                      color: selected
                          ? Palette.shu
                          : (seen ? Palette.kin : Palette.line)),
                  borderRadius: BorderRadius.circular(radiusSm),
                ),
                child: Text(
                  e.bonus ? '★' : '${e.number ?? i + 1}',
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : (seen ? Palette.kin : Palette.muted),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
