"""Build an aligned, continuous grass coverage mask from local Sentinel-2 and DEM."""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image
import rasterio
from scipy.ndimage import gaussian_filter


def smooth(low, high, value):
    weight = np.clip((value - low) / (high - low), 0, 1)
    return weight * weight * (3 - 2 * weight)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    stage = json.loads((Path(__file__).parent / "output/scene_input.json").read_text())
    with rasterio.open(args.source / "SS01_Sentinel2_RGBN_10m.tif") as satellite, rasterio.open(
        args.source / "SS01_DEM_GLO30_remuestreado_10m.tif"
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
    east, north = stage["origin"]
    mapping = [bounds.left - east, north - bounds.top, bounds.right - bounds.left, bounds.top - bounds.bottom]
    (args.output / "pastizal_gis.json").write_text(json.dumps(mapping) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
