"""Build VW Golf Mk1 chassis, wheels, collision hulls, and manifest with F-250 PSX finish.

Source model:
    D:/RallyManiacAssets/cars/1974-volkswagen-golf-mk1-lp/source/Volkswagen Golf Mk1 (LP).blend

Pipeline:
1. Open source .blend in Blender, reset armature pose & unparent all meshes cleanly.
2. Delete interior ('Interior', 'Steering Wheel', 'Trunk shelf'), armature, boneshapes,
   empties, cameras, and lights.
3. Rotate exterior and wheels +180 deg around Z so vehicle faces +Y in Blender (-Z in Godot).
4. Force 'Glass' material to opaque glossy black (Transmission=0, Alpha=1).
5. Join exterior body panels and all 6 windows into 'VWGolfMk1Exterior', fit X/Y/Z
   using shell width (ignoring side mirror overhang on Door FL) and piecewise linear mapping
   to exact VW Golf Mk1 dimensions (wheelbase 2.400 m, length 3.741 m, roof 1.425 m).
6. Bake a 1024x1024 Cycles CPU Emit atlas onto UV layer 'Atlas' (AO 0.29m/8 samples mixed
   0.41*AO + 0.59, directional light dot(N, (0.35, 0.31, 0.88)) mapped [-0.50, 0.90] ->
   [0.83, 1.00] on Paint / [0.94, 1.00] on remaining materials, margin=9, EXTEND).
7. Quantize & Bayer-dither the baked chassis atlas (dither=0.36) and Wheel_BaseColor.png
   (dither=0.32) to 512x512 RGB555 via ps1kit (system Python subprocess).
8. Replace all chassis materials with one unified material on 'Atlas' (TEXCOORD_0 only),
   normalize & center the 4 wheels to (W=0.195 m, D=0.610 m), export GLBs with Closest
   filtering, and patch glTF samplers to NEAREST (magFilter=9728, minFilter=9984).
9. Generate vw_golf_mk1_collision.json (front/cabin/rear convex hulls + sump_guard box)
   and manifest.json.
"""

from __future__ import annotations

import hashlib
import json
import math
import subprocess
import tempfile
from pathlib import Path
import struct

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector
from mathutils.geometry import convex_hull_2d


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = PROJECT_ROOT / "game" / "assets" / "rally" / "vw_golf_mk1"

SOURCE_ROOT = Path(r"D:\RallyManiacAssets\cars\1974-volkswagen-golf-mk1-lp")
SOURCE_BLEND = SOURCE_ROOT / "source" / "Volkswagen Golf Mk1 (LP).blend"
SOURCE_TEXTURES_DIR = SOURCE_ROOT / "textures"
PS1KIT_DIR = Path(r"D:\RallyManiacAssets\tools\ps1kit")

# Exact target VW Golf Mk1 dimensions (meters) matching manifest & physics profile.
TARGET_WHEELBASE_M = 2.400
TARGET_HALF_WHEELBASE_M = TARGET_WHEELBASE_M * 0.5
TARGET_FRONT_OVERHANG_M = 0.715
TARGET_REAR_OVERHANG_M = 0.626
TARGET_LENGTH_M = TARGET_WHEELBASE_M + TARGET_FRONT_OVERHANG_M + TARGET_REAR_OVERHANG_M  # 3.741
TARGET_FRONT_TRACK_M = 1.420
TARGET_REAR_TRACK_M = 1.410
TARGET_BODY_WIDTH_M = 1.630  # Main shell width without driver mirror (accommodates 1.42m + 0.195m tires)
TARGET_TIRE_RADIUS_M = 0.305
TARGET_TIRE_WIDTH_M = 0.195
TARGET_BOTTOM_CLEARANCE_M = 0.185
TARGET_ROOF_HEIGHT_M = 1.425

EXTERIOR_OBJECTS = (
    "Body",
    "Hood",
    "Door FL",
    "Door FR",
    "Door BL",
    "Door BR",
    "Trunk Lid",
    "Plates",
    "Windshield",
    "Back Window",
    "Window FL",
    "Window FR",
    "Window BL",
    "Window BR",
)

WHEEL_OBJECTS = {
    "front_left": "Wheel FL",
    "front_right": "Wheel FR",
    "rear_left": "Wheel BL",
    "rear_right": "Wheel BR",
}

