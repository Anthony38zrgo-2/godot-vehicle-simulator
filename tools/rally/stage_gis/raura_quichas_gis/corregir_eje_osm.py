import argparse
import json
from pathlib import Path

import numpy as np
import rasterio
from rasterio.warp import transform
from scipy import ndimage

ROOT = Path(__file__).resolve().parent


def track(score, offsets):
    """Second-order Viterbi with bounded station-to-station changes."""
    change = offsets[None, :] - offsets[:, None]
    cost = -8 * score + 0.25 * (offsets / 20)**2
    step = np.where(abs(change) <= 3, 0.08 * change**2, np.inf)
    pair = cost[0, :, None] + cost[1, None, :] + step
    curvature = 0.16 * (change[None, :, :] - change[:, :, None])**2
    history = []
    for emission in cost[2:]:
        choices = pair[:, :, None] + curvature
        history.append(choices.argmin(axis=0))
        pair = choices.min(axis=0) + step + emission
    previous, current = np.unravel_index(pair.argmin(), pair.shape)
    path = [current, previous]
    for pointers in reversed(history):
        path.append(pointers[path[-1], path[-2]])
    return np.asarray(path[::-1])


def main():
    parser = argparse.ArgumentParser(description="Detect road offsets in a UTM 18S satellite image")
    parser.add_argument("raster", type=Path)
    parser.add_argument("--rmse-gcp", type=float, help="Independent checkpoint RMSE in meters")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--pk-max", type=int, default=800)
    parser.add_argument("--diagnostic-only", action="store_true", help="Record offsets without applying them")
    args = parser.parse_args()
    if not 100 <= args.pk_max <= 800 or args.pk_max % 5:
        parser.error("PK máximo: múltiplo de 5 entre 100 y 800")
    if not args.diagnostic_only and (args.rmse_gcp is None or not np.isfinite(args.rmse_gcp) or args.rmse_gcp <= 0):
        parser.error("Provide a positive independent checkpoint RMSE")
    with rasterio.open(args.raster) as ds:
        if ds.driver != "GTiff" or ds.crs is None or ds.crs.to_epsg() != 32718 or (max(ds.res) > 1 and not args.diagnostic_only):
            parser.error("Expected EPSG:32718 GeoTIFF at 1 m/px or finer")
        if ds.count < 3 or any(dtype != "uint8" for dtype in ds.dtypes[:3]):
            parser.error("Expected three 8-bit RGB bands")
        rgb = ds.read([1, 2, 3]).astype(np.float32) / 255
        mask = ds.dataset_mask() != 0
        affine = ds.transform
        gsd = max(ds.res)
    red, green, blue = rgb
    value = rgb.max(axis=0)
    saturation = (value - rgb.min(axis=0)) / np.maximum(value, 1e-6)
    size = max(3, round(1 / gsd))
    mean = ndimage.uniform_filter(value, size)
    variance = np.maximum(0, ndimage.uniform_filter(value**2, size) - mean**2)
    ridge = np.clip((value - ndimage.gaussian_filter(value, 8 / gsd)) / 0.15, 0, 1)
    likelihood = np.clip((value - .35) / .4, 0, 1) * np.clip((.45 - saturation) / .3, 0, 1)
    likelihood *= np.exp(-variance / .08**2) * ridge
    mask &= (value >= .25) & (2 * green - red - blue <= .05)
    mask &= ~((value > .85) & (saturation < .1))
    likelihood[~mask] = 0

    scene = json.loads((ROOT / "output/scene_input.json").read_text(encoding="utf8"))
    axis = np.asarray(scene["route"])[:, :2] + scene["origin"]
    source_pk = np.r_[0, np.cumsum(np.linalg.norm(np.diff(axis, axis=0), axis=1))]
    pk = np.arange(0, args.pk_max + 1, 5)
    points = np.column_stack([np.interp(pk, source_pk, component) for component in axis.T])
    tangent = np.gradient(points, axis=0)
    normal = tangent[:, ::-1] * [-1, 1] / np.linalg.norm(tangent, axis=1)[:, None]
    offsets = np.arange(-20, 20.1, .5)
    lateral = np.arange(-26, 26.1, .5)
    xy = points[:, None, :] + lateral[None, :, None] * normal[:, None, :]
    cols, rows = (~affine) * (xy[..., 0], xy[..., 1])
    if np.any((cols < .5) | (cols > likelihood.shape[1] - .5) |
              (rows < .5) | (rows > likelihood.shape[0] - .5)):
        parser.error("Raster must cover the full ±26 m sampling band through the requested PK")
    samples = ndimage.map_coordinates(likelihood, [rows - .5, cols - .5], order=1)
    distance = abs(lateral[None, :] - offsets[:, None])
    scores = []
    for width in (4, 5, 6):
        inside = distance <= width / 2
        shoulders = (distance > width / 2) & (distance <= width)
        scores.append(samples @ (inside / inside.sum(axis=1)[:, None] -
                                 shoulders / shoulders.sum(axis=1)[:, None]).T)
    score = np.maximum(0, np.max(scores, axis=0))
    index = track(score, offsets)
    chosen = offsets[index].copy()
    evidence = score[np.arange(len(pk)), index]
    for i, j in enumerate(index):
        if 0 < j < len(offsets) - 1:
            left, peak, right = score[i, j-1:j+2]
            bend = left - 2 * peak + right
            if bend < 0 and peak >= max(left, right):
                chosen[i] += .25 * (left - right) / bend
    uncertainty = (np.full(len(pk), np.nan) if args.rmse_gcp is None else
                   np.hypot(args.rmse_gcp, .5 / np.maximum(evidence * 10, .1)))
    accepted = (evidence >= .05) & (abs(chosen) > np.maximum(3, 2 * uncertainty))
    if args.diagnostic_only:
        accepted[:] = False
    applied = np.zeros_like(chosen)
    for sign in (-1, 1):
        labels, count = ndimage.label(accepted & (np.sign(chosen) == sign))
        for label in range(1, count + 1):
            run = labels == label
            if run.sum() >= 3:
                applied[run] = ndimage.gaussian_filter1d(chosen * run, 1)[run]
    taper = np.clip((args.pk_max - pk) / 100, 0, 1)
    applied *= taper**2 * (3 - 2 * taper)
    output_pk = np.unique(np.r_[source_pk, pk])
    base = np.column_stack([np.interp(output_pk, source_pk, component) for component in axis.T])
    delta = np.column_stack([np.interp(output_pk, pk, component, right=0)
                             for component in (applied[:, None] * normal).T])
    corrected = base + delta
    lon, lat = transform("EPSG:32718", "EPSG:4326", *corrected.T)
    args.output.mkdir(parents=True, exist_ok=True)
    feature = {"type": "Feature", "properties": {"status": "candidato_para_revision",
               "raster": args.raster.name, "rmse_gcp_m": args.rmse_gcp},
               "geometry": {"type": "LineString", "coordinates": list(zip(lon, lat))}}
    if not args.diagnostic_only:
        (args.output / "route_osm_corregido.geojson").write_text(
            json.dumps({"type": "FeatureCollection", "features": [feature]}), encoding="utf8")
    np.savetxt(args.output / "desplazamientos_pk.csv",
               np.column_stack([pk, chosen, applied, evidence, uncertainty]), delimiter=",",
               header="pk_m,offset_estimado_m,offset_candidato_m,evidencia,incertidumbre_indicativa_m",
               comments="", fmt="%.3f")


if __name__ == "__main__":
    main()
