import pathlib

p = pathlib.Path("tools/rally_trophy/blender_export.py")
t = p.read_text(encoding="utf-8")
is_crlf = "\r\n" in t
t = t.replace("\r\n", "\n")

target1 = """    if roof_faces:
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
        bs.inputs["Base Color"].default_value = (0.08, 0.075, 0.065, 1)"""

replacement1 = """    if roof_faces:
        roof = subset(body, roof_faces, "interior_roof")
        roof.matrix_world.translation.z -= 0.015
        bm = bmesh.new()
        bm.from_mesh(roof.data)
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
        bm.to_mesh(roof.data)
        bm.free()
        roof.data.materials.clear()
        mat = bpy.data.materials.new("Rally Trophy roof lining")
        mat.use_nodes = True
        mat.use_backface_culling = True
        bs = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bs.inputs["Base Color"].default_value = (0.08, 0.075, 0.065, 1)"""

assert target1 in t, "target1 not found"
t = t.replace(target1, replacement1, 1)

target2 = 'for name in ["steering_wheel_hi", "indicator_rpm", "indicator_speed", "wipers"]:'
replacement2 = 'for name in ["steering_wheel_hi", "indicator_rpm", "indicator_speed", "wipers", "ext_pipe01"]:'

assert target2 in t, "target2 not found"
t = t.replace(target2, replacement2, 1)

if is_crlf:
    t = t.replace("\n", "\r\n")

p.write_text(t, encoding="utf-8")
print("blender_export.py patched successfully")
