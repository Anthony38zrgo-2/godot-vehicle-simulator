"""Blender worker. Run only through the CLI with a generated job.json.

Never imports an existing car .blend or the user's live Blender session.
"""
from pathlib import Path
import hashlib
import json
import re
import shutil
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector


def world_bounds(obj):
    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    return [min(p[i] for p in points) for i in range(3)], [max(p[i] for p in points) for i in range(3)]


def meshes(root):
    return ([root] if root.type == "MESH" else []) + [o for o in root.children_recursive if o.type == "MESH"]


def components(obj):
    # FBX can duplicate vertices at UV seams; weld in a temporary analysis mesh,
    # retaining original face indices for extraction from the textured source.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    layer = bm.faces.layers.int.new("original_face")
    for i, face in enumerate(bm.faces):
        face[layer] = i
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.00001)
    seen, result = set(), []
    for vertex in bm.verts:
        if vertex in seen:
            continue
        stack, group = [vertex], set()
        seen.add(vertex)
        while stack:
            v = stack.pop()
            group.add(v)
            for edge in v.link_edges:
                other = edge.other_vert(v)
                if other not in seen:
                    stack.append(other)
                    seen.add(other)
        faces = {face for v in group for face in v.link_faces}
        points = [obj.matrix_world @ v.co for v in group]
        result.append({"faces": sorted(f[layer] for f in faces),
                       "min": [min(p[i] for p in points) for i in range(3)],
                       "max": [max(p[i] for p in points) for i in range(3)]})
    bm.free()
    return result


def subset(obj, indices, name):
    result = bpy.data.objects.new(name, obj.data.copy())
    bpy.context.collection.objects.link(result)
    result.matrix_world = obj.matrix_world.copy()
    bm = bmesh.new()
    bm.from_mesh(result.data)
    bm.faces.ensure_lookup_table()
    keep = set(indices)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(result.data)
    bm.free()
    return result


def flatten_parent(obj):
    world = obj.matrix_world.copy()
    obj.parent = None
    obj.matrix_world = world