HULL_ZONES = (
    ("front", 0.55, 10.0),
    ("cabin", -0.85, 0.70),
    ("rear", -10.0, -0.70),
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(65536):
            digest.update(chunk)
    return digest.hexdigest()


def to_godot_coords(vec: Vector | tuple[float, float, float]) -> list[float]:
    return [round(float(vec[0]), 6), round(float(vec[2]), 6), round(float(-vec[1]), 6)]


def piecewise_linear_map(value: float, src_pts: list[float], dst_pts: list[float]) -> float:
    if value <= src_pts[0]:
        span = src_pts[1] - src_pts[0]
        slope = (dst_pts[1] - dst_pts[0]) / span if abs(span) > 1e-8 else 1.0
        return dst_pts[0] + (value - src_pts[0]) * slope
    for idx in range(len(src_pts) - 1):
        if value <= src_pts[idx + 1]:
            span = src_pts[idx + 1] - src_pts[idx]
            t = (value - src_pts[idx]) / span if abs(span) > 1e-8 else 0.0
            return dst_pts[idx] + t * (dst_pts[idx + 1] - dst_pts[idx])
    span = src_pts[-1] - src_pts[-2]
    slope = (dst_pts[-1] - dst_pts[-2]) / span if abs(span) > 1e-8 else 1.0
    return dst_pts[-1] + (value - src_pts[-1]) * slope


def resolve_source_images() -> None:
    """Ensure all image datablocks referenced by the .blend point to real texture files."""
    if not SOURCE_TEXTURES_DIR.is_dir():
        return
    norm = lambda s: s.lower().replace(" ", "_")
    available_by_name = {norm(p.name): p for p in SOURCE_TEXTURES_DIR.iterdir() if p.is_file()}
    available_by_stem = {norm(p.stem): p for p in SOURCE_TEXTURES_DIR.iterdir() if p.is_file()}
    for img in bpy.data.images:
        if img.source != "FILE":
            continue
        raw_name = Path(bpy.path.abspath(img.filepath)).name or img.name
        key = norm(raw_name)
        candidate = available_by_name.get(key)
        if candidate is None:
            stem_name = key.split(".png")[0] + ".png" if ".png" in key else key
            candidate = available_by_name.get(stem_name) or available_by_stem.get(norm(Path(raw_name).stem))
        if candidate is not None:
            if img.packed_file is not None:
                img.unpack(method="REMOVE")
            img.filepath = str(candidate)
            img.reload()
            print(f"[IMAGE] Resolved '{img.name}' -> {candidate.name}")
        else:
            print(f"[IMAGE] Unresolved '{img.name}' (filepath={img.filepath!r}, packed={img.packed_file is not None})")


def clear_pose_and_unparent() -> None:
    """Reset any armature pose transforms, unparent target objects keeping world transforms, and purge clutter."""
    # Reset any Armature pose bones to rest before baking/unparenting
    for obj in bpy.data.objects:
        if obj.type == "ARMATURE" and obj.pose is not None:
            for pbone in obj.pose.bones:
                pbone.location = (0.0, 0.0, 0.0)
                pbone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
                pbone.rotation_euler = (0.0, 0.0, 0.0)
                pbone.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()

    # Clear animation/pose/steered rotations on empties if any (e.g., F_Wheel.L / F_Wheel.R)
    for empty_name in ("F_Wheel.L", "F_Wheel.R", "B_Wheel.L", "B_Wheel.R"):
        empty = bpy.data.objects.get(empty_name)
        if empty is not None:
            empty.rotation_euler = (0.0, 0.0, 0.0)
            empty.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
    bpy.context.view_layer.update()

    keep_names = set(EXTERIOR_OBJECTS) | set(WHEEL_OBJECTS.values())
    for name in sorted(keep_names):
        obj = bpy.data.objects.get(name)
        if obj is None:
            raise RuntimeError(f"Expected object '{name}' not found in {SOURCE_BLEND}")
        world_mat = obj.matrix_world.copy()
        obj.modifiers.clear()
        obj.constraints.clear()
        obj.parent = None
        obj.matrix_world = world_mat

    # Delete everything except exterior and wheel meshes
    to_delete = [obj for obj in list(bpy.data.objects) if obj.name not in keep_names]
    for obj in to_delete:
        bpy.data.objects.remove(obj, do_unlink=True)

    bpy.context.view_layer.update()
    print(f"[SCENE] Retained {len(bpy.data.objects)} objects; purged {len(to_delete)} interior/rig/helper objects.")


def rotate_all_180_z_and_apply() -> None:
    """Make shared meshes single-user, rotate +180 deg around Z (+Y forward), and apply transforms."""
    rot_z = Matrix.Rotation(math.pi, 4, "Z")
    for obj in bpy.data.objects:
        if obj.type == "MESH" and obj.data.users > 1:
            obj.data = obj.data.copy()
        obj.matrix_world = rot_z @ obj.matrix_world
    bpy.context.view_layer.update()

    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = bpy.data.objects[EXTERIOR_OBJECTS[0]]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.select_all(action="DESELECT")


def configure_opaque_black_glass() -> None:
    """Turn Glass material opaque glossy black so zero interior visibility exists."""
    glass = bpy.data.materials.get("Glass")
    if glass is None:
        raise RuntimeError("Material 'Glass' not found in source blend")
    glass.use_nodes = True
    nt = glass.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        nt.nodes.clear()
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    for inp_name in ("Base Color", "Roughness", "Transmission Weight", "Transmission", "Alpha", "Emission Strength"):
        inp = bsdf.inputs.get(inp_name)
        if inp is not None:
            for link in list(inp.links):
                nt.links.remove(link)

    bsdf.inputs["Base Color"].default_value = (0.0025, 0.0028, 0.0032, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.06
    if "Metallic" in bsdf.inputs:
        bsdf.inputs["Metallic"].default_value = 0.0
    if "Transmission Weight" in bsdf.inputs:
        bsdf.inputs["Transmission Weight"].default_value = 0.0
    elif "Transmission" in bsdf.inputs:
        bsdf.inputs["Transmission"].default_value = 0.0
    if "Alpha" in bsdf.inputs:
        bsdf.inputs["Alpha"].default_value = 1.0
    if "Emission Strength" in bsdf.inputs:
        bsdf.inputs["Emission Strength"].default_value = 0.0
    print("[MATERIAL] Configured 'Glass' as opaque glossy black.")


def standardize_uv_name_before_join(obj: bpy.types.Object) -> None:
    mesh = obj.data
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="Original")
    else:
        for idx, layer in enumerate(list(mesh.uv_layers)):
            if idx == 0:
                layer.name = "Original"
            else:
                mesh.uv_layers.remove(layer)
    mesh.uv_layers["Original"].active = True
    mesh.uv_layers["Original"].active_render = True


def compute_object_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


def measure_wheel_centers_after_rotation() -> tuple[float, float, float]:
    """Return (front_y, rear_y, wheel_bottom_z) from the rotated wheel meshes."""
    front_ys = []
    rear_ys = []
    bottom_zs = []
    for key, obj_name in WHEEL_OBJECTS.items():
        wobj = bpy.data.objects[obj_name]
        wmin, wmax = compute_object_bounds(wobj)
        cy = 0.5 * (wmin.y + wmax.y)
        bottom_zs.append(wmin.z)
        if "front" in key:
            front_ys.append(cy)
        else:
            rear_ys.append(cy)
    return sum(front_ys) / len(front_ys), sum(rear_ys) / len(rear_ys), min(bottom_zs)


def join_and_fit_exterior(front_axle_y: float, rear_axle_y: float, wheel_bottom_z: float) -> bpy.types.Object:
    """Join exterior panels and windows into 'VWGolfMk1Exterior' and fit exact RallyGolf dimensions."""
    body_obj = bpy.data.objects["Body"]
    body_min, body_max = compute_object_bounds(body_obj)
    # Center body shell X around 0 (using main shell so Door FL side mirror does not skew X)
    shell_center_x = 0.5 * (body_min.x + body_max.x)
    shell_width_x = body_max.x - body_min.x

    for name in EXTERIOR_OBJECTS:
        obj = bpy.data.objects[name]
        standardize_uv_name_before_join(obj)

    bpy.ops.object.select_all(action="DESELECT")
    for name in EXTERIOR_OBJECTS:
        bpy.data.objects[name].select_set(True)
    bpy.context.view_layer.objects.active = body_obj
    bpy.ops.object.join()

    exterior = bpy.context.view_layer.objects.active
    exterior.name = "VWGolfMk1Exterior"
    exterior.data.name = "VWGolfMk1ExteriorMesh"

    # Measure raw joined Y/Z bounds (shifted so wheel bottom Z == 0.0 before piecewise Z mapping)
    raw_min, raw_max = compute_object_bounds(exterior)
    print(
        f"[EXTERIOR RAW] X=[{raw_min.x:.4f},{raw_max.x:.4f}] (Body shell W={shell_width_x:.4f}) "
        f"Y=[{raw_min.y:.4f},{raw_max.y:.4f}] (front_axle={front_axle_y:.4f}, rear_axle={rear_axle_y:.4f}) "
        f"Z=[{raw_min.z:.4f},{raw_max.z:.4f}] (wheel_bottom={wheel_bottom_z:.4f})"
    )

    scale_x = TARGET_BODY_WIDTH_M / shell_width_x
    src_y = [raw_min.y, rear_axle_y, front_axle_y, raw_max.y]
    dst_y = [
        -(TARGET_HALF_WHEELBASE_M + TARGET_REAR_OVERHANG_M),  # -1.826
        -TARGET_HALF_WHEELBASE_M,                              # -1.200
        +TARGET_HALF_WHEELBASE_M,                              # +1.200
        +(TARGET_HALF_WHEELBASE_M + TARGET_FRONT_OVERHANG_M), # +1.915
    ]

    z_offset = -wheel_bottom_z
    src_z_min = raw_min.z + z_offset
    src_z_axle = 0.5 * (compute_object_bounds(bpy.data.objects[WHEEL_OBJECTS["front_left"]])[0].z +
                        compute_object_bounds(bpy.data.objects[WHEEL_OBJECTS["front_left"]])[1].z) + z_offset
    src_z_max = raw_max.z + z_offset
    src_z = [src_z_min, src_z_axle, src_z_max]
    dst_z = [TARGET_BOTTOM_CLEARANCE_M, TARGET_TIRE_RADIUS_M, TARGET_ROOF_HEIGHT_M]

    for vert in exterior.data.vertices:
        vert.co.x = (vert.co.x - shell_center_x) * scale_x
        vert.co.y = piecewise_linear_map(vert.co.y, src_y, dst_y)
        vert.co.z = piecewise_linear_map(vert.co.z + z_offset, src_z, dst_z)

    exterior.data.update()
    fit_min, fit_max = compute_object_bounds(exterior)
    print(
        f"[EXTERIOR FIT] X=[{fit_min.x:.4f},{fit_max.x:.4f}] "
        f"Y=[{fit_min.y:.4f},{fit_max.y:.4f}] (len={fit_max.y - fit_min.y:.4f}) "
        f"Z=[{fit_min.z:.4f},{fit_max.z:.4f}]"
    )
    return exterior


def create_atlas_uv_and_bake(exterior: bpy.types.Object, raw_bake_path: Path) -> None:
    """Create 'Atlas' UV via Smart UV Project and bake F-250 Cycles Emit + AO + directional lighting."""
    mesh = exterior.data
    mesh.uv_layers.new(name="Atlas")
    mesh.uv_layers.active = mesh.uv_layers["Atlas"]
    mesh.uv_layers.active_index = list(mesh.uv_layers).index(mesh.uv_layers["Atlas"])

    # Smart UV Project on the Atlas UV layer
    bpy.ops.object.select_all(action="DESELECT")
    exterior.select_set(True)
    bpy.context.view_layer.objects.active = exterior
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.05, island_margin=0.018)
    bpy.ops.object.mode_set(mode="OBJECT")

    mesh.uv_layers.active = mesh.uv_layers["Atlas"]
    mesh.uv_layers["Atlas"].active = True
    mesh.uv_layers["Atlas"].active_render = True

    bake_img = bpy.data.images.new("Golf_Atlas_Bake", width=1024, height=1024, alpha=True)
    bake_img.colorspace_settings.name = "sRGB"

    # Build Cycles Emit shader graph on each material slot per F250_ACABADO_PSX.md / bake_stratos_photo.py
    light_dir = Vector((0.35, 0.31, 0.88)).normalized()

    for slot in exterior.material_slots:
        mat = slot.material
        if mat is None:
            continue
        mat.use_nodes = True
        nt = mat.node_tree

        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None)
        if out is None:
            out = nt.nodes.new("ShaderNodeOutputMaterial")

        # Force existing Image Texture nodes to sample 'Original' UVs
        uv_orig_node = nt.nodes.new("ShaderNodeUVMap")
        uv_orig_node.uv_map = "Original"
        for node in nt.nodes:
            if node.type == "TEX_IMAGE":
                vec_in = node.inputs.get("Vector")
                if vec_in is not None and not vec_in.is_linked:
                    nt.links.new(uv_orig_node.outputs["UV"], vec_in)
                elif vec_in is not None and vec_in.is_linked:
                    src_node = vec_in.links[0].from_node
                    if src_node.type in ("TEX_COORD", "UVMAP"):
                        nt.links.new(uv_orig_node.outputs["UV"], vec_in)

        # Resolve base color socket or constant
        base_color_socket = None
        base_color_default = (0.5, 0.5, 0.5, 1.0)
        if bsdf is not None:
            bc_in = bsdf.inputs.get("Base Color")
            if bc_in is not None:
                if bc_in.is_linked:
                    base_color_socket = bc_in.links[0].from_socket
                else:
                    base_color_default = tuple(bc_in.default_value)

        # Ambient Occlusion (0.29m, 8 samples) -> 0.41 * AO + 0.59
        ao_node = nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao_node.samples = 8
        ao_node.inputs["Distance"].default_value = 0.29

        ao_mix = nt.nodes.new("ShaderNodeMath")
        ao_mix.operation = "MULTIPLY_ADD"
        nt.links.new(ao_node.outputs["AO"], ao_mix.inputs[0])
        ao_mix.inputs[1].default_value = 0.41
        ao_mix.inputs[2].default_value = 0.59

        # Directional dot(N, (0.35, 0.31, 0.88)) mapped [-0.50, 0.90] -> [0.83, 1.00] on Paint / [0.94, 1.00] on rest
        geom = nt.nodes.new("ShaderNodeNewGeometry")
        dot_node = nt.nodes.new("ShaderNodeVectorMath")
        dot_node.operation = "DOT_PRODUCT"
        nt.links.new(geom.outputs["Normal"], dot_node.inputs[0])
        dot_node.inputs[1].default_value = (light_dir.x, light_dir.y, light_dir.z)

        dir_min = 0.83 if mat.name == "Paint" else 0.94
        map_range = nt.nodes.new("ShaderNodeMapRange")
        map_range.clamp = True
        map_range.inputs["From Min"].default_value = -0.50
        map_range.inputs["From Max"].default_value = 0.90
        map_range.inputs["To Min"].default_value = dir_min
        map_range.inputs["To Max"].default_value = 1.00
        nt.links.new(dot_node.outputs["Value"], map_range.inputs["Value"])

        shade_mul = nt.nodes.new("ShaderNodeMath")
        shade_mul.operation = "MULTIPLY"
        nt.links.new(ao_mix.outputs["Value"], shade_mul.inputs[0])
        nt.links.new(map_range.outputs["Result"], shade_mul.inputs[1])

        tint_mul = nt.nodes.new("ShaderNodeMix")
        tint_mul.data_type = "RGBA"
        tint_mul.blend_type = "MULTIPLY"
        tint_mul.inputs["Factor"].default_value = 1.0
        if base_color_socket is not None:
            nt.links.new(base_color_socket, tint_mul.inputs["A"])
        else:
            tint_mul.inputs["A"].default_value = base_color_default
        # Combine scalar shade factor into RGB via Combine Color
        comb = nt.nodes.new("ShaderNodeCombineColor")
        nt.links.new(shade_mul.outputs["Value"], comb.inputs["Red"])
        nt.links.new(shade_mul.outputs["Value"], comb.inputs["Green"])
        nt.links.new(shade_mul.outputs["Value"], comb.inputs["Blue"])
        nt.links.new(comb.outputs["Color"], tint_mul.inputs["B"])

        emit_node = nt.nodes.new("ShaderNodeEmission")
        emit_node.inputs["Strength"].default_value = 1.0
        nt.links.new(tint_mul.outputs["Result"], emit_node.inputs["Color"])
        nt.links.new(emit_node.outputs["Emission"], out.inputs["Surface"])

        # Target Bake Image node (unlinked, active & selected for Cycles bake)
        for n in nt.nodes:
            n.select = False
        target_tex = nt.nodes.new("ShaderNodeTexImage")
        target_tex.image = bake_img
        target_tex.select = True
        nt.nodes.active = target_tex

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.bake_type = "EMIT"
    scene.render.bake.use_pass_direct = False
    scene.render.bake.use_pass_indirect = False
    scene.render.bake.margin = 9
    scene.render.bake.margin_type = "EXTEND"
    scene.render.bake.use_clear = True

    mesh.uv_layers.active = mesh.uv_layers["Atlas"]
    mesh.uv_layers["Atlas"].active = True
    bpy.ops.object.select_all(action="DESELECT")
    exterior.select_set(True)
    bpy.context.view_layer.objects.active = exterior

    print("[BAKE] Running Cycles CPU EMIT bake (1024x1024, 24 samples, AO + directional)...")
    bpy.ops.object.bake(type="EMIT")

    bake_img.filepath_raw = str(raw_bake_path)
    bake_img.file_format = "PNG"
    bake_img.save()
    print(f"[BAKE] Saved raw 1024x1024 bake to {raw_bake_path}")


