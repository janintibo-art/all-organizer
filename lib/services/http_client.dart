/// En-têtes communs à toutes les requêtes.
///
/// Le client HTTP de Dart s'annonce par défaut comme « Dart/3.x (dart:io) ».
/// Certains services derrière Cloudflare traitent ce genre de signature
/// comme du trafic automatisé et répond 403. On se présente donc comme une
/// application identifiable, avec un contact, ce que demandent la plupart
/// des API publiques.
class AppHttp {
  /// Uniquement de l'ASCII : un en-tete HTTP n'accepte rien d'autre,
  /// un simple accent fait echouer la requete avant l'envoi.
  static const String userAgent =
      'MediaOrganizer/1.0 (personal media library; Flutter)';

  static Map<String, String> headers({
    String accept = 'application/json',
    bool json = false,
  }) {
    return {
      'User-Agent': userAgent,
      'Accept': accept,
      if (json) 'Content-Type': 'application/json',
    };
  }
}
