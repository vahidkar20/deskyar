// A small, dependency-free HTML renderer for the ad slot.
//
// The slot has to show "whatever is on the page". The page is served as
// `text/html`, so an image decoder can never read it, and the creative may be
// anything from a single linked logo (what ad.yar.one serves today) to a
// headline + paragraph + button. This file turns the markup into a handful of
// layout blocks that Flutter can paint natively.
//
// ## Scope
//
// This is deliberately *not* a browser. It understands the subset an ad page
// actually uses:
//
//   * block structure: p, div, section, article, header, footer, main, aside,
//     nav, ul/ol/li, blockquote, figure, h1-h6, br, hr
//   * images (`<img src alt>`), including the anchor that wraps them
//   * links (`<a href>`) and button-like anchors (class `btn`/`button`/`cta`,
//     or a background colour in the inline style)
//   * inline emphasis: b/strong/i/em, plus `color`, `font-size`,
//     `font-weight`, `text-align` from a `style="..."` attribute
//   * the page's own `dir`, `lang`, `<title>`, and the `body` background/text
//     colours from a `<style>` block
//
// Scripts, stylesheets beyond the body colours, layout (flex/grid/position),
// web fonts, video and forms are ignored - if the ad ever needs those, it needs
// a real WebView, and the trade-off is documented in banner_slot.dart.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// A block of the rendered document.
abstract class AdBlock {
  const AdBlock({this.spacingBefore = 0});

  /// Vertical gap above the block, in logical pixels.
  final double spacingBefore;
}

/// A styled run inside a text block.
class AdTextRun {
  const AdTextRun({
    required this.text,
    this.bold = false,
    this.color,
    this.fontSize,
  });

  final String text;
  final bool bold;
  final Color? color;
  final double? fontSize;
}

class AdTextBlock extends AdBlock {
  const AdTextBlock({
    required this.runs,
    this.align,
    this.href,
    super.spacingBefore,
  });

  final List<AdTextRun> runs;
  final TextAlign? align;
  final Uri? href;

  String get plainText => runs.map((r) => r.text).join();
}

class AdImageBlock extends AdBlock {
  const AdImageBlock({
    required this.url,
    this.alt = '',
    this.href,
    super.spacingBefore,
  });

  final Uri url;
  final String alt;
  final Uri? href;
}

class AdButtonBlock extends AdBlock {
  const AdButtonBlock({
    required this.label,
    this.href,
    super.spacingBefore,
  });

  final String label;
  final Uri? href;
}

class AdDividerBlock extends AdBlock {
  const AdDividerBlock({super.spacingBefore});
}

/// Everything the slot needs to paint one ad page.
class AdDocument {
  const AdDocument({
    required this.blocks,
    this.title = '',
    this.background,
    this.textColor,
    this.textDirection = TextDirection.rtl,
  });

  final List<AdBlock> blocks;
  final String title;
  final Color? background;
  final Color? textColor;
  final TextDirection textDirection;

  bool get isEmpty => blocks.isEmpty;

  /// A page that is just one image needs no paper, padding or border - the
  /// artwork is the card, exactly as the page renders it.
  bool get isImageOnly => blocks.length == 1 && blocks.first is AdImageBlock;

  AdDocument withImageUrls(Uri Function(Uri) transform) {
    final mapped = blocks.map((block) {
      if (block is AdImageBlock) {
        return AdImageBlock(
          url: transform(block.url),
          alt: block.alt,
          href: block.href,
          spacingBefore: block.spacingBefore,
        );
      }
      return block;
    }).toList();
    return AdDocument(
      blocks: mapped,
      title: title,
      background: background,
      textColor: textColor,
      textDirection: textDirection,
    );
  }
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/// Parse [html] into a renderable document. Never throws: anything it cannot
/// understand is skipped, and a page with no usable content yields an empty
/// document that the caller renders as its fallback.
AdDocument parseAdDocument(String html, Uri base) {
  final title = _cleanText(_firstGroup(
        RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false)
            .firstMatch(html),
        1,
      ));
  final css = _styleSheets(html);
  final body = _bodyStyles(css);
  final direction = _textDirection(html);

