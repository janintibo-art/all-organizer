import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Étiquettes lues directement dans le fichier audio.
class AudioTags {
  final String? title;
  final String? artist;
  final String? albumArtist;
  final String? album;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final String? genre;
  final Duration? duration;

  /// Pochette intégrée au fichier, telle quelle.
  final Uint8List? artwork;

  const AudioTags({
    this.title,
    this.artist,
    this.albumArtist,
    this.album,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.genre,
    this.duration,
    this.artwork,
  });

  bool get isEmpty =>
      title == null && artist == null && album == null && artwork == null;
}

/// Lecture des étiquettes sans aucun module natif.
///
/// C'est délibéré : les modules de lecture d'étiquettes sont une source
/// classique d'échec de compilation, et le format des fichiers audio est
/// suffisamment documenté pour être lu directement. Trois familles sont
/// couvertes : ID3v2 pour le MP3, les commentaires Vorbis pour le FLAC et
/// l'OGG, et les atomes pour le M4A.
class TagReader {
  /// On ne lit que le début et la fin du fichier : les étiquettes s'y
  /// trouvent toujours, inutile de charger un album entier en mémoire.
  static const int _teteMax = 2 * 1024 * 1024;

  /// Ne lit que la pochette. Appelée une fois par album plutôt que pour
  /// chaque morceau.
  static Future<Uint8List?> readArtwork(String path) async {
    final tags = await read(path);
    return tags.artwork;
  }

  static Future<AudioTags> read(String path) async {
    try {
      final data = await _lireTete(path, _teteMax);
      return readBytes(data, path.toLowerCase().split('.').last);
    } catch (_) {
      return const AudioTags();
    }
  }

  /// Même analyse, à partir d'octets déjà en mémoire.
  ///
  /// C'est ce qui permet de lire les étiquettes d'un fichier distant : on
  /// récupère seulement son début par une requête partielle, et on l'analyse
  /// ici sans jamais l'écrire sur le disque.
  static AudioTags readBytes(Uint8List data, String extension) {
    try {
      switch (extension) {
        case 'mp3':
          return _mp3(data);
        case 'flac':
          return _flac(data);
        case 'ogg':
        case 'opus':
          return _ogg(data);
        case 'm4a':
        case 'mp4':
        case 'aac':
          return _m4a(data);
        default:
          return const AudioTags();
      }
    } catch (_) {
      return const AudioTags();
    }
  }

  static Future<Uint8List> _lireTete(String path, int taille) async {
    final file = await File(path).open();
    try {
      final bytes = await file.read(taille);
      return Uint8List.fromList(bytes);
    } finally {
      await file.close();
    }
  }

  // ------------------------------------------------------------------ MP3

  /// ID3v2 : un en-tête de dix octets, puis des trames « nom + taille ».
  static AudioTags _mp3(Uint8List data) {
    if (data.length < 10) return const AudioTags();
    if (data[0] != 0x49 || data[1] != 0x44 || data[2] != 0x33) {
      return const AudioTags(); // pas d'ID3v2
    }

    final version = data[3];
    // La taille est codée sur sept bits par octet, pour ne jamais
    // ressembler à un début de trame audio.
    final taille = ((data[6] & 0x7F) << 21) |
        ((data[7] & 0x7F) << 14) |
        ((data[8] & 0x7F) << 7) |
        (data[9] & 0x7F);

    var position = 10;
    final fin = (10 + taille).clamp(0, data.length);

    String? titre, artiste, artisteAlbum, album, genre;
    int? piste, disque, annee;
    Uint8List? pochette;

    final tailleNom = version >= 3 ? 4 : 3;
    final tailleTrame = version >= 3 ? 4 : 3;

    while (position + tailleNom + tailleTrame < fin) {
      final nom = String.fromCharCodes(
          data.sublist(position, position + tailleNom));
      if (nom.trim().isEmpty || nom.codeUnitAt(0) == 0) break;

      int longueur;
      if (version == 4) {
        // ID3v2.4 code aussi les tailles de trames sur sept bits.
        longueur = ((data[position + 4] & 0x7F) << 21) |
            ((data[position + 5] & 0x7F) << 14) |
            ((data[position + 6] & 0x7F) << 7) |
            (data[position + 7] & 0x7F);
      } else if (version == 3) {
        longueur = (data[position + 4] << 24) |
            (data[position + 5] << 16) |
            (data[position + 6] << 8) |
            data[position + 7];
      } else {
        longueur = (data[position + 3] << 16) |
            (data[position + 4] << 8) |
            data[position + 5];
      }

      final entete = version >= 3 ? 10 : 6;
      final debut = position + entete;
      final finTrame = debut + longueur;
      if (longueur <= 0 || finTrame > data.length) break;

      final contenu = data.sublist(debut, finTrame);

      switch (nom) {
        case 'TIT2':
        case 'TT2':
          titre = _texteId3(contenu);
          break;
        case 'TPE1':
        case 'TP1':
          artiste = _texteId3(contenu);
          break;
        case 'TPE2':
        case 'TP2':
          artisteAlbum = _texteId3(contenu);
          break;
        case 'TALB':
        case 'TAL':
          album = _texteId3(contenu);
          break;
        case 'TCON':
        case 'TCO':
          genre = _nettoyerGenre(_texteId3(contenu));
          break;
        case 'TRCK':
        case 'TRK':
          piste = _premierNombre(_texteId3(contenu));
          break;
        case 'TPOS':
        case 'TPA':
          disque = _premierNombre(_texteId3(contenu));
          break;
        case 'TYER':
        case 'TYE':
        case 'TDRC':
          annee = _premierNombre(_texteId3(contenu));
          break;
        case 'APIC':
        case 'PIC':
          pochette ??= _imageId3(contenu, version);
          break;
      }

      position = finTrame;
    }

    return AudioTags(
      title: titre,
      artist: artiste,
      albumArtist: artisteAlbum,
      album: album,
      trackNumber: piste,
      discNumber: disque,
      year: annee,
      genre: genre,
      artwork: pochette,
    );
  }

