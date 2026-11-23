"""Build Ford Mustang 1967 (ford_mustang_1967_289_2v) from PalominoSpecial67.blend with F-250 PSX finish.

Source model:
    D:/RallyManiacAssets/cars/palomino-special-67-low-poly-model/source/PalominoSpecial67.blend

Pipeline:
1. Open PalominoSpecial67.blend, resolve textures from ../textures, delete Interior and Steering_Wheel.
2. Rotate +90 deg around Z (+X front -> +Y front in Blender / -Z forward in Godot) and apply transforms.
3. Measure native wheel pivots/radii/widths from PalominoSpecial67_WheelStock_*, center X=0 and
   wheelbase Y=0, and seat tires on Z=0.
4. Separate cabin windows into opaque glossy black, Headlights_Glass into crystal light blue,
   Taillights_Glass into ruby taillight red, preserve Bodymat red Mix(MULTIPLY) with Generic_bodymat_dif,
   blend Numberplates_Misk_U onto bright plate backing, and isolate Badges into Palomino67Badges
   (ALPHA_SCISSOR binary cutout hidden during exterior Cycles AO bake).
5. Bake 1024x1024 chassis atlas + 512x512 wheel atlases (F-250 Cycles CPU Emit + AO + directional),
   quantize via ps1kit (512x512 RGB555, dither=0.36 chassis / 0.32 wheels & badges),
   export ford_mustang_1967_289_2v_*.glb with glTF NEAREST samplers (9728/9984),
   regenerate collision JSON, and sync manifest.json, chassis.json, tires.json, HISTORICAL_PROVENANCE.json.
"""

from __future__ import annotations

import hashlib
import json
import math
import struct
import subprocess
import tempfile
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.geometry import convex_hull_2d


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = PROJECT_ROOT / "game" / "assets" / "rally" / "ford_mustang_1967_289_2v"
PROFILE_DIR = PROJECT_ROOT / "game" / "data" / "vehicles" / "ford-mustang-1967-289-2v"

SOURCE_ROOT = Path(r"D:\RallyManiacAssets\cars\palomino-special-67-low-poly-model")
SOURCE_BLEND = SOURCE_ROOT / "source" / "PalominoSpecial67.blend"
SOURCE_TEXTURES_DIR = SOURCE_ROOT / "textures"
PS1KIT_DIR = Path(r"D:\RallyManiacAssets\tools\ps1kit")

PURGE_OBJECTS = (
    "PalominoSpecial67_Interior",
    "PalominoSpecial67_Steering_Wheel",
)

CABIN_GLASS_OBJECTS = (
    "PalominoSpecial67_Bodyglass",
    "PalominoSpecial67_Glass_Driver",
    "PalominoSpecial67_Glass_Passenger",
    "PalominoSpecial67_Glass_Rear",
    "PalominoSpecial67_Windshield",
)

BADGE_OBJECTS = (
    "PalominoSpecial67_Body_Badges",
    "PalominoSpecial67_Trunkdoor_Badges",
)

WHEEL_OBJECTS = {
    "front_left": "PalominoSpecial67_WheelStock_FL",
    "front_right": "PalominoSpecial67_WheelStock_FR",
    "rear_left": "PalominoSpecial67_WheelStock_RL",
    "rear_right": "PalominoSpecial67_WheelStock_RR",
}

