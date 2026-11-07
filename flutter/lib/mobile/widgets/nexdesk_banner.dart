import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/widgets/ad_creative.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:url_launcher/url_launcher.dart';

/// Promo banner for the mobile home screen.
///
/// The desktop banner renders HTML in a pane of its own; mobile paints one
/// image. Both read the same live ad slot, and neither has the creative baked
/// into the build.
///
/// The creative is not a plain image URL: `ad.yar.one` answers `/` with a shell
/// that loads a script, and the script `document.write`s the markup. Requesting
/// `/banner.png` - which is what this widget used to do - returns 404, so the
/// banner silently hid itself. [resolveAdCreative] follows the script and hands
/// back the real image, which is why this widget resolves asynchronously and
/// renders nothing until it has something to show.
class NexDeskBanner extends StatefulWidget {
  const NexDeskBanner({super.key});

  @override
  State<NexDeskBanner> createState() => _NexDeskBannerState();
}

class _NexDeskBannerState extends State<NexDeskBanner> {
  static const _dismissKey = 'nexdesk-mobile-banner-dismissed';

  /// The ad slot, not the image. Resolved at runtime - see ad_creative.dart.
  static const _pageUrl = 'https://ad.yar.one';

  static const _fallbackTarget = 'https://nexdesk.ir';

  AdCreative? _creative;
  bool _visible = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // A new creative re-shows a previously dismissed card: the stored value is
    // the creative's URL, so replacing the artwork on the server is enough to
    // bring the banner back.
    _visible = bind.mainGetLocalOption(key: _dismissKey) != _pageUrl;
    if (_visible) _resolve();
  }

  Future<void> _resolve() async {
    final creative = await resolveAdCreative(Uri.parse(_pageUrl));
    if (!mounted) return;
    if (creative == null) {
      setState(() => _failed = true);
      return;
    }
    setState(() => _creative = creative);
  }

  Future<void> _dismiss() async {
    setState(() => _visible = false);
    await bind.mainSetLocalOption(key: _dismissKey, value: _pageUrl);
  }

  @override
  Widget build(BuildContext context) {
    final creative = _creative;
    if (!_visible || _failed || creative == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => launchUrl(creative.target ?? Uri.parse(_fallbackTarget)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                creative.image.toString(),
                width: double.infinity,
                // The creative is a portrait poster, not a strip: `cover` in a
                // short slot would crop the artwork down to a slice of its
                // middle. `contain` inside a capped height keeps the whole
                // image visible instead.
                height: 200,
                fit: BoxFit.contain,
                // A missing or blocked banner must not leave a hole in the UI.
                errorBuilder: (_, __, ___) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _failed = true);
                  });
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
          PositionedDirectional(
            top: 2,
            end: 2,
            child: IconButton(
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              tooltip: isRtlLocale ? 'بستن' : 'Dismiss',
              // A shadow, because the close button sits on the artwork and a
              // light creative would swallow a plain white glyph.
              icon: const Icon(Icons.close,
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)]),
              onPressed: _dismiss,
            ),
          ),
        ],
      ),
    );
  }
}
