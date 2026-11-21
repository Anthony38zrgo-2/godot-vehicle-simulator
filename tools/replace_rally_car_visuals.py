#!/usr/bin/env python3
"""
Replace visual GLBs (chassis + 4 wheels) for:
  - ford_escort_rs2000_1971  <- Ford Escort RS1800 with lights.fbx + ford_escort_RS1800_alta.png
  - rt-alpine-a110           <- Renault Alpine.fbx + renault_alpine_a110_alta.png
  - rt-mini-cooper-s         <- Mini Cooper.fbx + mini_cooper_S_alta.png
  - rt-lancia-stratos        <- Lancia Stratos with lights.fbx + lancia_stratos_alta.png

Fits each chassis to the existing runtime chassis bounds (piecewise linear across longitudinal
axles and hub height) and scales each wheel to the exact manifest wheel_pivots radius & width,
keeping all physics, collision, audio, and axle geometry 100% untouched.

Usage:
  blender -b --factory-startup --python tools/replace_rally_car_visuals.py
"""

from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

REPO = Path(__file__).resolve().parent.parent
SRC_ROOT = Path(r"D:\RallyManiacAssets\cars\1965-2002-rally-cars\source\Cars")
TEX_ROOT = SRC_ROOT / "Texture2D"

TARGETS = [
    {
        "vehicle_id": "ford_escort_rs2000_1971",
        "asset_dir": REPO / "game/assets/rally/ford_escort_rs2000_1971",
        "fbx": SRC_ROOT / "Ford Escort RS1800 with lights.fbx",
        "texture": TEX_ROOT / "ford_escort_RS1800_alta.png",
        "chassis_node_name": "EscortRS1800Exterior",
        "body_meshes": ["Ford Escort RS1800"],
        "extra_meshes": ["fanale1_geo.001"],
        "chassis_glb": "ford_escort_rs2000_1971_chassis.glb",
        "wheel_glbs": {
            "front_left": "ford_escort_rs2000_1971_wheel_front_left.glb",
            "front_right": "ford_escort_rs2000_1971_wheel_front_right.glb",
            "rear_left": "ford_escort_rs2000_1971_wheel_rear_left.glb",
            "rear_right": "ford_escort_rs2000_1971_wheel_rear_right.glb",
        },
        # Sill height of existing body is ~0.10 m (0.005 m is only mudflaps)
        "z_bottom_override": 0.10,
    },
    {
        "vehicle_id": "rt-alpine-a110",
        "asset_dir": REPO / "game/assets/rally/rt/rt-alpine-a110",
        "fbx": SRC_ROOT / "Renault Alpine.fbx",
        "texture": TEX_ROOT / "renault_alpine_a110_alta.png",
        "chassis_node_name": "AlpineA110Exterior",
        "body_meshes": ["Renault Alpine"],
        "extra_meshes": [],
        "chassis_glb": "chassis.glb",
        "wheel_glbs": {
            "front_left": "wheel_front_left.glb",
            "front_right": "wheel_front_right.glb",
            "rear_left": "wheel_rear_left.glb",
            "rear_right": "wheel_rear_right.glb",
        },
        "z_bottom_override": None,
    },
    {
        "vehicle_id": "rt-mini-cooper-s",
        "asset_dir": REPO / "game/assets/rally/rt/rt-mini-cooper-s",
        "fbx": SRC_ROOT / "Mini Cooper.fbx",
        "texture": TEX_ROOT / "mini_cooper_S_alta.png",
        "chassis_node_name": "MiniCooperExterior",
        "body_meshes": ["body_geo #370564"],
        "extra_meshes": [],
        "chassis_glb": "chassis.glb",
        "wheel_glbs": {
            "front_left": "wheel_front_left.glb",
            "front_right": "wheel_front_right.glb",
            "rear_left": "wheel_rear_left.glb",
            "rear_right": "wheel_rear_right.glb",
        },
        # Use symmetric body half-width (0.724 m; -0.762 m was only an asymmetric mirror)
        # and sill height ~0.10 m (0.055 m was mudflap/exhaust tip).
        "x_half_width_override": 0.724,
        "z_bottom_override": 0.10,
    },
    {
        "vehicle_id": "rt-lancia-stratos",
        "asset_dir": REPO / "game/assets/rally/rt/rt-lancia-stratos",
        "fbx": SRC_ROOT / "Lancia Stratos with lights.fbx",
        "texture": TEX_ROOT / "lancia_stratos_alta.png",
        "chassis_node_name": "LanciaStratosExterior",
        "body_meshes": ["body_geo #370683"],
        "extra_meshes": ["fanali_geo #370649"],
        "chassis_glb": "chassis.glb",
        "wheel_glbs": {
            "front_left": "wheel_front_left.glb",
            "front_right": "wheel_front_right.glb",
            "rear_left": "wheel_rear_left.glb",
            "rear_right": "wheel_rear_right.glb",
        },
        # Sill height of existing Stratos is ~0.101 m (0.010 m is mudflap)
        "z_bottom_override": 0.10,
    },
]


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
    """Apply world matrix into mesh data, then rotate 180 deg around Z so car faces +Y Blender (-Z Godot)."""
    rot180 = Matrix.Rotation(math.pi, 4, "Z")
    xf = rot180 @ obj.matrix_world
    obj.data.transform(xf)
    obj.parent = None
    obj.matrix_world = Matrix.Identity(4)


