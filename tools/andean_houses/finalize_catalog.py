#!/usr/bin/env python3
"""
Generate Godot showcase scene (casas_andinas_catalogo.tscn) and annotate
the 20-house overview render with numbered badges.
"""
import os
import json
from PIL import Image, ImageDraw, ImageFont

BASE_DIR = r"d:\rust-godot-vehicle-simulator\game\assets\rally\CDI\casas_andinas"
TSCN_PATH = r"d:\rust-godot-vehicle-simulator\game\scenes\rally\casas_andinas_catalogo.tscn"
SCRATCH_DIR = r"C:\Users\bill\.gemini\antigravity\brain\aec6b34e-ede5-418a-8c77-3a4d3d9a5402\scratch"
ARTIFACT_DIR = r"C:\Users\bill\.gemini\antigravity\brain\aec6b34e-ede5-418a-8c77-3a4d3d9a5402"


def generate_godot_scene(manifest):
    lines = ["[gd_scene load_steps=21 format=3]", ""]
    for idx, item in enumerate(manifest, start=1):
        lines.append(f'[ext_resource type="PackedScene" path="{item["glb"]}" id="{idx}"]')
    lines.extend([
        "",
        '[node name="CasasAndinasCatalogo" type="Node3D"]',
        "",
        '[node name="Sun" type="DirectionalLight3D" parent="."]',
        "transform = Transform3D(0.848, -0.371, 0.378, 0, 0.713, 0.701, -0.530, -0.594, 0.605, 0, 20, 0)",
        "shadow_enabled = true",
        "",
        '[node name="OverviewCamera" type="Camera3D" parent="."]',
        "transform = Transform3D(1, 0, 0, 0, 0.848, 0.530, 0, -0.530, 0.848, 0, 42, 68)",
        "fov = 42.0",
        "",
    ])

    cols, rows = 5, 4
    spacing_x, spacing_z = 11.4, 11.4
    for idx, item in enumerate(manifest):
        r, c = divmod(idx, cols)
        px = (c - (cols - 1) * 0.5) * spacing_x
        pz = ((rows - 1) * 0.5 - r) * spacing_z
        lines.append(f'[node name="{item["name"]}" parent="." instance=ExtResource("{idx + 1}")]')
        lines.append(f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {px:.2f}, 0, {pz:.2f})")
        lines.append("")

    with open(TSCN_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("WROTE TSCN:", TSCN_PATH)


def annotate_overview():
    raw_img = Image.open(os.path.join(SCRATCH_DIR, "catalogo_20_casas_raw.png")).convert("RGBA")
    w, h = raw_img.size
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    try:
        font_sm = ImageFont.truetype("arialbd.ttf", 14)
        font_title = ImageFont.truetype("arialbd.ttf", 26)
    except Exception:
        font_sm = ImageFont.load_default()
        font_title = font_sm

    # Top header banner
    draw.rectangle([(0, 0), (w, 54)], fill=(18, 22, 28, 215))
    draw.text(
        (24, 13),
        "CATALOGO PSX — 20 CASAS ANDINAS MODULARES (64x64 Nearest, Low-Poly Mate, 1 a 3 pisos)",
        fill=(245, 243, 235, 255),
        font=font_title,
    )

    with open(os.path.join(SCRATCH_DIR, "label_coords.json"), "r", encoding="utf-8") as f:
        coords = json.load(f)

    for item in coords:
        cx = int(item["u"] * w)
        cy = int((1.0 - item["v"]) * h)
        parts = item["name"].split("_")
        num = parts[0]
        short = " ".join(parts[1:])
        if len(short) > 22:
            short = short[:21] + "."
        label = f"#{num} {short}"
        bbox = draw.textbbox((0, 0), label, font=font_sm)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        pad_x, pad_y = 7, 4
        x0 = max(6, min(w - tw - 2 * pad_x - 6, cx - (tw // 2) - pad_x))
        y0 = max(60, min(h - th - 2 * pad_y - 6, cy - (th // 2) - pad_y))
        draw.rounded_rectangle(
            [(x0, y0), (x0 + tw + 2 * pad_x, y0 + th + 2 * pad_y)],
            radius=5,
            fill=(16, 18, 22, 215),
            outline=(235, 228, 210, 220),
            width=1,
        )
        draw.text((x0 + pad_x, y0 + pad_y - 1), label, fill=(252, 248, 235, 255), font=font_sm)

    final_img = Image.alpha_composite(raw_img, overlay).convert("RGB")
    out_art = os.path.join(ARTIFACT_DIR, "catalogo_20_casas_overview.png")
    out_proj = os.path.join(BASE_DIR, "catalogo_20_casas_overview.png")
    final_img.save(out_art)
    final_img.save(out_proj)
    print("SAVED OVERVIEW:", out_art)
    print("SAVED PROJECT COPY:", out_proj)


if __name__ == "__main__":
    with open(os.path.join(BASE_DIR, "catalog_manifest.json"), "r", encoding="utf-8") as f:
        manifest = json.load(f)
    generate_godot_scene(manifest)
    annotate_overview()
