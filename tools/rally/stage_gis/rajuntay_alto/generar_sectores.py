"""Split the authored GLB into XZ sectors without changing its triangles."""
import argparse
import copy
import hashlib
import json
import shutil
import struct
from collections import defaultdict
from pathlib import Path

from generar_ss01 import OUT, TRACK

import numpy as np
from scipy.spatial import cKDTree

BASE = Path(__file__).resolve().parent
ASSETS = BASE.parents[3] / "game/assets/rally" / TRACK
SIZE_M = 192
REQUIRED_DETAIL = {"Road", "Ladera DSM", "Terrain_Dirt_Left", "Terrain_Dirt_Right"}
DETAIL = REQUIRED_DETAIL | {"Guardarrail"}
DTYPES = {5123: "<u2", 5125: "<u4", 5126: "<f4"}
COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_glb(path):
    with path.open("rb") as stream:
        magic, version, _, size, kind = struct.unpack("<IIIII", stream.read(20))
        assert (magic, version, kind) == (0x46546C67, 2, 0x4E4F534A)
        doc = json.loads(stream.read(size))
        size, kind = struct.unpack("<II", stream.read(8))
        assert kind == 0x004E4942
        return doc, stream.read(size)


def accessor(doc, data, index):
    field = doc["accessors"][index]
    view = doc["bufferViews"][field["bufferView"]]
    assert "byteStride" not in view and "sparse" not in field
    width = COMPONENTS[field["type"]]
    offset = view.get("byteOffset", 0) + field.get("byteOffset", 0)
    return np.frombuffer(data, dtype=DTYPES[field["componentType"]],
                         count=field["count"] * width, offset=offset).reshape((-1, width))


def regional_dem_colors(dem, east, south, center, cell_m):
    def linear_rgb(hex_color):
        srgb = np.array(list(bytes.fromhex(hex_color))) / 255.0
        return ((srgb + 0.055) / 1.055) ** 2.4

    def smooth(low, high, values):
        t = np.clip((values - low) / (high - low), 0, 1)
        return t * t * (3 - 2 * t)

    def blend(a, b, weight):
        return a + (b - a) * weight[..., None]

    dz, dx = np.gradient(dem / cell_m)
    slope = np.hypot(dx, dz)
    curvature = np.gradient(dx, axis=1) + np.gradient(dz, axis=0)
    x = east - center[0]
    z = south + center[1]

    # Interpret the aerial reference in route-relative coordinates: broad
    # southwest beds, a smaller warm patch to the east, and gray eastern ridges.
    southwest = np.exp(-((x + 1200) / 1850) ** 2 - ((z - 780) / 2400) ** 2)
    east_patch = np.exp(-((x - 3200) / 1100) ** 2 - ((z + 1450) / 2000) ** 2)
    bedding = (z - 0.55 * x + 0.8 * (dem - 4800) + 95 * np.sin(x / 430)) / 560
    strata = smooth(0.12, 0.70, np.cos(2 * np.pi * bedding))
    warm = np.maximum(southwest * 0.90, east_patch * 0.78) * (0.23 + 0.77 * strata)

    # COLOR_0.rgb: albedo mineral puro (sin sombreado ni bruma: el shader ilumina
    # con el sol dinámico y aplica la bruma por distancia a cámara).
    # COLOR_0.a: exposición rocosa (pendiente + altitud - vaguadas) para el corte nítido en el shader.
    # Paleta medida en fotos LM-116: roca gris neutra, escarpes salmón solo en cotas bajas/medias.
    rock = blend(linear_rgb("7A7676"), linear_rgb("5E5C5D"), smooth(0.40, 0.85, slope))
    rock = blend(rock, linear_rgb("6B6866"), smooth(0.30, 0.80, strata) * 0.35)
    warm_rock = blend(linear_rgb("8F6655"), linear_rgb("7A5446"), smooth(0.35, 0.80, slope))
    warm = warm * (1 - smooth(4950, 5150, dem))
    color = blend(rock, warm_rock, np.clip(warm * 1.15, 0, 1))
    # Oclusión ligera de quebradas (propiedad del material, no iluminación)
    color *= np.clip(1.0 - curvature * 1.2, 0.80, 1.08)[..., None]

    hollow = smooth(0.01, 0.10, curvature)
    exposure = smooth(0.26, 0.62, slope + np.clip((dem - 4800) / 1000, -0.12, 0.30) - hollow * 0.22)
    exposure = np.maximum(exposure, warm * smooth(0.18, 0.40, slope) * 0.85)

    snow = np.clip((dem - 5220) / 230 - slope * 0.38, 0, 0.78)
    if TRACK == "cdi_stage4":
        snow.fill(0.0)  # Ticlio uses the same runtime snow field as the close terrain.
    color = blend(color, np.array([0.70, 0.72, 0.75]), snow)
    exposure = np.maximum(exposure, snow)
    return np.concatenate((color, exposure[..., None]), axis=-1)


