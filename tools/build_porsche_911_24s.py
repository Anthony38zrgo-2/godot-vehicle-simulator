#!/usr/bin/env python3
"""
Build visual GLBs, manifest.json, and convex collision hulls for the
1972-1973 Porsche 911 2.4 S (`porsche_911_24s`) from D:\\RallyManiacAssets\\90120\\cars\\90120.

Official Porsche 911 2.4 S (F-Series LWB) dimensions in metres:
  - Wheelbase:      2.271 m (front axle -1.1355 m, rear axle +1.1355 m in Godot)
  - Length:         4.163 m (front overhang 0.880 m, rear overhang 1.012 m)
  - Body width:     1.610 m (shell +/- 0.805 m; mirrors protrude slightly beyond)
  - Height:         1.320 m (ground clearance 0.155 m, roof top 1.320 m)
  - Tracks:         1.372 m front (+/- 0.686 m), 1.354 m rear (+/- 0.677 m)
  - Tires:          185/70 VR 15 on 6Jx15 -> OD 0.640 m (radius 0.320 m), width 0.195 m

Coordinates:
  Blender working space: +X right, +Y forward, +Z up
  Godot / glTF +Y up:    +X right, -Z forward, +Y up

Usage:
  blender -b --factory-startup --python tools/build_porsche_911_24s.py
"""

from __future__ import annotations

import hashlib
import json
import struct
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

REPO = Path(__file__).resolve().parent.parent
SRC_DIR = Path(r"D:\RallyManiacAssets\90120\cars\90120")
ASSET_DIR = REPO / "game" / "assets" / "rally" / "porsche_911_24s"

TARGET_WHEELBASE_M = 2.271
TARGET_LENGTH_M = 4.163
TARGET_FRONT_OVERHANG_M = 0.880
TARGET_REAR_OVERHANG_M = 1.012
TARGET_BODY_HALF_WIDTH_M = 0.805
TARGET_FRONT_TRACK_M = 1.372
TARGET_REAR_TRACK_M = 1.354
TARGET_TIRE_RADIUS_M = 0.320
TARGET_TIRE_WIDTH_M = 0.195
TARGET_BOTTOM_CLEARANCE_M = 0.155
TARGET_ROOF_HEIGHT_M = 1.320

# Source body.prm constants (in Re-Volt coords converted to Blender: x, z, -y)
SRC_SHELL_HALF_X = 28.542
SRC_REAR_AXLE_Y = -37.500
SRC_FRONT_AXLE_Y = 42.500
SRC_REAR_BUMPER_Y = -74.165
SRC_FRONT_BUMPER_Y = 74.363
SRC_Z_MIN = -15.105
SRC_HUB_Z = -12.500
SRC_Z_MAX = 22.653

POLY_QUAD = 1 << 0
POLY_NOENV = 1 << 10


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def piecewise_linear_map(val: float, src_knots: list[float], dst_knots: list[float]) -> float:
    if val <= src_knots[0]:
        slope = (dst_knots[1] - dst_knots[0]) / (src_knots[1] - src_knots[0])
        return dst_knots[0] + (val - src_knots[0]) * slope
    if val >= src_knots[-1]:
        slope = (dst_knots[-1] - dst_knots[-2]) / (src_knots[-1] - src_knots[-2])
        return dst_knots[-1] + (val - src_knots[-1]) * slope
    return float(np.interp(val, src_knots, dst_knots))


