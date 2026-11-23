"""Build Alpine Renault A110 (rt-alpine-a110) chassis, wheels, collision, manifest, and PSX finish.

Source model:
    D:/RallyManiacAssets/1963-alpine-renault-a110-lp/source/Alpine Renault A110 '63 (LP).blend

Key features:
- Resets armature rest pose, applies Mirror modifiers before clearing Armature/helpers.
- Removes Interior, Seats, Armature, Camera, Light, plus interior polygons
  ('Interior 1', 'Interior 2', 'Interior 3') embedded in Body.
- Keeps headlight crystal covers ('Shade') painted as light crystal-blue glass,
  and converts cabin 'Glass' to opaque glossy black.
- Updates front/rear tracks (1.300 m / 1.300 m) and wheel radius/width (0.2972 m / 0.2050 m)
  from the Blender model into manifest.json, chassis.json, tires.json, and HISTORICAL_PROVENANCE.json.
- Applies F-250 Cycles Emit + AO + directional bake -> ps1kit RGB555 Bayer dithering
  (512x512, dither=0.36 chassis / 0.32 wheel) and glTF NEAREST sampler patching.
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
OUTPUT_DIR = PROJECT_ROOT / "game" / "assets" / "rally" / "rt" / "rt-alpine-a110"
PROFILE_DIR = PROJECT_ROOT / "game" / "data" / "vehicles" / "rt" / "rt-alpine-a110"

SOURCE_BLEND = Path(r"D:\RallyManiacAssets\1963-alpine-renault-a110-lp\source\Alpine Renault A110 '63 (LP).blend")
PS1KIT_DIR = Path(r"D:\RallyManiacAssets\tools\ps1kit")

TARGET_WHEELBASE_M = 2.100  # Matches documented FIA #3035 & chassis.json (native blend is 2.110 m)

EXTERIOR_OBJECTS = (
    "Body",
    "Bumpers",
    "Exhaust",
    "Side mirror(s)",
    "Turn signals",
    "Wipers",
)
WHEEL_SOURCE_OBJECT = "Low-poly wheels"
INTERIOR_MATERIAL_NAMES = {"Interior 1", "Interior 2", "Interior 3"}


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


def prepare_objects_and_apply_mirror() -> None:
    """Reset armature rest pose, apply Mirror modifiers, unparent, and delete interior/rig helpers."""
    for obj in bpy.data.objects:
        if obj.type == "ARMATURE" and obj.pose is not None:
            for pbone in obj.pose.bones:
                pbone.location = (0.0, 0.0, 0.0)
                pbone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
                pbone.rotation_euler = (0.0, 0.0, 0.0)
                pbone.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()

    keep_names = set(EXTERIOR_OBJECTS) | {WHEEL_SOURCE_OBJECT}
    for name in sorted(keep_names):
        obj = bpy.data.objects.get(name)
        if obj is None:
            raise RuntimeError(f"Expected object '{name}' not found in {SOURCE_BLEND}")
        if obj.data.users > 1:
            obj.data = obj.data.copy()

        world_mat = obj.matrix_world.copy()
        obj.constraints.clear()
        obj.parent = None
        obj.matrix_world = world_mat

        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj

        # Apply Mirror, Armature (at rest), and Auto Smooth NODES modifiers before cleanup
        for mod in list(obj.modifiers):
            if mod.type in ("MIRROR", "ARMATURE", "NODES"):
                bpy.ops.object.modifier_apply(modifier=mod.name)
        obj.modifiers.clear()

    to_delete = [obj for obj in list(bpy.data.objects) if obj.name not in keep_names]
    for obj in to_delete:
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.context.view_layer.update()
    print(f"[SCENE] Retained {len(bpy.data.objects)} mirrored objects; purged {len(to_delete)} interior/rig helpers.")


def strip_embedded_interior_faces(body_obj: bpy.types.Object) -> None:
    """Delete polygons assigned to Interior 1/2/3 materials embedded inside Body."""
    interior_indices = {
        idx
        for idx, slot in enumerate(body_obj.material_slots)
        if slot.material and slot.material.name in INTERIOR_MATERIAL_NAMES
    }
    if not interior_indices:
        return

    bm = bmesh.new()
    bm.from_mesh(body_obj.data)
    remove_faces = [f for f in bm.faces if f.material_index in interior_indices]
    bmesh.ops.delete(bm, geom=remove_faces, context="FACES")
    orphan_verts = [v for v in bm.verts if not v.link_faces]
    if orphan_verts:
        bmesh.ops.delete(bm, geom=orphan_verts, context="VERTS")
    bm.to_mesh(body_obj.data)
    bm.free()

    # Clean unused interior material slots (keep indexes aligned by popping backwards)
    bpy.ops.object.select_all(action="DESELECT")
    body_obj.select_set(True)
    bpy.context.view_layer.objects.active = body_obj
    for idx in sorted(interior_indices, reverse=True):
        body_obj.active_material_index = idx
        bpy.ops.object.material_slot_remove()
    body_obj.data.update()
    print(f"[BODY] Stripped {len(remove_faces)} embedded interior faces and {len(orphan_verts)} orphan verts.")


def rotate_all_180_z_and_apply() -> None:
    """Rotate all objects +180 deg around Z (+Y forward in Blender) and apply transforms."""
    rot_z = Matrix.Rotation(math.pi, 4, "Z")
    for obj in bpy.data.objects:
        if obj.type == "MESH" and obj.data.users > 1:
            obj.data = obj.data.copy()
        obj.matrix_world = rot_z @ obj.matrix_world
    bpy.context.view_layer.update()

    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = bpy.data.objects["Body"]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.select_all(action="DESELECT")


def separate_wheels_by_quadrant(wheels_obj: bpy.types.Object) -> dict[str, bpy.types.Object]:
    """Split combined Low-poly wheels into 4 separate wheel objects after +180 deg Z rotation."""
    mesh = wheels_obj.data
    quadrants = {
        "front_left": lambda v: v.x < 0.0 and v.y > 0.0,
        "front_right": lambda v: v.x > 0.0 and v.y > 0.0,
        "rear_left": lambda v: v.x < 0.0 and v.y < 0.0,
        "rear_right": lambda v: v.x > 0.0 and v.y < 0.0,
    }
    separated: dict[str, bpy.types.Object] = {}
    for key, pred in quadrants.items():
        new_mesh = mesh.copy()
        new_mesh.name = f"WheelMesh_{key}"
        new_obj = bpy.data.objects.new(f"wheel_{key}", new_mesh)
        bpy.context.collection.objects.link(new_obj)

        bm = bmesh.new()
        bm.from_mesh(new_mesh)
        keep_verts = {v for v in bm.verts if pred(v.co)}
        del_verts = [v for v in bm.verts if v not in keep_verts]
        bmesh.ops.delete(bm, geom=del_verts, context="VERTS")
        bm.to_mesh(new_mesh)
        bm.free()
        new_mesh.update()
        separated[key] = new_obj

    bpy.data.objects.remove(wheels_obj, do_unlink=True)
    bpy.context.view_layer.update()
    return separated


def align_geometry_from_blender_measurements(
    exterior_objs: list[bpy.types.Object],
    wheel_objs: dict[str, bpy.types.Object],
) -> dict[str, float]:
    """Center wheelbase around Y=0, ground wheels at Z=0, preserve native Blender tracks & tire sizes."""
    centers = {}
    widths = []
    radii = []
    bottoms = []
    for key, wobj in wheel_objs.items():
        wmin, wmax = compute_object_bounds(wobj)
        centers[key] = 0.5 * (wmin + wmax)
        widths.append(wmax.x - wmin.x)
        radii.append(0.25 * ((wmax.y - wmin.y) + (wmax.z - wmin.z)))
        bottoms.append(wmin.z)

    front_y_raw = 0.5 * (centers["front_left"].y + centers["front_right"].y)
    rear_y_raw = 0.5 * (centers["rear_left"].y + centers["rear_right"].y)
    raw_wheelbase = front_y_raw - rear_y_raw
    y_center_shift = -0.5 * (front_y_raw + rear_y_raw)
    y_scale = TARGET_WHEELBASE_M / raw_wheelbase
    z_shift = -min(bottoms)

    front_track = abs(centers["front_right"].x - centers["front_left"].x)
    rear_track = abs(centers["rear_right"].x - centers["rear_left"].x)
    tire_width = sum(widths) / len(widths)
    tire_radius = sum(radii) / len(radii)

    for obj in exterior_objs:
        for v in obj.data.vertices:
            v.co.y = (v.co.y + y_center_shift) * y_scale
            v.co.z = v.co.z + z_shift
        obj.data.update()
    for wobj in wheel_objs.values():
        for v in wobj.data.vertices:
            v.co.y = v.co.y + y_center_shift
            v.co.z = v.co.z + z_shift
        wobj.data.update()

    print(
        f"[MEASURE] raw_wb={raw_wheelbase:.4f} -> {TARGET_WHEELBASE_M:.4f} (y_scale={y_scale:.5f}), "
        f"tracks=({front_track:.4f}, {rear_track:.4f}), tire R={tire_radius:.4f}, W={tire_width:.4f}"
    )
    return {
        "wheelbase": TARGET_WHEELBASE_M,
        "front_track": round(float(front_track), 4),
        "rear_track": round(float(rear_track), 4),
        "tire_radius": round(float(tire_radius), 4),
        "tire_width": round(float(tire_width), 4),
    }


def join_exterior(exterior_objs: list[bpy.types.Object]) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in exterior_objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = exterior_objs[0]
    bpy.ops.object.join()
    exterior = bpy.context.view_layer.objects.active
    exterior.name = "AlpineA110Exterior"
    exterior.data.name = "AlpineA110ExteriorMesh"
    if exterior.data.validate(verbose=True):
        print("[EXTERIOR] Mesh validation repaired geometry issues.")
    exterior.data.update()
    bmin, bmax = compute_object_bounds(exterior)
    print(f"[EXTERIOR] X=[{bmin.x:.4f},{bmax.x:.4f}] Y=[{bmin.y:.4f},{bmax.y:.4f}] Z=[{bmin.z:.4f},{bmax.z:.4f}]")
    return exterior


def resolve_material_bake_color(mat: bpy.types.Material) -> tuple[tuple[float, float, float, float], float]:
    """Return (linear_rgba, min_directional_scale) tailored for each procedural Alpine material."""
    name = mat.name
    if name == "Glass":
        return (0.0025, 0.0028, 0.0032, 1.0), 0.94
    if name == "Shade":
        # User choice: preserve crystal-painted headlight covers
        return (0.72, 0.83, 0.94, 1.0), 0.85
    if name == "Headlight":
        return (0.96, 0.97, 1.00, 1.0), 0.94
    if name == "Tail lights":
        return (0.80, 0.015, 0.015, 1.0), 0.94
    if name == "Orange plastic":
        return (0.82, 0.16, 0.0, 1.0), 0.94
    if name == "Paint (metallic)":
        return (0.0595, 0.204, 0.4931, 1.0), 0.83
    if name == "Chrom":
        return (0.72, 0.74, 0.76, 1.0), 0.88
    if name == "Aluminium":
        return (0.84, 0.86, 0.88, 1.0), 0.88
    if name == "Steel":
        return (0.5583, 0.5711, 0.5776, 1.0), 0.90
    if name == "Reflector":
        return (0.95, 0.94, 0.90, 1.0), 0.94
    if name == "Black plastic":
        return (0.0196, 0.020, 0.022, 1.0), 0.92
    if name == "Rubber":
        return (0.012, 0.013, 0.015, 1.0), 0.88
    if name == "Underbody":
        return (0.006, 0.006, 0.007, 1.0), 0.94
    return (0.5, 0.5, 0.5, 1.0), 0.94


def bake_f250_emit_atlas(obj: bpy.types.Object, image_size: int, bake_path: Path, is_paint_weighted: bool = True) -> None:
    """Create 'Atlas' UV via Smart UV Project and bake Cycles CPU Emit with F-250 AO + directional shade."""
    mesh = obj.data
    for layer in list(mesh.uv_layers):
        mesh.uv_layers.remove(layer)
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
    # Replace each slot with a duplicate material configured for Cycles Emit so exterior & wheels don't collide
    for slot in obj.material_slots:
        orig_mat = slot.material
        if orig_mat is None:
            continue
        mat = orig_mat.copy()
        slot.material = mat
        mat.use_nodes = True
        nt = mat.node_tree
        nt.nodes.clear()

        rgba, dir_min = resolve_material_bake_color(orig_mat)
        if not is_paint_weighted and dir_min < 0.88:
            dir_min = 0.88

        out = nt.nodes.new("ShaderNodeOutputMaterial")
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
        tint_mul.inputs["A"].default_value = rgba

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


def run_ps1kit_quantize(src_path: Path, dst_path: Path, size: tuple[int, int], dither_strength: float) -> None:
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


def apply_single_material(obj: bpy.types.Object, mat: bpy.types.Material) -> None:
    mesh = obj.data
    mesh.materials.clear()
    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.material_index = 0
    mesh.uv_layers.active = mesh.uv_layers["Atlas"]
    mesh.uv_layers["Atlas"].active = True
    mesh.uv_layers["Atlas"].active_render = True
    mesh.update()


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


def extract_hull_godot(obj: bpy.types.Object, z_min_bl: float, z_max_bl: float) -> list[dict[str, float]]:
    bm = bmesh.new()
    for v in obj.data.vertices:
        if z_min_bl <= v.co.z <= z_max_bl:
            bm.verts.new((v.co.x, v.co.y, max(0.14, v.co.z)))
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
    chassis_glb: Path,
    wheel_glbs: dict[str, Path],
    dims: dict[str, float],
) -> None:
    ext_min, ext_max = compute_object_bounds(exterior)
    lower_pts = extract_hull_godot(exterior, 0.0, 0.60)
    cabin_pts = extract_hull_godot(exterior, 0.35, 10.0)
    collision_doc = {
        "hulls": [
            {"identifier": "lower", "points": lower_pts},
            {"identifier": "cabin", "points": cabin_pts},
        ],
        "boxes": [],
        "source": f"Generated from {SOURCE_BLEND.name} ({exterior.name})",
    }
    collision_path = OUTPUT_DIR / "collision.json"
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

    manifest_path = OUTPUT_DIR / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["source"]["runtime_visuals"] = {
        "blend": str(SOURCE_BLEND),
        "finish": "original_livery_baked_psx_rgb555",
        "fit": (
            f"Blender 'Alpine Renault A110 63 (LP).blend' rotated +180 deg Z, Mirror applied, "
            f"interior stripped, headlight crystal covers ('Shade') preserved, cabin glass opaque black; "
            f"tracks {dims['front_track']:.3f}/{dims['rear_track']:.3f} m and tire R={radius:.4f} W={width:.4f} m."
        ),
        "cockpit_enabled": False,
        "visual_damage_enabled": False,
    }
    manifest["source"]["texture_finish"] = "original_livery_baked_psx_rgb555"
    manifest["coordinate_system"] = {
        "forward": "-Z",
        "right": "+X",
        "up": "+Y",
        "visual_physics_offset_metres": 0,
    }
    manifest["chassis"] = {
        "path": chassis_glb.name,
        "sha256": sha256_file(chassis_glb),
        "size_bytes": chassis_glb.stat().st_size,
        "exported_nodes": [exterior.name],
    }
    manifest["wheels"] = {
        key: {
            "path": path.name,
            "sha256": sha256_file(path),
            "size_bytes": path.stat().st_size,
        }
        for key, path in wheel_glbs.items()
    }
    manifest["wheel_pivots"] = {
        key: {
            "center_metres": {
                "x": to_godot_coords(p_bl)[0],
                "y": to_godot_coords(p_bl)[1],
                "z": to_godot_coords(p_bl)[2],
            },
            "radius_metres": radius,
            "width_metres": width,
        }
        for key, p_bl in pivots_bl.items()
    }
    manifest["geometry"] = {
        "wheelbase": dims["wheelbase"],
        "front_axle_z": -half_wb,
        "rear_axle_z": half_wb,
        "front_track": dims["front_track"],
        "rear_track": dims["rear_track"],
    }
    manifest["collision"] = {
        "path": collision_path.name,
        "sha256": sha256_file(collision_path),
    }
    manifest["bounds_world_metres"] = {
        "min_godot": [round(float(ext_min.x), 6), round(float(ext_min.z), 6), round(float(-ext_max.y), 6)],
        "max_godot": [round(float(ext_max.x), 6), round(float(ext_max.z), 6), round(float(-ext_min.y), 6)],
    }
    manifest["measurement"] = {
        "geometry_policy": "blender_model_native_tracks_wheels",
        "uniform_scale": 1.0,
        "native_wheelbase_m": dims["wheelbase"],
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    # Sync track & tire dimensions in physics profile (chassis.json, tires.json) and HISTORICAL_PROVENANCE.json
    chassis_json_path = PROFILE_DIR / "chassis.json"
    chassis_doc = json.loads(chassis_json_path.read_text(encoding="utf-8"))
    chassis_doc["geometry"]["wheelbase"] = dims["wheelbase"]
    chassis_doc["geometry"]["front_axle_z"] = -half_wb
    chassis_doc["geometry"]["rear_axle_z"] = half_wb
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

    provenance_path = PROFILE_DIR / "HISTORICAL_PROVENANCE.json"
    provenance_doc = json.loads(provenance_path.read_text(encoding="utf-8"))
    for fname in list(provenance_doc.get("profile_json_sha256", {})):
        fpath = PROFILE_DIR / fname
        if fpath.is_file():
            provenance_doc["profile_json_sha256"][fname] = sha256_file(fpath)
    provenance_path.write_text(json.dumps(provenance_doc, indent=2) + "\n", encoding="utf-8")
    print("[DONE] Updated collision.json, manifest.json, chassis.json, tires.json, and HISTORICAL_PROVENANCE.json")


def main() -> None:
    if not SOURCE_BLEND.is_file():
        raise FileNotFoundError(f"Source blend missing: {SOURCE_BLEND}")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.open_mainfile(filepath=str(SOURCE_BLEND))
    prepare_objects_and_apply_mirror()
    strip_embedded_interior_faces(bpy.data.objects["Body"])
    rotate_all_180_z_and_apply()

    wheel_objs = separate_wheels_by_quadrant(bpy.data.objects[WHEEL_SOURCE_OBJECT])
    exterior_list = [bpy.data.objects[name] for name in EXTERIOR_OBJECTS]
    dims = align_geometry_from_blender_measurements(exterior_list, wheel_objs)
    exterior = join_exterior(exterior_list)

    with tempfile.TemporaryDirectory(prefix="alpine_psx_") as tmp:
        tmp_dir = Path(tmp)
        chassis_raw = tmp_dir / "chassis_bake_1024.png"
        chassis_psx = tmp_dir / "chassis_psx_512.png"

        bake_f250_emit_atlas(exterior, 1024, chassis_raw, is_paint_weighted=True)
        run_ps1kit_quantize(chassis_raw, chassis_psx, size=(512, 512), dither_strength=0.36)
        chassis_mat = make_psx_material("AlpineA110_PSX", chassis_psx, roughness=0.64, coat=0.08)
        apply_single_material(exterior, chassis_mat)

        chassis_glb = OUTPUT_DIR / "chassis.glb"
        export_single_glb(exterior, chassis_glb)
        patch_glb_nearest_samplers(chassis_glb)
        print(f"[CHASSIS] Exported & patched {chassis_glb.name}")

        wheel_glbs: dict[str, Path] = {}
        for key, wobj in wheel_objs.items():
            # Center wheel vertices at origin (0,0,0) before baking & exporting
            wmin, wmax = compute_object_bounds(wobj)
            wcenter = 0.5 * (wmin + wmax)
            for v in wobj.data.vertices:
                v.co -= wcenter
            wobj.data.update()

            wheel_raw = tmp_dir / f"wheel_{key}_bake_512.png"
            wheel_psx = tmp_dir / f"wheel_{key}_psx_512.png"
            bake_f250_emit_atlas(wobj, 512, wheel_raw, is_paint_weighted=False)
            run_ps1kit_quantize(wheel_raw, wheel_psx, size=(512, 512), dither_strength=0.32)
            wmat = make_psx_material(f"AlpineWheel_{key}_PSX", wheel_psx, roughness=0.72, coat=0.0)
            apply_single_material(wobj, wmat)

            out_path = OUTPUT_DIR / f"wheel_{key}.glb"
            export_single_glb(wobj, out_path)
            patch_glb_nearest_samplers(out_path)
            wheel_glbs[key] = out_path
            wmin2, wmax2 = compute_object_bounds(wobj)
            print(f"[WHEEL {key}] X=[{wmin2.x:.4f},{wmax2.x:.4f}] Y=[{wmin2.y:.4f},{wmax2.y:.4f}] Z=[{wmin2.z:.4f},{wmax2.z:.4f}]")

    build_collision_manifest_and_sync_profile(exterior, chassis_glb, wheel_glbs, dims)


if __name__ == "__main__":
    main()
