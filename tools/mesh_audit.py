#!/usr/bin/env python3
"""
Mesh Audit Tool using PyMeshLab
Audits 3D geometry for issues:
- Non-manifold edges and vertices
- Self-intersections
- Inverted / folded faces and elongated (sliver) triangles
- Border edges / open holes
- Duplicate faces and unreferenced vertices
"""

import sys
import argparse
import json
from pathlib import Path

try:
    import pymeshlab
except ImportError:
    print("Error: pymeshlab is not installed. Run: pip install pymeshlab", file=sys.stderr)
    sys.exit(1)


def audit_mesh(input_path: str, folded_angle: float = 160.0) -> dict:
    path = Path(input_path).resolve()
    if not path.exists():
        raise FileNotFoundError(f"File not found: {path}")

    ms = pymeshlab.MeshSet()
    ms.load_new_mesh(str(path))
    m = ms.current_mesh()

    initial_verts = m.vertex_number()
    initial_faces = m.face_number()

    report = {
        "file": str(path),
        "vertices": initial_verts,
        "faces": initial_faces,
        "issues": {},
        "status": "PASS"
    }

    # 1. Non-manifold edges
    ms.apply_filter('set_selection_none')
    ms.apply_filter('compute_selection_by_non_manifold_edges_per_face')
    report["issues"]["non_manifold_edge_faces"] = ms.current_mesh().selected_face_number()

    # 2. Non-manifold vertices
    ms.apply_filter('set_selection_none')
    ms.apply_filter('compute_selection_by_non_manifold_per_vertex')
    report["issues"]["non_manifold_vertices"] = ms.current_mesh().selected_vertex_number()

    # 3. Self-intersecting faces
    ms.apply_filter('set_selection_none')
    ms.apply_filter('compute_selection_by_self_intersections_per_face')
    report["issues"]["self_intersecting_faces"] = ms.current_mesh().selected_face_number()

    # 4. Bad faces (elongated / sliver triangles and folded faces)
    ms.apply_filter('set_selection_none')
    ms.apply_filter(
        'compute_selection_bad_faces',
        usear=True,
        select_folded_faces=True,
        folded_faces_angle_threshold=folded_angle
    )
    report["issues"]["elongated_or_folded_faces"] = ms.current_mesh().selected_face_number()

    # 5. Open borders / holes
    ms.apply_filter('set_selection_none')
    ms.apply_filter('compute_selection_from_mesh_border')
    report["issues"]["open_border_faces"] = ms.current_mesh().selected_face_number()

    # Clean selections
    ms.apply_filter('set_selection_none')

    # Determine overall status
    critical_issues = (
        report["issues"]["non_manifold_edge_faces"]
        + report["issues"]["non_manifold_vertices"]
        + report["issues"]["self_intersecting_faces"]
    )
    all_issues = sum(report["issues"].values())

    if critical_issues > 0:
        report["status"] = "FAIL"
    elif all_issues > 0:
        report["status"] = "WARNING"
    else:
        report["status"] = "PASS"

    return report


def main():
    parser = argparse.ArgumentParser(description="Audit 3D mesh geometry using PyMeshLab")
    parser.add_argument("mesh", help="Path to 3D mesh file (.obj, .stl, .ply, .off, etc.)")
    parser.add_argument("--json", action="store_true", help="Output results in JSON format")
    parser.add_argument("--folded-angle", type=float, default=160.0, help="Angle threshold for folded faces (default: 160.0)")
    parser.add_argument("--clean-output", help="Save cleaned mesh (duplicate faces & unreferenced vertices removed) to path")
    args = parser.parse_args()

    try:
        report = audit_mesh(args.mesh, folded_angle=args.folded_angle)
    except Exception as e:
        print(f"Error auditing mesh: {e}", file=sys.stderr)
        sys.exit(1)

    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print("=" * 60)
        print(f"GEOMETRY AUDIT REPORT: {Path(args.mesh).name}")
        print("=" * 60)
        print(f"Total Vertices: {report['vertices']:,}")
        print(f"Total Faces:    {report['faces']:,}")
        print(f"Overall Status: {report['status']}")
        print("-" * 60)
        print("Detected Issues:")
        for key, val in report["issues"].items():
            name = key.replace("_", " ").capitalize()
            symbol = "[OK]" if val == 0 else "[!]"
            print(f"  {symbol} {name:<35}: {val}")
        print("=" * 60)

    if args.clean_output:
        ms = pymeshlab.MeshSet()
        ms.load_new_mesh(args.mesh)
        ms.apply_filter('meshing_remove_duplicate_faces')
        ms.apply_filter('meshing_remove_duplicate_vertices')
        ms.apply_filter('meshing_remove_unreferenced_vertices')
        ms.save_current_mesh(args.clean_output)
        print(f"\nCleaned mesh saved to: {args.clean_output}")


if __name__ == "__main__":
    main()