def run_ps1kit_quantize(src_path: Path, dst_path: Path, size: tuple[int, int], dither_strength: float) -> None:
    """Invoke system Python to downsample & Bayer-dither a texture to RGB555 via ps1kit."""
    script = (
        "import sys; "
        f"sys.path.insert(0, {repr(str(PS1KIT_DIR))}); "
        "from PIL import Image; "
        "from ps1kit import process_texture; "
        f"img = Image.open({repr(str(src_path))}); "
        f"out, _ = process_texture(img, size={repr(size)}, colors=None, dither_strength={dither_strength}); "
        f"out.save({repr(str(dst_path))}, format='PNG'); "
        "print('[PS1KIT]', out.size, out.mode)"
    )
    subprocess.run(["python", "-c", script], check=True)


def make_psx_material(name: str, image_path: Path, roughness: float, coat: float = 0.0) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex = nt.nodes.new("ShaderNodeTexImage")

    img = bpy.data.images.load(str(image_path), check_existing=False)
    img.colorspace_settings.name = "sRGB"
    tex.image = img
    tex.interpolation = "Closest"

    bsdf.inputs["Roughness"].default_value = roughness
    if "Metallic" in bsdf.inputs:
        bsdf.inputs["Metallic"].default_value = 0.0
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = coat
    elif "Clearcoat" in bsdf.inputs:
        bsdf.inputs["Clearcoat"].default_value = coat

    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def apply_unified_chassis_material_and_uv(exterior: bpy.types.Object, psx_atlas_path: Path) -> None:
    mesh = exterior.data
    orig_uv = mesh.uv_layers.get("Original")
    if orig_uv is not None:
        mesh.uv_layers.remove(orig_uv)
    atlas_uv = mesh.uv_layers["Atlas"]
    atlas_uv.active = True
    atlas_uv.active_render = True

    psx_mat = make_psx_material("VWGolfMk1PSX", psx_atlas_path, roughness=0.64, coat=0.08)
    mesh.materials.clear()
    mesh.materials.append(psx_mat)
    for poly in mesh.polygons:
        poly.material_index = 0
    mesh.update()


