"""Cortes ortogonales estabilizados cada 2.0 m + bordes L(s)/R(s).

Usa una curva guía B-spline suavizada SOLO para tangentes/normales
(garantizando |k_frame| < 1/12 m^-1) y detecta bordes combinando
frontera de material, UV de la cinta vial y elevación Y baricéntrica.
"""
from typing import Any, Dict, List, Optional

import numpy as np
from scipy.interpolate import splprep, splev

from road_spatial_index import RoadSpatialIndex, _point_in_tri_2d

STEP_M = 2.0
HALF_RANGE_M = 20.0
SAMPLE_DX_M = 0.25
MAX_FRAME_KAPPA = 1.0 / 12.0


def resample_route(points: np.ndarray, step: float = STEP_M) -> np.ndarray:
    """Interpola la polilínea de ruta a estaciones uniformes cada `step` m."""
    pts = np.asarray(points, dtype=np.float64)
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    total = cum[-1]
    n = max(2, int(round(total / step)) + 1)
    s = np.linspace(0.0, total, n)
    out = np.stack([np.interp(s, cum, pts[:, 0]),
                    np.interp(s, cum, pts[:, 1]),
                    np.interp(s, cum, pts[:, 2])], axis=1)
    return out


def smoothed_frame_tangents(xz: np.ndarray) -> np.ndarray:
    """Tangentes unitarias de un B-spline suavizado con k_frame acotada."""
    x, z = xz[:, 0], xz[:, 1]
    n = len(x)
    k = 3 if n > 10 else 1
    # s inicial proporcional al ruido esperado; se duplica hasta acotar k.
    s = max(1.0, n * 0.02)
    tang = None
    for _ in range(25):
        try:
            tck, _ = splprep([x, z], s=s, k=k)
        except Exception:
            s *= 2.0
            continue
        u = np.linspace(0.0, 1.0, n)
        d1 = np.stack(splev(u, tck, der=1), axis=1)
        norm = np.linalg.norm(d1, axis=1, keepdims=True)
        norm = np.where(norm < 1e-9, 1.0, norm)
        tang = d1 / norm
        ang = np.unwrap(np.arctan2(tang[:, 0], tang[:, 1]))
        kappa = np.abs(np.diff(ang)) / STEP_M
        if len(kappa) == 0 or float(kappa.max(initial=0.0)) < MAX_FRAME_KAPPA:
            break
        s *= 1.6
    if tang is None:
        d = np.diff(xz, axis=0)
        d = np.vstack([d, d[-1:]])
        tang = d / np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9)
    return tang


def _barycentric_y(tri: np.ndarray, x: float, z: float) -> float:
    """Interpola Y baricéntricamente dentro de un triángulo Godot."""
    ax, ay, az = tri[0]
    bx, by, bz = tri[1]
    cx, cy, cz = tri[2]
    d = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
    if abs(d) < 1e-12:
        return float((ay + by + cy) / 3.0)
    l1 = ((bz - cz) * (x - cx) + (cx - bx) * (z - cz)) / d
    l2 = ((cz - az) * (x - cx) + (ax - cx) * (z - cz)) / d
    l3 = 1.0 - l1 - l2
    return float(l1 * ay + l2 * by + l3 * cy)


