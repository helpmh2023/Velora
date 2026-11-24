import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/share_server.dart';
import 'glass_button.dart';
import 'glass_panel.dart';
import 'toast.dart';

/// "Play on iPad": starts sharing on the local network and shows a QR code to
/// scan with the other device's camera. With [item] the code opens that
/// video's page; without, the list of everything pre-buffered.
Future<void> showShareDialog(BuildContext context, {ShareItem? item}) async {
  final share = context.read<ShareServer>();
  final problem = await share.start();
  if (!context.mounted) return;
  if (problem != null) {
    showToast(context, problem, error: true);
    return;
  }
  final url = item == null ? share.indexUrl! : share.pageUrl(item)!;
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (ctx) => _ShareDialog(url: url, title: item?.label, share: share),
  );
}

class _ShareDialog extends StatelessWidget {
  const _ShareDialog({required this.url, required this.share, this.title});

  final String url;
  final String? title;
  final ShareServer share;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 460,
        child: GlassPanel(
          borderRadius: 24,
          padding: const EdgeInsets.all(24),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Watch on your iPad',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                if (title != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    title!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: url,
                    size: 220,
                    version: QrVersions.auto,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '1. Put the iPad on the same Wi-Fi as this PC.\n'
                  '2. Point its camera at this code and tap the link. It opens '
                  'VLC by itself (free on the App Store); if asked, tap Open.\n'
                  '3. Keep this PC on, with Velora open. Where you stop is saved '
                  'here, so Continue Watching picks it up.',
                  style: TextStyle(
                    color: Colors.white70,
                    height: 1.5,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  url,
                  style: const TextStyle(color: Colors.white38, fontSize: 11.5),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GlassButton(
                      label: 'Stop sharing',
                      onTap: () async {
                        await share.stop();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(width: 12),
                    GlassButton(
                      label: 'Done',
                      primary: true,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
