"""
Blender headless worker that extracts all mesh nodes from all target vehicle .glb files
into .obj files for PyMeshLab and MeshLib auditing, while also capturing GLB scene-graph,
material, UV, normal, and shape-key metadata.
"""

import json
import struct
import sys
from collections import Counter
from pathlib import Path

import bpy
import bmesh


def glb_json_chunk(path: Path) -> dict:
    blob = path.read_bytes()
    if len(blob) < 20 or blob[:4] != b"glTF":
        raise ValueError(f"Invalid GLB header: {path}")
    length = struct.unpack_from("<I", blob, 8)[0]
    if length != len(blob):
        raise ValueError(f"GLB size mismatch: header={length}, actual={len(blob)}")
    chunk_len, chunk_type = struct.unpack_from("<II", blob, 12)
    if chunk_type != 0x4E4F534A:
        raise ValueError(f"Missing JSON chunk in {path}")
    return json.loads(blob[20 : 20 + chunk_len])


def canonical_same_winding(tri: tuple) -> tuple:
    m = min(tri)
    idx = tri.index(m)
    return tri[idx:] + tri[:idx]


def write_obj_fast(obj, filepath: Path):
    """Write world-space triangulated mesh to OBJ for PyMeshLab and MeshLib."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.transform(bm, matrix=obj.matrix_world, verts=bm.verts)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()

    lines = [f"# Exported from {obj.name}\n"]
    for v in bm.verts:
        lines.append(f"v {v.co.x:.7f} {v.co.y:.7f} {v.co.z:.7f}\n")
    for f in bm.faces:
        i0, i1, i2 = f.verts[0].index + 1, f.verts[1].index + 1, f.verts[2].index + 1
        lines.append(f"f {i0} {i1} {i2}\n")

    filepath.parent.mkdir(parents=True, exist_ok=True)
    filepath.write_text("".join(lines), encoding="utf-8")
    bm.free()


def analyze_bmesh_topology(obj) -> dict:
    """
    Analyze bmesh topology while properly distinguishing intentional double-sided
    shells (back-to-back opposite-winding triangles) from true geometric defects.
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.transform(bm, matrix=obj.matrix_world, verts=bm.verts)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()

    raw_verts = len(bm.verts)
    raw_faces = len(bm.faces)
    loose_verts = sum(1 for v in bm.verts if not v.link_faces)
    loose_edges = sum(1 for e in bm.edges if not e.link_faces)

    def rpos(v):
        return tuple(round(c, 4) for c in v.co)

    zero_area_faces = 0
    sliver_faces = 0
    valid_oriented_tris = []

    for f in bm.faces:
        pts = tuple(rpos(v) for v in f.verts)
        area = f.calc_area()
        if area < 1e-7 or len(set(pts)) < 3:
            zero_area_faces += 1
            continue

        lengths = [e.calc_length() for e in f.edges]
        max_l = max(lengths) if lengths else 0.0
        if max_l > 1e-6 and (area / (max_l * max_l)) < 0.002:
            sliver_faces += 1

        valid_oriented_tris.append(canonical_same_winding(pts))

    # 1. Exact same-winding duplicate triangles (cause Z-fighting)
    oriented_counts = Counter(valid_oriented_tris)
    same_winding_duplicates = sum(c - 1 for c in oriented_counts.values() if c > 1)

    # 2. Separate double-sided pairs from single-sided triangles
    unoriented_map = {}
    for tri in set(valid_oriented_tris):
        key = tuple(sorted(tri))
        unoriented_map.setdefault(key, []).append(tri)

    double_sided_pairs = sum(1 for tris in unoriented_map.values() if len(tris) > 1)
    single_sided_tris = [tris[0] for tris in unoriented_map.values() if len(tris) == 1]

    # 3. Check winding continuity & non-manifold edges on single-sided surface
    directed_edges = Counter()
    undirected_edges = Counter()
    for a, b, c in single_sided_tris:
        for u, v in ((a, b), (b, c), (c, a)):
            directed_edges[(u, v)] += 1
            undirected_edges[tuple(sorted((u, v)))] += 1

    single_sided_non_manifold_edges = sum(1 for cnt in undirected_edges.values() if cnt > 2)
    inverted_winding_edges = 0
    for (u, v), cnt in directed_edges.items():
        ukey = tuple(sorted((u, v)))
        if undirected_edges[ukey] == 2 and cnt == 2:
            inverted_winding_edges += 1

    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-4)
    welded_verts = len(bm.verts)
    welded_faces = len(bm.faces)
    bm.free()

    return {
        "raw_vertices": raw_verts,
        "raw_faces": raw_faces,
        "welded_vertices": welded_verts,
        "welded_faces": welded_faces,
        "loose_vertices": loose_verts,
        "loose_edges": loose_edges,
        "zero_area_faces": zero_area_faces,
        "sliver_faces": sliver_faces,
        "same_winding_duplicates": same_winding_duplicates,
        "double_sided_pairs": double_sided_pairs,
        "single_sided_non_manifold_edges": single_sided_non_manifold_edges,
        "inverted_winding_edges": inverted_winding_edges,
    }


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :]
    manifest_in = Path(argv[0]).resolve()
    out_dir = Path(argv[1]).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    targets = json.loads(manifest_in.read_text(encoding="utf-8"))
    results = []

    for item in targets:
        vehicle_id = item["vehicle_id"]
        rel_glb = item["rel_path"]
        glb_path = Path(item["abs_path"])

        entry = {
            "vehicle_id": vehicle_id,
            "rel_path": rel_glb,
            "abs_path": str(glb_path),
            "container_valid": True,
            "container_errors": [],
            "embedded_images": 0,
            "external_image_uris": [],
            "nodes": [],
            "meshes": [],
        }

        try:
            doc = glb_json_chunk(glb_path)
            images = doc.get("images", [])
            entry["embedded_images"] = len(images)
            for img in images:
                if "uri" in img:
                    entry["external_image_uris"].append(img["uri"])
        except Exception as e:
            entry["container_valid"] = False
            entry["container_errors"].append(str(e))
            results.append(entry)
            continue

        bpy.ops.wm.read_factory_settings(use_empty=True)
        try:
            bpy.ops.import_scene.gltf(filepath=str(glb_path))
            bpy.context.view_layer.update()
        except Exception as e:
            entry["container_valid"] = False
            entry["container_errors"].append(f"Blender import failed: {e}")
            results.append(entry)
            continue

        for obj in sorted(bpy.data.objects, key=lambda o: o.name):
            entry["nodes"].append({"name": obj.name, "type": obj.type})
            if obj.type != "MESH":
                continue

            safe_name = "".join(c if c.isalnum() or c in ("_", "-") else "_" for c in obj.name)
            glb_stem = Path(rel_glb).stem
            obj_out = out_dir / "meshes" / vehicle_id / glb_stem / f"{safe_name}.obj"
            write_obj_fast(obj, obj_out)

            bmesh_stats = analyze_bmesh_topology(obj)
            shape_key_count = (
                len(obj.data.shape_keys.key_blocks) - 1
                if obj.data.shape_keys and obj.data.shape_keys.key_blocks
                else 0
            )
            materials = []
            for mat in obj.data.materials:
                if mat:
                    materials.append(
                        {
                            "name": mat.name,
                            "backface_culling": bool(getattr(mat, "use_backface_culling", False)),
                        }
                    )
                else:
                    materials.append({"name": None, "backface_culling": False})

            unassigned_polys = sum(
                1
                for p in obj.data.polygons
                if p.material_index >= len(obj.data.materials)
                or obj.data.materials[p.material_index] is None
            )

            entry["meshes"].append(
                {
                    "node_name": obj.name,
                    "obj_path": str(obj_out),
                    "uv_layers": len(obj.data.uv_layers),
                    "shape_keys": shape_key_count,
                    "materials": materials,
                    "unassigned_material_polygons": unassigned_polys,
                    "bmesh": bmesh_stats,
                }
            )

        results.append(entry)

    out_json = out_dir / "blender_extracted.json"
    out_json.write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(f"ALL_EXTRACTED: {len(results)} GLB files -> {out_json}")


if __name__ == "__main__":
    main()
