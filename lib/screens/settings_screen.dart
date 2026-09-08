import 'package:flutter/material.dart';

import '../main.dart';
import '../services/library_controller.dart';
import '../services/audio_player_service.dart';
import '../services/music_controller.dart';
import '../services/ai_service.dart';
import '../services/diagnostics.dart';
import '../services/links.dart';
import '../services/tmdb_api.dart';
import '../services/poster_cache.dart';
import 'bulk_fix_screen.dart';
import 'folder_picker_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _key =
      TextEditingController(text: library.settings.apiKey);
  late final TextEditingController _endpoint =
      TextEditingController(text: library.settings.libreEndpoint);
  late final TextEditingController _email =
      TextEditingController(text: library.settings.email);
  late final TextEditingController _aiKey =
      TextEditingController(text: library.settings.aiKey);
  late final TextEditingController _aiModel =
      TextEditingController(text: library.settings.aiModel);
  late final TextEditingController _aiEndpoint =
      TextEditingController(text: library.settings.aiEndpoint);

  late final TextEditingController _audioLang =
      TextEditingController(text: library.settings.preferredAudio);
  late final TextEditingController _subLang =
      TextEditingController(text: library.settings.preferredSubtitle);
  late final TextEditingController _tmdbKey =
      TextEditingController(text: library.settings.tmdbKey);
  late final TextEditingController _subKey =
      TextEditingController(text: library.settings.subtitleKey);
  late final TextEditingController _subUser =
      TextEditingController(text: library.settings.subtitleUser);
  late final TextEditingController _subPass =
      TextEditingController(text: library.settings.subtitlePassword);

  List<String> _models = [];
  List<String> _diagnostic = [];
  bool _diagBusy = false;



  String? _aiMessage;
  bool _aiBusy = false;

  @override
  void dispose() {
    _key.dispose();
    _endpoint.dispose();
    _email.dispose();
    _aiKey.dispose();
    _aiModel.dispose();
    _aiEndpoint.dispose();
    _audioLang.dispose();
    _subLang.dispose();
    _tmdbKey.dispose();
    _subKey.dispose();
    _subUser.dispose();
    _subPass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final s = library.settings;
        return Scaffold(
          appBar: darkAppBar(title: const Text('Réglages')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              if (audioInitError != null || startupErrors.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Palette.shu.withAlpha(20),
                    border: Border.all(color: Palette.shu),
                    borderRadius: BorderRadius.circular(radiusMd),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 17, color: Palette.shu),
                          const SizedBox(width: 8),
                          Text('Demarrage',
                              style: TextStyle(
                                  color: Palette.shu,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (audioInitError != null)
                        SelectableText(
                          'La session media n a pas pu etre ouverte. La '
                          'lecture fonctionne, sans commandes sur l ecran '
                          'verrouille.\n\n$audioInitError',
                          style: TextStyle(
                              color: Palette.muted,
                              fontSize: 11.5,
                              height: 1.45),
                        ),
                      for (final e in startupErrors)
                        SelectableText(e,
                            style: TextStyle(
                                color: Palette.muted,
                                fontSize: 11.5,
                                height: 1.45)),
                    ],
                  ),
                ),
              _card(
                icon: Icons.folder_copy_outlined,
                title: 'Bibliothèque',
                children: [
                  if (library.folders.isEmpty)
                    Text('Aucun dossier pour l\'instant.',
                        style: TextStyle(color: Palette.muted, fontSize: 13)),
                  for (final f in library.folders)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading:
                          Icon(Icons.folder_outlined, color: Palette.kin),
                      title: Text(f, style: const TextStyle(fontSize: 12.5)),
                      trailing: IconButton(
                        icon: Icon(Icons.close,
                            color: Palette.muted, size: 18),
                        onPressed: () => _confirmRemoveFolder(f),
                      ),
                    ),
                  _switch(
                    value: s.scanOnStart,
                    onChanged: (v) =>
                        library.updateSettings((s) => s.scanOnStart = v),
                    title: 'Scanner à chaque ouverture',
                    subtitle:
                        'Détecte les nouveaux items. Les fiches déjà trouvées sont conservées.',
                  ),
                ],
              ),
              _card(
                icon: Icons.storage,
                title: 'Ta mémoire',
                children: [
                  Text(
                    '${library.knownTitles.length} correspondance(s) mémorisée(s) '
                    'depuis tes corrections. Ces dossiers ne seront plus recherchés.',
                    style: TextStyle(
                        color: Palette.kin, fontSize: 12, height: 1.4),
                  ),
                  if (library.knownTitles.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _forgetTitles,
                      icon: const Icon(Icons.backspace_outlined, size: 18),
                      label: const Text('Oublier les correspondances'),
                    ),
                  ],
                ],
              ),
              _card(
                icon: Icons.badge_outlined,
                title: 'Métadonnées',
                children: [
                  _dropdown<String>(
                    label: 'Source',
                    value: s.metaSource,
                    items: const {
                      'auto': 'TMDB, puis TVmaze pour les séries',
                      'tmdb': 'TMDB seulement',
                      'tvmaze': 'TVmaze seulement (séries)',
                    },
                    onChanged: (v) =>
                        library.updateSettings((s) => s.metaSource = v),
                  ),
                  _field(
                    controller: _tmdbKey,
                    label: 'Clé TMDB',
                    hint: 'Indispensable : films, séries et textes en français',
                    obscure: true,
                    onSubmit: (v) => library.updateSettings((s) => s.tmdbKey = v),
                  ),
                  GestureDetector(
                    onTap: () => Links.open(TmdbApi.keyUrl),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Icon(Icons.open_in_new,
                              size: 14, color: Palette.kin),
                          const SizedBox(width: 6),
                          Text('Obtenir une clé gratuite',
                              style: TextStyle(
                                  color: Palette.kin,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  _switch(
                    value: s.autoFetch,
                    onChanged: (v) =>
                        library.updateSettings((s) => s.autoFetch = v),
                    title: 'Chercher images et descriptions',
                    subtitle: 'Images, synopsis, genres, notes et studios.',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed:
                            library.busy ? null : () => library.retryFailed(),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Compléter les fiches manquantes'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const BulkFixScreen()),
                        ),
                        icon: const Icon(Icons.edit_note, size: 18),
                        label: Text(
                            'Corriger ${library.unmatched.length} fiche(s)'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _relabel,
                        icon: const Icon(Icons.g_translate, size: 18),
                        label: const Text('Retraduire les fiches existantes'),
                      ),
                    ],
                  ),
                ],
              ),
              _card(
                icon: Icons.translate,
                title: 'Traduction',
                children: [
                  _dropdown<String>(
                    label: 'Service',
                    value: s.translationProvider,
                    items: const {
                      'none': 'Aucune traduction',
                      'mymemory': 'MyMemory (gratuit, sans clé)',
                      'libretranslate': 'LibreTranslate',
                      'deepl': 'DeepL (clé requise)',
                    },
                    onChanged: (v) =>
                        library.updateSettings((s) => s.translationProvider = v),
                  ),
                  _dropdown<String>(
                    label: 'Langue cible',
                    value: s.targetLang,
                    items: const {
                      'fr': 'Français',
                      'es': 'Espagnol',
                      'de': 'Allemand',
                      'it': 'Italien',
                      'pt': 'Portugais',
                      'nl': 'Néerlandais',
                    },
                    onChanged: (v) =>
                        library.updateSettings((s) => s.targetLang = v),
                  ),
                  if (s.translationProvider == 'mymemory')
                    _field(
                      controller: _email,
                      label: 'Email (facultatif)',
                      hint: 'Fait passer le quota de 5 000 à 50 000 caractères par jour',
                      onSubmit: (v) => library.updateSettings((s) => s.email = v),
                    ),
                  if (s.translationProvider == 'libretranslate')
                    _field(
                      controller: _endpoint,
                      label: 'Adresse du serveur',
                      hint: 'https://libretranslate.com',
                      onSubmit: (v) =>
                          library.updateSettings((s) => s.libreEndpoint = v),
                    ),
                  if (s.translationProvider == 'libretranslate' ||
                      s.translationProvider == 'deepl')
                    _field(
                      controller: _key,
                      label: 'Clé API',
                      hint: 'Collée depuis ton compte',
                      obscure: true,
                      onSubmit: (v) => library.updateSettings((s) => s.apiKey = v),
                    ),
                  _switch(
                    value: s.autoTranslate,
                    onChanged: (v) =>
                        library.updateSettings((s) => s.autoTranslate = v),
                    title: 'Traduire pendant le scan',
                    subtitle: 'Plus lent, mais les fiches sont prêtes tout de suite.',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed:
                        library.busy ? null : () => library.translateAll(),
                    icon: const Icon(Icons.translate, size: 18),
                    label: const Text('Tout traduire'),
                  ),
                ],
              ),
              _card(
                icon: Icons.play_circle_outline,
                title: 'Lecteur',
                children: [
                  _switch(
                    value: s.autoNext,
                    onChanged: (v) =>
                        library.updateSettings((s) => s.autoNext = v),
                    title: 'Enchaîner les épisodes',
                    subtitle:
                        'Sinon la lecture s\'arrête à la fin de chaque épisode.',
                  ),
                  _dropdown<int>(
                    label: 'Bouton « passer l\'intro »',
                    value: const [60, 85, 90, 120].contains(s.skipIntroSeconds)
                        ? s.skipIntroSeconds
                        : 85,
                    items: const {
                      60: '60 secondes',
                      85: '85 secondes (générique classique)',
                      90: '90 secondes',
                      120: '2 minutes',
                    },
                    onChanged: (v) =>
                        library.updateSettings((s) => s.skipIntroSeconds = v),
                  ),
                  _switch(
                    value: s.hardwareDecoding,
                    onChanged: (v) =>
                        library.updateSettings((s) => s.hardwareDecoding = v),
                    title: 'Décodage matériel',
                    subtitle:
                        'À désactiver si une vidéo reste noire ou saccade. '
                        'Prend effet au prochain épisode lancé.',
                  ),
                  _field(
                    controller: _audioLang,
                    label: 'Langue audio préférée',
                    hint: 'jpn, fre, eng… laisser vide pour ne rien forcer',
                    onSubmit: (v) =>
                        library.updateSettings((s) => s.preferredAudio = v),
                  ),
                  _field(
                    controller: _subLang,
                    label: 'Sous-titres préférés',
                    hint: 'fr, fre, vostfr…',
                    onSubmit: (v) =>
                        library.updateSettings((s) => s.preferredSubtitle = v),
                  ),
                  Text(
                    'Les fichiers .srt ou .ass posés à côté des vidéos sont chargés '
                    'automatiquement, ainsi que les pistes audio livrées à part.',
                    style: TextStyle(
                        color: Palette.muted, fontSize: 12, height: 1.4),
                  ),
                  Divider(color: Palette.line, height: 28),
                  const Text('Sous-titres en ligne',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    'Quand un épisode n\'a pas de sous-titres dans ta langue, '
                    'ils sont cherchés sur OpenSubtitles. La recherche utilise '
                    'l\'empreinte du fichier, ce qui donne des sous-titres '
                    'réellement synchronisés.',
                    style: TextStyle(
                        color: Palette.muted, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  _switch(
                    value: s.autoFetchSubtitles,
                    onChanged: (v) => library
                        .updateSettings((s) => s.autoFetchSubtitles = v),
                    title: 'Chercher automatiquement',
                    subtitle:
                        'Sinon, le bouton reste disponible dans les options du lecteur.',
                  ),
                  _field(
                    controller: _subKey,
                    label: 'Clé OpenSubtitles',
                    hint: 'opensubtitles.com — compte gratuit, section API',
                    obscure: true,
                    onSubmit: (v) =>
                        library.updateSettings((s) => s.subtitleKey = v),
                  ),
                  _field(
                    controller: _subUser,
                    label: 'Identifiant (facultatif)',
                    hint: 'Augmente le quota de téléchargement quotidien',
                    onSubmit: (v) =>
                        library.updateSettings((s) => s.subtitleUser = v),
                  ),
                  if (s.subtitleUser.trim().isNotEmpty)
                    _field(
                      controller: _subPass,
                      label: 'Mot de passe',
                      hint: 'Utilisé uniquement pour la connexion',
                      obscure: true,
                      onSubmit: (v) => library
                          .updateSettings((s) => s.subtitlePassword = v),
                    ),
                ],
              ),
              _card(
                icon: Icons.auto_awesome,
                title: 'Assistant IA',
                children: [
                  Text(
                    'Quand TMDB ne reconnaît pas un dossier, '
                    'l\'IA identifie la série et donne son titre en romaji, en anglais, '
                    'en français et en japonais.',
                    style: TextStyle(
                        color: Palette.muted, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  _switch(
                    value: s.aiEnabled,
                    onChanged: (v) =>
                        library.updateSettings((s) => s.aiEnabled = v),
                    title: 'Utiliser l\'IA en dernier recours',
                    subtitle:
                        'Uniquement quand la recherche classique échoue.',
                  ),
                  _dropdown<String>(
                    label: 'Fournisseur',
                    value: s.aiProvider,
                    items: const {
                      'groq': 'Groq — gratuit, sans carte bancaire',
                      'openrouter': 'OpenRouter',
                      'custom': 'Serveur compatible OpenAI',
                    },
                    onChanged: (v) {
                      library.updateSettings((s) => s.aiProvider = v);
                      setState(() => _models = []);
                    },
                  ),
                  if (s.aiProvider == 'custom')
                    _field(
                      controller: _aiEndpoint,
                      label: 'Adresse du serveur',
                      hint: 'https://mon-serveur/v1',
                      onSubmit: (v) =>
                          library.updateSettings((s) => s.aiEndpoint = v),
                    ),
                  _field(
                    controller: _aiKey,
                    label: 'Clé d\'API',
                    hint: s.aiProvider == 'groq'
                        ? 'console.groq.com — clé gratuite'
                        : 'Collée depuis ton compte',
                    obscure: true,
                    onSubmit: (v) => library.updateSettings((s) => s.aiKey = v),
                  ),
                  if (_models.isEmpty)
                    _field(
                      controller: _aiModel,
                      label: 'Modèle',
                      hint: 'llama-3.3-70b-versatile',
                      onSubmit: (v) =>
                          library.updateSettings((s) => s.aiModel = v),
                    )
                  else
                    _dropdown<String>(
                      label: 'Modèle',
                      value: _models.contains(s.aiModel)
                          ? s.aiModel
                          : _models.first,
                      items: {for (final m in _models) m: m},
                      onChanged: (v) {
                        _aiModel.text = v;
                        library.updateSettings((s) => s.aiModel = v);
                      },
                    ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _aiBusy ? null : _loadModels,
                        icon: const Icon(Icons.list_alt, size: 18),
                        label: const Text('Charger les modèles'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _aiBusy ? null : _testAi,
                        icon: const Icon(Icons.wifi_tethering, size: 18),
                        label: const Text('Tester la connexion'),
                      ),
                    ],
                  ),
                  if (_aiBusy)
                    Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: Palette.raised,
                          color: Palette.shu),
                    ),
                  _switch(
                    value: s.aiWebSearch,
                    onChanged: (v) =>
                        library.updateSettings((s) => s.aiWebSearch = v),
                    title: 'Autoriser la recherche web',
                    subtitle:
                        'Uniquement avec un modèle qui la prend en charge.',
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      AiService.supportsWeb(s.aiModel)
                          ? 'Ce modèle peut consulter le web : les nouveautés '
                              'et les sorties récentes lui sont accessibles.'
                          : 'Ce modèle ne consulte pas Internet : sa connaissance '
                              's\'arrête à son entraînement. Pour les nouveautés, '
                              'choisis « groq/compound » ou « groq/compound-mini ». '
                              'Les modèles « gpt-oss » consomment beaucoup de jetons ; '
                              '« llama-3.3-70b-versatile » répond plus directement.',
                      style: TextStyle(
                          color: AiService.supportsWeb(s.aiModel)
                              ? Palette.kin
                              : Palette.muted,
                          fontSize: 11.5,
                          height: 1.4),
                    ),
                  ),
                  if (_aiMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_aiMessage!,
                          style: TextStyle(
                              color: Palette.kin, fontSize: 12, height: 1.4)),
                    ),
                ],
              ),
              _card(
                icon: Icons.cloud_off_outlined,
                title: 'Hors connexion',
                children: [
                  _switch(
                    value: s.offlinePosters,
                    onChanged: (v) =>
                        library.updateSettings((s) => s.offlinePosters = v),
                    title: 'Enregistrer les affiches sur l\'appareil',
                    subtitle:
                        'La bibliothèque reste illustrée sans connexion.',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: library.busy ? null : _cachePosters,
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: const Text('Télécharger les affiches'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _clearPosters,
                        icon: const Icon(Icons.cleaning_services_outlined,
                            size: 18),
                        label: const Text('Vider le cache d\'affiches'),
                      ),
                    ],
                  ),
                ],
              ),
              _card(
                icon: Icons.network_check,
                title: 'Diagnostic',
                children: [
                  Text(
                    'Vérifie que l\'application atteint bien Internet et les deux bases de données. '
                    'À lancer si aucune image ni description n\'apparaît.',
                    style: TextStyle(
                        color: Palette.muted, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _diagBusy ? null : _runDiagnostic,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Tester la connexion'),
                  ),
                  if (_diagBusy)
                    Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: Palette.raised,
                          color: Palette.shu),
                    ),
                  for (final line in _diagnostic)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: SelectableText(
                        line,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: line.contains('OK') ? Palette.kin : Palette.shu,
                        ),
                      ),
                    ),
                ],
              ),
              _card(
                icon: Icons.save_outlined,
                title: 'Sauvegarde',
                children: [
                  Text(
                    'Un fichier unique contient les fiches, les favoris et la progression. '
                    'Les vidéos ne sont pas copiées.',
                    style: TextStyle(
                        color: Palette.muted, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _export,
                        icon: const Icon(Icons.upload_file, size: 18),
                        label: const Text('Exporter'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _import,
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('Restaurer'),
                      ),
                    ],
                  ),
                ],
              ),
              _card(
                icon: Icons.palette_outlined,
                title: 'Apparence',
                children: [
                  const Text('Thème',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final theme in appThemes) _themeTile(theme, s.themeId),
                  const SizedBox(height: 14),
                  _dropdown<String>(
                    label: 'Affichage de la collection',
                    value: s.viewMode,
                    items: const {
                      'grid': 'Grille d\'affiches',
                      'list': 'Liste compacte',
                      'genre': 'Rayons par genre',
                    },
                    onChanged: (v) =>
                        library.updateSettings((s) => s.viewMode = v),
                  ),
                ],
              ),
              _dangerZone(),
              const SizedBox(height: 20),
              Text(
                'Les vidéos restent sur ton disque : l\'application ne fait que les lister et les lire. '
                'Seuls les titres sont envoyés aux services de métadonnées et de traduction.',
                style: TextStyle(color: Palette.muted, fontSize: 12, height: 1.5),
              ),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------ blocs

  Widget _card({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Palette.surface,
        border: Border.all(color: Palette.line),
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 3, height: 15, color: Palette.shu),
              const SizedBox(width: 8),
              Icon(icon, size: 17, color: Palette.kin),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _dangerZone() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0x14BF2F25),
        border: Border.all(color: Palette.shu),
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 17, color: Palette.shu),
              SizedBox(width: 8),
              Text('Actions sensibles',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Palette.shu)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Ces actions effacent des données de l\'application. Tes fichiers vidéo ne sont jamais touchés.',
            style: TextStyle(color: Palette.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Palette.shu,
              side: BorderSide(color: Palette.shu),
            ),
            onPressed: library.busy ? null : _confirmClear,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('Vider la bibliothèque'),
          ),
        ],
      ),
    );
  }




  /// Une ligne par thème, avec sa bannière et ses trois couleurs clés.
  Widget _themeTile(AppTheme theme, String selectedId) {
    final selected = theme.id == selectedId;

    return GestureDetector(
      onTap: () async {
        await library.updateSettings((s) => s.themeId = theme.id);
        Palette.apply(theme.id);
        library.refresh();
        if (mounted) setState(() {});
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.surface,
          border: Border.all(
              color: selected ? theme.shu : theme.line,
              width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.ink,
                borderRadius: BorderRadius.circular(radiusSm),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                child: Image.asset(theme.logo, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final color in [theme.shu, theme.kin, theme.sakura])
                  Container(
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.line),
                    ),
                  ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(theme.name,
                          style: TextStyle(
                              color: theme.text,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700)),
                      Text(theme.description,
                          style: TextStyle(
                              color: theme.muted, fontSize: 11, height: 1.3)),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, color: theme.shu, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _relabel() async {
    final changed = await library.relabelAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(changed == 0
            ? 'Toutes les fiches sont déjà en français.'
            : '$changed fiche(s) mise(s) à jour.'),
      ),
    );
  }

  Future<void> _forgetTitles() async {
    library.knownTitles.clear();
    await library.save();
    library.refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Correspondances oubliées.')),
    );
  }

  Future<void> _runDiagnostic() async {
    setState(() {
      _diagBusy = true;
      _diagnostic = [];
    });
    final lines = await Diagnostics.run(library.settings.tmdbKey);
    lines.addAll(Diagnostics.lastErrors());
    if (!mounted) return;
    setState(() {
      _diagBusy = false;
      _diagnostic = lines;
    });
  }

  Future<void> _loadModels() async {
    setState(() {
      _aiBusy = true;
      _aiMessage = null;
    });
    final models = await AiService.listModels(
      provider: library.settings.aiProvider,
      apiKey: _aiKey.text.trim(),
      custom: _aiEndpoint.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _aiBusy = false;
      _models = models;
      _aiMessage = models.isEmpty
          ? 'Aucun modèle reçu. Vérifie la clé et la connexion.'
          : '${models.length} modèles disponibles.';
    });
  }

  Future<void> _testAi() async {
    setState(() {
      _aiBusy = true;
      _aiMessage = null;
    });
    final result = await AiService.test(
      provider: library.settings.aiProvider,
      apiKey: _aiKey.text.trim(),
      model: _aiModel.text.trim(),
      custom: _aiEndpoint.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _aiBusy = false;
      _aiMessage = result;
    });
  }

  Future<void> _cachePosters() async {
    final count = await library.cachePosters();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count affiche(s) enregistrée(s).')),
    );
  }

  Future<void> _clearPosters() async {
    final count = await PosterCache.clear();
    for (final a in library.items) {
      a.posterPath = null;
    }
    await library.save();
    library.refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count fichier(s) supprimé(s).')),
    );
  }

  Future<void> _export() async {
    final folder = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const FolderPickerScreen()),
    );
    if (folder == null) return;
    try {
      final path = await library.exportLibrary(folder);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sauvegarde écrite : $path')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Écriture impossible dans ce dossier.')),
      );
    }
  }

  Future<void> _import() async {
    final file = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const FolderPickerScreen(pickExtension: '.json'),
      ),
    );
    if (file == null || !mounted) return;

    final merge = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Restaurer cette sauvegarde ?'),
        content: const Text(
          'Fusionner conserve ta bibliothèque actuelle et y ajoute les fiches et la progression du fichier. '
          'Remplacer efface tout et repart de la sauvegarde.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Remplacer',
                  style: TextStyle(color: Palette.shu))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.shu),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Fusionner'),
          ),
        ],
      ),
    );
    if (merge == null) return;

    try {
      final count = await library.importLibrary(file, merge: merge);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count série(s) restaurée(s).')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fichier de sauvegarde illisible.')),
      );
    }
  }

  Future<void> _confirmRemoveFolder(String folder) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Retirer ce dossier ?'),
        content: Text(
          'Les séries de $folder disparaîtront de la bibliothèque. '
          'Aucun fichier vidéo n\'est supprimé du disque.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.shu),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (ok == true) await library.removeFolder(folder);
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Vider la bibliothèque ?'),
        content: const Text(
            'Les fiches, les favoris et la progression seront effacés. Tes fichiers vidéo ne sont pas touchés.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.shu),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Vider'),
          ),
        ],
      ),
    );
    if (ok == true) await library.clearLibrary();
  }

  Widget _switch({
    required bool value,
    required ValueChanged<bool> onChanged,
    required String title,
    required String subtitle,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(subtitle,
          style: TextStyle(color: Palette.muted, fontSize: 12)),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: fieldDecoration(labelText: label),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            dropdownColor: Palette.raised,
            style: TextStyle(color: Palette.text, fontSize: 14),
            items: items.entries
                .map((e) =>
                    DropdownMenuItem<T>(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required ValueChanged<String> onSubmit,
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        // On enregistre a la validation plutot qu'a chaque frappe.
        onEditingComplete: () => onSubmit(controller.text),
        onSubmitted: onSubmit,
        onTapOutside: (_) => onSubmit(controller.text),
        decoration: fieldDecoration(labelText: label, hintText: hint),
      ),
    );
  }
}
