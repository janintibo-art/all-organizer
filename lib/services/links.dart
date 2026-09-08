import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// Liens de recherche externes : moteurs, agrégateur légal et plateformes.
/// Rien n'est scrapé, on ouvre simplement une recherche dans le navigateur.
class WatchLink {
  final String label;
  final String url;
  const WatchLink(this.label, this.url);
}

class Links {
  static List<WatchLink> forTitle(String title, {int? year}) {
    final clean = title.trim();
    if (clean.isEmpty) return const [];

    final suffix = year == null ? '' : ' $year';
    final plain = Uri.encodeQueryComponent(clean);
    final web = Uri.encodeQueryComponent('$clean streaming vf vostfr');
    final trailer = Uri.encodeQueryComponent('$clean$suffix bande annonce');

    return [
      WatchLink('Google', 'https://www.google.com/search?q=$web'),
      WatchLink('DuckDuckGo', 'https://duckduckgo.com/?q=$web'),
      WatchLink('JustWatch', 'https://www.justwatch.com/fr/recherche?q=$plain'),
      WatchLink('Netflix', 'https://www.netflix.com/search?q=$plain'),
      WatchLink('Prime Video', 'https://www.primevideo.com/search/?phrase=$plain'),
      WatchLink('Allociné', 'https://www.allocine.fr/rechercher/?q=$plain'),
      WatchLink('TMDB', 'https://www.themoviedb.org/search?query=$plain'),
      WatchLink('Bande-annonce', 'https://www.youtube.com/results?search_query=$trailer'),
    ];
  }

  /// Ouvre le lien dans le navigateur. Renvoie false si l'appareil refuse,
  /// auquel cas l'appelant propose de copier l'adresse.
  static Future<bool> open(String url) async {
    try {
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return true;
    } catch (_) {}

    // Repli pour les postes de travail si le plugin ne prend pas la main.
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
        return true;
      }
      if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
        return true;
      }
    } catch (_) {}
    return false;
  }
}
