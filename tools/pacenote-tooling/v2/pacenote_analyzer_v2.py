"""
Analizador de trazado y generador de Pacenotes CMR2 (v2).

Cruza la geometría 3D de la ruta (resetN.bin) con perfil vertical, objetos físicos 3D y un modelo
de velocidad/tiempo para generar llamadas con RITMO consistente y PELIGROS priorizados.

Cambios principales respecto a v1
---------------------------------
RITMO
  * La detección de curvas trabaja en el dominio de la distancia (polilínea remuestreada cada
    ~3 m, curvatura dθ/ds, histéresis, fusión de curvas del mismo sentido, absorción de zigzags
    pequeños, ángulo mínimo). Ya no depende del espaciado de nodos.
  * Perfil de velocidad esperado (límite lateral + aceleración/frenada) por todo el tramo.
  * Planificador de llamadas: el instante de aviso depende de velocidad y duración de la frase
    (no 50 m fijos). Si dos llamadas se pisan: se retrasa la segunda (queda encadenada), se acorta
    la de menor prioridad por niveles, y como último recurso se descarta (nunca un peligro crítico).
PELIGROS
  * Prioridad por gravedad (jump > cruce > portón > rocas > poste > crest), no por orden de mesh.
  * Los peligros en rectas ahora se cantan como entradas propias (kind=0, solo hazard/surface).
  * Salto/crest decididos con física (v²·κv / g) usando la velocidad esperada en ese punto.
  * Distancia al objeto por vértice en XZ (no centroide); filtros laterales para todos los tipos.
  * `caution` escala a 2 (salto antes de curva cerrada, rocas interiores en curva cerrada,
    frenada muy exigente en horquilla...).
  * Se corrige el wrap de yaw (±π) que daba tightens/opens falsos, y el filtro "tree" que
    descartaba "street*".
  * confidence / review_status ya no están hardcodeados.

Genera (mismos nombres que v1):
- <country>_<stage>_pacenotes_candidates.json
- <country>_<stage>_pacenotes_authoring.json
- <country>_<stage>_pacenotes.json  (runtime)
"""

import json
import math
import re
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import numpy as np


# ---------------------------------------------------------------------------------------------
# Codec CMR2 (sin cambios respecto a v1)
# ---------------------------------------------------------------------------------------------
def pack_cmr2_word(
    kind: int = 0,
    direction: int = 0,
    distance: int = 0,
    length: int = 0,
    turn: int = 0,
    surface: int = 0,
    hazard: int = 0,
    caution: int = 0,
    junction: int = 0,
    no_cut: int = 0,
    ending: int = 0,
    side: int = 0,
) -> int:
    return (
        (kind & 15)
        | ((direction & 3) << 4)
        | ((distance & 15) << 6)
        | ((length & 3) << 10)
        | ((turn & 7) << 12)
        | ((surface & 3) << 15)
        | ((hazard & 15) << 17)
        | ((caution & 3) << 21)
        | ((junction & 1) << 23)
        | ((no_cut & 1) << 24)
        | ((ending & 7) << 25)
        | ((side & 3) << 28)
    ) & 0xFFFFFFFF


def decode_cmr2_slots(word: int, mirror: bool = False) -> List[int]:
    word &= 0xFFFFFFFF
    kind = word & 15
    direction = (word >> 4) & 3
    distance = (word >> 6) & 15
    length = (word >> 10) & 3
    turn = (word >> 12) & 7
    surface = (word >> 15) & 3
    hazard = (word >> 17) & 15
    caution = (word >> 21) & 3
    junction = (word >> 23) & 1
    no_cut = (word >> 24) & 1
    ending = (word >> 25) & 7
    side = (word >> 28) & 3

    res: List[int] = []
    if (
        kind == 6
        and direction == 0
        and distance == 0
        and length == 0
        and turn == 0
        and hazard == 0
        and caution == 0
        and surface == 0
        and side == 0
        and no_cut == 0
        and ending == 0
    ):
        return res

    if kind == 9:
        res.append(55)
    if 1 <= distance <= 14:
        res.append(min(13 + distance, 22))
    if caution in (1, 2):
        res.append({1: 26, 2: 27}[caution])
    if length in (1, 2):
        res.append({1: 10, 2: 28}[length])
    if junction == 1:
        res.append(29)
    if 1 <= kind <= 8:
        res.append({1: 5, 2: 4, 3: 3, 4: 2, 5: 1, 6: 0, 7: 6, 8: 7}[kind])
    if direction in (1, 2):
        res.append((9 if direction == 1 else 8) if mirror else (8 if direction == 1 else 9))
    if turn in (1, 2, 3):
        res.append({1: 12, 2: 11, 3: 30}[turn])
    if surface in (1, 2):
        res.append({1: 23, 2: 31}[surface])
    if 1 <= hazard <= 15:
        res.append(
            {
                1: 25, 2: 24, 3: 34, 4: 35, 5: 36, 6: 33, 7: 37, 8: 38,
                9: 39, 10: 40, 11: 41, 12: 42, 13: 43, 14: 54, 15: 32,
            }[hazard]
        )
    if side in (1, 2):
        res.append({1: 44, 2: 45}[side])
    if no_cut == 1:
        res.append(46)
    if 1 <= ending <= 7:
        res.append(46 + ending)
    return res


# ---------------------------------------------------------------------------------------------
# Configuración (todo lo "afinable" está aquí)
# ---------------------------------------------------------------------------------------------
@dataclass
class PaceConfig:
    # --- detección de curvas (dominio distancia) ---
    resample_m: float = 3.0          # paso del remuestreo de la ruta
    smooth_m: float = 9.0            # suavizado del rumbo
    r_on_m: float = 280.0            # entra en curva si R < r_on
    r_off_m: float = 420.0           # sale de curva si R > r_off (histéresis)
    merge_gap_m: float = 20.0        # funde curvas del mismo sentido separadas < esto
    wiggle_deg: float = 10.0         # un zigzag opuesto menor a esto se absorbe...
    wiggle_gap_m: float = 15.0       # ...si sus huecos con los vecinos son < esto
    min_angle_deg: float = 15.0      # no se canta una curva con menos ángulo total
    flat_min_angle_deg: float = 20.0 # umbral para curvas "six" (casi planas)
    # --- perfil de velocidad esperado ---
    a_lat: float = 8.0               # m/s² lateral
    a_acc: float = 4.5               # m/s² aceleración
    a_brk: float = 7.0               # m/s² frenada
    v_max: float = 55.0              # m/s (~200 km/h)
    v_start: float = 12.0            # m/s en la salida
    # --- perfil vertical ---
    g: float = 9.81
    vslope_smooth_m: Optional[float] = None  # None = automático: max(9 m, 2.5 x espaciado de nodos)
    crest_ratio: float = 0.50        # v²·κv/g mínimo para "over crest" (en curva)
    straight_crest_ratio: float = 0.80  # idem pero en recta (evita saturar)
    jump_ratio: float = 1.0          # >= esto: despegue físico => "jump"
    geom_jump_min_ratio: float = 0.6 # el criterio geométrico solo vale si ratio >= esto
    compression_ratio: float = 0.6   # compresión (valle) relevante
    hazard_compression: Optional[int] = None  # id de hazard CMR2 para compresión; None = solo candidatos
    # --- obstáculos ---
    obstacle_radius_m: float = 16.0
    curve_zone_before_m: float = 20.0
    curve_zone_after_m: float = 10.0
    straight_group_m: float = 25.0   # peligros de recta a < esto se agrupan en una llamada
    # --- severidad por pendiente ---
    sev_down_mid_pct: float = 4.0    # descenso (%) que suma 0.5 punto
    sev_down_high_pct: float = 6.5   # suma 1.0
    sev_down_extreme_pct: float = 10.0  # suma 2.0
    sev_demand_mid_ms: float = 22.0  # velocidad a perder (m/s) hasta el ápice que suma 0.5 (curvas >= three... kind>=3)
    sev_demand_high_ms: float = 30.0 # suma 1.0
    sev_approach_m: float = 40.0     # tramo previo a la curva que cuenta como zona de frenada
    sev_max_bonus: int = 2           # máximo de escalones de severidad que se pueden añadir
    # --- ritmo ---
    t_lead_s: float = 3.0            # la frase debe terminar ~3 s antes del evento
    min_lead_s: float = 1.5          # mínimo absoluto aceptable
    margin_s: float = 0.8            # silencio mínimo entre llamadas
    speed_safety: float = 1.15       # el piloto real puede ir más rápido que el perfil esperado
    slot_sec: float = 0.50           # duración por defecto de cada palabra (conservadora)
    base_sec: float = 0.35
    slot_durations: Optional[Dict[int, float]] = None  # duración medida por slot (ver --slot-durations)
    lead_min_m: float = 40.0
    lead_max_m: float = 260.0
    # --- emisión ---
    emit_standalone_hazards: bool = True
    use_calibrated_table: bool = True
    protect_table_curves: bool = False  # True: nunca descartar curvas de la tabla (si no caben, se solapan y se marcan)
    distance_mode: str = "next"      # "next" = comportamiento v1 (gap a la curva siguiente); "prev" = gap desde la anterior
    runtime_extra_fields: bool = True


