"""Build Ford Lotus Cortina Mk1 (rt-lotus-cortina) from FINAL_MODEL_65.fbx with F-250 PSX finish.

Source model:
    D:/RallyManiacAssets/1965-ford-lotus-cortina-mk1/source/FINAL_MODEL_65/FINAL_MODEL_65.fbx

Pipeline:
1. Import FINAL_MODEL_65.fbx, apply group1 transforms + 100x cm->m scale and +180 deg Z rotation
   (+Y forward in Blender / -Z forward in Godot).
2. Remove interior ('Cortina:lod13' Internal) and brake hardware ('Cortina:lod5', 'Cortina:lod6').
3. Keep badges ('Cortina:lod4') as an opaque-background-free ALPHA_SCISSOR sibling mesh
   ('LotusCortinaBadges') hidden during exterior AO baking so badges don't cast shadow boxes.
4. Separate tires ('Cortina:lod0') and rims ('Cortina:lod11') by quadrant into 4 wheel objects,
   extract exact native FBX measurements (wheelbase ~2.498 m, tracks ~1.315 m, tire R ~0.268 m,
   W ~0.177 m), center wheelbase around Y=0, X=0, and seat tires on Z=0.
5. Configure Cortina materials for Cycles Emit bake:
   - CaarPaint -> Ermine White (0.79, 0.78, 0.73) + Color_2 Lotus Green (0.1065, 0.187, 0.0707)
   - windows -> opaque glossy black (0.0025, 0.0028, 0.0032)
   - glass_light -> crystal blue headlight lenses (0.72, 0.83, 0.94)
   - Ted_glass / Oraange_glass -> ruby red / amber
   - grille -> silver slats over dark radiator cavity using Grille_d.png alpha
   - tire -> dark charcoal tinted Shared_Car_Tire_Sport_SSO.png; rim -> Rim_D.png
6. Bake 1024x1024 chassis atlas + 512x512 wheel atlases (F-250 Emit + AO + directional),
   quantize via ps1kit (512x512 RGB555, dither=0.36 chassis / 0.32 wheels / binary cutout badges),
   export GLBs with NEAREST samplers (magFilter=9728, minFilter=9984), regenerate collision.json,
   and update manifest.json, chassis.json, tires.json, and HISTORICAL_PROVENANCE.json.
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
OUTPUT_DIR = PROJECT_ROOT / "game" / "assets" / "rally" / "rt" / "rt-lotus-cortina"
PROFILE_DIR = PROJECT_ROOT / "game" / "data" / "vehicles" / "rt" / "rt-lotus-cortina"

SOURCE_DIR = Path(r"D:\RallyManiacAssets\1965-ford-lotus-cortina-mk1\source\FINAL_MODEL_65")
SOURCE_FBX = SOURCE_DIR / "FINAL_MODEL_65.fbx"
PS1KIT_DIR = Path(r"D:\RallyManiacAssets\tools\ps1kit")

SCALE_FBX_WORLD_TO_METRES = 100.0

EXTERIOR_OBJECTS = (
    "Cortina:lod1",   # metal / bumpers / trim
    "Cortina:lod2",   # amber & red rear lights
    "Cortina:lod3",   # windows, headlight crystal glass, red/amber glass
    "Cortina:lod7",   # underbody chassis
    "Cortina:lod8",   # front grille
    "Cortina:lod9",   # headlight reflectors
    "Cortina:lod10",  # CaarPaint (Ermine White)
    "Cortina:lod12",  # rear Plate
    "Cortina:lod14",  # side mirrors
    "Cortina:lod15",  # Color_2 (Lotus Green flash)
    "Cortina:lod16",  # front trim / plate bracket
)
BADGE_OBJECT = "Cortina:lod4"
TIRE_OBJECT = "Cortina:lod0"
RIM_OBJECT = "Cortina:lod11"
PURGE_OBJECTS = ("Cortina:lod5", "Cortina:lod6", "Cortina:lod13")


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


def resolve_fbx_images() -> None:
    by_name = {p.name.lower(): p for p in SOURCE_DIR.iterdir() if p.is_file()}
    for img in bpy.data.images:
        if img.source != "FILE":
            continue
        name = Path(bpy.path.abspath(img.filepath)).name.lower()
        if name in by_name:
            img.filepath = str(by_name[name])
            img.reload()


def bake_world_scale_and_rotate() -> None:
    """Purge interior/calipers/discs, unparent, scale to metres, and rotate +180 deg around Z."""
    for pname in PURGE_OBJECTS:
        pobj = bpy.data.objects.get(pname)
        if pobj is not None:
            bpy.data.objects.remove(pobj, do_unlink=True)

    keep_meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    scale_rot = Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Scale(SCALE_FBX_WORLD_TO_METRES, 4)

    for obj in keep_meshes:
        if obj.data.users > 1:
            obj.data = obj.data.copy()
        new_world = scale_rot @ obj.matrix_world
        obj.parent = None
        obj.matrix_world = new_world

    # Remove empty group1 etc.
    for obj in list(bpy.data.objects):
        if obj.type != "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.context.view_layer.update()

    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = bpy.data.objects["Cortina:lod10"]
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
    print(f"[SCENE] Converted {len(bpy.data.objects)} Cortina meshes to metric +Y-forward space.")


def separate_quadrant_meshes(tire_obj: bpy.types.Object, rim_obj: bpy.types.Object) -> dict[str, bpy.types.Object]:
    """Separate tires and rims into 4 combined wheel objects by (X, Y) quadrant."""
    quadrants = {
        "front_left": lambda v: v.x < 0.0 and v.y > 0.0,
        "front_right": lambda v: v.x > 0.0 and v.y > 0.0,
        "rear_left": lambda v: v.x < 0.0 and v.y < 0.0,
        "rear_right": lambda v: v.x > 0.0 and v.y < 0.0,
    }
    wheels: dict[str, bpy.types.Object] = {}

    for key, pred in quadrants.items():
        parts = []
        for src in (tire_obj, rim_obj):
            m = src.data.copy()
            o = bpy.data.objects.new(f"_tmp_{src.name}_{key}", m)
            bpy.context.collection.objects.link(o)
            bm = bmesh.new()
            bm.from_mesh(m)
            keep = {v for v in bm.verts if pred(v.co)}
            del_v = [v for v in bm.verts if v not in keep]
            bmesh.ops.delete(bm, geom=del_v, context="VERTS")
            bm.to_mesh(m)
            bm.free()
            m.update()
            parts.append(o)

        bpy.ops.object.select_all(action="DESELECT")
        for p in parts:
            p.select_set(True)
        bpy.context.view_layer.objects.active = parts[0]
        bpy.ops.object.join()
        wobj = bpy.context.view_layer.objects.active
        wobj.name = f"wheel_{key}"
        wobj.data.name = f"WheelMesh_{key}"
        wheels[key] = wobj

    bpy.data.objects.remove(tire_obj, do_unlink=True)
    bpy.data.objects.remove(rim_obj, do_unlink=True)
    bpy.context.view_layer.update()
    return wheels


def align_native_fbx_origin_and_measure(
    exterior_objs: list[bpy.types.Object],
    badges_obj: bpy.types.Object,
    wheel_objs: dict[str, bpy.types.Object],
) -> dict[str, float]:
    """Center X=0 and wheelbase Y=0 and seat tires on Z=0 preserving exact 1:1 native FBX proportions."""
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
    for obj in exterior_objs + [badges_obj] + list(wheel_objs.values()):
        for v in obj.data.vertices:
            v.co += shift
        obj.data.update()

    print(
        f"[NATIVE FBX] wheelbase={wheelbase:.4f} m, tracks=({front_track:.4f}, {rear_track:.4f}) m, "
        f"tire R={tire_radius:.4f} m, W={tire_width:.4f} m"
    )
    return {
        "wheelbase": round(float(wheelbase), 4),
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
    exterior.name = "LotusCortinaExterior"
    exterior.data.name = "LotusCortinaExteriorMesh"
    if exterior.data.validate(verbose=True):
        print("[EXTERIOR] Mesh validation repaired geometry issues.")
    exterior.data.update()
    bmin, bmax = compute_object_bounds(exterior)
    print(f"[EXTERIOR] X=[{bmin.x:.4f},{bmax.x:.4f}] Y=[{bmin.y:.4f},{bmax.y:.4f}] Z=[{bmin.z:.4f},{bmax.z:.4f}]")
    return exterior


def _find_image_texture(mat: bpy.types.Material) -> bpy.types.Image | None:
    if not mat.use_nodes or not mat.node_tree:
        return None
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf and bsdf.inputs["Base Color"].is_linked:
        src = bsdf.inputs["Base Color"].links[0].from_node
        if src.type == "TEX_IMAGE" and src.image is not None:
            return src.image
    return None


def bake_f250_emit_atlas(obj: bpy.types.Object, image_size: int, bake_path: Path, is_chassis: bool = True) -> None:
    """Create 'Atlas' UV via Smart UV Project and bake Cycles CPU Emit while sampling 'Original' textures."""
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
        linked_img = _find_image_texture(orig_mat)

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

        if mname == "CaarPaint":
            const_color = (0.79, 0.78, 0.73, 1.0)  # Ermine White
            dir_min = 0.83
        elif mname == "Color_2":
            const_color = (0.1065, 0.1870, 0.0707, 1.0)  # Sherwood / Lotus Green stripe
            dir_min = 0.83
        elif mname == "windows":
            const_color = (0.0025, 0.0028, 0.0032, 1.0)  # Opaque black glass
            dir_min = 0.94
        elif mname == "glass_light":
            const_color = (0.72, 0.83, 0.94, 1.0)  # Crystal tinted headlight lens
            dir_min = 0.85
        elif mname == "Ted_glass":
            const_color = (0.80, 0.015, 0.015, 1.0)
        elif mname == "Oraange_glass":
            const_color = (0.82, 0.16, 0.0, 1.0)
        elif mname == "mirrors":
            const_color = (0.76, 0.78, 0.80, 1.0)
            dir_min = 0.90
        elif mname == "Plate":
            const_color = (0.74, 0.74, 0.72, 1.0)
        elif mname == "grille" and linked_img is not None:
            # Blend chrome/silver slats (Alpha=1) over dark radiator backing (Alpha=0)
            tex_g = nt.nodes.new("ShaderNodeTexImage")
            tex_g.image = linked_img
            nt.links.new(uv_orig.outputs["UV"], tex_g.inputs["Vector"])
            mix_g = nt.nodes.new("ShaderNodeMix")
            mix_g.data_type = "RGBA"
            mix_g.inputs["A"].default_value = (0.012, 0.012, 0.015, 1.0)
            mix_g.inputs["B"].default_value = (0.48, 0.50, 0.52, 1.0)
            nt.links.new(tex_g.outputs["Alpha"], mix_g.inputs["Factor"])
            color_socket = mix_g.outputs["Result"]
            dir_min = 0.90
        elif mname == "tire" and linked_img is not None:
            # Shared_Car_Tire_Sport_SSO.png is bright grayscale Forza SSO; tint to dark rubber
            tex_t = nt.nodes.new("ShaderNodeTexImage")
            tex_t.image = linked_img
            nt.links.new(uv_orig.outputs["UV"], tex_t.inputs["Vector"])
            tint_t = nt.nodes.new("ShaderNodeMix")
            tint_t.data_type = "RGBA"
            tint_t.blend_type = "MULTIPLY"
            tint_t.inputs["Factor"].default_value = 1.0
            nt.links.new(tex_t.outputs["Color"], tint_t.inputs["A"])
            tint_t.inputs["B"].default_value = (0.018, 0.019, 0.021, 1.0)
            color_socket = tint_t.outputs["Result"]
            dir_min = 0.88
        elif linked_img is not None:
            tex_src = nt.nodes.new("ShaderNodeTexImage")
            tex_src.image = linked_img
            nt.links.new(uv_orig.outputs["UV"], tex_src.inputs["Vector"])
            color_socket = tex_src.outputs["Color"]
            dir_min = 0.88 if mname in ("metal", "rim") else 0.94

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
    badges_obj: bpy.types.Object,
    chassis_glb: Path,
    wheel_glbs: dict[str, Path],
    dims: dict[str, float],
) -> None:
    ext_min, ext_max = compute_object_bounds(exterior)
    lower_pts = extract_hull_godot(exterior, 0.0, 0.62)
    cabin_pts = extract_hull_godot(exterior, 0.42, 10.0)
    collision_doc = {
        "hulls": [
            {"identifier": "lower", "points": lower_pts},
            {"identifier": "cabin", "points": cabin_pts},
        ],
        "boxes": [],
        "source": f"Generated from {SOURCE_FBX.name} ({exterior.name})",
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
        "fbx": str(SOURCE_FBX),
        "finish": "original_livery_baked_psx_rgb555",
        "fit": (
            f"FINAL_MODEL_65.fbx scaled to metres, rotated +180 deg Z, interior/calipers/discs purged, "
            f"Ermine White CaarPaint + Lotus Green Color_2, crystal headlight lenses, opaque black windows; "
            f"native FBX wheelbase={dims['wheelbase']:.4f} m, tracks={dims['front_track']:.4f}/{dims['rear_track']:.4f} m, "
            f"tire R={radius:.4f} W={width:.4f} m."
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
        "exported_nodes": [exterior.name, badges_obj.name],
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
        "geometry_policy": "fbx_native_dimensions",
        "uniform_scale": 1.0,
        "native_wheelbase_m": dims["wheelbase"],
    }
    manifest["capabilities"]["cockpit"] = False
    manifest["capabilities"]["seats"] = 0
    manifest["capabilities"]["native_arm_poses"] = 0
    manifest["capabilities"]["damage_variants"] = 0
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    # Sync physics JSONs (chassis.json, tires.json) & HISTORICAL_PROVENANCE.json hashes
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
    if not SOURCE_FBX.is_file():
        raise FileNotFoundError(f"Source FBX missing: {SOURCE_FBX}")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(SOURCE_FBX))
    resolve_fbx_images()
    bake_world_scale_and_rotate()

    wheel_objs = separate_quadrant_meshes(bpy.data.objects[TIRE_OBJECT], bpy.data.objects[RIM_OBJECT])
    exterior_list = [bpy.data.objects[name] for name in EXTERIOR_OBJECTS]
    badges_obj = bpy.data.objects[BADGE_OBJECT]
    badges_obj.name = "LotusCortinaBadges"
    badges_obj.data.name = "LotusCortinaBadgesMesh"

    dims = align_native_fbx_origin_and_measure(exterior_list, badges_obj, wheel_objs)
    exterior = join_exterior(exterior_list)

    with tempfile.TemporaryDirectory(prefix="cortina_psx_") as tmp:
        tmp_dir = Path(tmp)
        chassis_raw = tmp_dir / "chassis_bake_1024.png"
        chassis_psx = tmp_dir / "chassis_psx_512.png"
        badges_psx = tmp_dir / "badges_psx_512.png"

        # Hide floating badges and wheels during exterior Cycles bake so they don't cast stray AO
        badges_obj.hide_render = True
        for w in wheel_objs.values():
            w.hide_render = True
        bake_f250_emit_atlas(exterior, 1024, chassis_raw, is_chassis=True)
        badges_obj.hide_render = False
        for w in wheel_objs.values():
            w.hide_render = False

        run_ps1kit_quantize(chassis_raw, chassis_psx, size=(512, 512), dither_strength=0.36)
        chassis_mat = make_psx_material("LotusCortina_PSX", chassis_psx, roughness=0.64, coat=0.08)
        finalize_single_uv_and_material(exterior, "Atlas", chassis_mat)

        run_ps1kit_quantize(SOURCE_DIR / "Badges_D.png", badges_psx, size=(512, 512), dither_strength=0.32, binary_alpha=True)
        badges_mat = make_psx_material("LotusCortina_Badges_PSX", badges_psx, roughness=0.55, coat=0.0, alpha_cutout=True)
        finalize_single_uv_and_material(badges_obj, "Original", badges_mat)

        chassis_glb = OUTPUT_DIR / "chassis.glb"
        export_selected_glb([exterior, badges_obj], chassis_glb)
        patch_glb_nearest_samplers(chassis_glb)
        print(f"[CHASSIS] Exported & patched {chassis_glb.name}")

        # Bake and export each wheel
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
            wmat = make_psx_material(f"CortinaWheel_{key}_PSX", wheel_psx, roughness=0.72, coat=0.0)
            finalize_single_uv_and_material(wobj, "Atlas", wmat)

            out_path = OUTPUT_DIR / f"wheel_{key}.glb"
            export_selected_glb([wobj], out_path)
            patch_glb_nearest_samplers(out_path)
            wheel_glbs[key] = out_path
            wmin2, wmax2 = compute_object_bounds(wobj)
            print(f"[WHEEL {key}] X=[{wmin2.x:.4f},{wmax2.x:.4f}] Y=[{wmin2.y:.4f},{wmax2.y:.4f}] Z=[{wmin2.z:.4f},{wmax2.z:.4f}]")

    build_collision_manifest_and_sync_profile(exterior, badges_obj, chassis_glb, wheel_glbs, dims)


if __name__ == "__main__":
    main()
