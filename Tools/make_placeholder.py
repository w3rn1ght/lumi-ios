import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES = os.path.join(ROOT, "Resources")

# Minimal WebP (VP8 lossy) decoder is not included; this script generates a
# placeholder PNG used when the original avatar cannot be decoded on iOS 12.
SIZE = 256
C1 = (96, 32, 210)
C2 = (238, 66, 132)


def render():
    rows = []
    for y in range(SIZE):
        row = bytearray()
        row.append(0)
        for x in range(SIZE):
            t = (x + y) / (2.0 * (SIZE - 1))
            r = int(C1[0] * (1 - t) + C2[0] * t)
            g = int(C1[1] * (1 - t) + C2[1] * t)
            b = int(C1[2] * (1 - t) + C2[2] * t)
            # simple rounded avatar mask
            cx, cy = SIZE / 2.0, SIZE / 2.0
            dx, dy = x - cx, y - cy
            radius = SIZE / 2.0 - 1
            if dx * dx + dy * dy <= radius * radius:
                row.extend((r, g, b, 255))
            else:
                row.extend((0, 0, 0, 0))
        rows.append(bytes(row))
    return b"".join(rows)


def chunk(tag, payload):
    return (
        struct.pack(">I", len(payload))
        + tag
        + payload
        + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
    )


raw = render()
png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
png += chunk(b"sRGB", b"\x00")
png += chunk(b"IDAT", zlib.compress(raw, 9))
png += chunk(b"IEND", b"")

path = os.path.join(RESOURCES, "AvatarPlaceholder.png")
with open(path, "wb") as handle:
    handle.write(png)
print("wrote", path)