PRIO_CRITICAL = 90
HAZARD_RANK = {"jump": 100, "junction": 90, "gate": 70, "rocks_nocut": 65, "rocks": 50, "post": 45, "crest": 35}
KIND_BASE_PRIORITY = {1: 30, 2: 40, 3: 50, 4: 60, 5: 70, 6: 75, 7: 80, 8: 85}
KIND_NAMES = {1: "six", 2: "five", 3: "four", 4: "three", 5: "two", 6: "one", 7: "openhairpin", 8: "hairpin"}
HAZARD_NAMES = {0: "none", 1: "jump", 2: "crest", 4: "rocks", 5: "post", 6: "gate"}

JUNCTION_KEYS = ("roadbar", "dangerouscrossing", "sign_hardturn")
GATE_KEYS = ("fence_gate",)
ROCK_KEYS = ("stone_", "rock_")
POST_KEYS = ("phoneline", "sign_splimit")
_EXCLUDE_TOKENS = ("sky", "horizon", "tree", "bush", "grass", "forest")

# límites laterales (m desde el eje de la ruta)
CURVE_LAT = {"junction": 8.0, "gate": 6.0, "rocks": 9.5, "rocks_nocut": 8.5, "post": 3.5}
STRAIGHT_LAT = {"junction": 8.0, "gate": 6.0, "rocks": 5.0, "post": 2.5}

RUNTIME_ORIGINAL_KEYS = (
    "curve_id", "start_node", "end_node", "advisory_gate_node", "route_distance_m", "length_m",
    "total_angle_deg", "direction", "estimated_radius_m", "cmr2_kind", "caution",
    "call_word_hex", "call_index", "confidence", "review_status", "evidence",
)

# Calibración manual de russia_stage1 (nodos). Se usa solo si cfg.use_calibrated_table.
RU1_CALIBRATED_INTERVALS = [
    (13, 15, "left", 140.1, 8.2), (16, 25, "right", 193.5, 27.3), (30, 33, "left", 206.2, 8.6),
    (42, 45, "left", 211.0, 8.4), (47, 60, "right", 237.1, 32.2), (62, 68, "right", 115.5, 30.3),
    (69, 78, "left", 124.5, 42.2), (85, 93, "left", 112.5, 41.7), (96, 106, "right", 107.0, 55.4),
    (108, 116, "left", 113.8, 41.3), (133, 136, "right", 22.0, 88.5), (139, 146, "left", 73.2, 57.0),
    (148, 153, "right", 111.4, 27.2), (170, 176, "right", 105.1, 34.3), (204, 207, "left", 24.0, 78.4),
    (215, 219, "left", 110.2, 22.1), (238, 245, "right", 116.4, 35.5), (248, 253, "left", 112.1, 26.6),
    (257, 261, "right", 108.5, 22.3), (264, 267, "left", 115.2, 16.4), (269, 272, "right", 118.0, 15.6),
    (275, 281, "left", 110.5, 32.2), (285, 289, "left", 125.1, 19.3), (302, 307, "right", 114.2, 26.1),
    (323, 333, "left", 122.5, 48.3), (340, 345, "right", 115.4, 26.0), (352, 358, "left", 110.8, 32.2),
    (366, 375, "right", 112.4, 46.5), (378, 386, "left", 115.0, 42.1), (397, 402, "right", 65.2, 48.0),
    (419, 425, "right", 68.4, 52.1), (457, 465, "left", 115.0, 41.5),
]


# ---------------------------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------------------------
def _json_default(o: Any):
    if isinstance(o, np.integer):
        return int(o)
    if isinstance(o, np.floating):
        return float(o)
    if isinstance(o, np.bool_):
        return bool(o)
    raise TypeError(f"No serializable: {type(o)}")


def _smooth_edge(a: np.ndarray, win: int) -> np.ndarray:
    """Media móvil con relleno de bordes (sin el sesgo a cero de np.convolve 'same')."""
    if win <= 1:
        return a.copy()
    pad = win // 2
    ap = np.pad(a, (pad, win - 1 - pad), mode="edge")
    return np.convolve(ap, np.ones(win) / win, mode="valid")


def _nearest_node(cum_d: np.ndarray, s: float) -> int:
    i = int(np.searchsorted(cum_d, s))
    if i <= 0:
        return 0
    if i >= len(cum_d):
        return len(cum_d) - 1
    return i - 1 if abs(cum_d[i - 1] - s) <= abs(cum_d[i] - s) else i


def _floor_node(cum_d: np.ndarray, s: float) -> int:
    i = int(np.searchsorted(cum_d, s, side="right")) - 1
    return int(min(max(i, 0), len(cum_d) - 1))


def _excluded(name: str) -> bool:
    """Descarta vegetación/cielo por TOKEN (v1 usaba subcadena: 'street' contiene 'tree')."""
    tokens = re.split(r"[^a-z]+", name.lower())
    return any(t.startswith(p) for t in tokens if t for p in _EXCLUDE_TOKENS)


def _resample(pts: np.ndarray, cum_d: np.ndarray, ds: float) -> Tuple[np.ndarray, np.ndarray]:
    keep = np.concatenate([[True], np.diff(cum_d) > 1e-6])
    c, p = cum_d[keep], pts[keep]
    total = float(c[-1])
    k = max(int(math.floor(total / ds)), 2) + 1
    s_r = np.linspace(0.0, total, k)
    pts_r = np.stack([np.interp(s_r, c, p[:, d]) for d in range(3)], axis=1)
    return s_r, pts_r


def _distance_class(gap_m: float) -> int:
    if gap_m >= 180.0:
        return 9   # 200
    if gap_m >= 135.0:
        return 8   # 150
    if gap_m >= 110.0:
        return 7   # 120
    if gap_m >= 85.0:
        return 6   # 100
    if gap_m >= 60.0:
        return 5   # 70
    if gap_m >= 40.0:
        return 4   # 50
    if gap_m >= 22.0:
        return 3   # 30
    if gap_m >= 10.0:
        return 2   # into
    return 1       # and


def classify_kind(radius_m: float, angle_deg: float) -> Tuple[int, str]:
    """1=six .. 6=one, 7=openhairpin, 8=hairpin."""
    if (angle_deg >= 85.0 and radius_m <= 25.0) or (angle_deg >= 120.0 and radius_m <= 35.0):
        kind = 8 if angle_deg >= 100.0 else 7
    elif radius_m >= 130.0:
        kind = 1
    elif radius_m >= 95.0:
        kind = 2
    elif radius_m >= 60.0:
        kind = 3
    elif radius_m >= 35.0:
        kind = 4
    elif radius_m >= 22.0:
        kind = 5
    else:
        kind = 6
    return kind, KIND_NAMES[kind]


# ---------------------------------------------------------------------------------------------
# Geometría: curvatura, curvas, perfil de velocidad
# ---------------------------------------------------------------------------------------------
def compute_heading_curvature(s_r: np.ndarray, pts_r: np.ndarray, cfg: PaceConfig):
    """Rumbo desenrollado (sin saltos de ±π) y curvatura con signo (+ = derecha)."""
    ds = float(s_r[1] - s_r[0])
    seg = pts_r[1:] - pts_r[:-1]
    h = np.unwrap(np.arctan2(seg[:, 0], -seg[:, 2]))
    s_mid = 0.5 * (s_r[:-1] + s_r[1:])
    theta = np.interp(s_r, s_mid, h)
    win = max(1, int(round(cfg.smooth_m / ds)))
    kappa = np.gradient(_smooth_edge(theta, win), ds)
    return theta, kappa, ds


