import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/smooth_scroll.dart';
import '../../models/meta_item.dart';
import '../../providers/home_provider.dart';
import '../../providers/library_provider.dart';
import '../../widgets/continue_row.dart';
import '../../widgets/glass_button.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/hero_banner.dart';
import '../../widgets/media_row.dart';
import '../details/details_screen.dart';

/// Hero banner plus horizontal rows of movies and series from Cinemeta.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();

  static void openDetails(BuildContext context, MetaItem item) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, _, _) => DetailsScreen(item: item),
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }
}

class _HomeScreenState extends State<HomeScreen> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();

    switch (home.state) {
      case LoadState.loading:
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      case LoadState.error:
        return Center(
          child: GlassPanel(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded, size: 36),
                const SizedBox(height: 12),
                const Text(
                  "Couldn't load the catalog",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  home.error ?? '',
                  style: const TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 18),
                GlassButton(
                  label: 'Try again',
                  icon: Icons.refresh_rounded,
                  primary: true,
                  autofocus: true,
                  onTap: () => context.read<HomeProvider>().load(),
                ),
              ],
            ),
          ),
        );
      case LoadState.ready:
        void open(MetaItem m) => HomeScreen.openDetails(context, m);
        final lib = context.watch<LibraryProvider>();
        final cont = lib.continueWatching;
        final next = lib.nextUp;
        final favs = lib.favourites;
        final shelves = <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: HeroBanner(items: home.hero, onOpen: open),
          ),
          if (cont.isNotEmpty || next.isNotEmpty)
            ContinueRow(items: cont, nextUp: next, onOpenDetails: open),
          if (favs.isNotEmpty)
            MediaRow(title: 'My List', items: favs, onOpen: open),
          for (final row in home.rows)
            MediaRow(title: row.title, items: row.items, onOpen: open),
        ];
        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: 40),
          itemCount: shelves.length,
          itemBuilder: (context, i) => shelves[i],
        );
    }
  }
}