def prepare_and_export_wheels(wheel_psx_path: Path) -> dict[str, Path]:
    """Center, normalize, apply PSX material, and export each wheel GLB."""
    wheel_mat = make_psx_material("VWGolfMk1WheelPSX", wheel_psx_path, roughness=0.72, coat=0.0)
    exported: dict[str, Path] = {}
    target_d = TARGET_TIRE_RADIUS_M * 2.0

    for key, obj_name in WHEEL_OBJECTS.items():
        wobj = bpy.data.objects[obj_name]
        wmin, wmax = compute_object_bounds(wobj)
        center = 0.5 * (wmin + wmax)
        cur_w = max(wmax.x - wmin.x, 1e-5)
        cur_dy = max(wmax.y - wmin.y, 1e-5)
        cur_dz = max(wmax.z - wmin.z, 1e-5)

        sx = TARGET_TIRE_WIDTH_M / cur_w
        sy = target_d / cur_dy
        sz = target_d / cur_dz
        for v in wobj.data.vertices:
            v.co.x = (v.co.x - center.x) * sx
            v.co.y = (v.co.y - center.y) * sy
            v.co.z = (v.co.z - center.z) * sz

        wobj.data.materials.clear()
        wobj.data.materials.append(wheel_mat)
        for poly in wobj.data.polygons:
            poly.material_index = 0
        wobj.data.update()

        out_path = OUTPUT_DIR / f"vw_golf_mk1_wheel_{key}.glb"
        export_single_glb(wobj, out_path)
        patch_glb_nearest_samplers(out_path)
        exported[key] = out_path
        wmin2, wmax2 = compute_object_bounds(wobj)
        print(f"[WHEEL {key}] bounds X=[{wmin2.x:.4f},{wmax2.x:.4f}] Y=[{wmin2.y:.4f},{wmax2.y:.4f}] Z=[{wmin2.z:.4f},{wmax2.z:.4f}] -> {out_path.name}")
    return exported