def terrain_proxy():
    """Resident valley mesh with clearance below the detailed road cut."""
    from generar_horizonte import CELL_M

    stage = json.loads((OUT / "scene_input.json").read_text(encoding="utf-8"))
    with np.load(OUT / "horizonte_dem.npz") as context:
        dem = context["elevation"]
        center = context["center"]
        axis = (np.arange(dem.shape[0]) + 0.5) * CELL_M - float(context["extent"])
    east, south = np.meshgrid(axis + center[0], axis - center[1])
    distance = np.full(dem.shape, np.inf)
    for x, y, _ in stage["route"][::4]:
        np.minimum(distance, (east - x) ** 2 + (south + y) ** 2, out=distance)
    clearance = 0.7 + 30 * np.clip(1 - np.sqrt(distance) / 165, 0, 1)
    y_height = dem - stage["z0"] - clearance
    positions = np.stack((east, y_height, south), axis=-1)
    dz, dx = np.gradient(y_height / CELL_M)
    normals = np.stack((-dx, np.ones_like(dx), -dz), axis=-1)
    normals /= np.linalg.norm(normals, axis=-1, keepdims=True)
    color = regional_dem_colors(dem, east, south, center, CELL_M)
    i = np.arange(dem.size, dtype="<u4").reshape(dem.shape)[:-1, :-1].ravel()
    width = dem.shape[1]
    faces = np.column_stack((i, i+width, i+1, i+1, i+width, i+width+1)).reshape(-1, 3)
    return ({"POSITION": positions.reshape(-1, 3).astype("<f4"),
             "NORMAL": normals.reshape(-1, 3).astype("<f4"),
             "COLOR_0": color.reshape(-1, 4).astype("<f4")}, faces)


def route_stations(positions, route, stations, tree):
    result = np.zeros(len(positions), dtype="<f4")
    for start in range(0, len(positions), 65536):
        points = positions[start:start + 65536][:, [0, 2]]
        _, nearest = tree.query(points, k=4)
        candidates = np.clip(np.concatenate((nearest - 1, nearest), axis=1), 0, len(route) - 2)
        origins = route[candidates]
        segments = route[candidates + 1] - origins
        relative = points[:, None, :] - origins
        fraction = np.clip((relative * segments).sum(axis=2) / (segments ** 2).sum(axis=2), 0, 1)
        residual = relative - fraction[..., None] * segments
        closest = np.argmin((residual ** 2).sum(axis=2), axis=1)
        rows = np.arange(len(points))
        segment = candidates[rows, closest]
        station = stations[segment] + fraction[rows, closest] * (stations[segment + 1] - stations[segment])
        result[start:start + len(points)] = station
    return result


