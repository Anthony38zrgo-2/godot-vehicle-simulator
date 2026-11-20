"""Author roadside guardrails on descending sides of CDI asphalt."""
from bisect import bisect_right
import math

from mathutils import Vector


def build_guardrails(rows, stations, dem, mesh, material, visual, collision):
    height_scale = 0.70
    rail_materials = [material(name, (0.55, 0.59, 0.61))
                      for name in ("arm_1a", "arm_1b", "arm_1a_reverse")]
    vertices, faces, uv, styles = [], [], [], []
    wall_vertices, wall_faces = [], []
    runs = []
    for edge, shoulder in ((2, 1), (4, 5)):
        alignment, exposed = [], []
        for row in rows:
            curb, verge = Vector(row[edge]), Vector(row[shoulder])
            alignment.append(curb.lerp(verge, 0.80))
            outward = (curb - Vector(row[3])).xy.normalized()
            near = dem(*(curb.xy + outward * 8.0))
            far = dem(*(curb.xy + outward * 20.0))
            exposed.append(curb.z - near >= 2.0 and curb.z - far >= 10.0 and near - far >= 4.0)

        first = 0
        while first < len(rows) - 1:
            if not exposed[first]:
                first += 1
                continue
            last = first + 1
            while last < len(rows) and exposed[last]:
                last += 1
            last -= 1
            length = stations[last] - stations[first]
            if length >= 14.0:
                runs.append({"side": "left" if edge == 2 else "right",
                             "start_m": round(stations[first], 2), "length_m": round(length, 2)})
                count = max(3, round(length / 4.0))
                for panel in range(count):
                    a = stations[first] + length * panel / count
                    b = stations[first] + length * (panel + 1) / count
                    knots = [a, *[s for s in stations[first:last + 1] if a < s < b], b]
                    style = 0 if panel == 0 else 2 if panel == count - 1 else 1
                    start = len(vertices)
                    wall_start = len(wall_vertices)
                    for station in knots:
                        i = min(last - 1, bisect_right(stations, station, first, last) - 1)
                        t = (station - stations[i]) / (stations[i + 1] - stations[i])
                        p = alignment[i].lerp(alignment[i + 1], t)
                        u = (station - a) / (b - a)
                        vertices.extend((p, p + Vector((0, 0, 1.18 * height_scale))))
                        uv.extend(((u, 0.0), (u, 1.0)))
                        wall_vertices.extend((p + Vector((0, 0, 0.34 * height_scale)), p + Vector((0, 0, 1.04 * height_scale))))
                    for k in range(len(knots) - 1):
                        quad = (2*k, 2*k+2, 2*k+3, 2*k+1)
                        if edge == 4:
                            quad = quad[::-1]
                        faces.append(tuple(start + j for j in quad))
                        styles.append(style)
                        wall_faces.append(tuple(wall_start + j for j in quad))
            first = last + 1

    if faces:
        rail = mesh("Guardarrail", vertices, faces, rail_materials[0], visual)
        for mat in rail_materials[1:]:
            rail.data.materials.append(mat)
        texcoords = rail.data.uv_layers.new(name="Guardarrail")
        for face, style in zip(rail.data.polygons, styles):
            face.material_index = style
            for loop in face.loop_indices:
                texcoords.data[loop].uv = uv[rail.data.loops[loop].vertex_index]
        mesh("Collision_Barrier_Guardrail", wall_vertices, wall_faces, rail_materials[1], collision)
    return {"runs": runs, "length_m": round(math.fsum(run["length_m"] for run in runs), 2)}