def build_speed_profile(kappa: np.ndarray, ds: float, cfg: PaceConfig,
                        grade: Optional[np.ndarray] = None) -> Tuple[np.ndarray, np.ndarray]:
    """
    (v_final, v_libre). v_libre = solo límite lateral + aceleración (sin frenar para curvas).
    `grade` = dy/ds suavizado: en bajada se acelera más y se frena peor (a_brk + g·grade, grade<0).
    """
    gr = np.zeros(len(kappa)) if grade is None else grade
    a_acc = np.maximum(1.5, cfg.a_acc - cfg.g * gr)
    a_brk = np.maximum(3.0, cfg.a_brk + cfg.g * gr)
    v = np.minimum(cfg.v_max, np.sqrt(cfg.a_lat / np.maximum(np.abs(kappa), 1e-4)))
    v[0] = min(v[0], cfg.v_start)
    for i in range(1, len(v)):
        v[i] = min(v[i], math.sqrt(v[i - 1] ** 2 + 2.0 * a_acc[i] * ds))
    v_free = v.copy()
    for i in range(len(v) - 2, -1, -1):
        v[i] = min(v[i], math.sqrt(v[i + 1] ** 2 + 2.0 * a_brk[i] * ds))
    return v, v_free


def detect_curve_runs(s_r, kappa, ds, cfg: PaceConfig) -> List[Dict[str, Any]]:
    k_on, k_off = 1.0 / cfg.r_on_m, 1.0 / cfg.r_off_m
    n = len(kappa)
    sgn = np.sign(kappa)

    runs: List[List[int]] = []
    i = 0
    while i < n:
        if abs(kappa[i]) >= k_on:
            sg = sgn[i]
            a = i
            lo = runs[-1][1] if runs else 0
            while a > lo and sgn[a - 1] == sg and abs(kappa[a - 1]) >= k_off:
                a -= 1
            b = i
            while b + 1 < n and sgn[b + 1] == sg and abs(kappa[b + 1]) >= k_off:
                b += 1
            runs.append([a, b + 1, int(sg)])
            i = b + 1
        else:
            i += 1

    def pos(idx: int) -> float:
        return float(s_r[min(idx, n - 1)])

    # 1) fusionar mismo sentido con hueco corto
    merged: List[List[int]] = []
    for r in runs:
        if merged and merged[-1][2] == r[2] and pos(r[0]) - pos(merged[-1][1]) <= cfg.merge_gap_m:
            merged[-1][1] = r[1]
        else:
            merged.append(list(r))

    # 2) absorber zigzags opuestos pequeños entre dos curvas del mismo sentido
    i = 1
    while i < len(merged) - 1:
        a, b, c = merged[i - 1], merged[i], merged[i + 1]
        ang = abs(float(np.sum(kappa[b[0]:b[1]])) * ds) * 180.0 / math.pi
        if (
            a[2] == c[2] and b[2] != a[2] and ang < cfg.wiggle_deg
            and pos(b[0]) - pos(a[1]) <= cfg.wiggle_gap_m and pos(c[0]) - pos(b[1]) <= cfg.wiggle_gap_m
        ):
            merged[i - 1] = [a[0], c[1], a[2]]
            del merged[i:i + 2]
        else:
            i += 1

    out = []
    for a, b, _ in merged:
        sub = kappa[a:b]
        if len(sub) == 0:
            continue
        net = float(np.sum(sub) * ds)
        ang_rad = abs(net)
        ang = ang_rad * 180.0 / math.pi
        if ang < cfg.min_angle_deg:
            continue
        s0, s1 = pos(a), pos(b)
        length = s1 - s0
        avg_r = length / max(ang_rad, 1e-4)
        apex_r = 1.0 / max(float(np.max(np.abs(sub))), 1e-4)
        out.append({
            "s0": s0, "s1": s1, "dir": "right" if net > 0 else "left",
            "radius": round(0.55 * min(apex_r, 2000.0) + 0.45 * avg_r, 1),
            "angle": round(ang, 1), "origin": "auto",
        })
    return out


def calibrated_intervals(cum_d: np.ndarray) -> List[Dict[str, Any]]:
    n = len(cum_d)
    out = []
    for s_n, e_n, d, r, ang in RU1_CALIBRATED_INTERVALS:
        s_n, e_n = min(s_n, n - 2), min(e_n, n - 1)
        out.append({"s0": float(cum_d[s_n]), "s1": float(cum_d[e_n]), "dir": d,
                    "radius": r, "angle": ang, "origin": "table"})
    return out


def half_radii(s0: float, s1: float, s_r: np.ndarray, theta: np.ndarray) -> Tuple[float, float]:
    """Radios de la 1ª y 2ª mitad de la curva usando rumbo desenrollado (sin wrap)."""
    sm = 0.5 * (s0 + s1)
    th = lambda s: float(np.interp(s, s_r, theta))
    a1 = abs(th(sm) - th(s0))
    a2 = abs(th(s1) - th(sm))
    return (sm - s0) / max(a1, 1e-4), (s1 - sm) / max(a2, 1e-4)


# ---------------------------------------------------------------------------------------------
# Perfil vertical: crests / saltos / compresiones (con física)
# ---------------------------------------------------------------------------------------------
def detect_vertical_features(s_r, y_r, v_prof, cum_d, cfg: PaceConfig, smooth_m: float):
    ds = float(s_r[1] - s_r[0])
    k = len(s_r)
    slope = np.gradient(y_r, ds)
    slope_s = _smooth_edge(slope, max(1, int(round(smooth_m / ds))))
    kv = np.gradient(slope_s, ds)                       # curvatura vertical (1/m); <0 = convexo
    r_crest = v_prof ** 2 * (-kv) / cfg.g
    r_comp = v_prof ** 2 * kv / cfg.g
    w = max(6, int(round(smooth_m / ds)))
    off = max(5, int(round(smooth_m / ds)))

    def peaks(arr, thr):
        res, last = [], -10 ** 9
        for j in range(3, k - 3):
            if arr[j] >= thr and arr[j] >= np.max(arr[max(0, j - w):j + w + 1]) and j - last >= w:
                res.append(j)
                last = j
        return res

    crests, comps = [], []
    for j in peaks(r_crest, cfg.crest_ratio):
        s_in = float(slope_s[max(0, j - off)])
        s_out = float(slope_s[min(k - 1, j + off)])
        delta = (s_out - s_in) * 100.0
        geom = (delta <= -8.0 and s_out <= -0.08) or (s_in >= 0.10 and delta <= -10.0)
        ratio = float(r_crest[j])
        is_jump = ratio >= cfg.jump_ratio or (geom and ratio >= cfg.geom_jump_min_ratio)
        node = _nearest_node(cum_d, float(s_r[j]))
        crests.append({
            "node": node, "dist_m": round(float(s_r[j]), 1),
            "slope_in_pct": round(s_in * 100, 1), "slope_out_pct": round(s_out * 100, 1),
            "delta_slope_pct": round(delta, 2), "is_jump": bool(is_jump),
            "airborne_ratio": round(ratio, 2), "speed_kmh": round(float(v_prof[j]) * 3.6, 0),
            "geometric_jump": bool(geom), "s": float(s_r[j]),
        })
    for j in peaks(r_comp, cfg.compression_ratio):
        comps.append({
            "node": _nearest_node(cum_d, float(s_r[j])), "dist_m": round(float(s_r[j]), 1),
            "compression_ratio": round(float(r_comp[j]), 2), "speed_kmh": round(float(v_prof[j]) * 3.6, 0),
            "s": float(s_r[j]),
        })
    return crests, comps


# ---------------------------------------------------------------------------------------------
# Obstáculos 3D (distancia por vértice en XZ, no por centroide)
# ---------------------------------------------------------------------------------------------
def _obstacle_class(name: str) -> Optional[str]:
    n = name.lower()
    if any(k in n for k in JUNCTION_KEYS):
        return "junction"
    if any(k in n for k in GATE_KEYS):
        return "gate"
    if any(k in n for k in ROCK_KEYS):
        return "rocks"
    if any(k in n for k in POST_KEYS):
        return "post"
    return None


