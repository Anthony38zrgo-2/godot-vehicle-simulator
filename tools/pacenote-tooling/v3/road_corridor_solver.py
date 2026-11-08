"""Resolución de cruces y recorte del corredor con barreras físicas."""
from typing import Any, Dict, List

import numpy as np

import sys
from pathlib import Path as _Path
try:
    from road_mesh_extractor import classify_material
except ImportError:
    sys.path.insert(0, str(_Path(__file__).resolve().parent))
    from road_mesh_extractor import classify_material

DW_DS_LIMIT = 0.35
JUNCTION_WIDTH_FACTOR = 1.45


def _nearest_barrier_hit(origin: np.ndarray, direction: np.ndarray, max_dist: float,
                         segs: np.ndarray) -> float:
    """Distancia al primer cruce con una barrera (XZ). inf si no hay cruce."""
    if len(segs) == 0 or max_dist <= 0:
        return float("inf")
    q = segs[:, 0, :]
    s = segs[:, 1, :] - segs[:, 0, :]
    seg_len = np.linalg.norm(s, axis=1)
    valid_seg = seg_len > 1e-6
    r = direction * max_dist
    denom = r[0] * s[:, 1] - r[1] * s[:, 0]
    ok = valid_seg & (np.abs(denom) > 1e-12)
    qp = q - origin[None, :]
    t = np.full(len(segs), np.inf)
    u = np.full(len(segs), np.inf)
    t[ok] = (qp[ok, 0] * s[ok, 1] - qp[ok, 1] * s[ok, 0]) / denom[ok]
    u[ok] = (qp[ok, 0] * r[1] - qp[ok, 1] * r[0]) / denom[ok]
    hit = ok & (t >= 0.0) & (t <= 1.0) & (u >= 0.0) & (u <= 1.0)
    if not np.any(hit):
        return float("inf")
    return float((t[hit] * max_dist).min())