def main(job_path):
    job = json.loads(Path(job_path).read_text(encoding="utf-8"))
    source, driver, output = (Path(job[k]) for k in ["source_dir", "driver_dir", "asset_dir"])
    recipe, car = job["recipe"], job["car_config"]
    output.mkdir(parents=True, exist_ok=True)
    damage_dir = output / "damage"
    damage_dir.mkdir(exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(source / "model_out.fbx"), global_scale=100.0, use_custom_normals=True)
    bpy.context.view_layer.update()
    print("RT_SOURCE_OBJECTS", [o.name for o in bpy.data.objects if not o.name.startswith("Surface")])
    warnings = []
    aliases = recipe.get("semantic_aliases", {})

    def group(name, required=True):
        root = next((bpy.data.objects.get(n) for n in aliases.get(name, [name]) if bpy.data.objects.get(n)), None)
        if root is None:
            if required:
                raise ValueError(f"Missing semantic object: {name}; supply semantic_aliases in the recipe")
            return None
        parts = meshes(root)
        if not parts:
            if required:
                raise ValueError(f"No geometry below semantic object: {name}")
            return None
        for obj in parts:
            flatten_parent(obj)
        bpy.ops.object.select_all(action="DESELECT")
        for obj in parts:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = parts[0]
        if len(parts) > 1:
            bpy.ops.object.join()
        obj = bpy.context.object
        if root.type != "MESH":
            bpy.data.objects.remove(root, do_unlink=True)
        obj.name = name
        return obj

    panels = recipe.get("body_panels", ["body", "hood", "trunk"])
    exterior = [group(name) for name in panels]
    body = exterior[panels.index("body")]
    interior = group("interior_hi")
    broken = {part: group(part + "_crash") for part in panels}
    wheels = {key: group(name) for key, name in zip(
        ["front_left", "front_right", "rear_left", "rear_right"], ["tire_fl", "tire_fr", "tire_rl", "tire_rr"])}
    pivots = {}
    for key, obj in wheels.items():
        lo, hi = world_bounds(obj)
        center = Vector([(lo[i] + hi[i]) * 0.5 for i in range(3)])
        pivots[key] = {"center_metres": {"x": center.x, "y": center.z, "z": -center.y},
                       "radius_metres": (hi[2] - lo[2]) * 0.5, "width_metres": hi[0] - lo[0]}
        obj.data.transform(obj.matrix_world)
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
        for vertex in obj.data.vertices:
            vertex.co -= center

    displacement = float(car.get("WheelDisplacement", 0.1))
    healthy = exterior + [interior]
    for name in ["steering_wheel_hi", "indicator_rpm", "indicator_speed", "wipers"]:
        obj = group(name, required=name == "steering_wheel_hi")
        if obj:
            healthy.append(obj)
    for obj in healthy + list(broken.values()):
        flatten_parent(obj)
        obj.matrix_world.translation.z += displacement

    low = group("interior_lo", required=False)
    recovered = []
    component_report = components(low) if low else []
    # Explicit per-car selection can override recognition; ambiguous seats fail.
    rules = recipe.get("interior", {})
    seat_faces = rules.get("seat_face_counts", [44])
    for i, item in enumerate(component_report):
        seat = len(item["faces"]) in seat_faces
        cage = len(item["faces"]) == 12 and item["max"][1] < 0 and item["max"][2] - item["min"][2] > 0.025
        if i in rules.get("exclude_components", []):
            continue
        if not (seat or cage or i in rules.get("include_components", [])):
            continue
        name = ("seat_driver" if (item["min"][0] + item["max"][0]) < 0 else "seat_co_driver") if seat else f"roll_cage_{i}"
        obj = subset(low, item["faces"], name)
        obj.matrix_world.translation.z += displacement
        recovered.append(obj)
    Path(job["report_path"]).write_text(json.dumps([{**item, "faces": len(item["faces"])} for item in component_report], indent=2))
    if rules.get("require_seats", True) and not all(any(o.name == name for o in recovered) for name in ["seat_driver", "seat_co_driver"]):
        raise ValueError("Cannot identify both native seats; review component_report.json and recipe interior rules")
    if not any(o.name.startswith("seat_") for o in recovered):
        warnings.append("No separately identifiable native seats in interior_lo; interior_hi retained")
    healthy += recovered

    # Derive an inward-facing lining from real roof faces, avoiding duplicate glass.
    lo, hi = world_bounds(body)
    roof_faces = [f.index for f in body.data.polygons
                  if all((body.matrix_world @ body.data.vertices[v].co).z >= hi[2] - 0.09 for v in f.vertices)
                  and (body.matrix_world.to_3x3() @ f.normal).z > 0.3]
    if roof_faces:
        roof = subset(body, roof_faces, "interior_roof")
        roof.matrix_world.translation.z -= 0.008
        bm = bmesh.new()
        bm.from_mesh(roof.data)
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
        bm.to_mesh(roof.data)
        bm.free()
        roof.data.materials.clear()
        mat = bpy.data.materials.new("Rally Trophy roof lining")
        mat.use_nodes = True
        bs = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bs.inputs["Base Color"].default_value = (0.08, 0.075, 0.065, 1)
        roof.data.materials.append(mat)
        for face in roof.data.polygons:
            face.material_index = 0
        healthy.append(roof)

    # DriverType chooses the original archive. No dependency on a previous Escort export.
    def import_occupant(path, prefix, location):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=str(path), global_scale=100.0, use_custom_normals=True)
        added = list(set(bpy.data.objects) - before)
        for obj in added:
            if not obj.parent:
                obj.location += Vector((location[0], location[2], location[1] + displacement))
            original = obj.name
            obj.name = prefix + "_" + original
        bpy.context.view_layer.update()
        return [o for o in added if o.type == "MESH"]

    for prefix, filename, location in [("Driver", "Driver_out.fbx", car["DriverLoc"]),
                                        ("co_Driver", "co_Driver_out.fbx", car["CoDriverLoc"])]:
        healthy += import_occupant(driver / filename, prefix, location)
    for side in ["left", "right"]:
        poses = import_occupant(driver / f"arm_{side}_lo_static_out.fbx", f"DriverArm_{side}", car["DriverLoc"])
        # Find the frame ancestor before flattening, then bake all source samples.
        ordered = {}
        for obj in poses:
            node = obj
            while node:
                match = re.search(r"frame(\d+)", node.name, re.I)
                if match:
                    ordered[int(match[1])] = obj
                    break
                node = node.parent
        if len(ordered) != 19 or 9 not in ordered:
            raise ValueError(f"Expected 19 original {side} arm frames, found {len(ordered)}")
        base = ordered[9]
        base.name = f"DriverArm_{side}_frame09"
        base.shape_key_add(name="Basis")
        inverse = base.matrix_world.inverted()
        topology = [tuple(f.vertices) for f in base.data.polygons]
        for index in range(19):
            pose = ordered[index]
            if [tuple(f.vertices) for f in pose.data.polygons] != topology:
                raise ValueError("Native arm pose topology differs")
            key = base.shape_key_add(name=f"steer_{index:02}")
            matrix = inverse @ pose.matrix_world
            for vertex, target in zip(pose.data.vertices, key.data):
                target.co = matrix @ vertex.co
        healthy.append(base)
    for obj in healthy:
        flatten_parent(obj)

    # Normalize texture basenames via separators, never Path('//Body.tga').name on Windows.
    texture_index = {p.stem.casefold(): p for folder in [source, driver] for p in folder.glob("*.png")}
    material_report = []
    used = {m for o in healthy + list(wheels.values()) + list(broken.values()) for m in o.data.materials}
    for material in used:
        if material.name == "Rally Trophy roof lining":
            continue
        images = [n.image for n in material.node_tree.nodes if n.type == "TEX_IMAGE" and n.image] if material.node_tree else []
        filename = next((im.filepath.replace("\\", "/").split("/")[-1] for im in images
                         if Path(im.filepath.replace("\\", "/").split("/")[-1]).stem.casefold() in texture_index), None)
        if filename is None:
            raise ValueError(f"Missing diffuse texture: {material.name}; source images {[im.filepath for im in images]}")
        texture = texture_index[Path(filename).stem.casefold()]
        image = bpy.data.images.load(str(texture), check_existing=True)
        image.alpha_mode = "STRAIGHT"
        image.pack()
        material.use_nodes = True
        material.node_tree.nodes.clear()
        nodes, links = material.node_tree.nodes, material.node_tree.links
        shader, output_node, tex = nodes.new("ShaderNodeBsdfPrincipled"), nodes.new("ShaderNodeOutputMaterial"), nodes.new("ShaderNodeTexImage")
        tex.image = image
        links.new(shader.outputs["BSDF"], output_node.inputs["Surface"])
        links.new(tex.outputs["Color"], shader.inputs["Base Color"])
        shader.inputs["Roughness"].default_value = 0.4
        alpha = "window" in material.name.lower() or "tire_alpha" in material.name.lower()
        if alpha:
            links.new(tex.outputs["Alpha"], shader.inputs["Alpha"])
            shader.inputs["Roughness"].default_value = 0.18
        material.use_backface_culling = False if alpha or material.name == "interior_lo" else True
        material_report.append({"name": material.name, "texture": texture.name, "alpha": alpha})

    eye = bpy.data.objects.new("CockpitEye", None)
    bpy.context.collection.objects.link(eye)
    interior_loc = car["InteriorLoc"]
    eye.location = (interior_loc[0], interior_loc[2], interior_loc[1] + displacement)
    damaged_interior = interior.copy()
    damaged_interior.data = interior.data.copy()
    damaged_interior.name = "interior_crash_mesh"
    bpy.context.collection.objects.link(damaged_interior)
    for i, material in enumerate(damaged_interior.data.materials):
        if material.name == "windows":
            copied = material.copy()
            copied.name = "windshield_interior"
            damaged_interior.data.materials[i] = copied
    for part, obj in broken.items():
        obj.name = part + "_crash_mesh"

    scale = 1.0
    raw_wheelbase = pivots["rear_left"]["center_metres"]["z"] - pivots["front_left"]["center_metres"]["z"]
    if recipe["geometry_policy"] == "historical_uniform":
        scale = float(job["historical_wheelbase_m"]) / raw_wheelbase
        for obj in healthy + list(broken.values()) + [damaged_interior, eye]:
            obj.matrix_world = Matrix.Diagonal((scale, scale, scale, 1)) @ obj.matrix_world
        for obj in wheels.values():
            obj.data.transform(Matrix.Scale(scale, 4))
        for pivot in pivots.values():
            pivot["center_metres"] = {k: v * scale for k, v in pivot["center_metres"].items()}
            pivot["radius_metres"] *= scale
            pivot["width_metres"] *= scale
    elif recipe["geometry_policy"] != "native":
        raise ValueError("Unknown geometry policy")

    def artifact(objects, path):
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.hide_set(False)
            obj.hide_render = False
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
                                  export_morph=True, export_animations=False)
        return {"path": path.relative_to(output).as_posix(), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "size_bytes": path.stat().st_size}

    chassis = artifact(healthy + [eye], output / "chassis.glb")
    wheel_files = {key: artifact([obj], output / ("wheel_" + key + ".glb")) for key, obj in wheels.items()}
    crash = artifact(list(broken.values()) + [damaged_interior], damage_dir / "damage.glb")
    damage_files = {}
    for name in ["windows_damaged", "interior_windows_damaged", "lights_damaged"]:
        destination = damage_dir / (name + ".png")
        shutil.copyfile(source / (name + ".png"), destination)
        damage_files[destination.relative_to(output).as_posix()] = {"sha256": hashlib.sha256(destination.read_bytes()).hexdigest()}
    damage_files[crash["path"]] = {"sha256": crash["sha256"]}

    proxy = group("collision", required=recipe.get("collision_source") != "exterior")
    if proxy:
        proxy_points = [proxy.matrix_world @ v.co for v in proxy.data.vertices]
        collision_source = "Decoded model.BMF collision helper"
    else:
        proxy_points = [(obj.matrix_world @ v.co) / scale - Vector((0, 0, displacement))
                        for obj in exterior for v in obj.data.vertices]
        collision_source = "Estimated convex hulls from exterior meshes; model.BMF has no collision helper"
        warnings.append(collision_source)
    midpoint = (min(p.z for p in proxy_points) + max(p.z for p in proxy_points)) * 0.5
    hulls = []
    for name, predicate in [("lower", lambda p: p.z <= midpoint + 0.15), ("cabin", lambda p: p.z >= midpoint - 0.15)]:
        bm = bmesh.new()
        for point in proxy_points:
            if predicate(point):
                bm.verts.new((point.x * scale, max((point.z + displacement) * scale, 0.15), -point.y * scale))
        if len(bm.verts) >= 4:
            bmesh.ops.convex_hull(bm, input=list(bm.verts))
            vs = {v for f in bm.faces for v in f.verts}
            hulls.append({"identifier": name, "points": [dict(zip("xyz", v.co)) for v in vs]})
        bm.free()
    if not hulls:
        raise ValueError("No collision proxy hulls")
    collision_path = output / "collision.json"
    collision_path.write_text(json.dumps({"hulls": hulls, "boxes": [], "source": collision_source}, indent=2) + "\n")
    fp, rp = (pivots[key]["center_metres"] for key in ["front_left", "rear_left"])
    geometry = {"wheelbase": rp["z"] - fp["z"], "front_axle_z": fp["z"], "rear_axle_z": rp["z"],
                "front_track": pivots["front_right"]["center_metres"]["x"] - fp["x"],
                "rear_track": pivots["rear_right"]["center_metres"]["x"] - rp["x"]}
    all_points = [obj.matrix_world @ vertex.co for obj in healthy for vertex in obj.data.vertices]
    bounds = {"min_godot": [min(p.x for p in all_points), min(p.z for p in all_points), min(-p.y for p in all_points)],
              "max_godot": [max(p.x for p in all_points), max(p.z for p in all_points), max(-p.y for p in all_points)]}
    manifest = {"contract_version": 1, "vehicle_id": recipe["id"], "source": job["provenance"],
        "coordinate_system": {"forward": "-Z", "right": "+X", "up": "+Y", "visual_physics_offset_metres": 0},
        "chassis": chassis, "wheels": wheel_files, "wheel_pivots": pivots, "geometry": geometry,
        "collision": {"path": "collision.json", "sha256": hashlib.sha256(collision_path.read_bytes()).hexdigest()},
        "visual_damage": {"files": damage_files}, "bounds_world_metres": bounds,
        "measurement": {"geometry_policy": recipe["geometry_policy"], "uniform_scale": scale, "native_wheelbase_m": raw_wheelbase},
        "capabilities": {"cockpit": True, "native_arm_poses": 19, "seats": sum(o.name.startswith("seat_") for o in recovered),
                         "recovered_components": len(recovered), "damage_variants": len(broken) + 1}, "warnings": warnings}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    report = {"geometry": geometry, "materials": material_report, "interior_components": component_report,
              "healthy_nodes": [o.name for o in healthy], "warnings": warnings}
    Path(job["report_path"]).write_text(json.dumps(report, indent=2) + "\n")
    if job.get("save_blend"):
        visible = set(healthy + [eye] + list(wheels.values()))
        for obj in bpy.data.objects:
            if obj.type == "MESH" and obj not in visible:
                obj.hide_set(True)
                obj.hide_render = True
        for image in list(bpy.data.images):
            if image.source == "FILE" and not image.packed_file and not Path(bpy.path.abspath(image.filepath)).exists():
                bpy.data.images.remove(image)
        bpy.ops.file.pack_all()
        bpy.ops.wm.save_as_mainfile(filepath=job["save_blend"])
    print("RT_EXPORT_SUCCESS " + recipe["id"])


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1])
