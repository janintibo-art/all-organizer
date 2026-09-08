/// Traduction des valeurs brutes renvoyées par les bases de données.
///
/// Chacune a son vocabulaire : « finished », « FINISHED », « Finished Airing »,
/// « current »… On ramène tout à une forme française unique, à l'enregistrement
/// comme à l'affichage, pour que les filtres regroupent correctement.
class Labels {
  static const Map<String, String> _status = {
    'finished': 'Terminé',
    'finished airing': 'Terminé',
    'complete': 'Terminé',
    'current': 'En cours',
    'releasing': 'En cours',
    'currently airing': 'En cours',
    'ongoing': 'En cours',
    'upcoming': 'À venir',
    'not_yet_released': 'À venir',
    'not yet released': 'À venir',
    'not yet aired': 'À venir',
    'tba': 'À venir',
    'unreleased': 'À venir',
    'cancelled': 'Annulé',
    'canceled': 'Annulé',
    'hiatus': 'En pause',
    'unknown': '',
  };

  static const Map<String, String> _format = {
    'tv': 'Série',
    'tv_short': 'Format court',
    'tv short': 'Format court',
    'movie': 'Film',
    'ova': 'OAV',
    'ona': 'ONA',
    'special': 'Épisode spécial',
    'music': 'Clip',
    'unknown': '',
  };

  static const Map<String, String> _genres = {
    'action': 'Action',
    'adventure': 'Aventure',
    'comedy': 'Comédie',
    'drama': 'Drame',
    'ecchi': 'Ecchi',
    'fantasy': 'Fantastique',
    'fantasy world': 'Monde fantastique',
    'horror': 'Horreur',
    'mahou shoujo': 'Magical girl',
    'magical girl': 'Magical girl',
    'mecha': 'Mecha',
    'music': 'Musique',
    'mystery': 'Mystère',
    'psychological': 'Psychologique',
    'romance': 'Romance',
    'sci-fi': 'Science-fiction',
    'science fiction': 'Science-fiction',
    'slice of life': 'Tranche de vie',
    'sports': 'Sport',
    'sport': 'Sport',
    'supernatural': 'Surnaturel',
    'thriller': 'Thriller',
    'school': 'École',
    'shounen': 'Shonen',
    'shoujo': 'Shojo',
    'seinen': 'Seinen',
    'josei': 'Josei',
    'kids': 'Jeunesse',
    'historical': 'Historique',
    'military': 'Militaire',
    'martial arts': 'Arts martiaux',
    'super power': 'Super-pouvoirs',
    'superhero': 'Super-héros',
    'super hero': 'Super-héros',
    'post apocalypse': 'Post-apocalyptique',
    'post-apocalyptic': 'Post-apocalyptique',
    'demons': 'Démons',
    'demon': 'Démons',
    'vampire': 'Vampires',
    'space': 'Espace',
    'cyberpunk': 'Cyberpunk',
    'isekai': 'Isekai',
    'harem': 'Harem',
    'parody': 'Parodie',
    'samurai': 'Samouraïs',
    'police': 'Policier',
    'detective': 'Policier',
    'survival': 'Survie',
    'food': 'Gastronomie',
    'gore': 'Gore',
    'iyashikei': 'Apaisant',
    'time travel': 'Voyage temporel',
    'work life': 'Monde du travail',
    'coming of age': 'Passage à l\'âge adulte',
    'anthropomorphic': 'Anthropomorphe',
    'android': 'Androïdes',
    'robots': 'Robots',
    'magic': 'Magie',
    'war': 'Guerre',
    'tragedy': 'Tragédie',
    'love triangle': 'Triangle amoureux',
    'friendship': 'Amitié',
    'family life': 'Vie de famille',
    'boys love': 'Boys love',
    'reincarnation': 'Réincarnation',
    'time manipulation': 'Voyage temporel',
    'revenge': 'Vengeance',
    'gods': 'Divinités',
    'zombie': 'Zombies',
    'ninja': 'Ninjas',
    'pirates': 'Pirates',
    'steampunk': 'Steampunk',
    'kaiju': 'Kaiju',
    'dragons': 'Dragons',
    'assassins': 'Assassins',
    'crime': 'Crime',
    'politics': 'Politique',
    'cooking': 'Cuisine',
    'idol': 'Idoles',
    'video games': 'Jeux vidéo',
    'mythology': 'Mythologie',
    'female protagonist': 'Héroïne',
    'male protagonist': 'Héros',
    'ensemble cast': 'Distribution chorale',
    'philosophy': 'Philosophie',
    'transforming craft': 'Machines transformables',
    'primarily female cast': 'Distribution féminine',
    'primarily male cast': 'Distribution masculine',
    'girls love': 'Girls love',
  };

  static String _clean(String value) =>
      value.trim().toLowerCase().replaceAll('_', ' ');

  /// Met la première lettre en majuscule, pour les valeurs inconnues.
  static String _capitalize(String value) {
    final v = value.trim();
    if (v.isEmpty) return v;
    return v[0].toUpperCase() + v.substring(1);
  }

  static String? status(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final mapped = _status[_clean(raw)];
    if (mapped == null) return _capitalize(raw);
    return mapped.isEmpty ? null : mapped;
  }

  static String? format(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final mapped = _format[_clean(raw)];
    if (mapped == null) return raw.toUpperCase();
    return mapped.isEmpty ? null : mapped;
  }

  static String genre(String raw) =>
      _genres[_clean(raw)] ?? _capitalize(raw);

  static List<String> genres(List<String> raw) {
    final out = <String>[];
    for (final g in raw) {
      final translated = genre(g);
      if (translated.isNotEmpty && !out.contains(translated)) {
        out.add(translated);
      }
    }
    return out;
  }
}