def export_single_glb(obj: bpy.types.Object, out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_texcoords=True,
        export_normals=True,
        export_animations=False,
    )


def patch_glb_nearest_samplers(glb_path: Path) -> None:
    """Force magFilter=9728 (NEAREST) and minFilter=9984 (NEAREST_MIPMAP_NEAREST) in glTF samplers."""
    raw = glb_path.read_bytes()
    magic, version, _ = struct.unpack_from("<4sII", raw, 0)
    if magic != b"glTF" or version != 2:
        raise RuntimeError(f"Unexpected GLB header in {glb_path}")
    json_len, json_type = struct.unpack_from("<II", raw, 12)
    if json_type != 0x4E4F534A:  # 'JSON'
        raise RuntimeError(f"Expected JSON chunk first in {glb_path}")
    model = json.loads(raw[20:20 + json_len])
    bin_offset = 20 + json_len
    bin_chunk = raw[bin_offset:]

    samplers = model.setdefault("samplers", [])
    if not samplers:
        samplers.append({})
    for sampler in samplers:
        sampler["magFilter"] = 9728
        sampler["minFilter"] = 9984
    for tex in model.get("textures", []):
        if "sampler" not in tex:
            tex["sampler"] = 0

    json_bytes = json.dumps(model, separators=(",", ":")).encode("utf-8")
    json_pad = (-len(json_bytes)) % 4
    json_bytes += b" " * json_pad
    json_hdr = struct.pack("<I4s", len(json_bytes), b"JSON")
    total_len = 12 + len(json_hdr) + len(json_bytes) + len(bin_chunk)
    new_glb = struct.pack("<4sII", b"glTF", 2, total_len) + json_hdr + json_bytes + bin_chunk
    glb_path.write_bytes(new_glb)


