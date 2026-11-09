#!/usr/bin/env python3
"""Count real glTF primitive/material triangles in Sweden's eight stage GLBs.

Run from the repository root:
    python tools/rally/audit_sweden_glb.py
    python tools/rally/audit_sweden_glb.py --json game/docs/rally/sweden_surface_audit.json

Uses only Python's standard library. Does not alter GLBs. Counts indexed
triangle primitives from accessor.count; no image decoding or Blender needed.
"""
import argparse
import json
import struct
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "game" / "assets" / "rally"
GLB_MAGIC = b"glTF"
JSON_CHUNK = 0x4E4F534A
TRIANGLES = 4
TRIANGLE_STRIP = 5
TRIANGLE_FAN = 6


def open_gltf_json(path):
    with path.open("rb") as file:
        header = file.read(12)
        if len(header) != 12:
            raise ValueError("GLB header is incomplete")
        magic, version, length = struct.unpack("<4sII", header)
        if magic != GLB_MAGIC or version != 2:
            raise ValueError("Not a GLB 2.0 file")
        if length != path.stat().st_size:
            raise ValueError("Declared GLB length differs from file size")
        while file.tell() < length:
            chunk_header = file.read(8)
            if len(chunk_header) != 8:
                raise ValueError("Truncated GLB chunk")
            size, kind = struct.unpack("<II", chunk_header)
            data = file.read(size)
            if len(data) != size:
                raise ValueError("Truncated GLB payload")
            if kind == JSON_CHUNK:
                return json.loads(data.decode("utf-8").rstrip("\0 \t\r\n"))
    raise ValueError("No JSON chunk in GLB")


def classify(material):
    m = material.lower().strip()
    if m.startswith("road_snow_") or m == "road_snow":
        return "snow_packed"
    if m.startswith("erosion_snow_"):
        return "snow_loose"
    if m.startswith("road_ice_") or m == "road_ice":
        return "ice_explicit"
    if m.startswith("road_"):
        return "road_uncovered_or_unknown"
    if "snow" in m:
        return "other_snow_material_review"
    if "ice" in m:
        return "other_ice_material_review"
    return "other"


def triangle_count(doc, primitive):
    mode = int(primitive.get("mode", TRIANGLES))
    accessors = doc.get("accessors", [])
    indices = primitive.get("indices")
    if indices is not None:
        count = int(accessors[indices].get("count", 0))
    else:
        position = primitive.get("attributes", {}).get("POSITION")
        count = int(accessors[position].get("count", 0)) if position is not None else 0
    if mode == TRIANGLES:
        if count % 3:
            raise ValueError("Triangle primitive has a non-multiple-of-three vertex/index count")
        return count // 3
    if mode in (TRIANGLE_STRIP, TRIANGLE_FAN):
        return max(count - 2, 0)
    return 0


def inspect(path):
    doc = open_gltf_json(path)
    meshes = doc.get("meshes", [])
    materials = doc.get("materials", [])
    nodes = doc.get("nodes", [])
    parents = {}
    for idx, node in enumerate(nodes):
        for child in node.get("children", []):
            parents[int(child)] = idx
    by_material = defaultdict(lambda: {"triangles": 0, "primitives": 0, "nodes": set()})
    by_category = Counter()
    by_node = Counter()
    no_material = 0
    total_triangles = 0
    for node_index, node in enumerate(nodes):
        mesh_index = node.get("mesh")
        if mesh_index is None:
            continue
        node_name = str(node.get("name", f"node_{node_index}"))
        # Retain parent hierarchy for identifying the Collision_Road family.
        lineage = [node_name]
        parent = parents.get(node_index)
        while parent is not None:
            lineage.append(str(nodes[parent].get("name", f"node_{parent}")))
            parent = parents.get(parent)
        lineage.reverse()
        node_path = "/".join(lineage)
        for primitive in meshes[mesh_index].get("primitives", []):
            triangles = triangle_count(doc, primitive)
            material_index = primitive.get("material")
            material_name = (
                str(materials[material_index].get("name", f"material_{material_index}"))
                if material_index is not None else "<NO_MATERIAL>"
            )
            if material_index is None:
                no_material += triangles
            category = classify(material_name)
            info = by_material[material_name]
            info["triangles"] += triangles
            info["primitives"] += 1
            info["nodes"].add(node_path)
            by_category[category] += triangles
            by_node[node_path] += triangles
            total_triangles += triangles
    return {
        "file": str(path.relative_to(ROOT)),
        "total_triangles": total_triangles,
        "triangles_without_material": no_material,
        "by_category": dict(sorted(by_category.items())),
        "by_material": [
            {"material": name, "category": classify(name),
             "triangles": value["triangles"], "primitives": value["primitives"],
             "nodes": sorted(value["nodes"])}
            for name, value in sorted(by_material.items(), key=lambda item: -item[1]["triangles"])
        ],
        "by_node": dict(sorted(by_node.items())),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", type=Path, help="Optional JSON report destination")
    args = parser.parse_args()
    report = {"stages": {}, "summary_by_category": {}, "warnings": []}
    summary = Counter()
    for stage_no in range(1, 9):
        stage = f"sweden_stage{stage_no}"
        stage_data = {}
        for kind in ("collision", "visual"):
            path = ASSETS / stage / f"{stage}_{kind}.glb"
            if not path.exists():
                report["warnings"].append(f"Missing {path.relative_to(ROOT)}")
                continue
            data = inspect(path)
            stage_data[kind] = data
            for key, count in data["by_category"].items():
                summary[f"{kind}:{key}"] += count
            if kind == "collision" and data["triangles_without_material"]:
                report["warnings"].append(
                    f"{stage}: {data['triangles_without_material']} collision triangles lack a glTF material"
                )
        report["stages"][stage] = stage_data
        col = stage_data.get("collision", {})
        vis = stage_data.get("visual", {})
        print(f"{stage}: collision={col.get('total_triangles', 'missing')} "
              f"packed_snow={col.get('by_category', {}).get('snow_packed', 0)} "
              f"ice={col.get('by_category', {}).get('ice_explicit', 0)} "
              f"visual_snow_bank={vis.get('by_category', {}).get('snow_loose', 0)}")
    report["summary_by_category"] = dict(sorted(summary.items()))
    print("\nTOTALS", json.dumps(report["summary_by_category"], ensure_ascii=False))
    for warning in report["warnings"]:
        print("WARNING", warning)
    if args.json:
        output = args.json if args.json.is_absolute() else ROOT / args.json
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("Report:", output)


if __name__ == "__main__":
    main()
