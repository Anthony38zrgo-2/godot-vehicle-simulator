"""Build the full Raura Stage 2 from the approved GIS review."""
from collections import defaultdict
import hashlib
import json
import math
import shutil
import tempfile
import sys
import time
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


def smooth(values, radius, pin_ends=False):
    def weight(i, j):
        return radius + 1 - abs(i - j)

    return [
        values[i] if pin_ends and i in (0, len(values)-1) else sum(values[j] * weight(i, j)
            for j in range(max(0, i - radius), min(len(values), i + radius + 1)))
        / sum(weight(i, j)
              for j in range(max(0, i - radius), min(len(values), i + radius + 1)))
        for i in range(len(values))
    ]


def limit_grade(axis, maximum_grade):
    """Fit a continuous grade bound along the adjusted horizontal axis."""
    steps = [maximum_grade * (b - a).xy.length for a, b in zip(axis, axis[1:])]
    heights = [p.z for p in axis]
    from_start = [0.0]
    for step in steps:
        from_start.append(from_start[-1] + step)
    total = from_start[-1]
    assert abs(heights[0] - heights[-1]) <= total, "Infeasible endpoint elevations"
    # Clamp target heights to the reach of both anchors. The lower and upper
    # envelopes then preserve both endpoints while limiting adjacent grades.
    feasible = [
        max(heights[0] - d, heights[-1] - (total - d),
            min(z, heights[0] + d, heights[-1] + (total - d)))
        for z, d in zip(heights, from_start)
    ]
    lower, upper = feasible[:], feasible[:]
    for indices in (range(1, len(axis)), range(len(axis)-2, -1, -1)):
        forward = indices.step == 1
        for i in indices:
            j = i - indices.step
            step = steps[j if forward else i]
            lower[i] = min(lower[i], lower[j] + step)
            upper[i] = max(upper[i], upper[j] - step)
    for p, lo, hi in zip(axis, lower, upper):
        p.z = (lo + hi) / 2
    return max(abs(p.z - z) for p, z in zip(axis, heights))


def material(name, color):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    return m


def textured_material(name, filename):
    mat = material(name, (0.25, 0.19, 0.13))
    mat.use_nodes = True
    shader = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    shader.inputs["Roughness"].default_value = 0.93
    texture = mat.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = bpy.data.images.load(str(BASE / "textures" / filename), check_existing=True)
    if not texture.image.packed_file:
        texture.image.pack()
    mat.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    return mat


def mesh(name, vertices, faces, mat, collection):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    data.materials.append(mat)
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    return obj


def inside(point, edge_bands):
    x, y = point
    hit = False
    for (ax, ay), (bx, by) in edge_bands.get(math.floor(y / 20), ()):
        if (ay > y) != (by > y) and x < ax + (bx - ax) * (y - ay) / (by - ay):
            hit = not hit
    return hit


def godot(point):
    return [point[0], point[2], -point[1]]