def extract_obstacles(bmf_stage, pts_r, s_r, cum_d, cfg: PaceConfig) -> List[Dict[str, Any]]:
    rx, rz = pts_r[:, 0], pts_r[:, 2]
    out: List[Dict[str, Any]] = []
    R2 = cfg.obstacle_radius_m ** 2
    for m in bmf_stage.hierarchy_meshes:
        if m.get("is_timing_trigger", False):
            continue
        name = m["name"]
        if _excluded(name):
            continue
        mat = m["matrix"]
        px, py, pz = m["pos_extra"]
        vs, mats = [], set()
        for mod in m["models"]:
            for b in mod["batches"]:
                if b["mat_id"] < len(bmf_stage.materials):
                    mats.add(bmf_stage.materials[b["mat_id"]]["name"])
                for vx, vy, vz in b["verts"]:
                    wx = vx * mat[0] + vy * mat[4] + vz * mat[8] + px
                    wy = vx * mat[1] + vy * mat[5] + vz * mat[9] + py
                    wz = vx * mat[2] + vy * mat[6] + vz * mat[10] + pz
                    vs.append([wx, wy, -wz])
        if not vs:
            continue
        V = np.asarray(vs, dtype=np.float64)
        centroid_d3 = float(np.min(np.linalg.norm(pts_r - V.mean(axis=0), axis=1)))
        step = max(1, int(math.ceil(len(V) / 4000)))
        Vs = V[::step]
        idx_all = np.empty(len(Vs), dtype=int)
        d2_all = np.empty(len(Vs))
        for k in range(0, len(Vs), 400):
            ch = Vs[k:k + 400]
            d2 = (ch[:, 0, None] - rx[None, :]) ** 2 + (ch[:, 2, None] - rz[None, :]) ** 2
            ii = np.argmin(d2, axis=1)
            idx_all[k:k + 400] = ii
            d2_all[k:k + 400] = d2[np.arange(len(ch)), ii]
        within = d2_all <= R2
        if not within.any():
            continue
        interesting = _obstacle_class(name) is not None
        if not (interesting or centroid_d3 <= cfg.obstacle_radius_m):
            continue

        b = int(np.argmin(d2_all))
        j = int(idx_all[b])
        v = Vs[b]
        t = pts_r[min(j + 1, len(pts_r) - 1)] - pts_r[max(j - 1, 0)]
        t_xz = np.array([t[0], t[2]])
        tn = np.linalg.norm(t_xz)
        if tn > 1e-6:
            t_xz = t_xz / tn
        right_xz = np.array([-t_xz[1], t_xz[0]])
        lat = float(np.dot(np.array([v[0] - pts_r[j, 0], v[2] - pts_r[j, 2]]), right_xz))
        s_near = float(s_r[j])
        node = _nearest_node(cum_d, s_near)
        out.append({
            "node": node, "dist_m": round(float(cum_d[node]), 1), "name": name,
            "materials": sorted(mats),
            "dist_3d_m": round(float(np.linalg.norm(v - pts_r[j])), 2),
            "dist_xz_m": round(math.sqrt(float(d2_all[b])), 2),
            "lateral_m": round(lat, 2), "side": "right" if lat > 0 else "left",
            "span_m": [round(float(s_r[idx_all[within]].min()), 1), round(float(s_r[idx_all[within]].max()), 1)],
            "s_near": s_near,
        })
    return out


def _obstacle_candidate(o: Dict[str, Any], curve_dir: Optional[str]) -> Optional[Dict[str, Any]]:
    cls = _obstacle_class(o["name"])
    if cls is None:
        return None
    lat = o["lateral_m"]
    alat = abs(lat)
    lim = CURVE_LAT if curve_dir else STRAIGHT_LAT
    is_inside = bool(curve_dir) and ((curve_dir == "left" and lat < 0) or (curve_dir == "right" and lat > 0))
    s = o["s_near"]

    if cls == "junction":
        if alat > lim["junction"]:
            return None
        return {"cls": "junction", "rank": HAZARD_RANK["junction"], "s": s, "obs": o,
                "fields": {"junction": 1, "caution": 1},
                "text": f"Intersección/barrera en calzada ({o['name']} a {lat:+.1f}m): 'turn'."}
    if cls == "gate":
        if alat > lim["gate"]:
            return None
        return {"cls": "gate", "rank": HAZARD_RANK["gate"], "s": s, "obs": o,
                "fields": {"surface": 2, "hazard": 6, "turn": 3, "caution": 1},
                "text": f"Paso estrecho a través de portón ({o['name']} a {lat:+.1f}m): 'through gate, narrows'."}
    if cls == "rocks":
        if alat > lim["rocks"]:
            return None
        nocut = is_inside and alat <= CURVE_LAT["rocks_nocut"]
        side = (1 if is_inside else 2) if curve_dir else 0
        f = {"hazard": 4, "side": side}
        if nocut:
            f.update({"no_cut": 1, "caution": 1})
            txt = f"Rocas en el interior de la cuerda ({o['name']} a {lat:+.1f}m): 'rocks inside, dontcut'."
        else:
            txt = f"Rocas en margen ({o['name']} a {lat:+.1f}m {o['side']}): 'rocks {o['side']}'."
        return {"cls": "rocks_nocut" if nocut else "rocks",
                "rank": HAZARD_RANK["rocks_nocut" if nocut else "rocks"], "s": s, "obs": o,
                "fields": f, "text": txt}
    if cls == "post":
        if alat > lim["post"]:
            return None
        side = (1 if is_inside else 2) if curve_dir else 0
        return {"cls": "post", "rank": HAZARD_RANK["post"], "s": s, "obs": o,
                "fields": {"hazard": 5, "side": side},
                "text": f"Poste en borde de calzada ({o['name']} a {lat:+.1f}m): 'post'."}
    return None


def _vertical_candidate(vc: Dict[str, Any]) -> Dict[str, Any]:
    if vc["is_jump"]:
        return {"cls": "jump", "rank": HAZARD_RANK["jump"], "s": vc["s"], "vc": vc,
                "fields": {"surface": 1, "hazard": 1, "caution": 1},
                "text": (f"Ruptura de rasante en {vc['dist_m']}m ({vc['slope_in_pct']:+.1f}% -> {vc['slope_out_pct']:+.1f}%, "
                         f"ratio despegue {vc['airborne_ratio']:.2f} a ~{vc['speed_kmh']:.0f} km/h): 'over jump'.")}
    return {"cls": "crest", "rank": HAZARD_RANK["crest"], "s": vc["s"], "vc": vc,
            "fields": {"surface": 1, "hazard": 2},
            "text": (f"Cambio convexo de rasante en {vc['dist_m']}m ({vc['slope_in_pct']:+.1f}% -> {vc['slope_out_pct']:+.1f}%, "
                     f"ratio {vc['airborne_ratio']:.2f} a ~{vc['speed_kmh']:.0f} km/h): 'over crest'.")}


# ---------------------------------------------------------------------------------------------
# Palabras, duración y planificador de ritmo
# ---------------------------------------------------------------------------------------------
def _event_word(ev: Dict[str, Any], lvl: Optional[int] = None) -> int:
    lvl = ev["deg_level"] if lvl is None else lvl
    f = dict(ev["fields"])
    f["distance"] = ev.get("distance", 0)
    if lvl >= 1:                       # 1: fuera modificadores de longitud / evolución de radio
        f["length"] = 0
        if f.get("turn") in (1, 2):
            f["turn"] = 0
    if lvl >= 2:                       # 2: fuera prefijo de distancia
        f["distance"] = 0
    if lvl >= 3:                       # 3: fuera lado
        f["side"] = 0
    return pack_cmr2_word(**f)


# Palabras largas conocidas (estimación). Sustituir por duraciones medidas con --slot-durations.
DEFAULT_SLOT_DURATIONS = {28: 0.80, 46: 0.75, 27: 0.60, 7: 0.65, 6: 0.75, 30: 0.65, 29: 0.55, 35: 0.55}


def speech_duration(slots: List[int], cfg: PaceConfig) -> float:
    table = dict(DEFAULT_SLOT_DURATIONS)
    if cfg.slot_durations:
        table.update(cfg.slot_durations)
    return cfg.base_sec + sum(table.get(sl, cfg.slot_sec) for sl in slots)


