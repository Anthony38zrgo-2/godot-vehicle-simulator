"""Build the Raura Stage 2 driving pilot from the approved GIS review."""
import hashlib
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.geometry import delaunay_2d_cdt

BASE = Path(__file__).resolve().parent
GAME = BASE.parents[3] / "game"
TRACK = "raura_stage2"
ASSETS = GAME / "assets/rally" / TRACK
OUT = BASE / "output"
SOURCE = OUT / "scene_input.json"


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf8")


def smooth(values, radius):
    return [
        sum(values[j] * (radius + 1 - abs(i - j))
            for j in range(max(0, i - radius), min(len(values), i + radius + 1)))
        / sum(radius + 1 - abs(i - j)
              for j in range(max(0, i - radius), min(len(values), i + radius + 1)))
        for i in range(len(values))
    ]


def material(name, color):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    return m


def mesh(name, vertices, faces, mat, collection):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    data.materials.append(mat)
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    return obj


def inside(point, polygon):
    x, y = point
    hit = False
    for (ax, ay), (bx, by) in zip(polygon, polygon[1:] + polygon[:1]):
        if (ay > y) != (by > y) and x < ax + (bx - ax) * (y - ay) / (by - ay):
            hit = not hit
    return hit


def godot(point):
    return [point[0], point[2], -point[1]]