def main():
    corrected_stage = "--stage-sr" in sys.argv
    earth_trial = "--pilot-start-earth" in sys.argv
    start_survey = "--pilot-start-survey" in sys.argv
    lateral_trial = "--pilot-start-lateral" in sys.argv
    start_pilot = "--pilot-start-relief" in sys.argv or lateral_trial or (earth_trial and not start_survey)
    pilot_dir = OUT / ("piloto_inicio" if start_survey or start_pilot else "piloto_osqp")
    if earth_trial:
        pilot_dir = OUT / "earth_salida_sigma5" / "piloto"
    survey_only = "--pilot-survey" in sys.argv or start_survey
    pilot_relief = "--pilot-relief" in sys.argv or start_pilot
    pilot = "--pilot-osqp" in sys.argv or pilot_relief
    relief_enabled = pilot_relief or not (pilot or survey_only)
    if pilot and (survey_only or "--visual-only" in sys.argv):
        raise ValueError("Choose a single pilot mode")
    track = "raurastart_stage2" if start_pilot else "raurarelief_stage2" if pilot_relief else ("raurapilot_stage2" if pilot else TRACK)
    if relief_enabled:
        sys.path.insert(0, str(BASE))
        import relieve_piloto as detail
    if earth_trial:
        track = "rauraearth_stage2"
    if corrected_stage:
        track = "raurasr_stage2"
    assets = GAME / "assets/rally" / track if pilot or corrected_stage else ASSETS
    if lateral_trial:
        assets = pilot_dir / "variante_lateral"
        assets.mkdir(exist_ok=True)
    source_path = pilot_dir / "scene_input.json" if earth_trial else SOURCE
    if corrected_stage:
        source_path = OUT / "scene_input_sr.json"
    data = json.loads(source_path.read_text(encoding="utf8"))
    assert all(p is not None for p in data["route"]), "The approved axis contains missing elevations"
    source = [Vector(p) for p in data["route"]]
    distances = [0.0]
    for a, b in zip(source, source[1:]):
        distances.append(distances[-1] + (b - a).xy.length)
    # Sample the approved axis from start to finish.
    start_pk = 0.0
    samples = []
    j = 0
    for i in range(math.ceil(distances[-1] / 2) + 1):
        pk = min(distances[-1], start_pk + 2 * i)
        while distances[j + 1] < pk:
            j += 1
        span = distances[j + 1] - distances[j]
        samples.append(source[j].lerp(source[j + 1], (pk - distances[j]) / span))
    reference_elevations = smooth([p.z for p in samples], 20)
    elevations = smooth(smooth(reference_elevations, 35), 18)
    # Fade back to the already established endpoint elevations over 80 m.
    for end, direction in ((0, 1), (-1, -1)):
        correction = reference_elevations[end] - elevations[end]
        for i in range(40):
            elevations[end + direction * i] += correction * (1 - i / 40) ** 2
    # Separate adjacent arms of the switchbacks while retaining the approved
    # endpoints. Smooth the adjustment along the axis to avoid sharp jogs.
    axis = [Vector((x, y, z)) for x, y, z in zip(
        smooth([p.x for p in samples], 8),
        smooth([p.y for p in samples], 8), elevations)]
    for endpoint, direction in ((0, 1), (-1, -1)):
        delta = samples[endpoint].xy - axis[endpoint].xy
        for step in range(12):
            weight = (1.0 - step / 12.0) ** 2
            p = axis[endpoint + direction * step]
            p.x += delta.x * weight
            p.y += delta.y * weight
    clearance = 9.0
    for _ in range(16):
        buckets = defaultdict(list)
        shifts = [Vector((0, 0)) for _ in axis]
        counts = [0 for _ in axis]
        for i, p in enumerate(axis):
            cell = (math.floor(p.x / clearance), math.floor(p.y / clearance))
            for x in range(cell[0]-1, cell[0]+2):
                for y in range(cell[1]-1, cell[1]+2):
                    for j in buckets[x, y]:
                        if i - j < 9:
                            continue
                        delta = p.xy - axis[j].xy
                        length = delta.length
                        if 0.001 < length < clearance:
                            shift = delta * ((clearance - length) / (2 * length))
                            shifts[i] += shift
                            shifts[j] -= shift
                            counts[i] += 1
                            counts[j] += 1
            buckets[cell].append(i)
        dx = smooth([v.x / max(n, 1) for v, n in zip(shifts, counts)], 4, pin_ends=True)
        dy = smooth([v.y / max(n, 1) for v, n in zip(shifts, counts)], 4, pin_ends=True)
        for i in range(1, len(axis)-1):
            axis[i].x += dx[i]
            axis[i].y += dy[i]
    max_grade = 0.22
    max_grade_adjustment = limit_grade(axis, max_grade)
    rounded = smooth([p.z for p in axis], 10, pin_ends=True)
    for p, z in zip(axis, rounded):
        p.z = z
    limit_grade(axis, max_grade)
    origin = axis[0].copy()
    axis = [p - origin for p in axis]
    timed_axis = axis[:]
    # Keep a short apron beyond each timing endpoint.
    for start in (True, False):
        endpoint = axis[0] if start else axis[-1]
        interior = axis[3] if start else axis[-4]
        delta = endpoint - interior
        step = delta * (2.0 / delta.xy.length)
        apron = [endpoint + step * i for i in range(1, 7)]
        axis = apron[::-1] + axis if start else axis + apron
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
    widths = [1.0] * len(axis)
    normals = []
    for i in range(len(axis)):
        forward = (axis[min(i + 1, len(axis) - 1)] - axis[max(0, i - 1)]).xy.normalized()
        normals.append(Vector((forward.y, -forward.x)))

    def cross_sections():
        rows = []
        for p, right, scale in zip(axis, normals, widths):
            row = []
            half_width = min(3.0, 6.0 * scale - 0.28)
            shoulder = min(half_width + 1.0, 6.0 * scale - 0.14)
            actual = [-6*scale, -shoulder, -half_width, 0, half_width, shoulder, 6*scale]
            for offset, lateral in zip(offsets, actual):
                x, y = p.xy + lateral * right
                z = p.z - 0.025 * abs(lateral)
                if abs(offset) == 6:
                    # Continue from the shoulder instead of snapping to the DSM.
                    inner_z = p.z - 0.025 * shoulder
                    reach = 0.60 * (abs(lateral) - shoulder)
                    z = max(inner_z - reach, min(ground(x, y), inner_z + reach))
                row.append((x, y, z))
            rows.append(row)
        return rows

    for attempt in range(20):
        rows = cross_sections()
        boundary = [r[0] for r in rows] + rows[-1][1:] + [r[-1] for r in rows[-2::-1]] + rows[0][-2:0:-1]
        polygon = [(x, y) for x, y, _ in boundary]
        edges = [(i, (i + 1) % len(boundary)) for i in range(len(boundary))]
        probe, _, _, source_ids, _, _ = delaunay_2d_cdt(
            [Vector(v) for v in polygon], edges, [], 0, 0.0001)
        crossings = [point for point, ids in zip(probe, source_ids) if not ids]
        if not crossings:
            break
        print(f"Corridor pass {attempt + 1}: {len(crossings)} intersections", flush=True)
        for i, p in enumerate(axis):
            nearest = min((p.xy - c).length for c in crossings)
            if nearest < 18.0:
                widths[i] *= 1.0 - 0.28 * (1.0 - nearest / 18.0)
    else:
        raise ValueError("Unable to resolve intersecting corridor at hairpins")
    if survey_only:
        station = [0.0]
        for a,b in zip(timed_axis, timed_axis[1:]):
            station.append(station[-1] + (b-a).xy.length)
        # Select the close-arm switchback near source OSM PK 4+890.
        center = station[2445]
        first = next(i for i, value in enumerate(station) if value >= center - 350)
        last = next(i for i, value in enumerate(station) if value >= center + 350)
        if start_survey:
            first = 0
            last = next(i for i, value in enumerate(station) if value >= 700)
        write_json(pilot_dir / "base.json", {
            "utm_origin": [data["origin"][0] + origin.x, data["origin"][1] + origin.y, data["z0"] + origin.z],
            "pk_m": station[first:last+1],
            "axis": [list(p) for p in timed_axis[first:last+1]],
            "sections": rows[first+6:last+7],
            "apron_before": rows[first:first+6], "apron_after": rows[last+7:last+13],
        })
        return
    if pilot:
        proposal = json.loads((pilot_dir / "propuesta.json").read_text(encoding="utf8"))
        timed_axis = [Vector(v) for v in proposal["axis"]]
        rows = proposal["apron_before"] + proposal["sections"] + proposal["apron_after"]
        axis = [Vector(row[3]) for row in rows]
        start_pk = proposal["pk_m"][0]
        max_grade_adjustment = proposal["metrics"]["maximum_z_change_m"]
    min_road_width = min(math.dist(row[2][:2], row[4][:2]) for row in rows)
    assert min_road_width >= 2.2, f"Road is too narrow: {min_road_width:.2f} m"
    print(f"Minimum road width: {min_road_width:.2f} m", flush=True)
    def signed_area(a, b, c):
        return (b[0]-a[0])*(c[1]-a[1]) - (b[1]-a[1])*(c[0]-a[0])
    folds = []
    for i, (row, following) in enumerate(zip(rows, rows[1:])):
        for k in range(6):
            a, b, c, d = row[k], row[k+1], following[k+1], following[k]
            if min(signed_area(a,b,c), signed_area(a,c,d)) <= 0:
                folds.append((i,k))
    assert not folds, f"Folded cross-sections: {folds[:20]}"


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
    visual_gravel = textured_material("road_gravel_raura", "dirt_stones.png" if pilot else "greece_g_4a.png")
    compacted = textured_material("road_gravel_compacted_raura", "dirt.png") if pilot else visual_gravel
    scree = textured_material("raura_cascajo", "dirt_stones.png" if pilot else "dirt.png")
    exposed_rock = textured_material("raura_roca_expuesta", "stone.png" if pilot else "argentina_talud.png")
    stations = [0.0]
    for a, b in zip(axis, axis[1:]):
        stations.append(stations[-1] + (b - a).length)

    def visual_strip(name, sections, materials, choose_material, period, strip_stations=stations):
        width = len(sections[0])
        faces = []
        for i in range(len(sections) - 1):
            for k in range(width - 1):
                a = i * width + k
                faces.append((a, a + 1, a + width + 1, a + width))
        obj = mesh(name, [p for row in sections for p in row], faces, materials[0], visual)
        for mat in materials[1:]:
            obj.data.materials.append(mat)
        uv = obj.data.uv_layers.new(name="Metros")
        for face in obj.data.polygons:
            i, k = divmod(face.index, width - 1)
            face.material_index = choose_material(i, k)
            for loop_index in face.loop_indices:
                row_index, col = divmod(obj.data.loops[loop_index].vertex_index, width)
                row = sections[row_index]
                lateral = (row[col] - row[0]).length
                if name == "Road" and not pilot:
                    # The Greece road tile has both wheel tracks across its width.
                    uv.data[loop_index].uv = (col / (width - 1), strip_stations[row_index] / 4.0)
                else:
                    uv.data[loop_index].uv = (lateral / period, strip_stations[row_index] / period)
        return obj, faces

    if relief_enabled:
        rows = detail.bank_sections(rows, stations)
    road_sections = []
    for row in rows:
        left, center, right = (Vector(row[i]) for i in (2, 3, 4))
        # Keep wheel tracks inside the narrowed sections of the road.
        road_sections.append([
            left, left.lerp(center, 0.37), left.lerp(center, 0.65), center,
            center.lerp(right, 0.35), center.lerp(right, 0.63), right,
        ])
    if relief_enabled:
        pk = [0.0]
        for a,b in zip(timed_axis, timed_axis[1:]):
            pk.append(pk[-1] + (b-a).xy.length)
        if pilot:
            pk = proposal["pk_m"]
        if pilot:
            road_relief = detail.RoadRelief(rows, stations, pk, BASE / "desgaste_inicio.json" if start_pilot else None)
        else:
            road_relief = detail.StartWear(rows, stations, pk, BASE / "desgaste_inicio_stage2.json",
                                           pothole_fraction=0.8 if corrected_stage else 1.0)
        inventory_dir = assets if lateral_trial else pilot_dir
        inventory = inventory_dir / "baches_resueltos.json" if pilot else OUT / "baches_stage2_resueltos.json"
        if corrected_stage:
            inventory = OUT / "baches_raurasr_resueltos.json"
        write_json(inventory, {"seed":road_relief.seed,"features":road_relief.features})
        road_sections, road_stations, road_originals = detail.densify(rows, stations, road_relief)
        width = len(road_sections[0])
        _, road_faces = visual_strip(
            "Road", road_sections, (visual_gravel, compacted) if pilot else (visual_gravel,),
            lambda _i, k: int(pilot and 0.35 < abs(2 * (k+0.5) / (width-1) - 1) < 0.63),
            1.0, road_stations,
        )
        mesh("Collision_Road", [p for row in road_sections for p in row], road_faces, gravel, collision)
    else:
        visual_strip("Road", road_sections, (visual_gravel, compacted),
                     lambda _i, k: int(k in (1, 4)), 1.0)

    side_caps = {}
    for side, indices in (("Left", (0, 1, 2)), ("Right", (4, 5, 6))):
        sections = [[Vector(row[k]) for k in indices] for row in rows]
        outer = 0 if side == "Left" else 2
        inner = 2 - outer
        outer_face = 0 if side == "Left" else 1

        def rock_cut(i, k):
            is_shoulder = k == (8 if side == "Left" else 0) if relief_enabled else k != outer_face
            if is_shoulder:
                return 0
            if not pilot:
                # Classify the generated cross slope, not the raw DEM or grade along the road.
                threshold = math.tan(math.radians(15))
                slopes = []
                for row in detailed[i:i+2]:
                    delta = row[k+1] - row[k]
                    slopes.append(abs(delta.z) / max(delta.xy.length, 1e-6))
                return int(min(slopes) >= threshold)
            slopes = []
            for j in range(max(0, i - 4), min(len(sections), i + 6)):
                row = sections[j]
                reach = (row[outer] - row[inner]).xy.length
                rise = ground(row[outer].x, row[outer].y) - row[inner].z
                slopes.append(rise / max(reach, 0.1))
            return int(sum(slopes) / len(slopes) > 1.0)

        if relief_enabled:
            detailed = []
            for i, row in enumerate(sections):
                shoulder = row[1]
                rounded = detail.slope_section(shoulder, row[outer], stations[i], stations[-1],
                                               -1 if side == "Left" else 1)
                if lateral_trial:
                    reach = (row[outer] - shoulder).xy.length
                    pk = stations[i] - stations[6]
                    weight = max(detail.smoothstep(1 - abs(pk - center) / 35)
                                 for center in (35, 225, 500))
                    rise = row[outer].z - shoulder.z
                    variation = math.sin(pk / 17)
                    if rise > 0:
                        foot = min(0.45, reach * 0.25)
                        crest = max(foot + 0.01, reach * 0.80)
                    else:
                        width = 3 + variation
                        foot = min(width, reach * 0.65)
                        crest = max(foot + 0.01, reach * 0.95)
                    for point in rounded:
                        distance = (point - shoulder).xy.length
                        fraction = detail.smoothstep((distance - foot) / (crest - foot))
                        target = shoulder.z + rise * fraction
                        if rise <= 0:
                            target += min(0.25, abs(rise) * 0.2) * math.sin(math.pi * min(1, distance / max(foot, 0.01)))
                        point.z += weight * (target - point.z)
                detailed.append([row[0], *reversed(rounded), *row[1:]] if side == "Left"
                                else [*row[:2], *rounded, row[2]])
            side_vertices = [p for row in detailed for p in row]
            side_uvs = [((p - row[0]).length / 2.5, stations[i] / 2.5)
                        for i, row in enumerate(detailed) for p in row]
            side_faces, side_materials = [], []
            columns = len(detailed[0])
            shoulder_col = columns - 2 if side == "Left" else 0
            road_col = columns - 1 if side == "Left" else 0
            road_edge = 0 if side == "Left" else -1
            for i in range(len(detailed)-1):
                for k in range(columns-1):
                    j = i*columns+k
                    if k != shoulder_col:
                        side_faces.append((j,j+1,j+columns+1,j+columns))
                        side_materials.append(rock_cut(i,k))
                        continue
                    start, end = road_originals[i:i+2]
                    chain = [i*columns+road_col]
                    for d in range(start+1,end):
                        chain.append(len(side_vertices))
                        point = road_sections[d][road_edge]
                        side_vertices.append(point)
                        t = (road_stations[d]-stations[i])/(stations[i+1]-stations[i])
                        a = side_uvs[i*columns+road_col][0]
                        b = side_uvs[(i+1)*columns+road_col][0]
                        side_uvs.append((a+(b-a)*t, road_stations[d]/2.5))
                    chain.append((i+1)*columns+road_col)
                    if side == "Left":
                        fan = [(j,a,b) for a,b in zip(chain,chain[1:])]
                        fan.append((j,chain[-1],j+columns))
                    else:
                        fan = [(j+1,b,a) for a,b in zip(chain,chain[1:])]
                        fan.append((j+1,j+columns+1,chain[-1]))
                    side_faces.extend(fan)
                    side_materials.extend([0]*len(fan))
            obj = mesh("Terrain_Dirt_" + side, side_vertices, side_faces, scree, visual)
            obj.data.materials.append(exposed_rock)
            uv = obj.data.uv_layers.new(name="Metros")
            for face in obj.data.polygons:
                face.use_smooth = True
                face.material_index = side_materials[face.index]
                for loop in face.loop_indices:
                    uv.data[loop].uv = side_uvs[obj.data.loops[loop].vertex_index]
            shoulder_meshes.append((side_vertices, side_faces))
            side_caps[side] = (detailed[0], detailed[-1])
        else:
            visual_strip("Terrain_Dirt_" + side, sections, (scree, exposed_rock), rock_cut, 2.5)

    def strip(name, first, last, mat):
        vertices = [p for row in rows for p in row[first:last + 1]]
        width = last - first + 1
        faces = []
        for i in range(len(rows) - 1):
            for k in range(width - 1):
                a = i * width + k
                faces.append((a, a + 1, a + width + 1, a + width))
        if name == "Road":
            mesh("Collision_Road", vertices, faces, mat, collision)
        else:
            shoulder_meshes.append((vertices, faces))

    if not relief_enabled:
        strip("Road", 2, 4, gravel)
        strip("Terrain_Dirt_Left", 0, 2, dirt)
        strip("Terrain_Dirt_Right", 4, 6, dirt)
    boundary = [r[0] for r in rows] + rows[-1][1:] + [r[-1] for r in rows[-2::-1]] + rows[0][-2:0:-1]
    if relief_enabled:
        caps = [side_caps["Left"][i][:-1] + road_sections[j] + side_caps["Right"][i][1:]
                for i,j in ((0,0),(1,-1))]
        boundary = ([Vector(r[0]) for r in rows] + caps[1][1:] +
                    [Vector(r[-1]) for r in rows[-2::-1]] + caps[0][-2:0:-1])
    polygon = [(x, y) for x, y, _ in boundary]
    edge_bands = defaultdict(list)
    for a, b in zip(polygon, polygon[1:] + polygon[:1]):
        for band in range(math.floor(min(a[1], b[1]) / 20), math.floor(max(a[1], b[1]) / 20) + 1):
            edge_bands[band].append((a, b))
    bounds = (min(x for x, y in polygon)-360, min(y for x,y in polygon)-360,
              max(x for x,y in polygon)+360, max(y for x,y in polygon)+360)
    west,south,east,north = bounds
    # Grade the surrounding terrain from the same edge used by both meshes.
    blend_radius = 72.0
    bin_size = 18.0
    edge_bins = defaultdict(list)

    def cell(x, y):
        return math.floor(x / bin_size), math.floor(y / bin_size)

    boundary_segments = list(zip(boundary, boundary[1:] + boundary[:1]))
    for a, b in boundary_segments:
        ax, ay, az = a
        bx, by, bz = b
        start_x, start_y = cell(min(ax, bx) - blend_radius, min(ay, by) - blend_radius)
        end_x, end_y = cell(max(ax, bx) + blend_radius, max(ay, by) + blend_radius)
        vx, vy = bx - ax, by - ay
        length_sq = vx * vx + vy * vy
        if length_sq == 0:
            continue
        segment = (ax, ay, az, vx, vy, bz - az, length_sq)
        for cx in range(start_x, end_x + 1):
            for cy in range(start_y, end_y + 1):
                edge_bins[cx, cy].append(segment)

    def grade_terrain(x, y, dsm_z):
        nearest_sq = blend_radius ** 2
        edge_z = dsm_z
        for ax, ay, az, vx, vy, vz, length_sq in edge_bins.get(cell(x, y), ()):
            dx, dy = x - ax, y - ay
            t = max(0.0, min(1.0, (dx * vx + dy * vy) / length_sq))
            distance_sq = (dx - vx * t) ** 2 + (dy - vy * t) ** 2
            if distance_sq < nearest_sq:
                nearest_sq = distance_sq
                edge_z = az + vz * t
        distance = math.sqrt(nearest_sq)
        if distance < 1.0:
            return None
        rise = dsm_z - edge_z
        limit = 0.65 * distance
        graded = edge_z + max(-limit, min(limit, rise))
        if relief_enabled:
            graded = edge_z + (graded - edge_z) * (0.40 + 0.60 * detail.smoothstep(distance / 6.0))
        t = max(0.0, (distance - 18.0) / (blend_radius - 18.0))
        return graded + (dsm_z - graded) * t * t * (3 - 2 * t)

    vertices = boundary[:]
    for p in terrain:
        if west <= p.x <= east and south <= p.y <= north and not inside(p.xy, edge_bands):
            z = grade_terrain(p.x, p.y, p.z)
            if z is not None:
                vertices.append((p.x, p.y, z))

    # Add near-road samples where the 30 m raster has no support points.
    occupied = {(round(x / 3), round(y / 3)) for x, y, _ in vertices}
    for a, b in boundary_segments[::3]:
        vx, vy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(vx, vy)
        if length < 0.01:
            continue
        for distance in (4.0, 10.0, 20.0, 36.0, 54.0):
            x = (a[0] + b[0]) * 0.5 - vy / length * distance
            y = (a[1] + b[1]) * 0.5 + vx / length * distance
            key = (round(x / 3), round(y / 3))
            if key in occupied or inside((x, y), edge_bands):
                continue
            z = grade_terrain(x, y, ground(x, y))
            if z is not None:
                occupied.add(key)
                vertices.append((x, y, z))

    edges = [(i, (i + 1) % len(boundary)) for i in range(len(boundary))]
    pts, _, triangles, origins, _, _ = delaunay_2d_cdt(
        [Vector(v[:2]) for v in vertices], edges, [], 0, 0.0001)
    assert all(origins), "Terrain triangulation split a corridor edge"
    ground_vertices = [(p.x, p.y, vertices[ids[0]][2]) for p, ids in zip(pts, origins)]
    outside = [f for f in triangles if not inside(sum((pts[i] for i in f), Vector((0,0))) / len(f), edge_bands)]
    edge_counts = {}
    for f in outside:
        for a,b in zip(f, f[1:] + f[:1]):
            key = tuple(sorted((a,b)))
            edge_counts[key] = edge_counts.get(key, 0) + 1
    by_input = {i:j for j, ids in enumerate(origins) for i in ids}
    assert all(edge_counts.get(tuple(sorted((by_input[a],by_input[b])))) == 1 for a,b in edges), "Unsealed corridor"
    active = sorted({i for face in outside for i in face})
    compact_index = {old: new for new,old in enumerate(active)}
    compact_ground = [ground_vertices[i] for i in active]
    outside = [tuple(compact_index[i] for i in face) for face in outside]
    background = mesh("Ladera DSM", compact_ground, outside, dirt, visual)
    split_exterior = not pilot or start_pilot
    if split_exterior:
        mesh("Collision_Terrain_Dirt_Raura_Exterior", compact_ground, outside, dirt, collision)
    collision_vertices = [] if split_exterior else list(compact_ground)
    collision_faces = [] if split_exterior else list(outside)
    for strip_vertices, strip_faces in shoulder_meshes:
        index = len(collision_vertices)
        collision_vertices.extend(strip_vertices)
        collision_faces.extend(tuple(index + v for v in f) for f in strip_faces)
    mesh("Collision_Terrain_Dirt", collision_vertices, collision_faces, dirt, collision)
    photo = material("Sentinel Raura", (0.3,0.3,0.3))
    photo.use_nodes = True
    nt = photo.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage")
    satellite_texture = "sentinel_raura_fotorrealista.jpg" if corrected_stage else "sentinel.png"
    tex.image = bpy.data.images.load(str(OUT / satellite_texture))
    tex.image.pack()
    shader = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    nt.links.new(tex.outputs["Color"], shader.inputs["Base Color"])
    background.data.materials[0] = photo
    uv = background.data.uv_layers.new()
    w,s,e,n = data["bounds"]
    for loop in background.data.loops:
        x,y,_ = compact_ground[loop.vertex_index]
        uv.data[loop.index].uv = ((x+origin.x-w)/(e-w), (y+origin.y-s)/(n-s))

    if relief_enabled:
        from auditar_costuras import audit
        inner = {tuple(sorted((by_input[a], by_input[b]))) for a,b in edges}
        exterior = [(ground_vertices[a], ground_vertices[b]) for (a,b),count in edge_counts.items()
                    if count == 1 and (a,b) not in inner]
        for group in (visual, collision):
            audit(group.objects, exterior, axis, pk)

    assets.mkdir(parents=True, exist_ok=True)
    manifest = {"contract_version":1, "track_id":track,
                "source":{"blend":"raura_stage2.blend", "generator":Path(__file__).name,
                          "approved_axis":"earth_salida_sigma5/route_osm_corregido.geojson" if earth_trial else "route_osm_candidate.geojson",
                          "road_width_m":[min_road_width,6.0],
                          "maximum_design_grade":max_grade,
                          "terrain_blend_radius_m":blend_radius,
                          "max_grade_adjustment_m":max_grade_adjustment,
                          "source_pk_m":[start_pk, distances[-1]],
                          "timed_source_pk_m":[start_pk, distances[-1]]}}
    if pilot:
        manifest["source"].update(blend="raura_stage2_piloto_osqp.blend",
                                  source_pk_m=proposal["pk_m"][::len(timed_axis)-1],
                                  timed_source_pk_m=proposal["pk_m"][::len(timed_axis)-1],
                                  rasante=proposal["metrics"]["solver"], corridor="section daylight prototype")
    if relief_enabled:
        manifest["source"].update(blend="raura_stage2_piloto_relieve.blend" if pilot else "raura_stage2.blend",
                                  relief_seed=road_relief.seed, pothole_count=len(road_relief.pits),
                                  maximum_road_depression_m=road_relief.max_depth)
    visual_only = "--visual-only" in sys.argv
    if visual_only:
        previous = json.loads((assets / "manifest.json").read_text(encoding="utf8"))
        manifest["collision"] = previous["collision"]
    manifest["source"]["surface_texture_pack"] = (
        "HandPainted/texture-pack-2-ground" if pilot else "CMR2/02_Greece/Stage01/hi"
    )
    if not pilot:
        manifest["source"]["slope_texture"] = {"file":"argentina_talud.png","minimum_cross_slope_degrees":15}
    exports = [("visual", visual)] if visual_only else [("visual", visual), ("collision", collision)]
    staged_glbs = []
    for kind, group in exports:
        bpy.ops.object.select_all(action="DESELECT")
        for ob in group.objects:
            ob.select_set(True)
        path = assets / f"{track}_{kind}.glb"
        staged = path.with_suffix(".pending.glb")
        if corrected_stage:
            with tempfile.TemporaryDirectory(prefix="raura_sr_") as temp_dir:
                local_export = Path(temp_dir) / path.name
                bpy.ops.export_scene.gltf(filepath=str(local_export), export_format="GLB", use_selection=True)
                shutil.copyfile(local_export, staged)
        else:
            bpy.ops.export_scene.gltf(filepath=str(staged), export_format="GLB", use_selection=True)
        with staged.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        manifest[kind] = {"path":path.name, "sha256":digest, "size_bytes":staged.stat().st_size}
        staged_glbs.append((staged, path))
    for staged, path in staged_glbs:
        for attempt in range(6):
            try:
                staged.replace(path)
                break
            except PermissionError:
                if attempt == 5:
                    raise
                time.sleep(0.5 * (attempt+1))
    collision.hide_viewport = True
    collision.hide_render = True
    blend = pilot_dir / "raura_stage2_piloto_osqp.blend" if pilot else OUT / "raura_stage2.blend"
    if pilot_relief:
        blend = pilot_dir / "raura_stage2_piloto_relieve.blend"
    if corrected_stage:
        blend = (assets if assets.is_junction() else OUT) / "raurasr_stage2.blend"
        manifest["source"]["blend"] = blend.name
        manifest["source"]["approved_axis"] = "osm_corregido_sr_z_preservado"
    if lateral_trial:
        blend = assets / blend.name
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                view = area.spaces.active
                view.clip_end = 10000
                view.shading.type = "MATERIAL"
                view.region_3d.view_location = axis[len(axis)//2]
                view.region_3d.view_distance = 850 if pilot else 6000
                view.region_3d.view_rotation = Vector((0,-1,1.2)).to_track_quat("Z","Y")
    if pilot:
        before = bpy.data.collections.new("Rasante anterior (comparacion)")
        scene.collection.children.link(before)
        curve = bpy.data.curves.new("Eje base", "CURVE")
        curve.dimensions = "3D"
        curve.bevel_depth = 0.15
        spline = curve.splines.new("POLY")
        spline.points.add(len(timed_axis)-1)
        for point, xyz in zip(spline.points, proposal["base_axis"]):
            point.co = (*xyz, 1)
        before.objects.link(bpy.data.objects.new("Eje base", curve))
        before.hide_viewport = True
        before.hide_render = True
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    if visual_only:
        previous["source"].update(manifest["source"])
        previous["source"]["blend_sha256"] = hashlib.sha256(blend.read_bytes()).hexdigest()
        previous["visual"] = manifest["visual"]
        write_json(assets / "manifest.json", previous)
        return
    sample_indices = list(range(0, len(timed_axis), 4))
    if sample_indices[-1] != len(timed_axis) - 1:
        sample_indices.append(len(timed_axis) - 1)
    points = [timed_axis[i] for i in sample_indices]
    surface_probes = []
    for i in sample_indices:
        row = [Vector(p) for p in rows[i + 6]]
        if relief_enabled:
            refined = road_sections[road_originals[i + 6]]
            surface_probes.append([godot(refined[k]) for k in (12, 4, 20)] +
                                  [godot(row[1].lerp(row[2], 0.5)), godot(row[4].lerp(row[5], 0.5))])
        else:
            surface_probes.append([
                godot(row[3]), godot(row[3].lerp(row[2], 0.78)), godot(row[3].lerp(row[4], 0.78)),
                godot(row[1].lerp(row[2], 0.5)), godot(row[4].lerp(row[5], 0.5)),
            ])
    pothole_probes = []
    if relief_enabled:
        from bisect import bisect_left
        for station, t, *_ in road_relief.pits:
            i = min(bisect_left(road_stations, station), len(road_stations) - 1)
            k = round((1 + t) * detail.ROAD_COLUMNS / 2)
            p = road_sections[i][k]
            center = road_sections[i][detail.ROAD_COLUMNS // 2]
            edge = road_sections[i][0 if t < 0 else -1]
            half_width = (edge - center).xy.length
            pothole_probes.append({"position":godot(p), "offset_m":road_relief.height(
                road_stations[i], 2*k/detail.ROAD_COLUMNS-1, half_width)})
    lengths = [0.0]
    for a,b in zip(points,points[1:]):
        lengths.append(lengths[-1] + (b-a).length)
    heading = (points[1]-points[0]).xy.normalized()
    manifest["start_pose"] = {"ground_godot":godot(points[0]), "heading_radians":math.atan2(-heading.x,heading.y)}
    manifest["coordinate_system"] = {"engine":"Godot","forward":"-Z","right":"+X","up":"+Y","unit_scale":1.0}
    write_json(assets / "manifest.json", manifest)
    route = f"res://data/rally/{track}_route.json"
    gates = f"res://data/competition/stages/{track}_timing_gates.json"
    write_json(GAME / route.removeprefix("res://"), {"points":[godot(p) for p in points],
        "point_count":len(points),"total_route_length_m":lengths[-1],"checkpoint_radius_m":8,
        "surface_probes":surface_probes, **({"pothole_probes":pothole_probes} if relief_enabled else {})})
    gate_list = []
    split_indices = [min(range(len(points)), key=lambda i: abs(lengths[i] - lengths[-1] * fraction))
                     for fraction in (0.25, 0.5, 0.75)]
    control_indices = [*split_indices, len(points) - 1]
    for number, i in enumerate(control_indices, 1):
        kind = "finish" if i == len(points) - 1 else "split"
        tangent = (points[min(i+1,len(points)-1)]-points[i-1]).xy.normalized()
        gate_list.append({"id":kind if kind == "finish" else f"split_{number:02d}","kind":kind,"origin":godot(points[i]),"forward":godot((*tangent,0)),
            "right":godot((tangent.y,-tangent.x,0)),"up":[0,1,0],"half_width_m":6,"half_height_m":5,
            "route_position":godot(points[i]),"route_distance_m":lengths[i],"route_index":i})
    write_json(GAME / gates.removeprefix("res://"), {"version":1,"gates":gate_list})
    baseline = f"res://data/competition/stages/{track}_reference.json"
    sectors = [lengths[b] - lengths[a] for a,b in zip([0,*split_indices], control_indices)]
    write_json(GAME / baseline.removeprefix("res://"), {
        "basis":"Synthetic standalone defaults at 50 km/h",
        "values_seconds":{f"CPUSplit{i}":[length / 13.89] for i, length in enumerate(sectors)}})
    write_json(GAME / f"data/competition/stages/{track}.json", {"id":track,"name":"Rally Raura — Piloto con relieve" if pilot_relief else ("Rally Raura — Piloto OSQP" if pilot else "Rally Raura — Stage 2"),
        "route_path":route,"timing_gates_path":gates,"surface":"gravel_mud",
        "fallback_path":baseline,"difficulty":0,"reference_scale":1.0,
        "roughness":0.1,"jumps":0,"visibility":1,"wetness":0,"blind_route":False,
        "sector_checkpoint_indices":control_indices,"sector_lengths_km":[length/1000 for length in sectors]})
    write_json(GAME / f"data/rally/pacenotes/{track}.json", {"stage_id":track,"route_point_count":len(points),
        "total_distance_m":lengths[-1],"calls":[]})
    manifest["source"]["blend_sha256"] = hashlib.sha256(blend.read_bytes()).hexdigest()
    write_json(assets / "manifest.json", manifest)
    print("RAURA STAGE 2", start_pk, distances[-1], lengths[-1], len(outside), max_grade_adjustment)


if __name__ == "__main__":
    main()






