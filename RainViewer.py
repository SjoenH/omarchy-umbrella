#!/usr/bin/env python3
"""RainViewer tile sampler for the koka.umbrella plugin.

Fetches the 512px zoom-7 radar tile centered on a coordinate from the free
RainViewer Weather Maps API (no key, personal/educational use) and reports
whether rain covers that point, with a rough mm/h estimate decoded from the
Universal Blue colorbar.

Usage: python3 RainViewer.py <tile_base_url> <lat> <lon>
Prints "wet <mm/h>" or "dry" on stdout; exits non-zero on any failure so the
caller keeps its previous verdict.
"""
import struct
import sys
import urllib.request
import zlib


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "koka-umbrella/2.0 github.com/SjoenH/omarchy-umbrella"})
    with urllib.request.urlopen(req, timeout=8) as resp:
        return resp.read()


def decode_png(data: bytes):
    """Minimal PNG decoder: 8-bit, RGB/RGBA/gray, non-interlaced."""
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos = 8
    width = height = bitdepth = color = None
    idat = b""
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if ctype == b"IHDR":
            width, height, bitdepth, color = struct.unpack(">IIBB", body[:10])
        elif ctype == b"IDAT":
            idat += body
        elif ctype == b"IEND":
            break
        pos += 12 + length
    assert bitdepth == 8 and color in (0, 2, 6), f"unsupported PNG: depth={bitdepth} color={color}"
    channels = {0: 1, 2: 3, 6: 4}[color]
    raw = zlib.decompress(idat)
    stride = width * channels
    out = bytearray()
    prev = bytearray(stride)
    i = 0
    for _ in range(height):
        ftype = raw[i]
        i += 1
        line = bytearray(raw[i:i + stride])
        i += stride
        if ftype == 1:
            for x in range(channels, stride):
                line[x] = (line[x] + line[x - channels]) & 0xFF
        elif ftype == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 0xFF
        elif ftype == 3:
            for x in range(stride):
                left = line[x - channels] if x >= channels else 0
                line[x] = (line[x] + ((left + prev[x]) >> 1)) & 0xFF
        elif ftype == 4:
            for x in range(stride):
                a = line[x - channels] if x >= channels else 0
                b = prev[x]
                c = prev[x - channels] if x >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 0xFF
        out += line
        prev = line
    return width, height, channels, bytes(out)


def classify(r: int, g: int, b: int, a: float):
    """Universal Blue band -> rough mm/h. Gray semi-transparent = halo."""
    if a < 0.2:
        return None
    if abs(r - g) < 30 and abs(g - b) < 30:
        return None
    if r > 200 and g > 120 and b < 120:
        return 15.0  # yellow/orange: extreme
    if r < 60 and b >= 210:
        return 0.8   # pale cyan: light rain
    if r < 60 and b >= 170:
        return 2.0   # mid blue
    if b > 140:
        return 4.0   # deeper blue
    return 8.0       # darkest blue


def main() -> int:
    base, lat, lon = sys.argv[1], sys.argv[2], sys.argv[3]
    tile = fetch(f"{base}/512/7/{lat}/{lon}/1/1_1.png")
    width, height, ch, px = decode_png(tile)

    samples = []
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            x, y = width // 2 + dx, height // 2 + dy
            o = (y * width + x) * ch
            r, g, b = px[o], px[o + 1], px[o + 2]
            a = px[o + 3] / 255.0 if ch == 4 else 1.0
            if color := classify(r, g, b, a):
                samples.append(color)

    if samples:
        print("wet %.1f" % (sum(samples) / len(samples)))
    else:
        print("dry")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(1)
