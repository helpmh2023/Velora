import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/smooth_scroll.dart';
import '../../models/meta_item.dart';
import '../../providers/browse_provider.dart';
import '../../widgets/prebuffer_status.dart';
import '../../widgets/glass_button.dart';
import '../../widgets/poster_card.dart';
import '../home/home_screen.dart';

/// Movies / Series tab: browse a whole catalog by popularity, featured list
/// or year, filter by genre, and keep scrolling for more.
/// [T] picks which provider (movies or series) this screen shows.
class BrowseScreen<T extends BrowseProvider> extends StatefulWidget {
  const BrowseScreen({super.key, required this.title});

  final String title;

  @override
  State<BrowseScreen<T>> createState() => _BrowseScreenState<T>();
}

class _BrowseScreenState<T extends BrowseProvider>
    extends State<BrowseScreen<T>> {
  late final T _browse = context.read<T>();
  late final SmoothScrollController _scroll = SmoothScrollController(
    initialScrollOffset: _browse.scrollOffset,
  );

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // Not during build: loading notifies listeners.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _browse.ensureLoaded();
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    _browse.scrollOffset = p.pixels;
    // Fetch the next page before the user reaches the bottom.
    if (p.pixels > p.maxScrollExtent - 900) _browse.loadMore();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _open(MetaItem m) => HomeScreen.openDetails(context, m);

  @override
  Widget build(BuildContext context) {
    final b = context.watch<T>();
    final items = b.items;

    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(
          child: _Header(title: widget.title, browse: b),
        ),
        if (items.isNotEmpty)
          SliverPadding(
            // Side room for the hover glow; bottom room before the footer.
            padding: const EdgeInsets.fromLTRB(40, 18, 40, 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 190,
                mainAxisExtent: 305,
                crossAxisSpacing: 18,
                mainAxisSpacing: 14,
              ),
              delegate: SliverChildBuilderDelegate((context, i) {
                final m = items[i];
                return Align(
                  alignment: Alignment.topCenter,
                  child: PosterCard(item: m, onTap: () => _open(m)),
                );
              }, childCount: items.length),
            ),
          ),
        SliverToBoxAdapter(child: _Footer(browse: b)),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.browse});

  final String title;
  final BrowseProvider browse;

  @override
  Widget build(BuildContext context) {
    final b = browse;
    final inYear = b.mode == BrowseMode.year;
    final options = inYear ? b.years : b.genres;

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 20, 40, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              PrebufferStatusButton(
                preferType: title == 'Series' ? 'series' : 'movie',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in BrowseMode.values)
                GlassButton(
                  label: m.label,
                  primary: b.mode == m,
                  onTap: () => b.setMode(m),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Genres (or years) in one horizontally scrolling row.
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                if (!inYear)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GlassButton(
                      label: 'All genres',
                      primary: b.filter == null,
                      onTap: () => b.setFilter(null),
                    ),
                  ),
                for (final o in options)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GlassButton(
                      label: o,
                      primary: b.filter == o,
                      onTap: () => b.setFilter(o),
                    ),
                  ),
              ],
            ),
          ),
          if (inYear)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                'Year lists cannot be combined with a genre.',
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
            ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.browse});

  final BrowseProvider browse;

  @override
  Widget build(BuildContext context) {
    final b = browse;

    if (b.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 36,
              color: Colors.white38,
            ),
            const SizedBox(height: 10),
            Text(b.error!, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 14),
            GlassButton(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              primary: true,
              onTap: b.retry,
            ),
          ],
        ),
      );
    }
    if (b.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    if (b.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 70),
        child: Column(
          children: [
            Icon(Icons.search_off_rounded, size: 44, color: Colors.white30),
            SizedBox(height: 12),
            Text('Nothing here', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }
    if (!b.hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            "That's everything for this list.",
            style: TextStyle(color: Colors.white38),
          ),
        ),
      );
    }
    return const SizedBox(height: 48);
  }
}
