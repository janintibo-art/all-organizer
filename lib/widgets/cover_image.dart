import 'dart:io';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/cover_cache.dart';

/// Pochette d'un morceau ou d'un album, avec un substitut sobre quand
/// aucune image n'existe.
class CoverImage extends StatelessWidget {
  final String? path;
  final double size;
  final double radius;
  final IconData icon;

  const CoverImage({
    super.key,
    required this.path,
    this.size = 56,
    this.radius = radiusSm,
    this.icon = Icons.music_note,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: CoverCache.exists(path)
            ? Image.file(
                File(path!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _substitut(),
              )
            : _substitut(),
      ),
    );
  }

  Widget _substitut() {
    return Container(
      decoration: BoxDecoration(
        color: Palette.raised,
        border: Border.all(color: Palette.line),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Palette.muted, size: size * 0.4),
    );
  }
}
