import 'package:flutter/material.dart';

import '../main.dart';
import '../models/media_item.dart';
import 'poster_image.dart';

/// Affiche d'une serie. Reagit au survol sous Windows et a l'appui sur mobile.
class MediaCard extends StatefulWidget {
  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final double titleSize;

  const MediaCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onFavorite,
    this.titleSize = 13.5,
  });

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final scale = _down ? 0.97 : (_hover ? 1.03 : 1.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radiusMd),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PosterImage(item: item),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 62,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Color(0xE60D0B0B), Colors.transparent],
                            ),
                          ),
                        ),
                      ),
                      if (item.score != null)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Palette.shu,
                              borderRadius: BorderRadius.circular(radiusSm),
                            ),
                            child: Text(
                              item.score!.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      // Marque discrète : ce titre vit sur un serveur, il
                      // n'est lisible que quand le PC répond.
                      if (item.remote)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Palette.ink.withAlpha(200),
                              borderRadius: BorderRadius.circular(radiusSm),
                            ),
                            child: Icon(Icons.dns,
                                size: 13, color: Palette.kin),
                          ),
                        ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: IconButton(
                          iconSize: 20,
                          visualDensity: VisualDensity.compact,
                          onPressed: widget.onFavorite,
                          icon: Icon(
                            item.favorite
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: item.favorite
                                ? Palette.sakura
                                : Colors.white70,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: item.progress > 0 ? 12 : 6,
                        child: Text(
                          item.progress > 0
                              ? '${item.watchedCount}/${item.episodes.length} vus'
                              : '${item.episodes.length} fichier${item.episodes.length > 1 ? 's' : ''}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (item.progress > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: item.progress,
                            minHeight: 3,
                            backgroundColor: const Color(0x66000000),
                            color: item.finished ? Palette.kin : Palette.shu,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: widget.titleSize,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.genres.isEmpty
                    ? (item.metaFetched ? 'Genre inconnu' : 'Fiche non chargée')
                    : item.genres.take(2).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: item.genres.isEmpty ? Palette.muted : Palette.kin,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

/// Ligne compacte pour le mode liste.
class MediaRow extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;

  const MediaRow({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(radiusSm),
              child: SizedBox(
                width: 46,
                height: 66,
                child: PosterImage(item: item, iconSize: 18),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (item.year != null) '${item.year}',
                      if (item.genres.isNotEmpty) item.genres.first,
                      '${item.episodes.length} épisodes',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Palette.muted, fontSize: 11.5),
                  ),
                  if (item.progress > 0) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: item.progress,
                        minHeight: 3,
                        backgroundColor: Palette.line,
                        color: item.finished ? Palette.kin : Palette.shu,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (item.score != null)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(item.score!.toStringAsFixed(1),
                    style: TextStyle(
                        color: Palette.kin,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
  }
}
