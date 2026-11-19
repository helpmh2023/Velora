import 'package:flutter/material.dart';

/// Thin progress bar with a buffered layer; click or drag to seek.
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final ValueChanged<Duration> onSeek;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _drag; // 0..1 while dragging
  bool _hover = false;

  double _frac(Duration d) => widget.duration.inMilliseconds <= 0
      ? 0
      : (d.inMilliseconds / widget.duration.inMilliseconds).clamp(0.0, 1.0);

  void _commit(double f) => widget.onSeek(
    Duration(
      milliseconds: (f.clamp(0.0, 1.0) * widget.duration.inMilliseconds)
          .round(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final played = _drag ?? _frac(widget.position);
    final buffered = _frac(widget.buffered);
    final active = _hover || _drag != null;

    return LayoutBuilder(
      builder: (context, c) {
        double fx(Offset p) => p.dx / c.maxWidth;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _commit(fx(d.localPosition)),
            onHorizontalDragStart: (d) =>
                setState(() => _drag = fx(d.localPosition).clamp(0.0, 1.0)),
            onHorizontalDragUpdate: (d) =>
                setState(() => _drag = fx(d.localPosition).clamp(0.0, 1.0)),
            onHorizontalDragEnd: (_) {
              if (_drag != null) _commit(_drag!);
              setState(() => _drag = null);
            },
            child: SizedBox(
              height: 28,
              child: CustomPaint(
                painter: _BarPainter(
                  played: played,
                  buffered: buffered,
                  thick: active,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.played,
    required this.buffered,
    required this.thick,
  });

  final double played;
  final double buffered;
  final bool thick;

  @override
  void paint(Canvas canvas, Size size) {
    final h = thick ? 6.0 : 4.0;
    final y = size.height / 2;
    RRect bar(double from, double to) =>
        RRect.fromLTRBR(from, y - h / 2, to, y + h / 2, Radius.circular(h / 2));

    canvas.drawRRect(
      bar(0, size.width),
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
    canvas.drawRRect(
      bar(0, size.width * buffered),
      Paint()..color = Colors.white.withValues(alpha: 0.32),
    );

    final px = size.width * played;
    canvas.drawRRect(
      bar(0, px),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF00BFA5), Color(0xFF00E5FF), Color(0xFF8C40F2)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    if (thick) {
      canvas.drawCircle(
        Offset(px, y),
        8,
        Paint()..color = const Color(0xFF00E5FF).withValues(alpha: 0.35),
      );
      canvas.drawCircle(Offset(px, y), 5.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_BarPainter o) =>
      o.played != played || o.buffered != buffered || o.thick != thick;
}