def write_glb(path, meshes, source, terrain=None):
    binary = bytearray()
    materials = copy.deepcopy(source["materials"])
    # The runtime shader binds the shared material textures once. Referencing
    # them from every GLB also asks the Godot importer to reimport them per tile.
    for material in materials:
        material.get("pbrMetallicRoughness", {}).pop("baseColorTexture", None)
    output = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": []}],
              "nodes": [], "meshes": [], "accessors": [], "bufferViews": [], "materials": materials}

    def store(array, kind, component, bounds=False):
        binary.extend(b"\0" * (-len(binary) % 4))
        view = {"buffer": 0, "byteOffset": len(binary), "byteLength": array.nbytes}
        binary.extend(array.tobytes())
        record = {"bufferView": len(output["bufferViews"]), "componentType": component,
                  "count": len(array), "type": kind}
        if bounds:
            record.update(min=array.min(axis=0).tolist(), max=array.max(axis=0).tolist())
        output["bufferViews"].append(view)
        output["accessors"].append(record)
        return len(output["accessors"]) - 1

    if terrain is not None:
        output["extensionsUsed"] = ["KHR_materials_unlit"]
        material = len(output["materials"])
        output["materials"].append({"name": "DEM regional", "doubleSided": True,
                                    "extensions": {"KHR_materials_unlit": {}}})
        meshes = {**meshes, "Rajuntay Regional DEM": [(*terrain, material)]}
    total = 0
    for name, primitives in meshes.items():
        packed = []
        for attributes, faces, material in primitives:
            indices, local = np.unique(faces, return_inverse=True)
            dtype, component = ("<u2", 5123) if len(indices) < 65536 else ("<u4", 5125)
            mapping = {key: store(values[indices], f"VEC{values.shape[1]}", 5126, key == "POSITION")
                       for key, values in attributes.items()}
            packed.append({"attributes": mapping, "material": material,
                           "indices": store(local.ravel().astype(dtype), "SCALAR", component)})
            total += len(faces)
        output["scenes"][0]["nodes"].append(len(output["nodes"]))
        output["nodes"].append({"name": name, "mesh": len(output["meshes"])})
        output["meshes"].append({"name": name, "primitives": packed})
    binary.extend(b"\0" * (-len(binary) % 4))
    output["buffers"] = [{"byteLength": len(binary)}]
    descriptor = json.dumps(output, separators=(",", ":")).encode()
    descriptor += b" " * (-len(descriptor) % 4)
    with path.open("wb") as stream:
        stream.write(struct.pack("<IIIII", 0x46546C67, 2, 28 + len(descriptor) + len(binary),
                                 len(descriptor), 0x4E4F534A))
        stream.write(descriptor)
        stream.write(struct.pack("<II", len(binary), 0x004E4942))
        stream.write(binary)
    return total


def build():
    runtime = ASSETS / f"{TRACK}_visual.glb"
    backup = OUT / f"{TRACK}_visual_autoria.glb"
    doc, data = read_glb(runtime)
    source = runtime
    if not REQUIRED_DETAIL <= {node["name"] for node in doc["nodes"]}:
        source = backup
        doc, data = read_glb(source)
    assert REQUIRED_DETAIL <= {node["name"] for node in doc["nodes"]}
    assert all(set(node) <= {"name", "mesh"} for node in doc["nodes"])
    textures = ASSETS / "texturas_sectores"
    sectors = ASSETS / "sectores"
    textures.mkdir(exist_ok=True)
    sectors.mkdir(exist_ok=True)
    index_path = sectors / "index.json"
    old_entries = json.loads(index_path.read_text(encoding="utf-8"))["sectors"] if index_path.exists() else []
    stage = json.loads((OUT / "scene_input.json").read_text(encoding="utf-8"))
    route = np.asarray(stage["route"])[:, :2] * [1, -1]
    stations = np.asarray(stage["source_pks"])
    tree = cKDTree(route)
    for image in doc["images"]:
        view = doc["bufferViews"][image["bufferView"]]
        offset = view.get("byteOffset", 0)
        (textures / (image["name"] + ".png")).write_bytes(data[offset:offset + view["byteLength"]])
    resident = defaultdict(list)
    tiles = defaultdict(lambda: defaultdict(list))
    expected = 0
    for node in doc["nodes"]:
        name = node["name"]
        for primitive in doc["meshes"][node["mesh"]]["primitives"]:
            attributes = {key: accessor(doc, data, index) for key, index in primitive["attributes"].items()}
            faces = accessor(doc, data, primitive["indices"]).reshape(-1, 3)
            material = primitive["material"]
            if name not in DETAIL:
                resident[name].append((attributes, faces, material))
                continue
            expected += len(faces)
            if name not in {"Ladera DSM", "Guardarrail"}:
                secondary_uv = attributes.get("TEXCOORD_1")
                if secondary_uv is None:
                    secondary_uv = np.zeros((len(attributes["POSITION"]), 2), dtype="<f4")
                else:
                    secondary_uv = secondary_uv.copy()
                if name == "Road" and TRACK in {"cdi_stage3", "cdi_stage4"}:
                    # Blender's glTF exporter flips V. Recover exact road stations,
                    # including at tight bends where nearest-point projection can jump.
                    secondary_uv[:, 1] = (1.0 - attributes["TEXCOORD_0"][:, 1]) * 4.0
                else:
                    secondary_uv[:, 1] = route_stations(attributes["POSITION"], route, stations, tree)
                attributes["TEXCOORD_1"] = secondary_uv
            centers = attributes["POSITION"][faces].mean(axis=1)
            keys = np.floor(centers[:, [0, 2]] / SIZE_M).astype(int)
            distinct, inverse = np.unique(keys, axis=0, return_inverse=True)
            for i, (x, z) in enumerate(distinct):
                tiles[int(x), int(z)][name].append((attributes, faces[inverse == i], material))

    entries = []
    for (x, z), mesh in sorted(tiles.items()):
        filename = f"sector_{x}_{z}.glb"
        count = write_glb(sectors / filename, mesh, doc)
        points = np.concatenate([attrs["POSITION"][faces].reshape(-1, 3)
                                 for parts in mesh.values() for attrs, faces, _ in parts])
        entries.append(dict(file=filename, minimum=points.min(axis=0).tolist(),
                            maximum=points.max(axis=0).tolist(), triangles=count))
    total = sum(entry["triangles"] for entry in entries)
    assert total == expected
    staged = OUT / f"{TRACK}_visual_residente.glb"
    write_glb(staged, resident, doc, terrain_proxy())
    if source != backup:
        shutil.copyfile(source, backup)
    staged.replace(runtime)
    index_path.write_text(json.dumps({"sectors": entries}, indent=2) + "\n", encoding="utf-8")
    current = {entry["file"] for entry in entries}
    for entry in old_entries:
        name = entry["file"]
        if name not in current and Path(name).name == name and name.startswith("sector_") and name.endswith(".glb"):
            for suffix in ("", ".import"):
                (sectors / (name + suffix)).unlink(missing_ok=True)
    path = ASSETS / "manifest.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    manifest["visual"].update(sha256=hashlib.sha256(runtime.read_bytes()).hexdigest(), size_bytes=runtime.stat().st_size)
    manifest["streaming"] = {"index": "sectores/index.json", "cell_m": SIZE_M,
                             "sector_count": len(entries), "detail_triangles": total}
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"CDI_SECTORES count={len(entries)} detail_triangles={total} resident_bytes={runtime.stat().st_size}")


