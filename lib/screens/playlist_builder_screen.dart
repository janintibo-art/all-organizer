import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../main.dart';
import '../services/music_scanner.dart';

/// Construction d'une liste en parcourant les disques.
///
/// C'est le mode d'emploi d'une collection mal étiquetée : on navigue dans
/// l'arborescence, on coche ce qu'on veut, dossier entier compris, et la
/// sélection survit aux allers-retours entre les dossiers.
class PlaylistBuilderScreen extends StatefulWidget {
  const PlaylistBuilderScreen({super.key});

  @override
  State<PlaylistBuilderScreen> createState() => _PlaylistBuilderScreenState();
}

class _PlaylistBuilderScreenState extends State<PlaylistBuilderScreen> {
  String? _courant;
  List<Directory> _dossiers = [];
  List<File> _fichiers = [];
  List<_Racine> _racines = [];
  String? _erreur;
  bool _occupe = false;

  /// La sélection est globale : elle traverse toute la navigation.
  final Set<String> _selection = {};

  @override
  void initState() {
    super.initState();
    _racines = _listerRacines();
  }

  List<_Racine> _listerRacines() {
    final racines = <_Racine>[];
    if (Platform.isAndroid) {
      for (final c in const [
        ['/storage/emulated/0', 'Mémoire interne'],
        ['/storage/emulated/0/Music', 'Musique'],
        ['/storage/emulated/0/Download', 'Téléchargements'],
      ]) {
        if (Directory(c[0]).existsSync()) racines.add(_Racine(c[0], c[1]));
      }
      for (final base in const ['/storage', '/mnt/media_rw']) {
        try {
          for (final e in Directory(base).listSync()) {
            if (e is! Directory) continue;
            final nom = p.basename(e.path);
            if (nom == 'emulated' || nom == 'self') continue;
            if (racines.any((r) => r.chemin == e.path)) continue;
            racines.add(_Racine(e.path, 'Carte SD ($nom)'));
          }
        } catch (_) {}
      }
    } else if (Platform.isWindows) {
      for (var c = 'A'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++) {
        final lecteur = '${String.fromCharCode(c)}:\\';
        if (Directory(lecteur).existsSync()) {
          racines.add(_Racine(lecteur, 'Disque ${String.fromCharCode(c)}'));
        }
      }
    } else {
      racines.add(_Racine('/', 'Racine'));
    }

    // Les dossiers déjà suivis sont les plus utiles : ils passent devant.
    for (final f in <String>[]) {
      racines.insert(0, _Racine(f, p.basename(f)));
    }
    return racines;
  }

  void _ouvrir(String chemin) {
    try {
      final entrees = Directory(chemin).listSync(followLinks: false);
      final dossiers = entrees
          .whereType<Directory>()
          .where((d) => !p.basename(d.path).startsWith('.'))
          .toList()
        ..sort((a, b) => p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase()));

      final fichiers = entrees
          .whereType<File>()
          .where((f) => MusicScanner.audioExtensions
              .contains(p.extension(f.path).toLowerCase()))
          .toList()
        ..sort((a, b) => p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase()));