def _event_dur(ev: Dict[str, Any], cfg: PaceConfig) -> float:
    return speech_duration(decode_cmr2_slots(_event_word(ev)), cfg)


def _lead(v: float, dur: float, cfg: PaceConfig) -> float:
    return float(min(cfg.lead_max_m, max(cfg.lead_min_m, v * cfg.speed_safety * (cfg.t_lead_s + dur))))


def _ceil_node_s(cum_d: np.ndarray, s: float) -> float:
    """Posición (m) del primer nodo >= s: el aviso nunca queda antes de lo planificado."""
    i = int(np.searchsorted(cum_d, s - 1e-9, side="left"))
    return float(cum_d[min(i, len(cum_d) - 1)])


def assign_distances(events: List[Dict[str, Any]], cfg: PaceConfig) -> None:
    curves = sorted([e for e in events if e["type"] == "curve"], key=lambda e: e["dist_m"])
    for e in events:
        e["distance"] = 0
    for i, c in enumerate(curves):
        if cfg.distance_mode == "prev":
            c["distance"] = _distance_class(max(0.0, c["dist_m"] - curves[i - 1]["end_m"])) if i > 0 else 0
        else:
            c["distance"] = (_distance_class(max(0.0, curves[i + 1]["dist_m"] - c["end_m"]))
                             if i < len(curves) - 1 else 0)


def schedule_events(events: List[Dict[str, Any]], cfg: PaceConfig, cum_d: np.ndarray):
    """
    Coloca cada llamada en el eje de distancia sin que se pisen.
    Orden de recursos si no cabe: retrasar (encadenar) -> acortar la de menor prioridad
    (4 niveles) -> descartar la de menor prioridad (nunca si es crítica).
    """
    events = sorted(events, key=lambda e: (e["dist_m"], -e["priority"]))
    kept: List[Dict[str, Any]] = []
    dropped: List[Dict[str, Any]] = []
    for ev in events:
        for k in ("trigger_m", "chained", "overlap", "late", "chained_after"):
            ev.pop(k, None)
        ev["deg_level"] = 0
        ev["dur_s"] = _event_dur(ev, cfg)
        v = ev["speed_ms"]
        ev["ideal_trigger_m"] = ev["dist_m"] - _lead(v, ev["dur_s"], cfg)

        while True:
            prev = kept[-1] if kept else None
            vs = v * cfg.speed_safety
            latest = ev["dist_m"] - vs * (cfg.min_lead_s + ev["dur_s"])
            if prev is None:
                t = _ceil_node_s(cum_d, max(ev["ideal_trigger_m"], 0.0))
                if t > latest and ev["deg_level"] < 3:      # primer evento muy cerca de la salida: acortar
                    ev["deg_level"] += 1
                    ev["dur_s"] = _event_dur(ev, cfg)
                    ev["ideal_trigger_m"] = ev["dist_m"] - _lead(v, ev["dur_s"], cfg)
                    continue
                ev["late"] = t > latest
                ev["trigger_m"], ev["chained"] = t, False
                kept.append(ev)
                break
            earliest = (prev["trigger_m"] + prev["speed_ms"] * cfg.speed_safety * prev["dur_s"]
                        + cfg.margin_s * vs)
            t = _ceil_node_s(cum_d, max(ev["ideal_trigger_m"], earliest))
            if t <= latest:
                ev["trigger_m"] = t
                ev["chained"] = earliest > ev["ideal_trigger_m"] + 1e-6
                if ev["chained"]:
                    ev["chained_after"] = prev["id"]
                kept.append(ev)
                break

            lo = ev if ev["priority"] <= prev["priority"] else prev
            if lo["deg_level"] < 3:
                lo["deg_level"] += 1
                lo["dur_s"] = _event_dur(lo, cfg)
                if lo is ev:
                    ev["ideal_trigger_m"] = ev["dist_m"] - _lead(v, ev["dur_s"], cfg)
                continue
            protected = cfg.protect_table_curves and lo["origin"] == "table"
            if lo["priority"] < PRIO_CRITICAL and not protected:
                if lo is ev:
                    ev["dropped"] = "solapa con una llamada de mayor/igual prioridad y no cabe ni acortada"
                    dropped.append(ev)
                    break
                kept.pop()
                prev["dropped"] = "desplazada por un evento de mayor prioridad"
                dropped.append(prev)
                continue
            # ambos críticos (o protegida): se permite solape, pero se marca para revisión
            ev["trigger_m"] = _ceil_node_s(cum_d, max(min(latest, t), prev["trigger_m"] + 1.0))
            ev["overlap"] = True
            ev["chained"] = False
            kept.append(ev)
            break
    return kept, dropped


# ---------------------------------------------------------------------------------------------
# Construcción de eventos
# ---------------------------------------------------------------------------------------------
def _base_fields(kind=0, direction=0, length=0, turn=0) -> Dict[str, int]:
    return dict(kind=kind, direction=direction, length=length, turn=turn, surface=0, hazard=0,
                caution=0, junction=0, no_cut=0, ending=0, side=0)


def _merge_fields(f: Dict[str, int], cand: Dict[str, Any]) -> None:
    for k, v in cand["fields"].items():
        f[k] = max(f[k], v) if k == "caution" else v


def _next_curve_after(curves: List[Dict[str, Any]], s: float, within_m: float, min_kind: int):
    for c in curves:
        if c["dist_m"] >= s - 5.0 and c["dist_m"] - s <= within_m:
            return c if c["fields"]["kind"] >= min_kind else None
        if c["dist_m"] - s > within_m:
            break
    return None


def _speed_at(s_r, v_prof, s: float, cfg: PaceConfig) -> float:
    return max(8.0, float(np.interp(max(0.0, s - 60.0), s_r, v_prof)))


def _hazard_name(f: Dict[str, int]) -> str:
    if f["hazard"]:
        return HAZARD_NAMES.get(f["hazard"], str(f["hazard"]))
    return "junction" if f["junction"] else "none"


def _curve_priority(kind: int, caution: int, hazard_rank: int) -> int:
    base = KIND_BASE_PRIORITY.get(kind, 40) + (10 if caution == 1 else 20 if caution == 2 else 0)
    return min(100, max(base, hazard_rank))


def build_curve_events(intervals, cum_d, s_r, theta, v_free, v_prof, y_r, cfg: PaceConfig):
    events: List[Dict[str, Any]] = []
    n_pts = len(cum_d)
    for iv in intervals:
        s0, s1, dir_str = iv["s0"], iv["s1"], iv["dir"]
        radius, ang = iv["radius"], iv["angle"]
        kind, kind_str = classify_kind(radius, ang)
        if iv["origin"] == "auto" and kind == 1 and ang < cfg.flat_min_angle_deg:
            continue
        s_node = _nearest_node(cum_d, s0)
        e_node = max(s_node + 1, min(_nearest_node(cum_d, s1), n_pts - 1))
        c_len = s1 - s0

        f = _base_fields(kind=kind, direction=1 if dir_str == "left" else 2)
        ev_txt = [f"Medida 3D: R={radius:.1f}m, ángulo={ang:.1f} deg, longitud={c_len:.1f}m "
                  f"({'tabla calibrada' if iv['origin'] == 'table' else 'detección automática'})."]
        if c_len >= 135.0:
            f["length"] = 2
            ev_txt.append(f"Longitud {c_len:.1f}m >= 135m: 'verylong'.")
        elif c_len >= 80.0:
            f["length"] = 1
            ev_txt.append(f"Longitud {c_len:.1f}m >= 80m: 'long'.")

        r_in, r_out = half_radii(s0, s1, s_r, theta)
        if r_out < 0.65 * r_in and (r_in - r_out) > 25.0:
            f["turn"] = 1
            ev_txt.append(f"Radio decreciente (R_in={r_in:.0f}m -> R_out={r_out:.0f}m): 'tightens'.")
        elif r_out > 1.5 * r_in and (r_out - r_in) > 25.0:
            f["turn"] = 2
            ev_txt.append(f"Radio creciente (R_in={r_in:.0f}m -> R_out={r_out:.0f}m): 'opens'.")

        i0, i1 = np.searchsorted(s_r, s0), np.searchsorted(s_r, s1) + 1
        v_min = float(np.min(v_prof[i0:max(i1, i0 + 1)]))
        demand = float(np.interp(s0, s_r, v_free)) - v_min
        v_app = _speed_at(s_r, v_prof, s0, cfg)

        def grade_pct(a: float, b: float) -> float:
            return (float(np.interp(b, s_r, y_r)) - float(np.interp(a, s_r, y_r))) / max(b - a, 1.0) * 100.0
        g_app = grade_pct(max(0.0, s0 - cfg.sev_approach_m), s0)
        g_cur = grade_pct(s0, s1)

        events.append({
            "id": None, "type": "curve", "dist_m": s0, "end_m": s1, "node": s_node, "end_node": e_node,
            "fields": f, "kind_str": kind_str, "direction": dir_str, "radius": radius, "angle": ang,
            "length": c_len, "origin": iv["origin"], "speed_ms": v_app, "demand": demand,
            "v_min": v_min, "evidence": ev_txt, "hazard_cands": [], "priority": 0,
            "grade_approach_pct": g_app, "grade_curve_pct": g_cur,
            "down_grade_pct": max(-g_app, -g_cur, 0.0),
        })
    return events


