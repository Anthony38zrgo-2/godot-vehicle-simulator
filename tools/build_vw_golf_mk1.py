#!/usr/bin/env python3
"""
Build visual GLBs, manifest.json, and convex collision hulls for the
VW Golf Mk1 GTI Group 2 Rally (`vw_golf_mk1_gti`) from RallyManiacAssets.

Source model notes (verified via Blender inspection):
  - D:\\RallyManiacAssets\\vw-golf-mk1-low-poly\\source\\VW Golf Mk1.zip (VW Golf Mk1.fbx)
  - Single mesh object `VW Golf MESH` at 0.01 scale, -Y forward, containing:
      * 4 wheel mesh islands (145 verts each)
      * 19 exterior body/detail islands (shell, GTI arch flares, quad headlights, plates, mirrors, etc.)
      * 6 single-vertex loose orphans (purged cleanly)
  - Full 2048x2048 PBR textures in D:\\RallyManiacAssets\\vw-golf-mk1-low-poly\\textures\\

Coordinates:
  Blender working space (after +180 deg Z bake): +X right, +Y forward, +Z up
  Godot / glTF +Y up export:                   +X right, -Z forward, +Y up

Usage:
  blender -b --factory-startup --python tools/build_vw_golf_mk1.py
"""

from __future__ import annotations

import hashlib
import json
import math
import tempfile
import zipfile
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix

REPO = Path(__file__).resolve().parent.parent
SRC_ZIP = Path(r"D:\RallyManiacAssets\vw-golf-mk1-low-poly\source\VW Golf Mk1.zip")
TEX_DIR = Path(r"D:\RallyManiacAssets\vw-golf-mk1-low-poly\textures")
TEX_BASE = TEX_DIR / "VW Golf Mk1_VW Golf_BaseColor.png"
TEX_METALLIC = TEX_DIR / "VW Golf Mk1_VW Golf_Metallic.png"
TEX_NORMAL = TEX_DIR / "VW Golf Mk1_VW Golf_Normal.png"
TEX_ROUGHNESS = TEX_DIR / "VW Golf Mk1_VW Golf_Roughness.png"
ASSET_DIR = REPO / "game" / "assets" / "rally" / "vw_golf_mk1"

# Target VW Golf Mk1 GTI Group 2 Rally (Typ 17, FIA Homologation 5584 / 5731 / 5732) dimensions in metres:
# - Wheelbase:      2.400 m (axles at +/- 1.200 m)
# - Length:         3.741 m (overhangs scaled proportionally to FBX: front 0.715 m, rear 0.626 m)
# - Body width:     ~1.631 m shell (1.610 m base + GTI/Gr.2 arch flares)
# - Tracks:         1.420 m front, 1.410 m rear (Gr.2 rally track setup flush with arch flares)
# - Tires:          185/70 R14 Gravel -> outer diameter 0.610 m (radius 0.305 m), width 0.195 m
# - Ground/Roof Z:  0.185 m sump/chin clearance, 1.425 m roof top (gravel rally ride height)
TARGET_WHEELBASE_M = 2.400
TARGET_LENGTH_M = 3.741
TARGET_FRONT_OVERHANG_M = 0.715
TARGET_REAR_OVERHANG_M = 0.626
TARGET_FRONT_TRACK_M = 1.420
TARGET_REAR_TRACK_M = 1.410
TARGET_X_SCALE = 2.700
TARGET_TIRE_RADIUS_M = 0.305
TARGET_TIRE_WIDTH_M = 0.195
TARGET_BOTTOM_CLEARANCE_M = 0.185
TARGET_ROOF_HEIGHT_M = 1.425


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_pbr_material(mat_name: str) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=mat_name)
    mat.use_nodes = True
    mat.use_backface_culling = False
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.45

    def load_tex(path: Path, colorspace: str) -> bpy.types.ShaderNodeTexImage:
        node = nodes.new("ShaderNodeTexImage")
        img = bpy.data.images.load(str(path), check_existing=True)
        img.colorspace_settings.name = colorspace
        img.alpha_mode = "NONE"
        img.pack()
        node.image = img
        node.interpolation = "Linear"
        return node

    tex_base = load_tex(TEX_BASE, "sRGB")
    links.new(tex_base.outputs["Color"], bsdf.inputs["Base Color"])

    if TEX_METALLIC.is_file():
        tex_met = load_tex(TEX_METALLIC, "Non-Color")
        links.new(tex_met.outputs["Color"], bsdf.inputs["Metallic"])

    if TEX_ROUGHNESS.is_file():
        tex_rough = load_tex(TEX_ROUGHNESS, "Non-Color")
        links.new(tex_rough.outputs["Color"], bsdf.inputs["Roughness"])

    if TEX_NORMAL.is_file():
        tex_norm = load_tex(TEX_NORMAL, "Non-Color")
        norm_map = nodes.new("ShaderNodeNormalMap")
        norm_map.inputs["Strength"].default_value = 1.0
        links.new(tex_norm.outputs["Color"], norm_map.inputs["Color"])
        links.new(norm_map.outputs["Normal"], bsdf.inputs["Normal"])

    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def bake_world_and_rotate_z180(obj: bpy.types.Object) -> None:
    rot180 = Matrix.Rotation(math.pi, 4, "Z")
    xf = rot180 @ obj.matrix_world
    obj.data.transform(xf)
    obj.parent = None
    obj.matrix_world = Matrix.Identity(4)