HULL_ZONES = (
    ("front", 0.55, 10.0),
    ("cabin", -0.95, 0.70),
    ("rear", -10.0, -0.80),
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(65536):
            digest.update(chunk)
    return digest.hexdigest()


def to_godot_coords(vec: Vector | tuple[float, float, float]) -> list[float]:
    return [round(float(vec[0]), 6), round(float(vec[2]), 6), round(float(-vec[1]), 6)]


def compute_object_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


def resolve_textures() -> None:
    if not SOURCE_TEXTURES_DIR.is_dir():
        return
    by_name = {p.name.lower(): p for p in SOURCE_TEXTURES_DIR.iterdir() if p.is_file()}
    for img in bpy.data.images:
        if img.source != "FILE":
            continue
        raw_name = Path(bpy.path.abspath(img.filepath)).name or img.name
        candidate = by_name.get(raw_name.lower())
        if candidate is not None:
            if img.packed_file is not None:
                img.unpack(method="REMOVE")
            img.filepath = str(candidate)
            img.reload()


def cleanup_and_rotate_90_z() -> None:
    """Purge interior/steering wheel, rotate +90 deg around Z (+X front -> +Y front), apply transforms."""
    for pname in PURGE_OBJECTS:
        obj = bpy.data.objects.get(pname)
        if obj is not None:
            bpy.data.objects.remove(obj, do_unlink=True)

    for obj in list(bpy.data.objects):
        if obj.type != "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)

    rot_z = Matrix.Rotation(math.pi * 0.5, 4, "Z")
    for obj in bpy.data.objects:
        if obj.data.users > 1:
            obj.data = obj.data.copy()
        obj.parent = None
        obj.matrix_world = rot_z @ obj.matrix_world
    bpy.context.view_layer.update()

    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = bpy.data.objects["PalominoSpecial67_Body"]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.select_all(action="DESELECT")

    for obj in bpy.data.objects:
        mesh = obj.data
        if mesh.uv_layers:
            for idx, layer in enumerate(list(mesh.uv_layers)):
                if idx == 0:
                    layer.name = "Original"
                else:
                    mesh.uv_layers.remove(layer)
        else:
            mesh.uv_layers.new(name="Original")
        mesh.uv_layers["Original"].active = True
        mesh.uv_layers["Original"].active_render = True


def align_and_measure_wheels() -> dict[str, float]:
    """Center X=0 and wheelbase Y=0 and ground tires at Z=0 preserving exact native model dimensions."""
    centers = {}
    widths = []
    radii = []
    bottoms = []
    for key, obj_name in WHEEL_OBJECTS.items():
        wobj = bpy.data.objects[obj_name]
        wmin, wmax = compute_object_bounds(wobj)
        centers[key] = 0.5 * (wmin + wmax)
        widths.append(wmax.x - wmin.x)
        radii.append(0.25 * ((wmax.y - wmin.y) + (wmax.z - wmin.z)))
        bottoms.append(wmin.z)

    x_shift = -0.25 * sum(c.x for c in centers.values())
    front_y = 0.5 * (centers["front_left"].y + centers["front_right"].y)
    rear_y = 0.5 * (centers["rear_left"].y + centers["rear_right"].y)
    y_shift = -0.5 * (front_y + rear_y)
    z_shift = -min(bottoms)

    wheelbase = front_y - rear_y
    front_track = abs(centers["front_right"].x - centers["front_left"].x)
    rear_track = abs(centers["rear_right"].x - centers["rear_left"].x)
    tire_width = sum(widths) / len(widths)
    tire_radius = sum(radii) / len(radii)

    shift = Vector((x_shift, y_shift, z_shift))
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        for v in obj.data.vertices:
            v.co += shift
        obj.data.update()

    print(
        f"[NATIVE BLEND] wheelbase={wheelbase:.5f} m, tracks=({front_track:.5f}, {rear_track:.5f}) m, "
        f"tire R={tire_radius:.5f} m, W={tire_width:.5f} m"
    )
    return {
        "wheelbase": round(float(wheelbase), 5),
        "front_track": round(float(front_track), 5),
        "rear_track": round(float(rear_track), 5),
        "tire_radius": round(float(tire_radius), 5),
        "tire_width": round(float(tire_width), 5),
    }


def reassign_glass_and_light_materials() -> None:
    """Split shared UCB_Lights_and_Glass_Transperent into cabin black glass, crystal headlights, and red taillights."""
    mat_cabin = bpy.data.materials.new("CabinGlass_OpaqueBlack")
    mat_head = bpy.data.materials.new("HeadlightCrystal")
    mat_tail = bpy.data.materials.new("TaillightRuby")

    for name in CABIN_GLASS_OBJECTS:
        obj = bpy.data.objects[name]
        obj.data.materials.clear()
        obj.data.materials.append(mat_cabin)
        for p in obj.data.polygons:
            p.material_index = 0

    head_glass = bpy.data.objects["PalominoSpecial67_Headlights_Glass"]
    head_glass.data.materials.clear()
    head_glass.data.materials.append(mat_head)
    for p in head_glass.data.polygons:
        p.material_index = 0

    tail_glass = bpy.data.objects["PalominoSpecial67_Taillights_Glass"]
    tail_glass.data.materials.clear()
    tail_glass.data.materials.append(mat_tail)
    for p in tail_glass.data.polygons:
        p.material_index = 0


def join_exterior_and_badges() -> tuple[bpy.types.Object, bpy.types.Object]:
    wheel_set = set(WHEEL_OBJECTS.values())
    badge_set = set(BADGE_OBJECTS)

    # Join Badges
    bpy.ops.object.select_all(action="DESELECT")
    for bname in BADGE_OBJECTS:
        bpy.data.objects[bname].select_set(True)
    bpy.context.view_layer.objects.active = bpy.data.objects[BADGE_OBJECTS[0]]
    bpy.ops.object.join()
    badges_obj = bpy.context.view_layer.objects.active
    badges_obj.name = "Palomino67Badges"
    badges_obj.data.name = "Palomino67BadgesMesh"

    # Join remaining exterior objects
    ext_objs = [
        obj for obj in bpy.data.objects
        if obj.type == "MESH" and obj.name not in wheel_set and obj != badges_obj
    ]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in ext_objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = bpy.data.objects["PalominoSpecial67_Body"]
    bpy.ops.object.join()
    exterior = bpy.context.view_layer.objects.active
    exterior.name = "Palomino67Exterior"
    exterior.data.name = "Palomino67ExteriorMesh"
    if exterior.data.validate(verbose=True):
        print("[EXTERIOR] Mesh validation repaired geometry issues.")
    exterior.data.update()
    bmin, bmax = compute_object_bounds(exterior)
    print(f"[EXTERIOR] X=[{bmin.x:.4f},{bmax.x:.4f}] Y=[{bmin.y:.4f},{bmax.y:.4f}] Z=[{bmin.z:.4f},{bmax.z:.4f}]")
    return exterior, badges_obj


def bake_f250_emit_atlas(obj: bpy.types.Object, image_size: int, bake_path: Path, is_chassis: bool = True) -> None:
    """Create 'Atlas' UV via Smart UV Project and bake Cycles CPU Emit with F-250 AO + directional lighting."""
    mesh = obj.data
    if "Atlas" in mesh.uv_layers:
        mesh.uv_layers.remove(mesh.uv_layers["Atlas"])
    mesh.uv_layers.new(name="Atlas")
    mesh.uv_layers.active = mesh.uv_layers["Atlas"]
    mesh.uv_layers["Atlas"].active = True
    mesh.uv_layers["Atlas"].active_render = True

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.05, island_margin=0.018)
    bpy.ops.object.mode_set(mode="OBJECT")
    mesh.uv_layers.active = mesh.uv_layers["Atlas"]
    mesh.uv_layers["Atlas"].active = True

    bake_img = bpy.data.images.new(f"Bake_{obj.name}", width=image_size, height=image_size, alpha=True)
    bake_img.colorspace_settings.name = "sRGB"

    light_dir = Vector((0.35, 0.31, 0.88)).normalized()

    for slot in obj.material_slots:
        orig_mat = slot.material
        if orig_mat is None:
            continue
        mname = orig_mat.name

        # Grab base color image before rebuilding node tree
        linked_img = None
        mix_mul_color = None
        if orig_mat.use_nodes and orig_mat.node_tree:
            bsdf = next((n for n in orig_mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if bsdf and bsdf.inputs["Base Color"].is_linked:
                src_node = bsdf.inputs["Base Color"].links[0].from_node
                if src_node.type == "TEX_IMAGE":
                    linked_img = src_node.image
                elif src_node.type == "MIX":
                    mix_mul_color = tuple(src_node.inputs[7].default_value)
                    if src_node.inputs[6].is_linked and src_node.inputs[6].links[0].from_node.type == "TEX_IMAGE":
                        linked_img = src_node.inputs[6].links[0].from_node.image

        mat = orig_mat.copy()
        slot.material = mat
        mat.use_nodes = True
        nt = mat.node_tree
        nt.nodes.clear()

        out = nt.nodes.new("ShaderNodeOutputMaterial")
        uv_orig = nt.nodes.new("ShaderNodeUVMap")
        uv_orig.uv_map = "Original"

        dir_min = 0.94
        color_socket = None
        const_color = (0.5, 0.5, 0.5, 1.0)

        if mname == "CabinGlass_OpaqueBlack":
            const_color = (0.0025, 0.0028, 0.0032, 1.0)
            dir_min = 0.94
        elif mname == "HeadlightCrystal":
            const_color = (0.72, 0.83, 0.94, 1.0)
            dir_min = 0.85
        elif mname == "TaillightRuby":
            const_color = (0.76, 0.025, 0.025, 1.0)
            dir_min = 0.92
        elif mname == "PalominoSpecial67_Bodymat" and linked_img is not None:
            tex_b = nt.nodes.new("ShaderNodeTexImage")
            tex_b.image = linked_img
            nt.links.new(uv_orig.outputs["UV"], tex_b.inputs["Vector"])
            mix_r = nt.nodes.new("ShaderNodeMix")
            mix_r.data_type = "RGBA"
            mix_r.blend_type = "MULTIPLY"
            mix_r.inputs["Factor"].default_value = 1.0
            nt.links.new(tex_b.outputs["Color"], mix_r.inputs["A"])
            mix_r.inputs["B"].default_value = mix_mul_color or (0.6706, 0.0, 0.0, 1.0)
            color_socket = mix_r.outputs["Result"]
            dir_min = 0.83
        elif mname == "Numberplates_Misk_U" and linked_img is not None:
            tex_p = nt.nodes.new("ShaderNodeTexImage")
            tex_p.image = linked_img
            nt.links.new(uv_orig.outputs["UV"], tex_p.inputs["Vector"])
            mix_p = nt.nodes.new("ShaderNodeMix")
            mix_p.data_type = "RGBA"
            mix_p.inputs["A"].default_value = (0.76, 0.76, 0.74, 1.0)
            nt.links.new(tex_p.outputs["Color"], mix_p.inputs["B"])
            nt.links.new(tex_p.outputs["Alpha"], mix_p.inputs["Factor"])
            color_socket = mix_p.outputs["Result"]
            dir_min = 0.94
        elif linked_img is not None:
            tex_s = nt.nodes.new("ShaderNodeTexImage")
            tex_s.image = linked_img
            nt.links.new(uv_orig.outputs["UV"], tex_s.inputs["Vector"])
            color_socket = tex_s.outputs["Color"]
            dir_min = 0.88 if not is_chassis else 0.94

        if not is_chassis and dir_min > 0.88:
            dir_min = 0.88

        ao_node = nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao_node.samples = 8
        ao_node.inputs["Distance"].default_value = 0.29

        ao_mix = nt.nodes.new("ShaderNodeMath")
        ao_mix.operation = "MULTIPLY_ADD"
        nt.links.new(ao_node.outputs["AO"], ao_mix.inputs[0])
        ao_mix.inputs[1].default_value = 0.41
        ao_mix.inputs[2].default_value = 0.59

        geom = nt.nodes.new("ShaderNodeNewGeometry")
        dot_node = nt.nodes.new("ShaderNodeVectorMath")
        dot_node.operation = "DOT_PRODUCT"
        nt.links.new(geom.outputs["Normal"], dot_node.inputs[0])
        dot_node.inputs[1].default_value = (light_dir.x, light_dir.y, light_dir.z)

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
        if color_socket is not None:
            nt.links.new(color_socket, tint_mul.inputs["A"])
        else:
            tint_mul.inputs["A"].default_value = const_color

        comb = nt.nodes.new("ShaderNodeCombineColor")
        nt.links.new(shade_mul.outputs["Value"], comb.inputs["Red"])
        nt.links.new(shade_mul.outputs["Value"], comb.inputs["Green"])
        nt.links.new(shade_mul.outputs["Value"], comb.inputs["Blue"])
        nt.links.new(comb.outputs["Color"], tint_mul.inputs["B"])

        emit = nt.nodes.new("ShaderNodeEmission")
        emit.inputs["Strength"].default_value = 1.0
        nt.links.new(tint_mul.outputs["Result"], emit.inputs["Color"])
        nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])

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

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.bake(type="EMIT")

    bake_img.filepath_raw = str(bake_path)
    bake_img.file_format = "PNG"
    bake_img.save()
    print(f"[BAKE] Saved {image_size}x{image_size} bake for {obj.name} -> {bake_path.name}")


