"""Materials and perimeter for the compact SS01 terrain."""
import math

from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import delaunay_2d_cdt
from mathutils.noise import noise


def paint_ground(background, uv, vertices, output, material):
    data = background.data
    data.materials.clear()
    for name in ("pasto_denso", "pasto_ralo", "pedregal"):
        mat = material("rajuntay_" + name, output / (name + ".png"))
        next(node for node in mat.node_tree.nodes if node.type == "TEX_IMAGE").interpolation = "Closest"
        data.materials.append(mat)
    for face in data.polygons:
        patch = noise(face.center * 0.043)
        face.material_index = 2 if abs(face.normal.z) < 0.82 else int(patch < -0.06)
    for loop in data.loops:
        x, y, _ = vertices[loop.vertex_index]
        uv.data[loop.index].uv = (x / 3.5, y / 3.5)


def build_barrier(ring, origin, ground_vertices, ground_faces, dem, mesh, material, collection):
    terrain = BVHTree.FromPolygons(ground_vertices, ground_faces, all_triangles=True)
    vertices, faces = [], []
    open_m = 0.0
    for a, b in zip(ring, ring[1:] + ring[:1]):
        a, b = Vector(a) - origin.xy, Vector(b) - origin.xy
        delta = b - a
        if delta.length < 0.001:
            continue
        outward = Vector((delta.y, -delta.x)).normalized()
        middle = (a + b) * 0.5
        # Leave steep descending slopes open. Sample the DEM outside the wall
        # footprint so a cliff at the outer edge does not become a guardrail.
        if dem(*(middle - outward * 12.0)) - dem(*(middle + outward * 12.0)) >= 14.0:
            open_m += delta.length
            continue
        index = len(vertices)
        for x, y in (a, b):
            hit, _, _, _ = terrain.ray_cast(Vector((x, y, 500)), Vector((0, 0, -1)))
            assert hit is not None, f"Barrier outside generated terrain at {(x, y)}"
            vertices.extend(((x, y, hit.z - 2.0), (x, y, hit.z + 4.0)))
        faces.append((index, index+2, index+3, index+1))
    if faces:
        mesh("Collision_Barrier_Rajuntay", vertices, faces, material, collection)
    return {"segments": len(faces), "open_steep_slope_m": round(open_m, 2)}


def build_backdrop(ring, bands, origin, samples, dem, inside, mesh, material, collection):
    # Low-density visual continuation under fog. It shares the DEM elevations
    # along the playable corridor, and is intentionally absent from collision.
    vertices = [(x, y, dem(x, y)) for x, y in ring]
    for x, y, z in samples:
        point = (x - origin.x, y - origin.y)
        if not inside(point, bands):
            vertices.append((*point, z - origin.z))
    edges = [(i, (i+1) % len(ring)) for i in range(len(ring))]
    points, _, triangles, originals, _, _ = delaunay_2d_cdt(
        [Vector(point[:2]) for point in vertices], edges, [], 0, 0.0001)
    faces = []
    for face in triangles:
        a, b, c = (points[i] for i in face)
        center = tuple(sum(float(points[i][axis]) for i in face) / 3 for axis in (0, 1))
        if abs((b - a).cross(c - a)) > 0.001 and not inside(center, bands):
            faces.append(face)
    positions = [(p.x, p.y, vertices[ids[0]][2] if ids else dem(p.x, p.y))
                 for p, ids in zip(points, originals)]
    backdrop = mesh("Rajuntay DEM fondo", positions, faces, material, collection)
    uv = backdrop.data.uv_layers.new()
    for loop in backdrop.data.loops:
        x, y, _ = positions[loop.vertex_index]
        uv.data[loop.index].uv = (x / 3.5, y / 3.5)


def build_finish_boards(center, forward, row, mesh, material, collection):
    right = Vector((forward.y, -forward.x, 0.0))
    white = material("Meta blanco", (0.92, 0.92, 0.87))
    dark = material("Meta negro", (0.035, 0.035, 0.035))
    for label, side, shoulder in (("L", -1, row[1]), ("R", 1, row[5])):
        base = center + right * (4.4 * side)
        base.z = shoulder[2]
        vertices = [base + right * x + Vector((0, 0, z)) for z in (0.8, 1.05, 1.3, 1.55)
                    for x in (-0.5, -0.25, 0.0, 0.25, 0.5)]
        faces = [(i, i+1, i+6, i+5) for i in (0, 1, 2, 3, 5, 6, 7, 8, 10, 11, 12, 13)]
        board = mesh("Meta_" + label, vertices, faces, white, collection)
        board.data.materials.append(dark)
        for face in board.data.polygons:
            y, x = divmod(face.index, 4)
            face.material_index = (x + y) % 2
        for post, offset in enumerate((-0.37, 0.37)):
            support = [base + right * (offset + x) + Vector((0, 0, z))
                       for z in (-0.12, 0.81) for x in (-0.045, 0.045)]
            mesh(f"Meta_{label}_soporte_{post}", support, [(0, 1, 3, 2)], dark, collection)
