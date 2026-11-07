import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:url_launcher/url_launcher.dart';

/// Promo banner for the mobile home screen.
///
/// The desktop banner renders HTML in a WebView, which mobile does not have.
/// This is the image-only equivalent: one cached PNG, one tap target, and a
/// dismiss that is remembered per install. It sits above the device list so it
/// never covers the connect field or the peer cards.
class NexDeskBanner extends StatefulWidget {
  const NexDeskBanner({super.key});

  @override
  State<NexDeskBanner> createState() => _NexDeskBannerState();
}

class _NexDeskBannerState extends State<NexDeskBanner> {
  static const _imageUrl = 'https://ad.yar.one/banner.png';
  static const _targetUrl = 'https://nexdesk.ir';
  static const _dismissKey = 'nexdesk-mobile-banner-dismissed';
  static const _versionKey = 'nexdesk-mobile-banner-version';

  bool _visible = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // A new banner version re-shows a previously dismissed card.
    _visible = bind.mainGetLocalOption(key: _dismissKey) != _imageUrl;
  }

  Future<void> _dismiss() async {
    setState(() => _visible = false);
    await bind.mainSetLocalOption(key: _dismissKey, value: _imageUrl);
    await bind.mainSetLocalOption(key: _versionKey, value: '1');
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible || _failed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => launchUrl(Uri.parse(_targetUrl)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                _imageUrl,
                height: 88,
                width: double.infinity,
                fit: BoxFit.cover,
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
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: _dismiss,
            ),
          ),
        ],
      ),
    );
  }
}
