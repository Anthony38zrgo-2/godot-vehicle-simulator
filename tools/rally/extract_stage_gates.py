"""Run in Blender: --background --python tools/rally/extract_stage_gates.py -- --fbx PATH --glb PATH --route PATH --output PATH
Recover original hidden timing planes, not arbitrary equal-distance sectors.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import struct
import math
import bpy
from mathutils import Vector

parser = argparse.ArgumentParser()
parser.add_argument("--fbx", type=Path, required=True)
parser.add_argument("--glb", type=Path, required=True)
parser.add_argument("--route", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(args.fbx.resolve()), global_scale=100.0, use_custom_normals=True)
def godot(v):
    return Vector((v.x, v.z, -v.y))
points = [Vector(p) for p in json.loads(args.route.read_text(encoding="utf-8"))["points"]]
original_count = len(points)
# The reset path ends before the finish banner. Extend its last tangent to intersect split_09.
points.append(points[-1] + (points[-1] - points[-2]).normalized() * 100.0)
distances = [0.0]
for a, b in zip(points, points[1:]):
    distances.append(distances[-1] + (b-a).length)
gates = []
for index in range(10):
    name = f"split_{index:02}"
    obj = bpy.data.objects.get(name)
    if obj is None or obj.type != "MESH":
        raise ValueError(f"Original timing mesh missing: {name}")
    vertices = [godot(obj.matrix_world @ v.co) for v in obj.data.vertices]
    center = sum(vertices, Vector()) / len(vertices)
    normal = godot(obj.matrix_world.to_3x3().inverted().transposed() @ obj.data.polygons[0].normal).normalized()
    right = godot(obj.matrix_world.to_3x3().col[0]).normalized()
    up = godot(obj.matrix_world.to_3x3().col[1]).normalized()
    nearest = min(range(len(points)-1), key=lambda i: ((points[i]+points[i+1])*0.5-center).length_squared)
    if normal.dot(points[nearest+1]-points[nearest]) < 0:
        normal = -normal
    width = max(abs((v-center).dot(right)) for v in vertices)
    height = max(abs((v-center).dot(up)) for v in vertices)
    candidates = []
    for i,(a,b) in enumerate(zip(points,points[1:])):
        before,after = (a-center).dot(normal),(b-center).dot(normal)
        if before <= 0 <= after and after-before > 1e-6:
            f = -before/(after-before)
            hit = a.lerp(b,f)
            if abs((hit-center).dot(right)) <= width+1 and abs((hit-center).dot(up)) <= height+1:
                candidates.append(((hit-center).length_squared,i,f,hit))
    if not candidates:
        raise ValueError(f"Route does not intersect {name}")
    _,i,f,hit = min(candidates,key=lambda c:c[0])
    distance = distances[i]+(distances[i+1]-distances[i])*f
    gates.append({"id":name,"kind":"finish" if index==9 else "split","origin":list(center),"forward":list(normal),"right":list(right),"up":list(up),"half_width_m":width,"half_height_m":height,"route_position":list(hit),"route_distance_m":distance,"source_vertices_godot":[list(v) for v in vertices],"source_materials":[m.name for m in obj.data.materials]})
assert all(a["route_distance_m"] < b["route_distance_m"] for a,b in zip(gates,gates[1:]))
# Cross-check source trigger planes against the signs actually rendered in GLB.
raw = args.glb.read_bytes()
json_size = struct.unpack_from("<I", raw, 12)[0]
gltf = json.loads(raw[20:20+json_size])
binary = raw[28+json_size:]
def accessor(index):
    a = gltf["accessors"][index]
    view = gltf["bufferViews"][a["bufferView"]]
    count = {"VEC3": 3, "SCALAR": 1}[a["type"]]
    fmt = {5123: "H", 5125: "I", 5126: "f"}[a["componentType"]]
    stride = view.get("byteStride", struct.calcsize(fmt)*count)
    start = view.get("byteOffset", 0)+a.get("byteOffset", 0)
    return [struct.unpack_from("<"+fmt*count, binary, start+i*stride) for i in range(a["count"])]
markers = {"checkpoint": [], "gate_finish": []}
for mesh in gltf["meshes"]:
    for primitive in mesh["primitives"]:
        material = gltf["materials"][primitive["material"]]["name"]
        if material in markers:
            vertices = accessor(primitive["attributes"]["POSITION"])
            markers[material].extend(vertices[i[0]] for i in accessor(primitive["indices"]))
for gate in gates:
    material = "gate_finish" if gate["kind"] == "finish" else "checkpoint"
    center = gate["route_position"]
    near = [v for v in markers[material] if math.hypot(v[0]-center[0], v[2]-center[2]) < 35]
    if not near:
        raise ValueError(f"No GLB sign near {gate['id']}")
    gap = min(abs(sum((v[k]-gate["origin"][k])*gate["forward"][k] for k in range(3))) for v in near)
    if gap > 3.0:
        raise ValueError(f"GLB/source mismatch at {gate['id']}: {gap} m")
    gate["visual_marker_audit"] = {"material": material, "vertices_within_35m": len(near), "minimum_plane_gap_m": gap}
result={"version":1,"basis":"Original split_00..split_09 hidden timing meshes recovered from the source FBX; Blender Z-up converted to Godot +Y-up. Render GLB omits the trigger meshes but retains checkpoint signs.","source_fbx":str(args.fbx),"source_fbx_sha256":hashlib.sha256(args.fbx.read_bytes()).hexdigest(),"visual_glb_sha256":hashlib.sha256(args.glb.read_bytes()).hexdigest(),"route_sha256":hashlib.sha256(args.route.read_bytes()).hexdigest(),"original_route_point_count":original_count,"gates":gates}
args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print("ORIGINAL_TIMING_GATES",[(g["id"],round(g["route_distance_m"],2)) for g in gates])