  /// Le premier octet indique l'encodage du texte qui suit.
  static String? _texteId3(Uint8List contenu) {
    if (contenu.isEmpty) return null;
    final encodage = contenu[0];
    final corps = contenu.sublist(1);
    try {
      String texte;
      switch (encodage) {
        case 0: // Latin-1
          texte = latin1.decode(corps, allowInvalid: true);
          break;
        case 1: // UTF-16 avec marque d'ordre
          texte = _utf16(corps);
          break;
        case 2: // UTF-16 gros-boutiste sans marque
          texte = _utf16(corps, grosBoutiste: true);
          break;
        default: // UTF-8
          texte = utf8.decode(corps, allowMalformed: true);
      }
      return _nettoyer(texte);
    } catch (_) {
      return null;
    }
  }

  static String _utf16(Uint8List octets, {bool grosBoutiste = false}) {
    var debut = 0;
    var gros = grosBoutiste;
    if (octets.length >= 2) {
      if (octets[0] == 0xFF && octets[1] == 0xFE) {
        gros = false;
        debut = 2;
      } else if (octets[0] == 0xFE && octets[1] == 0xFF) {
        gros = true;
        debut = 2;
      }
    }
    final unites = <int>[];
    for (var i = debut; i + 1 < octets.length; i += 2) {
      unites.add(gros
          ? (octets[i] << 8) | octets[i + 1]
          : (octets[i + 1] << 8) | octets[i]);
    }
    return String.fromCharCodes(unites);
  }

  /// Une trame APIC contient l'encodage, le type MIME, un octet de rôle,
  /// une description, puis l'image elle-même.
  static Uint8List? _imageId3(Uint8List contenu, int version) {
    if (contenu.length < 4) return null;
    var i = 1; // encodage

    if (version >= 3) {
      while (i < contenu.length && contenu[i] != 0) {
        i++;
      }
      i++; // fin du type MIME
    } else {
      i += 3; // ID3v2.2 : type sur trois lettres
    }
    if (i >= contenu.length) return null;

    i++; // rôle de l'image
    while (i < contenu.length && contenu[i] != 0) {
      i++;
    }
    i++; // fin de la description

    if (i >= contenu.length) return null;
    final image = contenu.sublist(i);
    return image.length > 512 ? image : null;
  }

  // ----------------------------------------------------------------- FLAC

