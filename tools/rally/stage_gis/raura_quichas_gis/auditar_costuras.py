"""Audit exported heightfield pieces and their paired, directed boundary edges."""
from collections import defaultdict
import numpy as np
from mathutils import Vector


def point_key(point):
    return tuple(Vector(point))


def audit(objects, exterior, axis, pk):
    boundaries = defaultdict(list)
    outer = {tuple(sorted((point_key(a),point_key(b)))) for a,b in exterior}

    def fail(reason, position, name):
        nearest = min(range(len(axis)), key=lambda i: (axis[i].xy-Vector(position).xy).length_squared)
        p = axis[nearest]
        heading = axis[min(nearest+1,len(axis)-1)] - axis[max(0,nearest-1)]
        cross = heading.x*(position[1]-p.y)-heading.y*(position[0]-p.x)
        side = "izquierda" if cross > 0 else "derecha"
        station = pk[min(len(pk)-1,max(0,nearest-6))]
        raise ValueError(f"{reason} | {name} | PK {station:.2f} m | {side} | XYZ {tuple(position)}")

    for obj in objects:
        mesh = obj.data
        # A surface assembled over XY should have positive projected area.
        normal = np.empty(len(mesh.polygons)*3,dtype=np.float32)
        mesh.polygons.foreach_get("normal", normal)
        area = np.empty(len(mesh.polygons),dtype=np.float32)
        mesh.polygons.foreach_get("area", area)
        bad = np.flatnonzero((area < 1e-10) | (normal[2::3] <= 0))
        if bad.size:
            fail("Cara degenerada o invertida", mesh.polygons[int(bad[0])].center, obj.name)
        vertices = np.empty(len(mesh.loops),dtype=np.int32)
        edges = np.empty(len(mesh.loops),dtype=np.int32)
        mesh.loops.foreach_get("vertex_index",vertices)
        mesh.loops.foreach_get("edge_index",edges)
        used = np.bincount(vertices,minlength=len(mesh.vertices))
        loose = np.flatnonzero(used == 0)
        if loose.size:
            fail("Vértice sin cara", mesh.vertices[int(loose[0])].co, obj.name)
        counts = np.bincount(edges,minlength=len(mesh.edges))
        ends = np.empty(len(mesh.edges)*2,dtype=np.int32)
        mesh.edges.foreach_get("vertices",ends)
        ends = ends.reshape(-1,2)
        orientation = np.bincount(edges, weights=np.where(vertices==ends[edges,0],1,-1),
                                  minlength=len(mesh.edges))
        bad = np.flatnonzero((counts == 0) | (counts > 2) | ((counts == 2) & (orientation != 0)))
        if bad.size:
            fail("Arista suelta, múltiple o de orientación inválida",mesh.vertices[int(ends[bad[0],0])].co,obj.name)
        for i in np.flatnonzero(counts == 1):
            a,b = (point_key(mesh.vertices[int(j)].co) for j in ends[i])
            key = tuple(sorted((a,b)))
            sign = (1 if a < b else -1)*int(orientation[i])
            boundaries[key].append((obj.name,sign))
    for key, incidents in boundaries.items():
        if key in outer and len(incidents)==1:
            continue
        if len(incidents)!=2 or incidents[0][1]+incidents[1][1]!=0:
            fail("Costura abierta, duplicada o unión en T",key[0],", ".join(n for n,_ in incidents))
    print(f"RAURA_SEAM_AUDIT pieces={len(objects)} paired={len(boundaries)-len(outer)} exterior={len(outer)}")
