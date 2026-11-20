"""Fetch the Rajuntay GLO-30 crop and render the terrain portion of its skybox."""
import json
import math
import sys
from pathlib import Path

from generar_ss01 import OUT, TRACK

BASE = Path(__file__).resolve().parent
ASSETS = BASE.parents[3] / "game/assets/rally" / TRACK / "horizonte"
TILE = "Copernicus_DSM_COG_10_S12_00_W077_00_DEM"
DEM_URL = f"https://copernicus-dem-30m.s3.eu-central-1.amazonaws.com/{TILE}/{TILE}.tif"
PANORAMA = "rajuntay_panorama.png"
NEAR_M, FAR_M, RADIUS_M = 1050, 11500, 4300
CELL_M = 55
ELEVATION_MIN, ELEVATION_MAX = -90, 34


def prepare():
    import numpy as np
    import rasterio
    from rasterio.transform import from_origin
    from rasterio.warp import Resampling, reproject

    stage = json.loads((OUT / "scene_input.json").read_text(encoding="utf-8"))
    x, y, z = np.asarray(stage["route"]).T
    center = [float((x.min() + x.max()) * 0.5), float((y.min() + y.max()) * 0.5), float(np.median(z))]
    extent = math.ceil((FAR_M + CELL_M) / CELL_M) * CELL_M
    size = 2 * extent // CELL_M
    destination = np.full((size, size), np.nan, dtype=np.float32)
    east, north = np.asarray(stage["origin"]) + center[:2]
    with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN="YES", GDAL_HTTP_MAX_RETRY="3"):
        with rasterio.open(DEM_URL) as source:
            reproject(rasterio.band(source, 1), destination,
                      dst_transform=from_origin(east - extent, north + extent, CELL_M, CELL_M),
                      dst_crs="EPSG:32718", dst_nodata=np.nan, resampling=Resampling.bilinear)
    if not np.isfinite(destination).all():
        raise ValueError("The Rajuntay horizon crop has missing elevations")
    np.savez_compressed(OUT / "horizonte_dem.npz", elevation=destination, center=center, extent=extent, z0=stage["z0"])


