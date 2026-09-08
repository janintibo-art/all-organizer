import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../services/links.dart';

/// Bloc « Où regarder » : une rangée de liens de recherche.
/// Appui long pour copier l'adresse si l'ouverture échoue.
class WatchLinks extends StatelessWidget {
  final String title;
  final int? year;

  const WatchLinks({super.key, required this.title, this.year});

  Future<void> _open(BuildContext context, WatchLink link) async {
    final ok = await Links.open(link.url);
    if (ok || !context.mounted) return;
    await Clipboard.setData(ClipboardData(text: link.url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Ouverture impossible. Adresse copiée.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final links = Links.forTitle(title, year: year);
    if (links.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 3, height: 15, color: Palette.shu),
            const SizedBox(width: 8),
            const Text('Où regarder',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Ouvre une recherche dans ton navigateur.',
          style: TextStyle(color: Palette.muted, fontSize: 11.5),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final link in links)
              GestureDetector(
                onTap: () => _open(context, link),
                onLongPress: () async {
                  await Clipboard.setData(ClipboardData(text: link.url));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Adresse copiée.')),
                  );
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Palette.surface,
                    border: Border.all(color: Palette.line),
                    borderRadius: BorderRadius.circular(radiusSm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_new,
                          size: 13, color: Palette.muted),
                      const SizedBox(width: 6),
                      Text(link.label,
                          style: TextStyle(
                              fontSize: 12.5, color: Palette.text)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
