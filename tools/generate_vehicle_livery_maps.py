#!/usr/bin/env python3
"""
Generate compact RGBA livery data maps (`game/assets/rally/liveries/<car_key>_livery_data.png`)
for all 17 CDI vehicles using each vehicle's real Cycles lightmap (`R=AO`, `G=dot(N,L)`),
part masks / UV regions, and raw albedo panel seams from D:\\RallyManiacAssets.

Channels of `<car_key>_livery_data.png`:
  R: paint_mask
       255 (1.00) -> main body paint (recolored in all liveries)
       153 (0.60) -> optional original-only accent (e.g., Lotus Cortina green side stripe:
                     kept untouched on its original Blanco livery, painted solid on all other 15)
         0 (0.00) -> non-paint details (glass, chrome, lights, plates, badges, Mini white roof)
  G: Cycles AO (`lightmap.R`) — mask-aware downsampled to `effective_res` for Porsche 911 PSX parity
  B: Cycles directional `dot(N,L)` encoded (`lightmap.G`) — mask-aware downsampled to `effective_res`
  A: Panel seam/crease multiplier from `albedo_raw` (255 = flat body, <255 = baked door/panel seams)

Usage:
  python tools/generate_vehicle_livery_maps.py
  python tools/generate_vehicle_livery_maps.py --diag-dir <path>
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parent.parent
ASSETS_ROOT = Path(r"D:\RallyManiacAssets")
OUT_DIR = REPO / "game" / "assets" / "rally" / "liveries"


def _resize_f32(arr: np.ndarray, size: tuple[int, int], resample) -> np.ndarray:
    w, h = size
    if arr.shape == (h, w):
        return arr.astype(np.float32, copy=False)
    img = Image.fromarray(arr.astype(np.float32), mode="F")
    return np.asarray(img.resize((w, h), resample), dtype=np.float32)


def _downsample_masked_3ch(arr: np.ndarray, mask: np.ndarray, target_size: tuple[int, int]) -> np.ndarray:
    """Mask-aware BOX downsample so non-paint regions never bleed into body paint."""
    w, h = target_size
    if (arr.shape[1], arr.shape[0]) == (w, h):
        return arr.astype(np.float32, copy=False)
    m_f = mask.astype(np.float32)
    m_down = _resize_f32(m_f, (w, h), Image.Resampling.BOX)
    valid = m_down > 1e-4
    out = np.empty((h, w, arr.shape[2]), dtype=np.float32)
    for c in range(arr.shape[2]):
        fb = _resize_f32(arr[..., c], (w, h), Image.Resampling.BOX)
        ch_down = _resize_f32(arr[..., c] * m_f, (w, h), Image.Resampling.BOX)
        out[..., c] = np.where(valid, ch_down / np.maximum(m_down, 1e-4), fb)
    return out


def _nearest_upscale_3ch(arr: np.ndarray, target_size: tuple[int, int]) -> np.ndarray:
    w, h = target_size
    if (arr.shape[1], arr.shape[0]) == (w, h):
        return arr
    out = np.empty((h, w, arr.shape[2]), dtype=np.float32)
    for c in range(arr.shape[2]):
        out[..., c] = _resize_f32(arr[..., c], (w, h), Image.Resampling.NEAREST)
    return out


def _id_mask(id_map_path: Path, color: tuple[int, int, int], size: tuple[int, int], tol: int = 36) -> np.ndarray:
    with Image.open(id_map_path) as im:
        rgb = im.convert("RGB")
        if rgb.size != size:
            rgb = rgb.resize(size, Image.Resampling.NEAREST)
        arr = np.asarray(rgb, dtype=np.int16)
    target = np.asarray(color, dtype=np.int16)
    return np.all(np.abs(arr - target[None, None, :]) <= tol, axis=2)


def _porsche911_mask(size: tuple[int, int]) -> np.ndarray:
    """Exact inverse of non-paint regions from porsche_911_24s_stylized.json."""
    w, h = size
    canvas = Image.new("L", (w, h), 255)
    draw = ImageDraw.Draw(canvas)
    sx, sy = w / 1024.0, h / 1024.0
    exclude_rects = [
        [0, 0, 44, 44],        # trim_swatches
        [748, 0, 1024, 320],   # lights_badges_text
        [854, 320, 1024, 672], # rear_grille
        [846, 672, 1024, 868], # windows_glass
        [730, 868, 1024, 1024],# wheel_unused_in_chassis
    ]
    for x0, y0, x1, y1 in exclude_rects:
        draw.rectangle([x0 * sx, y0 * sy, x1 * sx - 1, y1 * sy - 1], fill=0)
    return np.asarray(canvas) > 127


def _mini_cooper_mask(src_path: Path, size: tuple[int, int]) -> np.ndarray:
    """Select only the red body paint on Mini Cooper S, preserving the white roof,
    #2 door roundels, Rallye Monte Carlo hood plaque, 10NZ/GB plates, grille,
    headlights, taillights, glass, wheels, and underbody."""
    with Image.open(src_path) as im:
        rgb = im.convert("RGB")
        if rgb.size != size:
            rgb = rgb.resize(size, Image.Resampling.NEAREST)
        arr = np.asarray(rgb, dtype=np.float32)

    w, h = size
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    # Strong red body paint test (excludes white roof, grey chrome, black glass, amber blinkers)
    red_paint = (
        (r > 65.0)
        & (r > g * 1.48)
        & (r > b * 1.48)
        & ((r - np.maximum(g, b)) > 30.0)
    )

    # Exclude non-body regions that contain red (red wheel rim, taillight swatch, underbody, Monte Carlo plaque)
    excl = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(excl)
    sx, sy = w / 512.0, h / 512.0
    exclude_rects = [
        [0, 296, 200, 512],    # wheels region (bottom-left includes red rim)
        [296, 368, 358, 410],  # taillight / blinker swatch (bottom-center)
        [248, 405, 512, 512],  # underbody
        [78, 154, 108, 210],   # Rallye Monte Carlo hood plaque (red & white banner)
        [0, 0, 118, 90],       # front headlights / auxiliary lamps
        [440, 248, 512, 344],  # auxiliary spotlights
    ]
    for x0, y0, x1, y1 in exclude_rects:
        draw.rectangle([x0 * sx, y0 * sy, x1 * sx - 1, y1 * sy - 1], fill=255)
    excl_mask = np.asarray(excl) > 127
    return red_paint & (~excl_mask)


def _golfmk1_mask(id_map_path: Path, albedo_path: Path, size: tuple[int, int]) -> np.ndarray:
    """Intersect Golf Mk1 body part mask with orange-paint chroma so black plastic flares,
    bumpers, grille, and dark trim remain untouched."""
    part = _id_mask(id_map_path, (255, 0, 0), size)
    with Image.open(albedo_path) as im:
        rgb = im.convert("RGB")
        if rgb.size != size:
            rgb = rgb.resize(size, Image.Resampling.NEAREST)
        arr = np.asarray(rgb, dtype=np.float32)
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    orange_paint = (
        (r > 85.0)
        & (r > b * 1.55)
        & (g > b * 1.15)
        & ((r - b) > 35.0)
    )
    return part & orange_paint


def _extract_seam_detail(albedo_path: Path | None, paint_mask: np.ndarray, size: tuple[int, int], flat_body: bool, sparse_seams: bool = False) -> np.ndarray:
    """Return [0..1] seam multiplier (1.0 on flat painted panels, <1.0 on baked door/panel seams)."""
    w, h = size
    if flat_body or albedo_path is None or not albedo_path.exists():
        return np.ones((h, w), dtype=np.float32)
    with Image.open(albedo_path) as im:
        rgb = im.convert("RGB")
        if rgb.size != size:
            rgb = rgb.resize(size, Image.Resampling.BOX)
        arr = np.asarray(rgb, dtype=np.float32) / 255.0
    luma = 0.299 * arr[..., 0] + 0.587 * arr[..., 1] + 0.114 * arr[..., 2]
    samples = luma[paint_mask & (luma > 0.02)]
    if samples.size < 64:
        return np.ones((h, w), dtype=np.float32)
    p50 = float(np.percentile(samples, 50))
    p90 = float(np.percentile(samples, 90))
    # If the raw albedo has virtually zero variation (flat color bake), keep 1.0 cleanly.
    low = float(samples.min() if sparse_seams else np.percentile(samples, 5))
    if (p90 - low) < 0.03:
        return np.ones((h, w), dtype=np.float32)
    ref = max(p50, 0.05)
    seam = np.clip(luma / ref, 0.28, 1.0)
    # Keep slight brightenings clamped at 1.0 so bright seams/noise never wash out target hex
    seam = np.where(seam > 0.94, 1.0, seam)
    return seam.astype(np.float32)


def _load_lightmap(path: Path, size: tuple[int, int]) -> tuple[np.ndarray, np.ndarray]:
    with Image.open(path) as im:
        rgb = im.convert("RGB")
        if rgb.size != size:
            rgb = rgb.resize(size, Image.Resampling.BOX)
        arr = np.asarray(rgb, dtype=np.float32) / 255.0
    return arr[..., 0], arr[..., 1]


def fbx_exterior_spec(car_key: str, work: Path) -> dict:
    return {
        "car_key": car_key,
        "size": (1024, 1024),
        "effective_scale": 0.5,
        "lightmap": work / ("lightmap_polished.png" if car_key == "rt-lancia-stratos" else "lightmap.png"),
        "albedo_raw": work / "albedo_raw.png",
        "mask_mode": "id_map",
        "id_map": work / "part_mask.png",
        "flat_body": False,
    }


SPECS: list[dict] = [
    # --- Group A: Dedicated *_BodyPaint_PSX material (10 cars) ---
    {
        "car_key": "fulvia",
        "size": (512, 512),
        "effective_scale": 1.0,
        "lightmap": ASSETS_ROOT / "fulvia_guinda_psx" / "fulvia_body_lightmap.png",
        "albedo_raw": ASSETS_ROOT / "fulvia_guinda_psx" / "fulvia_body_albedo_raw.png",
        "mask_mode": "full",
        "flat_body": True,
    },
    {
        "car_key": "escort",
        "size": (512, 512),
        "effective_scale": 1.0,
        "lightmap": ASSETS_ROOT / "escort_mk1_crema_psx" / "escort_mk1_body_lightmap.png",
        "albedo_raw": ASSETS_ROOT / "escort_mk1_crema_psx" / "escort_mk1_body_albedo_raw.png",
        "mask_mode": "full",
        "flat_body": True,
    },
    {
        "car_key": "rt-alfa-giulia-gta",
        "size": (1024, 1024),
        "effective_scale": 1.0,
        "lightmap": ASSETS_ROOT / "alfa1750_clean_uv" / "body_lightmap.png",
        "albedo_raw": ASSETS_ROOT / "alfa1750_clean_uv" / "body_albedo_raw_ocra.png",
        "mask_mode": "exclude_baked_mask",
        "exclude_mask": ASSETS_ROOT / "alfa1750_clean_uv" / "body_baked_details_mask.png",
        "flat_body": True,
    },
    {
        "car_key": "rt-fiat-abarth-1000",
        "size": (512, 512),
        "effective_scale": 1.0,
        "lightmap": ASSETS_ROOT / "fiat500_negro_psx" / "fiat500_body_lightmap.png",
        "albedo_raw": ASSETS_ROOT / "fiat500_negro_psx" / "fiat500_body_albedo_raw.png",
        "mask_mode": "full",
        "flat_body": True,
    },
    fbx_exterior_spec("rt-lancia-stratos", ASSETS_ROOT / "cdi_fbx_psx" / "rt-lancia-stratos"),
    {
        "car_key": "rt-porsche-356b-2000gs",
        "size": (1024, 1024),
        "effective_scale": 1.0,
        "lightmap": ASSETS_ROOT / "porsche356_clean_uv" / "body_lightmap.png",
        "albedo_raw": ASSETS_ROOT / "porsche356_clean_uv" / "body_albedo_raw_red.png",
        "mask_mode": "exclude_baked_mask",
        "exclude_mask": ASSETS_ROOT / "porsche356_clean_uv" / "body_baked_details_mask.png",
        "flat_body": True,
    },
    {
        "car_key": "rt-saab-96-v4",
        "size": (512, 512),
        "effective_scale": 1.0,
        "lightmap": ASSETS_ROOT / "saab_96_psx" / "saab96_body_lightmap.png",
        "albedo_raw": ASSETS_ROOT / "saab_96_psx" / "saab96_body_albedo_raw.png",
        "mask_mode": "full",
        "flat_body": True,
    },
    {
        "car_key": "rt-volvo-amazon",
        "size": (512, 512),
        "effective_scale": 1.0,
        "lightmap": ASSETS_ROOT / "volvo_123gt_psx" / "volvo123_body_lightmap.png",
        "albedo_raw": ASSETS_ROOT / "volvo_123gt_psx" / "volvo123_body_albedo_raw.png",
        "mask_mode": "full",
        "flat_body": True,
    },
    {
        "car_key": "fiat131",
        "size": (512, 512),
        "effective_scale": 1.0,
        "lightmap": ASSETS_ROOT / "fiat131_azul_psx" / "fiat131_body_lightmap.png",
        "albedo_raw": ASSETS_ROOT / "fiat131_azul_psx" / "fiat131_body_albedo_raw.png",
        "mask_mode": "full",
        "flat_body": True,
    },
    {
        "car_key": "gaz24",
        "size": (512, 512),
        "effective_scale": 1.0,
        "lightmap": ASSETS_ROOT / "gaz24_negro_psx" / "gaz24_body_lightmap.png",
        "albedo_raw": ASSETS_ROOT / "gaz24_negro_psx" / "gaz24_body_albedo_raw.png",
        "mask_mode": "full",
        "flat_body": True,
    },
    # --- Group B: Dedicated Paint material on shared atlas (1 car) ---
    {
        "car_key": "f10070",
        "size": (512, 512),
        "effective_scale": 1.0,
        "lightmap": ASSETS_ROOT / "cdi_stylized" / "f10070" / "f10070_lightmap.png",
        "albedo_raw": REPO / "game" / "assets" / "rally" / "ford_f100_1970" / "chassis_pickup_body_ps1.png",
        "mask_mode": "full",
        "flat_body": True,
    },
    # --- Group C: Single/Combined Exterior Atlas (6 cars) ---
    {
        "car_key": "rt-alpine-a110",
        "size": (1024, 1024),
        "effective_scale": 1.0,
        "lightmap": ASSETS_ROOT / "cdi_stylized" / "rt-alpine-a110" / "alpine_chassis_lightmap.png",
        "albedo_raw": ASSETS_ROOT / "cdi_stylized" / "rt-alpine-a110" / "alpine_chassis_albedo_raw.png",
        "mask_mode": "id_map",
        "id_map": ASSETS_ROOT / "cdi_stylized" / "rt-alpine-a110" / "alpine_chassis_part_mask.png",
        "flat_body": True,
    },
    {
        "car_key": "rt-lotus-cortina",
        "size": (1024, 1024),
        "effective_scale": 1.0,
        "lightmap": ASSETS_ROOT / "lotus_cortina_mk1_psx" / "cortina_chassis_lightmap.png",
        "albedo_raw": ASSETS_ROOT / "lotus_cortina_mk1_psx" / "cortina_chassis_albedo_raw.png",
        "mask_mode": "cortina_stripe",
        "id_map": ASSETS_ROOT / "lotus_cortina_mk1_psx" / "cortina_chassis_part_mask.png",
        "flat_body": True,
    },
    {
        "car_key": "rt-mini-cooper-s",
        "size": (512, 512),
        "effective_scale": 1.0,
        "lightmap": ASSETS_ROOT / "cdi_stylized" / "rt-mini-cooper-s" / "rt-mini-cooper-s_lightmap.png",
        "albedo_raw": REPO / "game" / "assets" / "rally" / "rt" / "rt-mini-cooper-s" / "chassis_mini_cooper_S_alta.png",
        "mask_mode": "mini_cooper",
        "flat_body": False,
    },
    {
        "car_key": "mustang67",
        "size": (1024, 1024),
        "effective_scale": 1.0,
        "lightmap": ASSETS_ROOT / "ford_mustang_1967_psx" / "mustang_chassis_lightmap.png",
        "albedo_raw": ASSETS_ROOT / "ford_mustang_1967_psx" / "mustang_chassis_albedo_raw.png",
        "mask_mode": "id_map",
        "id_map": ASSETS_ROOT / "ford_mustang_1967_psx" / "mustang_chassis_part_mask.png",
        "flat_body": True,
    },
    {
        "car_key": "golfmk1",
        "size": (1024, 1024),
        "effective_scale": 1.0,
        "lightmap": ASSETS_ROOT / "cdi_stylized" / "golfmk1" / "golf_chassis_lightmap.png",
        "albedo_raw": ASSETS_ROOT / "cdi_stylized" / "golfmk1" / "golf_chassis_albedo_raw.png",
        "mask_mode": "golfmk1",
        "id_map": ASSETS_ROOT / "cdi_stylized" / "golfmk1" / "golf_chassis_part_mask.png",
        "flat_body": True,
    },
    {
        "car_key": "porsche911",
        "size": (1024, 1024),
        "effective_scale": 0.5,
        "lightmap": ASSETS_ROOT / "porsche_911_24s_psx" / "porsche_911_24s_lightmap.png",
        "albedo_raw": REPO / "game" / "assets" / "rally" / "porsche_911_24s" / "porsche_911_24s_diffuse.png",
        "mask_mode": "porsche911",
        "flat_body": False,
    },
]


def build_one(spec: dict, diag_dir: Path | None) -> tuple[Path, float]:
    car_key = spec["car_key"]
    size = spec["size"]
    w, h = size
    lm_path: Path = spec["lightmap"]
    if not lm_path.exists():
        raise FileNotFoundError(f"Missing lightmap for {car_key}: {lm_path}")

    mode = spec["mask_mode"]
    stripe_mask = np.zeros((h, w), dtype=bool)
    if mode == "full":
        body_mask = np.ones((h, w), dtype=bool)
    elif mode == "exclude_baked_mask":
        with Image.open(spec["exclude_mask"]) as ex_im:
            ex_arr = np.asarray(ex_im.convert("L").resize(size, Image.Resampling.NEAREST), dtype=np.uint8)
        body_mask = ex_arr <= 32
    elif mode == "id_map":
        body_mask = _id_mask(spec["id_map"], (255, 0, 0), size)
    elif mode == "cortina_stripe":
        body_mask = _id_mask(spec["id_map"], (255, 0, 0), size)
        stripe_mask = _id_mask(spec["id_map"], (0, 255, 0), size) & (~body_mask)
    elif mode == "porsche911":
        body_mask = _porsche911_mask(size)
    elif mode == "mini_cooper":
        body_mask = _mini_cooper_mask(spec["albedo_raw"], size)
    elif mode == "golfmk1":
        body_mask = _golfmk1_mask(spec["id_map"], spec["albedo_raw"], size)
    else:
        raise ValueError(f"Unknown mask_mode: {mode}")

    any_paint = body_mask | stripe_mask
    ao, dot_nl = _load_lightmap(lm_path, size)
    seam = _extract_seam_detail(spec.get("albedo_raw"), body_mask, size, spec.get("flat_body", True),
                                sparse_seams=car_key == "rt-lancia-stratos")
    # On Lotus Cortina's green stripe, keep seam=1.0 so non-original liveries paint seamlessly over the stripe
    if stripe_mask.any():
        seam[stripe_mask] = 1.0

    # Match ps1kit effective_scale mask-aware BOX downsample for G, B, A so UV boundaries never bleed
    eff_scale = float(spec.get("effective_scale", 1.0))
    if eff_scale < 0.999:
        work_size = (max(1, round(w * eff_scale)), max(1, round(h * eff_scale)))
        packed_gba = np.stack([ao, dot_nl, seam], axis=-1)
        down_gba = _downsample_masked_3ch(packed_gba, any_paint, work_size)
        up_gba = _nearest_upscale_3ch(down_gba, size)
        ao, dot_nl, seam = up_gba[..., 0], up_gba[..., 1], up_gba[..., 2]

    r_u8 = np.zeros((h, w), dtype=np.uint8)
    r_u8[body_mask] = 255
    r_u8[stripe_mask] = 153  # 0.60 -> excluded when threshold=0.80 (original), included when threshold=0.30
    g_u8 = np.clip(np.round(ao * 255.0), 0, 255).astype(np.uint8)
    b_u8 = np.clip(np.round(dot_nl * 255.0), 0, 255).astype(np.uint8)
    a_u8 = np.clip(np.round(seam * 255.0), 0, 255).astype(np.uint8)

    rgba = np.stack([r_u8, g_u8, b_u8, a_u8], axis=-1)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUT_DIR / f"{car_key}_livery_data.png"
    Image.fromarray(rgba, mode="RGBA").save(out_path, optimize=True)

    # Optional visual diagnostic overlay for masked cars
    if diag_dir is not None and mode != "full":
        diag_dir.mkdir(parents=True, exist_ok=True)
        with Image.open(spec["albedo_raw"]) as src_im:
            base = np.asarray(src_im.convert("RGB").resize(size, Image.Resampling.NEAREST), dtype=np.float32)
        vis = base.copy()
        # Highlight body mask in bright cyan tint, stripe mask in magenta tint
        vis[body_mask] = vis[body_mask] * 0.35 + np.array([30.0, 220.0, 255.0]) * 0.65
        if stripe_mask.any():
            vis[stripe_mask] = vis[stripe_mask] * 0.35 + np.array([255.0, 40.0, 220.0]) * 0.65
        Image.fromarray(np.clip(vis, 0, 255).astype(np.uint8), mode="RGB").save(
            diag_dir / f"mask_overlay_{car_key}.png"
        )

    coverage = float(any_paint.mean()) * 100.0
    return out_path, coverage


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate RGBA PSX livery data maps for all 17 CDI vehicles.")
    parser.add_argument("--diag-dir", type=Path, default=None, help="Optional directory to save mask overlay previews")
    args = parser.parse_args()

    total_bytes = 0
    for spec in SPECS:
        out_path, cov = build_one(spec, args.diag_dir)
        sz = out_path.stat().st_size
        total_bytes += sz
        print(f"OK {spec['car_key']:24s} -> {out_path.name:38s} {spec['size'][0]}x{spec['size'][1]} paint={cov:5.1f}% size={sz/1024:6.1f} KB")
    print(f"GENERATED {len(SPECS)} LIVERY DATA MAPS ({total_bytes / 1024.0 / 1024.0:.2f} MB total)")


if __name__ == "__main__":
    main()