def render():
    import bpy
    import numpy as np

    sample = np.load(OUT / "horizonte_dem.npz")
    dem, center, extent, z0 = (sample[key] for key in ("elevation", "center", "extent", "z0"))
    heights = dem - z0 - center[2]
    distance_axis = np.arange(dem.shape[0]) * CELL_M - float(extent) + CELL_M / 2
    x, y = np.meshgrid(distance_axis, -distance_axis)
    radius = np.hypot(x, y)
    row_grade, col_grade = np.gradient(dem / CELL_M)
    grade = np.hypot(row_grade, col_grade)
    shade = np.clip(0.77 + col_grade * 0.29 + row_grade * 0.36, 0.4, 1.13)
    stone = np.clip((grade - 0.24) * 1.55 + (dem - 4950) / 1050, 0, 1)
    snow = np.clip((dem - 5230) / 225 - grade * 0.37, 0, 0.76)
    grass_rgb = np.array([0.23, 0.185, 0.105])
    rock_rgb = np.array([0.20, 0.17, 0.17])
    snow_rgb = np.array([0.61, 0.65, 0.69])
    ground = grass_rgb + (rock_rgb - grass_rgb) * stone[..., None]
    ground = (ground + (snow_rgb - ground) * snow[..., None]) * shade[..., None]

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    sky_camera = bpy.data.cameras.new("Panorama Rajuntay")
    sky_camera.type = "PANO"
    sky_camera.panorama_type = "EQUIRECTANGULAR"
    sky_camera.latitude_min = math.radians(ELEVATION_MIN)
    sky_camera.latitude_max = math.radians(ELEVATION_MAX)
    sky_camera.clip_end = 25000
    camera = bpy.data.objects.new("Panorama Rajuntay", sky_camera)
    scene.collection.objects.link(camera)
    camera.rotation_euler.x = math.pi / 2
    scene.camera = camera
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 8
    scene.render.resolution_x = 2048
    scene.render.resolution_y = 706
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    material = bpy.data.materials.new("Relieve de Rajuntay")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    emission = nodes.new("ShaderNodeEmission")
    color = nodes.new("ShaderNodeVertexColor")
    color.layer_name = "Relieve"
    material.node_tree.links.new(color.outputs["Color"], emission.inputs["Color"])
    material.node_tree.links.new(emission.outputs[0], nodes.get("Material Output").inputs["Surface"])

    ASSETS.mkdir(parents=True, exist_ok=True)
    rows, cols = np.where((radius[:-1, :-1] >= NEAR_M) & (radius[:-1, :-1] <= FAR_M))
    corners = {}
    vertices, faces, colors = [], [], []
    atmospheric = np.clip(0.11 + radius / 23000, 0.15, 0.62)
    sky = np.array([0.27, 0.36, 0.47])
    palette = ground + (sky - ground) * atmospheric[..., None]
    for row, col in zip(rows, cols):
        face = []
        for key in ((row, col), (row+1, col), (row+1, col+1), (row, col+1)):
            if key not in corners:
                corners[key] = len(vertices)
                vertices.append((x[key], y[key], heights[key]))
                colors.extend((*palette[key], 1))
            face.append(corners[key])
        faces.append(face)
    mesh = bpy.data.meshes.new("Relieve de Rajuntay")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(material)
    mesh.color_attributes.new(name="Relieve", type="FLOAT_COLOR", domain="POINT").data.foreach_set("color", colors)
    terrain = bpy.data.objects.new("Relieve de Rajuntay", mesh)
    scene.collection.objects.link(terrain)
    scene.render.filepath = str(OUT / PANORAMA)
    bpy.ops.render.render(write_still=True)
    metadata = {"center": [float(center[0]), float(center[2]), -float(center[1])],
                "elevation_degrees": [ELEVATION_MIN, ELEVATION_MAX],
                "file": PANORAMA, "radius_m": RADIUS_M,
                "source": DEM_URL}
    (ASSETS / "panorama.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")


def finish():
    import numpy as np
    from PIL import Image

    # Keep Blender's skyline alpha. Fill internal gaps and taper the base to
    # the color of the near valley while keeping it opaque down to the nadir.
    with Image.open(OUT / PANORAMA) as source:
        pixels = np.array(source.convert("RGBA"))
    height, width = pixels.shape[:2]
    haze = np.array([123, 119, 102], dtype=float)
    visible = pixels[:, :, 3] >= 192
    if not visible.any(axis=0).all():
        raise ValueError("A longitude of the terrain panorama has no DEM coverage")
    bottoms = np.where(visible, np.arange(height)[:, None], -1).max(axis=0)
    edge = pixels[bottoms, np.arange(width), :3].astype(float)
    soft_edge = sum(np.roll(edge, offset, axis=0) for offset in range(-48, 49)) / 97
    for x, bottom in enumerate(bottoms):
        rows = np.flatnonzero(visible[:, x])
        gaps = np.flatnonzero(~visible[rows[0]:bottom, x]) + rows[0]
        for channel in range(3):
            pixels[gaps, x, channel] = np.interp(gaps, rows, pixels[rows, x, channel])
        pixels[rows[0]:, x, 3] = 255
        depth = np.arange(1, height-bottom)[:, None]
        smoothing = np.minimum(1.0, depth / 12.0)
        color = edge[x] + (soft_edge[x] - edge[x]) * smoothing
        atmospheric = np.minimum(1.0, depth / 55.0)
        pixels[bottom+1:, x, :3] = color + (haze - color) * atmospheric
    Image.fromarray(pixels).save(ASSETS / PANORAMA, optimize=True)


if __name__ == "__main__":
    if "--prepare" in sys.argv:
        prepare()
    elif "--finish" in sys.argv:
        finish()
    else:
        render()
