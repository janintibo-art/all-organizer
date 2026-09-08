import 'media_meta.dart';

/// Un épisode fraîchement diffusé, rattaché à sa série.
class EpisodeRelease {
  final MediaMeta anime;
  final int? number;
  final DateTime? airedAt;

  const EpisodeRelease({required this.anime, this.number, this.airedAt});

  /// Clé de dédoublonnage entre les différentes sources.
  String get key =>
      '${anime.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}-${number ?? 0}';

  /// « il y a 3 h », « hier », puis la date passé deux jours.
  String get whenLabel {
    final date = airedAt;
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.isNegative) return 'à venir';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    if (diff.inDays == 1) return 'hier';
    if (diff.inDays < 7) return 'il y a ${diff.inDays} jours';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}';
  }

  String get episodeLabel =>
      number == null ? 'Nouvel épisode' : 'Épisode $number';
}
