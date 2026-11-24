import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../models/meta_item.dart';
import '../../models/stream_source.dart';
import '../../providers/library_provider.dart';
import '../../providers/prebuffer_provider.dart';
import '../../services/next_episode.dart';
import '../../widgets/glass_panel.dart';
import '../details/stream_picker.dart';
import 'open_player.dart';

/// Plays [next] of a series without asking which source: finds the one that
/// best matches [reference] (the episode just watched), shows a short
/// "finding a source" card meanwhile, and falls back to the source picker if
/// nothing suitable is found.
///
/// With [replace] the new player takes the place of the current screen (used
/// from inside the player). Returns true if a player was opened (it does not
/// wait for that player to close), false if the user backed out.
Future<bool> playEpisodeAuto(
  BuildContext context, {
  required MetaItem meta,
  required Episode next,
  StreamSource? reference,
  bool replace = false,
  bool fullscreen = false,
}) async {
  final svc = context.read<NextEpisodeService>();
  final library = context.read<LibraryProvider>();
  final prebuffer = context.read<PrebufferProvider>();
  final nav = Navigator.of(context);
  final label = 'S${next.season} E${next.number}  -  ${next.title}';

  // Pre-buffered already: play that copy straight away.
  final pre = prebuffer.sourceFor(next.id);
  if (pre != null) {
    final saved = library.progressFor(next.id);
    final route = playerRoute(
      source: pre,
      meta: meta,
      videoId: next.id,
      subtitle: label,
      season: next.season,
      episode: next.number,
      episodeTitle: next.title,
      resumeFrom: saved?.finished == true ? null : saved?.position,
      knownDuration: saved?.duration,
      fullscreen: fullscreen,
    );
    if (replace) {
      nav.pushReplacement(route);
    } else {
      nav.push(route);
    }
    return true;
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => PopScope(
      canPop: false,
      child: Center(
        child: GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'Finding a source for $label...',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  StreamSource? source;
  try {
    source = await svc.sourceFor(next, reference);
  } catch (_) {
    // Fall through to the picker, which shows its own error and retry.
  }
  if (!context.mounted) return false;
  Navigator.of(context, rootNavigator: true).pop(); // close the card

  source ??= await showStreamPicker(
    context,
    type: 'series',
    videoId: next.id,
    title: meta.name,
    subtitle: label,
  );
  if (source == null || !context.mounted) return false;

  final saved = library.progressFor(next.id);
  final route = playerRoute(
    source: source,
    meta: meta,
    videoId: next.id,
    subtitle: label,
    season: next.season,
    episode: next.number,
    episodeTitle: next.title,
    resumeFrom: saved?.finished == true ? null : saved?.position,
    knownDuration: saved?.duration,
    fullscreen: fullscreen,
  );
  if (replace) {
    nav.pushReplacement(route);
  } else {
    nav.push(route);
  }
  return true;
}
