"""Deterministic generator for the 10 bathymetric rally puddle masks (256x256, L).

Each mask encodes normalized basin depth in [0, 1] where:
- 0.000          : dry outside boundary (strict 0.0 margin >= 8.5% for UV domain warping)
- 0.006 .. 0.18  : outer damp-soil saturation halo (rendered as soft wet pavement halo)
- 0.18  .. 1.00  : standing water body (depth = ((mask - 0.18) / 0.82) * fill * max_depth_mm)

All 10 masks use domain-warped multi-octave fBm + ridged shoreline erosion + C1-smooth
signed-distance unions to produce genuinely irregular, asymmetric, flat-bottomed natural
depressions while guaranteeing non-zero standing water (mask >= 0.55) at UV center (0.5, 0.5).
"""

from __future__ import annotations

from pathlib import Path
import numpy as np
from PIL import Image

OUT_DIR = Path(__file__).resolve().parents[1] / "game" / "assets" / "vfx" / "puddles"
SIZE = 256


def _smoothstep(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / np.maximum(e1 - e0, 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _smin(a: np.ndarray, b: np.ndarray, k: float) -> np.ndarray:
    """Polynomial C1 smooth minimum for organic signed-distance unions."""
    h = np.clip(0.5 + 0.5 * (b - a) / max(k, 1e-6), 0.0, 1.0)
    return b * (1.0 - h) + a * h - k * h * (1.0 - h)


def _smax(a: np.ndarray, b: np.ndarray, k: float) -> np.ndarray:
    return -_smin(-a, -b, k)


def _value_noise_2d(x: np.ndarray, y: np.ndarray, seed: int) -> np.ndarray:
    ix = np.floor(x).astype(np.int64)
    iy = np.floor(y).astype(np.int64)
    fx = x - ix
    fy = y - iy
    ux = fx * fx * (3.0 - 2.0 * fx)
    uy = fy * fy * (3.0 - 2.0 * fy)

    def h(gx: np.ndarray, gy: np.ndarray) -> np.ndarray:
        n = (gx * 374761393 + gy * 668265263 + seed * 1442695041) & 0xFFFFFFFF
        n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
        n = (n ^ (n >> 16)) & 0xFFFFFFFF
        return n.astype(np.float32) / 4294967295.0

    a = h(ix, iy)
    b = h(ix + 1, iy)
    c = h(ix, iy + 1)
    d = h(ix + 1, iy + 1)
    return (a * (1.0 - ux) + b * ux) * (1.0 - uy) + (c * (1.0 - ux) + d * ux) * uy


def _fbm(u: np.ndarray, v: np.ndarray, freq: float, seed: int, octaves: int = 4) -> np.ndarray:
    total = np.zeros_like(u, dtype=np.float32)
    amp = 0.55
    norm = 0.0
    f = freq
    ca, sa = np.float32(0.80), np.float32(0.60)
    ru, rv = u.copy(), v.copy()
    for o in range(octaves):
        total += amp * (_value_noise_2d(ru * f + 11.3 * o, rv * f - 7.1 * o, seed + o * 97) * 2.0 - 1.0)
        norm += amp
        amp *= 0.52
        f *= 2.07
        ru, rv = ca * ru - sa * rv, sa * ru + ca * rv
    return total / max(norm, 1e-6)


def _ridged_fbm(u: np.ndarray, v: np.ndarray, freq: float, seed: int, octaves: int = 3) -> np.ndarray:
    """Sharp ridged noise in [-1, 1] for fractured crater rims and gravel indentations."""
    total = np.zeros_like(u, dtype=np.float32)
    amp = 0.55
    norm = 0.0
    f = freq
    ca, sa = np.float32(0.76), np.float32(-0.65)
    ru, rv = u.copy(), v.copy()
    for o in range(octaves):
        n = _value_noise_2d(ru * f - 5.7 * o, rv * f + 9.3 * o, seed + o * 131) * 2.0 - 1.0
        ridge = 1.0 - np.abs(n)
        ridge = ridge * ridge
        total += amp * (ridge * 2.0 - 1.0)
        norm += amp
        amp *= 0.54
        f *= 2.11
        ru, rv = ca * ru - sa * rv, sa * ru + ca * rv
    return total / max(norm, 1e-6)


def _domain_warp(
    u: np.ndarray, v: np.ndarray, freq: float, amp_u: float, amp_v: float, seed: int
) -> tuple[np.ndarray, np.ndarray]:
    wx = _fbm(u, v, freq, seed=seed, octaves=3)
    wy = _fbm(u + 3.7, v - 2.9, freq, seed=seed + 41, octaves=3)
    return u + amp_u * wx, v + amp_v * wy


def _grid() -> tuple[np.ndarray, np.ndarray]:
    lin = np.linspace(-1.0, 1.0, SIZE, dtype=np.float32)
    u, v = np.meshgrid(lin, lin)
    return u, v


def _border_envelope(u: np.ndarray, v: np.ndarray, margin: float = 0.09) -> np.ndarray:
    edge = np.maximum(np.abs(u), np.abs(v))
    return 1.0 - _smoothstep(1.0 - margin - 0.10, 1.0 - margin, edge)


def _finalize(
    raw: np.ndarray,
    u: np.ndarray,
    v: np.ndarray,
    gamma: float = 0.55,
    margin: float = 0.09,
    min_center: float = 0.64,
) -> np.ndarray:
    env = _border_envelope(u, v, margin=margin)
    val = np.clip(raw, 0.0, 1.0) * env
    # Ensure UV center (0.5, 0.5) holds strong standing water for physics & contract probes
    r_ctr = np.sqrt(u * u + v * v)
    ctr_boost = (1.0 - _smoothstep(0.0, 0.28, r_ctr)) * min_center
    val = np.maximum(val, ctr_boost * env)
    peak = float(val.max())
    if peak > 1e-5:
        val = val / peak
    val = np.power(np.clip(val, 0.0, 1.0), gamma)
    val = val * (1.0 - _smoothstep(1.0 - margin - 0.04, 1.0 - margin, np.maximum(np.abs(u), np.abs(v))))
    val[val < 0.004] = 0.0
    return val


def mask_rut(u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """1. Irregular meandering tire-rut channel with pinch-and-swell width & runoff splashes."""
    uw, vw = _domain_warp(u, v, freq=2.2, amp_u=0.13, amp_v=0.09, seed=101)
    n_shore = _fbm(uw, vw, 4.6, seed=107, octaves=4)
    n_ridge = _ridged_fbm(u, v, 6.2, seed=113, octaves=3)
    # Meandering S-curve spine running full length
    spine = (
        0.11 * np.sin(vw * 2.8 + 0.35)
        + 0.06 * np.cos(vw * 5.2 - 0.7)
        - 0.06 * (vw * vw - 0.25)
    )
    u_c = uw - spine
    # Continuous rut with organic pinch-and-swell width (wider basin, never pinches thin)
    swell = (
        0.50
        + 0.11 * np.sin(vw * 3.9 + 0.5)
        + 0.08 * np.cos(vw * 6.8 - 1.1)
        + 0.11 * n_shore
        + 0.05 * n_ridge
    )
    taper_ends = 1.0 - 0.32 * _smoothstep(0.58, 0.88, np.abs(vw))
    width_v = np.clip(swell * taper_ends, 0.32, 0.72)
    du = np.abs(u_c) / width_v
    dv = np.abs(vw) / (0.86 + 0.07 * n_shore)
    d_main = np.power(np.power(du, 2.3) + np.power(dv, 3.6), 1.0 / 2.7)
    # Asymmetric side splash pockets extruded along the rut
    d_sp1 = np.sqrt(((uw - 0.30) / 0.32) ** 2 + ((vw + 0.26) / 0.36) ** 2)
    d_sp2 = np.sqrt(((uw + 0.28) / 0.29) ** 2 + ((vw - 0.22) / 0.34) ** 2)
    d = _smin(_smin(d_main, d_sp1, 0.26), d_sp2, 0.25) - 0.07 * n_shore - 0.04 * n_ridge
    pockets = 0.86 + 0.14 * np.sin(vw * 4.7 + 0.3) + 0.10 * _fbm(u, v, 3.6, seed=127, octaves=3)
    raw = (1.0 - _smoothstep(0.22, 1.0, d)) * np.clip(pockets, 0.68, 1.08)
    return _finalize(raw, u, v, gamma=0.52, margin=0.09)


def mask_twin_rut(u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """2. Asymmetric parallel wheel-ruts of unequal length joined by a diagonal splash breach."""
    uw, vw = _domain_warp(u, v, freq=2.4, amp_u=0.13, amp_v=0.11, seed=203)
    n_edge = _fbm(uw, vw, 4.6, seed=211, octaves=4)
    n_fine = _ridged_fbm(u, v, 6.5, seed=223, octaves=3)

    # Left rut: longer, slightly curved, deeper in lower half
    spine_l = -0.34 + 0.08 * np.sin(vw * 2.9 - 0.4)
    w_l = np.clip(0.32 + 0.09 * np.cos(vw * 4.2 + 0.6) + 0.09 * n_edge, 0.20, 0.52)
    d_left = np.sqrt(((uw - spine_l) / w_l) ** 2 + ((vw + 0.05) / 0.85) ** 2)

    # Right rut: shorter, offset upward, wider splash belly
    spine_r = 0.32 + 0.09 * np.cos(vw * 3.3 + 0.5)
    w_r = np.clip(0.35 + 0.10 * np.sin(vw * 3.7 - 0.9) - 0.08 * n_edge, 0.22, 0.56)
    d_right = np.sqrt(((uw - spine_r) / w_r) ** 2 + ((vw - 0.11) / 0.68) ** 2)

    # Diagonal breach connecting left & right across center (0, 0)
    u_diag = uw * 0.82 - vw * 0.57
    v_diag = uw * 0.57 + vw * 0.82
    d_breach = np.sqrt((u_diag / (0.56 + 0.08 * n_edge)) ** 2 + ((v_diag - 0.03) / (0.36 + 0.07 * n_edge)) ** 2)

    d_union = _smin(_smin(d_left, d_right, 0.25), d_breach, 0.26) - 0.07 * n_edge - 0.04 * n_fine
    base = 1.0 - _smoothstep(0.20, 1.0, d_union)
    # Partial drier crown island at upper/lower gap while center bridge stays flooded
    crown_island = 0.38 * np.exp(-((uw - 0.02) / 0.18) ** 2 - ((vw + 0.38) / 0.24) ** 2)
    raw = base * (1.0 - crown_island)
    return _finalize(raw, u, v, gamma=0.54, margin=0.09)


def mask_gutter_wedge(u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """3. Jagged roadside ditch / cutbank trough on +U with irregular drainage tongues spilling to -U."""
    uw, vw = _domain_warp(u, v, freq=2.5, amp_u=0.14, amp_v=0.12, seed=307)
    n_edge = _fbm(uw, vw, 4.4, seed=311, octaves=4)
    n_rock = _ridged_fbm(u, v, 5.8, seed=317, octaves=3)

    # Steep rocky cutbank wall along +U (around u = +0.28..0.42)
    wall_u = 0.28 + 0.09 * np.sin(vw * 3.1 + 0.3) + 0.08 * n_rock
    u_diff = uw - wall_u
    side_blend = _smoothstep(-0.18, 0.18, u_diff)

    # Three uneven runoff tongues spilling inward toward -U (across road camber)
    tongues = (
        0.22 * np.exp(-((vw + 0.34) / 0.22) ** 2)
        + 0.28 * np.exp(-((vw - 0.04) / 0.25) ** 2)
        + 0.19 * np.exp(-((vw - 0.41) / 0.18) ** 2)
    )
    inward_reach = np.clip(0.68 + tongues + 0.14 * n_edge, 0.42, 1.12)
    outward_steep = np.clip(0.36 + 0.07 * n_rock, 0.24, 0.50)
    u_scale = inward_reach * (1.0 - side_blend) + outward_steep * side_blend

    du = np.abs(u_diff) / u_scale
    dv = np.abs(vw - 0.02 * uw) / (0.84 + 0.08 * n_edge)
    d = np.sqrt(du * du + dv * dv) - 0.06 * n_edge - 0.045 * n_rock
    profile = 1.0 - _smoothstep(0.18, 1.0, d)
    local_gamma = 0.78 * (1.0 - side_blend) + 0.44 * side_blend
    raw = np.power(np.clip(profile, 0.0, 1.0), local_gamma)
    return _finalize(raw, u, v, gamma=0.58, margin=0.09)


def mask_kidney_soft(u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """4. Asymmetric hooked apex crescent with a wide pooled belly and scalloped shoreline bays."""
    uw, vw = _domain_warp(u, v, freq=2.2, amp_u=0.15, amp_v=0.13, seed=409)
    n_edge = _fbm(uw, vw, 4.2, seed=419, octaves=4)
    n_fine = _ridged_fbm(u, v, 6.4, seed=431, octaves=3)

    # Asymmetric banana/hook bend passing through (0, 0)
    u_bent = uw - 0.46 * (vw * vw - 0.12) - 0.11 * (vw ** 3)
    # Wide belly at v < 0, broader hooked tail at v > 0
    width_profile = np.clip(0.50 - 0.14 * vw + 0.10 * np.sin(vw * 4.5 + 0.8) + 0.10 * n_edge, 0.26, 0.72)
    du = u_bent / width_profile
    dv = (vw + 0.04) / (0.82 + 0.07 * n_edge)
    d_arc = np.sqrt(du * du + dv * dv)
    # Secondary inner apex pocket
    d_pocket = np.sqrt(((uw + 0.22) / 0.38) ** 2 + ((vw + 0.20) / 0.38) ** 2)
    d = _smin(d_arc, d_pocket, 0.26) - 0.07 * n_edge - 0.04 * n_fine
    raw = 1.0 - _smoothstep(0.20, 1.0, d)
    return _finalize(raw, u, v, gamma=0.56, margin=0.09)


def mask_pothole(u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """5. Fractured asphalt/gravel pothole crater: angular jagged rim, steep walls & off-center pit."""
    uw, vw = _domain_warp(u, v, freq=2.8, amp_u=0.16, amp_v=0.16, seed=503)
    n_frac = _ridged_fbm(uw, vw, 4.2, seed=521, octaves=4)
    n_rim = _fbm(uw, vw, 5.6, seed=541, octaves=3)

    # Asymmetric multi-faceted fracture contour (non-elliptical)
    theta = np.arctan2(vw - 0.04, uw + 0.05)
    r_angular = (
        0.58
        + 0.12 * np.sin(3.0 * theta + 0.6)
        - 0.09 * np.cos(4.0 * theta - 1.2)
        + 0.07 * np.sin(5.0 * theta + 2.1)
        + 0.13 * n_frac
        + 0.08 * n_rim
    )
    r1 = np.sqrt(((uw + 0.05) * 1.12) ** 2 + ((vw - 0.04) * 0.92) ** 2) / np.clip(r_angular, 0.28, 0.92)
    # Jagged spalled fracture chip breaking off toward (-0.28, +0.26)
    r2 = np.sqrt(((uw + 0.27) / 0.28) ** 2 + ((vw - 0.24) / 0.23) ** 2)
    # Trailing tire-exit chip toward (+0.24, -0.26)
    r3 = np.sqrt(((uw - 0.23) / 0.25) ** 2 + ((vw + 0.27) / 0.21) ** 2)
    d = _smin(_smin(r1, r2, 0.24), r3, 0.22) - 0.06 * n_frac
    raw = 1.0 - _smoothstep(0.28, 1.0, d)
    return _finalize(raw, u, v, gamma=0.44, margin=0.09)


def mask_egg_asym(u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """6. Asymmetric broken crater + diagonal washout scar + small trailing satellite pool."""
    uw, vw = _domain_warp(u, v, freq=2.5, amp_u=0.15, amp_v=0.14, seed=601)
    n_edge = _fbm(uw, vw, 4.5, seed=613, octaves=4)
    n_ridge = _ridged_fbm(u, v, 6.0, seed=619, octaves=3)

    # Main upper-left crater (wide, irregular, covers center)
    d_main = np.sqrt(((uw + 0.08) / (0.46 + 0.09 * n_edge)) ** 2 + ((vw + 0.09) / (0.42 + 0.08 * n_edge)) ** 2)
    # Elongated diagonal scar extending toward (+0.26, -0.28)
    u_r = (uw - 0.18) * 0.78 + (vw - 0.22) * 0.62
    v_r = -(uw - 0.18) * 0.62 + (vw - 0.22) * 0.78
    d_scar = np.sqrt((u_r / (0.26 + 0.06 * n_edge)) ** 2 + (v_r / (0.44 + 0.07 * n_edge)) ** 2)
    # Small side pocket toward (-0.34, +0.28)
    d_sat = np.sqrt(((uw + 0.34) / 0.22) ** 2 + ((vw - 0.29) / 0.20) ** 2)

    d_union = _smin(_smin(d_main, d_scar, 0.26), d_sat, 0.18) - 0.07 * n_edge - 0.045 * n_ridge
    raw = 1.0 - _smoothstep(0.22, 1.0, d_union)
    raw = raw * (0.86 + 0.18 * _smoothstep(-0.45, 0.35, -vw - 0.4 * uw))
    return _finalize(raw, u, v, gamma=0.50, margin=0.09)


def mask_basin(u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """7. Sprawling eroded compression basin with dendritic runoff inlets & multi-pocket floor."""
    uw, vw = _domain_warp(u, v, freq=2.1, amp_u=0.17, amp_v=0.15, seed=701)
    n1 = _fbm(uw, vw, 3.6, seed=719, octaves=4)
    n2 = _ridged_fbm(u, v, 5.4, seed=733, octaves=3)

    d_core = np.sqrt(((uw + 0.04) / 0.56) ** 2 + ((vw - 0.03) / 0.48) ** 2)
    d_arm1 = np.sqrt(((uw - 0.32) / 0.34) ** 2 + ((vw + 0.18) / 0.26) ** 2)
    d_arm2 = np.sqrt(((uw + 0.29) / 0.28) ** 2 + ((vw + 0.27) / 0.32) ** 2)
    d_arm3 = np.sqrt(((uw + 0.12) / 0.26) ** 2 + ((vw - 0.36) / 0.29) ** 2)
    d_outer = _smin(_smin(d_core, d_arm1, 0.30), _smin(d_arm2, d_arm3, 0.28), 0.28) - 0.09 * n1 - 0.05 * n2
    d_inner = np.sqrt(((uw - 0.07) / 0.36) ** 2 + ((vw + 0.05) / 0.31) ** 2) - 0.06 * n2

    outer = 0.64 * (1.0 - _smoothstep(0.20, 1.0, d_outer))
    inner = 0.36 * (1.0 - _smoothstep(0.12, 1.0, d_inner))
    raw = (outer + inner) * (0.86 + 0.14 * np.clip(0.5 + n1, 0.0, 1.0))
    return _finalize(raw, u, v, gamma=0.55, margin=0.09)


def mask_sheet(u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """8. Wide diagonal cross-road aquaplaning flood sheet with long runoff fingers & shoal islands."""
    uw, vw = _domain_warp(u, v, freq=2.0, amp_u=0.18, amp_v=0.16, seed=809)
    n1 = _fbm(uw, vw, 3.4, seed=823, octaves=4)
    n2 = _ridged_fbm(u, v, 5.8, seed=839, octaves=3)

    # Diagonal main sheet + 4 elongated runoff tongues
    u_d = uw * 0.85 + vw * 0.52
    v_d = -uw * 0.52 + vw * 0.85
    d_main = np.sqrt((u_d / (0.64 + 0.12 * n1)) ** 2 + (v_d / (0.48 + 0.10 * n1)) ** 2)
    d_f1 = np.sqrt(((uw - 0.36) / 0.25) ** 2 + ((vw - 0.26) / 0.36) ** 2)
    d_f2 = np.sqrt(((uw + 0.38) / 0.32) ** 2 + ((vw + 0.19) / 0.24) ** 2)
    d_f3 = np.sqrt(((uw - 0.14) / 0.24) ** 2 + ((vw + 0.38) / 0.30) ** 2)
    d = _smin(_smin(d_main, d_f1, 0.28), _smin(d_f2, d_f3, 0.26), 0.28) - 0.09 * n1 - 0.05 * n2

    # Subtle shallow shoals near the periphery for natural broken-film sheet texture
    shoal = 0.26 * _smoothstep(0.32, 0.72, d) * np.clip(0.5 - n1, 0.0, 1.0)
    raw = (1.0 - _smoothstep(0.24, 1.0, d)) * (1.0 - shoal)
    return _finalize(raw, u, v, gamma=0.50, margin=0.085)


def mask_lobe_triple(u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """9. Irregular branching Y/L-shaped coalesced drainage swale (meandering multi-bay pool)."""
    uw, vw = _domain_warp(u, v, freq=2.2, amp_u=0.17, amp_v=0.15, seed=907)
    n_edge = _fbm(uw, vw, 4.0, seed=919, octaves=4)
    n_ridge = _ridged_fbm(u, v, 5.8, seed=929, octaves=3)

    # Diagonal main swale + oblique drainage branch + trailing runoff bay
    u_a = (uw + 0.06) * 0.82 - (vw - 0.03) * 0.57
    v_a = (uw + 0.06) * 0.57 + (vw - 0.03) * 0.82
    d_swale = np.sqrt((u_a / (0.34 + 0.08 * n_edge)) ** 2 + (v_a / (0.72 + 0.09 * n_edge)) ** 2)

    u_b = (uw - 0.24) * 0.60 + (vw + 0.14) * 0.80
    v_b = -(uw - 0.24) * 0.80 + (vw + 0.14) * 0.60
    d_branch = np.sqrt((u_b / (0.28 + 0.07 * n_edge)) ** 2 + (v_b / (0.48 + 0.08 * n_edge)) ** 2)

    d_bay = np.sqrt(((uw + 0.28) / 0.33) ** 2 + ((vw + 0.24) / 0.26) ** 2)
    d_union = _smin(_smin(d_swale, d_branch, 0.34), d_bay, 0.32) - 0.08 * n_edge - 0.045 * n_ridge
    raw = 1.0 - _smoothstep(0.22, 1.0, d_union)
    return _finalize(raw, u, v, gamma=0.54, margin=0.09)


def mask_round_organic(u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """10. Porous, island-pocked shallow rain-glaze splatter with ragged shoreline fingers."""
    uw, vw = _domain_warp(u, v, freq=2.6, amp_u=0.17, amp_v=0.17, seed=1009)
    n1 = _fbm(uw, vw, 3.8, seed=1013, octaves=4)
    n2 = _ridged_fbm(u, v, 6.6, seed=1021, octaves=3)

    d_base = np.sqrt(((uw - 0.05) / 0.54) ** 2 + ((vw + 0.04) / 0.44) ** 2)
    d_lobe1 = np.sqrt(((uw + 0.31) / 0.32) ** 2 + ((vw - 0.19) / 0.25) ** 2)
    d_lobe2 = np.sqrt(((uw - 0.24) / 0.24) ** 2 + ((vw + 0.29) / 0.31) ** 2)
    d = _smin(_smin(d_base, d_lobe1, 0.28), d_lobe2, 0.26) - 0.11 * n1 - 0.06 * n2

    # Porous micro-relief breakup near outer shore while center stays continuous
    r_ctr = np.sqrt(u * u + v * v)
    porous = 0.32 * _smoothstep(0.18, 0.62, r_ctr) * np.clip(0.45 - n1 + 0.3 * n2, 0.0, 1.0)
    raw = (1.0 - _smoothstep(0.16, 1.0, d)) * (1.0 - porous)
    return _finalize(raw, u, v, gamma=0.68, margin=0.09)


MASKS = {
    "puddle_rut.png": mask_rut,
    "puddle_twin_rut.png": mask_twin_rut,
    "puddle_gutter_wedge.png": mask_gutter_wedge,
    "puddle_kidney_soft.png": mask_kidney_soft,
    "puddle_pothole.png": mask_pothole,
    "puddle_egg_asym.png": mask_egg_asym,
    "puddle_basin.png": mask_basin,
    "puddle_sheet.png": mask_sheet,
    "puddle_lobe_triple.png": mask_lobe_triple,
    "puddle_round_organic.png": mask_round_organic,
}


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    u, v = _grid()
    cx = SIZE // 2
    for name, fn in MASKS.items():
        arr = fn(u, v)
        border = float(max(arr[0, :].max(), arr[-1, :].max(), arr[:, 0].max(), arr[:, -1].max()))
        center = float(arr[cx, cx])
        frac_body = float((arr > 0.18).mean())
        frac_wet = float((arr > 0.01).mean())
        assert border == 0.0, f"{name}: non-zero border {border}"
        assert center >= 0.45, f"{name}: center depth too low ({center:.3f})"
        img = Image.fromarray(np.round(arr * 255.0).astype(np.uint8), mode="L")
        img.save(OUT_DIR / name, optimize=True)
        print(
            f"{name:26s} center={center:.3f} max={arr.max():.3f} border={border:.3f} "
            f"body(>0.18)={frac_body:.3f} wet(>0.01)={frac_wet:.3f}"
        )


if __name__ == "__main__":
    main()
