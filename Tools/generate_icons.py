#!/usr/bin/env python3
"""Generate Lumi app icons and the launch logo without external dependencies."""

import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES = os.path.join(ROOT, "Resources")

ACCENT_A = (96, 32, 210)
ACCENT_B = (238, 66, 132)
DARK = (11, 11, 18)

# Bubble geometry (normalized coordinates).
BUBBLE_X0, BUBBLE_Y0 = 0.20, 0.18
BUBBLE_X1, BUBBLE_Y1 = 0.80, 0.64
BUBBLE_R = 0.115
TAIL_A = (0.245, 0.555)
TAIL_B = (0.375, 0.640)
TAIL_C = (0.225, 0.760)

# Letter "L" geometry (normalized coordinates).
L_X0, L_X1 = 0.395, 0.490
L_Y0, L_Y1 = 0.310, 0.555
L_ARM_X1 = 0.625
L_ARM_Y0 = 0.470


def clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(int(round(lerp(c1[i], c2[i], t))) for i in range(3))


def background_color(x, y):
    t = clamp((x * 0.75 + y * 1.25) / 2.0)
    t = t * t * (3.0 - 2.0 * t)
    color = mix(ACCENT_A, ACCENT_B, t)
    dx, dy = x - 0.25, y - 0.15
    distance = math.sqrt(dx * dx + dy * dy)
    glow = max(0.0, 1.0 - distance / 0.85)
    color = tuple(min(255, int(c + 22 * glow * glow)) for c in color)
    edge = max(abs(x - 0.5), abs(y - 0.5)) * 2.0
    factor = 1.0 - 0.10 * max(0.0, edge - 0.55)
    return tuple(int(c * factor) for c in color)


def in_rounded_rect(x, y, x0, y0, x1, y1, radius):
    if x < x0 or x > x1 or y < y0 or y > y1:
        return False
    cx = min(max(x, x0 + radius), x1 - radius)
    cy = min(max(y, y0 + radius), y1 - radius)
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius * radius


def triangle_sign(px, py, ax, ay, bx, by):
    return (px - bx) * (ay - by) - (ax - bx) * (py - by)


def in_triangle(x, y, a, b, c):
    d1 = triangle_sign(x, y, a[0], a[1], b[0], b[1])
    d2 = triangle_sign(x, y, b[0], b[1], c[0], c[1])
    d3 = triangle_sign(x, y, c[0], c[1], a[0], a[1])
    has_negative = d1 < 0 or d2 < 0 or d3 < 0
    has_positive = d1 > 0 or d2 > 0 or d3 > 0
    return not (has_negative and has_positive)


def in_bubble(x, y):
    return in_rounded_rect(
        x, y, BUBBLE_X0, BUBBLE_Y0, BUBBLE_X1, BUBBLE_Y1, BUBBLE_R
    ) or in_triangle(x, y, TAIL_A, TAIL_B, TAIL_C)


def in_letter_l(x, y):
    vertical = L_X0 <= x <= L_X1 and L_Y0 <= y <= L_Y1
    horizontal = L_X0 <= x <= L_ARM_X1 and L_ARM_Y0 <= y <= L_Y1
    return vertical or horizontal


def sample(x, y, transparent):
    if not in_bubble(x, y):
        if transparent:
            return 0, 0, 0, 0
        r, g, b = background_color(x, y)
        return r, g, b, 255
    if in_letter_l(x, y):
        r, g, b = background_color(x, y)
        return r, g, b, 255
    return 255, 255, 255, 255


def render(size, transparent=False, samples=3):
    pixels = bytearray()
    inv = 1.0 / size
    step = 1.0 / samples
    total = samples * samples
    for py in range(size):
        for px in range(size):
            red = green = blue = alpha = 0
            for sy in range(samples):
                y = (py + (sy + 0.5) * step) * inv
                for sx in range(samples):
                    x = (px + (sx + 0.5) * step) * inv
                    r, g, b, a = sample(x, y, transparent)
                    red += r
                    green += g
                    blue += b
                    alpha += a
            pixels += bytes(
                (red // total, green // total, blue // total, alpha // total)
            )
    return bytes(pixels)


def write_png(path, width, height, rgba):
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw.extend(rgba[y * stride : (y + 1) * stride])

    def chunk(tag, payload):
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"sRGB", b"\x00")
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(png)


def main():
    os.makedirs(RESOURCES, exist_ok=True)

    icons = {
        "Icon-20@2x.png": 40,
        "Icon-20@3x.png": 60,
        "Icon-29@2x.png": 58,
        "Icon-29@3x.png": 87,
        "Icon-40@2x.png": 80,
        "Icon-40@3x.png": 120,
        "Icon-60@2x.png": 120,
        "Icon-60@3x.png": 180,
        "Icon-76.png": 76,
        "Icon-76@2x.png": 152,
        "Icon-83.5@2x.png": 167,
        "Icon-1024.png": 1024,
    }

    for name, size in icons.items():
        samples = 2 if size > 256 else 3
        print("generating", name, f"({size}x{size})")
        write_png(
            os.path.join(RESOURCES, name),
            size,
            size,
            render(size, transparent=False, samples=samples),
        )

    print("generating LaunchLogo.png (512x512, transparent)")
    write_png(
        os.path.join(RESOURCES, "LaunchLogo.png"),
        512,
        512,
        render(512, transparent=True, samples=2),
    )


if __name__ == "__main__":
    main()
