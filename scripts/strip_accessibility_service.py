#!/usr/bin/env python3
"""Remove the accessibility service from the Android manifest, for the
"controller" build variant.

Google Play Protect blocks the *installation* of an internet-sideloaded app that
declares any of RECEIVE_SMS, READ_SMS, BIND_NOTIFICATION_LISTENER_SERVICE or
BIND_ACCESSIBILITY_SERVICE, and offers no "install anyway":

    https://developers.google.com/android/play-protect/warning-dev-guidance

NexDesk needs accessibility to inject touch and keyboard when the phone is the
*host*. It does not need it to be the *controller*. A build without the service
therefore installs normally and still does everything a controller does; it just
cannot let another device control this phone.

The script is deliberately strict. It removes exactly one <service> block whose
android:name is ".InputService" (together with the comment that explains it) and
fails loudly if the file does not look the way it expects. A silent no-op would
ship an APK that is still blocked; a silent over-match would ship a broken
manifest. Both are worse than a red build.

Usage: python3 scripts/strip_accessibility_service.py <AndroidManifest.xml>
"""

import re
import sys

# One XML comment, without letting the match run past the end of a comment.
COMMENT = r"[ \t]*<!--(?:(?!-->).)*-->[ \t]*\n"
SERVICE = re.compile(
    r"(?:" + COMMENT + r")?[ \t]*<service\s+android:name=\"\.InputService\".*?</service>[ \t]*\n",
    re.DOTALL,
)

PERMISSION_ATTR = 'android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE"'


def main(path: str) -> int:
    with open(path, encoding="utf-8") as f:
        source = f.read()

    stripped, count = SERVICE.subn("", source)
    if count != 1:
        print(
            f"expected exactly one .InputService block in {path}, found {count}",
            file=sys.stderr,
        )
        return 1
    if "InputService" in stripped:
        print("an InputService reference survived; refusing to continue", file=sys.stderr)
        return 1
    if PERMISSION_ATTR in stripped:
        print(
            "the BIND_ACCESSIBILITY_SERVICE declaration survived; refusing to continue",
            file=sys.stderr,
        )
        return 1
    if stripped == source:
        print("nothing changed", file=sys.stderr)
        return 1

    with open(path, "w", encoding="utf-8") as f:
        f.write(stripped)
    print(f"removed the accessibility service from {path}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
