import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/nav_provider.dart';
import 'glass_panel.dart';

/// Floating glass pill with the app's main destinations.
class TopNav extends StatelessWidget {
  const TopNav({super.key});

  static const _icons = {
    AppTab.home: Icons.home_rounded,
    AppTab.movies: Icons.movie_rounded,
    AppTab.series: Icons.tv_rounded,
    AppTab.search: Icons.search_rounded,
    AppTab.library: Icons.bookmark_rounded,
    AppTab.settings: Icons.settings_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavProvider>();
    return GlassPanel(
      borderRadius: 999,
      blur: 20,
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final tab in AppTab.values)
            _NavItem(
              label: tab.label,
              icon: _icons[tab]!,
              selected: nav.tab == tab,
              onTap: () => context.read<NavProvider>().select(tab),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    final lit = _hover || _focus;
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: Colors.white.withValues(
              alpha: sel ? 0.18 : (lit ? 0.09 : 0.0),
            ),
            border: Border.all(
              color: _focus
                  ? const Color(0xFF00E5FF).withValues(alpha: 0.8)
                  : Colors.transparent,
            ),
            boxShadow: sel
                ? [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.22),
                      blurRadius: 14,
                    ),
                  ]
                : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 17,
                color: Colors.white.withValues(alpha: sel ? 1 : 0.65),
              ),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  color: Colors.white.withValues(alpha: sel ? 1 : 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
