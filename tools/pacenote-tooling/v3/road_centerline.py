"""Eje geométrico C(s) y trazada de mínima curvatura acotada P*(s).

P*(s_i) = C(s_i) + alpha_i * (R(s_i) - L(s_i)) con alpha en [-0.35, +0.35]
(margen del 15% a cada borde). Se resuelve como mínimos cuadrados acotados:
  min ||T alpha + c||^2 + lambda * ||alpha||^2,  lambda = 1e-3,
donde T es el operador tridiagonal de segundas diferencias y c la
segunda diferencia del centro C. Obstáculos interiores contraen la cota
correspondiente a 0.0 en [s_i - 8 m, s_i + 8 m].
"""
from typing import Any, Dict, List, Optional

import numpy as np
from scipy.signal import savgol_filter
from scipy.optimize import lsq_linear
from scipy import sparse

ALPHA_MIN, ALPHA_MAX = -0.35, 0.35
LAMBDA = 1e-3
OBSTACLE_HALF_WINDOW_M = 8.0


def smooth_centerline(raw_mid: np.ndarray, widths: np.ndarray) -> np.ndarray:
    """Suaviza el eje con Savitzky-Golay (orden 3, ventana ~11 m).

    Restringe el resultado al tercio central: ||C - raw|| <= 0.15 * W.
    raw_mid: (N,3) puntos medios crudos; widths: (N,).
    """
    n = len(raw_mid)
    # Ventana de ~11 m con paso de 2 m -> 5 muestras (impar, > orden 3).
    win = 5 if n >= 5 else (n if n % 2 == 1 else max(3, n - 1))
    win = max(3, min(win, n if n % 2 == 1 else n - 1))
    if win < 4:
        return raw_mid.copy()
    c = np.stack([savgol_filter(raw_mid[:, k], window_length=win, polyorder=3, mode="interp")
                  for k in range(3)], axis=1)
    dev = np.linalg.norm(c - raw_mid, axis=1)
    limit = 0.15 * np.asarray(widths, dtype=np.float64)
    over = (limit > 1e-9) & (dev > limit)
    c[over] = raw_mid[over] + (c[over] - raw_mid[over]) * (limit[over] / dev[over])[:, None]
    return c


def solve_racing_line(center: np.ndarray, left: np.ndarray, right: np.ndarray,
                      obstacles: Optional[List[Dict[str, Any]]] = None,
                      step_m: float = 2.0) -> np.ndarray:
    """Resuelve los alpha óptimos acotados y retorna P* (N,3)."""
    n = len(center)
    d = right - left  # (N,3)
    # Segundas diferencias del centro: c_i = C_{i+1} - 2 C_i + C_{i-1}.
    c = center[2:] - 2.0 * center[1:-1] + center[:-2]  # (N-2,3)
    rows, cols, data = [], [], []
    for j in range(3):  # una fila por componente x/y/z
        for i in range(n - 2):
            base = j * (n - 2) + i
            rows += [base, base, base]
            cols += [i, i + 1, i + 2]
            data += [d[i, j], -2.0 * d[i + 1, j], d[i + 2, j]]
    t = sparse.csr_matrix((data, (rows, cols)), shape=(3 * (n - 2), n))
    reg = sparse.diags(np.full(n, np.sqrt(LAMBDA)))
    m = sparse.vstack([t, reg]).tocsc()
    y = np.concatenate([-c.reshape(-1), np.zeros(n)])
    lo = np.full(n, ALPHA_MIN)
    hi = np.full(n, ALPHA_MAX)
    if obstacles:
        s_grid = np.arange(n) * step_m
        for ob in obstacles:
            s0 = float(ob.get("s_m", 0.0))
            side = str(ob.get("side", ""))
            sel = np.abs(s_grid - s0) <= OBSTACLE_HALF_WINDOW_M
            if side == "left":
                lo[sel] = np.maximum(lo[sel], 0.0)
            elif side == "right":
                hi[sel] = np.minimum(hi[sel], 0.0)
    res = lsq_linear(m, y, bounds=(lo, hi), lsmr_tol="auto", verbose=0)
    alpha = res.x
    return center + alpha[:, None] * d


def build_centerline(solved_sections: List[Dict[str, Any]],
                     obstacles: Optional[List[Dict[str, Any]]] = None,
                     step_m: float = 2.0) -> Dict[str, Any]:
    """Calcula C(s) y P*(s) a partir de las secciones resueltas del corredor."""
    left = np.array([s["solved_left_edge"] for s in solved_sections], dtype=np.float64)
    right = np.array([s["solved_right_edge"] for s in solved_sections], dtype=np.float64)
    widths = np.array([s["solved_width_m"] for s in solved_sections], dtype=np.float64)
    raw_mid = 0.5 * (left + right)
    center = smooth_centerline(raw_mid, widths)
    opt = solve_racing_line(center, left, right, obstacles, step_m)
    return {"center": center, "opt_line": opt, "widths": widths}
