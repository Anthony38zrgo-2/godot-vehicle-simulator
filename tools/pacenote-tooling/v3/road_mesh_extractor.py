"""Extracción de la malla vial real desde el .BMF y conversión a espacio Godot.

Capa 1 (Geometría) del pipeline rally_road_reconstruction_v2.
Convierte DirectX (mano izquierda, +Z avance) a Godot (mano derecha,
-Y arriba... +Y arriba, -Z avance): (x, y, z) -> (x, y, -z),
invirtiendo el *winding order* para conservar normales hacia +Y.
"""
import fnmatch
from pathlib import Path
from typing import Any, Dict, List, Optional

import numpy as np

# Taxonomía exacta de materiales sobre MATERIALLIST (spec §3.1.B).
CORE_ROAD_MATERIALS = [
    "road_gravel_1", "road_forest", "road_field_1",
    "road_asphalt_*", "road_tarmac_*", "bridge_*",
]
JUNCTION_ROAD_MATERIALS = [
    "road_crossroad_2", "road_field_1_cross", "road_crossroad_*",
]
SHOULDER_MATERIALS = [
    "road_gravel_1_dif1", "road_gravel_1_dif2", "road_*_dif*",
]
BARRIER_WALL_MATERIALS = [
    "roadbar1", "string_red", "fence_metal",
    "fence_1_1", "fence_1_2", "fence_rock_1",
]

ROAD_CATEGORIES = {"core", "junction", "shoulder"}


def classify_material(mat_name: str) -> str:
    """Clasifica un material del BMF en core/junction/shoulder/barrier/ditch/other."""
    m = mat_name.strip()
    for pat in BARRIER_WALL_MATERIALS:
        if fnmatch.fnmatchcase(m, pat):
            return "barrier"
    for pat in JUNCTION_ROAD_MATERIALS:
        if fnmatch.fnmatchcase(m, pat):
            return "junction"
    for pat in CORE_ROAD_MATERIALS:
        if fnmatch.fnmatchcase(m, pat):
            return "core"
    for pat in SHOULDER_MATERIALS:
        if fnmatch.fnmatchcase(m, pat):
            return "shoulder"
    low = m.lower()
    if low.startswith("ditch_"):
        return "ditch"
    return "other"


def _flip_winding(faces: np.ndarray) -> np.ndarray:
    """(i0, i1, i2) -> (i0, i2, i1): restaura normales +Y tras negar Z."""
    out = faces.copy()
    out[:, [1, 2]] = out[:, [2, 1]]
    return out


def extract_road_mesh(stage) -> Dict[str, Any]:
    """Extrae triángulos viales, barreras y zanjas en coordenadas Godot.

    Retorna dict con arrays numpy:
      road_triangles (N,3,3), road_materials (N,), road_categories (N,),
      road_uvs (N,3,2), barrier_segments (M,2,2) en XZ, ditch_triangles (K,3,3).
    """
    road_verts: List[np.ndarray] = []
    road_mats: List[str] = []
    road_cats: List[str] = []
    road_uvs: List[np.ndarray] = []
    barrier_segs: List[np.ndarray] = []
    ditch_verts: List[np.ndarray] = []

    def _push_batch(verts, faces, uvs, mat_name: str, world_of, det_sign: float):
        cat = classify_material(mat_name)
        if cat not in ROAD_CATEGORIES and cat not in ("barrier", "ditch"):
            return
        gw = np.asarray(world_of(np.asarray(verts, dtype=np.float64)), dtype=np.float64)
        godot = np.column_stack([gw[:, 0], gw[:, 1], -gw[:, 2]])
        f = np.asarray(faces, dtype=np.int64)
        if det_sign > 0.0:
            f = _flip_winding(f)
        tri = godot[f]  # (F,3,3)
        if cat in ROAD_CATEGORIES:
            road_verts.append(tri)
            road_mats.extend([mat_name] * len(tri))
            road_cats.extend([cat] * len(tri))
            if uvs is not None and len(uvs) == len(verts):
                uv_arr = np.asarray(uvs, dtype=np.float64)[f]
                road_uvs.append(uv_arr)
            else:
                road_uvs.append(np.zeros((len(tri), 3, 2)))
        elif cat == "barrier":
            for t in tri:
                p = t[:, [0, 2]]
                barrier_segs.append(np.array([p[0], p[1]]))
                barrier_segs.append(np.array([p[1], p[2]]))
                barrier_segs.append(np.array([p[2], p[0]]))
        elif cat == "ditch":
            ditch_verts.append(tri)

    # TRACK: vértices ya en mundo DirectX.
    for chunk in stage.track_chunks:
        for b in chunk["batches"]:
            mat_id = b["mat_id"]
            mat_name = stage.materials[mat_id]["name"] if mat_id < len(stage.materials) else "default"
            _push_batch(b["verts"], b["faces"], b.get("uvs"), mat_name, lambda v: v, det_sign=1.0)

    # HIERARCHY: aplicar matriz 4x4 del nodo en espacio BMF.
    for mesh in stage.hierarchy_meshes:
        mat4 = np.asarray(mesh["matrix"], dtype=np.float64).reshape(4, 4)
        rot = mat4[:3, :3]
        det_sign = float(np.linalg.det(rot))
        px, py, pz = mesh["pos_extra"]
        for model in mesh["models"]:
            for b in model["batches"]:
                mat_id = b["mat_id"]
                mat_name = stage.materials[mat_id]["name"] if mat_id < len(stage.materials) else "default"

                # Convención row-vector del BMF (ver timing_gates.py):
                # wx = vx*m0 + vy*m4 + vz*m8 + px  =>  world = v @ R + p.
                def _world(v, _rot=rot):
                    return v @ _rot + np.array([px, py, pz])

                _push_batch(b["verts"], b["faces"], b.get("uvs"), mat_name, _world, det_sign)

    road_tri = np.concatenate(road_verts, axis=0) if road_verts else np.zeros((0, 3, 3))
    road_uv = np.concatenate(road_uvs, axis=0) if road_uvs else np.zeros((0, 3, 2))
    return {
        "road_triangles": road_tri,
        "road_materials": np.asarray(road_mats),
        "road_categories": np.asarray(road_cats),
        "road_uvs": road_uv,
        "barrier_segments": np.asarray(barrier_segs, dtype=np.float64).reshape(-1, 2, 2) if barrier_segs else np.zeros((0, 2, 2)),
        "ditch_triangles": np.concatenate(ditch_verts, axis=0) if ditch_verts else np.zeros((0, 3, 3)),
    }
