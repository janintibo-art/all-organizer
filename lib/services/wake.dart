import 'dart:async';

import 'package:http/http.dart' as http;

import '../models/server_profile.dart';
import 'http_client.dart';
import 'server_api.dart';

/// Réveil du PC par une adresse HTTP libre.
///
/// On n'impose aucun format : Tasmota, ESPHome ou un montage Arduino
/// n'exposent pas la même adresse, et coder en dur celle d'un appareil
/// précis aurait limité le choix du matériel.
class Wake {
  static String? lastError;

  /// Appelle l'adresse de réveil. Un module qui répond mal n'est pas
  /// forcément en panne : beaucoup renvoient une page vide ou un code
  /// inattendu tout en ayant bien fermé le contact.
  static Future<bool> trigger(ServerProfile s) async {
    lastError = null;
    final url = s.wakeUrl.trim();
    if (url.isEmpty) {
      lastError = 'Aucune adresse de réveil enregistrée.';
      return false;
    }
    try {
      final res = await http
          .get(Uri.parse(url), headers: AppHttp.headers())
          .timeout(const Duration(seconds: 12));
      if (res.statusCode >= 500) {
        lastError = 'Le module a répondu HTTP ${res.statusCode}.';
        return false;
      }
      return true;
    } catch (e) {
      lastError = e.toString().contains('SocketException')
          ? 'Module de réveil injoignable. Vérifie son adresse et qu\'il est '
              'bien alimenté.'
          : e.toString();
      return false;
    }
  }

  /// Réveille puis attend que le serveur réponde, en réessayant.
  ///
  /// Un PC met une bonne minute à démarrer et à ouvrir sa session : on
  /// interroge donc régulièrement plutôt que d'attendre une durée fixe.
  static Future<bool> wakeAndWait(
    ServerProfile s, {
    void Function(String message)? onProgress,
  }) async {
    onProgress?.call('Envoi du signal de réveil…');
    if (!await trigger(s)) return false;

    final limite = DateTime.now().add(Duration(seconds: s.wakeWaitSeconds));
    var essai = 0;

    while (DateTime.now().isBefore(limite)) {
      essai++;
      final restant = limite.difference(DateTime.now()).inSeconds;
      onProgress?.call('Attente du serveur… ${restant}s (essai $essai)');
      await Future<void>.delayed(const Duration(seconds: 5));

      final reponse = await ServerApi.ping(s,
          timeout: const Duration(seconds: 4));
      if (reponse != null) {
        onProgress?.call('Serveur en ligne.');
        return true;
      }
    }

    lastError = 'Le serveur n\'a pas répondu dans le délai. Le PC met '
        'peut-être plus de temps à démarrer : augmente le délai d\'attente.';
    return false;
  }
}