  final parser = _HtmlBlockParser(base);
  parser.parse(_stripNonContent(html));

  var blocks = parser.blocks;
  if (blocks.isEmpty && title.isNotEmpty) {
    blocks = [
      AdTextBlock(
        runs: [AdTextRun(text: title, bold: true)],
        align: TextAlign.center,
      ),
    ];
  }
  return AdDocument(
    blocks: blocks,
    title: title,
    background: body.background,
    textColor: body.color,
    textDirection: direction,
  );
}

/// Build a document for a URL that served an image directly.
AdDocument imageDocument(Uri url) => AdDocument(
      blocks: [AdImageBlock(url: url)],
      textDirection: TextDirection.rtl,
    );

class _BodyStyles {
  const _BodyStyles({this.background, this.color});
  final Color? background;
  final Color? color;
}

String _firstGroup(Match? match, int group) =>
    match == null ? '' : (match.group(group) ?? '');

String _stripNonContent(String html) {
  var s = html;
  s = s.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
  s = s.replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ');
  s = s.replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ');
  s = s.replaceAll(RegExp(r'<head[\s\S]*?</head>', caseSensitive: false), ' ');
  s = s.replaceAll(RegExp(r'<title[\s\S]*?</title>', caseSensitive: false), ' ');
  s = s.replaceAll(RegExp(r'<!DOCTYPE[^>]*>', caseSensitive: false), ' ');
  s = s.replaceAll(
      RegExp(r'<(meta|link|base|noscript)\b[^>]*>', caseSensitive: false), ' ');
  return s;
}

String _styleSheets(String html) {
  final buffer = StringBuffer();
  for (final match
      in RegExp(r'<style[^>]*>([\s\S]*?)</style>', caseSensitive: false)
          .allMatches(html)) {
    buffer.writeln(match.group(1));
  }
  return buffer.toString();
}

_BodyStyles _bodyStyles(String css) {
  final rule = RegExp(r'(?:^|[},])\s*body\s*\{([^}]*)\}', caseSensitive: false)
      .firstMatch(css);
  if (rule == null) return const _BodyStyles();
  final declarations = rule.group(1) ?? '';
  final background = _parseColor(
    _declaration(declarations, 'background-color') ??
        _declaration(declarations, 'background'),
  );
  final color = _parseColor(_declaration(declarations, 'color'));
  return _BodyStyles(background: background, color: color);
}

TextDirection _textDirection(String html) {
  final dir = RegExp(r'''dir\s*=\s*["']?(rtl|ltr)''', caseSensitive: false)
      .firstMatch(html);
  final value = dir?.group(1)?.toLowerCase();
  if (value == 'rtl') return TextDirection.rtl;
  if (value == 'ltr') return TextDirection.ltr;
  final lang = RegExp(r'''lang\s*=\s*["']?([a-zA-Z-]+)''', caseSensitive: false)
      .firstMatch(html);
  final code = (lang?.group(1) ?? '').toLowerCase();
  if (const {'fa', 'ar', 'he', 'ur', 'ps', 'sd', 'yi'}.contains(code)) {
    return TextDirection.rtl;
  }
  return TextDirection.ltr;
}

class _Ctx {
  const _Ctx({this.bold = false, this.color, this.fontSize, this.align});

  final bool bold;
  final Color? color;
  final double? fontSize;
  final TextAlign? align;

  _Ctx copyWith({bool? bold, Color? color, double? fontSize, TextAlign? align}) =>
      _Ctx(
        bold: bold ?? this.bold,
        color: color ?? this.color,
        fontSize: fontSize ?? this.fontSize,
        align: align ?? this.align,
      );
}

const Set<String> _blockTags = {
  'p', 'div', 'section', 'article', 'header', 'footer', 'main', 'aside', 'nav',
  'ul', 'ol', 'li', 'blockquote', 'figure', 'figcaption', 'table', 'tr', 'td',
  'th', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
};