def clean_mesh_topology(obj: bpy.types.Object) -> dict:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()

    uv_layer = bm.loops.layers.uv.active

    def rpos(v):
        return (round(v.co.x, 4), round(v.co.y, 4), round(v.co.z, 4))

    def canonical(tri):
        m = min(tri)
        idx = tri.index(m)
        return tri[idx:] + tri[:idx]

    def uv_area(f):
        if not uv_layer or len(f.loops) < 3:
            return 0.0
        u0, u1, u2 = f.loops[0][uv_layer].uv, f.loops[1][uv_layer].uv, f.loops[2][uv_layer].uv
        return 0.5 * abs((u1.x - u0.x) * (u2.y - u0.y) - (u2.x - u0.x) * (u1.y - u0.y))

    zero_faces = []
    oriented_groups = {}
    for f in bm.faces:
        pts = tuple(rpos(v) for v in f.verts)
        if len(pts) != 3 or len(set(pts)) < 3 or f.calc_area() < 1e-7:
            zero_faces.append(f)
            continue
        oriented_groups.setdefault(canonical(pts), []).append(f)

    dup_faces = []
    for grp in oriented_groups.values():
        if len(grp) > 1:
            ranked = sorted(grp, key=lambda f: (-uv_area(f), f.index))
            dup_faces.extend(ranked[1:])

    to_delete = list(set(zero_faces + dup_faces))
    if to_delete:
        bmesh.ops.delete(bm, geom=to_delete, context="FACES")

    loose_edges = [e for e in bm.edges if not e.link_faces]
    if loose_edges:
        bmesh.ops.delete(bm, geom=loose_edges, context="EDGES")
    loose_verts = [v for v in bm.verts if not v.link_faces]
    if loose_verts:
        bmesh.ops.delete(bm, geom=loose_verts, context="VERTS")

    bm.normal_update()
    bm.to_mesh(obj.data)
    obj.data.update()
    bm.free()

    return {
        "zero_deleted": len(zero_faces),
        "dups_deleted": len(dup_faces),
        "loose_edges_deleted": len(loose_edges),
        "loose_verts_deleted": len(loose_verts),
    }


def piecewise_linear_map(val: float, src_knots: list[float], dst_knots: list[float]) -> float:
    if val <= src_knots[0]:
        slope = (dst_knots[1] - dst_knots[0]) / (src_knots[1] - src_knots[0])
        return dst_knots[0] + (val - src_knots[0]) * slope
    if val >= src_knots[-1]:
        slope = (dst_knots[-1] - dst_knots[-2]) / (src_knots[-1] - src_knots[-2])
        return dst_knots[-1] + (val - src_knots[-1]) * slope
    return float(np.interp(val, src_knots, dst_knots))


def world_bounds(obj: bpy.types.Object) -> tuple[np.ndarray, np.ndarray]:
    pts = np.array([list(obj.matrix_world @ v.co) for v in obj.data.vertices], dtype=np.float64)
    return pts.min(axis=0), pts.max(axis=0)


