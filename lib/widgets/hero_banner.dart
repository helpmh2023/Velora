import 'dart:async';

import 'package:flutter/material.dart';

import '../models/meta_item.dart';
import 'glass_button.dart';
import 'net_image.dart';

/// Full-width landscape hero. Uses the high-res `background` image (never the
/// poster), anchored top-centre, with a left-to-right scrim so text stays
/// readable. Rotates through [items] every few seconds.
/// Backdrops are decoded at this width (they are 1920px originals).
const int heroDecodeWidth = 1600;

class HeroBanner extends StatefulWidget {
  const HeroBanner({super.key, required this.items, required this.onOpen});

  final List<MetaItem> items;
  final ValueChanged<MetaItem> onOpen;

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  static const _interval = Duration(seconds: 9);

  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Warm the first backdrop so it does not pop in late.
    _precache(0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    if (widget.items.length < 2) return;
    _timer = Timer.periodic(
      _interval,
      (_) => _go((_index + 1) % widget.items.length),
    );
  }

  Future<void> _precache(int i) async {
    final url = widget.items[i].heroImage;
    if (url == null || !mounted) return;
    try {
      await precacheImage(
        ResizeImage(NetworkImage(url), width: heroDecodeWidth),
        context,
      );
    } catch (_) {}
  }

  /// Load the next backdrop first, then crossfade to it.
  Future<void> _go(int i) async {
    await _precache(i);
    if (!mounted) return;
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final item = widget.items[_index];
    final width = MediaQuery.sizeOf(context).width;
    final height = (width * 0.40).clamp(380.0, 560.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 900),
                child: SizedBox.expand(
                  key: ValueKey(item.id),
                  child: NetImage(
                    item.heroImage,
                    alignment: Alignment.topCenter,
                    cacheWidth: heroDecodeWidth,
                  ),
                ),
              ),
              // Left-to-right scrim for text legibility.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0xF2060912),
                      Color(0xB3060912),
                      Color(0x00060912),
                    ],
                    stops: [0.0, 0.45, 0.85],
                  ),
                ),
              ),
              // Bottom fade so the hero melts into the page.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00060912), Color(0xFF060912)],
                    stops: [0.65, 1.0],
                  ),
                ),
              ),
              Positioned(
                left: 40,
                bottom: 48,
                width: (width * 0.42).clamp(320.0, 560.0),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: _Info(
                    key: ValueKey(item.id),
                    item: item,
                    onOpen: () => widget.onOpen(item),
                  ),
                ),
              ),
              if (widget.items.length > 1)
                Positioned(
                  right: 28,
                  bottom: 24,
                  child: Row(
                    children: [
                      for (var i = 0; i < widget.items.length; i++)
                        GestureDetector(
                          onTap: () {
                            _go(i);
                            _restart();
                          },
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Padding(
                              padding: const EdgeInsets.all(5),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                width: i == _index ? 22 : 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  color: Colors.white.withValues(
                                    alpha: i == _index ? 0.95 : 0.35,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({super.key, required this.item, required this.onOpen});

  final MetaItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (item.releaseInfo != null) item.releaseInfo!,
      if (item.runtime != null) item.runtime!,
      item.isSeries ? 'Series' : 'Movie',
    ].join('  -  ');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.logoImage != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 96, maxWidth: 360),
            child: Image.network(
              item.logoImage!,
              alignment: Alignment.centerLeft,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _Title(item.name),
            ),
          )
        else
          _Title(item.name),
        const SizedBox(height: 14),
        Row(
          children: [
            if (item.rating != null) ...[
              const Icon(
                Icons.star_rounded,
                size: 18,
                color: Color(0xFFFFD54F),
              ),
              const SizedBox(width: 4),
              Text(
                item.rating!.toStringAsFixed(1),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 14),
            ],
            Flexible(
              child: Text(
                meta,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13.5),
              ),
            ),
          ],
        ),
        if (item.genres.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            item.genres.take(3).join('  -  '),
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          item.description ?? '',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14.5,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            GlassButton(
              label: 'Watch',
              icon: Icons.play_arrow_rounded,
              primary: true,
              onTap: onOpen,
            ),
            const SizedBox(width: 12),
            GlassButton(
              label: 'More info',
              icon: Icons.info_outline_rounded,
              onTap: onOpen,
            ),
          ],
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => Text(
    name,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.w900,
      height: 1.05,
      letterSpacing: 0.5,
    ),
  );
}
