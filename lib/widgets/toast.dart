import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// A small message that appears near the bottom of the window and fades away.
/// Works anywhere (it uses the root overlay, not a Scaffold).
OverlayEntry? _current;
Timer? _currentTimer;

void showToast(BuildContext context, String message, {bool error = false}) {
  final overlay = Navigator.maybeOf(context, rootNavigator: true)?.overlay;
  if (overlay == null) return;
  // One at a time: a new message replaces the old one instead of piling up.
  _currentTimer?.cancel();
  _current?.remove();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      left: 0,
      right: 0,
      bottom: 36,
      child: IgnorePointer(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF111A2E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x33FFFFFF)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        error
                            ? Icons.error_outline_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 20,
                        color: error
                            ? const Color(0xFFFFB74D)
                            : const Color(0xFF69F0AE),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          message,
                          style: const TextStyle(fontSize: 13.5, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  _current = entry;
  overlay.insert(entry);
  _currentTimer = Timer(Duration(seconds: error ? 7 : 4), () {
    entry.remove();
    if (identical(_current, entry)) _current = null;
  });
}
