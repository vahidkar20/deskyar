// Guards the privacy constraint on the ad slot.
//
// NexDesk is free and funded by ads, so the slot is not removable. What keeps
// that compatible with the code-signing policy the project applies under is
// that the ad request is anonymous: no device id, install id, user id, session
// token or cookie. If someone adds an identifier to the request - plausibly, to
// "measure impressions better" - this test fails, because that change would
// quietly invalidate the privacy statement on nexdesk.ir.
//
// See the constraint comment on kNexDeskBannerUrl.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/banner_slot.dart';

void main() {
  group('ad request anonymity', () {
    test('carries exactly one query key, the cache-buster', () {
      final ad = nexDeskAdRequest(now: DateTime.fromMillisecondsSinceEpoch(0));

      expect(ad.request.queryParameters.keys.toList(), ['_']);
    });

    test('carries no identifier with a real clock', () {
      final ad = nexDeskAdRequest();

      expect(ad.request.queryParameters, hasLength(1));
      expect(ad.request.queryParameters.containsKey('_'), isTrue);
    });

    test('base is the bare ad host, with no query', () {
      final ad = nexDeskAdRequest();

      expect(ad.base.toString(), 'https://ad.yar.one/');
      expect(ad.base.hasQuery, isFalse);
    });

    test('query does not change scheme, host or path', () {
      final ad = nexDeskAdRequest(now: DateTime.fromMillisecondsSinceEpoch(0));

      expect(ad.request.scheme, 'https');
      expect(ad.request.host, 'ad.yar.one');
      expect(ad.request.path, '/');
      expect(ad.request.hasPort, isFalse);
      expect(ad.request.toString(), 'https://ad.yar.one/?_=0');
    });

    test('timestamp is the only thing that varies between calls', () {
      final a = nexDeskAdRequest(now: DateTime.fromMillisecondsSinceEpoch(0));
      final b = nexDeskAdRequest(now: DateTime.fromMillisecondsSinceEpoch(1));

      expect(a.request.queryParameters.keys, b.request.queryParameters.keys);
      expect(a.request.queryParameters['_'], isNot(b.request.queryParameters['_']));
    });
  });
}
