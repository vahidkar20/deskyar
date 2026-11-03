// Live ad slot for the home page's left pane.
//
// The creative is not baked into the build. The slot fetches the ad URL at
// runtime and paints whatever it finds:
//
//   * `Content-Type: image/*`  -> the response is the creative.
//   * `Content-Type: text/html` -> the markup is parsed into layout blocks by
//     ad_document.dart (headline, paragraph, image, link, button, ...).
//
// ## Why not `Image.network(pageUrl)`
//
// That was the original implementation, and it can never work: ad.yar.one
// serves `text/html`, and an image decoder cannot read HTML, so the slot
// silently fell through to its placeholder. Fetching the markup and rendering
// the blocks natively fixes it without pulling a browser engine into the main
// window.
//
// ## Why not a WebView
//
// A real browser would render arbitrary HTML pixel-for-pixel, but it adds a
// native plugin (WebView2), a second process and a large attack surface to the
// window that holds the user's session, and it cannot be verified without a
// Windows build of this fork. ad_document.dart covers the markup an ad page
// actually uses. If the ad ever needs flexbox/grid/video, that is the moment to
// revisit the WebView trade-off - not before.
//
// ## Responsiveness
//
// The slot is as wide as the pane allows (capped at [kDeskyarBannerWidth]); the
// document's height comes from its own content, and image heights come from the
// decoded aspect ratio, so nothing is stretched or letterboxed.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/widgets/ad_document.dart';
import 'package:http/http.dart' as http;

/// Where the ad page is served from.
const String kDeskyarBannerUrl = 'https://ad.yar.one';

/// Maximum width of the slot, in logical pixels.
const double kDeskyarBannerWidth = 240;

/// How often the creative is re-fetched while the window stays open.
const Duration kDeskyarBannerRefresh = Duration(minutes: 5);

/// How many images in a document get a cache-busting version. An ad has one
/// hero image; the cap keeps a pathological page from costing a dozen HEADs.
const int _kMaxVersionedImages = 3;

/// The banner slot itself.
class DeskyarBannerSlot extends StatefulWidget {
  const DeskyarBannerSlot({Key? key}) : super(key: key);

  @override
  State<DeskyarBannerSlot> createState() => _DeskyarBannerSlotState();
}

