import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform.dart';
import '../../providers/nav_provider.dart';
import '../../widgets/breathing_logo.dart';
import '../../widgets/breathing_mark.dart';
import '../../widgets/title_bar.dart';
import '../../widgets/top_nav.dart';
import '../../providers/browse_provider.dart';
import '../browse/browse_screen.dart';
import '../home/home_screen.dart';
import '../library/library_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';

/// App frame: header (logo + nav + window controls) over the active tab.
class ShellScreen extends StatelessWidget {
  const ShellScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tab = context.watch<NavProvider>().tab;

    const logo = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeaderMark(),
        SizedBox(width: 10),
        BreathingVeloraLogo(fontSize: 20),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          if (isDesktop)
            const VeloraTitleBar(leading: logo, center: TopNav())
          else
            const SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  children: [
                    Align(alignment: Alignment.centerLeft, child: logo),
                    SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: TopNav(),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: KeyedSubtree(
                key: ValueKey(tab),
                child: switch (tab) {
                  AppTab.home => const HomeScreen(),
                  AppTab.movies => const BrowseScreen<MoviesBrowse>(
                    title: 'Movies',
                  ),
                  AppTab.series => const BrowseScreen<SeriesBrowse>(
                    title: 'Series',
                  ),
                  AppTab.search => const SearchScreen(),
                  AppTab.library => const LibraryScreen(),
                  AppTab.settings => const SettingsScreen(),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderMark extends StatelessWidget {
  const _HeaderMark();

  @override
  Widget build(BuildContext context) => Image.asset(
    BreathingVeloraMark.asset,
    width: 30,
    height: 30,
    filterQuality: FilterQuality.high,
  );
}
