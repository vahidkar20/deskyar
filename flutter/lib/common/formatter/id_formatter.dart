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

String formatID(String id) {
  String id2 = id.replaceAll(' ', '');
  String suffix = '';
  if (id2.endsWith(r'\r') || id2.endsWith(r'/r')) {
    suffix = id2.substring(id2.length - 2, id2.length);
    id2 = id2.substring(0, id2.length - 2);
  }
  if (int.tryParse(id2) == null) return id;
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

String trimID(String id) {
  return id.replaceAll(' ', '');
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

/// Whether the current UI locale is right-to-left.
bool get isRtlLocale {
  final code = Get.locale?.languageCode ?? '';
  return const ['fa', 'ar', 'he', 'ur', 'ps', 'sd', 'yi'].contains(code);
}

/// Render an ID so its digits always read left-to-right.
///
/// ## The bug this fixes
///
/// DeskYar runs in Persian, so the whole app is laid out right-to-left. The
/// Unicode bidirectional algorithm treats a run of digits inside an RTL
/// paragraph as *right-to-left* text, because digits carry the "EN" (European
/// Number) class and the resolved paragraph direction is RTL. The result is
/// that `41025697` is painted as `79652014` - the digits are visually
/// reversed while the underlying string is untouched.
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