def attach_hazards(curve_events, all_cands, cfg: PaceConfig):
    """Asigna cada candidato a la curva cuya zona lo contiene; devuelve los que quedan en recta."""
    zones = [(c["dist_m"] - cfg.curve_zone_before_m, c["end_m"] + cfg.curve_zone_after_m, c) for c in curve_events]
    straight = []
    for cand in all_cands:
        best, best_d = None, None
        for lo, hi, c in zones:
            if lo <= cand["s"] <= hi:
                d = 0.0 if c["dist_m"] <= cand["s"] <= c["end_m"] else min(abs(cand["s"] - c["dist_m"]), abs(cand["s"] - c["end_m"]))
                if best is None or d < best_d:
                    best, best_d = c, d
        if best is None:
            straight.append(cand)
        else:
            best["hazard_cands"].append(cand)
    return straight


def severity_adjustment(ev: Dict[str, Any], cfg: PaceConfig) -> Tuple[int, List[str]]:
    """
    Una curva con pendiente o rasante en la entrada es más peligrosa de lo que dice su radio.
    Se suman puntos (descenso, crest/salto en la entrada) y cada punto entero sube un escalón
    de severidad (hasta 'one'). Efectos suaves por sí solos (<1 punto) no suben el escalón.
    """
    kind = ev["fields"]["kind"]
    pts, why = 0.0, []
    d = ev["down_grade_pct"]
    if d >= cfg.sev_down_extreme_pct:
        pts += 2.0
        why.append(f"descenso fuerte ({d:.1f}%) en entrada/curva")
    elif d >= cfg.sev_down_high_pct:
        pts += 1.0
        why.append(f"descenso ({d:.1f}%) en entrada/curva")
    elif d >= cfg.sev_down_mid_pct:
        pts += 0.5
        why.append(f"descenso moderado ({d:.1f}%)")
    if kind >= 3:
        dem = ev["demand"]
        if dem >= cfg.sev_demand_high_ms:
            pts += 1.0
            why.append(f"frenada muy exigente (~{dem * 3.6:.0f} km/h a perder)")
        elif dem >= cfg.sev_demand_mid_ms:
            pts += 0.5
            why.append(f"frenada exigente (~{dem * 3.6:.0f} km/h a perder)")
    lo, hi = ev["dist_m"] - 25.0, ev["dist_m"] + 0.6 * ev["length"]
    vcs = [c for c in ev["hazard_cands"] if c["cls"] in ("jump", "crest") and lo <= c["s"] <= hi]
    if vcs:
        vc = max(vcs, key=lambda c: c["vc"]["airborne_ratio"])["vc"]
        if vc["is_jump"] or vc["airborne_ratio"] >= 0.8:
            pts += 1.0
            why.append(f"salto/crest fuerte en la entrada (ratio {vc['airborne_ratio']:.2f})")
        else:
            pts += 0.5
            why.append(f"crest en la entrada (ratio {vc['airborne_ratio']:.2f})")
    bonus = int(math.floor(pts + 1e-9))
    if kind >= 7:
        bonus = 0                      # las horquillas no suben de escalón (sí suben caution, ver finalize)
    elif kind == 1:
        bonus = min(bonus, 1)          # una curva casi plana solo sube un escalón
    return min(bonus, cfg.sev_max_bonus), (why if pts > 0 else [])


def finalize_curve(ev, curves_sorted, cfg: PaceConfig):
    f = ev["fields"]
    cands = ev["hazard_cands"]
    # --- severidad ajustada por pendiente/rasante (antes de las reglas de caution) ---
    ev["base_kind"] = f["kind"]
    ev["base_kind_str"] = ev["kind_str"]
    bonus, why = severity_adjustment(ev, cfg)
    ev["severity_bonus"] = bonus
    ev["severity_reasons"] = why
    if bonus > 0:
        f["kind"] = min(f["kind"] + bonus, 6)
        ev["kind_str"] = KIND_NAMES[f["kind"]]
        ev["evidence"].append(
            f"Severidad ajustada {ev['base_kind_str']} -> {ev['kind_str']} por {', '.join(why)}.")
    elif why:
        ev["evidence"].append(f"Pendiente/rasante a vigilar ({', '.join(why)}), sin cambio de escalón.")
    junction = [c for c in cands if c["cls"] == "junction"]
    haz = [c for c in cands if c["cls"] != "junction"]
    primary = max(haz, key=lambda c: (c["rank"], -abs(c["s"] - ev["dist_m"])), default=None)
    jx = min(junction, key=lambda c: abs(c["s"] - ev["dist_m"]), default=None)
    rank = 0
    if primary:
        _merge_fields(f, primary)
        ev["evidence"].append(primary["text"])
        rank = max(rank, primary["rank"])
        for c in haz:
            if c is not primary:
                ev["evidence"].append(f"[no hablado: la palabra admite un solo peligro] {c['text']}")
    if jx:
        _merge_fields(f, jx)
        ev["evidence"].append(jx["text"])
        rank = max(rank, jx["rank"])

    kind = f["kind"]
    # escalada de caution
    if primary and primary["cls"] == "jump":
        vc = primary["vc"]
        f["caution"] = 2 if (vc["airborne_ratio"] >= 1.5 or kind >= 4) else max(f["caution"], 1)
        ev["evidence"].append(f"Salto en zona de curva (kind={kind}): caution={f['caution']}.")
    if primary and primary["cls"] == "rocks_nocut" and kind >= 5:
        f["caution"] = 2
        ev["evidence"].append("Rocas interiores en curva cerrada: caution=2.")
    if kind >= 5 and ev["demand"] >= 18.0:
        f["caution"] = max(f["caution"], 1)
        ev["evidence"].append(f"Frenada exigente (~{ev['demand'] * 3.6:.0f} km/h a perder): care.")
    if kind >= 7 and ev["demand"] >= 25.0:
        f["caution"] = 2
        ev["evidence"].append(f"Horquilla tras velocidad alta (~{ev['demand'] * 3.6:.0f} km/h a perder): caution.")
    if f["turn"] == 1 and kind >= 4:
        f["caution"] = max(f["caution"], 1)
    if ev["severity_bonus"] >= 1 and kind >= 4:
        f["caution"] = max(f["caution"], 1)
    if ev["severity_bonus"] >= 2 and kind >= 5:
        f["caution"] = 2
    if ev["base_kind"] >= 7 and ev["down_grade_pct"] >= cfg.sev_down_high_pct:
        f["caution"] = max(f["caution"], 2)
        ev["evidence"].append(f"Horquilla en descenso ({ev['down_grade_pct']:.1f}%): caution.")

    f["surface"] = 1 if f["hazard"] in (1, 2, 14) else (2 if f["hazard"] == 6 else 0)
    ev["priority"] = _curve_priority(kind, f["caution"], rank)
    ev["hazard_name"] = _hazard_name(f)

    score = 2
    if ev["angle"] < 20.0:
        score -= 1
    if ev["origin"] == "auto" and ev["length"] < 12.0:
        score -= 1
    ev["confidence"] = "high" if score >= 2 else ("medium" if score == 1 else "low")


