import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/meta_item.dart';
import '../models/next_up.dart';
import '../models/watch_progress.dart';
import '../providers/library_provider.dart';
import '../screens/player/open_player.dart';
import '../screens/player/play_next.dart';
import 'continue_card.dart';
import 'media_row.dart';
import 'next_up_card.dart';

/// "Continue Watching" shelf: things you are partway through (tap resumes
/// straight into the player) and, for series, "Up next" episodes after one you
/// just finished (tap starts it with a matching source). Newest activity first.
class ContinueRow extends StatelessWidget {
  const ContinueRow({
    super.key,
    required this.items,
    this.nextUp = const [],
    required this.onOpenDetails,
  });

  final List<WatchProgress> items;
  final List<NextUp> nextUp;
  final ValueChanged<MetaItem> onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final entries = <({DateTime at, Object value})>[
      for (final p in items) (at: p.updatedAt, value: p),
      for (final n in nextUp) (at: n.updatedAt, value: n),
    ]..sort((a, b) => b.at.compareTo(a.at));

    return MediaRow(
      title: 'Continue Watching',
      items: const [],
      onOpen: onOpenDetails,
      itemCount: entries.length,
      rowHeight: ContinueCard.height + 104,
      itemBuilder: (context, i) {
        final v = entries[i].value;
        if (v is NextUp) {
          return NextUpCard(
            nextUp: v,
            onTap: () => playEpisodeAuto(
              context,
              meta: v.meta,
              next: v.episode,
              reference: v.reference,
            ),
            onRemove: () =>
                context.read<LibraryProvider>().clearNextUp(v.meta.id),
          );
        }
        final p = v as WatchProgress;
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