def extract_zone_convex_hull_godot(obj: bpy.types.Object, y_min: float, y_max: float) -> list[dict[str, float]]:
    """Build simplified convex hull points in Godot coordinates for the requested Blender Y zone."""
    bm = bmesh.new()
    for v in obj.data.vertices:
        if y_min <= v.co.y <= y_max:
            bm.verts.new((v.co.x, v.co.y, max(0.20, v.co.z)))
    bm.verts.ensure_lookup_table()
    if len(bm.verts) < 8:
        bm.free()
        return []
    result = bmesh.ops.convex_hull(bm, input=list(bm.verts))
    hull_verts = [e for e in result["geom"] if isinstance(e, bmesh.types.BMVert)]
    points = [
        {"x": round(float(v.co.x), 6), "y": round(float(v.co.z), 6), "z": round(float(-v.co.y), 6)}
        for v in hull_verts
    ]
    bm.free()

    # Thin slightly if point count is excessive while preserving extreme silhouette vertices
    if len(points) > 120:
        # Keep convex silhouette in XY/YZ/XZ plus uniform stride
        keep = set()
        step = max(1, len(points) // 90)
        for i in range(0, len(points), step):
            keep.add(i)
        # Ensure extreme corners are always retained
        for axis in ("x", "y", "z"):
            keep.add(min(range(len(points)), key=lambda idx: points[idx][axis]))
            keep.add(max(range(len(points)), key=lambda idx: points[idx][axis]))
        xy = [Vector((p["x"], p["z"])) for p in points]
        for idx in convex_hull_2d(xy):
            keep.add(idx)
        points = [points[i] for i in sorted(keep)]
    return points


def build_collision_and_manifest(
    exterior: bpy.types.Object,
    chassis_glb: Path,
    wheel_glbs: dict[str, Path],
) -> None:
    ext_min, ext_max = compute_object_bounds(exterior)
    hulls = []
    for identifier, ymin, ymax in HULL_ZONES:
        pts = extract_zone_convex_hull_godot(exterior, ymin, ymax)
        hulls.append({"identifier": identifier, "points": pts, "point_count": len(pts)})

    collision_doc = {
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
                "center": {"x": 0.0, "y": 0.2, "z": -0.95},
                "half_extents": {"x": 0.5, "y": 0.05, "z": 0.45},
            }
        ],
    }
    collision_path = OUTPUT_DIR / "vw_golf_mk1_collision.json"
    collision_path.write_text(json.dumps(collision_doc, indent=2) + "\n", encoding="utf-8")

    half_front_track = TARGET_FRONT_TRACK_M * 0.5
    half_rear_track = TARGET_REAR_TRACK_M * 0.5
    pivots_bl = {
        "front_left": [-half_front_track, TARGET_HALF_WHEELBASE_M, TARGET_TIRE_RADIUS_M],
        "front_right": [half_front_track, TARGET_HALF_WHEELBASE_M, TARGET_TIRE_RADIUS_M],
        "rear_left": [-half_rear_track, -TARGET_HALF_WHEELBASE_M, TARGET_TIRE_RADIUS_M],
        "rear_right": [half_rear_track, -TARGET_HALF_WHEELBASE_M, TARGET_TIRE_RADIUS_M],
    }

    wheels_manifest = {}
    wheel_pivots = {}
    for key, path in wheel_glbs.items():
        p_bl = pivots_bl[key]
        p_gd = to_godot_coords(p_bl)
        wheels_manifest[key] = {
            "path": path.name,
            "sha256": sha256_file(path),
            "size_bytes": path.stat().st_size,
        }
        wheel_pivots[key] = {
            "blender_object": WHEEL_OBJECTS[key],
            "center_metres": {
                "x": p_gd[0],
                "y": p_gd[1],
                "z": p_gd[2],
            },
            "radius_metres": TARGET_TIRE_RADIUS_M,
            "width_metres": TARGET_TIRE_WIDTH_M,
        }

    min_bl = [round(float(ext_min.x), 6), round(float(ext_min.y), 6), round(float(ext_min.z), 6)]
    max_bl = [round(float(ext_max.x), 6), round(float(ext_max.y), 6), round(float(ext_max.z), 6)]
    min_gd = [round(float(ext_min.x), 6), round(float(ext_min.z), 6), round(float(-ext_max.y), 6)]
    max_gd = [round(float(ext_max.x), 6), round(float(ext_max.z), 6), round(float(-ext_min.y), 6)]

    manifest = {
        "contract_version": 1,
        "vehicle_id": "vw_golf_mk1",
        "display_name": "Volkswagen Golf Mk1 (1974)",
        "source_blend": str(SOURCE_BLEND),
        "texture_finish": "original_livery_baked_psx_rgb555",
        "coordinate_system": {
            "engine": "Godot",
            "forward": "-Z",
            "right": "+X",
            "up": "+Y",
            "origin": "ground plane under wheelbase center",
        },
        "geometry": {
            "wheelbase": TARGET_WHEELBASE_M,
            "front_track": TARGET_FRONT_TRACK_M,
            "rear_track": TARGET_REAR_TRACK_M,
            "front_axle_z": -TARGET_HALF_WHEELBASE_M,
            "rear_axle_z": TARGET_HALF_WHEELBASE_M,
        },
        "dimensions": {
            "wheelbase": TARGET_WHEELBASE_M,
            "front_track": TARGET_FRONT_TRACK_M,
            "rear_track": TARGET_REAR_TRACK_M,
            "length": TARGET_LENGTH_M,
            "front_overhang": TARGET_FRONT_OVERHANG_M,
            "rear_overhang": TARGET_REAR_OVERHANG_M,
            "tire_radius": TARGET_TIRE_RADIUS_M,
            "tire_width": TARGET_TIRE_WIDTH_M,
            "bottom_clearance": TARGET_BOTTOM_CLEARANCE_M,
            "roof_height": TARGET_ROOF_HEIGHT_M,
            "width_blender": round(float(ext_max.x - ext_min.x), 6),
            "min_blender": min_bl,
            "max_blender": max_bl,
        },
        "chassis": {
            "path": chassis_glb.name,
            "sha256": sha256_file(chassis_glb),
            "size_bytes": chassis_glb.stat().st_size,
            "exported_nodes": ["VWGolfMk1Exterior"],
            "bounds_blender": {"min": min_bl, "max": max_bl},
        },
        "wheels": wheels_manifest,
        "collision": {
            "path": collision_path.name,
            "sha256": sha256_file(collision_path),
        },
        "wheel_pivots": wheel_pivots,
        "bounds_world_metres": {
            "min_blender": min_bl,
            "max_blender": max_bl,
            "min_godot": min_gd,
            "max_godot": max_gd,
        },
    }
    manifest_path = OUTPUT_DIR / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"[DONE] Wrote {collision_path.name} and {manifest_path.name}")


