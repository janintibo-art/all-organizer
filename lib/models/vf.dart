/// Repérage d'une version française (doublage), d'après les conventions de
/// nommage des sorties françaises et les étiquettes de langue des pistes.
///
/// Les noms sont découpés en mots avant comparaison : « VOSTFR » et
/// « SUBFRENCH » forment un seul mot et ne sont donc jamais pris pour « FR »
/// ou « FRENCH ». C'est ce qui évite de confondre sous-titres et doublage.
class Vf {
  /// Mots qui annoncent une piste française dans un nom de vidéo.
  /// MULTi désigne, par convention, la VF accompagnée de la VO.
  static const Set<String> _marqueursVideo = {
    'VF', 'VFF', 'VFQ', 'VFI', 'VF2', 'VFB',
    'TRUEFRENCH', 'FRENCH', 'MULTI',
  };

  /// Pour une piste audio livrée à part, le simple code de langue suffit :
  /// « episode.fr.mka », « episode.fre.mka ».
  static const Set<String> _marqueursPiste = {
    ..._marqueursVideo, 'FR', 'FRA', 'FRE', 'FRANCAIS',
  };

  static Iterable<String> _mots(String texte) => texte
      .toUpperCase()
      .replaceAll(RegExp('[ÀÂÄ]'), 'A')
      .replaceAll(RegExp('[ÇĆ]'), 'C')
      .split(RegExp(r'[^A-Z0-9]+'))
      .where((m) => m.isNotEmpty);

  /// Le nom d'une vidéo, ou des dossiers qui la contiennent, annonce la VF.
  static bool inName(String texte) => _mots(texte).any(_marqueursVideo.contains);

  /// Le nom d'une piste audio séparée annonce une piste française.
  static bool inAudioFile(String chemin) =>
      _mots(_dernier(chemin)).any(_marqueursPiste.contains);

  /// Étiquette de langue d'une piste lue par le lecteur : « fre », « fra »,
  /// « fr », « fr-FR », « French », « Français »…
  static bool isFrench(String? langue) {
    if (langue == null) return false;
    final l = langue.trim().toLowerCase();
    if (l.isEmpty) return false;
    return l == 'fr' ||
        l == 'fre' ||
        l == 'fra' ||
        l.startsWith('fr-') ||
        l.startsWith('fr_') ||
        l.contains('french') ||
        l.contains('fran');
  }

  /// Les trois derniers éléments d'un chemin : le fichier et ses deux
  /// dossiers parents (« Série VF / Saison 1 / 01.mkv »). Plus haut, les
  /// noms décrivent le disque et plus la série.
  static String lastParts(String chemin) {
    final parts = chemin.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty);
    final liste = parts.toList();
    return liste.skip(liste.length > 3 ? liste.length - 3 : 0).join(' ');
  }

  static String _dernier(String chemin) {
    final parts = chemin.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? chemin : parts.last;
  }
}
