import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/meta_item.dart';
import '../models/watch_progress.dart';
import '../providers/library_provider.dart';
import '../screens/player/open_player.dart';
import 'continue_card.dart';
import 'media_row.dart';

/// "Continue Watching" shelf. Tapping resumes straight into the player;
/// entries saved without a source fall back to the details page.
class ContinueRow extends StatelessWidget {
  const ContinueRow({
    super.key,
    required this.items,
    required this.onOpenDetails,
  });

  final List<WatchProgress> items;
  final ValueChanged<MetaItem> onOpenDetails;

  @override
  Widget build(BuildContext context) {
    return MediaRow(
      title: 'Continue Watching',
      items: const [],
      onOpen: onOpenDetails,
      itemCount: items.length,
      rowHeight: ContinueCard.height + 104,
      itemBuilder: (context, i) {
        final p = items[i];
        return ContinueCard(
          progress: p,
          onTap: () async {
            final played = await resumeWatching(context, p);
            if (!played && context.mounted) onOpenDetails(p.meta);
          },
          onRemove: () =>
              context.read<LibraryProvider>().clearProgressFor(p.meta.id),
        );
      },
    );
  }
}