      setState(() {
        _courant = chemin;
        _dossiers = dossiers;
        _fichiers = fichiers;
        _erreur = null;
      });
    } catch (_) {
      setState(() {
        _courant = chemin;
        _dossiers = [];
        _fichiers = [];
        _erreur = 'Dossier illisible. Vérifie les autorisations.';
      });
    }
  }

  void _remonter() {
    final courant = _courant;
    if (courant == null) return;
    final parent = p.dirname(courant);
    if (parent == courant || !Directory(parent).existsSync()) {
      setState(() => _courant = null);
    } else {
      _ouvrir(parent);
    }
  }

  /// Ajoute tout le contenu audio d'un dossier, sous-dossiers compris.
  Future<void> _ajouterDossier(String chemin) async {
    setState(() => _occupe = true);
    final trouves = <String>[];
    try {
      await for (final e in Directory(chemin)
          .list(recursive: true, followLinks: false)
          .handleError((dynamic _) {},
              test: (dynamic e) => e is FileSystemException)) {
        if (e is! File) continue;
        if (MusicScanner.audioExtensions
            .contains(p.extension(e.path).toLowerCase())) {
          trouves.add(e.path);
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _selection.addAll(trouves);
      _occupe = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${trouves.length} morceau(x) ajouté(s).')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final courant = _courant;

    return Scaffold(
      appBar: darkAppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(courant == null
                ? 'Choisir un emplacement'
                : p.basename(courant)),
            Text('${_selection.length} morceau(x) sélectionné(s)',
                style: TextStyle(
                    color: _selection.isEmpty ? Palette.muted : Palette.kin,
                    fontSize: 10.5)),
          ],
        ),
        actions: [
          if (courant != null)
            IconButton(
              tooltip: 'Dossier parent',
              onPressed: _remonter,
              icon: const Icon(Icons.arrow_upward),
            ),
        ],
      ),
      bottomNavigationBar: _selection.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: Palette.surface,
                border: Border(top: BorderSide(color: Palette.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                        '${_selection.length} morceau(x) retenu(s)',
                        style: TextStyle(
                            color: Palette.text, fontSize: 13)),
                  ),
                  TextButton(
                    onPressed: () => setState(_selection.clear),
                    child: Text('Vider',
                        style: TextStyle(color: Palette.muted)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Palette.shu,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(radiusSm)),
                    ),
                    onPressed: () =>
                        Navigator.pop(context, _selection.toList()),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Valider'),
                  ),
                ],
              ),
            ),
      body: Column(
        children: [
          if (_occupe)
            LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: Palette.raised,
                color: Palette.shu),
          if (_erreur != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_erreur!,
                  style: TextStyle(color: Palette.shu, fontSize: 13)),
            ),
          Expanded(
            child: courant == null ? _listeRacines() : _listeContenu(courant),
          ),
        ],
      ),
    );
  }

  Widget _listeRacines() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final r in _racines)
          ListTile(
            leading: Icon(Icons.storage, color: Palette.kin),
            title: Text(r.nom, style: TextStyle(color: Palette.text)),
            subtitle: Text(r.chemin,
                style: TextStyle(color: Palette.muted, fontSize: 11.5)),
            onTap: () => _ouvrir(r.chemin),
          ),
      ],
    );
  }

  Widget _listeContenu(String courant) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _dossiers.length + _fichiers.length + 1,
      itemBuilder: (context, i) {
        // Première ligne : ajouter tout le dossier d'un geste.
        if (i == 0) {
          return ListTile(
            leading: Icon(Icons.playlist_add, color: Palette.shu),
            title: Text('Ajouter tout ce dossier',
                style: TextStyle(
                    color: Palette.shu, fontWeight: FontWeight.w600)),
            subtitle: Text('Sous-dossiers compris',
                style: TextStyle(color: Palette.muted, fontSize: 11.5)),
            onTap: _occupe ? null : () => _ajouterDossier(courant),
          );
        }

        final index = i - 1;
        if (index < _dossiers.length) {
          final d = _dossiers[index];
          return ListTile(
            leading: Icon(Icons.folder_outlined, color: Palette.kin),
            title: Text(p.basename(d.path),
                style: TextStyle(color: Palette.text, fontSize: 14)),
            trailing:
                Icon(Icons.chevron_right, color: Palette.muted, size: 20),
            onTap: () => _ouvrir(d.path),
          );
        }

        final f = _fichiers[index - _dossiers.length];
        final choisi = _selection.contains(f.path);
        return ListTile(
          dense: true,
          leading: Icon(
            choisi ? Icons.check_circle : Icons.music_note,
            color: choisi ? Palette.shu : Palette.muted,
          ),
          title: Text(p.basenameWithoutExtension(f.path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: choisi ? Palette.shu : Palette.text, fontSize: 13.5)),
          subtitle: Text(
              '${(f.lengthSync() / 1000000).toStringAsFixed(1)} Mo',
              style: TextStyle(color: Palette.muted, fontSize: 11)),
          onTap: () => setState(() =>
              choisi ? _selection.remove(f.path) : _selection.add(f.path)),
        );
      },
    );
  }
}

class _Racine {
  final String chemin;
  final String nom;
  const _Racine(this.chemin, this.nom);
}