def rebuild_resident_dem():
    """Rebuild only the resident GLB (including Rajuntay Regional DEM colors and normals)."""
    runtime = ASSETS / f"{TRACK}_visual.glb"
    backup = OUT / f"{TRACK}_visual_autoria.glb"
    source = backup if backup.exists() else runtime
    doc, data = read_glb(source)
    resident = defaultdict(list)
    for node in doc["nodes"]:
        name = node["name"]
        if name in DETAIL or name == "Rajuntay Regional DEM":
            continue
        for primitive in doc["meshes"][node["mesh"]]["primitives"]:
            attributes = {key: accessor(doc, data, index) for key, index in primitive["attributes"].items()}
            faces = accessor(doc, data, primitive["indices"]).reshape(-1, 3)
            resident[name].append((attributes, faces, primitive["material"]))
    staged = OUT / f"{TRACK}_visual_residente.glb"
    write_glb(staged, resident, doc, terrain_proxy())
    staged.replace(runtime)
    path = ASSETS / "manifest.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    manifest["visual"].update(sha256=hashlib.sha256(runtime.read_bytes()).hexdigest(), size_bytes=runtime.stat().st_size)
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"CDI_REGIONAL_DEM_ONLY resident_bytes={runtime.stat().st_size} sha256={manifest['visual']['sha256'][:12]}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--regional-only", action="store_true",
                        help="Only rebuild Rajuntay Regional DEM (colors + normals) inside the resident GLB.")
    stages = parser.add_mutually_exclusive_group()
    stages.add_argument("--ss03", action="store_true", help="Use Chinchán Asfalto.")
    stages.add_argument("--ss04", action="store_true", help="Use Abra Ticlio.")
    stages.add_argument("--ss02", action="store_true", help="Build Quebrada Chinchán.")
    args = parser.parse_args()
    if args.regional_only:
        rebuild_resident_dem()
    else:
        build()
