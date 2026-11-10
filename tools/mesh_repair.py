#!/usr/bin/env python3
"""
Mesh Repair Tool using MeshLib (mrmeshpy)
Repairs 3D geometry:
- Hole filling (finding and closing non-manifold hole boundaries)
- Self-intersection resolution (local geometry-preserving or voxel-based reconstruction)
- Mesh decimation and simplification
"""

import sys
import argparse
from pathlib import Path

try:
    import meshlib.mrmeshpy as mr
except ImportError:
    print("Error: meshlib is not installed. Run: pip install meshlib", file=sys.stderr)
    sys.exit(1)


def repair_mesh(
    input_path: str,
    output_path: str,
    fill_holes: bool = True,
    fix_intersections: bool = False,
    reconstruct_surface: bool = False,
    voxel_resolution: int = 150,
    decimate_error: float = None,
) -> dict:
    path = Path(input_path).resolve()
    if not path.exists():
        raise FileNotFoundError(f"File not found: {path}")

    # Load mesh
    mesh = mr.loadMesh(path)
    initial_verts = mesh.points.size()
    initial_faces = mesh.topology.getValidFaces().count()
    initial_holes = mesh.topology.findNumHoles()

    actions_taken = []

    # 1. Fill holes
    filled_holes_count = 0
    if fill_holes:
        hole_edges = mesh.topology.findHoleRepresentiveEdges()
        filled_holes_count = len(hole_edges)
        if filled_holes_count > 0:
            mr.fillHoles(mesh, hole_edges)
            actions_taken.append(f"Filled {filled_holes_count} holes")

    # 2. Fix self-intersections (preserving geometry locally)
    if fix_intersections and not reconstruct_surface:
        settings = mr.SelfIntersections.Settings()
        mr.localFixSelfIntersections(mesh, settings)
        actions_taken.append("Fixed self-intersections (local geometry-preserving)")

    # 3. Surface reconstruction / voxel fix (removes self-intersections & guarantees watertightness)
    if reconstruct_surface:
        bbox = mesh.computeBoundingBox()
        diag = bbox.diagonal()
        if diag <= 0:
            diag = 1.0
        voxel_size = diag / float(voxel_resolution)
        mr.fixSelfIntersections(mesh, voxel_size)
        actions_taken.append(f"Reconstructed watertight surface (voxel size: {voxel_size:.5f})")

    # 4. Decimate / simplify if requested
    if decimate_error is not None and decimate_error > 0.0:
        settings = mr.DecimateSettings()
        settings.maxError = float(decimate_error)
        mr.decimateMesh(mesh, settings)
        actions_taken.append(f"Decimated mesh (max error: {decimate_error})")

    # Save repaired mesh
    out = Path(output_path).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    mr.saveMesh(mesh, out)

    final_verts = mesh.points.size()
    final_faces = mesh.topology.getValidFaces().count()
    final_holes = mesh.topology.findNumHoles()

    return {
        "input": str(path),
        "output": str(out),
        "initial": {
            "vertices": initial_verts,
            "faces": initial_faces,
            "holes": initial_holes
        },
        "final": {
            "vertices": final_verts,
            "faces": final_faces,
            "holes": final_holes
        },
        "actions": actions_taken
    }


def main():
    parser = argparse.ArgumentParser(description="Repair 3D mesh geometry using MeshLib")
    parser.add_argument("input", help="Path to input 3D mesh (.obj, .stl, .ply, etc.)")
    parser.add_argument("-o", "--output", required=True, help="Path to output repaired mesh")
    parser.add_argument("--no-fill-holes", action="store_true", help="Skip automatic hole filling")
    parser.add_argument("--fix-intersections", action="store_true", help="Fix self-intersections preserving local geometry")
    parser.add_argument("--reconstruct-surface", action="store_true", help="Deep voxel reconstruction for watertight manifold mesh")
    parser.add_argument("--voxel-res", type=int, default=150, help="Voxel resolution along bounding box diagonal (default: 150)")
    parser.add_argument("--decimate-error", type=float, default=None, help="Simplify mesh with maximum geometric error tolerance")

    args = parser.parse_args()

    try:
        report = repair_mesh(
            input_path=args.input,
            output_path=args.output,
            fill_holes=not args.no_fill_holes,
            fix_intersections=args.fix_intersections,
            reconstruct_surface=args.reconstruct_surface,
            voxel_resolution=args.voxel_res,
            decimate_error=args.decimate_error,
        )
    except Exception as e:
        print(f"Error repairing mesh: {e}", file=sys.stderr)
        sys.exit(1)

    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

    print("=" * 60)
    print("MESHLIB REPAIR REPORT")
    print("=" * 60)
    print(f"Input:  {report['input']}")
    print(f"Output: {report['output']}")
    print("-" * 60)
    print(f"Vertices: {report['initial']['vertices']:,} -> {report['final']['vertices']:,}")
    print(f"Faces:    {report['initial']['faces']:,} -> {report['final']['faces']:,}")
    print(f"Holes:    {report['initial']['holes']} -> {report['final']['holes']}")
    print("-" * 60)
    print("Actions performed:")
    if report["actions"]:
        for action in report["actions"]:
            print(f"  [+] {action}")
    else:
        print("  (No geometry modifications were needed)")
    print("=" * 60)


if __name__ == "__main__":
    main()
