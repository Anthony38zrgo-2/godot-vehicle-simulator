"""Recover per-triangle materials in Sweden collision .blend scenes and re-export.

Root cause: tools/stage_builder.py (external Rally Trophy exporter) accumulates
collision faces without material slots (data_by_col has no mat_ids/mat_slot_map
and the mesh creation never sets polygon.material_index), so the exported
*_collision.glb files carry zero glTF materials.

This tool repairs the already-built .blend scenes by geometric correspondence:
every collision triangle is matched against the visual meshes of the SAME scene
(same float coordinates, same 1mm rounding as the builder). No proximity
invention: exact match first, then 1cm-grid fallback (sign decals offset by
2mm), then nearest-centroid under 15mm. Anything else stays material-less and
is reported, never guessed.

Erosion banks (erosion_snow_*): the runtime rebuilds them from the visual GLB
in RallyTrackCollisionBuilder.build_erosion_bank_collision(), so keeping them
in the exported collision GLB duplicates colliders. Exactly-matched erosion
triangles are removed from the exported collision (logged); the runtime banks
remain the single source. All other faces keep their geometry untouched.

Run from the repository root with Blender 5.2 (same major as the exporter)::

    blender --background --python tools/rally/fix_sweden_collision_materials.py -- \
        --stage-dir D:/games/rally-throphy/stage_exporter/stages/sweden/stage1

Dry run by default (report only, no writes). Add --apply to assign materials,
exclude duplicated erosion banks, save the .blend, re-export the collision GLB
(full material EXPORT with names preserved; images stripped in memory only,
never saved) and refresh the stage manifest + collision_summary metadata.

Only standard library + bpy. No physics, tire or gameplay changes.
"""

import argparse
import hashlib
import json
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path

VISUAL_OBJECTS = {
    "Track_Road_And_Terrain",
    "Buildings_And_Structures",
    "Fences_And_Barriers",
    "Foliage_And_Vegetation",
    "Props_And_Markers",
}
COLLISION_PREFIX = "Collision_"
EROSION_PREFIX = "erosion_snow_"
NEAREST_LIMIT_M = 0.015


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def world_tris(obj):
    ws = obj.matrix_world
    for poly in obj.data.polygons:
        pts = []
        for li in poly.loop_indices:
            co = ws @ obj.data.vertices[obj.data.loops[li].vertex_index].co
            pts.append((co.x, co.y, co.z))
        yield poly, pts


def fkey(pts, rnd):
    return frozenset((round(x, rnd), round(y, rnd), round(z, rnd)) for x, y, z in pts)


def centroid(pts):
    n = len(pts)
    return (sum(p[0] for p in pts) / n, sum(p[1] for p in pts) / n, sum(p[2] for p in pts) / n)


def dist(a, b):
    return math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)


