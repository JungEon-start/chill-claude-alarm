#!/usr/bin/env python3
"""Generate a DMG background image with a drag arrow and text."""
import struct
import zlib
import sys

WIDTH, HEIGHT = 540, 300

# Clean 9px tall bitmap font (extra rows for descenders like g)
FONT = {
    'D': [
        "11111100",
        "11000110",
        "11000011",
        "11000011",
        "11000011",
        "11000110",
        "11111100",
        "00000000",
        "00000000",
    ],
    'r': [
        "00000000",
        "00000000",
        "11001100",
        "11011110",
        "11110000",
        "11000000",
        "11000000",
        "00000000",
        "00000000",
    ],
    'a': [
        "00000000",
        "00000000",
        "01111100",
        "00000110",
        "01111110",
        "11000110",
        "01111110",
        "00000000",
        "00000000",
    ],
    'g': [
        "00000000",
        "00000000",
        "01111110",
        "11000110",
        "11000110",
        "01111110",
        "00000110",
        "11000110",
        "01111100",
    ],
}


def render_text(text, scale=2):
    """Render text to a set of (x, y) pixel positions."""
    positions = set()
    cx = 0
    for ch in text:
        glyph = FONT.get(ch, [])
        if not glyph:
            cx += 6 * scale
            continue
        for row_idx, row in enumerate(glyph):
            for col_idx, pixel in enumerate(row):
                if pixel == '1':
                    for sy in range(scale):
                        for sx in range(scale):
                            positions.add((cx + col_idx * scale + sx, row_idx * scale + sy))
        cx += (len(glyph[0]) + 2) * scale
    return positions


def create_png(width, height):
    pixels = []

    bg = (255, 255, 255)
    arrow_color = (40, 40, 40)
    text_color = (80, 80, 80)

    arrow_y_center = 150
    arrow_x_start = 225
    arrow_x_end = 315
    arrow_thickness = 3
    arrowhead_size = 14

    # Render "Drag" text centered below arrow
    scale = 2
    text_positions = render_text("Drag", scale=scale)
    if text_positions:
        text_w = max(p[0] for p in text_positions) + 1
        text_h = max(p[1] for p in text_positions) + 1
    else:
        text_w, text_h = 0, 0
    text_ox = (arrow_x_start + arrow_x_end) // 2 - text_w // 2
    text_oy = arrow_y_center + 24
    text_set = set((text_ox + px, text_oy + py) for px, py in text_positions)

    for y in range(height):
        row = []
        for x in range(width):
            r, g, b = bg

            # Arrow shaft
            if arrow_x_start <= x <= arrow_x_end - arrowhead_size:
                if abs(y - arrow_y_center) <= arrow_thickness:
                    r, g, b = arrow_color

            # Arrowhead
            head_start = arrow_x_end - arrowhead_size
            if head_start <= x <= arrow_x_end:
                progress = (x - head_start) / arrowhead_size
                half_height = arrowhead_size * (1 - progress)
                if abs(y - arrow_y_center) <= half_height:
                    r, g, b = arrow_color

            # Text
            if (x, y) in text_set:
                r, g, b = text_color

            row.append((r, g, b))
        pixels.append(row)

    def make_chunk(chunk_type, data):
        chunk = chunk_type + data
        return struct.pack('>I', len(data)) + chunk + struct.pack('>I', zlib.crc32(chunk) & 0xFFFFFFFF)

    signature = b'\x89PNG\r\n\x1a\n'
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)

    raw_data = b''
    for row in pixels:
        raw_data += b'\x00'
        for r, g, b in row:
            raw_data += struct.pack('BBB', r, g, b)

    idat = zlib.compress(raw_data)

    png = signature
    png += make_chunk(b'IHDR', ihdr)
    png += make_chunk(b'IDAT', idat)
    png += make_chunk(b'IEND', b'')

    return png


output = sys.argv[1] if len(sys.argv) > 1 else 'dmg-bg.png'
with open(output, 'wb') as f:
    f.write(create_png(WIDTH, HEIGHT))
print(f"Created {output} ({WIDTH}x{HEIGHT})")