const Set<String> _inlineTags = {
  'b', 'strong', 'i', 'em', 'span', 'font', 'small', 'u', 'label',
};

class _HtmlBlockParser {
  _HtmlBlockParser(this.base);

  final Uri base;
  final List<AdBlock> blocks = [];
  final List<AdTextRun> _runs = [];
  final List<String> _hrefs = [];
  final List<MapEntry<String, _Ctx>> _ctx = [];
  _Ctx _current = const _Ctx();
  int _buttonHrefDepth = -1;

  void parse(String html) {
    final tagRe = RegExp(r'<(/)?([a-zA-Z][a-zA-Z0-9:-]*)([^>]*)>');
    var last = 0;
    for (final match in tagRe.allMatches(html)) {
      if (match.start > last) {
        _appendText(html.substring(last, match.start));
      }
      last = match.end;
      final closing = match.group(1) == '/';
      final name = (match.group(2) ?? '').toLowerCase();
      final attrs = match.group(3) ?? '';
      if (closing) {
        _closeTag(name);
      } else {
        _openTag(name, attrs);
      }
    }
    if (last < html.length) _appendText(html.substring(last));
    _flushText();
  }

  // -- text ----------------------------------------------------------------

  static const Set<String> _noSpaceBefore = {
    ',', '.', ';', ':', '!', '?', '،', '؛', '»', ')', ']', '}', '٪', '%',
  };

  void _appendText(String raw) {
    final text = _cleanText(raw);
    if (text.isEmpty) return;
    final needsSpace = _runs.isNotEmpty &&
        !_runs.last.text.endsWith(' ') &&
        !_noSpaceBefore.contains(text[0]);
    final chunk = needsSpace ? ' $text' : text;
    if (_runs.isNotEmpty &&
        _runs.last.bold == _current.bold &&
        _runs.last.color == _current.color &&
        _runs.last.fontSize == _current.fontSize) {
      final last = _runs.removeLast();
      _runs.add(AdTextRun(
        text: last.text + chunk,
        bold: last.bold,
        color: last.color,
        fontSize: last.fontSize,
      ));
    } else {
      _runs.add(AdTextRun(
        text: chunk,
        bold: _current.bold,
        color: _current.color,
        fontSize: _current.fontSize,
      ));
    }
  }

  void _flushText({bool asButton = false}) {
    if (_runs.isEmpty) return;
    final runs = List<AdTextRun>.from(_runs);
    _runs.clear();
    final href = _resolve(_hrefs.isEmpty ? null : _hrefs.last);
    if (asButton) {
      final label = runs.map((r) => r.text).join().trim();
      if (label.isNotEmpty) {
        blocks.add(AdButtonBlock(
          label: label,
          href: href,
          spacingBefore: blocks.isEmpty ? 0 : 8,
        ));
      }
      return;
    }
    final text = runs.map((r) => r.text).join().trim();
    if (text.isEmpty) return;
    blocks.add(AdTextBlock(
      runs: runs,
      align: _current.align,
      href: href,
      spacingBefore: blocks.isEmpty ? 0 : 8,
    ));
  }

  // -- tags ----------------------------------------------------------------

  void _openTag(String name, String attrs) {
    if (name == 'br') {
      _flushText();
      return;
    }
    if (name == 'hr') {
      _flushText();
      blocks.add(AdDividerBlock(spacingBefore: blocks.isEmpty ? 0 : 10));
      return;
    }
    if (name == 'img') {
      _flushText();
      _addImage(attrs);
      return;
    }
    if (name == 'a') {
      final href = _htmlAttr(attrs, 'href') ?? '';
      final classes = (_htmlAttr(attrs, 'class') ?? '').toLowerCase();
      final style = _htmlAttr(attrs, 'style') ?? '';
      final isButton = _isButtonLike(classes, style);
      // Flush before the anchor is pushed: text that precedes the link belongs
      // to the enclosing scope, not to this href.
      if (isButton) _flushText();
      _hrefs.add(href);
      if (isButton) _buttonHrefDepth = _hrefs.length;
      return;
    }
    if (name == 'body') {
      final style = _htmlAttr(attrs, 'style');
      if (style != null) _current = _applyInlineStyle(_current, style);
      return;
    }
    if (!_blockTags.contains(name) && !_inlineTags.contains(name)) return;

    if (_blockTags.contains(name)) _flushText();
    _ctx.add(MapEntry(name, _current));

    var next = _current;
    final heading = _headingSize(name);
    if (heading != null) {
      next = next.copyWith(fontSize: heading, bold: true);
    }
    next = _applyInlineStyle(next, _htmlAttr(attrs, 'style'));
    _current = next;
  }

