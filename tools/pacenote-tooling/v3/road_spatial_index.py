"""Índice espacial 2D/3D sobre la malla vial (cKDTree + tests vectorizados)."""
from typing import List, Optional, Tuple

import numpy as np
from scipy.spatial import cKDTree


def _point_in_tri_2d(px: np.ndarray, pz: np.ndarray, tri: np.ndarray) -> np.ndarray:
    """Test vectorizado punto-en-triángulo en XZ (batches de puntos x triángulos).

    px, pz: (P,); tri: (T,3,2). Retorna máscara (P,T) bool.
    """
    ax, az = tri[:, 0, 0], tri[:, 0, 1]
    bx, bz = tri[:, 1, 0], tri[:, 1, 1]
    cx, cz = tri[:, 2, 0], tri[:, 2, 1]
    d = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
    d = np.where(np.abs(d) < 1e-12, 1e-12, d)
    pxe = px[:, None]
    pze = pz[:, None]
    l1 = ((bz - cz) * (pxe - cx) + (cx - bx) * (pze - cz)) / d
    l2 = ((cz - az) * (pxe - cx) + (ax - cx) * (pze - cz)) / d
    l3 = 1.0 - l1 - l2
    eps = -1e-9
    return (l1 >= eps) & (l2 >= eps) & (l3 >= eps)


class RoadSpatialIndex:
    """Índice sobre triángulos viales en coordenadas Godot."""

    def __init__(self, triangles: np.ndarray):
        self.triangles = np.asarray(triangles, dtype=np.float64).reshape(-1, 3, 3)
        if len(self.triangles):
            self.centroids = self.triangles.mean(axis=1)
            self.tree = cKDTree(self.centroids)
            self.max_radius = float(np.abs(self.triangles - self.centroids[:, None, :]).max())
        else:
            self.centroids = np.zeros((0, 3))
            self.tree = None
            self.max_radius = 0.0

    def __len__(self) -> int:
        return len(self.triangles)

    def triangles_near(self, point: np.ndarray, radius: float) -> np.ndarray:
        """Índices de triángulos con centroide dentro del radio."""
        if self.tree is None:
            return np.zeros((0,), dtype=np.int64)
        return np.asarray(self.tree.query_ball_point(np.asarray(point[:3]), radius + self.max_radius))

    def containing_triangle(self, x: float, y: float, z: float, radius: float = 8.0) -> int:
        """Primer triángulo que contiene (x,z) con |Δy| <= 6 m. -1 si ninguno."""
        cand = self.triangles_near(np.array([x, y, z]), radius)
        if len(cand) == 0:
            return -1
        tris = self.triangles[cand][:, :, [0, 2]]
        inside = _point_in_tri_2d(np.array([x]), np.array([z]), tris)[0]
        for k, idx in enumerate(cand):
            if inside[k]:
                ty = self.triangles[idx][:, 1]
                if abs(float(ty.mean()) - y) <= 6.0:
                    return int(idx)
        return -1

    def cover_mask(self, xs: np.ndarray, zs: np.ndarray, y: float, radius: float = 8.0) -> np.ndarray:
        """Para cada muestra (x,z), True si cae sobre malla vial (|Δy|<=6)."""
        xs = np.asarray(xs, dtype=np.float64)
        out = np.zeros(len(xs), dtype=bool)
        # Candidatos globales: union de query_ball_point de todas las muestras.
        pts = np.column_stack([xs, np.full_like(xs, y), zs])
        if self.tree is None:
            return out
        ball = self.tree.query_ball_point(pts, radius + self.max_radius)
        # Con entrada matricial scipy devuelve object-array; normalizar a lista.
        if isinstance(ball, np.ndarray):
            ball = list(ball)
        all_idx = [np.asarray(b, dtype=np.int64) for b in ball if len(b) > 0]
        uniq = np.unique(np.concatenate(all_idx)) if all_idx else np.zeros((0,), dtype=np.int64)
        if len(uniq) == 0:
            return out
        tris2d = self.triangles[uniq][:, :, [0, 2]]
        inside = _point_in_tri_2d(xs, zs, tris2d)
        hit = inside.any(axis=1)
        # Comprobar cota Y solo donde hay cobertura XZ.
        for j in np.flatnonzero(hit):
            for k in np.flatnonzero(inside[j]):
                ty = float(self.triangles[uniq[k]][:, 1].mean())
                if abs(ty - y) <= 6.0:
                    out[j] = True
                    break
        return out
