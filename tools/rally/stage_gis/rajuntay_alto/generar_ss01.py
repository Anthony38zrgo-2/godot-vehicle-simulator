"""Prepare a CDI stage with Python/Pillow/Shapely, then build it with Blender."""
import csv
import json
import math
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent
RAURA = BASE.parent / "raura_quichas_gis"
STAGE_NAMES = ("Rajuntay Alto", "Quebrada Chinchán", "Chinchán Asfalto", "Abra Ticlio")
STAGE_NUMBER = next((i for i in range(2, 5) if f"--ss0{i}" in sys.argv), 1)
STAGE_ID = f"SS{STAGE_NUMBER:02d}"
TRACK = f"cdi_stage{STAGE_NUMBER}"
OUT = BASE / "output"
if STAGE_NUMBER > 1:
    OUT /= STAGE_ID.lower()
END_RUNWAY_M = 50.0


def prepare(source, extend_valley=False):
    from PIL import Image
    from shapely.geometry import LineString, Polygon
    from shapely.geometry.polygon import orient

    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    with (source / f"{STAGE_ID}_Carretera_Spline_3D_Nodes.csv").open(newline="", encoding="utf-8-sig") as stream:
        for row in csv.DictReader(stream):
            point = tuple(float(row[key]) for key in ("x_utm_corr", "y_utm_corr", "z_corr_m"))
            pk = float(row["s_corrected_m"])
            rows.append((pk, point))
    end_pk = rows[-1][0]
    finish_pk = end_pk - END_RUNWAY_M
    x0, y0, z0 = rows[0][1]
    route = [(x-x0, y-y0, z-z0) for _, (x, y, z) in rows]
    centerline = LineString([(x, y) for x, y, _ in route])

    def ring(distance, spacing):
        buffered = centerline.buffer(distance, quad_segs=8)
        # Fill islands inside switchbacks so the playable corridor has one perimeter.
        outline = orient(Polygon(buffered.exterior), sign=1).segmentize(spacing)
        return list(outline.exterior.coords)[:-1]

    terrain_ring = ring(58.0, 5.0)
    wall_ring = ring(33.0, 3.0)
    metadata = json.loads((source / f"{STAGE_ID}_metadata.json").read_text(encoding="utf-8"))
    west, step, _, north, _, _ = metadata["grid_2p5m"]["transform_gdal"]
    with Image.open(source / f"{STAGE_ID}_DEM_GLO30_suavizado_2p5m.tif") as dem:
        xs, ys = zip(*terrain_ring)
        left = math.floor((min(xs) + x0 - west) / step) - 3
        right = math.ceil((max(xs) + x0 - west) / step) + 3
        top = math.floor((north - (max(ys) + y0)) / step) - 3
        bottom = math.ceil((north - (min(ys) + y0)) / step) + 3
        assert 0 <= left < right < dem.width and 0 <= top < bottom < dem.height
        terrain = [
            (west + (col+0.5)*step - x0, north - (row+0.5)*step - y0, dem.getpixel((col, row))-z0)
            for row in range(top, bottom, 2) for col in range(left, right, 2)
        ]
        pad = math.ceil((900 if extend_valley else 315) / step)
        left_far, right_far = max(0, left-pad), min(dem.width, right+pad)
        top_far, bottom_far = max(0, top-pad), min(dem.height, bottom+pad)
        distant_terrain = [
            (west + (col+0.5)*step - x0, north - (row+0.5)*step - y0, dem.getpixel((col, row))-z0)
            for row in range(top_far, bottom_far, 10)
            for col in range(left_far, right_far, 10)
        ]
    if extend_valley:
        from generar_horizonte import CELL_M
        from shapely import contains_xy
        import numpy as np

        with np.load(OUT / "horizonte_dem.npz") as context:
            heights = context["elevation"]
            center = context["center"]
            axis = (np.arange(heights.shape[0]) + 0.5) * CELL_M - float(context["extent"])
            x, y = np.meshgrid(axis + center[0], -axis + center[1])
            west_far = west + (left_far - 4) * step - x0
            east_far = west + (right_far - 5) * step - x0
            north_far = north - (top_far - 4) * step - y0
            south_far = north - (bottom_far - 5) * step - y0
            outside_local = (x < west_far) | (x > east_far) | (y < south_far) | (y > north_far)
            use = outside_local & contains_xy(centerline.buffer(950), x, y)
            distant_terrain.extend(zip(x[use].tolist(), y[use].tolist(), (heights[use] - z0).tolist()))

    with Image.open(BASE / "rajuntay_materiales_atlas_v1_ps1.png") as atlas:
        for index, name in enumerate(("pasto_denso", "pasto_ralo", "pedregal", "tierra")):
            x, y = (index % 2) * 128, (index // 2) * 128
            atlas.crop((x, y, x+128, y+128)).save(OUT / (name + ".png"))

    data = dict(origin=[x0, y0], z0=z0, route=route, terrain=terrain, terrain_ring=terrain_ring,
                wall_ring=wall_ring, source_pks=[pk for pk, _ in rows], distant_terrain=distant_terrain,
                timing_pks=[END_RUNWAY_M, finish_pk])
    (OUT / "scene_input.json").write_text(json.dumps(data), encoding="utf-8")
    wear = json.loads((RAURA / "desgaste_inicio_stage2.json").read_text(encoding="utf-8"))
    wear.update(seed=20261117, zones=[], manual_features=[],
                exclusion_zones=[{"from_pk_m": 0, "to_pk_m": 65},
                                 {"from_pk_m": finish_pk - 10, "to_pk_m": end_pk}])
    if STAGE_NUMBER >= 3:
        wear.update(exclusion_zones=[{"from_pk_m": 0, "to_pk_m": end_pk}],
                    corrugations=[], crests=[], settlements=[], undulation_m=0.0)
    (OUT / "desgaste.json").write_text(json.dumps(wear), encoding="utf-8")


if __name__ == "__main__":
    if "--prepare" in sys.argv:
        prepare(Path(sys.argv[sys.argv.index("--prepare") + 1]), "--extend-valley" in sys.argv)
    else:
        sys.path[:0] = [str(BASE), str(RAURA)]
        from generar_stage2 import main

        stage_cfg = dict(
            track=TRACK, output=OUT, wear=OUT / "desgaste.json",
            axis_source=f"{STAGE_ID}_Carretera_Spline_3D_Nodes.csv",
            asphalt=STAGE_NUMBER >= 3, snow_second_half=STAGE_NUMBER == 4,
            name=f"Caminos del Inca · {STAGE_ID} {STAGE_NAMES[STAGE_NUMBER - 1]}",
        )
        if STAGE_NUMBER in (1, 4):
            stage_cfg["geography"] = {
                "crs": "EPSG:32718",
                "dem_source": "Copernicus DEM GLO-30 (cop-dem-glo-30, Copernicus_DSM_COG_10_S12_00_W077_00_DEM)",
                "vertical_datum": "EGM2008 orthometric (shared by DEM origin z0 and approved axis)",
                "vertical_datum_verified": True,
                "osm_observations": [
                    f"{STAGE_ID}_Carretera_Spline_3D_Nodes.csv z_corr_m derived from GLO-30 DEM 2.5m sharing datum with DEM origin z0.",
                ],
            }
        main(stage_cfg)