def main():
    if (OUT / "raura_stage2.blend").exists():
        raise SystemExit("El Stage 2 completo ya existe. Usa generar_stage2.py para regenerarlo.")
    data = json.loads(SOURCE.read_text(encoding="utf8"))
    assert all(p is not None for p in data["route"]), "The approved axis contains missing elevations"
    source = [Vector(p) for p in data["route"]]
    distances = [0.0]
    for a, b in zip(source, source[1:]):
        distances.append(distances[-1] + (b - a).xy.length)
    # Keep a short lead-in before the pilot start and end at the approved finish.
    start_pk = distances[-1] - 920
    samples = []
    j = 0
    for i in range(461):
        pk = min(distances[-1], start_pk + 2 * i)
        while distances[j + 1] < pk:
            j += 1
        span = distances[j + 1] - distances[j]
        samples.append(source[j].lerp(source[j + 1], (pk - distances[j]) / span))
    elevations = smooth([p.z for p in samples], 20)
    axis = [Vector((x, y, z)) for x, y, z in zip(smooth([p.x for p in samples], 20),
                                                    smooth([p.y for p in samples], 20), elevations)]
    origin = axis[0].copy()
    axis = [p - origin for p in axis]
    terrain = [Vector(v) - origin for v in data["terrain"]]
    grid = {(round(p.x, 3), round(p.y, 3)): p.z for p in terrain}
    grid_x = sorted({x for x, _ in grid})
    grid_y = sorted({y for _, y in grid})
    dx, dy = grid_x[1] - grid_x[0], grid_y[1] - grid_y[0]

    def ground(x, y):
        gx, gy = (x - grid_x[0]) / dx, (y - grid_y[0]) / dy
        ix, iy = math.floor(gx), math.floor(gy)
        fx, fy = gx - ix, gy - iy
        z00 = grid[grid_x[ix], grid_y[iy]]
        z10 = grid[grid_x[ix + 1], grid_y[iy]]
        z01 = grid[grid_x[ix], grid_y[iy + 1]]
        z11 = grid[grid_x[ix + 1], grid_y[iy + 1]]
        return (1-fy)*((1-fx)*z00 + fx*z10) + fy*((1-fx)*z01 + fx*z11)

    offsets = [-6, -4, -3, 0, 3, 4, 6]
    rows = []
    for i, p in enumerate(axis):
        forward = (axis[min(i + 1, len(axis) - 1)] - axis[max(0, i - 1)]).xy.normalized()
        right = Vector((forward.y, -forward.x))
        row = []
        for offset in offsets:
            x, y = p.xy + offset * right
            z = p.z - 0.025 * abs(offset)
            if abs(offset) == 6:
                z = ground(x, y)
            row.append((x, y, z))
        rows.append(row)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene["SRID"] = "EPSG:32718"
    scene["crs x"] = data["origin"][0] + origin.x
    scene["crs y"] = data["origin"][1] + origin.y
    scene["scale"] = 1.0
    scene["raura_z_origin_m"] = data["z0"] + origin.z
    bpy.context.preferences.filepaths.save_version = 0
    gravel = material("road_gravel_raura", (0.33, 0.24, 0.16))
    dirt = material("dirt_raura", (0.22, 0.16, 0.12))
    visual = bpy.data.collections.new("Visual")
    collision = bpy.data.collections.new("Colision")
    scene.collection.children.link(visual)
    scene.collection.children.link(collision)

    shoulder_meshes = []

    def strip(name, first, last, mat):
        vertices = [p for row in rows for p in row[first:last + 1]]
        width = last - first + 1
        faces = []
        for i in range(len(rows) - 1):
            for k in range(width - 1):
                a = i * width + k
                faces.append((a, a + 1, a + width + 1, a + width))
        mesh(name, vertices, faces, mat, visual)
        if name == "Road":
            mesh("Collision_Road", vertices, faces, mat, collision)
        else:
            shoulder_meshes.append((vertices, faces))

    strip("Road", 2, 4, gravel)
    strip("Terrain_Dirt_Left", 0, 2, dirt)
    strip("Terrain_Dirt_Right", 4, 6, dirt)
    boundary = [r[0] for r in rows] + rows[-1][1:] + [r[-1] for r in rows[-2::-1]] + rows[0][-2:0:-1]
    polygon = [(x, y) for x, y, _ in boundary]
    bounds = (min(x for x, y in polygon)-360, min(y for x,y in polygon)-360,
              max(x for x,y in polygon)+360, max(y for x,y in polygon)+360)
    west,south,east,north = bounds
    vertices = boundary + [tuple(p) for p in terrain if west <= p.x <= east and south <= p.y <= north
                           and not inside(p.xy, polygon)]
    edges = [(i, (i + 1) % len(boundary)) for i in range(len(boundary))]
    pts, _, triangles, origins, _, _ = delaunay_2d_cdt(
        [Vector(v[:2]) for v in vertices], edges, [], 0, 0.0001)
    assert all(ids for ids in origins), str([tuple(p) for p, ids in zip(pts, origins) if not ids][:15])
    ground_vertices = [(p.x, p.y, vertices[ids[0]][2]) for p, ids in zip(pts, origins)]
    outside = [f for f in triangles if not inside(sum((pts[i] for i in f), Vector((0,0))) / len(f), polygon)]
    edge_counts = {}
    for f in outside:
        for a,b in zip(f, f[1:] + f[:1]):
            key = tuple(sorted((a,b)))
            edge_counts[key] = edge_counts.get(key, 0) + 1
    by_input = {i:j for j, ids in enumerate(origins) for i in ids}
    assert all(edge_counts.get(tuple(sorted((by_input[a],by_input[b])))) == 1 for a,b in edges), "Unsealed corridor"
    background = mesh("Ladera DSM", ground_vertices, outside, dirt, visual)
    collision_vertices = list(ground_vertices)
    collision_faces = list(outside)
    for strip_vertices, strip_faces in shoulder_meshes:
        index = len(collision_vertices)
        collision_vertices.extend(strip_vertices)
        collision_faces.extend(tuple(index + v for v in f) for f in strip_faces)
    mesh("Collision_Terrain_Dirt", collision_vertices, collision_faces, dirt, collision)
    photo = material("Sentinel Raura", (0.3,0.3,0.3))
    photo.use_nodes = True
    nt = photo.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(OUT / "sentinel.png"))
    tex.image.pack()
    shader = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    nt.links.new(tex.outputs["Color"], shader.inputs["Base Color"])
    background.data.materials[0] = photo
    uv = background.data.uv_layers.new()
    w,s,e,n = data["bounds"]
    for loop in background.data.loops:
        x,y,_ = ground_vertices[loop.vertex_index]
        uv.data[loop.index].uv = ((x+origin.x-w)/(e-w), (y+origin.y-s)/(n-s))

    ASSETS.mkdir(parents=True, exist_ok=True)
    manifest = {"contract_version":1, "track_id":TRACK,
                "source":{"blend":"raura_stage2_piloto.blend", "generator":Path(__file__).name,
                          "approved_axis":"route_osm_candidate.geojson", "source_pk_m":[start_pk, distances[-1]],
                          "timed_source_pk_m":[start_pk+16, distances[-1]-16]}}
    for kind, group in (("visual",visual),("collision",collision)):
        bpy.ops.object.select_all(action="DESELECT")
        for ob in group.objects:
            ob.select_set(True)
        path = ASSETS / f"{TRACK}_{kind}.glb"
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True)
        manifest[kind] = {"path":path.name, "sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
                          "size_bytes":path.stat().st_size}
    collision.hide_viewport = True
    collision.hide_render = True
    points = axis[8:-8:4]
    if points[-1] != axis[-9]:
        points.append(axis[-9])
    lengths = [0.0]
    for a,b in zip(points,points[1:]):
        lengths.append(lengths[-1] + (b-a).length)
    heading = (points[1]-points[0]).xy.normalized()
    manifest["start_pose"] = {"ground_godot":godot(points[0]), "heading_radians":math.atan2(-heading.x,heading.y)}
    manifest["coordinate_system"] = {"engine":"Godot","forward":"-Z","right":"+X","up":"+Y","unit_scale":1.0}
    write_json(ASSETS / "manifest.json", manifest)
    route = f"res://data/rally/{TRACK}_route.json"
    gates = f"res://data/competition/stages/{TRACK}_timing_gates.json"
    write_json(GAME / route.removeprefix("res://"), {"points":[godot(p) for p in points],
        "point_count":len(points),"total_route_length_m":lengths[-1],"checkpoint_radius_m":8})
    gate_list = []
    for i,kind in ((len(points)//2,"split"),(len(points)-1,"finish")):
        tangent = (points[min(i+1,len(points)-1)]-points[i-1]).xy.normalized()
        gate_list.append({"id":kind,"kind":kind,"origin":godot(points[i]),"forward":godot((*tangent,0)),
            "right":godot((tangent.y,-tangent.x,0)),"up":[0,1,0],"half_width_m":6,"half_height_m":5,
            "route_position":godot(points[i]),"route_distance_m":lengths[i],"route_index":i})
    write_json(GAME / gates.removeprefix("res://"), {"version":1,"gates":gate_list})
    baseline = f"res://data/competition/stages/{TRACK}_pilot_reference.json"
    middle = lengths[len(points)//2]
    write_json(GAME / baseline.removeprefix("res://"), {
        "basis":"Synthetic pilot defaults at 50 km/h, for standalone session startup",
        "values_seconds":{"CPUSplit0":[middle/13.89], "CPUSplit1":[(lengths[-1]-middle)/13.89]}})
    write_json(GAME / f"data/competition/stages/{TRACK}.json", {"id":TRACK,"name":"Rally Raura — Stage 2 piloto",
        "route_path":route,"timing_gates_path":gates,"surface":"gravel_mud",
        "fallback_path":baseline,"difficulty":0,"reference_scale":1.0,
        "roughness":0.1,"jumps":0,"visibility":1,"wetness":0,"blind_route":False,"sector_checkpoint_indices":[len(points)//2,len(points)-1],
        "sector_lengths_km":[lengths[len(points)//2]/1000,(lengths[-1]-lengths[len(points)//2])/1000]})
    write_json(GAME / f"data/rally/pacenotes/{TRACK}.json", {"stage_id":TRACK,"route_point_count":len(points),
        "total_distance_m":lengths[-1],"calls":[]})
    blend = OUT / "raura_stage2_piloto.blend"
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                view = area.spaces.active
                view.clip_end = 10000
                view.shading.type = "MATERIAL"
                view.region_3d.view_location = axis[len(axis)//2]
                view.region_3d.view_distance = 850
                view.region_3d.view_rotation = Vector((0,-1,1.2)).to_track_quat("Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    manifest["source"]["blend_sha256"] = hashlib.sha256(blend.read_bytes()).hexdigest()
    write_json(ASSETS / "manifest.json", manifest)
    print("RAURA PILOT", start_pk, distances[-1], lengths[-1], len(outside))


if __name__ == "__main__":
    main()




