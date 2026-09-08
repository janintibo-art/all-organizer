import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/media_item.dart';
import '../services/poster_cache.dart';

/// Affiche d'une série : fichier local si disponible, sinon réseau.
class PosterImage extends StatelessWidget {
  final MediaItem item;
  final BoxFit fit;
  final Alignment alignment;
  final double iconSize;

  const PosterImage({
    super.key,
    required this.item,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.iconSize = 32,
  });

  @override
  Widget build(BuildContext context) {
    if (PosterCache.exists(item.posterPath)) {
      return Image.file(
        File(item.posterPath!),
        fit: fit,
        alignment: alignment,
        errorBuilder: (_, __, ___) => _network(),
      );
    }
    return _network();
  }

  Widget _network() {
    if (item.imageUrl == null || item.imageUrl!.isEmpty) return _placeholder();
    return CachedNetworkImage(
      imageUrl: item.imageUrl!,
      fit: fit,
      alignment: alignment,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, __) => Container(color: Palette.raised),
      errorWidget: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(
      decoration: BoxDecoration(
        color: Palette.surface,
        border: Border.all(color: Palette.line),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.movie_outlined, color: Palette.muted, size: iconSize),
    );
  }
}
