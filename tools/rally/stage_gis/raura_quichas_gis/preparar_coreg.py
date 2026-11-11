"""Normalize the AW3D30 datum and prepare conservative xDEM masks for Raura."""
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

import numpy as np
from pyproj import Transformer
from pyproj.enums import TransformDirection
import rasterio as rio
from rasterio.features import rasterize
from rasterio.warp import Resampling, reproject, transform_geom
from scipy.ndimage import binary_erosion, distance_transform_edt
import xdem

BASE = Path(__file__).resolve().parent
TERRAIN = BASE / "data/terrain"
OUT = TERRAIN / "coreg"
GLO = TERRAIN / "raura_copernicus_glo30_utm18s.tif"
ALOS = TERRAIN / "raura_aw3d30_utm18s.tif"
GRID96 = OUT / "us_nga_egm96_15.tif"
GRID08 = OUT / "us_nga_egm08_25.tif"
SCL = OUT / "raura_sentinel_scl_native.tif"
OSM = BASE / "data/roads/raura_quichas_highways.osm"
SCENE = BASE / "data/satellite/scene_stac_item.json"


def sha256(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def write_raster(path, data, profile, **tags):
    with rio.open(path, "w", **profile) as dataset:
        dataset.write(data, 1)
        dataset.update_tags(**tags)


def convert_heights(lon, lat, heights):
    # Orthometric H = ellipsoidal h - geoid undulation N.
    # Add N96 to recover h, then subtract N08 to obtain H08.
    if any(not p.is_file() or " " in str(p) for p in (GRID96, GRID08)):
        raise ValueError("Both local PROJ grids must exist in a path without spaces")
    degrees = "+proj=unitconvert +xy_in=deg +xy_out=rad"
    inverse_degrees = "+proj=unitconvert +xy_in=rad +xy_out=deg"
    steps = (
        f"+step +proj=vgridshift +grids={GRID96.as_posix()} +multiplier=1 "
        f"+step +inv +proj=vgridshift +grids={GRID08.as_posix()} +multiplier=1"
    )
    transformer = Transformer.from_pipeline(
        f"+proj=pipeline +step {degrees} {steps} +step {inverse_degrees}"
    )
    x, y, converted = transformer.transform(lon, lat, heights, errcheck=True)
    _, _, recovered = transformer.transform(
        x, y, converted, direction=TransformDirection.INVERSE, errcheck=True
    )
    np.testing.assert_allclose(recovered, heights, atol=1e-8, rtol=0)
    # Independently check the sign against the two grid values at a sample.
    mid = len(heights) // 2
    geoid = []
    for grid in (GRID96, GRID08):
        with rio.open(grid) as dataset:
            geoid.append(float(next(dataset.sample([(lon[mid], lat[mid])]))[0]))
    np.testing.assert_allclose(converted[mid] - heights[mid], geoid[0] - geoid[1], atol=0.3, rtol=0)
    return converted


def road_pixels(shape, transform, crs):
    osm = ET.parse(OSM).getroot()
    nodes = {n.get("id"): (float(n.get("lon")), float(n.get("lat"))) for n in osm.findall("node")}
    roads = []
    for way in osm.findall("way"):
        coords = [nodes[n.get("ref")] for n in way.findall("nd")]
        if len(coords) >= 2:
            roads.append(transform_geom("EPSG:4326", crs, {"type": "LineString", "coordinates": coords}))
    return rasterize(roads, out_shape=shape, transform=transform, all_touched=True).astype(bool)


def main():
    with rio.open(GLO) as glo, rio.open(ALOS) as alos:
        if (alos.crs, alos.transform, alos.shape) != (glo.crs, glo.transform, glo.shape):
            raise ValueError("DEM grids do not match")
        profile = glo.profile
        ref = glo.read(1, masked=True).filled(np.nan)
        src = alos.read(1, masked=True).filled(np.nan)
    profile.update(compress="deflate")
    transform, crs = profile["transform"], profile["crs"]
    shape = ref.shape
    spacing = (abs(transform.e), abs(transform.a))
    valid_alos = np.isfinite(src)
    common = valid_alos & np.isfinite(ref)
    y, x = np.where(valid_alos)
    east, north = transform * (x + 0.5, y + 0.5)
    lon, lat = Transformer.from_crs(crs, 4326, always_xy=True).transform(east, north)
    converted = convert_heights(lon, lat, src[valid_alos].astype(np.float64))
    output = np.full(shape, profile["nodata"], dtype=np.float32)
    output[valid_alos] = converted
    correction = converted - src[valid_alos]
    alos_output = OUT / "raura_aw3d30_egm2008_utm18s.tif"
    write_raster(alos_output, output, profile, vertical_datum="EGM2008",
                 vertical_epsg="3855", conversion="H96 + N96 - N08", source=ALOS.name)

    with rio.open(SCL) as scene:
        classes = np.zeros(shape, dtype=np.uint8)
        reproject(rio.band(scene, 1), classes, src_nodata=0, dst_crs=crs,
                  dst_transform=transform, dst_nodata=0, resampling=Resampling.nearest)
    mask_profile = dict(profile, dtype="uint8", nodata=None, predictor=1)
    # Class 5 is non-vegetated. Erode by two pixels to avoid class boundaries.
    bare = binary_erosion(classes == 5, structure=np.ones((3, 3)), iterations=2)
    gy, gx = np.gradient(ref, *spacing)
    slope = np.degrees(np.arctan(np.hypot(gx, gy)))
    slope_ok = (slope >= 5) & (slope <= 40)
    # Conservative proxy for persistent snow/ice without a temporal inventory.
    elevation_ok = (ref < 4700) & (output < 4700)
    away_from_roads = distance_transform_edt(~road_pixels(shape, transform, crs), sampling=spacing) > 60
    valid_neighborhood = binary_erosion(common, structure=np.ones((3, 3)))
    eligible = valid_neighborhood & bare & elevation_ok & slope_ok & away_from_roads

    row, col = np.indices(shape)
    # 600 m spatial blocks, with a 90 m separation between fit and holdout.
    holdout_blocks = (col // 20 + 2 * (row // 20)) % 5 == 0
    holdout = eligible & holdout_blocks
    fit = eligible & (distance_transform_edt(~holdout_blocks, sampling=spacing) > 90)
    aspect = np.degrees(np.arctan2(gy, gx)) % 360
    aspect_octants = [int(np.count_nonzero(fit & (aspect >= a) & (aspect < a+45)))
                      for a in range(0, 360, 45)]
    if int(fit.sum()) < 500 or int(holdout.sum()) < 100 or min(aspect_octants) < 10:
        raise ValueError(f"Insufficient mask support: fit={fit.sum()}, holdout={holdout.sum()}, aspects={aspect_octants}")
    if (fit & holdout).any():
        raise ValueError("Fit and holdout masks overlap")

    paths = {}
    for name, values in (("scl_utm18s", classes), ("mascara_estable_candidata", eligible),
                         ("mascara_ajuste", fit), ("mascara_validacion", holdout)):
        path = OUT / (name + ".tif")
        write_raster(path, values.astype("uint8"), mask_profile, meaning=(
            "Sentinel-2 L2A SCL classes" if name.startswith("scl") else "1=selected, 0=excluded"))
        paths[name] = path

    # Check that the installed xDEM can consume both rasters and the fit array.
    ref_dem = xdem.DEM(str(GLO), vcrs="EGM08")
    alos_dem = xdem.DEM(str(alos_output), vcrs="EGM08")
    assert ref_dem.shape == alos_dem.shape == fit.shape
    assert ref_dem.vcrs == alos_dem.vcrs
    scene = json.loads(SCENE.read_text(encoding="utf8"))
    report = {
        "horizontal_crs": str(crs), "vertical_crs": "EPSG:3855", "shape": list(shape),
        "correction_m": {"min": float(correction.min()), "median": float(np.median(correction)),
                         "max": float(correction.max())},
        "mask_parameters": {"scl_class": 5, "class_erosion_pixels": 2,
                            "maximum_elevation_m": 4700, "slope_deg": [5, 40],
                            "road_exclusion_m": 60, "block_m": 600, "holdout_buffer_m": 90},
        "pixels": {"both_dems": int(common.sum()), "bare_buffered": int(bare.sum()),
                   "eligible": int(eligible.sum()), "fit": int(fit.sum()), "holdout": int(holdout.sum()),
                   "excluded_buffer": int(eligible.sum() - fit.sum() - holdout.sum()),
                   "fit_aspect_octants": aspect_octants},
        "source_urls": {GRID96.name: "https://cdn.proj.org/us_nga_egm96_15.tif",
                        GRID08.name: "https://cdn.proj.org/us_nga_egm08_25.tif",
                        SCL.name: scene["assets"]["scl"]["href"]},
        "sha256": {path.name: sha256(path) for path in
                   (GLO, ALOS, OSM, GRID96, GRID08, SCL, alos_output, *paths.values())},
        "status": "Prepared and verified as inputs; no co-registration fit has been run.",
    }
    (OUT / "preparacion_coreg.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf8")
    print(json.dumps({key: report[key] for key in ("correction_m", "pixels", "status")}, indent=2))


if __name__ == "__main__":
    main()