  void _closeTag(String name) {
    if (name == 'a') {
      final isButton = _buttonHrefDepth == _hrefs.length;
      _flushText(asButton: isButton);
      if (isButton) _buttonHrefDepth = -1;
      if (_hrefs.isNotEmpty) _hrefs.removeLast();
      return;
    }
    if (name == 'body') return;
    if (!_blockTags.contains(name) && !_inlineTags.contains(name)) return;

    if (_blockTags.contains(name)) _flushText();

    // Restore the context captured when this tag opened. Searching instead of
    // assuming the top of the stack keeps a stray closing tag from wiping the
    // styles of its parents.
    for (var i = _ctx.length - 1; i >= 0; i--) {
      if (_ctx[i].key == name) {
        _current = _ctx[i].value;
        _ctx.removeRange(i, _ctx.length);
        break;
      }
    }
  }

  void _addImage(String attrs) {
    final src = _htmlAttr(attrs, 'src');
    final url = _resolve(src);
    if (url == null) return;
    blocks.add(AdImageBlock(
      url: url,
      alt: _cleanText(_htmlAttr(attrs, 'alt') ?? ''),
      href: _resolve(_hrefs.isEmpty ? null : _hrefs.last),
      spacingBefore: blocks.isEmpty ? 0 : 8,
    ));
  }

  bool _isButtonLike(String classes, String style) {
    if (classes.contains('btn') ||
        classes.contains('button') ||
        classes.contains('cta')) {
      return true;
    }
    final background = _declaration(style, 'background-color') ??
        _declaration(style, 'background');
    return background != null && _parseColor(background) != null;
  }

  _Ctx _applyInlineStyle(_Ctx ctx, String? style) {
    if (style == null || style.trim().isEmpty) return ctx;
    var out = ctx;
    final color = _parseColor(_declaration(style, 'color'));
    if (color != null) out = out.copyWith(color: color);
    final size = _parseLength(_declaration(style, 'font-size'));
    if (size != null) out = out.copyWith(fontSize: size.clamp(9.0, 30.0));
    final weight = _declaration(style, 'font-weight');
    if (weight != null) {
      final numeric = int.tryParse(weight.trim());
      if (weight.contains('bold') || (numeric != null && numeric >= 600)) {
        out = out.copyWith(bold: true);
      }
    }
    final align = _declaration(style, 'text-align');
    if (align != null) out = out.copyWith(align: _textAlign(align));
    return out;
  }

  Uri? _resolve(String? reference) {
    if (reference == null) return null;
    final trimmed = reference.trim();
    if (trimmed.isEmpty) return null;
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) return null;
    final resolved = base.resolveUri(parsed);
    if (resolved.scheme != 'http' && resolved.scheme != 'https') return null;
    return resolved;
  }
}

double? _headingSize(String tag) {
  switch (tag) {
    case 'h1':
      return 19;
    case 'h2':
      return 17;
    case 'h3':
      return 15.5;
    case 'h4':
      return 14.5;
    case 'h5':
      return 14;
    case 'h6':
      return 13.5;
  }
  return null;
}

TextAlign? _textAlign(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.contains('center')) return TextAlign.center;
  if (value.contains('right')) return TextAlign.right;
  if (value.contains('left')) return TextAlign.left;
  return null;
}