def main():
    import bpy

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage-dir", required=True, type=Path)
    parser.add_argument("--apply", action="store_true",
                        help="Write .blend, re-export collision GLB, refresh metadata.")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])

    stage_dir = Path(str(args.stage_dir))
    blends = sorted(stage_dir.glob("sweden_stage*.blend"))
    if not blends:
        raise FileNotFoundError(f"No sweden_stage*.blend in {stage_dir}")
    blend_path = blends[0]
    track_id = blend_path.stem

    bpy.ops.wm.open_mainfile(filepath=str(blend_path))

    # ---- visual lookup ----------------------------------------------------
    look3, look2 = {}, {}
    grid = defaultdict(list)
    visual_tri_count = Counter()
    CELL = 1.0
    for o in bpy.data.objects:
        if o.type != "MESH" or o.name not in VISUAL_OBJECTS:
            continue
        mats = [m.name if m else "<None>" for m in o.data.materials]
        for poly, pts in world_tris(o):
            mat = mats[poly.material_index] if poly.material_index < len(mats) else "<None>"
            visual_tri_count[mat] += 1
            look3.setdefault(fkey(pts, 3), set()).add(mat)
            look2.setdefault(fkey(pts, 2), set()).add((mat, centroid(pts)))
            c = centroid(pts)
            grid[(math.floor(c[0] / CELL), math.floor(c[1] / CELL), math.floor(c[2] / CELL))].append(
                (c, mat))

    def nearest(c):
        best = None
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for vc, vm in grid[(math.floor(c[0] / CELL) + dx,
                                        math.floor(c[1] / CELL) + dy,
                                        math.floor(c[2] / CELL) + dz)]:
                        d = dist(c, vc)
                        if best is None or d < best[0]:
                            best = (d, vm)
        return best

    # ---- match collision --------------------------------------------------
    report = {"track_id": track_id, "blend": str(blend_path), "objects": {},
              "erosion_excluded": {}, "warnings": []}
    assignments = {}  # (obj_name, poly_index) -> (material, method)
    for o in sorted(bpy.data.objects, key=lambda x: x.name):
        if o.type != "MESH" or not o.name.startswith(COLLISION_PREFIX):
            continue
        methods = Counter()
        per_mat = Counter()
        amb = Counter()
        for idx, (poly, pts) in enumerate(world_tris(o)):
            cand = look3.get(fkey(pts, 3))
            if cand and len(cand) == 1:
                mat = next(iter(cand))
                assignments[(o.name, idx)] = (mat, "exact")
                methods["exact"] += 1
                per_mat[mat] += 1
                continue
            if cand and len(cand) > 1:
                # Same triangle under two visual materials: pick the visually
                # dominant one (deterministic, logged). No geometry invented.
                mat = sorted(cand, key=lambda m: (-visual_tri_count[m], m))[0]
                assignments[(o.name, idx)] = (mat, "ambiguous-dominant")
                methods["ambiguous"] += 1
                amb["|".join(sorted(cand))] += 1
                per_mat[mat] += 1
                continue
            cand2 = look2.get(fkey(pts, 2))
            if cand2:
                mats2 = {m for m, _ in cand2}
                if len(mats2) == 1:
                    mat = next(iter(mats2))
                    assignments[(o.name, idx)] = (mat, "fallback-1cm")
                    methods["fallback-1cm"] += 1
                    per_mat[mat] += 1
                    continue
            best = nearest(centroid(pts))
            if best is not None and best[0] < NEAREST_LIMIT_M:
                assignments[(o.name, idx)] = (best[1], f"nearest-{best[0]*1000:.1f}mm")
                methods["nearest"] += 1
                per_mat[best[1]] += 1
                continue
            methods["unmatched"] += 1
            report["warnings"].append(f"{o.name} poly {idx}: no visual twin, left material-less")
        report["objects"][o.name] = {"polys": sum(1 for _ in o.data.polygons),
                                     "methods": dict(methods),
                                     "materials": dict(per_mat),
                                     "ambiguous": dict(amb)}

    if not args.apply:
        print(json.dumps(report, ensure_ascii=False, indent=1))
        return

    import bmesh

    # ---- apply materials + exclude duplicated erosion banks ---------------
    for o in sorted(bpy.data.objects, key=lambda x: x.name):
        if o.type != "MESH" or not o.name.startswith(COLLISION_PREFIX):
            continue
        mesh = o.data
        slot_of = {}
        for si, m in enumerate(mesh.materials):
            if m is not None and m.name not in slot_of:
                slot_of[m.name] = si
        for idx, poly in enumerate(mesh.polygons):
            key = (o.name, idx)
            if key not in assignments:
                continue
            mat, method = assignments[key]
            if mat not in slot_of:
                existing = bpy.data.materials.get(mat)
                if existing is None:
                    raise RuntimeError(f"Visual material missing in .blend: {mat}")
                mesh.materials.append(existing)
                slot_of[mat] = len(mesh.materials) - 1
            poly.material_index = slot_of[mat]
        # Remove erosion banks covered by the runtime bank builder (exact
        # matches only: the runtime rebuilds from the same visual triangles).
        doomed = [idx for idx, poly in enumerate(mesh.polygons)
                  if assignments.get((o.name, idx), ("", ""))[0].startswith(EROSION_PREFIX)
                  and assignments[(o.name, idx)][1] == "exact"]
        if doomed:
            bm = bmesh.new()
            bm.from_mesh(mesh)
            bm.faces.ensure_lookup_table()
            # Collect face references BEFORE any removal: removing faces
            # invalidates the index lookup table, so index-based removal in a
            # loop silently drops faces (caught by the old try/except).
            todel = [bm.faces[i] for i in sorted(doomed)]
            removed = 0
            for face in todel:
                try:
                    bm.faces.remove(face)
                    removed += 1
                except Exception:
                    pass
            bm.to_mesh(mesh)
            bm.free()
            mesh.update()
            report["erosion_excluded"][o.name] = {"matched": len(doomed), "removed": removed}
            if removed != len(doomed):
                report["warnings"].append(
                    f"{o.name}: erosion removal incomplete ({removed}/{len(doomed)})")
        # Drop slots left without polygons.
        used = {p.material_index for p in mesh.polygons}
        for si in sorted(range(len(mesh.materials)), reverse=True):
            if si not in used:
                mesh.materials.pop(index=si)

    bpy.ops.wm.save_mainfile()

    # ---- re-export collision GLB -------------------------------------------
    # Same settings as the stage exporter, with full material EXPORT: the
    # exporter's PLACEHOLDER mode drops material references entirely
    # (verified on stage8). Images are stripped in memory before exporting
    # and the .blend is NOT re-saved afterwards, so the file on disk keeps
    # packed images and material links; the GLB carries nominal materials
    # (original names, no heavy textures).
    stripped_images = 0
    for img in list(bpy.data.images):
        try:
            bpy.data.images.remove(img)
            stripped_images += 1
        except Exception:
            pass
    report["images_stripped_for_export"] = stripped_images
    collision_objects = [o for o in bpy.data.objects
                         if o.type == "MESH" and o.name.startswith(COLLISION_PREFIX)]
    for o in bpy.data.objects:
        o.select_set(False)
    for o in collision_objects:
        o.select_set(True)
    out_glb = stage_dir / f"{track_id}_collision.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(out_glb),
        export_format="GLB",
        use_selection=True,
        export_attributes=False,
        export_apply=False,
    )

    # ---- refresh export metadata ------------------------------------------
    counts = {}
    mats_per_node = {}
    for o in collision_objects:
        counts[o.name] = sum(1 for _ in o.data.polygons)
        mats_per_node[o.name] = sorted({m.name for m in o.data.materials if m})
    manifest_path = stage_dir / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["collision"]["sha256"] = sha256_file(out_glb)
    manifest["collision"]["size_bytes"] = out_glb.stat().st_size
    manifest["collision"]["collision_objects"] = counts
    manifest["collision"]["materials"] = mats_per_node
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                             encoding="utf-8")
    summary_path = stage_dir / "collision_summary.json"
    if summary_path.exists():
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
        summary["collision_objects"] = counts
        summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
                                encoding="utf-8")
    report["reexport"] = {"glb": str(out_glb), "sha256": manifest["collision"]["sha256"],
                          "size_bytes": manifest["collision"]["size_bytes"],
                          "counts": counts, "materials": mats_per_node}
    print(json.dumps(report, ensure_ascii=False, indent=1))


main()