def split_wheels_and_body(src_obj: bpy.types.Object) -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    """
    Separate the 4 wheel connected islands (145 verts each, cylindrical aspect)
    from the monolithic VW Golf MESH, returning (body_obj, wheel_objs).
    """
    bm = bmesh.new()
    bm.from_mesh(src_obj.data)
    bm.verts.ensure_lookup_table()

    visited = set()
    islands: list[list[bmesh.types.BMVert]] = []
    for v in bm.verts:
        if v.index in visited:
            continue
        stack = [v]
        comp = []
        visited.add(v.index)
        while stack:
            cur = stack.pop()
            comp.append(cur)
            for e in cur.link_edges:
                nxt = e.other_vert(cur)
                if nxt.index not in visited:
                    visited.add(nxt.index)
                    stack.append(nxt)
        islands.append(comp)

    wheel_islands = []
    orphan_verts = []
    for comp in islands:
        if len(comp) == 1:
            orphan_verts.extend(comp)
            continue
        pts = np.array([list(v.co) for v in comp], dtype=np.float64)
        sz = pts.max(axis=0) - pts.min(axis=0)
        # Wheels have 145 verts, near-circular YZ extent (0.21..0.22 m raw) and ~0.063 m width
        if 120 <= len(comp) <= 180 and abs(sz[1] - sz[2]) < 0.02 and sz[2] > 0.18 and sz[0] < 0.09:
            wheel_islands.append(comp)

    assert len(wheel_islands) == 4, f"Expected 4 wheel islands, found {len(wheel_islands)}"

    # Purge single-vertex orphans from source mesh first
    if orphan_verts:
        bmesh.ops.delete(bm, geom=orphan_verts, context="VERTS")
        bm.to_mesh(src_obj.data)
        src_obj.data.update()
    bm.free()

    # Duplicate each wheel island into its own mesh object, then delete wheel verts from body
    wheel_objs: list[bpy.types.Object] = []
    # Re-collect islands cleanly after orphan purge
    bm_body = bmesh.new()
    bm_body.from_mesh(src_obj.data)
    bm_body.verts.ensure_lookup_table()
    visited = set()
    wheel_vert_sets: list[set[int]] = []
    for v in bm_body.verts:
        if v.index in visited:
            continue
        stack = [v]
        comp = []
        visited.add(v.index)
        while stack:
            cur = stack.pop()
            comp.append(cur)
            for e in cur.link_edges:
                nxt = e.other_vert(cur)
                if nxt.index not in visited:
                    visited.add(nxt.index)
                    stack.append(nxt)
        pts = np.array([list(vv.co) for vv in comp], dtype=np.float64)
        sz = pts.max(axis=0) - pts.min(axis=0)
        if 120 <= len(comp) <= 180 and abs(sz[1] - sz[2]) < 0.02 and sz[2] > 0.18 and sz[0] < 0.09:
            wheel_vert_sets.append({vv.index for vv in comp})

    assert len(wheel_vert_sets) == 4, f"Re-scan expected 4 wheel sets, got {len(wheel_vert_sets)}"

    for idx, keep_set in enumerate(wheel_vert_sets):
        w_mesh = src_obj.data.copy()
        w_obj = bpy.data.objects.new(f"raw_wheel_{idx}", w_mesh)
        bpy.context.collection.objects.link(w_obj)
        bm_w = bmesh.new()
        bm_w.from_mesh(w_obj.data)
        bm_w.verts.ensure_lookup_table()
        del_verts = [vv for vv in bm_w.verts if vv.index not in keep_set]
        bmesh.ops.delete(bm_w, geom=del_verts, context="VERTS")
        bm_w.normal_update()
        bm_w.to_mesh(w_obj.data)
        w_obj.data.update()
        bm_w.free()
        wheel_objs.append(w_obj)

    all_wheel_indices = set().union(*wheel_vert_sets)
    del_from_body = [vv for vv in bm_body.verts if vv.index in all_wheel_indices]
    bmesh.ops.delete(bm_body, geom=del_from_body, context="VERTS")
    bm_body.normal_update()
    bm_body.to_mesh(src_obj.data)
    src_obj.data.update()
    bm_body.free()

    return src_obj, wheel_objs


def export_glb(objects: list[bpy.types.Object], out_path: Path) -> dict:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_set(False)
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        use_selection=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_yup=True,
        export_animations=False,
        export_morph=False,
    )
    return {
        "path": out_path.name,
        "sha256": sha256_file(out_path),
        "size_bytes": out_path.stat().st_size,
    }