def parse_prm(path: Path):
    data = path.read_bytes()
    poly_num, vert_num = struct.unpack_from("<HH", data, 0)
    polys = []
    for i in range(poly_num):
        off = 4 + i * 60
        ptype, tpage, v0, v1, v2, v3 = struct.unpack_from("<hhHHHH", data, off)
        uvs = struct.unpack_from("<ffffffff", data, off + 28)
        if ptype & POLY_QUAD:
            vis = (v0, v3, v2, v1)
            fuvs = (
                (uvs[0], 1.0 - uvs[1]),
                (uvs[6], 1.0 - uvs[7]),
                (uvs[4], 1.0 - uvs[5]),
                (uvs[2], 1.0 - uvs[3]),
            )
        else:
            vis = (v0, v2, v1)
            fuvs = (
                (uvs[0], 1.0 - uvs[1]),
                (uvs[4], 1.0 - uvs[5]),
                (uvs[2], 1.0 - uvs[3]),
            )
        polys.append({"type": ptype, "tpage": tpage, "verts": vis, "uvs": fuvs})

    voff = 4 + poly_num * 60
    verts = []
    for i in range(vert_num):
        x, y, z, nx, ny, nz = struct.unpack_from("<ffffff", data, voff + i * 24)
        # Re-Volt (+X right, +Y down, +Z forward) -> Blender (+X right, +Y forward, +Z up)
        verts.append((Vector((x, z, -y)), Vector((nx, nz, -ny))))
    return verts, polys


def load_packed_png(bmp_path: Path, png_out: Path, name: str) -> bpy.types.Image:
    tmp = bpy.data.images.load(str(bmp_path), check_existing=False)
    _ = tmp.size[0]
    _ = tmp.pixels[0]
    tmp.filepath_raw = str(png_out)
    tmp.file_format = "PNG"
    tmp.save()
    bpy.data.images.remove(tmp)

    img = bpy.data.images.load(str(png_out), check_existing=False)
    img.name = name
    img.colorspace_settings.name = "sRGB"
    img.alpha_mode = "NONE"
    img.pack()
    return img