  /// FLAC : une suite de blocs, dont les commentaires Vorbis et l'image.
  static AudioTags _flac(Uint8List data) {
    if (data.length < 8) return const AudioTags();
    if (String.fromCharCodes(data.sublist(0, 4)) != 'fLaC') {
      return const AudioTags();
    }

    var position = 4;
    final champs = <String, String>{};
    Uint8List? pochette;
    Duration? duree;

    while (position + 4 < data.length) {
      final dernier = (data[position] & 0x80) != 0;
      final type = data[position] & 0x7F;
      final longueur = (data[position + 1] << 16) |
          (data[position + 2] << 8) |
          data[position + 3];
      final debut = position + 4;
      if (debut + longueur > data.length) break;

      if (type == 0 && longueur >= 18) {
        // STREAMINFO : la durée se calcule en échantillons.
        final bloc = data.sublist(debut, debut + 18);
        final frequence = (bloc[10] << 12) | (bloc[11] << 4) | (bloc[12] >> 4);
        final echantillons = ((bloc[13] & 0x0F) << 32) |
            (bloc[14] << 24) |
            (bloc[15] << 16) |
            (bloc[16] << 8) |
            bloc[17];
        if (frequence > 0) {
          duree = Duration(seconds: echantillons ~/ frequence);
        }
      } else if (type == 4) {
        champs.addAll(_vorbis(data.sublist(debut, debut + longueur)));
      } else if (type == 6) {
        pochette ??= _imageFlac(data.sublist(debut, debut + longueur));
      }

      position = debut + longueur;
      if (dernier) break;
    }

    return _depuisVorbis(champs, pochette, duree);
  }

  /// Bloc PICTURE du FLAC : type, MIME, description, dimensions, image.
  static Uint8List? _imageFlac(Uint8List bloc) {
    try {
      var i = 4; // type
      final tailleMime = _u32(bloc, i);
      i += 4 + tailleMime;
      final tailleDesc = _u32(bloc, i);
      i += 4 + tailleDesc;
      i += 16; // largeur, hauteur, profondeur, couleurs
      final tailleImage = _u32(bloc, i);
      i += 4;
      if (i + tailleImage > bloc.length || tailleImage < 512) return null;
      return bloc.sublist(i, i + tailleImage);
    } catch (_) {
      return null;
    }
  }

  static int _u32(Uint8List b, int i) =>
      (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];