def extract_zone_convex_hull_godot(
    verts_blender: np.ndarray,
    y_min_b: float,
    y_max_b: float,
    z_floor_b: float,
    max_points: int = 88,
) -> list[dict]:
    """Compute convex hull vertex set in Godot coords (-Z forward, +X right, +Y up) for a Y slice."""
    mask = (verts_blender[:, 1] >= y_min_b) & (verts_blender[:, 1] <= y_max_b)
    pts = verts_blender[mask].copy()
    pts[:, 2] = np.maximum(pts[:, 2], z_floor_b)

    uniq = {}
    for p in pts:
        key = (round(float(p[0]), 3), round(float(p[1]), 3), round(float(p[2]), 3))
        uniq[key] = p
    sampled = list(uniq.values())

    bm = bmesh.new()
    bm_verts = [bm.verts.new((float(p[0]), float(p[1]), float(p[2]))) for p in sampled]
    bm.verts.ensure_lookup_table()
    res = bmesh.ops.convex_hull(bm, input=bm_verts, use_existing_faces=False)
    hull_verts = [g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)]
    if len(hull_verts) > max_points:
        coords = np.array([[v.co.x, v.co.y, v.co.z] for v in hull_verts], dtype=np.float64)
        chosen = [int(np.argmax(coords[:, 2]))]
        dists = np.linalg.norm(coords - coords[chosen[0]], axis=1)
        while len(chosen) < max_points:
            nxt = int(np.argmax(dists))
            if nxt in chosen:
                break
            chosen.append(nxt)
            dists = np.minimum(dists, np.linalg.norm(coords - coords[nxt], axis=1))
        final_pts = [coords[i] for i in chosen]
    else:
        final_pts = [[v.co.x, v.co.y, v.co.z] for v in hull_verts]
    bm.free()

    # Blender (+X, +Y_fwd, +Z_up) -> Godot (+X, +Y_up, -Z_fwd)
    return [
        {
            "x": round(float(p[0]), 6),
            "y": round(float(p[2]), 6),
            "z": round(float(-p[1]), 6),
        }
        for p in final_pts
    ]


