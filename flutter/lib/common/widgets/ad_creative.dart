// Resolving the creative of a live ad slot.
//
// The desktop slot and the mobile banner both point at `ad.yar.one`, and that
// server does not serve an image. It serves a one-line HTML shell whose only
// content is `<script src=".../serve.php"></script>`, and the script answers
// with:
//
//     document.write("<a href=\".../click.php?id=1\"><img src=\".../banner.php?id=1\" ...></a>");
//
// A static parser sees an empty page: `<script>` is stripped as non-content,
// so the slot fell through to its "Banner slot" placeholder and the mobile
// banner requested a `banner.png` that does not exist (HTTP 404).
//
// This file bridges that gap without a browser engine. It fetches the scripts
// the page pulls in, runs the *one* DOM operation an ad script actually uses -
// `document.write` of a string literal - and hands the resulting markup back
// to the caller. It is not a JavaScript interpreter: a creative that builds
// itself from data, timers or a framework will still not render, and at that
// point the slot needs a WebView (the trade-off is argued in banner_slot.dart).
//
// Security: the fetched script is never executed. Only a literal string handed
// to `document.write`/`writeln` is extracted, and the result is parsed as HTML
// by the same renderer as the page itself. No `eval`, no `dart:js`.

import 'dart:convert';

import 'package:http/http.dart' as http;

/// How many `<script src>` tags are followed. An ad page has one; the cap keeps
/// a pathological page from turning one slot refresh into a dozen requests.
const int kMaxAdScripts = 3;

const Duration _kScriptTimeout = Duration(seconds: 6);

/// The image (and click-through) an ad page ultimately shows.
class AdCreative {
  const AdCreative({required this.image, this.target});

  final Uri image;
  final Uri? target;
}

final RegExp _scriptSrc = RegExp(
  r'''<script\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>\s*</script>''',
  caseSensitive: false,
);

final RegExp _imgSrc = RegExp(
  r'''<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["']''',
  caseSensitive: false,
);

final RegExp _anchorHref = RegExp(
  r'''<a\b[^>]*\bhref\s*=\s*["']([^"']+)["']''',
  caseSensitive: false,
);

/// Replace every `<script src>` in [html] with the markup it writes.
///
/// A script that cannot be fetched, answers with a non-200, or contains no
/// `document.write` is replaced with nothing - the same result a browser would
/// produce for a blocked script, minus the error.
Future<String> inlineAdScripts(String html, Uri base) async {
  final matches = _scriptSrc.allMatches(html).take(kMaxAdScripts).toList();
  if (matches.isEmpty) return html;
  final buffer = StringBuffer();
  var cursor = 0;
  for (final match in matches) {
    buffer.write(html.substring(cursor, match.start));
    cursor = match.end;
    buffer.write(await _fetchWrittenMarkup(match.group(1) ?? '', base));
  }
  buffer.write(html.substring(cursor));
  return buffer.toString();
}

/// Fetch an ad page and return the first creative it displays.
///
/// Used by the mobile banner, which paints one image rather than a document.
/// Returns null when the page carries no image at all, so the caller can hide
/// the slot instead of leaving a hole in the layout.
Future<AdCreative?> resolveAdCreative(Uri page) async {
  try {
    final response = await http.get(page, headers: const {
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
    }).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;

    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    if (contentType.startsWith('image/')) {
      return AdCreative(image: page);
    }

    final html = utf8.decode(response.bodyBytes, allowMalformed: true);
    final markup = await inlineAdScripts(html, page);
    final image = _imgSrc.firstMatch(markup);
    if (image == null) return null;
    final src = _resolve(image.group(1), page);
    if (src == null) return null;
    final anchor = _anchorHref.firstMatch(markup);
    return AdCreative(image: src, target: _resolve(anchor?.group(1), page));
  } catch (_) {
    return null;
  }
}

Future<String> _fetchWrittenMarkup(String reference, Uri base) async {
  final uri = _resolve(reference, base);
  if (uri == null) return '';
  try {
    final response = await http.get(uri, headers: const {
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
    }).timeout(_kScriptTimeout);
    if (response.statusCode != 200) return '';
    return extractDocumentWrites(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
  } catch (_) {
    return '';
  }
}

/// Pull the string literals out of every `document.write(...)` / `writeln(...)`
/// call in [source], concatenated in call order.
///
/// Hand-rolled rather than regex-driven: the argument is a quoted string that
/// itself contains escaped quotes (`\"`), and a pattern that has to match
/// balanced quoting through escapes is exactly where a regex becomes
/// unreadable and subtly wrong.
String extractDocumentWrites(String source) {
  const marker = 'document.write';
  final out = StringBuffer();
  var cursor = 0;
  while (true) {
    final at = source.indexOf(marker, cursor);
    if (at < 0) break;
    var i = at + marker.length;
    if (source.startsWith('ln', i)) i += 2;
    i = _skipSpace(source, i);
    if (i >= source.length || source[i] != '(') {
      cursor = at + marker.length;
      continue;
    }
    i = _skipSpace(source, i + 1);
    if (i >= source.length) break;
    final quote = source[i];
    if (quote != '"' && quote != "'") {
      cursor = i;
      continue;
    }
    final literal = _readStringLiteral(source, i + 1, quote);
    out.writeln(literal.text);
    cursor = literal.end;
  }
  return out.toString();
}

int _skipSpace(String source, int index) {
  while (index < source.length && source[index].trim().isEmpty) {
    index++;
  }
  return index;
}

class _Literal {
  const _Literal(this.text, this.end);
  final String text;
  final int end;
}

/// Read a quoted string starting at [index] (just past the opening quote).
_Literal _readStringLiteral(String source, int index, String quote) {
  final buffer = StringBuffer();
  var i = index;
  while (i < source.length) {
    final char = source[i];
    if (char == '\\' && i + 1 < source.length) {
      final next = source[i + 1];
      if (next == 'u' && i + 5 < source.length) {
        final code = int.tryParse(source.substring(i + 2, i + 6), radix: 16);
        if (code != null) {
          buffer.writeCharCode(code);
          i += 6;
          continue;
        }
      }
      if (next == 'x' && i + 3 < source.length) {
        final code = int.tryParse(source.substring(i + 2, i + 4), radix: 16);
        if (code != null) {
          buffer.writeCharCode(code);
          i += 4;
          continue;
        }
      }
      buffer.write(switch (next) {
        'n' => '\n',
        'r' => '\r',
        't' => '\t',
        'b' => '\b',
        'f' => '\f',
        '0' => '\u0000',
        _ => next,
      });
      i += 2;
      continue;
    }
    if (char == quote) {
      return _Literal(buffer.toString(), i + 1);
    }
    buffer.write(char);
    i++;
  }
  return _Literal(buffer.toString(), i);
}

Uri? _resolve(String? reference, Uri base) {
  if (reference == null) return null;
  final trimmed = reference.trim();
  if (trimmed.isEmpty) return null;
  final parsed = Uri.tryParse(trimmed);
  if (parsed == null) return null;
  final resolved = base.resolveUri(parsed);
  if (resolved.scheme != 'http' && resolved.scheme != 'https') return null;
  return resolved;
}