  static int _u32le(Uint8List b, int i) =>
      b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);

  /// Commentaires Vorbis : « CLÉ=valeur », tailles en petit-boutiste.
  static Map<String, String> _vorbis(Uint8List bloc) {
    final champs = <String, String>{};
    try {
      var i = 0;
      final tailleEditeur = _u32le(bloc, i);
      i += 4 + tailleEditeur;
      final nombre = _u32le(bloc, i);
      i += 4;

      for (var n = 0; n < nombre && i + 4 <= bloc.length; n++) {
        final longueur = _u32le(bloc, i);
        i += 4;
        if (i + longueur > bloc.length) break;
        final entree = utf8.decode(bloc.sublist(i, i + longueur),
            allowMalformed: true);
        i += longueur;
        final egal = entree.indexOf('=');
        if (egal <= 0) continue;
        champs[entree.substring(0, egal).toUpperCase()] =
            entree.substring(egal + 1);
      }
    } catch (_) {}
    return champs;
  }

  static AudioTags _depuisVorbis(
    Map<String, String> champs,
    Uint8List? pochette,
    Duration? duree,
  ) {
    return AudioTags(
      title: _nettoyer(champs['TITLE']),
      artist: _nettoyer(champs['ARTIST']),
      albumArtist: _nettoyer(champs['ALBUMARTIST'] ?? champs['ALBUM ARTIST']),
      album: _nettoyer(champs['ALBUM']),
      trackNumber: _premierNombre(champs['TRACKNUMBER']),
      discNumber: _premierNombre(champs['DISCNUMBER']),
      year: _premierNombre(champs['DATE'] ?? champs['YEAR']),
      genre: _nettoyer(champs['GENRE']),
      duration: duree,
      artwork: pochette,
    );
  }

  // ------------------------------------------------------------------ OGG

  /// Les commentaires Vorbis d'un OGG sont dans le deuxième paquet.
  static AudioTags _ogg(Uint8List data) {
    final marqueur = utf8.encode('vorbis');
    for (var i = 0; i + 7 < data.length && i < 200000; i++) {
      if (data[i] != 3) continue;
      var trouve = true;
      for (var k = 0; k < 6; k++) {
        if (data[i + 1 + k] != marqueur[k]) {
          trouve = false;
          break;
        }
      }
      if (!trouve) continue;
      final champs = _vorbis(data.sublist(i + 7));
      if (champs.isNotEmpty) return _depuisVorbis(champs, null, null);
    }

    // Opus utilise le même format, avec un autre marqueur.
    final opus = utf8.encode('OpusTags');
    for (var i = 0; i + 8 < data.length && i < 200000; i++) {
      var trouve = true;
      for (var k = 0; k < 8; k++) {
        if (data[i + k] != opus[k]) {
          trouve = false;
          break;
        }
      }
      if (!trouve) continue;
      final champs = _vorbis(data.sublist(i + 8));
      if (champs.isNotEmpty) return _depuisVorbis(champs, null, null);
    }

    return const AudioTags();
  }

  // ------------------------------------------------------------------ M4A

  /// M4A : des atomes imbriqués, les étiquettes sont dans moov/udta/meta/ilst.
  static AudioTags _m4a(Uint8List data) {
    final ilst = _trouverAtome(data, 'ilst', 0, data.length);
    if (ilst == null) return const AudioTags();

    String? titre, artiste, artisteAlbum, album, genre;
    int? piste, disque, annee;
    Uint8List? pochette;

    var i = ilst[0];
    final fin = ilst[1];

    while (i + 8 <= fin) {
      final taille = _u32(data, i);
      if (taille < 8 || i + taille > fin) break;
      final nom = String.fromCharCodes(data.sublist(i + 4, i + 8));

      // Chaque étiquette contient un sous-atome « data ».
      final valeur = _donneeAtome(data, i + 8, i + taille);
      if (valeur != null) {
        final texte = utf8.decode(valeur, allowMalformed: true).trim();
        switch (nom) {
          case '\u00a9nam':
            titre = _nettoyer(texte);
            break;
          case '\u00a9ART':
            artiste = _nettoyer(texte);
            break;
          case 'aART':
            artisteAlbum = _nettoyer(texte);
            break;
          case '\u00a9alb':
            album = _nettoyer(texte);
            break;
          case '\u00a9gen':
            genre = _nettoyer(texte);
            break;
          case '\u00a9day':
            annee = _premierNombre(texte);
            break;
          case 'trkn':
            if (valeur.length >= 4) piste = (valeur[2] << 8) | valeur[3];
            break;
          case 'disk':
            if (valeur.length >= 4) disque = (valeur[2] << 8) | valeur[3];
            break;
          case 'covr':
            if (valeur.length > 512) pochette = valeur;
            break;
        }
      }
      i += taille;
    }

    return AudioTags(
      title: titre,
      artist: artiste,
      albumArtist: artisteAlbum,
      album: album,
      trackNumber: piste,
      discNumber: disque,
      year: annee,
      genre: genre,
      artwork: pochette,
    );
  }

  /// Cherche un atome par son nom, en descendant dans les conteneurs.
  static List<int>? _trouverAtome(
      Uint8List data, String cible, int debut, int fin) {
    const conteneurs = {'moov', 'udta', 'meta', 'ilst', 'trak', 'mdia'};
    var i = debut;
    while (i + 8 <= fin) {
      var taille = _u32(data, i);
      final nom = String.fromCharCodes(data.sublist(i + 4, i + 8));
      if (taille == 0) taille = fin - i;
      if (taille < 8 || i + taille > fin) return null;

      if (nom == cible) return [i + 8, i + taille];

      if (conteneurs.contains(nom)) {
        // « meta » porte quatre octets de version avant ses enfants.
        final saut = nom == 'meta' ? 12 : 8;
        final trouve = _trouverAtome(data, cible, i + saut, i + taille);
        if (trouve != null) return trouve;
      }
      i += taille;
    }
    return null;
  }

  static Uint8List? _donneeAtome(Uint8List data, int debut, int fin) {
    var i = debut;
    while (i + 8 <= fin) {
      final taille = _u32(data, i);
      if (taille < 8 || i + taille > fin) return null;
      final nom = String.fromCharCodes(data.sublist(i + 4, i + 8));
      if (nom == 'data' && taille > 16) {
        return data.sublist(i + 16, i + taille);
      }
      i += taille;
    }
    return null;
  }

  // ------------------------------------------------------------ nettoyage

  static String? _nettoyer(String? valeur) {
    if (valeur == null) return null;
    // Les étiquettes traînent souvent des octets nuls en fin de champ.
    final propre = valeur.replaceAll('\u0000', '').trim();
    return propre.isEmpty ? null : propre;
  }

  static int? _premierNombre(String? valeur) {
    if (valeur == null) return null;
    final trouve = RegExp(r'\d+').firstMatch(valeur);
    if (trouve == null) return null;
    return int.tryParse(trouve.group(0)!);
  }

  /// Les vieux fichiers écrivent le genre sous forme « (17) » ou « (17)Rock ».
  static String? _nettoyerGenre(String? valeur) {
    if (valeur == null) return null;
    final sansCode = valeur.replaceAll(RegExp(r'^\(\d+\)\s*'), '').trim();
    return sansCode.isEmpty ? null : sansCode;
  }
}
