"""Minimal PNG read/write helpers (stdlib only).

The build machine has no network access to install Pillow, so the brand asset
generator carries its own encoder: zlib + struct is all a PNG needs.
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def read_png(path: str | Path) -> tuple[int, int, bytearray]:
    """Decode an 8-bit RGB/RGBA/grey PNG into a flat RGBA bytearray."""
    data = Path(path).read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos = 8
    width = height = 0
    color_type = 6
    idat = bytearray()
    palette = b""
    trns = b""
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if ctype == b"IHDR":
            width, height, depth, color_type, _, _, interlace = struct.unpack(
                ">IIBBBBB", chunk
            )
            if depth != 8 or interlace != 0:
                raise ValueError(f"unsupported PNG: depth {depth} interlace {interlace}")
        elif ctype == b"PLTE":
            palette = chunk
        elif ctype == b"tRNS":
            trns = chunk
        elif ctype == b"IDAT":
            idat += chunk
        elif ctype == b"IEND":
            break

    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color_type]
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    out = bytearray(width * height * 4)
    prev = bytearray(stride)
    p = 0
    for y in range(height):
        f = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if f == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                c = prev[i - channels] if i >= channels else 0
                line[i] = (line[i] + _paeth(a, prev[i], c)) & 0xFF
        elif f != 0:
            raise ValueError(f"bad filter {f}")

        row = y * width * 4
        if color_type == 6:
            out[row:row + width * 4] = line
        elif color_type == 2:
            for x in range(width):
                r, g, b = line[x * 3:x * 3 + 3]
                out[row + x * 4:row + x * 4 + 4] = bytes((r, g, b, 255))
        elif color_type == 0:
            for x in range(width):
                v = line[x]
                out[row + x * 4:row + x * 4 + 4] = bytes((v, v, v, 255))
        elif color_type == 4:
            for x in range(width):
                v, a = line[x * 2], line[x * 2 + 1]
                out[row + x * 4:row + x * 4 + 4] = bytes((v, v, v, a))
        elif color_type == 3:
            for x in range(width):
                idx = line[x]
                r, g, b = palette[idx * 3:idx * 3 + 3]
                a = trns[idx] if idx < len(trns) else 255
                out[row + x * 4:row + x * 4 + 4] = bytes((r, g, b, a))
        prev = line
    return width, height, out


def _chunk(ctype: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + ctype
        + payload
        + struct.pack(">I", zlib.crc32(ctype + payload) & 0xFFFFFFFF)
    )


def write_png(path: str | Path, width: int, height: int, rgba: bytearray) -> None:
    stride = width * 4
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    blob = (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", ihdr)
        + _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + _chunk(b"IEND", b"")
    )
    Path(path).write_bytes(blob)


def write_ico(path: str | Path, frames: list[tuple[int, bytearray]]) -> None:
    """Write a multi-size .ico using uncompressed 32-bit DIB frames.

    DIB frames (rather than PNG-in-ICO) are what every Windows tool understands
    without negotiation: the shell, `winres`, the tray-icon crate and wxWidgets
    all read them.
    """
    n = len(frames)
    header = struct.pack("<HHH", 0, 1, n)
    entries = bytearray()
    payload = bytearray()
    offset = 6 + 16 * n
    for size, rgba in frames:
        bw = 0 if size >= 256 else size
        entries += struct.pack("<BBBBHHII", bw, bw, 0, 0, 1, 32, len(_dib(size, rgba)), offset)
        blob = _dib(size, rgba)
        payload += blob
        offset += len(blob)
    Path(path).write_bytes(header + bytes(entries) + bytes(payload))


def _dib(size: int, rgba: bytearray) -> bytes:
    # BITMAPINFOHEADER; height counts XOR + AND mask.
    mask_stride = ((size + 31) // 32) * 4
    info = struct.pack(
        "<IiiHHIIiiII", 40, size, size * 2, 1, 32, 0, size * size * 4 + mask_stride * size,
        0, 0, 0, 0,
    )
    pixels = bytearray()
    for y in range(size - 1, -1, -1):  # bottom-up
        row = y * size * 4
        for x in range(size):
            i = row + x * 4
            r, g, b, a = rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]
            pixels += bytes((b, g, r, a))
    mask = bytearray()
    for y in range(size - 1, -1, -1):
        row = y * size * 4
        bits = bytearray(mask_stride)
        for x in range(size):
            if rgba[row + x * 4 + 3] == 0:
                bits[x >> 3] |= 0x80 >> (x & 7)
        mask += bits
    return info + bytes(pixels) + bytes(mask)