class _DeskyarBannerSlotState extends State<DeskyarBannerSlot>
    with WidgetsBindingObserver {
  AdDocument? _document;
  bool _loading = true;
  String _error = '';
  Timer? _refreshTimer;
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Deferred by one microtask: `_load` calls setState immediately when it is
    // not silent, and mutating state while initState is still on the stack is
    // needless risk. The slot already renders its skeleton for this frame.
    Future.microtask(_load);
    _refreshTimer = Timer.periodic(
      kDeskyarBannerRefresh,
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app is the most likely moment for the creative to
    // have changed, and it costs one request.
    if (state == AppLifecycleState.resumed) {
      _load(silent: true);
    }
  }

  Future<void> _load({bool silent = false}) async {
    final seq = ++_requestSeq;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }
    try {
      // Normalise to an absolute path so relative `src="logo.png"` in the
      // markup resolves to `https://host/logo.png` rather than to a path that
      // depends on how the base URL was written.
      final parsedBase = Uri.parse(kDeskyarBannerUrl);
      final base =
          parsedBase.path.isEmpty ? parsedBase.replace(path: '/') : parsedBase;
      // A cache-busting parameter keeps an intermediate proxy from pinning an
      // old creative; the server ignores unknown query keys.
      final uri = base.replace(queryParameters: {
        ...base.queryParameters,
        '_': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      final response = await http
          .get(uri, headers: const {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          })
          .timeout(const Duration(seconds: 10));
      if (!mounted || seq != _requestSeq) return;
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final contentType =
          (response.headers['content-type'] ?? '').toLowerCase();
      var document = contentType.startsWith('image/')
          ? imageDocument(base)
          : parseAdDocument(
              utf8.decode(response.bodyBytes, allowMalformed: true),
              base,
            );

      // Version the image URLs so a creative replaced in place is not served
      // from Flutter's in-memory image cache for the rest of the session.
      final images =
          document.blocks.whereType<AdImageBlock>().take(_kMaxVersionedImages);
      if (images.isNotEmpty) {
        final versions = <String, Uri>{};
        for (final image in images) {
          versions[image.url.toString()] = await _versionImage(image.url);
        }
        if (!mounted || seq != _requestSeq) return;
        document =
            document.withImageUrls((url) => versions[url.toString()] ?? url);
      }

      setState(() {
        _document = document;
        _loading = false;
        _error = '';
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Give an image URL a cache key that changes when the file does.
  ///
  /// The ad server sends `Cache-Control: max-age=604800` for the image, and
  /// Flutter keeps decoded images in memory for the life of the process. A
  /// creative replaced at the same URL would therefore keep showing the old
  /// artwork until the app restarted. Folding the file's own `Last-Modified`
  /// (or `ETag`) into the URL makes a new file a new cache entry, while an
  /// unchanged file still comes straight from the cache.
  Future<Uri> _versionImage(Uri image) async {
    try {
      final head = await http.head(image).timeout(const Duration(seconds: 6));
      final stamp = head.headers['last-modified'] ?? head.headers['etag'];
      if (stamp == null || stamp.isEmpty) return image;
      return image.replace(queryParameters: {
        ...image.queryParameters,
        'v': stamp,
      });
    } catch (_) {
      return image;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : kDeskyarBannerWidth + 24;
        final width = math
            .min(kDeskyarBannerWidth, available - 24)
            .clamp(72.0, kDeskyarBannerWidth)
            .toDouble();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: SizedBox(
              width: width,
              child: _buildSlot(context, width),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSlot(BuildContext context, double width) {
    final document = _document;
    if (_loading && document == null) {
      return _Skeleton(width: width);
    }
    if (document == null || document.isEmpty) {
      return _Fallback(width: width, detail: _error, onRetry: () => _load());
    }
    return _AdCard(document: document, width: width);
  }
}

/// Card chrome around a document: rounded, shadowed, and lifted on hover.
class _AdCard extends StatefulWidget {
  const _AdCard({Key? key, required this.document, required this.width})
      : super(key: key);

  final AdDocument document;
  final double width;

  @override
  State<_AdCard> createState() => _AdCardState();
}

class _AdCardState extends State<_AdCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(_hover ? 0.32 : 0.16),
              blurRadius: _hover ? 18 : 9,
              offset: Offset(0, _hover ? 8 : 4),
            ),
          ],
        ),
        child: AdDocumentView(document: widget.document, width: widget.width),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = MyTheme.accent;
    return Container(
      width: width,
      height: width,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10323F) : const Color(0xFFEAF7F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.18)),
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

/// Shown when the page cannot be reached or carries no usable content. Offers a
/// retry rather than pretending the slot is empty.
class _Fallback extends StatefulWidget {
  const _Fallback({
    required this.width,
    required this.onRetry,
    this.detail = '',
  });

  final double width;
  final VoidCallback onRetry;

  /// Why the slot is empty, surfaced on hover so a support call can start from
  /// "HTTP 502" instead of "the ad is gone".
  final String detail;

  @override
  State<_Fallback> createState() => _FallbackState();
}

class _FallbackState extends State<_Fallback> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = MyTheme.accent;
    final card = Container(
      width: widget.width,
      height: widget.width * 0.75,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: isDark
              ? [const Color(0xFF10323F), const Color(0xFF0B3A47)]
              : [const Color(0xFFEAF7F5), const Color(0xFFDDF1EE)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(_hover ? 0.5 : 0.25)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _hover ? Icons.refresh_rounded : Icons.campaign_outlined,
            size: 24,
            color: accent.withOpacity(0.7),
          ),
          const SizedBox(height: 6),
          Text(
            translate('Banner slot'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _hover ? translate('Click to retry') : 'ad.yar.one',
            style: TextStyle(fontSize: 10, color: accent.withOpacity(0.6)),
          ),
        ],
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onRetry,
        child: widget.detail.isEmpty
            ? card
            : Tooltip(message: widget.detail, child: card),
      ),
    );
  }
}
