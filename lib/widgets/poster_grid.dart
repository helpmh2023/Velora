import 'package:flutter/material.dart';

import '../models/meta_item.dart';
import 'poster_card.dart';

/// Wrapping grid of posters (search results, My List).
class PosterGrid extends StatelessWidget {
  const PosterGrid({super.key, required this.items, required this.onOpen});

  final List<MetaItem> items;
  final ValueChanged<MetaItem> onOpen;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 20,
    runSpacing: 26,
    children: [
      for (final m in items) PosterCard(item: m, onTap: () => onOpen(m)),
    ],
  );
}