def build_standalone_events(straight_cands, curve_events, cfg: PaceConfig, cum_d, s_r, v_prof, prefix):
    cands = []
    for c in straight_cands:
        if c["cls"] == "crest" and c["vc"]["airborne_ratio"] < cfg.straight_crest_ratio:
            continue
        cands.append(c)
    cands.sort(key=lambda c: c["s"])
    groups: List[List[Dict[str, Any]]] = []
    for c in cands:
        if groups and c["s"] - groups[-1][-1]["s"] <= cfg.straight_group_m:
            groups[-1].append(c)
        else:
            groups.append([c])

    curves_sorted = sorted(curve_events, key=lambda e: e["dist_m"])
    events = []
    for gi, g in enumerate(groups):
        haz = [c for c in g if c["cls"] != "junction"]
        junction = [c for c in g if c["cls"] == "junction"]
        primary = max(haz, key=lambda c: c["rank"], default=None)
        jx = junction[0] if junction else None
        f = _base_fields()
        evidence = []
        rank = 0
        if primary:
            _merge_fields(f, primary)
            evidence.append(primary["text"])
            rank = max(rank, primary["rank"])
            for c in haz:
                if c is not primary:
                    evidence.append(f"[no hablado, agrupado] {c['text']}")
        if jx:
            _merge_fields(f, jx)
            evidence.append(jx["text"])
            rank = max(rank, jx["rank"])
        s = (primary or jx)["s"]
        if primary and primary["cls"] == "jump":
            nxt = _next_curve_after(curves_sorted, s, 100.0, 4)
            if primary["vc"]["airborne_ratio"] >= 1.5 or nxt is not None:
                f["caution"] = 2
                evidence.append("Salto en recta con curva cerrada inmediata o despegue muy marcado: caution=2.")
        f["surface"] = 1 if f["hazard"] in (1, 2, 14) else (2 if f["hazard"] == 6 else 0)
        f["turn"] = 3 if f["hazard"] == 6 else 0
        node = _nearest_node(cum_d, s)
        conf = "medium"
        if primary and primary["cls"] == "jump" and primary["vc"]["airborne_ratio"] >= 1.3:
            conf = "high"
        events.append({
            "id": f"{prefix}_HAZ_{gi:02d}", "type": "hazard", "dist_m": s, "end_m": s, "node": node, "end_node": node,
            "fields": f, "kind_str": "none", "direction": "none", "radius": 0.0, "angle": 0.0, "length": 0.0,
            "origin": "auto", "speed_ms": _speed_at(s_r, v_prof, s, cfg), "demand": 0.0, "v_min": 0.0,
            "evidence": evidence, "priority": min(100, rank + (10 if f["caution"] == 2 else 0)),
            "hazard_name": _hazard_name(f),
            "confidence": conf, "hazard_cands": [],
        })
    return events