def load_wheel_padded_png(body_png_path: Path, wheel_png_out: Path, name: str) -> bpy.types.Image:
    """Create a wheel-only diffuse PNG keeping only the grayscale rim/tire UV region
    and dilating its edge colors outward so bilinear/mipmap filtering never bleeds
    adjacent red body paint or blue window tint into the wheel rim at any distance."""
    tmp = bpy.data.images.load(str(body_png_path), check_existing=False)
    w, h = tmp.size[0], tmp.size[1]
    px = np.empty(w * h * 4, dtype=np.float32)
    tmp.pixels.foreach_get(px)
    arr = px.reshape((h, w, 4))  # Blender bottom-up: row 0 = bottom of image (RV V=1.0)
    rgb = arr[:, :, :3].copy()

    # In Blender bottom-up coordinates, wheel UVs occupy X >= 0.73*w and Y <= 0.16*h (top-down V >= 0.84)
    # Keep only neutral grayscale rim/rubber pixels inside that region (no red paint, no blue tint)
    ys, xs = np.mgrid[0:h, 0:w]
    chroma = np.max(rgb, axis=2) - np.min(rgb, axis=2)
    valid = (xs >= int(0.734 * w)) & (ys <= int(0.147 * h)) & (chroma < 0.08)

    # Multi-pass dilation across the full sheet so every mipmap level stays 100% neutral gray/rubber
    cur_rgb = rgb.copy()
    cur_valid = valid.copy()
    # First seed far left/top quickly with rim gray and tire dark gray, then dilate smoothly from true edges
    for _ in range(64):
        if np.all(cur_valid):
            break
        acc = np.zeros_like(cur_rgb)
        cnt = np.zeros((h, w), dtype=np.float32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            sv = np.zeros_like(cur_valid)
            sc = np.zeros_like(cur_rgb)
            sy0 = max(0, dy); sy1 = h + min(0, dy)
            sx0 = max(0, dx); sx1 = w + min(0, dx)
            ty0 = max(0, -dy); ty1 = h + min(0, -dy)
            tx0 = max(0, -dx); tx1 = w + min(0, -dx)
            sv[sy0:sy1, sx0:sx1] = cur_valid[ty0:ty1, tx0:tx1]
            sc[sy0:sy1, sx0:sx1] = cur_rgb[ty0:ty1, tx0:tx1]
            m = (~cur_valid) & sv
            acc[m] += sc[m]
            cnt[m] += 1.0
        fill = (~cur_valid) & (cnt > 0)
        if not np.any(fill):
            break
        cur_rgb[fill] = acc[fill] / cnt[fill, None]
        cur_valid[fill] = True

    # Fill any remaining outer pixels beyond 64 px from the nearest rim/rubber edge cleanly by X split
    rim_fill = (~cur_valid) & (xs < int(0.863 * w))
    tire_fill = (~cur_valid) & (xs >= int(0.863 * w))
    cur_rgb[rim_fill] = cur_rgb[int(0.05 * h), int(0.78 * w)]
    cur_rgb[tire_fill] = cur_rgb[int(0.05 * h), int(0.92 * w)]

    arr[:, :, :3] = cur_rgb
    arr[:, :, 3] = 1.0

    out_img = bpy.data.images.new(name=name, width=w, height=h, alpha=False)
    out_img.colorspace_settings.name = "sRGB"
    out_img.pixels.foreach_set(arr.ravel())
    out_img.filepath_raw = str(wheel_png_out)
    out_img.file_format = "PNG"
    out_img.save()
    bpy.data.images.remove(tmp)
    bpy.data.images.remove(out_img)

    final_img = bpy.data.images.load(str(wheel_png_out), check_existing=False)
    final_img.name = name
    final_img.colorspace_settings.name = "sRGB"
    final_img.alpha_mode = "NONE"
    final_img.pack()
    return final_img


def make_pbr_material(name: str, image: bpy.types.Image, roughness: float, metallic: float, specular: float) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_backface_culling = False
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = specular

    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Linear"

    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def build_mesh_from_prm(
    name: str,
    prm_path: Path,
    materials: list[bpy.types.Material],
    split_gloss_matte: bool = False,
    map_body_to_24s: bool = False,
) -> tuple[bpy.types.Object, dict]:
    verts, polys = parse_prm(prm_path)

    sx = TARGET_BODY_HALF_WIDTH_M / SRC_SHELL_HALF_X
    dst_rear_y = -0.5 * TARGET_WHEELBASE_M
    dst_front_y = +0.5 * TARGET_WHEELBASE_M
    src_y_knots = [SRC_REAR_BUMPER_Y, SRC_REAR_AXLE_Y, SRC_FRONT_AXLE_Y, SRC_FRONT_BUMPER_Y]
    dst_y_knots = [
        dst_rear_y - TARGET_REAR_OVERHANG_M,
        dst_rear_y,
        dst_front_y,
        dst_front_y + TARGET_FRONT_OVERHANG_M,
    ]
    src_z_knots = [SRC_Z_MIN, SRC_HUB_Z, SRC_Z_MAX]
    dst_z_knots = [TARGET_BOTTOM_CLEARANCE_M, TARGET_TIRE_RADIUS_M, TARGET_ROOF_HEIGHT_M]

    mapped_verts = []
    for pos, nrm in verts:
        if map_body_to_24s:
            mp = Vector((
                pos.x * sx,
                piecewise_linear_map(pos.y, src_y_knots, dst_y_knots),
                piecewise_linear_map(pos.z, src_z_knots, dst_z_knots),
            ))
            mn = Vector((nrm.x / sx, nrm.y / 0.0283875, nrm.z / 0.030854))
            if mn.length > 1e-6:
                mn.normalize()
            mapped_verts.append((mp, mn))
        else:
            mn = nrm.normalized() if nrm.length > 1e-6 else Vector((0.0, 0.0, 1.0))
            mapped_verts.append((pos.copy(), mn))

    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    bm_verts = [bm.verts.new(pos) for pos, _ in mapped_verts]
    bm.verts.ensure_lookup_table()

    face_v_indices = []
    skipped = 0
    for p in polys:
        vis = p["verts"]
        fuvs = p["uvs"]
        if len(set(vis)) < 3:
            skipped += 1
            continue
        if len(vis) == 4 and len(set(vis)) == 3:
            seen = set()
            nvis, nuvs = [], []
            for vi, uv in zip(vis, fuvs):
                if vi not in seen:
                    seen.add(vi)
                    nvis.append(vi)
                    nuvs.append(uv)
            vis, fuvs = tuple(nvis), tuple(nuvs)
        try:
            face = bm.faces.new([bm_verts[vi] for vi in vis])
        except ValueError:
            dup_verts = [bm.verts.new(mapped_verts[vi][0]) for vi in vis]
            face = bm.faces.new(dup_verts)
        face.smooth = True
        face.material_index = (1 if (p["type"] & POLY_NOENV) else 0) if split_gloss_matte else 0
        for loop, uv in zip(face.loops, fuvs):
            loop[uv_layer].uv = uv
        face_v_indices.append(vis)

    bm.to_mesh(mesh)
    bm.free()

    for m in materials:
        mesh.materials.append(m)

    loop_normals = [mapped_verts[vi][1] for vis in face_v_indices for vi in vis]
    if len(loop_normals) == len(mesh.loops):
        mesh.normals_split_custom_set(loop_normals)
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj, {"verts": len(mesh.vertices), "faces": len(mesh.polygons), "skipped": skipped}


def world_bounds(obj: bpy.types.Object) -> tuple[np.ndarray, np.ndarray]:
    pts = np.array([list(obj.matrix_world @ v.co) for v in obj.data.vertices], dtype=np.float64)
    return pts.min(axis=0), pts.max(axis=0)


def export_glb(obj: bpy.types.Object, out_path: Path) -> dict:
    bpy.ops.object.select_all(action="DESELECT")
    obj.hide_set(False)
    obj.hide_render = False
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
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

    return [
        {"x": round(float(p[0]), 6), "y": round(float(p[2]), 6), "z": round(float(-p[1]), 6)}
        for p in final_pts
    ]


def main() -> None:
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)

    tex_png = ASSET_DIR / "porsche_911_24s_diffuse.png"
    wheel_tex_png = ASSET_DIR / "porsche_911_24s_wheel_diffuse.png"
    img = load_packed_png(SRC_DIR / "car.bmp", tex_png, "Porsche911_24S_Diffuse")
    wheel_img = load_wheel_padded_png(tex_png, wheel_tex_png, "Porsche911_24S_Wheel_Diffuse")

    mat_gloss = make_pbr_material("Porsche911_24S_Body_Gloss", img, roughness=0.26, metallic=0.05, specular=0.50)
    mat_matte = make_pbr_material("Porsche911_24S_Body_Matte", img, roughness=0.72, metallic=0.0, specular=0.25)
    mat_wheel = make_pbr_material("Porsche911_24S_Wheel", wheel_img, roughness=0.52, metallic=0.16, specular=0.38)

    chassis_obj, ch_stats = build_mesh_from_prm(
        "Porsche911_24S_Exterior",
        SRC_DIR / "body.prm",
        [mat_gloss, mat_matte],
        split_gloss_matte=True,
        map_body_to_24s=True,
    )
    ch_lo, ch_hi = world_bounds(chassis_obj)
    print(f"Chassis built ({ch_stats}): bounds_bl lo={np.round(ch_lo, 5)} hi={np.round(ch_hi, 5)}")

    chassis_meta = export_glb(chassis_obj, ASSET_DIR / "porsche_911_24s_chassis.glb")
    chassis_meta["exported_nodes"] = [chassis_obj.name]
    print(f"Exported {chassis_meta['path']} ({chassis_meta['size_bytes']} bytes)")

    wheel_defs = [
        ("front_left", "wheel-l.prm", "tire_fl", -0.5 * TARGET_FRONT_TRACK_M, -0.5 * TARGET_WHEELBASE_M),
        ("front_right", "wheel-r.prm", "tire_fr", +0.5 * TARGET_FRONT_TRACK_M, -0.5 * TARGET_WHEELBASE_M),
        ("rear_left", "wheel-l.prm", "tire_rl", -0.5 * TARGET_REAR_TRACK_M, +0.5 * TARGET_WHEELBASE_M),
        ("rear_right", "wheel-r.prm", "tire_rr", +0.5 * TARGET_REAR_TRACK_M, +0.5 * TARGET_WHEELBASE_M),
    ]

    pivots = {}
    wheels_meta = {}
    for wkey, prm_name, node_name, px, pz in wheel_defs:
        wobj, _ = build_mesh_from_prm(
            node_name,
            SRC_DIR / prm_name,
            [mat_wheel],
            split_gloss_matte=False,
            map_body_to_24s=False,
        )
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

        wmeta = export_glb(wobj, ASSET_DIR / f"porsche_911_24s_wheel_{wkey}.glb")
        wheels_meta[wkey] = wmeta
        fwlo, fwhi = world_bounds(wobj)
        print(
            f"Exported {wmeta['path']} ({wmeta['size_bytes']} bytes): "
            f"center={np.round((fwlo + fwhi) * 0.5, 5)} size={np.round(fwhi - fwlo, 5)}"
        )
        pivots[wkey] = {
            "blender_object": node_name,
            "center_metres": {
                "x": round(px, 6),
                "y": round(TARGET_TIRE_RADIUS_M, 6),
                "z": round(pz, 6),
            },
            "radius_metres": TARGET_TIRE_RADIUS_M,
            "width_metres": TARGET_TIRE_WIDTH_M,
        }

    # Build 3 convex hulls along Blender Y (+2.0155..-2.1475) for chassis collision
    verts_b = np.array([list(v.co) for v in chassis_obj.data.vertices], dtype=np.float64)
    z_floor_b = 0.20
    hulls = []
    for ident, y0, y1 in [
        ("front", 0.55, float(ch_hi[1]) + 0.01),
        ("cabin", -0.80, 0.70),
        ("rear", float(ch_lo[1]) - 0.01, -0.65),
    ]:
        pts_g = extract_zone_convex_hull_godot(verts_b, y0, y1, z_floor_b, max_points=88)
        hulls.append({"identifier": ident, "points": pts_g, "point_count": len(pts_g)})

    coll_doc = {
        "coordinate_system": {
            "forward": "-Z",
            "right": "+X",
            "up": "+Y",
            "origin": "ground plane under wheelbase center",
        },
        "source_object": "Porsche911_24S_Exterior",
        "hulls": hulls,
        "boxes": [
            {
                "identifier": "sump_guard",
                "center": {"x": 0.0, "y": 0.20, "z": 1.15},
                "half_extents": {"x": 0.48, "y": 0.05, "z": 0.45},
            }
        ],
    }
    coll_path = ASSET_DIR / "porsche_911_24s_collision.json"
    coll_path.write_text(json.dumps(coll_doc, indent=2) + "\n", encoding="utf-8")

    manifest = {
        "contract_version": 1,
        "vehicle_id": "porsche_911_24s",
        "source": {
            "prm_dir": str(SRC_DIR),
            "texture": "car.bmp",
            "blender_version": "5.2.0 LTS",
            "runtime_visuals": {
                "source": str(SRC_DIR),
                "texture": tex_png.name,
                "finish": "high_res_pbr_no_psx",
                "fit": (
                    "Fitted to official Porsche 911 2.4 S (1972-1973 F-Series LWB) dimensions: "
                    "wheelbase 2.271 m, length 4.163 m, body width 1.610 m, height 1.320 m, "
                    "tracks 1.372 m / 1.354 m, 185/70 VR 15 tires (R=0.320 m, W=0.195 m)."
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
            "conversion": "Re-Volt PRM (+X right, +Y down, +Z fwd) -> Blender (+X, +Y_fwd, +Z_up) -> glTF +Y up",
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
    print(f"PORSCHE_911_24S_ASSETS_BUILT_OK: {ASSET_DIR}")


if __name__ == "__main__":
    main()