def main() -> None:
    if not SOURCE_BLEND.is_file():
        raise FileNotFoundError(f"Source blend missing: {SOURCE_BLEND}")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.open_mainfile(filepath=str(SOURCE_BLEND))
    resolve_source_images()
    clear_pose_and_unparent()
    rotate_all_180_z_and_apply()
    configure_opaque_black_glass()

    front_y, rear_y, wheel_bottom_z = measure_wheel_centers_after_rotation()
    exterior = join_and_fit_exterior(front_y, rear_y, wheel_bottom_z)

    with tempfile.TemporaryDirectory(prefix="vw_golf_psx_") as tmp:
        tmp_dir = Path(tmp)
        raw_bake = tmp_dir / "chassis_bake_1024.png"
        chassis_psx = tmp_dir / "chassis_psx_512.png"
        wheel_psx = tmp_dir / "wheel_psx_512.png"

        create_atlas_uv_and_bake(exterior, raw_bake)
        run_ps1kit_quantize(raw_bake, chassis_psx, size=(512, 512), dither_strength=0.36)
        run_ps1kit_quantize(SOURCE_TEXTURES_DIR / "Wheel_BaseColor.png", wheel_psx, size=(512, 512), dither_strength=0.32)

        apply_unified_chassis_material_and_uv(exterior, chassis_psx)

        chassis_glb = OUTPUT_DIR / "vw_golf_mk1_chassis.glb"
        export_single_glb(exterior, chassis_glb)
        patch_glb_nearest_samplers(chassis_glb)
        print(f"[CHASSIS] Exported & patched {chassis_glb.name}")

        wheel_glbs = prepare_and_export_wheels(wheel_psx)

    build_collision_and_manifest(exterior, chassis_glb, wheel_glbs)


if __name__ == "__main__":
    main()
