import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class IDTextEditingController extends TextEditingController {
  IDTextEditingController({String? text}) : super(text: text);

  String get id => trimID(value.text);

  set id(String newID) => text = formatID(newID);
}

class IDTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    } else if (newValue.text.compareTo(oldValue.text) == 0) {
      return newValue;
    } else {
      int selectionIndexFromTheRight =
          newValue.text.length - newValue.selection.extentOffset;
      String newID = formatID(newValue.text);
      return TextEditingValue(
        text: newID,
        selection: TextSelection.collapsed(
          offset: newID.length - selectionIndexFromTheRight,
        ),
        // https://github.com/flutter/flutter/issues/78066#issuecomment-797869906
        composing: newValue.composing,
      );
    }
  }
}

/// Format an ID with a space every three digits, for readability.
///
/// Bidi control characters are stripped first. This is not cosmetic: an ID
/// copied out of a [LtrIdText] - or out of any Persian sentence wrapped by
/// [ltrIsolate] - carries U+2066/U+2069. Left in place they make
/// `int.tryParse` fail, so the grouping below would be skipped *and* the
/// control characters would be sent to the server as part of the ID, which
/// never matches a real peer.
String formatID(String id) {
  String id2 = stripBidiIsolates(id).replaceAll(' ', '');
  String suffix = '';
  if (id2.endsWith(r'\r') || id2.endsWith(r'/r')) {
    suffix = id2.substring(id2.length - 2, id2.length);
    id2 = id2.substring(0, id2.length - 2);
  }
  // A custom ID can contain letters, in which case there is nothing to group -
  // but the isolates still have to go, or they leak into the connection.
  if (int.tryParse(id2) == null) return stripBidiIsolates(id);
  String newID = '';
  if (id2.length <= 3) {
    newID = id2;
  } else {
    var n = id2.length;
    var a = n % 3 != 0 ? n % 3 : 3;
    newID = id2.substring(0, a);
    for (var i = a; i < n; i += 3) {
      newID += " ${id2.substring(i, i + 3)}";
    }
  }
  return newID + suffix;
}

/// Reduce a displayed ID to the value that actually identifies a peer.
///
/// Removes the grouping spaces *and* the invisible bidi isolates, so the result
/// can be sent over the wire as-is. Every place that copies an ID or hands one
/// to `connect()` must go through this.
String trimID(String id) {
  return stripBidiIsolates(id).replaceAll(' ', '');
}

/// Wrap a numeric ID in the Unicode LEFT-TO-RIGHT isolate so it keeps its
/// digit order when embedded in a Persian sentence.
///
/// Use this for *strings* that mix an ID with RTL text, e.g.
/// `'${translate('Connect')} ${ltrIsolate(peer.id)}'`. The isolate is
/// invisible, so the sentence still reads naturally, but the number inside it
/// is laid out left-to-right.
///
/// For a standalone ID, prefer [LtrIdText], which additionally controls the
/// alignment of the whole widget.
String ltrIsolate(String id) {
  if (id.isEmpty) return id;
  // U+2066 LEFT-TO-RIGHT ISOLATE, U+2069 POP DIRECTIONAL ISOLATE.
  return '\u2066$id\u2069';
}

/// Strip the bidi isolate characters added by [ltrIsolate] and [LtrIdText].
///
/// Use this on text that is copied to the clipboard or sent to a peer, so the
/// invisible control characters never leak into the value.
String stripBidiIsolates(String text) {
  return text.replaceAll('\u2066', '').replaceAll('\u2069', '');
}

/// The locale the UI is actually running in.
///
/// `Get.locale` is not reliable here: `GetMaterialApp` receives an explicit
/// `locale:` argument but does not necessarily publish it back through GetX
/// before the first frame, so reading it alone can answer "not RTL" while the
/// whole app is laid out right-to-left. `getDeskyarLocale` writes the resolved
/// value here, which makes [isRtlLocale] independent of GetX's timing.
Locale deskyarUiLocale = const Locale('fa');

/// Whether the current UI locale is right-to-left.
///
/// Used only for *layout* decisions (isolates, alignment). Anything that
/// formats a number must not depend on it - see [kNumberTextDirection].
bool get isRtlLocale {
  final code = deskyarUiLocale.languageCode.isNotEmpty
      ? deskyarUiLocale.languageCode
      : (Get.locale?.languageCode ?? '');
  return const ['fa', 'ar', 'he', 'ur', 'ps', 'sd', 'yi'].contains(code);
}

/// Text direction for anything that shows or edits a number.
///
/// Always left-to-right, in every locale. The Unicode bidi algorithm orders a
/// digit run by the *paragraph* direction, so an ID such as `205 912 679` -
/// grouped with spaces by [formatID] - is painted `679 912 205` inside an RTL
/// paragraph, and every keystroke lands in the wrong visual place. Pinning the
/// field to LTR is the only fix that does not depend on locale detection.
const TextDirection kNumberTextDirection = TextDirection.ltr;

/// Render an ID so its digits always read left-to-right.
///
/// ## The bug this fixes
///
/// DeskYar runs in Persian, so the whole app is laid out right-to-left. An ID
/// is grouped into three-digit blocks by [formatID] (`410 256 978`), and the
/// spaces between those blocks are *neutral* characters: the bidi algorithm
/// resolves them to the paragraph direction, which splits the ID into three
/// separate number runs and lays them out right-to-left. The digits inside each
/// block keep their order, but the blocks swap places, so `410 256 978` is
/// painted `978 256 410`. An ungrouped ID (`410256978`) is a single run and
/// survives intact - which is why the bug only shows up in the formatted
/// fields.
///
/// That is not cosmetic. A user who reads their own ID off the screen types
/// the reversed number, the other side never connects, and neither party can
/// tell whether the ID was mistyped or merely displayed backwards. It also
/// makes "copy this ID" worthless, because the user cannot verify the digits
/// they pasted.
///
/// ## The fix
///
/// Wrap the text in a `Directionality` with `TextDirection.ltr` and bracket it
/// with the Unicode LEFT-TO-RIGHT / RIGHT-TO-LEFT *embedding* isolates
/// (U+2066 / U+2069). The isolates are what make this safe in an RTL
/// paragraph: they tell the bidi algorithm "treat the enclosed run as a
/// self-contained LTR segment", so neighbouring Persian text no longer leaks
/// into the number and the digits keep their true order.
///
/// The embedding characters are invisible, but they do end up in the copied
/// text, so this helper is only for *display*. Copy actions should use
/// [trimID] on the raw value instead.
class LtrIdText extends StatelessWidget {
  const LtrIdText(
    this.id, {
    Key? key,
    this.style,
    this.textAlign,
    this.maxLines = 1,
    this.overflow = TextOverflow.clip,
    this.fontFamily,
  }) : super(key: key);

  final String id;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int maxLines;
  final TextOverflow overflow;
  final String? fontFamily;

  /// U+2066 LEFT-TO-RIGHT ISOLATE and U+2069 POP DIRECTIONAL ISOLATE.
  static const String _lri = '\u2066';
  static const String _pdi = '\u2069';

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = (style ??
            const TextStyle(fontSize: 13))
        .copyWith(fontFamily: fontFamily);
    // Only wrap when the ambient locale is RTL. In an LTR locale the digits
    // already read correctly and the isolate characters would be noise.
    if (!isRtlLocale) {
      return Text(
        id,
        style: effectiveStyle,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      );
    }
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(
        '$_lri$id$_pdi',
        style: effectiveStyle,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}
