import 'package:material_ui/material_ui.dart';

import '../models/meta_item.dart';
import 'glass_card.dart';
import 'net_image.dart';

class PosterCard extends StatelessWidget {
  const PosterCard({super.key, required this.item, required this.onTap});

  final MetaItem item;
  final VoidCallback onTap;

  static const double width = 158;
  static const double height = 237;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassCard(
            width: width,
            height: height,
            onTap: onTap,
            child: NetImage(item.posterImage, cacheWidth: 320),
          ),
          const SizedBox(height: 12),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          if (item.releaseInfo != null)
            Text(
              item.releaseInfo!,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
        ],
      ),
    );
  }
}