def clean_mesh_topology(obj: bpy.types.Object) -> dict:
    """Remove zero-area faces, same-winding duplicate faces, and loose vertices/edges."""
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
    """Piecewise linear map with linear extrapolation outside the outermost knots."""
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


def process_vehicle(cfg: dict) -> None:
    vid = cfg["vehicle_id"]
    asset_dir: Path = cfg["asset_dir"]
    manifest_path = asset_dir / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    print(f"\n========================================")
    print(f"Processing {vid} from {cfg['fbx'].name}")
    print(f"========================================")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(cfg["fbx"]))
    bpy.context.view_layer.update()

    # Rotate every mesh 180 deg around Z and bake transforms to world space
    mesh_objs = [o for o in bpy.data.objects if o.type == "MESH"]
    for obj in mesh_objs:
        bake_world_and_rotate_z180(obj)

    body_objs = [bpy.data.objects[name] for name in cfg["body_meshes"]]
    extra_objs = [bpy.data.objects[name] for name in cfg["extra_meshes"]]
    wheel_objs = [o for o in mesh_objs if o not in body_objs and o not in extra_objs]
    assert len(wheel_objs) == 4, f"Expected 4 wheels in {cfg['fbx'].name}, found {len(wheel_objs)}"

    # Classify wheels after Z-180 rotation:
    # Front is +Y Blender (-Z Godot), Rear is -Y Blender (+Z Godot)
    # Left is -X, Right is +X
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
        assert key not in classified_wheels, f"Duplicate wheel key {key} for {vid}"
        classified_wheels[key] = w

    src_front_y = 0.5 * (wheel_centers[classified_wheels["front_left"]][1] + wheel_centers[classified_wheels["front_right"]][1])
    src_rear_y = 0.5 * (wheel_centers[classified_wheels["rear_left"]][1] + wheel_centers[classified_wheels["rear_right"]][1])
    src_hub_z = float(np.mean([c[2] for c in wheel_centers.values()]))

    # Compute source body bounds (excluding extra light pods so front bumper knot matches main body)
    body_pts = np.concatenate(
        [np.array([list(v.co) for v in b.data.vertices], dtype=np.float64) for b in body_objs],
        axis=0,
    )
    src_body_lo = body_pts.min(axis=0)
    src_body_hi = body_pts.max(axis=0)

    # Read target bounds & wheel pivots from existing manifest
    min_godot = manifest["bounds_world_metres"]["min_godot"]
    max_godot = manifest["bounds_world_metres"]["max_godot"]

    # Convert target Godot bounds to Blender Z-up coordinates:
    # Blender X = Godot X, Blender Y = -Godot Z, Blender Z = Godot Y
    if cfg.get("x_half_width_override") is not None:
        hw = float(cfg["x_half_width_override"])
        dst_x_lo, dst_x_hi = -hw, hw
    else:
        dst_x_lo, dst_x_hi = float(min_godot[0]), float(max_godot[0])

    dst_y_rear_bumper = -float(max_godot[2])
    dst_y_front_bumper = -float(min_godot[2])
    dst_z_bottom = float(cfg["z_bottom_override"]) if cfg.get("z_bottom_override") is not None else float(min_godot[1])
    dst_z_roof = float(max_godot[1])

    pivots = manifest["wheel_pivots"]
    dst_front_y = -0.5 * (
        float(pivots["front_left"]["center_metres"]["z"]) + float(pivots["front_right"]["center_metres"]["z"])
    )
    dst_rear_y = -0.5 * (
        float(pivots["rear_left"]["center_metres"]["z"]) + float(pivots["rear_right"]["center_metres"]["z"])
    )
    dst_hub_z = float(
        np.mean(
            [
                float(pivots[k]["center_metres"]["y"])
                for k in ("front_left", "front_right", "rear_left", "rear_right")
            ]
        )
    )

    print(f"  Src body bounds (Blender): lo={np.round(src_body_lo, 4)} hi={np.round(src_body_hi, 4)}")
    print(f"  Src axles Y: rear={src_rear_y:.4f}, front={src_front_y:.4f}, hub_z={src_hub_z:.4f}")
    print(f"  Dst bounds (Blender): X=[{dst_x_lo:.4f}, {dst_x_hi:.4f}], Y=[{dst_y_rear_bumper:.4f}, {dst_y_front_bumper:.4f}], Z=[{dst_z_bottom:.4f}, {dst_z_roof:.4f}]")
    print(f"  Dst axles Y: rear={dst_rear_y:.4f}, front={dst_front_y:.4f}, hub_z={dst_hub_z:.4f}")

    # Build clean PBR material with high-res _alta.png texture
    mat = build_clean_material(f"{cfg['chassis_node_name']}_Mat", cfg["texture"])

    # Join body + extra_meshes (light pods) into one clean chassis mesh object
    chassis_parts = body_objs + extra_objs
    bpy.ops.object.select_all(action="DESELECT")
    for p in chassis_parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = chassis_parts[0]
    if len(chassis_parts) > 1:
        bpy.ops.object.join()
    chassis_obj = bpy.context.active_object
    chassis_obj.name = cfg["chassis_node_name"]
    chassis_obj.data.name = cfg["chassis_node_name"]

    # Apply piecewise linear fit to chassis vertices (extrapolating smoothly for front light pods)
    src_y_knots = [float(src_body_lo[1]), src_rear_y, src_front_y, float(src_body_hi[1])]
    dst_y_knots = [dst_y_rear_bumper, dst_rear_y, dst_front_y, dst_y_front_bumper]
    src_z_knots = [float(src_body_lo[2]), src_hub_z, float(src_body_hi[2])]
    dst_z_knots = [dst_z_bottom, dst_hub_z, dst_z_roof]
    src_x_knots = [float(src_body_lo[0]), float(src_body_hi[0])]
    dst_x_knots = [dst_x_lo, dst_x_hi]

    for v in chassis_obj.data.vertices:
        v.co.x = piecewise_linear_map(v.co.x, src_x_knots, dst_x_knots)
        v.co.y = piecewise_linear_map(v.co.y, src_y_knots, dst_y_knots)
        v.co.z = piecewise_linear_map(v.co.z, src_z_knots, dst_z_knots)
    chassis_obj.data.update()

    # Assign clean material & clean topology
    chassis_obj.data.materials.clear()
    chassis_obj.data.materials.append(mat)
    for poly in chassis_obj.data.polygons:
        poly.material_index = 0
        poly.use_smooth = True
    topo = clean_mesh_topology(chassis_obj)
    print(f"  Chassis cleaned: {topo}")

    ch_lo, ch_hi = world_bounds(chassis_obj)
    print(f"  Final chassis bounds (Blender): lo={np.round(ch_lo, 5)} hi={np.round(ch_hi, 5)}")

    # Export chassis GLB
    chassis_meta = export_glb([chassis_obj], asset_dir / cfg["chassis_glb"])
    chassis_meta["exported_nodes"] = [chassis_obj.name]
    print(f"  Exported {cfg['chassis_glb']} ({chassis_meta['size_bytes']} bytes)")

    # Process & export each wheel centered at (0,0,0) with exact target radius & width
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
        target_r = float(pivots[wkey]["radius_metres"])
        target_w = float(pivots[wkey]["width_metres"])

        sx = target_w / wsz[0]
        sy = (2.0 * target_r) / wsz[1]
        sz = (2.0 * target_r) / wsz[2]

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

        fwlo, fwhi = world_bounds(wobj)
        wmeta = export_glb([wobj], asset_dir / cfg["wheel_glbs"][wkey])
        wheels_meta[wkey] = wmeta
        print(
            f"  Exported {cfg['wheel_glbs'][wkey]}: size={np.round(fwhi - fwlo, 5)} "
            f"(target W={target_w:.5f}, D={2*target_r:.5f}) topo={wtopo}"
        )

    # Update manifest.json preserving all physics/geometry/collision fields
    manifest.setdefault("source", {})["runtime_visuals"] = {
        "fbx": str(cfg["fbx"]),
        "texture": cfg["texture"].name,
        "finish": "high_res_pbr_no_psx",
        "fit": (
            "Exterior fitted to existing runtime chassis bounds with piecewise-linear longitudinal "
            "axle alignment and hub height preserved; wheel meshes match original manifest radius and width."
        ),
        "cockpit_enabled": False,
        "visual_damage_enabled": False,
    }

    # Update chassis entry while preserving only relevant fields
    manifest["chassis"]["path"] = chassis_meta["path"]
    manifest["chassis"]["sha256"] = chassis_meta["sha256"]
    manifest["chassis"]["size_bytes"] = chassis_meta["size_bytes"]
    manifest["chassis"]["exported_nodes"] = chassis_meta["exported_nodes"]
    manifest["chassis"].pop("source_objects", None)

    for wkey, wmeta in wheels_meta.items():
        manifest["wheels"][wkey]["path"] = wmeta["path"]
        manifest["wheels"][wkey]["sha256"] = wmeta["sha256"]
        manifest["wheels"][wkey]["size_bytes"] = wmeta["size_bytes"]

    if "capabilities" in manifest:
        manifest["capabilities"]["cockpit"] = False
        manifest["capabilities"]["native_arm_poses"] = 0
        manifest["capabilities"]["seats"] = 0
        manifest["capabilities"]["damage_variants"] = 0

    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"  Updated {manifest_path.relative_to(REPO)}")


def main() -> None:
    for cfg in TARGETS:
        process_vehicle(cfg)
    print("\nALL_FOUR_VEHICLES_REPLACED_OK")


if __name__ == "__main__":
    main()
