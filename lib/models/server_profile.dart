/// Un serveur enregistré, avec tout ce qu'il faut pour l'atteindre.
class ServerProfile {
  String id;
  String name;

  /// Adresse complète, protocole compris : http://192.168.1.42:8321
  String url;

  /// Jeton exigé par le serveur, s'il en réclame un.
  String token;

  /// Adresse HTTP libre qui déclenche le réveil du PC.
  ///
  /// Volontairement libre : un module Tasmota, ESPHome ou un montage
  /// maison n'exposent pas la même adresse, et coder en dur le format
  /// d'un appareil précis n'aurait servi à rien.
  String wakeUrl;

  /// Temps d'attente après le réveil, avant de retenter la connexion.
  int wakeWaitSeconds;

  ServerProfile({
    required this.id,
    required this.name,
    required this.url,
    this.token = '',
    this.wakeUrl = '',
    this.wakeWaitSeconds = 60,
  });

  /// Adresse nettoyée : sans barre oblique finale, protocole ajouté au
  /// besoin — c'est l'oubli le plus fréquent à la saisie.
  String get baseUrl {
    var v = url.trim();
    if (v.isEmpty) return v;
    if (!v.startsWith('http://') && !v.startsWith('https://')) {
      v = 'http://$v';
    }
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  bool get hasWake => wakeUrl.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'token': token,
        'wakeUrl': wakeUrl,
        'wakeWaitSeconds': wakeWaitSeconds,
      };

  factory ServerProfile.fromJson(Map<String, dynamic> j) => ServerProfile(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Serveur',
        url: j['url'] as String? ?? '',
        token: j['token'] as String? ?? '',
        wakeUrl: j['wakeUrl'] as String? ?? '',
        wakeWaitSeconds: j['wakeWaitSeconds'] as int? ?? 60,
      );
}

/// Nature d'un fichier, telle que le serveur l'annonce.
enum RemoteKind { folder, video, audio, subtitle, image, other }

/// Une entrée du serveur : dossier ou fichier.
class RemoteEntry {
  final String name;

  /// Chemin au sens du serveur, à renvoyer tel quel dans les requêtes.
  final String path;

  final RemoteKind kind;
  final int size;
  final int? modifiedMs;

  const RemoteEntry({
    required this.name,
    required this.path,
    required this.kind,
    this.size = 0,
    this.modifiedMs,
  });

  bool get isFolder => kind == RemoteKind.folder;
  bool get isPlayable =>
      kind == RemoteKind.video || kind == RemoteKind.audio;

  String get sizeLabel {
    if (size <= 0) return '';
    if (size < 1000000) return '${(size / 1000).round()} Ko';
    if (size < 1000000000) return '${(size / 1000000).toStringAsFixed(1)} Mo';
    return '${(size / 1000000000).toStringAsFixed(2)} Go';
  }

  static RemoteKind kindFrom(String? nature) {
    switch (nature) {
      case 'video':
        return RemoteKind.video;
      case 'audio':
        return RemoteKind.audio;
      case 'sous-titre':
        return RemoteKind.subtitle;
      case 'image':
        return RemoteKind.image;
      default:
        return RemoteKind.other;
    }
  }
}

/// Position mémorisée dans un fichier, pour reprendre la lecture.
class Resume {
  final String key;
  final String name;
  final String path;
  final String serverId;
  final int positionMs;
  final int durationMs;
  final int updatedAtMs;
  final bool video;

  const Resume({
    required this.key,
    required this.name,
    required this.path,
    required this.serverId,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAtMs,
    required this.video,
  });

  double get ratio =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);

  /// Terminé : on ne propose plus de reprendre au-delà de ce seuil.
  bool get finished => ratio > 0.94;

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'path': path,
        'serverId': serverId,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAtMs': updatedAtMs,
        'video': video,
      };

  factory Resume.fromJson(Map<String, dynamic> j) => Resume(
        key: j['key'] as String,
        name: j['name'] as String? ?? '',
        path: j['path'] as String? ?? '',
        serverId: j['serverId'] as String? ?? '',
        positionMs: j['positionMs'] as int? ?? 0,
        durationMs: j['durationMs'] as int? ?? 0,
        updatedAtMs: j['updatedAtMs'] as int? ?? 0,
        video: j['video'] as bool? ?? true,
      );
}
