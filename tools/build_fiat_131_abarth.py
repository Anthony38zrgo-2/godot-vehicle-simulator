#!/usr/bin/env python3
"""
Build visual GLBs, manifest.json, and convex collision hulls for the
FIA Group 4 Fiat 131 Abarth Rally (`fiat_131_abarth`) from RallyManiacAssets.

Coordinates:
  Blender working space (after +180 deg Z bake): +X right, +Y forward, +Z up
  Godot / glTF +Y up export:                   +X right, -Z forward, +Y up

Usage:
  blender -b --factory-startup --python tools/build_fiat_131_abarth.py
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix

REPO = Path(__file__).resolve().parent.parent
SRC_FBX = Path(r"D:\RallyManiacAssets\cars\1965-2002-rally-cars\source\Cars\Fiat 131.fbx")
SRC_TEX = Path(r"D:\RallyManiacAssets\cars\1965-2002-rally-cars\source\Cars\Texture2D\fiat_131_abarth_alta.png")
ASSET_DIR = REPO / "game" / "assets" / "rally" / "fiat_131_abarth"

# Target FIA Homologation No. 647 (Group 4 Rally) dimensions in metres:
# - Wheelbase: 2.490 m (axles at +/- 1.245 m)
# - Length:    4.181 m (overhangs scaled proportionally to FBX: rear 1.020 m, front 0.671 m)
# - Width:     1.7576 m (preserves native Bertone Group 4 wide arch flares)
# - Height:    1.375 m roof top (chin air dam lifted slightly to 0.185 m above collision floor)
# - Tires:     185/70 R15 Gravel -> outer diameter 0.640 m (radius 0.320 m), width 0.200 m
# - Tracks:    1.461 m front (FIA 647), 1.460 m rear (Group 4 wide rally setup)
TARGET_WHEELBASE_M = 2.490
TARGET_LENGTH_M = 4.181
TARGET_FRONT_OVERHANG_M = 0.671
TARGET_REAR_OVERHANG_M = 1.020
TARGET_FRONT_TRACK_M = 1.461
TARGET_REAR_TRACK_M = 1.460
TARGET_TIRE_RADIUS_M = 0.320
TARGET_TIRE_WIDTH_M = 0.200
TARGET_BOTTOM_CLEARANCE_M = 0.185
TARGET_ROOF_HEIGHT_M = 1.375


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_clean_material(mat_name: str, tex_path: Path) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=mat_name)
    mat.use_nodes = True
    mat.use_backface_culling = False
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.40
    bsdf.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.35

    tex_node = nodes.new("ShaderNodeTexImage")
    img = bpy.data.images.load(str(tex_path), check_existing=True)
    img.colorspace_settings.name = "sRGB"
    img.alpha_mode = "NONE"
    img.pack()
    tex_node.image = img
    tex_node.interpolation = "Linear"

    links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])
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
    max_points: int = 96,
) -> list[dict]:
    """Compute convex hull vertex set in Godot coords (-Z forward, +X right, +Y up) for a Y slice."""
    mask = (verts_blender[:, 1] >= y_min_b) & (verts_blender[:, 1] <= y_max_b)
    pts = verts_blender[mask].copy()
    pts[:, 2] = np.maximum(pts[:, 2], z_floor_b)

    # Deduplicate on a fine grid before convex hull for deterministic compact shapes
    uniq = {}
    for p in pts:
        key = (round(float(p[0]), 3), round(float(p[1]), 3), round(float(p[2]), 3))
        uniq[key] = p
    sampled = list(uniq.values())

    bm = bmesh.new()
    bm_verts = [bm.verts.new((float(p[0]), float(p[1]), float(p[2]))) for p in sampled]
    bm.verts.ensure_lookup_table()
    res = bmesh.ops.convex_hull(bm, input=bm_verts, use_existing_faces=False)
    hull_verts = [
        g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)
    ]
    if len(hull_verts) > max_points:
        # Furthest-point downsample on hull vertices so convex extent stays maximal
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

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(SRC_FBX))
    bpy.context.view_layer.update()

    mesh_objs = [o for o in bpy.data.objects if o.type == "MESH"]
    for obj in mesh_objs:
        bake_world_and_rotate_z180(obj)

    body_obj = bpy.data.objects["Fiat 131"]
    wheel_objs = [o for o in mesh_objs if o != body_obj]
    assert len(wheel_objs) == 4, f"Expected 4 wheels, got {len(wheel_objs)}"

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
        v.co.y = piecewise_linear_map(v.co.y, src_y_knots, dst_y_knots)
        v.co.z = piecewise_linear_map(v.co.z, src_z_knots, dst_z_knots)
    body_obj.data.update()

    mat = build_clean_material("Fiat131AbarthExterior_Mat", SRC_TEX)
    body_obj.name = "Fiat131AbarthExterior"
    body_obj.data.name = "Fiat131AbarthExterior"
    body_obj.data.materials.clear()
    body_obj.data.materials.append(mat)
    for poly in body_obj.data.polygons:
        poly.material_index = 0
        poly.use_smooth = True
    body_topo = clean_mesh_topology(body_obj)
    print(f"Chassis cleaned: {body_topo}")

    ch_lo, ch_hi = world_bounds(body_obj)
    print(f"Final chassis bounds (Blender): lo={np.round(ch_lo, 5)} hi={np.round(ch_hi, 5)}")

    chassis_meta = export_glb([body_obj], ASSET_DIR / "fiat_131_abarth_chassis.glb")
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
        wmeta = export_glb([wobj], ASSET_DIR / f"fiat_131_abarth_wheel_{wkey}.glb")
        wheels_meta[wkey] = wmeta
        print(f"Exported wheel {wkey}: {wmeta['path']} ({wmeta['size_bytes']} bytes) topo={wtopo}")

    # Build 3 convex hulls along Blender Y (+1.916..-2.265) for chassis collision
    verts_b = np.array([list(v.co) for v in body_obj.data.vertices], dtype=np.float64)
    z_floor_b = 0.20
    hulls = []
    for ident, y0, y1 in [
        ("front", 0.55, float(ch_hi[1]) + 0.01),
        ("cabin", -0.85, 0.70),
        ("rear", float(ch_lo[1]) - 0.01, -0.70),
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
        "source_object": "Fiat131AbarthExterior",
        "hulls": hulls,
        "boxes": [
            {
                "identifier": "sump_guard",
                "center": {"x": 0.0, "y": 0.21, "z": -0.95},
                "half_extents": {"x": 0.54, "y": 0.05, "z": 0.48},
            }
        ],
    }
    coll_path = ASSET_DIR / "fiat_131_abarth_collision.json"
    coll_path.write_text(json.dumps(coll_doc, indent=2) + "\n", encoding="utf-8")

    manifest = {
        "contract_version": 1,
        "vehicle_id": "fiat_131_abarth",
        "source": {
            "fbx": str(SRC_FBX),
            "texture": SRC_TEX.name,
            "blender_version": "5.2.0 LTS",
            "runtime_visuals": {
                "fbx": str(SRC_FBX),
                "texture": SRC_TEX.name,
                "finish": "high_res_pbr_no_psx",
                "fit": (
                    "Piecewise-linear longitudinal fit to FIA Homologation No. 647 Group 4 "
                    "wheelbase (2.490 m) and length (4.181 m) with wide Bertone Gr.4 arch width "
                    "(1.758 m) preserved and 185/70 R15 gravel wheels (R=0.320 m, W=0.200 m)."
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
    print(f"FIAT_131_ASSETS_BUILT_OK: {ASSET_DIR}")


if __name__ == "__main__":
    main()
