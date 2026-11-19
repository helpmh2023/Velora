import 'dart:ui' show PointerDeviceKind;

import 'package:material_ui/material_ui.dart';

import '../core/smooth_scroll.dart';
import '../models/meta_item.dart';
import 'poster_card.dart';

/// Titled horizontal row of posters. Scrolls with touch, mouse drag, shift +
/// wheel, the chevrons, or by arrowing through the cards.
class MediaRow extends StatefulWidget {
  const MediaRow({
    super.key,
    required this.title,
    required this.items,
    required this.onOpen,
    this.itemBuilder,
    this.itemCount,
    this.rowHeight,
  });

  final String title;
  final List<MetaItem> items;
  final ValueChanged<MetaItem> onOpen;

  /// Custom card (e.g. Continue Watching). Defaults to a poster card.
  final Widget Function(BuildContext context, int index)? itemBuilder;
  final int? itemCount;

  /// Height of the scrolling strip; defaults to fit a poster card.
  final double? rowHeight;

  @override
  State<MediaRow> createState() => _MediaRowState();
}

class _MediaRowState extends State<MediaRow> {
  final _controller = SmoothScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollBy(double dx) {
    if (!_controller.hasClients) return;
    final target = (_controller.offset + dx).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    const pad = 40.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: pad),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _Chevron(
                icon: Icons.chevron_left_rounded,
                onTap: () => _scrollBy(-640),
              ),
              const SizedBox(width: 6),
              _Chevron(
                icon: Icons.chevron_right_rounded,
                onTap: () => _scrollBy(640),
              ),
            ],
          ),
        ),
        // Vertical padding leaves room for the 1.05x scale + glow.
        SizedBox(
          height: widget.rowHeight ?? PosterCard.height + 104,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: ListView.separated(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(pad, 22, pad, 22),
              itemCount: widget.itemCount ?? widget.items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 18),
              itemBuilder:
                  widget.itemBuilder ??
                  (context, i) => PosterCard(
                    item: widget.items[i],
                    onTap: () => widget.onOpen(widget.items[i]),
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Chevron extends StatefulWidget {
  const _Chevron({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_Chevron> createState() => _ChevronState();
}

class _ChevronState extends State<_Chevron> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: _hover ? 0.2 : 0.08),
        ),
        child: Icon(widget.icon, size: 22, color: Colors.white),
      ),
    ),
  );
}
