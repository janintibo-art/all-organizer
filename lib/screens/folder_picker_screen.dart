import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';
import '../services/scanner.dart';

/// Explorateur de dossiers ecrit avec dart:io uniquement : aucun plugin natif,
/// donc le meme comportement sur Windows et sur Android.
class FolderPickerScreen extends StatefulWidget {
  final String? initialPath;

  /// Extension a selectionner (« .json »). Quand elle est fournie, l'ecran
  /// liste aussi les fichiers et renvoie celui qu'on touche.
  final String? pickExtension;

  const FolderPickerScreen({
    super.key,
    this.initialPath,
    this.pickExtension,
  });

  @override
  State<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends State<FolderPickerScreen> {
  String? _current;
  List<Directory> _children = [];
  List<File> _files = [];
  List<_Root> _roots = [];
  String? _error;
  bool _allFilesGranted = true;

  // Apercu du contenu du dossier courant.
  bool _previewing = false;
  int _previewSeries = 0;
  int _previewVideos = 0;

  @override
  void initState() {
    super.initState();
    _roots = _listRoots();
    _checkPermission();
    _addExternalVolumes();
    final start = widget.initialPath;
    if (start != null && Directory(start).existsSync()) _open(start);
  }

  Future<void> _checkPermission() async {
    if (!Platform.isAndroid) return;
    final granted = await Permission.manageExternalStorage.isGranted;
    if (!mounted) return;
    setState(() => _allFilesGranted = granted);
  }

  Future<void> _requestAllFiles() async {
    await Permission.manageExternalStorage.request();
    await _checkPermission();
    if (!mounted) return;
    setState(() => _roots = _listRoots());
    await _addExternalVolumes();
  }

  /// Sur Android 11+, lister /storage ne montre plus les cartes SD.
  /// Android accepte en revanche de donner les dossiers de l'application sur
  /// chaque volume monté : on remonte de là jusqu'à la racine du volume.
  Future<void> _addExternalVolumes() async {
    if (!Platform.isAndroid) return;
    try {
      final dirs = await getExternalStorageDirectories();
      if (dirs == null) return;
      final found = <_Root>[];
      for (final d in dirs) {
        final marker = d.path.indexOf('/Android/');
        if (marker <= 0) continue;
        final volume = d.path.substring(0, marker);
        if (volume.contains('/emulated/')) continue;
        if (_roots.any((r) => r.path == volume)) continue;
        if (found.any((r) => r.path == volume)) continue;
        found.add(_Root(
          volume,
          'Carte SD',
          icon: 'sd',
          subtitle: p.basename(volume),
          readable: _canList(volume),
        ));
      }
      if (found.isNotEmpty && mounted) {
        setState(() => _roots = [..._roots, ...found]);
      }
    } catch (_) {}
  }

  List<_Root> _listRoots() {
    final roots = <_Root>[];
    if (Platform.isAndroid) {
      for (final c in const [
        ['/storage/emulated/0', 'Mémoire interne', 'phone'],
        ['/storage/emulated/0/Download', 'Téléchargements', 'download'],
        ['/storage/emulated/0/Movies', 'Vidéos', 'movie'],
        ['/storage/emulated/0/DCIM', 'DCIM', 'camera'],
      ]) {
        if (Directory(c[0]).existsSync()) {
          roots.add(_Root(c[0], c[1], icon: c[2]));
        }
      }
      for (final base in const ['/storage', '/mnt/media_rw']) {
        try {
          for (final e in Directory(base).listSync()) {
            if (e is! Directory) continue;
            final name = p.basename(e.path);
            if (name == 'emulated' || name == 'self') continue;
            if (roots.any((r) => r.path == e.path)) continue;
            roots.add(_Root(
              e.path,
              name.contains('-') ? 'Carte SD' : 'Volume $name',
              icon: 'sd',
              subtitle: name,
              readable: _canList(e.path),
            ));
          }
        } catch (_) {}
      }
    } else if (Platform.isWindows) {
      for (var c = 'A'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++) {
        final drive = '${String.fromCharCode(c)}:\\';
        if (Directory(drive).existsSync()) {
          roots.add(_Root(drive, 'Disque ${String.fromCharCode(c)}',
              icon: 'disk'));
        }
      }
    } else {
      roots.add(_Root('/', 'Racine', icon: 'disk'));
      final home = Platform.environment['HOME'];
      if (home != null && Directory(home).existsSync()) {
        roots.add(_Root(home, 'Dossier personnel', icon: 'phone'));
      }
    }
    return roots;
  }

  bool _canList(String path) {
    try {
      Directory(path).listSync().take(1).toList();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _open(String path) {
    try {
      final dirs = Directory(path)
          .listSync(followLinks: false)
          .whereType<Directory>()
          .where((d) => !p.basename(d.path).startsWith('.'))
          .toList()
        ..sort((a, b) => p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase()));
      final ext = widget.pickExtension;
      final files = ext == null
          ? <File>[]
          : (Directory(path)
              .listSync(followLinks: false)
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith(ext.toLowerCase()))
              .toList()
            ..sort((a, b) => b.path.compareTo(a.path)));

      setState(() {
        _current = path;
        _children = dirs;
        _files = files;
        _error = null;
      });
    } catch (_) {
      setState(() {
        _current = path;
        _children = [];
        _files = [];
        _error = 'Dossier illisible. Vérifie les autorisations de stockage.';
      });
    }
    if (widget.pickExtension == null) _preview(path);
  }

  /// Compte ce que l'importation trouverait, avant de valider.
  Future<void> _preview(String path) async {
    setState(() {
      _previewing = true;
      _previewSeries = 0;
      _previewVideos = 0;
    });
    try {
      final found = await Scanner.scanFolders([path]);
      if (!mounted || _current != path) return;
      setState(() {
        _previewSeries = found.length;
        _previewVideos =
            found.fold<int>(0, (sum, a) => sum + a.episodes.length);
        _previewing = false;
      });
    } catch (_) {
      if (mounted) setState(() => _previewing = false);
    }
  }

  void _goUp() {
    final current = _current;
    if (current == null) return;
    final parent = p.dirname(current);
    if (parent == current || !Directory(parent).existsSync()) {
      setState(() => _current = null);
    } else {
      _open(parent);
    }
  }

  Future<void> _manualPath() async {
    final controller = TextEditingController(
      text: Platform.isAndroid ? '/storage/' : '',
    );
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Saisir un chemin'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: fieldDecoration(hintText: '/storage/1A2B-3C4D/Films'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Ouvrir'),
          ),
        ],
      ),
    );
    if (path != null && path.isNotEmpty) _open(path);
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;

    return Scaffold(
      appBar: darkAppBar(
        title: Text(widget.pickExtension == null
            ? 'Choisir un dossier'
            : 'Choisir un fichier'),
        actions: [
          IconButton(
            tooltip: 'Saisir un chemin',
            onPressed: _manualPath,
            icon: const Icon(Icons.keyboard),
          ),
          if (current != null)
            IconButton(
              tooltip: 'Dossier parent',
              onPressed: _goUp,
              icon: const Icon(Icons.arrow_upward),
            ),
        ],
      ),
      bottomNavigationBar: (current == null || widget.pickExtension != null)
          ? null
          : _selectionBar(current),
      body: current == null ? _rootList() : _folderList(current),
    );
  }

  // -------------------------------------------------------------- selection

  Widget _selectionBar(String current) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Palette.surface,
        border: Border(top: BorderSide(color: Palette.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dossier sélectionné',
            style: TextStyle(
                color: Palette.muted, fontSize: 10.5, letterSpacing: 0.8),
          ),
          const SizedBox(height: 3),
          Text(
            current,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _previewing
                    ? Text('Analyse en cours…',
                        style: TextStyle(color: Palette.muted, fontSize: 12))
                    : Text(
                        _previewVideos == 0
                            ? 'Aucune vidéo détectée ici'
                            : '$_previewSeries séries · $_previewVideos vidéos détectées',
                        style: TextStyle(
                          color: _previewVideos == 0
                              ? Palette.muted
                              : Palette.kin,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Palette.shu,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(radiusSm)),
                ),
                onPressed: () => Navigator.pop(context, current),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Importer'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ vues

  IconData _iconFor(String key) {
    switch (key) {
      case 'sd':
        return Icons.sd_card;
      case 'download':
        return Icons.download;
      case 'movie':
        return Icons.movie_creation_outlined;
      case 'camera':
        return Icons.photo_camera_outlined;
      case 'disk':
        return Icons.storage;
      default:
        return Icons.smartphone;
    }
  }

  Widget _rootList() {
    if (_roots.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Aucun emplacement accessible. Accorde l\'accès au stockage puis reviens ici.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Palette.muted),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (!_allFilesGranted) _permissionBanner(),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.5,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [for (final r in _roots) _storageCard(r)],
        ),
      ],
    );
  }

  Widget _storageCard(_Root r) {
    return InkWell(
      onTap: () => _open(r.path),
      borderRadius: BorderRadius.circular(radiusMd),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Palette.surface,
          border: Border.all(color: r.readable ? Palette.line : Palette.shu),
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(_iconFor(r.icon),
                color: r.readable ? Palette.kin : Palette.muted, size: 26),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  r.readable ? (r.subtitle ?? r.path) : 'Accès refusé',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: r.readable ? Palette.muted : Palette.shu,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _permissionBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Palette.raised,
        border: Border.all(color: Palette.shu),
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Accès à tous les fichiers désactivé',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 6),
          Text(
            'Sans cette autorisation, la carte SD et certains dossiers restent invisibles.',
            style: TextStyle(color: Palette.muted, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _requestAllFiles,
            style: FilledButton.styleFrom(
              backgroundColor: Palette.shu,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radiusSm)),
            ),
            child: const Text('Autoriser'),
          ),
        ],
      ),
    );
  }

  /// Fil d'Ariane : chaque segment ramene a son niveau.
  Widget _breadcrumb(String current) {
    final segments = p.split(current);
    final crumbs = <Widget>[];
    var built = '';

    crumbs.add(TextButton(
      onPressed: () => setState(() => _current = null),
      style: TextButton.styleFrom(
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 6)),
      child: Icon(Icons.home, size: 16, color: Palette.muted),
    ));

    for (var i = 0; i < segments.length; i++) {
      built = i == 0 ? segments[i] : p.join(built, segments[i]);
      final target = built;
      final last = i == segments.length - 1;
      crumbs.add(Text('/',
          style: TextStyle(color: Palette.line, fontSize: 12)));
      crumbs.add(TextButton(
        onPressed: last ? null : () => _open(target),
        style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 6)),
        child: Text(
          segments[i].replaceAll('\\', ''),
          style: TextStyle(
            fontSize: 12,
            color: last ? Palette.text : Palette.muted,
            fontWeight: last ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ));
    }

    return SizedBox(
      height: 36,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true, // le dossier courant reste visible
        child: Row(children: crumbs),
      ),
    );
  }

  Widget _folderList(String current) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: _breadcrumb(current),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(_error!,
                style: TextStyle(color: Palette.shu, fontSize: 13)),
          ),
        Expanded(
          child: _children.isEmpty && _files.isEmpty
              ? Center(
                  child: Text('Rien à afficher ici.',
                      style: TextStyle(color: Palette.muted)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _children.length + _files.length,
                  itemBuilder: (context, i) {
                    if (i < _children.length) {
                      final d = _children[i];
                      return ListTile(
                        leading: Icon(Icons.folder_outlined,
                            color: Palette.kin),
                        title: Text(p.basename(d.path),
                            style: const TextStyle(fontSize: 14)),
                        trailing: Icon(Icons.chevron_right,
                            color: Palette.muted, size: 20),
                        onTap: () => _open(d.path),
                      );
                    }
                    final f = _files[i - _children.length];
                    return ListTile(
                      leading: Icon(Icons.description_outlined,
                          color: Palette.shu),
                      title: Text(p.basename(f.path),
                          style: const TextStyle(fontSize: 13.5)),
                      subtitle: Text(
                        '${(f.lengthSync() / 1024).toStringAsFixed(0)} Ko',
                        style: TextStyle(
                            color: Palette.muted, fontSize: 11.5),
                      ),
                      onTap: () => Navigator.pop(context, f.path),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Root {
  final String path;
  final String label;
  final String icon;
  final String? subtitle;
  final bool readable;
  const _Root(this.path, this.label,
      {this.icon = 'phone', this.subtitle, this.readable = true});
}
