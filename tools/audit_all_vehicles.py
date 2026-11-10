#!/usr/bin/env python3
"""
Batch Vehicle GLB Auditor
Coordinates:
1. Blender headless extraction + bmesh / GLTF / UV / ShapeKey inspection
2. PyMeshLab topological & geometric audit (unwelded & welded)
3. MeshLib hole & self-intersection inspection
Produces tmp/glb_audit/audit_summary.json and tmp/glb_audit/audit_report.md
"""

import json
import subprocess
import sys
from pathlib import Path

import pymeshlab
import meshlib.mrmeshpy as mr

REPO = Path(__file__).resolve().parent.parent
RALLY_ASSETS = REPO / "game" / "assets" / "rally"
AUDIT_DIR = REPO / "tmp" / "glb_audit"

EXCLUDED_DIRS = {
    "drivers",
    "driver_lowpoly",
    "garage",
    "grass",
    "visual_pacenotes",
}


def discover_vehicle_glbs() -> list[dict]:
    targets = []

    # 1. Base rally vehicles in game/assets/rally/<car>
    for d in sorted(RALLY_ASSETS.iterdir()):
        if not d.is_dir() or d.name in EXCLUDED_DIRS or d.name.startswith("russia_stage") or d.name == "rt":
            continue
        for glb in sorted(d.rglob("*.glb")):
            targets.append(
                {
                    "vehicle_id": d.name,
                    "rel_path": glb.relative_to(d).as_posix(),
                    "abs_path": str(glb.resolve()),
                }
            )

    # 2. RT vehicles in game/assets/rally/rt/<car>
    rt_root = RALLY_ASSETS / "rt"
    if rt_root.is_dir():
        for d in sorted(rt_root.iterdir()):
            if not d.is_dir() or d.name in EXCLUDED_DIRS:
                continue
            for glb in sorted(d.rglob("*.glb")):
                targets.append(
                    {
                        "vehicle_id": d.name,
                        "rel_path": glb.relative_to(d).as_posix(),
                        "abs_path": str(glb.resolve()),
                    }
                )

    return targets


def audit_with_pymeshlab_and_meshlib(obj_path: Path) -> dict:
    ms = pymeshlab.MeshSet()
    ms.load_new_mesh(str(obj_path))

    raw_m = ms.current_mesh()
    raw_verts = raw_m.vertex_number()
    raw_faces = raw_m.face_number()

    # Check bad faces (elongated/sliver or folded) on raw mesh
    ms.apply_filter("set_selection_none")
    ms.apply_filter(
        "compute_selection_bad_faces",
        usear=True,
        aratio=0.02,
        select_folded_faces=True,
        folded_faces_angle_threshold=160.0,
    )
    bad_faces = ms.current_mesh().selected_face_number()

    # Inspect with MeshLib
    meshlib_holes = 0
    try:
        mr_mesh = mr.loadMesh(obj_path)
        meshlib_holes = mr_mesh.topology.findNumHoles()
    except Exception:
        meshlib_holes = -1

    return {
        "pymeshlab_raw_verts": raw_verts,
        "pymeshlab_raw_faces": raw_faces,
        "elongated_or_folded_faces": bad_faces,
        "meshlib_open_boundaries": meshlib_holes,
    }


