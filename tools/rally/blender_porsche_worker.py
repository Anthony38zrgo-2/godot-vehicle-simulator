"""
Blender worker script for Porsche 356A 1600GS Carrera GT import into Godot.
Executes within Blender headless session.
"""
import sys
import os
import json
import math
import shutil
from pathlib import Path

import bpy
import bmesh
from mathutils import Matrix, Vector

# 180-degree rotation around Blender Z axis:
# In original blend: Front=-Y, Rear=+Y, Left=+X, Right=-X, Up=+Z.
# After R180 in Blender: Front=+Y, Rear=-Y, Left=-X, Right=+X, Up=+Z.
# Standard glTF exporter (export_yup=True) converts Blender (X, Y, Z) to Godot (X, Z, -Y):
# Godot Left=-X, Right=+X, Up=+Y, Front=-Z, Rear=+Z.
R180 = Matrix([
    [-1.0,  0.0,  0.0,  0.0],
    [ 0.0, -1.0,  0.0,  0.0],
    [ 0.0,  0.0,  1.0,  0.0],
    [ 0.0,  0.0,  0.0,  1.0]
])

def apply_transform(obj):
    """Bake world transform rotated by R180 into mesh data and reset matrix_world to identity."""
    world_rotated = R180 @ obj.matrix_world
    obj.data.transform(world_rotated)
    obj.parent = None
    obj.matrix_world = Matrix.Identity(4)

def join_objects(objs, new_name):
    if not objs:
        return None
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    res = bpy.context.object
    res.name = new_name
    return res

def simplify_hull_points(points, max_points=20):
    """Reduces convex hull vertex count to a clean compact polygon."""
    if len(points) <= max_points:
        return points
    # Use bounding box and extreme directional points
    selected = []
    # 6 cardinal extrema
    for axis in range(3):
        selected.append(min(points, key=lambda p: p[axis]))
        selected.append(max(points, key=lambda p: p[axis]))
    # 8 corner extrema
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                selected.append(max(points, key=lambda p: sx*p[0] + sy*p[1] + sz*p[2]))
    # Remove duplicates preserving order
    unique = []
    for p in selected:
        if not any(all(math.isclose(p[i], u[i], abs_tol=1e-3) for i in range(3)) for u in unique):
            unique.append(p)
    return unique if len(unique) >= 4 else points[:max_points]

