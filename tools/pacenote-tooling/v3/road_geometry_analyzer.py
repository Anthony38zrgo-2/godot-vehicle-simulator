"""Derivadas geométricas y física de superficie por estación.

Convención de signo: kappa > 0 giro a la DERECHA, kappa < 0 a la izquierda,
con rumbo theta = unwrap(atan2(dx, -dz)).
"""
from typing import Any, Dict, List

import numpy as np

MU_BY_MATERIAL = {
    "road_gravel_1": 0.85,
    "road_forest": 0.76,
    "road_field_1": 0.76,
    "road_crossroad_2": 0.76,
    "road_field_1_cross": 0.76,
    "kenya_road_gravel_1": 0.85,
    "fin_path": 0.76,
}
DEFAULT_MU = 0.80
SANDY_MU = 0.60
SNOW_MU = 0.55
ASPHALT_MU = 0.95
DIRT_MU = 0.76


def grip_mu(material: str) -> float:
    """Adherencia base mu según §3.5.5 + equivalentes por país.

    Orden: tabla exacta > nieve/hielo > asfalto > tierra/barro >
    arena/terreno > grava/carretera genérica.
    """
    m = (material or "").strip()
    if m in MU_BY_MATERIAL:
        return MU_BY_MATERIAL[m]
    low = m.lower()
    if "snow" in low or "ice" in low:
        return SNOW_MU
    if "tarmac" in low or ("tunnel" in low and "road" in low):
        return ASPHALT_MU
    if "railroad" in low:
        return 0.70
    if "jungle" in low or "dirt" in low or "mud" in low or low == "fin_path":
        return DIRT_MU
    if low.startswith("sand_erosion_") or low.startswith("terrain_") or "sand" in low:
        return SANDY_MU
    if "road" in low or "bridge" in low or "crossroad" in low:
        return 0.85
    return DEFAULT_MU


def _moving_avg(x: np.ndarray, window_m: float, step_m: float = 2.0) -> np.ndarray:
    """Media móvil centrada en ventana de `window_m` metros."""
    w = max(1, int(round(window_m / step_m)))
    if w % 2 == 0:
        w += 1
    if w <= 1 or len(x) < w:
        return x.copy()
    pad = w // 2
    xp = np.pad(x, pad, mode="edge")
    kernel = np.ones(w) / w
    return np.convolve(xp, kernel, mode="valid")


def _heading_and_kappa(xy: np.ndarray, step_m: float = 2.0):
    """Rumbo suavizado y curvatura firmada filtrada contra ruido de malla."""
    d = np.diff(xy, axis=0)
    d = np.vstack([d, d[-1:]])
    theta_raw = np.unwrap(np.arctan2(d[:, 0], -d[:, 1]))
    # Suavizar el rumbo en ventana de 10 m antes de derivar
    theta = _moving_avg(theta_raw, 10.0, step_m)
    kappa_raw = np.gradient(theta, step_m)
    # Suavizar curvatura en ventana de 14 m para eliminar micro-ondulaciones de borde
    kappa = _moving_avg(kappa_raw, 14.0, step_m)
    return theta, kappa


def analyze(center: np.ndarray, opt_line: np.ndarray,
            left: np.ndarray, right: np.ndarray,
            materials: List[str], step_m: float = 2.0) -> Dict[str, np.ndarray]:
    """Calcula heading, kappas, grade, kappa_vertical, camber y mu."""
    n = len(center)
    theta_c, kappa_c = _heading_and_kappa(center[:, [0, 2]], step_m)
    _, kappa_opt = _heading_and_kappa(opt_line[:, [0, 2]], step_m)
    grade_raw = 100.0 * np.gradient(center[:, 1], step_m)
    grade = _moving_avg(grade_raw, 12.0, step_m)
    kv_raw = np.gradient(np.gradient(center[:, 1], step_m), step_m)
    kappa_v = _moving_avg(kv_raw, 14.0, step_m)
    span = np.linalg.norm(right[:, [0, 2]] - left[:, [0, 2]], axis=1)
    span = np.where(span < 1e-6, 1.0, span)
    camber = np.degrees(np.arctan2(right[:, 1] - left[:, 1], span))
    kappa_sign = np.sign(kappa_c)
    camber_eff = -kappa_sign * camber
    mu = np.array([grip_mu(m) for m in materials], dtype=np.float64)
    return {"heading_rad": theta_c, "kappa_center": kappa_c,
            "kappa_opt": kappa_opt, "grade_pct": grade,
            "kappa_vertical": kappa_v, "camber_deg": camber,
            "camber_effective_deg": camber_eff, "grip_mu": mu}
