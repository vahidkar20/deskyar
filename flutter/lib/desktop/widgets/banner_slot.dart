// Reserved banner slot in the home page's left pane.
//
// The artwork is fetched from the ad server at runtime, so the creative can be
// changed without shipping a new build. Anything the server returns as an image
// works (png/jpg/webp/gif), including an HTTP redirect to one.
//
// The slot is a 240x240 square - design the creative at that ratio. It only
// shrinks below 240 when the window is too narrow, never grows past it.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';

/// Where the banner is served from.
const String kDeskyarBannerUrl = 'https://ad.yar.one';

/// Edge of the banner square, in logical pixels.
const double kDeskyarBannerSize = 240;

class DeskyarBannerSlot extends StatelessWidget {
  const DeskyarBannerSlot({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The pane is 264 wide, so 240 plus the 12px margins fits exactly.
        final size = math
            .min(kDeskyarBannerSize, constraints.maxWidth - 24)
            .clamp(72.0, kDeskyarBannerSize)
            .toDouble();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: SizedBox(
              width: size,
              height: size,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  kDeskyarBannerUrl,
                  fit: BoxFit.cover,
                  // Keeps the previous frame visible while a new one decodes,
                  // so the pane does not flicker on refresh.
                  gaplessPlayback: true,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return _Loading(size: size);
                  },
                  errorBuilder: (context, error, stack) =>
                      _Fallback(size: size),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = MyTheme.accent;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10323F) : const Color(0xFFEAF7F5),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: accent),
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = MyTheme.accent;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: isDark
              ? [const Color(0xFF10323F), const Color(0xFF0B3A47)]
              : [const Color(0xFFEAF7F5), const Color(0xFFDDF1EE)],
        ),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.campaign_outlined,
                size: 26, color: accent.withOpacity(0.7)),
            const SizedBox(height: 8),
            Text(
              'جایگاه بنر',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'ad.yar.one',
              style: TextStyle(
                fontSize: 10,
                color: accent.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
