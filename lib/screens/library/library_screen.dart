import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/smooth_scroll.dart';
import '../../models/meta_item.dart';
import '../../providers/library_provider.dart';
import '../../widgets/continue_row.dart';
import '../../widgets/poster_grid.dart';
import '../home/home_screen.dart';

/// Continue Watching plus the user's list of favourites.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryProvider>();
    final cont = lib.continueWatching;
    final favs = lib.favourites;
    void open(MetaItem m) => HomeScreen.openDetails(context, m);

    if (cont.isEmpty && favs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border_rounded,
              size: 48,
              color: Colors.white30,
            ),
            SizedBox(height: 14),
            Text(
              'Your library is empty',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            Text(
              'Add titles with "My List" and they will show up here.',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.only(top: 12, bottom: 48),
      children: [
        if (cont.isNotEmpty) ContinueRow(items: cont, onOpenDetails: open),
        if (favs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 12, 40, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'My List',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                PosterGrid(items: favs, onOpen: open),
              ],
            ),
          ),
      ],
    );
  }
}