def run_ps1kit_quantize(src_path: Path, dst_path: Path, size: tuple[int, int], dither_strength: float, binary_alpha: bool = False) -> None:
    script = (
        "import sys, numpy as np; "
        f"sys.path.insert(0, {repr(str(PS1KIT_DIR))}); "
        "from PIL import Image; "
        "from ps1kit import process_texture; "
        f"img = Image.open({repr(str(src_path))}); "
        f"out, _ = process_texture(img, size={repr(size)}, colors=None, dither_strength={dither_strength}); "
    )
    if binary_alpha:
        script += (
            "arr = np.array(out); "
            "arr[..., 3] = np.where(arr[..., 3] >= 128, 255, 0); "
            "out = Image.fromarray(arr); "
        )
    script += f"out.save({repr(str(dst_path))}, format='PNG'); print('[PS1KIT]', out.size, out.mode)"
    subprocess.run(["python", "-c", script], check=True)


def make_psx_material(name: str, image_path: Path, roughness: float, coat: float = 0.0, alpha_cutout: bool = False) -> bpy.types.Material:
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
    if alpha_cutout:
        nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        mat.blend_method = "CLIP"
        mat.alpha_threshold = 0.5
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def finalize_single_uv_and_material(obj: bpy.types.Object, uv_keep: str, mat: bpy.types.Material) -> None:
    mesh = obj.data
    for layer in list(mesh.uv_layers):
        if layer.name != uv_keep:
            mesh.uv_layers.remove(layer)
    mesh.uv_layers.active = mesh.uv_layers[uv_keep]
    mesh.uv_layers[uv_keep].active = True
    mesh.uv_layers[uv_keep].active_render = True

    mesh.materials.clear()
    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.material_index = 0
    mesh.update()


