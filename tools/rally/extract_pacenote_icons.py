#!/usr/bin/env python3
"""
Extract co-driver arrow and warning icons from CMR2 bigfiles and export
modern SVG assets with exact silhouettes and provenance tracking.
"""

import gzip
import hashlib
import io
import json
import os
import struct
import cv2
import numpy as np
from PIL import Image

COM640_PATH = r"D:\open-cmr2-rust\og-cmr2\Game\Bigfiles\com640.bfl"
COM1024_PATH = r"D:\open-cmr2-rust\og-cmr2\Game\Bigfiles\com1024.bfl"
STAGING_DIR = r"D:\open-formula\staging_rally\pacenotes\cmr2"
OUTPUT_DIR = r"D:\rust-godot-vehicle-simulator\game\assets\rally\visual_pacenotes\cmr2"

CELL_RECTS_1024 = [
    (1, 0, 102, 102),     # 0: hairpin
    (103, 0, 102, 102),   # 1: open hairpin / 1
    (205, 0, 102, 102),   # 2: turn 2
    (307, 0, 102, 102),   # 3: turn 3
    (1, 102, 102, 102),   # 4: turn 4
    (103, 102, 102, 102), # 5: turn 5
    (205, 102, 102, 102), # 6: turn 6 / flat
    (307, 109, 107, 92)   # 7: warning triangle
]

ICON_NAMES = [
    "arrow_00.svg",
    "arrow_01.svg",
    "arrow_02.svg",
    "arrow_03.svg",
    "arrow_04.svg",
    "arrow_05.svg",
    "arrow_06.svg",
    "warning.svg"
]

ICON_COLORS = [
    "#ff0028", # 0
    "#ff0028", # 1
    "#ff4e08", # 2
    "#ff8208", # 3
    "#ffbd0d", # 4
    "#86a500", # 5
    "#a2b4c8", # 6
    "#ffffff"  # 7: white base for tinting
]

def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()

def extract_tga_from_bfl(bfl_path: str):
    with open(bfl_path, "rb") as f:
        raw_bfl = f.read()
    bfl_sha = sha256_bytes(raw_bfl)
    with gzip.open(bfl_path, "rb") as f:
        decompressed = f.read()
    buffer = decompressed[8:]
    toc_offset = struct.unpack("<i", buffer[-4:])[0]
    pos = toc_offset
    while pos < len(buffer) - 4:
        fsize, offset, nlen = struct.unpack("<III", buffer[pos:pos+12])
        pos += 12
        name = buffer[pos:pos+nlen].decode("latin1")
        pos += nlen + ((4 - (nlen % 4)) if (nlen % 4) != 0 else 0)
        if name.lower() == "arrows4.tga":
            tga_bytes = buffer[offset:offset+fsize]
            return bfl_sha, tga_bytes
    raise RuntimeError(f"arrows4.tga not found in {bfl_path}")

def contour_to_svg_path(contour):
    pts = contour.reshape(-1, 2)
    if len(pts) == 0:
        return ""
    d = [f"M {pts[0][0]},{pts[0][1]}"]
    for p in pts[1:]:
        d.append(f"L {p[0]},{p[1]}")
    d.append("Z")
    return " ".join(d)

def generate_svg_for_arrow(crop_arr, fill_color, w, h):
    # crop_arr is RGBA
    alpha = crop_arr[:, :, 3]
    r, g, b = crop_arr[:, :, 0], crop_arr[:, :, 1], crop_arr[:, :, 2]

    # Badge mask and erosion to isolate internal arrow glyph from outer border
    badge_mask = (alpha > 64).astype(np.uint8) * 255
    badge_eroded = cv2.erode(badge_mask, np.ones((7, 7), np.uint8))

    # Glyph mask: pixels that are black and inside the eroded badge
    glyph_mask = ((alpha > 128) & (r < 80) & (g < 80) & (b < 80) & (badge_eroded > 0)).astype(np.uint8) * 255

    cnts, _ = cv2.findContours(glyph_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    glyph_paths = []
    for c in cnts:
        if cv2.contourArea(c) > 20:
            app = cv2.approxPolyDP(c, 0.5, True)
            glyph_paths.append(contour_to_svg_path(app))

    svg_lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">',
        f'  <rect x="5.5" y="3.5" width="{w - 11}" height="{h - 7}" rx="8" ry="8" fill="{fill_color}" stroke="#000000" stroke-width="2" />',
    ]
    for gp in glyph_paths:
        svg_lines.append(f'  <path fill="#000000" fill-rule="evenodd" d="{gp}" />')
    svg_lines.append('</svg>\n')
    return "\n".join(svg_lines)

