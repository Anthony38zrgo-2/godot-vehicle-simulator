"""
Blender headless surgical repair worker for vehicle .glb files.
Repairs:
1. Zero-area / collapsed degenerate triangles (area < 1e-7 or <3 unique vertices)
2. Same-winding duplicate triangles (retaining the copy with the largest UV area)
3. Single-sided inverted triangles (where >=2 shared edges with single-sided neighbors have conflicting winding)
4. Orphaned / loose vertices and edges
Preserves 100% of node hierarchies, materials, embedded textures, UVs, custom normals on untouched faces,
and all 19 Shape Keys on DriverArm_left_frame09 / DriverArm_right_frame09.
"""

import json
import sys
from collections import Counter
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector


def canonical_same_winding(tri: tuple) -> tuple:
    m = min(tri)
    idx = tri.index(m)
    return tri[idx:] + tri[:idx]


def calc_uv_area(bm_face, uv_layer) -> float:
    if not uv_layer or len(bm_face.loops) < 3:
        return 0.0
    uv0 = bm_face.loops[0][uv_layer].uv
    uv1 = bm_face.loops[1][uv_layer].uv
    uv2 = bm_face.loops[2][uv_layer].uv
    return 0.5 * abs((uv1.x - uv0.x) * (uv2.y - uv0.y) - (uv2.x - uv0.x) * (uv1.y - uv0.y))


def repair_mesh_object(obj) -> dict:
    # Never alter topology of shape-key (morph target) meshes like DriverArm_*
    if obj.data.shape_keys and obj.data.shape_keys.key_blocks:
        return {"skipped_shape_keys": True, "zero_deleted": 0, "dups_deleted": 0, "inverted_flipped": 0, "loose_verts_deleted": 0}

    mw = obj.matrix_world
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    uv_layer = bm.loops.layers.uv.active

    def rpos(v):
        wco = mw @ v.co
        return (round(wco.x, 4), round(wco.y, 4), round(wco.z, 4))

    def world_area(f):
        pts = [mw @ v.co for v in f.verts]
        if len(pts) < 3:
            return 0.0
        return 0.5 * (pts[1] - pts[0]).cross(pts[2] - pts[0]).length

    # 1. Find zero-area / collapsed faces
    zero_faces = []
    valid_faces = []
    for f in bm.faces:
        pts = tuple(rpos(v) for v in f.verts)
        if len(pts) != 3 or len(set(pts)) < 3 or world_area(f) < 1e-7:
            zero_faces.append(f)
        else:
            valid_faces.append((f, pts))

    # 2. Find same-winding duplicate faces (keep copy with largest UV area)
    oriented_groups = {}
    for f, pts in valid_faces:
        key = canonical_same_winding(pts)
        oriented_groups.setdefault(key, []).append((f, pts))

    dup_faces = []
    deduped_faces = []
    for key, group in oriented_groups.items():
        if len(group) == 1:
            deduped_faces.append(group[0])
        else:
            # Sort descending by UV area (tie-break by lower face index)
            ranked = sorted(group, key=lambda item: (-calc_uv_area(item[0], uv_layer), item[0].index))
            deduped_faces.append(ranked[0])
            for extra_f, _ in ranked[1:]:
                dup_faces.append(extra_f)

    # 3. Find isolated inverted single-sided faces
    unoriented_groups = {}
    for f, pts in deduped_faces:
        ukey = tuple(sorted(pts))
        unoriented_groups.setdefault(ukey, []).append((f, pts))

    single_sided = [items[0] for items in unoriented_groups.values() if len(items) == 1]

    edge_map = {}
    for f, pts in single_sided:
        for i in range(3):
            u, v = pts[i], pts[(i + 1) % 3]
            ukey = tuple(sorted((u, v)))
            edge_map.setdefault(ukey, []).append((f, (u, v)))

    conflict_count = Counter()
    proper_count = Counter()
    for ukey, incidences in edge_map.items():
        if len(incidences) == 2:
            (f0, dir0), (f1, dir1) = incidences
            if dir0 == dir1:
                conflict_count[f0.index] += 1
                conflict_count[f1.index] += 1
            else:
                proper_count[f0.index] += 1
                proper_count[f1.index] += 1

    faces_to_flip = []
    for f, _ in single_sided:
        c_bad = conflict_count[f.index]
        c_good = proper_count[f.index]
        if c_bad >= 2 and c_bad > c_good:
            faces_to_flip.append(f)

    flipped_count = len(faces_to_flip)
    if faces_to_flip:
        bmesh.ops.reverse_faces(bm, faces=faces_to_flip)

    to_delete = list(set(zero_faces + dup_faces))
    if to_delete:
        bmesh.ops.delete(bm, geom=to_delete, context="FACES")

    loose_verts = [v for v in bm.verts if not v.link_faces]
    loose_edges = [e for e in bm.edges if not e.link_faces]
    if loose_edges:
        bmesh.ops.delete(bm, geom=loose_edges, context="EDGES")
    if loose_verts:
        bmesh.ops.delete(bm, geom=loose_verts, context="VERTS")

    modified = bool(to_delete or faces_to_flip or loose_verts or loose_edges)
    if modified:
        bm.normal_update()
        bm.to_mesh(obj.data)
        obj.data.update()

    bm.free()
    return {
        "skipped_shape_keys": False,
        "modified": modified,
        "zero_deleted": len(zero_faces),
        "dups_deleted": len(dup_faces),
        "inverted_flipped": flipped_count,
        "loose_verts_deleted": len(loose_verts),
    }


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :]
    jobs_path = Path(argv[0]).resolve()
    jobs = json.loads(jobs_path.read_text(encoding="utf-8"))

    reports = []
    for job in jobs:
        glb_path = Path(job["abs_path"])
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(glb_path))
        bpy.context.view_layer.update()

        any_modified = False
        mesh_reports = {}
        for obj in sorted(bpy.data.objects, key=lambda o: o.name):
            if obj.type != "MESH":
                continue
            res = repair_mesh_object(obj)
            if res.get("modified"):
                any_modified = True
                mesh_reports[obj.name] = res

        if any_modified:
            # Ensure all objects are visible and selectable for clean GLB export
            for obj in bpy.data.objects:
                obj.hide_set(False)
                obj.hide_render = False
            bpy.ops.export_scene.gltf(
                filepath=str(glb_path),
                export_format="GLB",
                use_selection=False,
                export_morph=True,
                export_animations=False,
            )
            print(f"REPAIRED_GLB: {job['vehicle_id']} -> {job['rel_path']} | {mesh_reports}")

        reports.append(
            {
                "vehicle_id": job["vehicle_id"],
                "rel_path": job["rel_path"],
                "abs_path": str(glb_path),
                "repaired": any_modified,
                "meshes": mesh_reports,
            }
        )

    out_report = jobs_path.with_name("repair_worker_report.json")
    out_report.write_text(json.dumps(reports, indent=2), encoding="utf-8")
    print(f"REPAIR_WORKER_DONE: {sum(1 for r in reports if r['repaired'])} GLBs modified")


if __name__ == "__main__":
    main()