# ---------------------------------------------------------------------------------------------
# Pipeline principal
# ---------------------------------------------------------------------------------------------
def analyze_and_build_pacenotes(
    route_points: List[List[float]],
    bmf_stage: Any,
    output_dir: Path,
    country_name: str = "russia",
    stage_name: str = "stage1",
    provenance_json_path: Optional[Path] = None,
    cfg: Optional[PaceConfig] = None,
) -> Dict[str, Any]:
    cfg = cfg or PaceConfig()
    output_dir.mkdir(parents=True, exist_ok=True)
    pts = np.array(route_points, dtype=np.float64)
    n_pts = len(pts)
    if n_pts < 4:
        raise ValueError("La ruta necesita al menos 4 puntos")

    seg_lens = np.linalg.norm(pts[1:] - pts[:-1], axis=1)
    cum_d = np.concatenate([[0.0], np.cumsum(seg_lens)])

    # 1) Dominio distancia, curvatura y velocidad esperada
    s_r, pts_r = _resample(pts, cum_d, cfg.resample_m)
    theta, kappa, ds = compute_heading_curvature(s_r, pts_r, cfg)
    vsmooth = cfg.vslope_smooth_m or max(9.0, 2.5 * float(np.median(seg_lens)))
    grade = _smooth_edge(np.gradient(pts_r[:, 1], ds), max(1, int(round(vsmooth / ds))))
    v_prof, v_free = build_speed_profile(kappa, ds, cfg, grade)

    # 2) Vertical (física) y obstáculos (vértices)
    crests, compressions = detect_vertical_features(s_r, pts_r[:, 1], v_prof, cum_d, cfg, vsmooth)
    obstacles = extract_obstacles(bmf_stage, pts_r, s_r, cum_d, cfg)

    # 3) Curvas
    use_table = (cfg.use_calibrated_table and country_name.lower() == "russia"
                 and stage_name.lower() == "stage1" and n_pts >= 466)
    intervals = calibrated_intervals(cum_d) if use_table else detect_curve_runs(s_r, kappa, ds, cfg)

    stage_digits = "".join(ch for ch in stage_name if ch.isdigit()) or "1"
    prefix = f"{country_name[:2].upper()}{stage_digits}"

    curve_events = build_curve_events(intervals, cum_d, s_r, theta, v_free, v_prof, pts_r[:, 1], cfg)
    curve_events.sort(key=lambda e: e["dist_m"])
    for i, e in enumerate(curve_events):
        e["id"] = f"{prefix}_CURVE_{i:02d}"

    # 4) Candidatos de peligro: se asignan a su curva o quedan en recta
    all_cands: List[Dict[str, Any]] = [_vertical_candidate(vc) for vc in crests]
    # una curva decide inside/outside según su sentido; los de recta usan límites de recta
    zones = [(c["dist_m"] - cfg.curve_zone_before_m, c["end_m"] + cfg.curve_zone_after_m, c) for c in curve_events]
    for o in obstacles:
        owner = next((c for lo, hi, c in zones if lo <= o["s_near"] <= hi), None)
        cand = _obstacle_candidate(o, owner["direction"] if owner else None)
        if cand:
            all_cands.append(cand)
    straight = attach_hazards(curve_events, all_cands, cfg)

    for e in curve_events:
        finalize_curve(e, curve_events, cfg)

    events = list(curve_events)
    standalone: List[Dict[str, Any]] = []
    if cfg.emit_standalone_hazards:
        standalone = build_standalone_events(straight, curve_events, cfg, cum_d, s_r, v_prof, prefix)
        events.extend(standalone)

    # 5) Ritmo: distancias + planificador (itera si se descarta una curva)
    active = list(events)
    dropped_all: List[Dict[str, Any]] = []
    kept: List[Dict[str, Any]] = []
    for _ in range(3):
        assign_distances(active, cfg)
        kept, dropped = schedule_events(active, cfg, cum_d)
        dropped_all.extend(dropped)
        if not any(d["type"] == "curve" for d in dropped):
            break
        active = kept

    # 6) Nodos de aviso estrictamente crecientes
    entries_auth, entries_run = [], []
    prev_node = -1
    for idx, ev in enumerate(kept):
        node = _floor_node(cum_d, max(ev["trigger_m"], 0.0))
        node = min(node, ev["node"])
        late_gate = False
        if node <= prev_node:
            node = prev_node + 1
        if node >= ev["node"] and ev["type"] == "curve":
            late_gate = True
        node = min(node, n_pts - 1)
        prev_node = node

        word = _event_word(ev)
        f = ev["fields"]
        lead_actual = ev["dist_m"] - float(cum_d[node])
        status_flags = []
        if ev["deg_level"] > 0:
            status_flags.append(f"acortada(nivel {ev['deg_level']})")
        if ev.get("overlap"):
            status_flags.append("solape entre críticos")
        if ev.get("late") or late_gate:
            status_flags.append("aviso tardío")
        conf = ev.get("confidence", "medium")
        if ev["origin"] == "table":
            conf, review = "high", "calibrated_table"
        else:
            review = "needs_review" if (status_flags or conf == "low") else "auto_ok"

        ev_lines = list(ev["evidence"])
        ev_lines.append(
            f"Aviso en nodo {node} a {cum_d[node]:.1f}m ({lead_actual:.0f}m antes; v≈{ev['speed_ms'] * 3.6:.0f} km/h, "
            f"frase≈{ev['dur_s']:.1f}s, prioridad {ev['priority']})."
        )
        if ev.get("chained"):
            ev_lines.append(f"Encadenada tras {ev.get('chained_after')} (retrasada para no pisar la llamada previa).")
        for s_ in status_flags:
            ev_lines.append(f"Ritmo: {s_}.")

        entry = {
            "curve_id": ev["id"],
            "start_node": int(ev["node"]),
            "end_node": int(ev["end_node"]),
            "advisory_gate_node": int(node),
            "route_distance_m": round(ev["dist_m"], 1),
            "length_m": round(ev["length"], 1),
            "total_angle_deg": round(ev["angle"], 1),
            "direction": ev["direction"],
            "estimated_radius_m": round(ev["radius"], 1),
            "cmr2_kind": ev["kind_str"] if ev["type"] == "curve" else "none",
            "caution": "care" if f["caution"] == 1 else ("caution" if f["caution"] == 2 else "none"),
            "call_word_hex": f"0x{word:08x}",
            "call_index": idx,
            "confidence": conf,
            "review_status": review,
            "evidence": ev_lines,
            # extensiones v2
            "entry_type": ev["type"],
            "hazard": ev.get("hazard_name", "none"),
            "priority": int(ev["priority"]),
            "advisory_distance_m": round(lead_actual, 1),
            "approach_speed_kmh": round(ev["speed_ms"] * 3.6, 0),
            "speech_duration_s": round(ev["dur_s"], 2),
            "chained_after": ev.get("chained_after"),
            "degrade_level": int(ev["deg_level"]),
            "base_kind": ev.get("base_kind_str", ev["kind_str"]) if ev["type"] == "curve" else "none",
            "severity_bonus": int(ev.get("severity_bonus", 0)),
            "down_grade_pct": round(float(ev.get("down_grade_pct", 0.0)), 1),
        }
        auth = dict(entry)
        auth["speech_slots"] = decode_cmr2_slots(word)
        entries_auth.append(auth)
        if cfg.runtime_extra_fields:
            entries_run.append(entry)
        else:
            entries_run.append({k: entry[k] for k in RUNTIME_ORIGINAL_KEYS})

    n_curves = sum(1 for e in kept if e["type"] == "curve")

    # Informe de ritmo (modelo conservador: velocidad x speed_safety, duración por slot)
    gaps = []
    for a_, b_ in zip(entries_auth, entries_auth[1:]):
        va = max(8.0, a_["approach_speed_kmh"] / 3.6) * cfg.speed_safety
        sa, sb = float(cum_d[a_["advisory_gate_node"]]), float(cum_d[b_["advisory_gate_node"]])
        gaps.append((sb - sa) / va - a_["speech_duration_s"])
    rhythm_report = {
        "model": f"v x {cfg.speed_safety}, duración por slot, margen {cfg.margin_s}s",
        "min_silence_s": round(min(gaps), 2) if gaps else None,
        "calls_overlapping": int(sum(g < 0 for g in gaps)),
        "calls_under_margin": int(sum(0 <= g < cfg.margin_s * 0.9 for g in gaps)),
    }
    sev_up = sum(1 for e in kept if e.get("severity_bonus", 0) > 0)

    # 7) Documentos de salida
    candidates_doc = {
        "stage": f"{country_name}-{stage_name}",
        "total_curves": n_curves,
        "vertical_crests_count": len(crests),
        "near_obstacles_count": len(obstacles),
        "vertical_crests": [{k: v for k, v in c.items() if k != "s"} for c in crests],
        "vertical_compressions": [{k: v for k, v in c.items() if k != "s"} for c in compressions],
        "near_obstacles": [{k: v for k, v in o.items() if k != "s_near"} for o in obstacles],
        "detected_curve_intervals": [{k: v for k, v in iv.items()} for iv in intervals],
        "standalone_hazards": [
            {"id": e["id"], "dist_m": round(e["dist_m"], 1), "hazard": e["hazard_name"], "priority": e["priority"]}
            for e in standalone
        ],
        "note": ("Las compresiones solo se cantan si cfg.hazard_compression tiene un id de hazard CMR2."
                 if cfg.hazard_compression is None else "Compresiones mapeadas a hazard CMR2."),
    }
    (output_dir / f"{country_name}_{stage_name}_pacenotes_candidates.json").write_text(
        json.dumps(candidates_doc, ensure_ascii=False, indent=2, default=_json_default) + "\n", encoding="utf-8")

    authoring_doc = {
        "stage": f"{country_name}-{stage_name}",
        "author": "Antigravity Agent (v2)",
        "methodology": ("Curvatura 3D en dominio distancia + perfil de velocidad + física vertical (v²κv/g) "
                        "+ obstáculos por vértice + planificador de ritmo por tiempo de habla"),
        "config": asdict(cfg),
        "total_curves_classified": n_curves,
        "total_calls": len(kept),
        "chained_calls": sum(1 for e in kept if e.get("chained")),
        "degraded_calls": sum(1 for e in kept if e["deg_level"] > 0),
        "rhythm_report": rhythm_report,
        "curves_with_raised_severity": sev_up,
        "dropped_events": [{"id": d["id"], "type": d["type"], "route_distance_m": round(d["dist_m"], 1),
                            "priority": d["priority"], "reason": d.get("dropped")} for d in dropped_all],
        "curves": entries_auth,
    }
    (output_dir / f"{country_name}_{stage_name}_pacenotes_authoring.json").write_text(
        json.dumps(authoring_doc, ensure_ascii=False, indent=2, default=_json_default) + "\n", encoding="utf-8")

    runtime_doc = {
        "stage": f"{country_name}-{stage_name}",
        "author": "Antigravity Agent (v2)",
        "methodology": "3D curvature in distance domain, speed-aware call scheduling, CMR2 vocabulary mapping",
        "total_curves_classified": n_curves,
        "total_calls": len(kept),
        "curves": entries_run,
    }
    runtime_path = output_dir / f"{country_name}_{stage_name}_pacenotes.json"
    runtime_path.write_text(json.dumps(runtime_doc, ensure_ascii=False, indent=2, default=_json_default) + "\n", encoding="utf-8")

    print(f"[PacenoteAnalyzer v2] {n_curves} curvas + {len(kept) - n_curves} peligros en recta = {len(kept)} llamadas "
          f"({authoring_doc['chained_calls']} encadenadas, {authoring_doc['degraded_calls']} acortadas, "
          f"{len(dropped_all)} descartadas; {sev_up} curvas con severidad subida; "
          f"silencio mínimo {rhythm_report['min_silence_s']} s, {rhythm_report['calls_overlapping']} solapes) -> {output_dir}")
    return runtime_doc


if __name__ == "__main__":
    import argparse
    import bmf_parser

    parser = argparse.ArgumentParser(description="Analizador de pacenotes CMR2 v2")
    parser.add_argument("--route-json", type=Path, required=True)
    parser.add_argument("--bmf", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--country", type=str, default="russia")
    parser.add_argument("--stage", type=str, default="stage1")
    parser.add_argument("--no-calibrated", action="store_true", help="ignora la tabla calibrada de russia_stage1")
    parser.add_argument("--protect-table", action="store_true", help="no descarta curvas de la tabla calibrada")
    parser.add_argument("--no-standalone", action="store_true", help="no emite peligros en recta como entradas propias")
    parser.add_argument("--minimal-runtime", action="store_true", help="runtime solo con las claves de v1")
    parser.add_argument("--slot-durations", type=Path, help="JSON {slot_id: segundos} con duraciones medidas de los audios")
    parser.add_argument("--speed-safety", type=float, default=None)
    parser.add_argument("--margin", type=float, default=None, help="silencio mínimo entre llamadas (s)")
    parser.add_argument("--distance-mode", choices=["next", "prev"], default="next")
    args = parser.parse_args()

    conf = PaceConfig(
        use_calibrated_table=not args.no_calibrated,
        protect_table_curves=args.protect_table,
        emit_standalone_hazards=not args.no_standalone,
        runtime_extra_fields=not args.minimal_runtime,
        distance_mode=args.distance_mode,
    )
    if args.slot_durations:
        conf.slot_durations = {int(k): float(v) for k, v in json.loads(args.slot_durations.read_text()).items()}
    if args.speed_safety:
        conf.speed_safety = args.speed_safety
    if args.margin:
        conf.margin_s = args.margin
    with open(args.route_json, "r", encoding="utf-8") as f:
        rdata = json.load(f)
    stage_bmf = bmf_parser.parse_bmf(args.bmf)
    analyze_and_build_pacenotes(
        rdata["points"], stage_bmf, args.output_dir,
        country_name=args.country, stage_name=args.stage, cfg=conf,
    )
