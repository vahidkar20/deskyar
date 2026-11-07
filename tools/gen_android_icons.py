#!/usr/bin/env python3
"""Generate the Android launcher icons from the master artwork.

The Android mipmaps are committed to the repository rather than produced by
`flutter_launcher_icons` at build time: the CI Android job only runs
`flutter build apk`, so whatever is checked in is what ships. That is how the
RustDesk artwork kept shipping inside a NexDesk APK long after the rebrand.

Everything is derived from `deskyar/res/icon.png`, the same master the Windows
and macOS icons come from, so the launcher icon can never drift from the
desktop one again.

Four artefacts per density are written:

  ic_launcher.png             legacy square icon (48..192 px)
  ic_launcher_round.png       legacy round icon, art on a matching green disc
  ic_launcher_foreground.png  adaptive-icon foreground on a transparent canvas
  ic_stat_logo.png            white notification-bar silhouette

Usage (from the repository root):

    python tools/gen_android_icons.py

No third-party imaging library is used: `pngutil` next to this file is a
stdlib-only PNG codec, matching the rest of the brand tooling.
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from pngutil import read_png, write_png  # noqa: E402

ROOT = HERE.parent
MASTER = ROOT / "res" / "icon.png"
RES = ROOT / "flutter" / "android" / "app" / "src" / "main" / "res"

# Android launcher icon sizes, in pixels, per density bucket.
LEGACY = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
# Adaptive icons are 108dp; only the inner 66dp is guaranteed to be visible.
FOREGROUND = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}
# Notification icons are 24dp.
STAT = {
    "mdpi": 24,
    "hdpi": 36,
    "xhdpi": 48,
    "xxhdpi": 72,
    "xxxhdpi": 96,
}

# Share of the canvas the artwork occupies. The legacy icon keeps a hair of
# padding so a launcher that draws a frame does not clip the plate; the
# adaptive foreground sits inside the 66/108 safe zone.
LEGACY_SCALE = 0.96
FOREGROUND_SCALE = 0.62


class Image:
    def __init__(self, width: int, height: int, rgba: bytearray):
        self.w = width
        self.h = height
        self.px = rgba

    def get(self, x: int, y: int) -> tuple[int, int, int, int]:
        i = (y * self.w + x) * 4
        p = self.px
        return p[i], p[i + 1], p[i + 2], p[i + 3]


def load(path: Path) -> Image:
    w, h, rgba = read_png(path)
    return Image(w, h, rgba)


def alpha_bbox(img: Image, threshold: int = 8) -> tuple[int, int, int, int]:
    """Tightest box that still contains every visibly opaque pixel."""
    left, top, right, bottom = img.w, img.h, -1, -1
    for y in range(img.h):
        row = y * img.w * 4
        for x in range(img.w):
            if img.px[row + x * 4 + 3] > threshold:
                if x < left:
                    left = x
                if x > right:
                    right = x
                if y < top:
                    top = y
                if y > bottom:
                    bottom = y
    if right < 0:
        return 0, 0, img.w, img.h
    return left, top, right + 1, bottom + 1


def crop(img: Image, box: tuple[int, int, int, int]) -> Image:
    left, top, right, bottom = box
    w, h = right - left, bottom - top
    out = bytearray(w * h * 4)
    for y in range(h):
        src = ((top + y) * img.w + left) * 4
        dst = y * w * 4
        out[dst:dst + w * 4] = img.px[src:src + w * 4]
    return Image(w, h, out)


def resize(img: Image, width: int, height: int) -> Image:
    """Box-filter resample in premultiplied alpha.

    Averaging straight RGBA darkens the fringe of a transparent edge (the RGB of
    fully transparent pixels is black here), which shows up as a dark outline
    around the plate at small sizes. Premultiplying first avoids it.
    """
    if width == img.w and height == img.h:
        return Image(width, height, bytearray(img.px))
    out = bytearray(width * height * 4)
    x_ratio = img.w / width
    y_ratio = img.h / height
    for y in range(height):
        y0 = int(y * y_ratio)
        y1 = max(y0 + 1, int((y + 1) * y_ratio))
        for x in range(width):
            x0 = int(x * x_ratio)
            x1 = max(x0 + 1, int((x + 1) * x_ratio))
            r = g = b = a = 0
            n = 0
            for sy in range(y0, min(y1, img.h)):
                row = sy * img.w * 4
                for sx in range(x0, min(x1, img.w)):
                    i = row + sx * 4
                    pa = img.px[i + 3]
                    r += img.px[i] * pa
                    g += img.px[i + 1] * pa
                    b += img.px[i + 2] * pa
                    a += pa
                    n += 1
            if n == 0:
                continue
            o = (y * width + x) * 4
            if a == 0:
                out[o:o + 4] = b"\x00\x00\x00\x00"
            else:
                out[o] = r // a
                out[o + 1] = g // a
                out[o + 2] = b // a
                out[o + 3] = a // n
    return Image(width, height, out)


def canvas(size: int, color: tuple[int, int, int, int] | None = None) -> Image:
    fill = bytes(color) if color else b"\x00\x00\x00\x00"
    return Image(size, size, bytearray(fill * (size * size)))


def paste_center(dst: Image, src: Image, scale: float) -> None:
    side = max(1, int(round(dst.w * scale)))
    art = resize(src, side, side)
    ox = (dst.w - side) // 2
    oy = (dst.h - side) // 2
    for y in range(side):
        s = y * side * 4
        d = ((oy + y) * dst.w + ox) * 4
        for x in range(side):
            si = s + x * 4
            sa = art.px[si + 3]
            if sa == 0:
                continue
            di = d + x * 4
            if sa == 255:
                dst.px[di:di + 4] = art.px[si:si + 4]
                continue
            # Source-over with the destination, both in straight alpha.
            da = dst.px[di + 3]
            out_a = sa + da * (255 - sa) // 255
            if out_a == 0:
                continue
            for c in range(3):
                dst.px[di + c] = (
                    art.px[si + c] * sa + dst.px[di + c] * da * (255 - sa) // 255
                ) // out_a
            dst.px[di + 3] = out_a


def circle_mask(img: Image) -> None:
    """Knock out everything outside the inscribed circle, anti-aliased."""
    cx = cy = (img.w - 1) / 2.0
    radius = img.w / 2.0 - 0.5
    for y in range(img.h):
        for x in range(img.w):
            dx, dy = x - cx, y - cy
            dist = (dx * dx + dy * dy) ** 0.5
            if dist <= radius - 1:
                continue
            i = (y * img.w + x) * 4
            if dist >= radius + 1:
                img.px[i + 3] = 0
            else:
                img.px[i + 3] = int(img.px[i + 3] * (radius + 1 - dist) / 2)


def plate_color(img: Image) -> tuple[int, int, int]:
    """Median colour of the plate's outer ring, used for the round background.

    Sampling a ring rather than one pixel keeps a glossy highlight or a shadow
    from deciding the colour of the whole disc.
    """
    samples = []
    left, top, right, bottom = alpha_bbox(img)
    cx, cy = (left + right) / 2.0, (top + bottom) / 2.0
    radius = min(right - left, bottom - top) / 2.0
    steps = 360
    for k in range(steps):
        angle = 2.0 * 3.141592653589793 * k / steps
        import math

        x = int(cx + math.cos(angle) * radius * 0.86)
        y = int(cy + math.sin(angle) * radius * 0.86)
        if 0 <= x < img.w and 0 <= y < img.h:
            r, g, b, a = img.get(x, y)
            if a > 200:
                samples.append((r, g, b))
    if not samples:
        return 2, 162, 76
    samples.sort(key=lambda c: c[0] + c[1] + c[2])
    return samples[len(samples) // 2]


# Geometry of the mark, copied from `deskyar/res/logo.svg` (a 512-unit
# viewBox). The N is a single stroked polyline with round caps and joins, and
# the two dots are rounded squares. Drawing the status-bar glyph from these
# numbers - rather than thresholding the glossy 3D plate - is what makes it
# crisp at 24 dp: thresholding a photograph of the plate also picks up its
# bright rim, which reads as a ghostly ring around the letter.
VIEWBOX = 512.0
N_POINTS = [(170.0, 352.0), (170.0, 202.0), (342.0, 352.0), (342.0, 202.0)]
N_STROKE = 64.0
DOTS = [(376.0, 118.0, 52.0, 14.0), (432.0, 172.0, 38.0, 11.0)]  # x, y, side, radius

# Bounding box of the mark, with the stroke width folded in.
MARK_BOX = (138.0, 118.0, 470.0, 384.0)


def _distance_to_segment(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    dx, dy = bx - ax, by - ay
    length2 = dx * dx + dy * dy
    if length2 == 0.0:
        return ((px - ax) ** 2 + (py - ay) ** 2) ** 0.5
    t = ((px - ax) * dx + (py - ay) * dy) / length2
    t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
    qx, qy = ax + t * dx, ay + t * dy
    return ((px - qx) ** 2 + (py - qy) ** 2) ** 0.5


def _inside_round_rect(px: float, py: float, x: float, y: float, side: float, radius: float) -> bool:
    if not (x <= px <= x + side and y <= py <= y + side):
        return False
    # Only the corners need the radius test.
    cx = min(max(px, x + radius), x + side - radius)
    cy = min(max(py, y + radius), y + side - radius)
    return (px - cx) ** 2 + (py - cy) ** 2 <= radius * radius


def monochrome(size: int) -> Image:
    """White mark for the status bar.

    Android tints `ic_stat_*` with the notification colour and only reads the
    alpha channel, so the glyph is drawn as solid white on transparency. Each
    pixel is sampled on a 3x3 grid to anti-alias the stroke, which matters most
    at 24 dp where a hard edge turns into a jagged blob.
    """
    out = canvas(size)
    box_w = MARK_BOX[2] - MARK_BOX[0]
    box_h = MARK_BOX[3] - MARK_BOX[1]
    # Leave a hair of padding so a launcher that adds its own inset does not
    # clip the caps.
    scale = (size * 0.94) / max(box_w, box_h)
    ox = (size - box_w * scale) / 2.0 - MARK_BOX[0] * scale
    oy = (size - box_h * scale) / 2.0 - MARK_BOX[1] * scale
    half = N_STROKE * scale / 2.0
    samples = 3
    step = 1.0 / samples
    for y in range(size):
        for x in range(size):
            hits = 0
            for sy in range(samples):
                py = (y + (sy + 0.5) * step - oy) / scale
                for sx in range(samples):
                    px = (x + (sx + 0.5) * step - ox) / scale
                    inside = False
                    for i in range(len(N_POINTS) - 1):
                        ax, ay = N_POINTS[i]
                        bx, by = N_POINTS[i + 1]
                        if _distance_to_segment(px, py, ax, ay, bx, by) <= N_STROKE / 2.0:
                            inside = True
                            break
                    if not inside:
                        for dx, dy, side, radius in DOTS:
                            if _inside_round_rect(px, py, dx, dy, side, radius):
                                inside = True
                                break
                    if inside:
                        hits += 1
            if hits:
                alpha = 255 * hits // (samples * samples)
                i = (y * size + x) * 4
                out.px[i:i + 4] = bytes((255, 255, 255, alpha))
    return out


def main() -> int:
    if not MASTER.exists():
        print(f"master artwork not found: {MASTER}")
        return 1
    master = load(MASTER)
    art = crop(master, alpha_bbox(master))
    green = plate_color(master)
    print(f"master {master.w}x{master.h}, art {art.w}x{art.h}, plate #{green[0]:02x}{green[1]:02x}{green[2]:02x}")

    for bucket, size in LEGACY.items():
        folder = RES / f"mipmap-{bucket}"
        folder.mkdir(parents=True, exist_ok=True)

        square = canvas(size)
        paste_center(square, art, LEGACY_SCALE)
        write_png(folder / "ic_launcher.png", size, size, square.px)

        round_icon = canvas(size, (green[0], green[1], green[2], 255))
        paste_center(round_icon, art, LEGACY_SCALE)
        circle_mask(round_icon)
        write_png(folder / "ic_launcher_round.png", size, size, round_icon.px)

        fg_size = FOREGROUND[bucket]
        foreground = canvas(fg_size)
        paste_center(foreground, art, FOREGROUND_SCALE)
        write_png(folder / "ic_launcher_foreground.png", fg_size, fg_size, foreground.px)

        stat_size = STAT[bucket]
        stat = monochrome(stat_size)
        write_png(folder / "ic_stat_logo.png", stat_size, stat_size, stat.px)
        print(f"  {bucket}: launcher {size}, foreground {fg_size}, stat {stat_size}")

    background = RES / "values" / "ic_launcher_background.xml"
    background.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        f'    <color name="ic_launcher_background">#{green[0]:02x}{green[1]:02x}{green[2]:02x}</color>\n'
        "</resources>\n",
        encoding="utf-8",
    )
    print(f"background colour written to {background.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