String? _htmlAttr(String tag, String name) {
  final pattern = RegExp(
    r'''(?:^|\s)''' + name + r'''\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
    caseSensitive: false,
  );
  final match = pattern.firstMatch(tag);
  if (match == null) return null;
  return match.group(1) ?? match.group(2) ?? match.group(3);
}

String? _declaration(String declarations, String name) {
  final pattern = RegExp(
    r'(?:^|;)\s*' + RegExp.escape(name) + r'\s*:\s*([^;]+)',
    caseSensitive: false,
  );
  final match = pattern.firstMatch(declarations);
  return match?.group(1)?.trim();
}

double? _parseLength(String? raw) {
  if (raw == null) return null;
  final match = RegExp(r'([\d.]+)\s*(px|pt|em|rem)?', caseSensitive: false)
      .firstMatch(raw.toLowerCase());
  if (match == null) return null;
  final value = double.tryParse(match.group(1) ?? '');
  if (value == null) return null;
  final unit = (match.group(2) ?? 'px').toLowerCase();
  if (unit == 'em' || unit == 'rem') return value * 13;
  if (unit == 'pt') return value * 1.333;
  return value;
}

Color? _parseColor(String? raw) {
  if (raw == null) return null;
  var value = raw.trim().toLowerCase();
  if (value.isEmpty) return null;
  if (value.startsWith('#')) {
    value = value.substring(1);
    if (value.length == 3) {
      value = value.split('').map((c) => '$c$c').join();
    }
    if (value.length == 6) value = 'ff$value';
    if (value.length != 8) return null;
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? null : Color(parsed);
  }
  final rgb =
      RegExp(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)').firstMatch(value);
  if (rgb != null) {
    final r = int.tryParse(rgb.group(1) ?? '');
    final g = int.tryParse(rgb.group(2) ?? '');
    final b = int.tryParse(rgb.group(3) ?? '');
    if (r == null || g == null || b == null) return null;
    return Color.fromARGB(255, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
  }
  const named = {
    'white': Color(0xFFFFFFFF),
    'black': Color(0xFF000000),
    'red': Color(0xFFE53935),
    'green': Color(0xFF2E7D32),
    'blue': Color(0xFF1565C0),
    'orange': Color(0xFFEF6C00),
    'gray': Color(0xFF757575),
    'grey': Color(0xFF757575),
    'silver': Color(0xFFBDBDBD),
    'teal': Color(0xFF00897B),
    'navy': Color(0xFF1A237E),
    'yellow': Color(0xFFF9A825),
    'transparent': null,
  };
  return named.containsKey(value) ? named[value] : null;
}

/// Decode entities and collapse whitespace.
String _cleanText(String input) {
  var text = input
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&hellip;', '…')
      .replaceAll('&mdash;', '—')
      .replaceAll('&ndash;', '–');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

/// Paints an [AdDocument] at [width] logical pixels.
class AdDocumentView extends StatelessWidget {
  const AdDocumentView({
    Key? key,
    required this.document,
    required this.width,
  }) : super(key: key);

  final AdDocument document;
  final double width;

  static const Color _paper = Color(0xFFF5F7FA);
  static const Color _ink = Color(0xFF16232B);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = MyTheme.accent;
    final imageOnly = document.isImageOnly;
    final padding = imageOnly ? 0.0 : 10.0;
    final inner = math.max(24.0, width - padding * 2);

    if (imageOnly) {
      // The artwork is the card: no paper, no padding, no border.
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final block in document.blocks)
              _buildBlock(block, inner, accent, Colors.white),
          ],
        ),
      );
    }

    final paper = document.background ?? _paper;
    final ink = document.textColor ?? _ink;
    // Keep the page's own colours, but do not let a near-white page become a
    // glaring slab inside a dark window: there the theme surface wins and the
    // text colour is inverted to stay readable.
    final usePaper = !(paper.computeLuminance() > 0.5 && isDark);
    final surface = usePaper ? paper : const Color(0xFF10232C);
    final textColor = usePaper ? ink : Colors.white.withOpacity(0.92);

    return Directionality(
      textDirection: document.textDirection,
      child: Container(
        width: width,
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: usePaper
                ? Colors.black.withOpacity(0.06)
                : accent.withOpacity(0.22),
          ),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: textColor, fontSize: 12.5, height: 1.55),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final block in document.blocks)
                _buildBlock(block, inner, accent, textColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlock(
      AdBlock block, double inner, Color accent, Color textColor) {
    final spacing = block.spacingBefore;
    Widget child;
    if (block is AdTextBlock) {
      child = _text(block);
    } else if (block is AdImageBlock) {
      child = _AdImage(
        // Keyed by URL: when a refresh produces a new (versioned) creative the
        // state must be rebuilt, otherwise the cached provider from the old URL
        // would keep painting the previous artwork.
        key: ValueKey(block.url.toString()),
        url: block.url,
        href: block.href,
        alt: block.alt,
        width: inner,
      );
    } else if (block is AdButtonBlock) {
      child = _button(block, accent);
    } else if (block is AdDividerBlock) {
      child = Container(
        height: 1,
        color: textColor.withOpacity(0.12),
      );
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(top: spacing),
      child: child,
    );
  }

  Widget _text(AdTextBlock block) {
    final spans = <TextSpan>[];
    for (final run in block.runs) {
      spans.add(TextSpan(
        text: run.text,
        style: TextStyle(
          fontWeight: run.bold ? FontWeight.w700 : null,
          color: run.color,
          fontSize: run.fontSize,
        ),
      ));
    }
    final text = Text.rich(
      TextSpan(children: spans),
      textAlign: block.align ?? TextAlign.start,
      maxLines: 6,
      overflow: TextOverflow.ellipsis,
    );
    if (block.href == null) return text;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => openAdLink(block.href!),
        child: text,
      ),
    );
  }

  Widget _button(AdButtonBlock block, Color accent) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        block.label,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    if (block.href == null) {
      return Align(alignment: AlignmentDirectional.centerStart, child: pill);
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => openAdLink(block.href!),
          child: pill,
        ),
      ),
    );
  }
}

/// Opens an ad click-through in the user's browser.
Future<void> openAdLink(Uri target) async {
  try {
    await launchUrlString(target.toString());
  } catch (_) {
    // A missing browser association is not worth an error dialog for an ad.
  }
}

class _AdImage extends StatefulWidget {
  const _AdImage({
    Key? key,
    required this.url,
    required this.width,
    this.href,
    this.alt = '',
  }) : super(key: key);

  final Uri url;
  final Uri? href;
  final String alt;
  final double width;

  @override
  State<_AdImage> createState() => _AdImageState();
}

class _AdImageState extends State<_AdImage> {
  late final ImageProvider _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  double _ratio = 1.0;
  bool _failed = false;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _provider = NetworkImage(widget.url.toString());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  void _resolve() {
    final stream = _provider.resolve(createLocalImageConfiguration(context));
    if (_stream?.key == stream.key) return;
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _listener = ImageStreamListener(
      (info, _) {
        if (info.image.height == 0) return;
        final ratio = info.image.width / info.image.height;
        if (!mounted || (ratio - _ratio).abs() < 0.01) return;
        // The listener can fire synchronously while the tree is building, so
        // the ratio is applied after the frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _ratio = ratio);
        });
      },
      onError: (error, stack) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _failed = true);
        });
      },
    );
    stream.addListener(_listener!);
    _stream = stream;
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = MyTheme.accent;
    final height = (widget.width / _ratio).clamp(48.0, 360.0).toDouble();
    final image = SizedBox(
      height: height,
      width: widget.width,
      child: _failed
          ? _broken(accent)
          : Image(
              image: _provider,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stack) => _broken(accent),
            ),
    );

    Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          image,
          if (_hover && widget.href != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: accent.withOpacity(0.6)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (widget.href == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => openAdLink(widget.href!),
        child: card,
      ),
    );
  }

  Widget _broken(Color accent) {
    return Container(
      color: accent.withOpacity(0.08),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported_outlined,
                size: 22, color: accent.withOpacity(0.6)),
            if (widget.alt.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                widget.alt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: accent.withOpacity(0.7)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