def bake_paint_materials():
    """Flatten the source paint and projected decals into glTF base color maps."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 6
    for obj in list(scene.objects):
        if obj.type != "MESH" or len(obj.data.materials) != 1:
            continue
        material = obj.data.materials[0]
        if not material or not (material.name.startswith("Ruby Red |") or material.name in {"Body", "BodyInt"}):
            continue
        material = material.copy()
        obj.data.materials[0] = material
        tree = material.node_tree
        nodes = tree.nodes
        shader = nodes.get("Principled BSDF")
        original_uv = next(uv for uv in obj.data.uv_layers if uv.active_render)
        uv = nodes.new("ShaderNodeUVMap")
        uv.uv_map = original_uv.name
        for node in list(nodes):
            if node.type == "TEX_IMAGE" and not node.inputs["Vector"].is_linked:
                tree.links.new(uv.outputs["UV"], node.inputs["Vector"])
            if node.type == "TEX_COORD":
                for link in list(node.outputs["UV"].links):
                    tree.links.new(uv.outputs["UV"], link.to_socket)
        obj.data.uv_layers.active = original_uv
        bake_uv = obj.data.uv_layers.new(name="RallyColor", do_init=True)
        bake_uv_name = bake_uv.name
        obj.data.uv_layers.active = bake_uv
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        if material.name.startswith("Ruby Red |") or material.name.startswith("BodyInt"):
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.uv.smart_project(island_margin=0.015)
            bpy.ops.object.mode_set(mode="OBJECT")
        resolution = 2048 if obj.name == "356Body" else 1024
        image = bpy.data.images.new("RallyColor_" + obj.name, resolution, resolution, alpha=False)
        target = nodes.new("ShaderNodeTexImage")
        target.image = image
        nodes.active = target
        source = shader.inputs["Base Color"].links[0].from_socket
        emission = nodes.new("ShaderNodeEmission")
        tree.links.new(source, emission.inputs["Color"])
        surface = nodes.get("Material Output").inputs["Surface"]
        tree.links.new(emission.outputs[0], surface)
        bpy.ops.object.bake(type="EMIT", uv_layer=bake_uv_name, margin=12)
        image.pack()
        tree.links.new(shader.outputs["BSDF"], surface)
        uv_baked = nodes.new("ShaderNodeUVMap")
        uv_baked.uv_map = bake_uv_name
        tree.links.new(uv_baked.outputs["UV"], target.inputs["Vector"])
        tree.links.new(target.outputs["Color"], shader.inputs["Base Color"])
        print("Baked paint:", obj.name, flush=True)


def process(job_json_path):
    with open(job_json_path, "r", encoding="utf-8") as f:
        job = json.load(f)

    output_dir = Path(job["output_dir"])
    output_dir.mkdir(parents=True, exist_ok=True)
    damage_dir = output_dir / "damage"
    damage_dir.mkdir(parents=True, exist_ok=True)

    print("=== Processing Porsche 356A in Blender (R180 glTF coordinate pipeline) ===")

    bake_paint_materials()

    # 1. Wheels extraction
    wheel_groups = {
        "front_left": ["P550TYRE_LF", "P550RIM_LF", "Wheel_Cap_Nut_Valve_LF"],
        "front_right": ["P550TYRE_RF", "P550RIM_RF", "Wheel_Cap_Nut_Valve_RF"],
        "rear_left": ["P550TYRE_LR", "P550RIM_LR", "Wheel_Cap_Nut_Valve_LR"],
        "rear_right": ["P550TYRE_RR", "P550RIM_RR", "Wheel_Cap_Nut_Valve_RR"]
    }

    pivots = {}
    wheel_objects = {}

    for key, mesh_names in wheel_groups.items():
        objs = [bpy.data.objects.get(name) for name in mesh_names if bpy.data.objects.get(name)]
        all_pts_blender = []
        for o in objs:
            all_pts_blender.extend([R180 @ (o.matrix_world @ v.co) for v in o.data.vertices])

        min_b = Vector([min(p[i] for p in all_pts_blender) for i in range(3)])
        max_b = Vector([max(p[i] for p in all_pts_blender) for i in range(3)])
        center_b = (min_b + max_b) * 0.5
        radius = (max_b.z - min_b.z) * 0.5
        width = max_b.x - min_b.x

        # glTF mapping: Godot X = Blender X, Godot Y = Blender Z, Godot Z = -Blender Y
        center_godot = Vector((center_b.x, center_b.z, -center_b.y))

        pivots[key] = {
            "center_metres": {"x": float(center_godot.x), "y": float(center_godot.y), "z": float(center_godot.z)},
            "radius_metres": float(radius),
            "width_metres": float(width)
        }

        # Standalone wheel glb: duplicate meshes, center at (0,0,0) in Blender
        dup_objs = []
        for o in objs:
            d = o.copy()
            d.data = o.data.copy()
            bpy.context.collection.objects.link(d)
            # Apply R180 world transform
            d.data.transform(R180 @ o.matrix_world)
            d.parent = None
            d.matrix_world = Matrix.Identity(4)
            # Center vertices around (0,0,0)
            for v in d.data.vertices:
                v.co -= center_b
            dup_objs.append(d)

        wheel_joined = join_objects(dup_objs, f"wheel_{key}")
        wheel_objects[key] = wheel_joined

        # Export wheel glb
        wheel_glb_path = output_dir / f"wheel_{key}.glb"
        bpy.ops.object.select_all(action="DESELECT")
        wheel_joined.select_set(True)
        bpy.context.view_layer.objects.active = wheel_joined
        bpy.ops.export_scene.gltf(
            filepath=str(wheel_glb_path),
            use_selection=True,
            export_format='GLB',
            export_morph=False,
            export_animations=False
        )
        print(f"Exported wheel_{key}.glb: godot_center={center_godot}")

    # 2. Driver & Co-Driver
    driver_head = bpy.data.objects.get("Piloto | Driver_driver_head")
    driver_body = bpy.data.objects.get("Piloto | Driver_driver_body")
    if driver_head:
        apply_transform(driver_head)
        driver_head.name = "Driver_driver_head"
    if driver_body:
        apply_transform(driver_body)
        driver_body.name = "Driver_driver_body"

    co_driver_head = bpy.data.objects.get("Copiloto | co_Driver_co_driver_head")
    co_driver_s1 = bpy.data.objects.get("Copiloto | co_Driver_Surface1")
    co_driver_s2 = bpy.data.objects.get("Copiloto | co_Driver_Surface2")
    if co_driver_head:
        apply_transform(co_driver_head)
        co_driver_head.name = "co_Driver_co_driver_head"
    if co_driver_s1:
        apply_transform(co_driver_s1)
        co_driver_s1.name = "co_Driver_Surface1"
    if co_driver_s2:
        apply_transform(co_driver_s2)
        co_driver_s2.name = "co_Driver_Surface2"

    # 3. Driver Arms with Shape Keys
    arm_l = bpy.data.objects.get("Piloto | DriverArm_left_frame09")
    arm_r = bpy.data.objects.get("Piloto | DriverArm_right_frame09")

    for arm, side in [(arm_l, "left"), (arm_r, "right")]:
        if not arm:
            continue
        m_orig = arm.matrix_world.copy()
        keys = arm.data.shape_keys.key_blocks

        source_keys = {}
        for idx in range(19):
            kname = f"steer_{idx:02d}"
            if kname in keys:
                source_keys[idx] = [R180 @ (m_orig @ v.co) for v in keys[kname].data]

        neutral_pts = source_keys.get(9)

        if arm.data.shape_keys:
            for kb in list(arm.data.shape_keys.key_blocks):
                arm.shape_key_remove(kb)

        for i, pt in enumerate(neutral_pts):
            arm.data.vertices[i].co = pt
        arm.parent = None
        arm.matrix_world = Matrix.Identity(4)

        arm.shape_key_add(name="Basis")
        for idx in range(19):
            src_idx = (18 - idx) if side == "left" else idx
            target_pts = source_keys[src_idx]
            kb = arm.shape_key_add(name=f"steer_{idx:02d}")
            for v_idx, pt in enumerate(target_pts):
                kb.data[v_idx].co = pt

        arm.name = f"DriverArm_{side}_frame09"
        print(f"Baked shape keys for DriverArm_{side}_frame09 (inverted={side == 'left'})")

    # 4. Steering Wheel Node
    steer_mesh_names = ["SteeringOuter&HornButton", "SteeringSpoke", "SteeringCenter", "SteeringHornButtonCrome", "LogoNardi"]
    steer_objs = [bpy.data.objects.get(n) for n in steer_mesh_names if bpy.data.objects.get(n)]
    for o in steer_objs:
        apply_transform(o)
    steer_joined = join_objects(steer_objs, "steering_wheel_hi")

    # Circle fit of the outer rim vertices after R180, excluding the hub.
    c_b = Vector((-0.255833, 0.229028, 0.813529))
    # Shaft points towards driver in Blender: -Y and +Z
    z_b = Vector((-0.018533, -0.965750, 0.258810)).normalized()
    y_b = Vector((0.0, 0.0, 1.0)).normalized()
    x_b = y_b.cross(z_b).normalized()
    y_b = z_b.cross(x_b).normalized()

    basis_mat = Matrix([
        [x_b.x, y_b.x, z_b.x, c_b.x],
        [x_b.y, y_b.y, z_b.y, c_b.y],
        [x_b.z, y_b.z, z_b.z, c_b.z],
        [0.0,   0.0,   0.0,   1.0]
    ])
    inv_basis = basis_mat.inverted()
    steer_joined.data.transform(inv_basis)
    steer_joined.matrix_world = basis_mat
    print("Configured steering_wheel_hi with rest basis aligned to steering column.")

    # 5. CockpitEye empty
    eye = bpy.data.objects.new("CockpitEye", None)
    bpy.context.collection.objects.link(eye)
    # Driver eye position in Blender: X=-0.2526, Y=-0.20, Z=1.08
    # GlTF exporter maps this to Godot (-0.2526, 1.08, 0.20)
    eye.location = Vector((-0.2526, -0.20, 1.08))

    # 6. Separate Panels: Body, Hood, Trunk, Interior_hi
    hood_mesh = bpy.data.objects.get("FrontHood")
    if hood_mesh:
        apply_transform(hood_mesh)
        hood_mesh.name = "hood"

    trunk_mesh_names = ["RearDeckLid", "RearDecikGrill", "ExtRubber_RearDeckGrill"]
    trunk_objs = [bpy.data.objects.get(n) for n in trunk_mesh_names if bpy.data.objects.get(n)]
    for o in trunk_objs:
        apply_transform(o)
    trunk_mesh = join_objects(trunk_objs, "trunk")

    # Interior meshes
    interior_names = [
        "BodyInt", "IntAluminum", "IntCarpet", "IntChrome", "IntDoorLeverBase_L", "IntDoorLeverBase_R",
        "IntDoorLever_L", "IntDoorLever_R", "IntDoorPad_L", "IntDoorPad_R", "IntDoorPanel&Strap_L",
        "IntDoorPanel&Strap_R", "IntDoorRubber_L", "IntDoorRubber_R", "IntMirror",
        "IntPlastic-Knobs&SteeringPost", "IntRubberMatPedals&CenterTunnel", "Leather", "MeterBoard",
        "MeterNeedleFuel", "MeterNeedleSpeedo", "MeterNeedleTach", "MeterNeedleTemp", "Seatbelt",
        "BeltMetal_L_On", "Belt_L_On", "Belt_L_On_Logo", "ShifterKnob&Rod", "ShifterRodBoot",
        "GlassRear&QuaterWindowInt", "Glass_Flat_Door_LInt", "Glass_Flat_Door_RInt", "GlassFrWindShieldInt"
    ]
    interior_objs = [bpy.data.objects.get(n) for n in interior_names if bpy.data.objects.get(n)]
    
    # Configure front interior windshield material to "windows" on GlassFrWindShieldInt
    g_int = bpy.data.objects.get("GlassFrWindShieldInt")
    if g_int:
        if g_int.data.materials and g_int.data.materials[0]:
            mat_win = g_int.data.materials[0].copy()
            mat_win.name = "windows"
        else:
            mat_win = bpy.data.materials.new(name="windows")
            mat_win.use_nodes = True
        g_int.data.materials.clear()
        g_int.data.materials.append(mat_win)

    for o in interior_objs:
        apply_transform(o)
    interior_mesh = join_objects(interior_objs, "interior_hi")

    # Headlight materials and Front windshield on Body
    hl = bpy.data.objects.get("HeadLightLense")
    if hl:
        apply_transform(hl)
        orig_lense_mat = hl.data.materials[0] if hl.data.materials else None
        if orig_lense_mat:
            mat_left = orig_lense_mat.copy()
            mat_left.name = "#E1 headlight_left"
            mat_right = orig_lense_mat.copy()
            mat_right.name = "#E1 headlight_right"
        else:
            mat_left = bpy.data.materials.new(name="#E1 headlight_left")
            mat_left.use_nodes = True
            mat_right = bpy.data.materials.new(name="#E1 headlight_right")
            mat_right.use_nodes = True
        hl.data.materials.clear()
        hl.data.materials.append(mat_left)
        hl.data.materials.append(mat_right)
        for poly in hl.data.polygons:
            poly_x = sum(hl.data.vertices[v].co.x for v in poly.vertices) / len(poly.vertices)
            poly.material_index = 0 if poly_x < 0 else 1

    gw = bpy.data.objects.get("GlassFrWindShieldRear&Quater")
    if gw:
        apply_transform(gw)
        orig_pg_mat = gw.data.materials[0] if gw.data.materials else None
        if orig_pg_mat:
            mat_wf = orig_pg_mat.copy()
            mat_wf.name = "#E1 window front"
        else:
            mat_wf = bpy.data.materials.new(name="#E1 window front")
            mat_wf.use_nodes = True
        gw.data.materials.append(mat_wf)
        wf_idx = len(gw.data.materials) - 1
        for poly in gw.data.polygons:
            poly_y = sum(gw.data.vertices[v].co.y for v in poly.vertices) / len(poly.vertices)
            if poly_y > 0.1:  # front windshield in Blender after R180 is Y > 0.1
                poly.material_index = wf_idx

    body_names = [
        "356Body", "Chassis", "DOOR_L", "DOOR_R", "DoorLatch_L", "DoorLatch_R", "Engine", "Exhaust",
        "Fanbelt", "ExtAluminum", "ExtAluminumTrim_Door_L", "ExtAluminumTrim_Door_R", "ExtChrome",
        "ExtCromeTrime_Door_L", "ExtCromeTrime_Door_R", "ExtLense", "ExtLogo-Emblem", "ExtRubber",
        "ExtRubber_Door_L", "ExtRubber_Door_R", "FrontBumper", "FrontBumperRetainer", "FrontBumperRubber",
        "FrontBumperTrim", "RearBumper", "RearBumperRetainer", "RearBumperRubber", "RearBumperTrim",
        "HeadLightBulb", "HeadLightHousing", "HeadLightReflector", "HeadLightTapeBase", "Mirror_Side",
        "ShockAbsorber&Transmission", "Spindle_LF", "Spindle_LR", "Spindle_RF", "Spindle_RR",
        "HUB_LR", "HUB_RR", "TailLight-BlakeBulb", "TailLightBulb", "TurnSignalBulb", "Vinyl",
        "WiperBlade_L", "WiperBlade_R", "Wiper_L", "Wiper_R", "Glass_Flat_Door_L", "Glass_Flat_Door_R",
        "PorscheCrest", "PorscheCrestBase", "PorscheCrestBaseRubber"
    ]
    if hl:
        body_names.append(hl.name)
    if gw:
        body_names.append(gw.name)

    body_objs = [bpy.data.objects.get(n) for n in body_names if bpy.data.objects.get(n)]
    for o in body_objs:
        if o != hl and o != gw:
            apply_transform(o)
    body_mesh = join_objects(body_objs, "body")

    # Clean up leftover wheel duplicate objects from the scene before export
    for o in list(wheel_objects.values()):
        if o.name in bpy.data.objects:
            bpy.data.objects.remove(o, do_unlink=True)

    # 7. Generate Damage Meshes (body_crash_mesh, hood_crash_mesh, trunk_crash_mesh, interior_crash_mesh)
    print("Generating visual damage meshes...")

    # Body crash
    body_crash = body_mesh.copy()
    body_crash.data = body_mesh.data.copy()
    body_crash.name = "body_crash_mesh"
    bpy.context.collection.objects.link(body_crash)
    for v in body_crash.data.vertices:
        if v.co.y > 1.1:  # front crumple in Blender (+Y is front)
            dy = v.co.y - 1.1
            v.co.y -= dy * 0.28
            v.co.z += (v.co.z - 0.5) * 0.15
        elif v.co.y < -0.8:  # rear crumple in Blender (-Y is rear)
            dy = -0.8 - v.co.y
            v.co.y += dy * 0.22
            v.co.z += (v.co.z - 0.5) * 0.10

    # Hood crash
    hood_crash = hood_mesh.copy()
    hood_crash.data = hood_mesh.data.copy()
    hood_crash.name = "hood_crash_mesh"
    bpy.context.collection.objects.link(hood_crash)
    for v in hood_crash.data.vertices:
        if v.co.y > 0.9:
            dy = v.co.y - 0.9
            v.co.y -= dy * 0.35
            v.co.z += 0.08 * (1.0 - min(abs(v.co.x) / 0.7, 1.0))

    # Trunk crash
    trunk_crash = trunk_mesh.copy()
    trunk_crash.data = trunk_mesh.data.copy()
    trunk_crash.name = "trunk_crash_mesh"
    bpy.context.collection.objects.link(trunk_crash)
    for v in trunk_crash.data.vertices:
        if v.co.y < -0.7:
            dy = -0.7 - v.co.y
            v.co.y += dy * 0.25
            v.co.z += 0.06

    # Interior crash: replace "windows" material slot with "windshield_interior"
    int_crash = interior_mesh.copy()
    int_crash.data = interior_mesh.data.copy()
    int_crash.name = "interior_crash_mesh"
    bpy.context.collection.objects.link(int_crash)
    
    mat_wi = bpy.data.materials.new(name="windshield_interior")
    mat_wi.use_nodes = True
    replaced = False
    for i, m in enumerate(int_crash.data.materials):
        if m and m.name == "windows":
            int_crash.data.materials[i] = mat_wi
            replaced = True
            break
    if not replaced:
        int_crash.data.materials.append(mat_wi)

    # Export damage.glb
    damage_glb_path = damage_dir / "damage.glb"
    bpy.ops.object.select_all(action="DESELECT")
    for o in [body_crash, hood_crash, trunk_crash, int_crash]:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=str(damage_glb_path),
        use_selection=True,
        export_format='GLB',
        export_morph=False,
        export_animations=False
    )
    print("Exported damage.glb")

    # Remove crash meshes from scene before exporting chassis.glb
    for o in [body_crash, hood_crash, trunk_crash, int_crash]:
        bpy.data.objects.remove(o, do_unlink=True)

    # 8. Export chassis.glb
    chassis_glb_path = output_dir / "chassis.glb"
    bpy.ops.object.select_all(action="DESELECT")
    healthy_objs = [
        body_mesh, hood_mesh, trunk_mesh, interior_mesh, steer_joined, eye,
        driver_head, driver_body, arm_l, arm_r,
        co_driver_head, co_driver_s1, co_driver_s2
    ]
    for o in healthy_objs:
        if o and o.name in bpy.data.objects:
            o.select_set(True)

    bpy.ops.export_scene.gltf(
        filepath=str(chassis_glb_path),
        use_selection=True,
        export_format='GLB',
        export_morph=True,
        export_animations=False
    )
    print("Exported chassis.glb")

    # 9. Collision hulls in Godot coordinates (lower and cabin)
    print("Computing simplified collision hulls...")
    # Convert points from Blender (x, y, z) to Godot (x, z, -y)
    ext_godot_pts = []
    for o in [body_mesh, hood_mesh, trunk_mesh]:
        ext_godot_pts.extend([(v.co.x, v.co.z, -v.co.y) for v in o.data.vertices])

    midpoint_y = (min(p[1] for p in ext_godot_pts) + max(p[1] for p in ext_godot_pts)) * 0.5
    hulls = []

    # Lower hull (below midpoint Y)
    lower_pts = [p for p in ext_godot_pts if p[1] <= midpoint_y + 0.12]
    simplified_lower = simplify_hull_points(lower_pts, max_points=18)
    hulls.append({
        "identifier": "lower",
        "points": [{"x": float(p[0]), "y": float(p[1]), "z": float(p[2])} for p in simplified_lower]
    })

    # Cabin hull (above midpoint Y and between firewall and rear lid)
    cabin_pts = [p for p in ext_godot_pts if p[1] >= midpoint_y - 0.12 and -0.8 <= p[2] <= 0.9]
    simplified_cabin = simplify_hull_points(cabin_pts, max_points=14)
    hulls.append({
        "identifier": "cabin",
        "points": [{"x": float(p[0]), "y": float(p[1]), "z": float(p[2])} for p in simplified_cabin]
    })

    collision_path = output_dir / "collision.json"
    collision_data = {
        "hulls": hulls,
        "boxes": [],
        "source": "Simplified Porsche 356A exterior collision hulls"
    }
    with open(collision_path, "w", encoding="utf-8") as f:
        json.dump(collision_data, f, indent=2)
    print(f"Exported collision.json with {len(hulls)} hulls ({len(simplified_lower)} lower, {len(simplified_cabin)} cabin points)")

    # 10. Copy damaged window textures from fulvia
    repo_root = Path(job.get("repo_root", "d:/rust-godot-vehicle-simulator"))
    fulvia_damage_dir = repo_root / "game/assets/rally/rt/rt-lancia-fulvia/damage"
    for tex_name in ["windows_damaged.png", "interior_windows_damaged.png", "lights_damaged.png"]:
        src_tex = fulvia_damage_dir / tex_name
        dst_tex = damage_dir / tex_name
        if src_tex.exists():
            shutil.copyfile(src_tex, dst_tex)
            print(f"Copied {tex_name}")

    # 11. Geometry & Bounds calculation in Godot coordinates
    fp = pivots["front_left"]["center_metres"]
    rp = pivots["rear_left"]["center_metres"]
    wheelbase = rp["z"] - fp["z"]
    front_track = pivots["front_right"]["center_metres"]["x"] - fp["x"]
    rear_track = pivots["rear_right"]["center_metres"]["x"] - rp["x"]

    # Bounds of healthy chassis meshes in Godot coordinates
    all_healthy_godot = [(v.co.x, v.co.z, -v.co.y) for o in healthy_objs if o and o.type == 'MESH' for v in o.data.vertices]
    bounds = {
        "min_godot": [min(p[0] for p in all_healthy_godot), min(p[1] for p in all_healthy_godot), min(p[2] for p in all_healthy_godot)],
        "max_godot": [max(p[0] for p in all_healthy_godot), max(p[1] for p in all_healthy_godot), max(p[2] for p in all_healthy_godot)]
    }
    geometry = {
        "wheelbase": float(wheelbase),
        "front_axle_z": float(fp["z"]),
        "rear_axle_z": float(rp["z"]),
        "front_track": float(front_track),
        "rear_track": float(rear_track)
    }

    # 12. Write manifest.json
    import hashlib
    def get_sha256(path):
        return hashlib.sha256(Path(path).read_bytes()).hexdigest()

    manifest = {
        "contract_version": 1,
        "vehicle_id": "rt-porsche-356a",
        "source": {
            "source_blend": "Porsche_356A_Carrera_GT_Ruby_Red.blend",
            "credits": "Ensyuya (Mitsunari Ishii) & Patrice Cote"
        },
        "coordinate_system": {
            "forward": "-Z",
            "right": "+X",
            "up": "+Y",
            "visual_physics_offset_metres": 0
        },
        "chassis": {
            "path": "chassis.glb",
            "sha256": get_sha256(chassis_glb_path),
            "size_bytes": chassis_glb_path.stat().st_size
        },
        "wheels": {
            key: {
                "path": f"wheel_{key}.glb",
                "sha256": get_sha256(output_dir / f"wheel_{key}.glb"),
                "size_bytes": (output_dir / f"wheel_{key}.glb").stat().st_size
            } for key in wheel_groups.keys()
        },
        "wheel_pivots": pivots,
        "geometry": geometry,
        "collision": {
            "path": "collision.json",
            "sha256": get_sha256(collision_path)
        },
        "visual_damage": {
            "files": {
                "damage/damage.glb": {"sha256": get_sha256(damage_glb_path)},
                "damage/windows_damaged.png": {"sha256": get_sha256(damage_dir / "windows_damaged.png")},
                "damage/interior_windows_damaged.png": {"sha256": get_sha256(damage_dir / "interior_windows_damaged.png")},
                "damage/lights_damaged.png": {"sha256": get_sha256(damage_dir / "lights_damaged.png")}
            }
        },
        "bounds_world_metres": bounds,
        "measurement": {
            "geometry_policy": "native",
            "uniform_scale": 1.0,
            "native_wheelbase_m": float(wheelbase)
        },
        "capabilities": {
            "cockpit": True,
            "native_arm_poses": 19,
            "seats": 2,
            "damage_variants": 4
        },
        "warnings": []
    }

    with open(output_dir / "manifest.json", "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    print("Exported asset manifest.json successfully!")

if __name__ == "__main__":
    job_path = sys.argv[-1]
    process(job_path)