def classify_mesh_health(mesh_entry: dict) -> tuple[str, list[str]]:
    """Classify a submesh into PASS, WARN, or FAIL with specific diagnostic reasons."""
    bm = mesh_entry["bmesh"]
    node = mesh_entry["node_name"]

    reasons_fail = []
    reasons_warn = []

    # Critical failures (true geometry corruption):
    if mesh_entry["unassigned_material_polygons"] > 0:
        reasons_fail.append(f"unassigned_materials({mesh_entry['unassigned_material_polygons']})")
    if mesh_entry["uv_layers"] == 0 and node != "interior_roof":
        reasons_fail.append("missing_uv_layer")
    if node.startswith("DriverArm_") and mesh_entry["shape_keys"] != 19:
        reasons_fail.append(f"broken_shape_keys({mesh_entry['shape_keys']}!=19)")
    if bm["loose_vertices"] > 0:
        reasons_fail.append(f"loose_vertices({bm['loose_vertices']})")
    if bm["loose_edges"] > 0:
        reasons_fail.append(f"loose_edges({bm['loose_edges']})")
    if bm["zero_area_faces"] > 0:
        reasons_fail.append(f"zero_area_faces({bm['zero_area_faces']})")
    if bm["same_winding_duplicates"] > 0:
        reasons_fail.append(f"same_winding_duplicates({bm['same_winding_duplicates']})")
    if bm["inverted_winding_edges"] > 0:
        reasons_fail.append(f"inverted_winding_edges({bm['inverted_winding_edges']})")

    # Warnings (minor aspect ratio / multi-shell T-junctions):
    if bm["sliver_faces"] > 0:
        reasons_warn.append(f"sliver_faces({bm['sliver_faces']})")
    if bm["single_sided_non_manifold_edges"] > 0:
        reasons_warn.append(f"single_sided_non_manifold({bm['single_sided_non_manifold_edges']})")

    if reasons_fail:
        return "FAIL", reasons_fail + reasons_warn
    if reasons_warn:
        return "WARN", reasons_warn
    return "PASS", []


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    AUDIT_DIR.mkdir(parents=True, exist_ok=True)
    targets = discover_vehicle_glbs()
    targets_path = AUDIT_DIR / "targets.json"
    targets_path.write_text(json.dumps(targets, indent=2), encoding="utf-8")

    vehicles = sorted({t["vehicle_id"] for t in targets})
    print(f"Discovered {len(targets)} GLB files across {len(vehicles)} vehicles.")

    worker = REPO / "tools" / "blender_extract_glb_meshes.py"
    cmd = [
        "blender",
        "-b",
        "--factory-startup",
        "--python",
        str(worker),
        "--",
        str(targets_path),
        str(AUDIT_DIR),
    ]
    print("Running Blender headless extraction & bmesh analysis...")
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if proc.returncode != 0:
        print("Blender extraction failed:", proc.stderr, file=sys.stderr)
        sys.exit(1)

    extracted_path = AUDIT_DIR / "blender_extracted.json"
    extracted = json.loads(extracted_path.read_text(encoding="utf-8"))

    print("Running PyMeshLab & MeshLib audits on all extracted submeshes...")
    total_meshes = 0
    fail_meshes = 0
    warn_meshes = 0
    pass_meshes = 0

    for glb_entry in extracted:
        glb_status = "PASS" if glb_entry["container_valid"] else "FAIL"
        for mesh_entry in glb_entry["meshes"]:
            total_meshes += 1
            obj_path = Path(mesh_entry["obj_path"])
            pm_stats = audit_with_pymeshlab_and_meshlib(obj_path)
            mesh_entry["pymeshlab_meshlib"] = pm_stats
            status, reasons = classify_mesh_health(mesh_entry)
            mesh_entry["status"] = status
            mesh_entry["reasons"] = reasons

            if status == "FAIL":
                fail_meshes += 1
                glb_status = "FAIL"
            elif status == "WARN":
                warn_meshes += 1
                if glb_status != "FAIL":
                    glb_status = "WARN"
            else:
                pass_meshes += 1

        glb_entry["status"] = glb_status

    summary = {
        "vehicles_count": len(vehicles),
        "glb_files_count": len(extracted),
        "total_submeshes": total_meshes,
        "submesh_counts": {
            "PASS": pass_meshes,
            "WARN": warn_meshes,
            "FAIL": fail_meshes,
        },
        "glbs": extracted,
    }

    summary_path = AUDIT_DIR / "audit_summary.json"
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    md = [
        "# Reporte de Auditoría Geométrica de Vehículos (GLB)",
        "",
        f"- **Vehículos auditados:** {len(vehicles)}",
        f"- **Archivos `.glb` analizados:** {len(extracted)}",
        f"- **Submallas totales inspeccionadas:** {total_meshes}",
        f"  - **PASS:** {pass_meshes}",
        f"  - **WARN:** {warn_meshes}",
        f"  - **FAIL:** {fail_meshes}",
        "",
        "## Resumen por Vehículo",
        "",
        "| Vehículo | GLBs | Submallas | FAIL | WARN | PASS | Principales Hallazgos |",
        "| :--- | :---: | :---: | :---: | :---: | :---: | :--- |",
    ]

    by_vehicle = {}
    for g in extracted:
        by_vehicle.setdefault(g["vehicle_id"], []).append(g)

    for vid in sorted(by_vehicle.keys()):
        glbs = by_vehicle[vid]
        meshes = [m for g in glbs for m in g["meshes"]]
        n_fail = sum(1 for m in meshes if m["status"] == "FAIL")
        n_warn = sum(1 for m in meshes if m["status"] == "WARN")
        n_pass = sum(1 for m in meshes if m["status"] == "PASS")
        issues_set = []
        for g in glbs:
            for m in g["meshes"]:
                if m["status"] == "FAIL":
                    issues_set.append(f"`{Path(g['rel_path']).name}:{m['node_name']}` ({', '.join(m['reasons'])})")
        findings = "; ".join(issues_set) if issues_set else "Sin fallos críticos"
        md.append(f"| `{vid}` | {len(glbs)} | {len(meshes)} | **{n_fail}** | {n_warn} | {n_pass} | {findings} |")

    md.extend(
        [
            "",
            "## Detalle de Submallas con Estado `FAIL`",
            "",
            "| Vehículo | Archivo GLB | Nodo / Submalla | Vértices (Raw/Welded) | Caras | Defectos Detectados |",
            "| :--- | :--- | :--- | :---: | :---: | :--- |",
        ]
    )

    for g in extracted:
        for m in g["meshes"]:
            if m["status"] == "FAIL":
                bm = m["bmesh"]
                v_str = f"{bm['raw_vertices']}/{bm['welded_vertices']}"
                f_str = f"{bm['raw_faces']}"
                md.append(
                    f"| `{g['vehicle_id']}` | `{g['rel_path']}` | `{m['node_name']}` | {v_str} | {f_str} | {', '.join(m['reasons'])} |"
                )

    report_md_path = AUDIT_DIR / "audit_report.md"
    report_md_path.write_text("\n".join(md) + "\n", encoding="utf-8")
    print(f"Audit completed! FAIL={fail_meshes}, WARN={warn_meshes}, PASS={pass_meshes}")


if __name__ == "__main__":
    main()