def generate_svg_for_warning(crop_arr, w, h):
    # Warning triangle: white background, black border, black exclamation mark
    alpha = crop_arr[:, :, 3]
    r, g, b = crop_arr[:, :, 0], crop_arr[:, :, 1], crop_arr[:, :, 2]

    badge_mask = (alpha > 64).astype(np.uint8) * 255
    tri_cnts, _ = cv2.findContours(badge_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    tri_c = max(tri_cnts, key=cv2.contourArea)
    app_tri = cv2.approxPolyDP(tri_c, 0.8, True)
    tri_path = contour_to_svg_path(app_tri)

    badge_eroded = cv2.erode(badge_mask, np.ones((7, 7), np.uint8))
    glyph_mask = ((alpha > 128) & (r < 80) & (g < 80) & (b < 80) & (badge_eroded > 0)).astype(np.uint8) * 255

    cnts, _ = cv2.findContours(glyph_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    mark_paths = []
    for c in cnts:
        if cv2.contourArea(c) > 20:
            app = cv2.approxPolyDP(c, 0.5, True)
            mark_paths.append(contour_to_svg_path(app))

    svg_lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">',
        f'  <path fill="#ffffff" stroke="#000000" stroke-width="2" d="{tri_path}" />',
    ]
    for mp in mark_paths:
        svg_lines.append(f'  <path fill="#000000" fill-rule="evenodd" d="{mp}" />')
    svg_lines.append('</svg>\n')
    return "\n".join(svg_lines)

def main():
    os.makedirs(STAGING_DIR, exist_ok=True)
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    bfl640_sha, tga640_bytes = extract_tga_from_bfl(COM640_PATH)
    bfl1024_sha, tga1024_bytes = extract_tga_from_bfl(COM1024_PATH)

    with open(os.path.join(STAGING_DIR, "arrows4_640.tga"), "wb") as f:
        f.write(tga640_bytes)
    with open(os.path.join(STAGING_DIR, "arrows4_1024.tga"), "wb") as f:
        f.write(tga1024_bytes)

    img1024 = Image.open(io.BytesIO(tga1024_bytes))
    arr1024 = np.array(img1024)

    manifest = {
        "sources": {
            "com640_bfl": {
                "path": COM640_PATH,
                "sha256": bfl640_sha,
                "tga_sha256": sha256_bytes(tga640_bytes),
                "resolution": [256, 128]
            },
            "com1024_bfl": {
                "path": COM1024_PATH,
                "sha256": bfl1024_sha,
                "tga_sha256": sha256_bytes(tga1024_bytes),
                "resolution": [512, 256]
            }
        },
        "icons": {}
    }

    for idx, (x, y, w, h) in enumerate(CELL_RECTS_1024):
        crop = arr1024[y:y+h, x:x+w]
        filename = ICON_NAMES[idx]
        color = ICON_COLORS[idx]
        if idx == 7:
            svg_content = generate_svg_for_warning(crop, w, h)
        else:
            svg_content = generate_svg_for_arrow(crop, color, w, h)

        svg_bytes = svg_content.encode("utf-8")
        out_path = os.path.join(OUTPUT_DIR, filename)
        with open(out_path, "wb") as f:
            f.write(svg_bytes)

        # Also save pixel-perfect PNG asset
        png_filename = filename.replace(".svg", ".png")
        png_out_path = os.path.join(OUTPUT_DIR, png_filename)
        Image.fromarray(crop).save(png_out_path)

        manifest["icons"][filename] = {
            "index": idx,
            "crop_rect": [x, y, w, h],
            "sha256": sha256_bytes(svg_bytes),
            "base_color": color,
            "description": "warning" if idx == 7 else f"arrow_{idx}"
        }
        print(f"Exported {filename}: sha256={manifest['icons'][filename]['sha256']}")

    manifest_path = os.path.join(OUTPUT_DIR, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    print(f"Saved manifest to {manifest_path}")

if __name__ == "__main__":
    main()