def main() -> None:
    ASSET_DIR.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmpdir:
        with zipfile.ZipFile(SRC_ZIP) as zf:
            fbx_member = next(n for n in zf.namelist() if n.lower().endswith(".fbx"))
            fbx_path = Path(zf.extract(fbx_member, tmpdir))

        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.fbx(filepath=str(fbx_path))
        bpy.context.view_layer.update()

    mesh_objs = [o for o in bpy.data.objects if o.type == "MESH"]
    assert len(mesh_objs) == 1, f"Expected 1 source mesh object, got {len(mesh_objs)}"
    src_obj = mesh_objs[0]
    bake_world_and_rotate_z180(src_obj)

    body_obj, wheel_objs = split_wheels_and_body(src_obj)

    wheel_centers = {}
    for w in wheel_objs:
        lo, hi = world_bounds(w)
        wheel_centers[w] = (lo + hi) * 0.5

    ys = sorted(c[1] for c in wheel_centers.values())
    y_mid = 0.5 * (ys[1] + ys[2])

    classified_wheels: dict[str, bpy.types.Object] = {}
    for w, c in wheel_centers.items():
        axle = "front" if c[1] > y_mid else "rear"
        side = "left" if c[0] < 0.0 else "right"
        key = f"{axle}_{side}"
        assert key not in classified_wheels, f"Duplicate wheel key {key}"
        classified_wheels[key] = w

    src_front_y = 0.5 * (
        wheel_centers[classified_wheels["front_left"]][1]
        + wheel_centers[classified_wheels["front_right"]][1]
    )
    src_rear_y = 0.5 * (
        wheel_centers[classified_wheels["rear_left"]][1]
        + wheel_centers[classified_wheels["rear_right"]][1]
    )
    src_hub_z = float(np.mean([c[2] for c in wheel_centers.values()]))

    body_lo, body_hi = world_bounds(body_obj)

    dst_rear_y = -0.5 * TARGET_WHEELBASE_M
    dst_front_y = +0.5 * TARGET_WHEELBASE_M
    dst_y_rear_bumper = dst_rear_y - TARGET_REAR_OVERHANG_M
    dst_y_front_bumper = dst_front_y + TARGET_FRONT_OVERHANG_M

    src_y_knots = [float(body_lo[1]), src_rear_y, src_front_y, float(body_hi[1])]
    dst_y_knots = [dst_y_rear_bumper, dst_rear_y, dst_front_y, dst_y_front_bumper]
    src_z_knots = [float(body_lo[2]), src_hub_z, float(body_hi[2])]
    dst_z_knots = [TARGET_BOTTOM_CLEARANCE_M, TARGET_TIRE_RADIUS_M, TARGET_ROOF_HEIGHT_M]

    for v in body_obj.data.vertices:
        v.co.x *= TARGET_X_SCALE
        v.co.y = piecewise_linear_map(v.co.y, src_y_knots, dst_y_knots)
        v.co.z = piecewise_linear_map(v.co.z, src_z_knots, dst_z_knots)
    body_obj.data.update()

    mat = build_pbr_material("VWGolfMk1Exterior_Mat")
    body_obj.name = "VWGolfMk1Exterior"
    body_obj.data.name = "VWGolfMk1Exterior"
    body_obj.data.materials.clear()
    body_obj.data.materials.append(mat)
    for poly in body_obj.data.polygons:
        poly.material_index = 0
        poly.use_smooth = True
    body_topo = clean_mesh_topology(body_obj)
    print(f"Chassis cleaned: {body_topo}")

    ch_lo, ch_hi = world_bounds(body_obj)
    print(f"Final chassis bounds (Blender): lo={np.round(ch_lo, 5)} hi={np.round(ch_hi, 5)}")

    chassis_meta = export_glb([body_obj], ASSET_DIR / "vw_golf_mk1_chassis.glb")
    chassis_meta["exported_nodes"] = [body_obj.name]

    pivots = {
        "front_left": {
            "blender_object": "tire_fl",
            "center_metres": {
                "x": -0.5 * TARGET_FRONT_TRACK_M,
                "y": TARGET_TIRE_RADIUS_M,
                "z": -0.5 * TARGET_WHEELBASE_M,
            },
            "radius_metres": TARGET_TIRE_RADIUS_M,
            "width_metres": TARGET_TIRE_WIDTH_M,
        },
        "front_right": {
            "blender_object": "tire_fr",
            "center_metres": {
                "x": +0.5 * TARGET_FRONT_TRACK_M,
                "y": TARGET_TIRE_RADIUS_M,
                "z": -0.5 * TARGET_WHEELBASE_M,
            },
            "radius_metres": TARGET_TIRE_RADIUS_M,
            "width_metres": TARGET_TIRE_WIDTH_M,
        },
        "rear_left": {
            "blender_object": "tire_rl",
            "center_metres": {
                "x": -0.5 * TARGET_REAR_TRACK_M,
                "y": TARGET_TIRE_RADIUS_M,
                "z": +0.5 * TARGET_WHEELBASE_M,
            },
            "radius_metres": TARGET_TIRE_RADIUS_M,
            "width_metres": TARGET_TIRE_WIDTH_M,
        },
        "rear_right": {
            "blender_object": "tire_rr",
            "center_metres": {
                "x": +0.5 * TARGET_REAR_TRACK_M,
                "y": TARGET_TIRE_RADIUS_M,
                "z": +0.5 * TARGET_WHEELBASE_M,
            },
            "radius_metres": TARGET_TIRE_RADIUS_M,
            "width_metres": TARGET_TIRE_WIDTH_M,
        },
    }

    wheel_node_names = {
        "front_left": "tire_fl",
        "front_right": "tire_fr",
        "rear_left": "tire_rl",
        "rear_right": "tire_rr",
    }
    wheels_meta = {}
    for wkey in ("front_left", "front_right", "rear_left", "rear_right"):
        wobj = classified_wheels[wkey]
        wobj.name = wheel_node_names[wkey]
        wobj.data.name = wheel_node_names[wkey]
        wlo, whi = world_bounds(wobj)
        wc = (wlo + whi) * 0.5
        wsz = whi - wlo
        sx = TARGET_TIRE_WIDTH_M / wsz[0]
        sy = (2.0 * TARGET_TIRE_RADIUS_M) / wsz[1]
        sz = (2.0 * TARGET_TIRE_RADIUS_M) / wsz[2]
        for v in wobj.data.vertices:
            v.co.x = (v.co.x - wc[0]) * sx
            v.co.y = (v.co.y - wc[1]) * sy
            v.co.z = (v.co.z - wc[2]) * sz
        wobj.data.update()

        wobj.data.materials.clear()
        wobj.data.materials.append(mat)
        for poly in wobj.data.polygons:
            poly.material_index = 0
            poly.use_smooth = True
        wtopo = clean_mesh_topology(wobj)
        wmeta = export_glb([wobj], ASSET_DIR / f"vw_golf_mk1_wheel_{wkey}.glb")
        wheels_meta[wkey] = wmeta
        print(f"Exported wheel {wkey}: {wmeta['path']} ({wmeta['size_bytes']} bytes) topo={wtopo}")

    # Build 3 convex hulls along Blender Y (+1.915..-1.826) for chassis collision
    verts_b = np.array([list(v.co) for v in body_obj.data.vertices], dtype=np.float64)
    z_floor_b = 0.20
    hulls = []
    for ident, y0, y1 in [
        ("front", 0.55, float(ch_hi[1]) + 0.01),
        ("cabin", -0.80, 0.70),
        ("rear", float(ch_lo[1]) - 0.01, -0.65),
    ]:
        pts_g = extract_zone_convex_hull_godot(verts_b, y0, y1, z_floor_b, max_points=88)
        hulls.append(
            {
                "identifier": ident,
                "points": pts_g,
                "point_count": len(pts_g),
            }
        )

    coll_doc = {
        "coordinate_system": {
            "forward": "-Z",
            "right": "+X",
            "up": "+Y",
            "origin": "ground plane under wheelbase center",
        },
        "source_object": "VWGolfMk1Exterior",
        "hulls": hulls,
        "boxes": [
            {
                "identifier": "sump_guard",
                "center": {"x": 0.0, "y": 0.20, "z": -0.95},
                "half_extents": {"x": 0.50, "y": 0.05, "z": 0.45},
            }
        ],
    }
    coll_path = ASSET_DIR / "vw_golf_mk1_collision.json"
    coll_path.write_text(json.dumps(coll_doc, indent=2) + "\n", encoding="utf-8")

    manifest = {
        "contract_version": 1,
        "vehicle_id": "vw_golf_mk1_gti",
        "source": {
            "fbx": f"{SRC_ZIP}!VW Golf Mk1.fbx",
            "texture": TEX_BASE.name,
            "blender_version": "5.2.0 LTS",
            "runtime_visuals": {
                "fbx": f"{SRC_ZIP}!VW Golf Mk1.fbx",
                "texture": TEX_BASE.name,
                "finish": "high_res_pbr_no_psx",
                "fit": (
                    "Scaled and fitted to VW Golf Mk1 GTI Group 2 (FIA 5584/5731/5732) "
                    "wheelbase (2.400 m) and length (3.741 m) with 185/70 R14 gravel wheels "
                    "(R=0.305 m, W=0.195 m) and 1.420/1.410 m tracks."
                ),
                "cockpit_enabled": False,
                "visual_damage_enabled": False,
            },
        },
        "coordinate_system": {
            "engine": "Godot",
            "forward": "-Z",
            "right": "+X",
            "up": "+Y",
            "conversion": "Blender Z-up rotated 180 deg around Z and exported with glTF +Y up",
            "visual_physics_offset_metres": 0.0,
        },
        "geometry": {
            "wheelbase": TARGET_WHEELBASE_M,
            "front_track": TARGET_FRONT_TRACK_M,
            "rear_track": TARGET_REAR_TRACK_M,
            "front_axle_z": -0.5 * TARGET_WHEELBASE_M,
            "rear_axle_z": +0.5 * TARGET_WHEELBASE_M,
        },
        "chassis": chassis_meta,
        "wheels": wheels_meta,
        "collision": {
            "path": coll_path.name,
            "sha256": sha256_file(coll_path),
        },
        "wheel_pivots": pivots,
        "bounds_world_metres": {
            "min_blender": [round(float(x), 6) for x in ch_lo],
            "max_blender": [round(float(x), 6) for x in ch_hi],
            "min_godot": [
                round(float(ch_lo[0]), 6),
                round(float(ch_lo[2]), 6),
                round(float(-ch_hi[1]), 6),
            ],
            "max_godot": [
                round(float(ch_hi[0]), 6),
                round(float(ch_hi[2]), 6),
                round(float(-ch_lo[1]), 6),
            ],
        },
        "capabilities": {
            "cockpit": False,
            "native_arm_poses": 0,
            "seats": 0,
            "damage_variants": 0,
        },
    }
    manifest_path = ASSET_DIR / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"VW_GOLF_MK1_ASSETS_BUILT_OK: {ASSET_DIR}")


if __name__ == "__main__":
    main()