class CrossSections:
    """Constructor de secciones transversales sobre la malla vial."""

    def __init__(self, triangles: np.ndarray, materials: np.ndarray,
                 categories: np.ndarray, uvs: np.ndarray):
        self.triangles = np.asarray(triangles, dtype=np.float64)
        self.materials = np.asarray(materials)
        self.categories = np.asarray(categories)
        self.uvs = np.asarray(uvs, dtype=np.float64)
        self.index = RoadSpatialIndex(self.triangles)

    def build(self, route_points: np.ndarray) -> Dict[str, Any]:
        """Genera secciones cada 2 m. Retorna dict con estaciones y bordes."""
        stations = resample_route(np.asarray(route_points, dtype=np.float64))
        tang = smoothed_frame_tangents(stations[:, [0, 2]])
        normals = np.column_stack([-tang[:, 1], tang[:, 0]])  # N_perp = (-Tz, Tx)

        qs = np.arange(-HALF_RANGE_M, HALF_RANGE_M + 1e-9, SAMPLE_DX_M)
        center_idx = int(np.argmin(np.abs(qs)))

        sections: List[Dict[str, Any]] = []
        for si in range(len(stations)):
            g = stations[si]
            nx, nz = normals[si]
            xs = g[0] + nx * qs
            zs = g[2] + nz * qs
            cover = self.index.cover_mask(xs, zs, float(g[1]))
            # Intervalo contiguo que contiene la guía.
            lo = center_idx
            while lo - 1 >= 0 and cover[lo - 1]:
                lo -= 1
            hi = center_idx
            while hi + 1 < len(qs) and cover[hi + 1]:
                hi += 1
            if not cover[center_idx]:
                # Fuera de malla: estación sin corredor (se marca).
                sections.append(self._empty_section(si, g, tang[si]))
                continue
            ql, qr = qs[lo], qs[hi]
            pl = np.array([g[0] + nx * ql, 0.0, g[2] + nz * ql])
            pr = np.array([g[0] + nx * qr, 0.0, g[2] + nz * qr])
            pl[1] = self._ground_y(pl[0], float(g[1]), pl[2])
            pr[1] = self._ground_y(pr[0], float(g[1]), pr[2])
            mat_c, uv_c = self._surface_at(g[0], float(g[1]), g[2])
            mat_l, uv_l = self._surface_at(pl[0], pl[1], pl[2])
            mat_r, uv_r = self._surface_at(pr[0], pr[1], pr[2])
            sections.append({
                "station_index": si,
                "s_m": float(si * STEP_M),
                "guide": [float(g[0]), float(g[1]), float(g[2])],
                "tangent": [float(tang[si][0]), float(tang[si][1])],
                "left_edge": [float(pl[0]), float(pl[1]), float(pl[2])],
                "right_edge": [float(pr[0]), float(pr[1]), float(pr[2])],
                "width_m": float(qr - ql),
                "surface_center": mat_c,
                "surface_left_edge": mat_l,
                "surface_right_edge": mat_r,
                "uv_center": uv_c,
                "uv_left_edge": uv_l,
                "uv_right_edge": uv_r,
                "has_corridor": True,
            })
        return {"step_m": STEP_M, "sections": sections,
                "total_length_m": float((len(stations) - 1) * STEP_M)}

    def _empty_section(self, si: int, g: np.ndarray, t: np.ndarray) -> Dict[str, Any]:
        return {"station_index": si, "s_m": float(si * STEP_M),
                "guide": [float(g[0]), float(g[1]), float(g[2])],
                "tangent": [float(t[0]), float(t[1])],
                "left_edge": [float(g[0]), float(g[1]), float(g[2])],
                "right_edge": [float(g[0]), float(g[1]), float(g[2])],
                "width_m": 0.0, "surface_center": "", "surface_left_edge": "",
                "surface_right_edge": "", "uv_center": [0.0, 0.0],
                "uv_left_edge": [0.0, 0.0], "uv_right_edge": [0.0, 0.0],
                "has_corridor": False}

    def _surface_at(self, x: float, y: float, z: float):
        idx = self.index.containing_triangle(x, y, z)
        if idx < 0:
            return "", [0.0, 0.0]
        tri = self.triangles[idx]
        uv_tri = self.uvs[idx] if idx < len(self.uvs) else np.zeros((3, 2))
        # UV baricéntricas (gradiente para distinguir costura de borde real).
        ax, az = tri[0, 0], tri[0, 2]
        bx, bz = tri[1, 0], tri[1, 2]
        cx, cz = tri[2, 0], tri[2, 2]
        d = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
        if abs(d) < 1e-12:
            uv = uv_tri.mean(axis=0)
        else:
            l1 = ((bz - cz) * (x - cx) + (cx - bx) * (z - cz)) / d
            l2 = ((cz - az) * (x - cx) + (ax - cx) * (z - cz)) / d
            l3 = 1.0 - l1 - l2
            uv = l1 * uv_tri[0] + l2 * uv_tri[1] + l3 * uv_tri[2]
        return str(self.materials[idx]), [float(uv[0]), float(uv[1])]

    def _ground_y(self, x: float, y_ref: float, z: float) -> float:
        idx = self.index.containing_triangle(x, y_ref, z)
        if idx < 0:
            return float(y_ref)
        return _barycentric_y(self.triangles[idx], x, z)
