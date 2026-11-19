import 'package:flutter/material.dart';

import '../../models/stream_source.dart';
import '../../services/torrentio_service.dart';
import '../../widgets/glass_button.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/glass_panel.dart';

/// Opens the glass source picker. Returns the chosen source, or null.
Future<StreamSource?> showStreamPicker(
  BuildContext context, {
  required String type,
  required String videoId,
  required String title,
  String? subtitle,
}) {
  return showGeneralDialog<StreamSource>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => _StreamPicker(
      type: type,
      videoId: videoId,
      title: title,
      subtitle: subtitle,
    ),
    transitionBuilder: (_, a, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween(
          begin: 0.96,
          end: 1.0,
        ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
}

class _StreamPicker extends StatefulWidget {
  const _StreamPicker({
    required this.type,
    required this.videoId,
    required this.title,
    this.subtitle,
  });

  final String type;
  final String videoId;
  final String title;
  final String? subtitle;

  @override
  State<_StreamPicker> createState() => _StreamPickerState();
}

class _StreamPickerState extends State<_StreamPicker> {
  List<StreamSource>? _all;
  String? _error;
  Quality? _filter; // null = all

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _all = null;
      _error = null;
    });
    try {
      final list = await TorrentioService().streams(
        widget.type,
        widget.videoId,
      );
      if (mounted) setState(() => _all = list);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = (size.width - 48).clamp(320.0, 820.0);
    final h = (size.height - 80).clamp(360.0, 760.0);

    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: w,
          height: h,
          child: GlassPanel(
            blur: 30,
            borderRadius: 28,
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (widget.subtitle != null)
                            Text(
                              widget.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white60),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(child: _body()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return _Centered(
        icon: Icons.cloud_off_rounded,
        text: _error!,
        action: GlassButton(
          label: 'Try again',
          icon: Icons.refresh_rounded,
          primary: true,
          autofocus: true,
          onTap: _load,
        ),
      );
    }
    final all = _all;
    if (all == null) {
      return const _Centered(spinner: true, text: 'Searching sources...');
    }
    if (all.isEmpty) {
      return const _Centered(
        icon: Icons.search_off_rounded,
        text: 'No sources with seeders were found for this title.',
      );
    }

    final tiers = [
      for (final q in Quality.values)
        if (all.any((s) => s.quality == q)) q,
    ];
    final shown = _filter == null
        ? all
        : all.where((s) => s.quality == _filter).toList();

    // The most-seeded source in what is currently shown (ties: higher quality).
    final best = shown.reduce((a, b) {
      if (a.seeders != b.seeders) return a.seeders > b.seeders ? a : b;
      return a.quality.index <= b.quality.index ? a : b;
    });

    // Flat list: a header row whenever the quality tier changes.
    final rows = <Object>[];
    Quality? last;
    for (final s in shown) {
      if (s.quality != last) {
        rows.add(s.quality);
        last = s.quality;
      }
      rows.add(s);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _chip(
                'All',
                _filter == null,
                () => setState(() => _filter = null),
              ),
              for (final q in tiers)
                _chip(q.label, _filter == q, () => setState(() => _filter = q)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassButton(
          label:
              'Play most-seeded  -  ${best.seeders} seeds, ${best.quality.label}, ${best.sizeLabel}',
          icon: Icons.bolt_rounded,
          primary: true,
          onTap: () => Navigator.of(context).pop(best),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            // Room for the hover glow/scale so tiles are never clipped.
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            itemBuilder: (context, i) {
              final r = rows[i];
              if (r is Quality) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(2, 10, 0, 8),
                  child: Text(
                    r.label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF00E5FF),
                      letterSpacing: 0.5,
                    ),
                  ),
                );
              }
              final s = r as StreamSource;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SourceTile(
                  source: s,
                  isBest: identical(s, best),
                  onTap: () => Navigator.of(context).pop(s),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: GlassButton(label: label, primary: selected, onTap: onTap),
  );
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.onTap,
    this.isBest = false,
  });

  final StreamSource source;
  final VoidCallback onTap;

  /// Marks the source with the most seeders in the current list.
  final bool isBest;

  @override
  Widget build(BuildContext context) {
    final s = source;
    return GlassCard(
      onTap: onTap,
      borderRadius: 16,
      scale: 1.015,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isBest) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: const Color(0xFF69F0AE).withValues(alpha: 0.18),
                        border: Border.all(
                          color: const Color(0xFF69F0AE).withValues(alpha: 0.6),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star_rounded,
                            size: 13,
                            color: Color(0xFF69F0AE),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'MOST SEEDS - best chance of a fast start',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: Color(0xFF69F0AE),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    s.release,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final t in s.tags) _Tag(t),
                      if (s.languages.isNotEmpty)
                        Text(s.languages, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_upward_rounded,
                      size: 15,
                      color: s.seeders >= 20
                          ? const Color(0xFF69F0AE)
                          : (s.seeders >= 5
                                ? const Color(0xFFFFD54F)
                                : const Color(0xFFFF8A65)),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${s.seeders}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  s.sizeLabel,
                  style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                ),
                Text(
                  s.provider,
                  style: const TextStyle(fontSize: 11.5, color: Colors.white38),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      color: Colors.white.withValues(alpha: 0.12),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

class _Centered extends StatelessWidget {
  const _Centered({
    this.icon,
    this.text = '',
    this.action,
    this.spinner = false,
  });

  final IconData? icon;
  final String text;
  final Widget? action;
  final bool spinner;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (spinner)
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          )
        else if (icon != null)
          Icon(icon, size: 38, color: Colors.white54),
        const SizedBox(height: 14),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
        if (action != null) ...[const SizedBox(height: 18), action!],
      ],
    ),
  );
}
