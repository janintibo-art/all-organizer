/// Un morceau, tel qu'il existe sur le disque.
class Track {
  final String path;

  /// Serveur d'origine, nul pour un fichier local.
  String? serverId;

  String title;
  String artist;
  String albumArtist;
  String album;
  int? trackNumber;
  int? discNumber;
  int? year;
  String? genre;
  int? durationMs;

  /// Pochette extraite du fichier et rangée dans le cache.
  String? coverPath;

  /// Étiquettes absentes : le titre vient alors du nom de fichier.
  bool taggedFromFile;

  /// Le fichier contient une pochette, pas encore extraite.
  bool embeddedArt;

  int? addedAtMs;
  int playCount;
  int? lastPlayedAtMs;
  bool favorite;

  Track({
    required this.path,
    this.serverId,
    required this.title,
    this.artist = 'Artiste inconnu',
    String? albumArtist,
    this.album = 'Sans album',
    this.trackNumber,
    this.discNumber,
    this.year,
    this.genre,
    this.durationMs,
    this.coverPath,
    this.taggedFromFile = false,
    this.embeddedArt = false,
    this.addedAtMs,
    this.playCount = 0,
    this.lastPlayedAtMs,
    this.favorite = false,
  }) : albumArtist = albumArtist ?? artist;

  bool get remote => serverId != null;

  Duration? get duration =>
      durationMs == null ? null : Duration(milliseconds: durationMs!);

  /// Clé d'album : l'artiste de l'album compte autant que son titre, sinon
  /// toutes les compilations nommées « Best Of » se retrouveraient fondues.
  String get albumKey =>
      '${albumArtist.toLowerCase()}|${album.toLowerCase()}';

  String get artistKey => albumArtist.toLowerCase();

  String get sortTitle => title.toLowerCase();

  Map<String, dynamic> toJson() => {
        'path': path,
        'serverId': serverId,
        'title': title,
        'artist': artist,
        'albumArtist': albumArtist,
        'album': album,
        'trackNumber': trackNumber,
        'discNumber': discNumber,
        'year': year,
        'genre': genre,
        'durationMs': durationMs,
        'coverPath': coverPath,
        'taggedFromFile': taggedFromFile,
        'embeddedArt': embeddedArt,
        'addedAtMs': addedAtMs,
        'playCount': playCount,
        'lastPlayedAtMs': lastPlayedAtMs,
        'favorite': favorite,
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        path: j['path'] as String,
        serverId: j['serverId'] as String?,
        title: j['title'] as String? ?? 'Sans titre',
        artist: j['artist'] as String? ?? 'Artiste inconnu',
        albumArtist: j['albumArtist'] as String?,
        album: j['album'] as String? ?? 'Sans album',
        trackNumber: j['trackNumber'] as int?,
        discNumber: j['discNumber'] as int?,
        year: j['year'] as int?,
        genre: j['genre'] as String?,
        durationMs: j['durationMs'] as int?,
        coverPath: j['coverPath'] as String?,
        taggedFromFile: j['taggedFromFile'] as bool? ?? false,
        embeddedArt: j['embeddedArt'] as bool? ?? false,
        addedAtMs: j['addedAtMs'] as int?,
        playCount: j['playCount'] as int? ?? 0,
        lastPlayedAtMs: j['lastPlayedAtMs'] as int?,
        favorite: j['favorite'] as bool? ?? false,
      );
}

/// Un album, reconstitué à partir des morceaux qui le composent.
class Album {
  final String key;
  final String title;
  final String artist;
  final List<Track> tracks;

  const Album({
    required this.key,
    required this.title,
    required this.artist,
    required this.tracks,
  });

  int? get year {
    for (final t in tracks) {
      if (t.year != null) return t.year;
    }
    return null;
  }

  String? get coverPath {
    for (final t in tracks) {
      if (t.coverPath != null) return t.coverPath;
    }
    return null;
  }

  Duration get duration => Duration(
      milliseconds:
          tracks.fold<int>(0, (sum, t) => sum + (t.durationMs ?? 0)));

  /// Ordre d'écoute : disque, puis numéro de piste, puis titre.
  List<Track> get ordered {
    final list = [...tracks];
    list.sort((a, b) {
      final da = a.discNumber ?? 1;
      final db = b.discNumber ?? 1;
      if (da != db) return da.compareTo(db);
      final ta = a.trackNumber ?? 9999;
      final tb = b.trackNumber ?? 9999;
      if (ta != tb) return ta.compareTo(tb);
      return a.sortTitle.compareTo(b.sortTitle);
    });
    return list;
  }
}

/// Une liste de lecture. Elle retient des chemins : un morceau retiré du
/// disque laisse une entrée signalée plutôt que de disparaître en silence.
class Playlist {
  String id;
  String name;
  List<String> paths;
  int createdAtMs;
  String? note;

  Playlist({
    required this.id,
    required this.name,
    List<String>? paths,
    int? createdAtMs,
    this.note,
  })  : paths = paths ?? [],
        createdAtMs = createdAtMs ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'paths': paths,
        'createdAtMs': createdAtMs,
        'note': note,
      };

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Sans nom',
        paths: (j['paths'] as List?)?.map((e) => e.toString()).toList(),
        createdAtMs: j['createdAtMs'] as int?,
        note: j['note'] as String?,
      );
}
