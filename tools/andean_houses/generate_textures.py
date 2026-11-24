#!/usr/bin/env python3
"""
Generate unified 64x64 PSX-style textures for the 20-house Andean catalog.
Combines:
  - D:\RallyManiacAssets\psx-white-house
  - PSX Andean Village Modular Kit (Nortimore)
  - New 64x64 PSX textures for calamina (galvanized & oxidized), quincha/barro,
    and wooden balcony balustrade.
"""
import os
import math
import random
from PIL import Image, ImageDraw, ImageEnhance, ImageOps

WHITE_HOUSE_DIR = r"D:\RallyManiacAssets\psx-white-house\source\411T_CST_Mahogany-Walnut"
NORTIMORE_DIR = r"C:\Users\bill\.gemini\antigravity\brain\aec6b34e-ede5-418a-8c77-3a4d3d9a5402\scratch\andean_kit\PSX Andean Village Modular Kit - Retro Exterior By Nortimore\Textures"
OUT_DIR = r"d:\rust-godot-vehicle-simulator\game\assets\rally\CDI\casas_andinas\textures"

os.makedirs(OUT_DIR, exist_ok=True)


def quantize_psx(img: Image.Image, colors: int = 32) -> Image.Image:
    """Subtle PSX palette reduction while preserving alpha if RGBA."""
    if img.mode == "RGBA":
        rgb = img.convert("RGB")
        alpha = img.getchannel("A")
        q = rgb.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
        q.putalpha(alpha)
        return q
    return img.convert("RGB").quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")


def make_tileable_64(img: Image.Image) -> Image.Image:
    """Downsample to 64x64 and gently blend borders so it tiles cleanly."""
    im = img.convert("RGB").resize((64, 64), Image.Resampling.BOX)
    # Mirror-blend 6px border for seamless tiling
    px = im.load()
    out = im.copy()
    opx = out.load()
    blend = 6
    for y in range(64):
        for x in range(64):
            r, g, b = px[x, y]
            if x < blend:
                t = (blend - x) / (2.0 * blend)
                r2, g2, b2 = px[63 - x, y]
                r = int(r * (1 - t) + r2 * t)
                g = int(g * (1 - t) + g2 * t)
                b = int(b * (1 - t) + b2 * t)
            elif x >= 64 - blend:
                t = (x - (64 - blend) + 1) / (2.0 * blend)
                r2, g2, b2 = px[63 - x, y]
                r = int(r * (1 - t) + r2 * t)
                g = int(g * (1 - t) + g2 * t)
                b = int(b * (1 - t) + b2 * t)
            opx[x, y] = (r, g, b)
    px = out.load()
    out2 = out.copy()
    opx = out2.load()
    for y in range(64):
        for x in range(64):
            r, g, b = px[x, y]
            if y < blend:
                t = (blend - y) / (2.0 * blend)
                r2, g2, b2 = px[x, 63 - y]
                r = int(r * (1 - t) + r2 * t)
                g = int(g * (1 - t) + g2 * t)
                b = int(b * (1 - t) + b2 * t)
            elif y >= 64 - blend:
                t = (y - (64 - blend) + 1) / (2.0 * blend)
                r2, g2, b2 = px[x, 63 - y]
                r = int(r * (1 - t) + r2 * t)
                g = int(g * (1 - t) + g2 * t)
                b = int(b * (1 - t) + b2 * t)
            opx[x, y] = (r, g, b)
    return out2


