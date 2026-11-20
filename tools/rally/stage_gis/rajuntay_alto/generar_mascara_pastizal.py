"""Build an aligned, continuous grass coverage mask from local Sentinel-2 and DEM."""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image
import rasterio
from scipy.ndimage import gaussian_filter

from generar_ss01 import OUT, STAGE_ID


def smooth(low, high, value):
    weight = np.clip((value - low) / (high - low), 0, 1)
    return weight * weight * (3 - 2 * weight)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    stages = parser.add_mutually_exclusive_group()
    stages.add_argument("--ss03", action="store_true", help="Use Chinchán Asfalto.")
    stages.add_argument("--ss04", action="store_true", help="Use Abra Ticlio.")
    stages.add_argument("--ss02", action="store_true", help="Align the mask to Quebrada Chinchán.")
    args = parser.parse_args()
    stage = json.loads((OUT / "scene_input.json").read_text())
    with rasterio.open(args.source / f"{STAGE_ID}_Sentinel2_RGBN_10m.tif") as satellite, rasterio.open(
        args.source / f"{STAGE_ID}_DEM_GLO30_remuestreado_10m.tif"
    ) as dem:
        if (satellite.crs, satellite.transform, satellite.shape) != (dem.crs, dem.transform, dem.shape):
            raise ValueError("Satellite and DEM grids differ")
        bounds = satellite.bounds
        red, green, blue, nir = satellite.read(out_dtype="float32")
        elevation = dem.read(1, out_dtype="float32")
        cell = satellite.res[0]
    if np.median(red) > 2:
        red, green, blue, nir = [band * 0.0001 - 0.1 for band in (red, green, blue, nir)]
    ndvi = gaussian_filter((nir - red) / np.maximum(nir + red, 0.04), 1.5)
    brightness = gaussian_filter((red + green + blue) / 3, 2)
    height = gaussian_filter(elevation, 1.2)
    slope = np.hypot(*np.gradient(height, cell))
    hollow = gaussian_filter(height, 5) - height
    bright_low, bright_high = np.percentile(brightness, [20, 85])
    sparse = smooth(bright_low, bright_high, brightness) * (1 - smooth(0.16, 0.34, ndvi) * 0.65)
    olive = smooth(0.17, 0.34, ndvi) * (0.38 + 0.62 * smooth(0, 9, hollow)) * (1 - smooth(0.28, 0.65, slope))
    mineral = smooth(0.24, 0.69, slope) * (1 - smooth(0.13, 0.27, ndvi)) * 0.85
    weights = np.stack((sparse, olive, mineral), axis=-1)
    if not np.isfinite(weights).all():
        raise ValueError("Invalid coverage weights")
    args.output.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.rint(weights * 255).astype(np.uint8)).save(args.output / "pastizal_gis.png")
    if STAGE_ID == "SS04":
        # Snow deposits use the DEM, plus coherent wind redistribution to
        # break up contours. This same raster drives the terrain and ichu.
        random = np.random.default_rng(4104).standard_normal(height.shape)
        broad = gaussian_filter(random, 4.5)
        fine = gaussian_filter(random, 1.25)
        wind = np.clip(0.50 + 0.22 * broad / broad.std() + 0.08 * fine / fine.std(), 0, 1)
        relative_height = height - float(stage["z0"])
        alpine = smooth(76, 296, relative_height)
        shelter = smooth(-2, 13, hollow)
        ridge = 1 - smooth(-15, -3, hollow)
        rock_face = smooth(0.28, 0.85, slope)
        deposit = alpine * 0.74 + (wind - 0.50) * 0.95 + shelter * 0.30 - ridge * 0.24 - rock_face * 0.30
        snow = smooth(0.24, 0.84, deposit) * smooth(65, 112, relative_height)
        snow *= 0.55 + 0.45 * smooth(0.27, 0.52, wind + shelter * 0.15)
        Image.fromarray(np.rint(snow * 255).astype(np.uint8)).save(args.output / "nieve_gis.png")
    east, north = stage["origin"]
    mapping = [bounds.left - east, north - bounds.top, bounds.right - bounds.left, bounds.top - bounds.bottom]
    (args.output / "pastizal_gis.json").write_text(json.dumps(mapping) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
