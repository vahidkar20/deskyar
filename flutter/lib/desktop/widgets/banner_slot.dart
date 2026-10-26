// Reserved slot for a promotional banner in the home page's left pane.
//
// The pane is narrow (200px, or 280px in incoming-only mode), so a fixed-size
// banner would either overflow or leave gaps. This widget measures the pane and
// keeps a 16:9 box that always fits, which means artwork can be dropped in later
// without touching layout code.
//
// To use it: save your image as `flutter/assets/banner.png`. It is picked up
// automatically. Until then a neutral placeholder is drawn so the slot is
// visible during design review.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';

/// Drop your banner artwork here (relative to `flutter/`).
const String kDeskyarBannerAsset = 'assets/banner.png';

class DeskyarBannerSlot extends StatelessWidget {
  const DeskyarBannerSlot({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Leave the same side margin the cards above use, so the banner lines
        // up with them instead of touching the pane edges.
        final width =
            (constraints.maxWidth - 24).clamp(80.0, 400.0).toDouble();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: width,
              height: width * 0.5625, // 16:9
              child: Image.asset(
                kDeskyarBannerAsset,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(context),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _placeholder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = MyTheme.accent;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: isDark
              ? [const Color(0xFF10323F), const Color(0xFF0B3A47)]
              : [const Color(0xFFEAF7F5), const Color(0xFFDDF1EE)],
        ),
        border: Border.all(color: accent.withOpacity(0.35), width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined,
                size: 22, color: accent.withOpacity(0.75)),
            const SizedBox(height: 6),
            Text(
              'جایگاه بنر',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'assets/banner.png',
              style: TextStyle(
                fontSize: 9.5,
                color: accent.withOpacity(0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
