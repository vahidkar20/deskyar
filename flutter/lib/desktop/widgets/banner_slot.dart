// Reserved banner slot in the home page's left pane.
//
// The artwork is fetched from the ad server at runtime, so the creative can be
// changed without shipping a new build. Anything the server returns as an image
// works (png/jpg/webp/gif), including an HTTP redirect to one.
//
// ## Sizing
//
// The slot is 240 wide. Its height is driven by the pane's state:
//
//   * **240** (square) in the normal case - the compact "box" placement.
//   * **480** (portrait) while the install prompt is on screen. A portable run
//     that has not been installed yet leaves the pane with a lot of empty
//     vertical space, and a half-page unit fills it instead of leaving a
//     square floating in the middle of nothing.
//
// Width shrinks below 240 only when the window is too narrow to fit it; it
// never grows past 240, because the pane is sized around that figure.
//
// Design the creative at 1:1 for the compact state and 1:2 for the tall one.
// `BoxFit.cover` is used either way, so a single 1:1 image still works in the
// tall slot - it is simply cropped top and bottom.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:get/get.dart';

/// Where the banner is served from.
const String kDeskyarBannerUrl = 'https://ad.yar.one';

/// Edge of the banner square, in logical pixels.
const double kDeskyarBannerWidth = 240;

/// Height in the normal (square) state.
const double kDeskyarBannerHeightCompact = 240;

/// Height while the install prompt is on screen.
const double kDeskyarBannerHeightTall = 480;

/// Whether the install prompt is currently visible.
///
/// `install_banner.dart` owns the real condition (Windows, portable, not
/// dismissed); it publishes the answer here so the banner can react without
/// the two widgets having to share a widget tree. Defaults to false, which is
/// the compact layout.
final RxBool deskyarInstallPromptVisible = false.obs;

class DeskyarBannerSlot extends StatelessWidget {
  const DeskyarBannerSlot({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The pane is 264 wide, so 240 plus the 12px margins fits exactly.
        final width = math
            .min(kDeskyarBannerWidth, constraints.maxWidth - 24)
            .clamp(72.0, kDeskyarBannerWidth)
            .toDouble();
        return Obx(() {
          final tall = deskyarInstallPromptVisible.value;
          final height =
              tall ? kDeskyarBannerHeightTall : kDeskyarBannerHeightCompact;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: AnimatedContainer(
                // Animated so the switch does not jolt the pane when the
                // install prompt appears or is dismissed.
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                width: width,
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.network(
                  kDeskyarBannerUrl,
                  fit: BoxFit.cover,
                  // Keeps the previous frame visible while a new one decodes,
                  // so the pane does not flicker on refresh.
                  gaplessPlayback: true,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return _Loading();
                  },
                  errorBuilder: (context, error, stack) => _Fallback(tall: tall),
                ),
              ),
            ),
          );
        });
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

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
  const _Fallback({required this.tall});
  final bool tall;

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
                size: tall ? 34 : 26, color: accent.withOpacity(0.7)),
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
            if (tall) ...[
              const SizedBox(height: 14),
              Text(
                '۲۴۰ × ۴۸۰',
                style: TextStyle(
                  fontSize: 10,
                  color: accent.withOpacity(0.45),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