class CorridorSolver:
    """Recorta bordes contra barreras y resuelve ramas en cruces."""

    def __init__(self, barrier_segments: np.ndarray):
        segs = np.asarray(barrier_segments, dtype=np.float64).reshape(-1, 2, 2)
        # Descarta aristas verticales (degeneradas en XZ).
        if len(segs):
            lens = np.linalg.norm(segs[:, 1, :] - segs[:, 0, :], axis=1)
            segs = segs[lens > 1e-4]
        self.barriers = segs
        if len(segs):
            self._mins = segs.min(axis=1)
            self._maxs = segs.max(axis=1)
        else:
            self._mins = np.zeros((0, 2))
            self._maxs = np.zeros((0, 2))

    def _nearby_barriers(self, guide: np.ndarray, radius: float = 25.0) -> np.ndarray:
        if len(self.barriers) == 0:
            return self.barriers
        lo = guide - radius
        hi = guide + radius
        mask = (self._maxs[:, 0] >= lo[0]) & (self._mins[:, 0] <= hi[0]) & \
               (self._maxs[:, 1] >= lo[1]) & (self._mins[:, 1] <= hi[1])
        return self.barriers[mask]

    def solve(self, sections_doc: Dict[str, Any]) -> Dict[str, Any]:
        """Aplica barrier clipping + resolución de junctions. Retorna secciones."""
        sections: List[Dict[str, Any]] = sections_doc["sections"]
        widths = np.array([s["width_m"] if s.get("has_corridor") else np.nan for s in sections])
        valid = ~np.isnan(widths)
        w_nom = float(np.median(widths[valid])) if np.any(valid) else 12.0

        out: List[Dict[str, Any]] = []
        for s in sections:
            r = dict(s)
            r["solved_left_edge"] = list(s["left_edge"])
            r["solved_right_edge"] = list(s["right_edge"])
            r["solved_width_m"] = float(s["width_m"])
            r["is_junction"] = False
            r["anomaly_flags"] = []
            if not s.get("has_corridor"):
                out.append(r)
                continue
            g = np.array(s["guide"], dtype=np.float64)
            tan = np.array(s["tangent"], dtype=np.float64)
            n = np.array([-tan[1], tan[0]])
            nl = np.linalg.norm(n)
            n = n / nl if nl > 1e-9 else np.array([1.0, 0.0])
            near = self._nearby_barriers(np.array([g[0], g[2]]))
            # Rayo lateral izquierdo (hacia left_edge) y derecho.
            for side, key in ((-1.0, "solved_left_edge"), (1.0, "solved_right_edge")):
                edge = np.array(r[key], dtype=np.float64)
                vec = edge[[0, 2]] - g[[0, 2]]
                dist = float(np.linalg.norm(vec))
                if dist < 1e-6:
                    continue
                d = vec / dist
                hit = _nearest_barrier_hit(g[[0, 2]], d, dist, near)
                if hit < dist - 0.05:
                    edge[[0, 2]] = g[[0, 2]] + d * hit
                    r[key] = [float(edge[0]), float(edge[1]), float(edge[2])]
                    r["anomaly_flags"].append("barrier_clipped_" + ("left" if side < 0 else "right"))
            le = np.array(r["solved_left_edge"])
            ri = np.array(r["solved_right_edge"])
            r["solved_width_m"] = float(np.linalg.norm(ri[[0, 2]] - le[[0, 2]]))
            mats = [s.get("surface_center", ""), s.get("surface_left_edge", ""), s.get("surface_right_edge", "")]
            cats = {classify_material(m) for m in mats if m}
            if "junction" in cats or r["solved_width_m"] > JUNCTION_WIDTH_FACTOR * w_nom:
                r["is_junction"] = True
            out.append(r)

        # Penalizar cambios bruscos de ancho en junctions (dW/ds <= 0.35).
        w = np.array([s["solved_width_m"] for s in out])
        ds = sections_doc.get("step_m", 2.0)
        for _ in range(3):
            for i in range(1, len(w)):
                if not out[i]["is_junction"] and not out[i - 1]["is_junction"]:
                    continue
                dw = w[i] - w[i - 1]
                lim = DW_DS_LIMIT * ds
                if abs(dw) > lim:
                    w[i] = w[i - 1] + np.sign(dw) * lim
        for i, s in enumerate(out):
            if s["is_junction"] and abs(w[i] - s["solved_width_m"]) > 0.05:
                s["solved_width_m"] = float(w[i])
                if "junction_width_clamped" not in s["anomaly_flags"]:
                    s["anomaly_flags"].append("junction_width_clamped")
            if s["is_junction"] and s.get("has_corridor", True):
                # Fija el lado estable y reconstruye el que abulta con el
                # offset de entrada/salida (§3.3): bordes consistentes con el
                # eje guía fuera del cruce. El lado medido conserva la forma
                # real de la curva (la malla); la rama bloqueada se elimina
                # sin aplanar la esquina contra la guía dispersa (nodos/10 m).
                j0, j1 = i, i
                while j0 - 1 >= 0 and out[j0 - 1].get("is_junction"):
                    j0 -= 1
                while j1 + 1 < len(out) and out[j1 + 1].get("is_junction"):
                    j1 += 1
                ref_idx = [k for k in list(range(max(0, j0 - 20), j0)) + list(range(j1 + 1, min(len(out), j1 + 21)))
                           if out[k].get("has_corridor", True)]
                if ref_idx:
                    offs_l, offs_r = [], []
                    for k in ref_idx:
                        gk = np.array(out[k]["guide"], dtype=np.float64)
                        tk = np.array(out[k]["tangent"], dtype=np.float64)
                        nk = np.array([-tk[1], tk[0]])
                        nk = nk / (np.linalg.norm(nk) or 1.0)
                        lk = np.array(out[k]["solved_left_edge"], dtype=np.float64)
                        rk = np.array(out[k]["solved_right_edge"], dtype=np.float64)
                        offs_l.append(float(np.dot(lk[[0, 2]] - gk[[0, 2]], nk)))
                        offs_r.append(float(np.dot(rk[[0, 2]] - gk[[0, 2]], nk)))
                    ref_l, ref_r = float(np.median(offs_l)), float(np.median(offs_r))
                    g = np.array(s["guide"], dtype=np.float64)
                    t = np.array(s["tangent"], dtype=np.float64)
                    n = np.array([-t[1], t[0]])
                    n = n / (np.linalg.norm(n) or 1.0)
                    le = np.array(s["solved_left_edge"], dtype=np.float64)
                    ri = np.array(s["solved_right_edge"], dtype=np.float64)
                    o_l = float(np.dot(le[[0, 2]] - g[[0, 2]], n))
                    o_r = float(np.dot(ri[[0, 2]] - g[[0, 2]], n))
                    if abs(o_l - ref_l) > abs(o_r - ref_r):
                        le[[0, 2]] = g[[0, 2]] + n * ref_l
                        s["solved_left_edge"] = [float(le[0]), float(le[1]), float(le[2])]
                        s["anomaly_flags"].append("junction_left_pinned")
                    else:
                        ri[[0, 2]] = g[[0, 2]] + n * ref_r
                        s["solved_right_edge"] = [float(ri[0]), float(ri[1]), float(ri[2])]
                        s["anomaly_flags"].append("junction_right_pinned")
                    le2 = np.array(s["solved_left_edge"])
                    ri2 = np.array(s["solved_right_edge"])
                    s["solved_width_m"] = float(np.linalg.norm(ri2[[0, 2]] - le2[[0, 2]]))

        # Estabilización de bordes (cortes "estabilizados" §3.2): un truncado
        # binario contra barreras crea escalones de 2 m que el filtro de C no
        # absorbe (ventana 11 m, orden 3). Suaviza XZ de L/R con la misma
        # familia Savitzky-Golay (ventana 14 m < escala de curva ~30 m).
        try:
            from scipy.signal import savgol_filter as _sg
            for key in ("solved_left_edge", "solved_right_edge"):
                arr = np.array([s[key] for s in out if s.get("has_corridor", True)], dtype=np.float64)
                if len(arr) >= 7:
                    for k in (0, 2):
                        arr[:, k] = _sg(arr[:, k], window_length=7, polyorder=3, mode="interp")
                    j = 0
                    for s in out:
                        if s.get("has_corridor", True):
                            s[key] = [float(arr[j, 0]), float(s[key][1]), float(arr[j, 2])]
                            j += 1
            for s in out:
                if s.get("has_corridor", True):
                    le = np.array(s["solved_left_edge"])
                    ri = np.array(s["solved_right_edge"])
                    s["solved_width_m"] = float(np.linalg.norm(ri[[0, 2]] - le[[0, 2]]))
        except Exception:
            pass

        return {"step_m": sections_doc.get("step_m", 2.0),
                "nominal_width_m": w_nom, "sections": out,
                "total_length_m": sections_doc.get("total_length_m", 0.0)}