def export_selected_glb(objs: list[bpy.types.Object], out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
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
    raw = glb_path.read_bytes()
    magic, version, _ = struct.unpack_from("<4sII", raw, 0)
    if magic != b"glTF" or version != 2:
        raise RuntimeError(f"Unexpected GLB header in {glb_path}")
    json_len, json_type = struct.unpack_from("<II", raw, 12)
    if json_type != 0x4E4F534A:
        raise RuntimeError(f"Expected JSON chunk first in {glb_path}")
    model = json.loads(raw[20:20 + json_len])
    bin_chunk = raw[20 + json_len:]

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
    json_bytes += b" " * ((-len(json_bytes)) % 4)
    json_hdr = struct.pack("<I4s", len(json_bytes), b"JSON")
    total_len = 12 + len(json_hdr) + len(json_bytes) + len(bin_chunk)
    glb_path.write_bytes(struct.pack("<4sII", b"glTF", 2, total_len) + json_hdr + json_bytes + bin_chunk)


def extract_zone_convex_hull_godot(obj: bpy.types.Object, y_min: float, y_max: float) -> list[dict[str, float]]:
    bm = bmesh.new()
    for v in obj.data.vertices:
        if y_min <= v.co.y <= y_max:
            bm.verts.new((v.co.x, v.co.y, max(0.18, v.co.z)))
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

    if len(points) > 100:
        keep = set(range(0, len(points), max(1, len(points) // 80)))
        for axis in ("x", "y", "z"):
            keep.add(min(range(len(points)), key=lambda idx: points[idx][axis]))
            keep.add(max(range(len(points)), key=lambda idx: points[idx][axis]))
        for idx in convex_hull_2d([Vector((p["x"], p["z"])) for p in points]):
            keep.add(idx)
        points = [points[i] for i in sorted(keep)]
    return points


def build_collision_manifest_and_sync_profile(
    exterior: bpy.types.Object,
    badges_obj: bpy.types.Object,
    chassis_glb: Path,
    wheel_glbs: dict[str, Path],
    dims: dict[str, float],
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
        "source_object": exterior.name,
        "hulls": hulls,
        "boxes": [
            {
                "identifier": "sump_guard",
                "center": {"x": 0.0, "y": 0.21, "z": -1.45},
                "half_extents": {"x": 0.55, "y": 0.06, "z": 0.55},
            },
            {
                "identifier": "floor",
                "center": {"x": 0.0, "y": 0.24, "z": 0.1},
                "half_extents": {"x": 0.6, "y": 0.09, "z": 1.5},
            },
        ],
    }
    collision_path = OUTPUT_DIR / "ford_mustang_1967_289_2v_collision.json"
    collision_path.write_text(json.dumps(collision_doc, indent=2) + "\n", encoding="utf-8")

    half_ft = dims["front_track"] * 0.5
    half_rt = dims["rear_track"] * 0.5
    half_wb = dims["wheelbase"] * 0.5
    radius = dims["tire_radius"]
    width = dims["tire_width"]

    pivots_bl = {
        "front_left": [-half_ft, half_wb, radius],
        "front_right": [half_ft, half_wb, radius],
        "rear_left": [-half_rt, -half_wb, radius],
        "rear_right": [half_rt, -half_wb, radius],
    }

    min_bl = [round(float(ext_min.x), 5), round(float(ext_min.y), 5), round(float(ext_min.z), 5)]
    max_bl = [round(float(ext_max.x), 5), round(float(ext_max.y), 5), round(float(ext_max.z), 5)]
    min_gd = [round(float(ext_min.x), 5), round(float(ext_min.z), 5), round(float(-ext_max.y), 5)]
    max_gd = [round(float(ext_max.x), 5), round(float(ext_max.z), 5), round(float(-ext_min.y), 5)]

    manifest = {
        "contract_version": 1,
        "vehicle_id": "ford_mustang_1967_289_2v",
        "source": {
            "blend": str(SOURCE_BLEND),
            "blender_version": "5.2.0 LTS",
            "texture_finish": "original_livery_baked_psx_rgb555",
            "note": (
                "PalominoSpecial67.blend exterior and wheels with interior stripped, opaque black cabin glass, "
                "crystal headlight glass, red Bodymat Mix(MULTIPLY) and F-250 PSX RGB555 baked finish."
            ),
        },
        "coordinate_system": {
            "engine": "Godot",
            "forward": "-Z",
            "right": "+X",
            "up": "+Y",
            "conversion": "Rotated +90 deg around Blender Z, centered wheelbase/tracks around origin; glTF +Y up.",
        },
        "geometry": {
            "wheelbase": dims["wheelbase"],
            "front_track": dims["front_track"],
            "rear_track": dims["rear_track"],
            "front_axle_z": -round(half_wb, 5),
            "rear_axle_z": round(half_wb, 5),
        },
        "chassis": {
            "path": chassis_glb.name,
            "sha256": sha256_file(chassis_glb),
            "size_bytes": chassis_glb.stat().st_size,
            "exported_nodes": [exterior.name, badges_obj.name],
        },
        "wheels": {
            key: {
                "path": path.name,
                "sha256": sha256_file(path),
                "size_bytes": path.stat().st_size,
                "source_object": WHEEL_OBJECTS[key],
            }
            for key, path in wheel_glbs.items()
        },
        "collision": {
            "path": collision_path.name,
            "sha256": sha256_file(collision_path),
        },
        "wheel_pivots": {
            key: {
                "blender_object": WHEEL_OBJECTS[key],
                "center_metres": {
                    "x": to_godot_coords(p_bl)[0],
                    "y": to_godot_coords(p_bl)[1],
                    "z": to_godot_coords(p_bl)[2],
                },
                "radius_metres": radius,
                "width_metres": width,
            }
            for key, p_bl in pivots_bl.items()
        },
        "bounds_world_metres": {
            "min_blender": min_bl,
            "max_blender": max_bl,
            "min_godot": min_gd,
            "max_godot": max_gd,
        },
    }
    manifest_path = OUTPUT_DIR / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    # Sync physics JSONs (chassis.json, tires.json) & HISTORICAL_PROVENANCE.json note
    chassis_json_path = PROFILE_DIR / "chassis.json"
    chassis_doc = json.loads(chassis_json_path.read_text(encoding="utf-8"))
    chassis_doc["geometry"]["wheelbase"] = dims["wheelbase"]
    chassis_doc["geometry"]["front_axle_z"] = -round(half_wb, 5)
    chassis_doc["geometry"]["rear_axle_z"] = round(half_wb, 5)
    chassis_doc["geometry"]["front_track"] = dims["front_track"]
    chassis_doc["geometry"]["rear_track"] = dims["rear_track"]
    chassis_json_path.write_text(json.dumps(chassis_doc, indent=2) + "\n", encoding="utf-8")

    tires_json_path = PROFILE_DIR / "tires.json"
    tires_doc = json.loads(tires_json_path.read_text(encoding="utf-8"))
    for axle in ("front", "rear"):
        if axle in tires_doc.get("tires", {}):
            tires_doc["tires"][axle]["radius"] = radius
            tires_doc["tires"][axle]["width"] = width
    tires_json_path.write_text(json.dumps(tires_doc, indent=2) + "\n", encoding="utf-8")

    prov_path = PROFILE_DIR / "HISTORICAL_PROVENANCE.json"
    prov_doc = json.loads(prov_path.read_text(encoding="utf-8"))
    prov_doc["note"] = (
        f"Uses native measured FBX/blend wheelbase ({dims['wheelbase']} m), tracks ({dims['front_track']} / "
        f"{dims['rear_track']} m), and tires (R={radius} m, W={width} m) from PalominoSpecial67."
    )
    prov_path.write_text(json.dumps(prov_doc, indent=2) + "\n", encoding="utf-8")
    print("[DONE] Wrote collision, manifest.json, chassis.json, tires.json, and HISTORICAL_PROVENANCE.json")


def main() -> None:
    if not SOURCE_BLEND.is_file():
        raise FileNotFoundError(f"Source blend missing: {SOURCE_BLEND}")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.open_mainfile(filepath=str(SOURCE_BLEND))
    resolve_textures()
    cleanup_and_rotate_90_z()
    dims = align_and_measure_wheels()
    reassign_glass_and_light_materials()
    exterior, badges_obj = join_exterior_and_badges()

    wheel_objs = {key: bpy.data.objects[name] for key, name in WHEEL_OBJECTS.items()}

    with tempfile.TemporaryDirectory(prefix="mustang_psx_") as tmp:
        tmp_dir = Path(tmp)
        chassis_raw = tmp_dir / "chassis_bake_1024.png"
        chassis_psx = tmp_dir / "chassis_psx_512.png"
        badges_psx = tmp_dir / "badges_psx_512.png"

        badges_obj.hide_render = True
        for w in wheel_objs.values():
            w.hide_render = True
        bake_f250_emit_atlas(exterior, 1024, chassis_raw, is_chassis=True)
        badges_obj.hide_render = False
        for w in wheel_objs.values():
            w.hide_render = False

        run_ps1kit_quantize(chassis_raw, chassis_psx, size=(512, 512), dither_strength=0.36)
        chassis_mat = make_psx_material("Mustang67_PSX", chassis_psx, roughness=0.64, coat=0.08)
        finalize_single_uv_and_material(exterior, "Atlas", chassis_mat)

        run_ps1kit_quantize(SOURCE_TEXTURES_DIR / "Carbadges_misc_U_dif.png", badges_psx, size=(512, 512), dither_strength=0.32, binary_alpha=True)
        badges_mat = make_psx_material("Mustang67_Badges_PSX", badges_psx, roughness=0.55, coat=0.0, alpha_cutout=True)
        finalize_single_uv_and_material(badges_obj, "Original", badges_mat)

        chassis_glb = OUTPUT_DIR / "ford_mustang_1967_289_2v_chassis.glb"
        export_selected_glb([exterior, badges_obj], chassis_glb)
        patch_glb_nearest_samplers(chassis_glb)
        print(f"[CHASSIS] Exported & patched {chassis_glb.name}")

        exterior.hide_render = True
        badges_obj.hide_render = True
        wheel_glbs: dict[str, Path] = {}
        for key, wobj in wheel_objs.items():
            wmin, wmax = compute_object_bounds(wobj)
            wcenter = 0.5 * (wmin + wmax)
            for v in wobj.data.vertices:
                v.co -= wcenter
            wobj.data.update()

            wheel_raw = tmp_dir / f"wheel_{key}_bake_512.png"
            wheel_psx = tmp_dir / f"wheel_{key}_psx_512.png"
            bake_f250_emit_atlas(wobj, 512, wheel_raw, is_chassis=False)
            run_ps1kit_quantize(wheel_raw, wheel_psx, size=(512, 512), dither_strength=0.32)
            wmat = make_psx_material(f"MustangWheel_{key}_PSX", wheel_psx, roughness=0.72, coat=0.0)
            finalize_single_uv_and_material(wobj, "Atlas", wmat)

            out_path = OUTPUT_DIR / f"ford_mustang_1967_289_2v_wheel_{key}.glb"
            export_selected_glb([wobj], out_path)
            patch_glb_nearest_samplers(out_path)
            wheel_glbs[key] = out_path
            wmin2, wmax2 = compute_object_bounds(wobj)
            print(f"[WHEEL {key}] X=[{wmin2.x:.4f},{wmax2.x:.4f}] Y=[{wmin2.y:.4f},{wmax2.y:.4f}] Z=[{wmin2.z:.4f},{wmax2.z:.4f}]")

    build_collision_manifest_and_sync_profile(exterior, badges_obj, chassis_glb, wheel_glbs, dims)


if __name__ == "__main__":
    main()
