import 'media_item.dart';

/// Un dossier surveillé, et ce qu'il contient.
///
/// La nature est déclarée au moment où l'on choisit le dossier, elle n'est
/// plus devinée : un dossier ajouté depuis l'onglet Animes ne contient que
/// des animes, quoi qu'en disent les fiches récupérées ensuite.
class LibraryFolder {
  final String path;
  final MediaKind kind;

  /// Vrai pour un dossier de contenus jeunesse, quelle que soit sa nature.
  final bool kids;

  const LibraryFolder({
    required this.path,
    required this.kind,
    this.kids = false,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'kind': kind.name,
        'kids': kids,
      };

  factory LibraryFolder.fromJson(Map<String, dynamic> j) => LibraryFolder(
        path: j['path'] as String,
        kind: switch (j['kind']) {
          'movie' => MediaKind.movie,
          'anime' => MediaKind.anime,
          _ => MediaKind.series,
        },
        kids: j['kids'] as bool? ?? false,
      );

  String get kindLabel {
    if (kids) return 'Jeunesse';
    return switch (kind) {
      MediaKind.anime => 'Animes',
      MediaKind.movie => 'Films',
      MediaKind.series => 'Séries',
    };
  }
}
