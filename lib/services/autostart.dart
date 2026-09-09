import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Inscription de l'application au demarrage de Windows.
///
/// Deux mecanismes, parce qu'ils ne repondent pas au meme besoin :
///
/// - le dossier Demarrage ne s'execute qu'**apres ouverture de session**.
///   Au reveil depuis la veille la session est deja ouverte, donc ca suffit ;
/// - la tache planifiee, elle, part au demarrage de Windows meme si personne
///   ne s'est connecte. C'est ce qu'il faut apres un arret complet, quand on
///   reveille le PC depuis le telephone. Elle exige les droits administrateur.
class Autostart {
  static const String _nomTache = 'MediaOrganizerServeur';

  static String? lastError;

  static bool get supported => !kIsWeb && Platform.isWindows;

  /// Fichier depose dans le dossier Demarrage de l'utilisateur.
  static File? _raccourci() {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return null;
    return File(p.join(appData, 'Microsoft', 'Windows', 'Start Menu',
        'Programs', 'Startup', 'MediaOrganizer.bat'));
  }

  static bool get installedForSession {
    if (!supported) return false;
    final f = _raccourci();
    return f != null && f.existsSync();
  }

  /// Inscrit l'application pour la session courante. Sans droits
  /// particuliers, mais ne part qu'une fois l'utilisateur connecte.
  static Future<bool> enableForSession() async {
    lastError = null;
    if (!supported) {
      lastError = 'Disponible seulement sous Windows.';
      return false;
    }
    final fichier = _raccourci();
    if (fichier == null) {
      lastError = 'Dossier Démarrage introuvable.';
      return false;
    }
    try {
      await fichier.parent.create(recursive: true);
      await fichier.writeAsString(
        '@echo off\r\n'
        'start "" /min "${Platform.resolvedExecutable}" --serveur\r\n',
        flush: true,
      );
      return true;
    } catch (e) {
      lastError = '$e';
      return false;
    }
  }

  static Future<void> disableForSession() async {
    final fichier = _raccourci();
    if (fichier != null && fichier.existsSync()) {
      try {
        await fichier.delete();
      } catch (e) {
        lastError = '$e';
      }
    }
  }

  /// Tache planifiee qui part au demarrage de Windows, session ouverte ou
  /// non. Renvoie faux si Windows refuse — le plus souvent faute de droits.
  static Future<bool> enableAtBoot() async {
    lastError = null;
    if (!supported) {
      lastError = 'Disponible seulement sous Windows.';
      return false;
    }
    try {
      final res = await Process.run('schtasks', [
        '/Create',
        '/F',
        '/SC',
        'ONSTART',
        '/RL',
        'HIGHEST',
        '/RU',
        'SYSTEM',
        '/TN',
        _nomTache,
        '/TR',
        '"${Platform.resolvedExecutable}" --serveur',
      ]);
      if (res.exitCode != 0) {
        lastError = _lisible(res);
        return false;
      }
      return true;
    } catch (e) {
      lastError = '$e';
      return false;
    }
  }

  static Future<void> disableAtBoot() async {
    if (!supported) return;
    try {
      await Process.run('schtasks', ['/Delete', '/F', '/TN', _nomTache]);
    } catch (e) {
      lastError = '$e';
    }
  }

  static Future<bool> installedAtBoot() async {
    if (!supported) return false;
    try {
      final res = await Process.run('schtasks', ['/Query', '/TN', _nomTache]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static String _lisible(ProcessResult res) {
    final sortie = '${res.stderr}'.trim().isEmpty
        ? '${res.stdout}'.trim()
        : '${res.stderr}'.trim();
    if (sortie.isEmpty) return 'schtasks a refusé (code ${res.exitCode}).';
    return sortie;
  }
}