def generate_from_white_house():
    # 1. Clean white stucco (neutralized bright plaster for crisp pastel tinting)
    stucco = Image.open(os.path.join(WHITE_HOUSE_DIR, "istockphoto-625881290-612x612.jpg")).convert("RGB")
    # Crop square center
    w, h = stucco.size
    m = min(w, h)
    stucco = stucco.crop(((w - m) // 2, (h - m) // 2, (w + m) // 2, (h + m) // 2))
    stucco64 = make_tileable_64(stucco)
    # Normalize brightness so white stucco is ~230 avg (ideal base for pastel multiply)
    stucco64 = ImageOps.grayscale(stucco64).convert("RGB")
    stucco64 = ImageEnhance.Contrast(stucco64).enhance(0.85)
    stucco64 = ImageEnhance.Brightness(stucco64).enhance(1.06)
    stucco64 = quantize_psx(stucco64, 24)
    stucco64.save(os.path.join(OUT_DIR, "stucco_clean.png"))

    # 2. Door from psx-white-house (mahogany wood)
    door = Image.open(os.path.join(WHITE_HOUSE_DIR, "411T_CST_Mahogany-Walnut.jpg")).convert("RGB")
    door64 = door.resize((64, 64), Image.Resampling.BOX)
    door64 = ImageEnhance.Brightness(door64).enhance(0.9)
    door64 = quantize_psx(door64, 32)
    door64.save(os.path.join(OUT_DIR, "door_mahogany.png"))

    # 3. Window from psx-white-house (crop out outer brick border so it fits cleanly on pastel walls)
    win = Image.open(os.path.join(WHITE_HOUSE_DIR, "WindowsHouseOld0417_1_350.jpg")).convert("RGB")
    ww, wh = win.size
    win = win.crop((int(ww * 0.14), int(wh * 0.04), int(ww * 0.86), int(wh * 0.96)))
    win64 = win.resize((64, 64), Image.Resampling.BOX)
    win64 = quantize_psx(win64, 32)
    win64.save(os.path.join(OUT_DIR, "window_wood_whitehouse.png"))

    # 4. Dark shingle roof from psx-white-house
    roof = Image.open(os.path.join(WHITE_HOUSE_DIR, "RoofTexture.png")).convert("RGB")
    rw, rh = roof.size
    roof = roof.crop((0, 0, rh, rh))
    roof64 = make_tileable_64(roof)
    roof64 = quantize_psx(roof64, 24)
    roof64.save(os.path.join(OUT_DIR, "roof_shingle_dark.png"))


def generate_from_nortimore():
    direct_copies = {
        "techovillapalmar.png": "roof_teja.png",
        "puertamaderavillapalmar.png": "door_andina.png",
        "paloPalmar.png": "wood_post.png",
        "palmarhousevillasuelo.png": "floor_terracotta.png",
        "muralgray.png": "stone_gray.png",
        "pozowallmural.png": "stone_rustic.png",
        "cercaCC 1.png": "fence_wood.png",
    }
    for src, dst in direct_copies.items():
        im = Image.open(os.path.join(NORTIMORE_DIR, src)).convert("RGB")
        if im.size != (64, 64):
            im = im.resize((64, 64), Image.Resampling.NEAREST)
        im.save(os.path.join(OUT_DIR, dst))

    # Extract warm stone plinth from bottom of wallpalmarhou.png (rows 51..63 = pure stone, no white stucco)
    wall = Image.open(os.path.join(NORTIMORE_DIR, "wallpalmarhou.png")).convert("RGB")
    plinth_strip = wall.crop((0, 51, 64, 64))  # 64x13
    plinth = Image.new("RGB", (64, 64))
    y = 0
    row_idx = 0
    while y < 64:
        shift = (row_idx * 19) % 64
        shifted = Image.new("RGB", (64, 13))
        shifted.paste(plinth_strip.crop((shift, 0, 64, 13)), (0, 0))
        shifted.paste(plinth_strip.crop((0, 0, shift, 13)), (64 - shift, 0))
        plinth.paste(shifted, (0, y))
        y += 13
        row_idx += 1
    plinth.save(os.path.join(OUT_DIR, "stone_plinth_warm.png"))

    # Extract crisp barred Andean window from VillapalmarhouserWindows.png (strictly inside wooden frame)
    win_panel = Image.open(os.path.join(NORTIMORE_DIR, "VillapalmarhouserWindows.png")).convert("RGB")
    win_crop = win_panel.crop((18, 17, 46, 43)).resize((64, 64), Image.Resampling.NEAREST)
    win_crop.save(os.path.join(OUT_DIR, "window_reja.png"))


def generate_calamina(oxidized: bool, filename: str, seed: int):
    """Generate 64x64 PSX corrugated metal (calamina) texture."""
    rng = random.Random(seed)
    img = Image.new("RGB", (64, 64))
    px = img.load()

    # Precompute subtle rust blobs if oxidized
    rust_spots = []
    if oxidized:
        for _ in range(18):
            rust_spots.append((rng.uniform(0, 64), rng.uniform(0, 64), rng.uniform(4.0, 12.0), rng.uniform(0.45, 0.95)))

    for y in range(64):
        # Horizontal sheet overlap seam at y == 31..32
        seam_dark = -28 if y == 32 else (14 if y == 31 else 0)
        for x in range(64):
            # 16 corrugations across 64px (4px wavelength)
            phase = (x % 4) / 4.0 * 2.0 * math.pi
            rib = math.sin(phase)
            noise = rng.randint(-7, 7)

            # Base galvanized metal color (slightly cool silvery gray)
            base_v = 148 + int(rib * 28) + seam_dark + noise
            r = base_v - 4
            g = base_v
            b = base_v + 6

            # Rivet dots along seam
            if y == 30 and (x % 8 == 1):
                r, g, b = r - 35, g - 35, b - 35

            if oxidized:
                rust_amt = 0.0
                for rx, ry, rad, strength in rust_spots:
                    # Wrap distance for tiling
                    dx = min(abs(x - rx), 64 - abs(x - rx))
                    dy = min(abs(y - ry), 64 - abs(y - ry))
                    dist = math.hypot(dx, dy)
                    if dist < rad:
                        w = (1.0 - dist / rad) ** 1.4 * strength
                        rust_amt = max(rust_amt, w)
                # Extra rust along horizontal seam and valleys
                if abs(y - 32) <= 3:
                    rust_amt = min(1.0, rust_amt + 0.38 * (1.0 - abs(y - 32) / 4.0))
                if rib < -0.3:
                    rust_amt = min(1.0, rust_amt + 0.12)
                rust_amt = max(0.0, min(1.0, rust_amt + rng.uniform(-0.08, 0.08)))
                # Rust palette: warm sienna / burnt umber
                rr = 128 + int(rib * 16) + rng.randint(-10, 10)
                rg = 66 + int(rib * 10) + rng.randint(-6, 6)
                rb = 38 + int(rib * 6) + rng.randint(-4, 4)
                r = int(r * (1 - rust_amt) + rr * rust_amt)
                g = int(g * (1 - rust_amt) + rg * rust_amt)
                b = int(b * (1 - rust_amt) + rb * rust_amt)

            px[x, y] = (
                max(20, min(235, r)),
                max(20, min(235, g)),
                max(20, min(235, b)),
            )

    img = quantize_psx(img, 28)
    img.save(os.path.join(OUT_DIR, filename))


def generate_quincha(base_rgb, light_variant: bool, filename: str, seed: int):
    """Generate 64x64 PSX adobe / quincha mud-wall texture with subtle straw & mud-brick courses."""
    rng = random.Random(seed)
    img = Image.new("RGB", (64, 64))
    px = img.load()

    # Soft blotches for hand-plastered mud unevenness
    blotches = [(rng.uniform(0, 64), rng.uniform(0, 64), rng.uniform(6, 16), rng.uniform(-16, 14)) for _ in range(22)]

    for y in range(64):
        # Subtle adobe brick / quincha horizontal courses every 8px
        course = (y % 8 == 0)
        brick_row = y // 8
        for x in range(64):
            vert_joint = ((x + (brick_row % 2) * 8) % 16 == 0)
            delta = rng.randint(-8, 8)
            for bx, by, rad, dv in blotches:
                dx = min(abs(x - bx), 64 - abs(x - bx))
                dy = min(abs(y - by), 64 - abs(y - by))
                d = math.hypot(dx, dy)
                if d < rad:
                    delta += int(dv * (1.0 - d / rad))
            if course:
                delta -= 10 if light_variant else 14
            if vert_joint and not course:
                delta -= 6 if light_variant else 9

            r = max(25, min(225, base_rgb[0] + delta))
            g = max(22, min(215, base_rgb[1] + int(delta * 0.92)))
            b = max(18, min(200, base_rgb[2] + int(delta * 0.80)))
            px[x, y] = (r, g, b)

    # Tiny straw flecks (ichú / paja en el barro)
    draw = ImageDraw.Draw(img)
    for _ in range(38):
        sx = rng.randint(0, 62)
        sy = rng.randint(0, 63)
        straw_col = (
            min(220, base_rgb[0] + 34),
            min(205, base_rgb[1] + 28),
            min(175, base_rgb[2] + 12),
        )
        draw.line([(sx, sy), (sx + rng.choice([1, 2]), sy + rng.choice([-1, 0, 1]))], fill=straw_col)

    # Subtle weathered plaster cracks
    for _ in range(4):
        cx, cy = rng.randint(6, 58), rng.randint(6, 58)
        for _ in range(7):
            nx = max(0, min(63, cx + rng.randint(-1, 1)))
            ny = max(0, min(63, cy + rng.randint(0, 2)))
            px[nx, ny] = (max(20, base_rgb[0] - 34), max(18, base_rgb[1] - 30), max(14, base_rgb[2] - 24))
            cx, cy = nx, ny

    img = quantize_psx(img, 28)
    img.save(os.path.join(OUT_DIR, filename))


def generate_wood_dark_trim():
    """64x64 dark Andean timber derived from Nortimore paloPalmar for beams/balconies."""
    src = Image.open(os.path.join(NORTIMORE_DIR, "paloPalmar.png")).convert("RGB")
    # Top 48px of paloPalmar is dark wood grain (bottom is lighter floor edge)
    wood_crop = src.crop((0, 0, 64, 48)).resize((64, 64), Image.Resampling.NEAREST)
    wood_crop.save(os.path.join(OUT_DIR, "wood_beam.png"))


def make_contact_sheet():
    files = sorted([f for f in os.listdir(OUT_DIR) if f.endswith(".png")])
    cols = 4
    rows = (len(files) + cols - 1) // cols
    cell = 152
    sheet = Image.new("RGB", (cols * cell, rows * cell), (28, 30, 34))
    draw = ImageDraw.Draw(sheet)
    for i, f in enumerate(files):
        r, c = divmod(i, cols)
        im = Image.open(os.path.join(OUT_DIR, f)).convert("RGB").resize((128, 128), Image.Resampling.NEAREST)
        sheet.paste(im, (c * cell + 12, r * cell + 6))
        draw.text((c * cell + 6, r * cell + 136), f[:-4][:22], fill=(235, 235, 235))
    out = r"C:\Users\bill\.gemini\antigravity\brain\aec6b34e-ede5-418a-8c77-3a4d3d9a5402\scratch\unified_textures_64.png"
    sheet.save(out)
    print(f"Generated {len(files)} textures in {OUT_DIR}")
    print(f"Contact sheet: {out}")


if __name__ == "__main__":
    generate_from_white_house()
    generate_from_nortimore()
    generate_wood_dark_trim()
    generate_calamina(oxidized=False, filename="roof_calamina_galv.png", seed=101)
    generate_calamina(oxidized=True, filename="roof_calamina_oxido.png", seed=202)
    generate_quincha((158, 120, 86), light_variant=False, filename="wall_quincha_barro.png", seed=303)
    generate_quincha((182, 148, 112), light_variant=True, filename="wall_quincha_claro.png", seed=404)
    make_contact_sheet()
