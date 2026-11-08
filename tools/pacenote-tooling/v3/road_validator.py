"""Validación de la reconstrucción: anomalías, JSON y GLB de depuración."""
import json
from pathlib import Path
from typing import Any, Dict, List

import numpy as np

try:
    import trimesh
    _HAS_TRIMESH = True
except Exception:
    _HAS_TRIMESH = False


def _nearest_route_node(station_s: np.ndarray, route_points: np.ndarray) -> np.ndarray:
    seg = np.linalg.norm(np.diff(route_points, axis=0), axis=1)
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    return np.argmin(np.abs(cum[None, :] - station_s[:, None]), axis=1)


def detect_anomalies(solved_sections: List[Dict[str, Any]], step_m: float = 2.0) -> Dict[str, int]:
    """Cuenta clamps de junction, huecos de malla y saltos bruscos de ancho."""
    junction_clamps = sum(1 for s in solved_sections if "junction_width_clamped" in s.get("anomaly_flags", []))
    mesh_gaps = sum(1 for s in solved_sections if not s.get("has_corridor", True))
    w = np.array([s.get("solved_width_m", 0.0) for s in solved_sections])
    dw = np.abs(np.diff(w)) / max(step_m, 1e-9)
    sharp = int(np.sum(dw[1:] > 0.35)) if len(dw) > 1 else 0
    return {"junction_clamps": int(junction_clamps), "mesh_gaps": int(mesh_gaps),
            "sharp_width_jumps": sharp}


def build_road_geometry(stage_id: str, solved: Dict[str, Any],
                        centerline: Dict[str, Any], analysis: Dict[str, np.ndarray],
                        route_points: np.ndarray) -> Dict[str, Any]:
    """Ensambla el documento russia road_geometry.json (§4.1)."""
    secs = solved["sections"]
    n = len(secs)
    step = float(solved.get("step_m", 2.0))
    station_s = np.arange(n) * step
    guide_nodes = _nearest_route_node(station_s, np.asarray(route_points, dtype=np.float64))
    center = np.asarray(centerline["center"], dtype=np.float64)
    opt = np.asarray(centerline["opt_line"], dtype=np.float64)
    out_sections: List[Dict[str, Any]] = []
    for i, s in enumerate(secs):
        flags = list(s.get("anomaly_flags", []))
        if s.get("is_junction"):
            has_corr = bool(s.get("has_corridor", True))
            conf = "low" if not has_corr else ("medium" if flags else "high")
        else:
            conf = "high" if (s.get("has_corridor", True) and not flags) else ("low" if not s.get("has_corridor", True) else "medium")
        out_sections.append({
            "s_m": round(float(station_s[i]), 2),
            "guide_node": int(guide_nodes[i]),
            "center": [round(float(v), 3) for v in center[i]],
            "left_edge": [round(float(v), 3) for v in s["solved_left_edge"]],
            "right_edge": [round(float(v), 3) for v in s["solved_right_edge"]],
            "opt_line": [round(float(v), 3) for v in opt[i]],
            "width_m": round(float(s.get("solved_width_m", 0.0)), 3),
            "heading_rad": round(float(analysis["heading_rad"][i]), 5),
            "kappa_center": round(float(analysis["kappa_center"][i]), 6),
            "kappa_opt": round(float(analysis["kappa_opt"][i]), 6),
            "kappa_vertical": round(float(analysis["kappa_vertical"][i]), 6),
            "grade_pct": round(float(analysis["grade_pct"][i]), 3),
            "camber_deg": round(float(analysis["camber_deg"][i]), 3),
            "surface_material": s.get("surface_center", ""),
            "grip_mu": round(float(analysis["grip_mu"][i]), 3),
            "is_junction": bool(s.get("is_junction", False)),
            "confidence": conf,
            "anomaly_flags": flags,
        })
    widths = np.array([s.get("solved_width_m", 0.0) for s in secs if s.get("has_corridor")])
    return {
        "stage": stage_id,
        "sample_step_m": step,
        "total_length_m": round(float(solved.get("total_length_m", station_s[-1] if n else 0.0)), 2),
        "median_width_m": round(float(np.median(widths)) if len(widths) else 0.0, 3),
        "anomalies_summary": detect_anomalies(secs, step),
        "sections": out_sections,
    }


def write_json(doc: Dict[str, Any], path) -> None:
    Path(path).write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _ribbon(points: np.ndarray, width: float, lift: float, color) -> "trimesh.Trimesh":
    """Cinta triangular siguiendo una polilínea 3D (depuración visual)."""
    pts = np.asarray(points, dtype=np.float64)
    n = len(pts)
    tang = np.diff(pts, axis=0)
    tang = np.vstack([tang, tang[-1:]])
    tang[:, 1] = 0.0
    norm = np.linalg.norm(tang, axis=1, keepdims=True)
    norm = np.where(norm < 1e-9, 1.0, norm)
    tang = tang / norm
    side = np.column_stack([-tang[:, 2], np.zeros(n), tang[:, 0]]) * (width * 0.5)
    verts = np.zeros((2 * n, 3))
    verts[0::2] = pts + side + np.array([0.0, lift, 0.0])
    verts[1::2] = pts - side + np.array([0.0, lift, 0.0])
    faces = []
    for i in range(n - 1):
        a, b, c, d = 2 * i, 2 * i + 1, 2 * i + 2, 2 * i + 3
        faces.append([a, b, c])
        faces.append([b, d, c])
    mesh = trimesh.Trimesh(vertices=verts, faces=np.array(faces), process=True)
    mesh.visual = trimesh.visual.ColorVisuals(mesh, face_colors=np.tile(color, (len(faces), 1)))
    return mesh


def write_debug_glb(doc: Dict[str, Any], path) -> None:
    """Exporta polilíneas L/R/C/P* como cintas de color (rojo/verde/azul/amarillo)."""
    if not _HAS_TRIMESH:
        raise RuntimeError("trimesh no disponible para el GLB de depuración")
    secs = doc["sections"]
    get = lambda k: np.array([s[k] for s in secs], dtype=np.float64)
    scene = trimesh.Scene()
    scene.add_geometry(_ribbon(get("left_edge"), 0.4, 0.6, [255, 40, 40, 255]), geom_name="L_border")
    scene.add_geometry(_ribbon(get("right_edge"), 0.4, 0.6, [40, 200, 80, 255]), geom_name="R_border")
    scene.add_geometry(_ribbon(get("center"), 0.4, 0.7, [60, 120, 255, 255]), geom_name="C_center")
    scene.add_geometry(_ribbon(get("opt_line"), 0.4, 0.8, [255, 200, 40, 255]), geom_name="P_optimal")
    data = scene.export(file_type="glb")
    Path(path).write_bytes(bytes(data))
