"""Generador de pacenotes CMR2 v3: geometría reconstruida + semántica + física + scheduler temporal.

Sustituye a pacenote_analyzer_v2.py. Detección 100% geométrica (sin tablas
manuales): curvas multi-ápice, obstáculos multi-instancia (TRACK+HIERARCHY),
3 escenarios de velocidad, planificador en dominio t(s) y exportador
multi-palabra. Reutiliza pack_cmr2_word/decode del v2 y la convención del
juego (direction 1=left/2=right, rocks=hazard 4, ditch=hazard 7, etc.).
"""
import json
import math
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
from scipy.signal import find_peaks
from scipy.spatial import cKDTree

CURRENT_DIR = Path(__file__).resolve().parent
if str(CURRENT_DIR) not in sys.path:
    sys.path.insert(0, str(CURRENT_DIR))
TOOLS_DIR = CURRENT_DIR.parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from pacenote_analyzer_v2 import pack_cmr2_word, decode_cmr2_slots, speech_duration  # noqa: E402
import bmf_parser  # noqa: E402
from road_mesh_extractor import extract_road_mesh, classify_material  # noqa: E402
from road_cross_sections import CrossSections, STEP_M  # noqa: E402
from road_corridor_solver import CorridorSolver  # noqa: E402
from road_centerline import build_centerline  # noqa: E402
from road_geometry_analyzer import analyze as analyze_geometry  # noqa: E402
from road_validator import build_road_geometry  # noqa: E402

G = 9.81

# --- Severidad geométrica 1..8 (documentado: umbrales propios calibrados) ---
# R_geom >= : six 160 / five 110 / four 75 / three 50 / two 32 / one 20 /
#              openhairpin 12 / hairpin < 12.
SEVERITY_BOUNDS = [160.0, 110.0, 75.0, 50.0, 32.0, 20.0, 12.0]
SEVERITY_NAMES = {1: "six", 2: "five", 3: "four", 4: "three",
                  5: "two", 6: "one", 7: "openhairpin", 8: "hairpin"}
KIND_BASE_PRIORITY = {1: 30, 2: 40, 3: 50, 4: 60, 5: 70, 6: 75, 7: 80, 8: 85}


def severity_for_radius(r_geom: float) -> int:
    for i, bound in enumerate(SEVERITY_BOUNDS):
        if r_geom >= bound:
            return i + 1
    return 8


@dataclass
class V3Config:
    # --- segmentación de curvas (estabilizada contra fragmentación) ---
    k_enter: float = 1.0 / 260.0          # Evita entrar en curva por ondulaciones leves en recta
    k_exit: float = 1.0 / 400.0           # Histéresis más amplia para no cortar curvas a la mitad
    bridge_gap_m: float = 24.0            # Puentea caídas breves de curvatura dentro de una misma curva
    trim_frac: float = 0.18               # Menos agresivo (antes 0.30) para no encoger la curva al ápice
    trim_floor: float = 1.0 / 320.0
    min_angle_center_deg: float = 10.0    # Filtra micro-desviaciones (<10°)
    min_angle_opt_deg: float = 6.5
    min_r_opt_m: float = 210.0
    peak_min_dist_m: float = 45.0         # Antes 18.0m: evita partir una curva por ondulaciones de malla
    peak_prominence: float = 1.0 / 90.0   # Antes 1/180: solo divide si hay dos ápices fuertes y distintos
    split_valley_frac: float = 0.25       # Antes 0.45: exige que casi se enderece (25%) entre ápices
    split_valley_len_m: float = 30.0      # Antes 14.0m: exige una recta real de 30m para dividir
    tighten_ratio: float = 0.68
    open_ratio: float = 1.48
    into_gap_m: float = 30.0
    # --- severidad efectiva ---
    downhill_p85_pct: float = -9.0
    downhill_window_m: float = 35.0
    bad_camber_deg: float = -4.5
    decel_demand_ms: float = 12.5
    decel_window_m: float = 60.0
    # --- obstáculos (estrictos junto al borde real) ---
    lateral_max_m: float = 3.2            # Antes 6.5m: descarta bosque y postes lejanos
    post_max_edge_m: float = 1.8          # Postes solo si están pegados a la calzada (<= 1.8m del borde)
    dy_max_m: float = 3.5
    cluster_eps_rock_m: float = 12.0
    cluster_eps_gate_m: float = 18.0
    curve_link_before_m: float = 15.0
    curve_link_after_m: float = 8.0
    dont_cut_edge_m: float = 1.2          # Antes 2.5m: solo 'dont_cut' si realmente invade el interior
    # --- velocidad (3 escenarios) ---
    grip_factors: Tuple[float, float, float] = (0.85, 1.00, 1.15)
    vmax: Tuple[float, float, float] = (44.0, 50.0, 56.0)
    acc_ms2: float = 3.5
    brk_ms2: float = 6.0
    v_start_ms: float = 12.0
    # --- crest/jump ---
    jump_gamma: float = 0.75
    crest_gamma: float = 0.38             # Antes 0.28: filtra baches menores de tierra
    crest_min_dist_m: float = 45.0        # Distancia mínima entre rasantes (NMS)
    crest_min_delta_grade_pct: float = 4.5  # Exige cambio real de pendiente (como en v1)
    jump_lookahead_m: float = 25.0
    # --- planificador temporal ---
    t_lead_base_s: float = 1.2
    t_lead_per_sev_s: float = 0.3
    t_gap_s: float = 0.8
    shift_early_max_s: float = 1.8
    lead_min_m: float = 40.0
    lead_max_m: float = 260.0
    long_m: float = 80.0
    verylong_m: float = 135.0
    link_into_m: float = 22.0
    link_and_m: float = 38.0
    numeric_dist_m: float = 30.0
    # --- anti-redundancia de voz (cooldowns de frase) ---
    caution_cooldown_m: float = 85.0
    caution_cooldown_s: float = 4.5
    hazard_repeat_cooldown_m: float = 65.0


def _unwrap_deg(a: np.ndarray) -> np.ndarray:
    return np.degrees(np.unwrap(np.radians(a)))


def detect_curves(geo: Dict[str, Any], cfg: V3Config) -> List[Dict[str, Any]]:
    """Segmenta curvas por ápices con core trimming y validación de trazada."""
    secs = geo["sections"]
    n = len(secs)
    s = np.array([x["s_m"] for x in secs])
    kc = np.array([x["kappa_center"] for x in secs])
    ko = np.array([x["kappa_opt"] for x in secs])
    hd = np.array([x["heading_rad"] for x in secs])
    opt = np.array([x["opt_line"] for x in secs])
    tho = np.degrees(np.unwrap(np.arctan2(np.diff(opt[:, 0], prepend=opt[0, 0]),
                                           -np.diff(opt[:, 2], prepend=opt[0, 2]))))
    curves: List[Dict[str, Any]] = []
    # Regiones del mismo signo sobre el umbral de entrada.
    active = np.abs(kc) >= cfg.k_enter
    i = 0
    regions = []
    while i < n:
        if not active[i]:
            i += 1
            continue
        j = i
        while j + 1 < n and (active[j + 1] or abs(kc[j + 1]) > cfg.k_exit) \
                and np.sign(kc[j + 1]) == np.sign(kc[i]):
            j += 1
        regions.append((i, j))
        i = j + 1
    # Fusionar regiones del mismo sentido separadas por micro-ondulaciones (< bridge_gap_m)
    merged_regions: List[Tuple[int, int]] = []
    max_gap_steps = int(round(cfg.bridge_gap_m / STEP_M))
    for r0, r1 in regions:
        sgn = np.sign(kc[np.argmax(np.abs(kc[r0:r1 + 1])) + r0])
        if merged_regions:
            p0, p1 = merged_regions[-1]
            prev_sgn = np.sign(kc[np.argmax(np.abs(kc[p0:p1 + 1])) + p0])
            # Si tienen el mismo sentido y en el hueco no hay un giro opuesto fuerte
            gap_slice = kc[p1 + 1:r0]
            opposite_peak = float(np.max(np.abs(gap_slice[np.sign(gap_slice) != sgn]), initial=0.0))
            if sgn == prev_sgn and (r0 - p1) <= max_gap_steps and opposite_peak < cfg.k_enter:
                merged_regions[-1] = (p0, r1)
                continue
        merged_regions.append((r0, r1))
    regions = merged_regions
    for r0, r1 in regions:
        direction = "right" if kc[np.argmax(np.abs(kc[r0:r1 + 1])) + r0] > 0 else "left"
        seg = np.arange(r0, r1 + 1)
        # Multi-ápice: picos separados >= 18 m con prominencia >= 1/180.
        peaks, props = find_peaks(np.abs(kc[r0:r1 + 1]),
                                  distance=max(1, round(cfg.peak_min_dist_m / STEP_M)),
                                  prominence=cfg.peak_prominence)
        peaks = [p + r0 for p in peaks]
        if not peaks:
            peaks = [int(np.argmax(np.abs(kc[r0:r1 + 1])) + r0)]
        # División por valles profundos y largos.
        bounds = [r0]
        for a, b in zip(peaks[:-1], peaks[1:]):
            lo = np.abs(kc[a:b + 1])
            thr = cfg.split_valley_frac * min(abs(kc[a]), abs(kc[b]))
            below = np.flatnonzero(lo < thr)
            if len(below) == 0:
                continue
            # Racha contigua más larga bajo el umbral.
            best_len, best_mid, cur_len, cur_start = 0, a, 0, None
            for k in below:
                if cur_start is None or k != cur_start + cur_len:
                    cur_start, cur_len = k, 1
                else:
                    cur_len += 1
                if cur_len > best_len:
                    best_len, best_mid = cur_len, cur_start + cur_len // 2
            if best_len * STEP_M >= cfg.split_valley_len_m:
                bounds.append(a + best_mid)
        bounds.append(r1)
        for _q0, _q1 in zip(bounds[:-1], bounds[1:]):
            q0, q1 = int(_q0), int(_q1)
            ev = _build_curve(s, kc, ko, hd, tho, opt, q0, q1, direction, cfg)
            if ev is not None:
                if ev["s_start"] < 20.0 and ev["angle_deg"] < 15.0:
                    continue  # Descarta falsa curva en la línea de salida (CALL_000)
                curves.append(ev)
    # Enlazar secuencias izquierda<->derecha con "into" si gap < 30 m.
    curves.sort(key=lambda e: e["s_start"])
    for prev, cur in zip(curves, curves[1:]):
        if prev["direction"] != cur["direction"] and cur["s_start"] - prev["s_end"] < cfg.into_gap_m:
            cur["link"] = "into"
    return curves


def _core_trim(s: np.ndarray, kc: np.ndarray, q0: int, q1: int, cfg: V3Config) -> Optional[Tuple[int, int]]:
    peak = float(np.abs(kc[q0:q1 + 1]).max(initial=0.0))
    if peak <= 0:
        return None
    thr = max(cfg.trim_frac * peak, cfg.trim_floor)
    inside = np.flatnonzero(np.abs(kc[q0:q1 + 1]) >= thr)
    if len(inside) == 0:
        return None
    return q0 + int(inside[0]), q0 + int(inside[-1])


def _build_curve(s, kc, ko, hd, tho, opt, q0, q1, direction, cfg: V3Config) -> Optional[Dict[str, Any]]:
    core = _core_trim(s, kc, q0, q1, cfg)
    if core is None:
        return None
    c0, c1 = core
    if c1 <= c0:
        return None
    # Ángulo sobre la región COMPLETA (giro total; el núcleo recortado solo
    # manda en longitud/radio/evolución). Un hairpin exige >=100° de rumbo:
    # una square de 90° nunca es hairpin aunque su ápice sea cerrado.
    ang_c = abs(float(np.degrees(hd[q1] - hd[q0])))
    ang_o = abs(float(tho[q1] - tho[q0]))
    with np.errstate(divide="ignore"):
        r_opt = 1.0 / np.maximum(np.abs(ko[c0:c1 + 1]), 1e-9)
    r_min_opt = float(r_opt.min(initial=1e9))
    if not (ang_c >= cfg.min_angle_center_deg and (ang_o >= cfg.min_angle_opt_deg or r_min_opt <= cfg.min_r_opt_m)):
        return None  # falsa curva en recta ancha
    ak = np.abs(kc[c0:c1 + 1])
    apex = c0 + int(np.argmax(ak))
    with np.errstate(divide="ignore"):
        r_all = 1.0 / np.maximum(ak, 1e-9)
    r_apex = float(1.0 / max(abs(float(kc[apex])), 1e-9))
    r_avg = float(r_all.mean())
    r_geom = 0.65 * r_apex + 0.35 * r_avg
    sev_geo = severity_for_radius(r_geom)
    # tightens / opens por mitades del núcleo.
    mid = (c0 + c1) // 2
    r_first = float(np.median(1.0 / np.maximum(np.abs(kc[c0:mid + 1]), 1e-9))) if mid > c0 else r_geom
    r_second = float(np.median(1.0 / np.maximum(np.abs(kc[mid:c1 + 1]), 1e-9))) if c1 > mid else r_geom
    mods: List[str] = []
    sev_eff = sev_geo
    if 1 <= sev_eff <= 6 and 1 <= severity_for_radius(r_second) <= 6:
        if r_second < cfg.tighten_ratio * r_first and \
                severity_for_radius(r_second) > severity_for_radius(r_first):
            mods.append("tightens")
    if r_second > cfg.open_ratio * r_first:
        mods.append("opens")
    length = float(s[c1] - s[c0])
    if length >= 135.0:
        mods.append("verylong")
    elif length >= 80.0:
        mods.append("long")
    return {
        "type": "curve", "direction": direction,
        "s_start": float(s[c0]), "s_end": float(s[c1]), "s_apex": float(s[apex]),
        "node_start": c0, "node_end": c1, "node_apex": apex,
        "angle_deg": round(ang_c, 2), "angle_opt_deg": round(ang_o, 2),
        "radius_apex_c": round(r_apex, 2), "radius_avg_core": round(r_avg, 2),
        "radius_geom": round(r_geom, 2),
        "radius_first_half": round(r_first, 2), "radius_second_half": round(r_second, 2),
        "length_m": round(length, 2),
        "severity_geometric": sev_geo, "severity_effective": sev_eff,
        "modifiers": mods, "review_reasons": [], "linked_hazard_ids": [],
    }


# --- Parte B: obstáculos multi-instancia + escenarios de velocidad ---

OBSTACLE_PATTERNS = {
    "rock": ["rock_big_*", "stone_*", "fence_rock_1", "rock_snow_*",
             "stone_snow", "stone_mountain_*", "fin_stone*", "fin_terrain_rocks*"],
    "ditch": ["*ditch_*", "sand_erosion_*"],
    "gate": ["fence_gate_1", "haybarn_*", "house_2", "house_cowhouse_1"],
    "post": ["pylon_1", "polyn_1_wire", "power_line_1", "phoneline", "sign_splimit",
             "sign_wooden*", "fin_pole*", "fin_pylon_1", "swe_pylon"],
    "junction": ["roadbar1", "road_crossroad_*", "road_field_1_cross", "*cross*",
                 "sign_crossing_*", "sign_hardturn", "sign_turn_right", "sign_stop", "sign_yield"],
}

# Troncos de arbolado (mobiliario continuo, no postes discretos): solo
# cuentan si implican dont_cut real; si no, son roadside_furniture.
TRUNK_PATTERNS = ["russian_tree_trunks", "nul_collision_wood", "kenya_tree_trunks",
                  "fin_tree_pine*", "fin_tree_birch*", "tree_birch_trunk*",
                  "sweden_tree_trunks", "mountain_tree_trunks"]


def _is_trunk(label: str) -> bool:
    return any(_fnm.fnmatchcase(label, p) for p in TRUNK_PATTERNS)

import fnmatch as _fnm  # noqa: E402


def _match_any(name: str, patterns: List[str]) -> bool:
    return any(_fnm.fnmatchcase(name, p) for p in patterns)


def _batch_world_verts(batch: Dict[str, Any], mat4: Optional[np.ndarray],
                       pos_extra: Optional[np.ndarray]) -> np.ndarray:
    v = np.asarray(batch["verts"], dtype=np.float64)
    if mat4 is not None:
        v = v @ np.asarray(mat4, dtype=np.float64)[:3, :3] + np.asarray(pos_extra, dtype=np.float64)
    return np.column_stack([v[:, 0], v[:, 1], -v[:, 2]])


def extract_obstacles(stage, center: np.ndarray, left: np.ndarray, right: np.ndarray,
                      step_m: float = 2.0, cfg=None) -> List[Dict[str, Any]]:
    """Extrae vértices de obstáculos (TRACK+HIERARCHY), filtra y clusteriza."""
    dy_max = float(getattr(cfg, "dy_max_m", 3.5))
    post_max = float(getattr(cfg, "post_max_edge_m", 1.8))
    rock_max = float(getattr(cfg, "lateral_max_m", 3.2))
    cxz = center[:, [0, 2]]
    tree = cKDTree(cxz)
    raw: List[Dict[str, Any]] = []

    def _collect(verts_godot: np.ndarray, label: str):
        if len(verts_godot) == 0:
            return
        cat_name = label.split(":")[0]
        max_edge = post_max if cat_name == "post" else (rock_max if cat_name == "rock" else 4.5)
        dist, st = tree.query(verts_godot[:, [0, 2]], k=1)
        for k in range(len(verts_godot)):
            i = int(st[k])
            l = left[i][[0, 2]]
            r = right[i][[0, 2]]
            d_edge = float(min(np.linalg.norm(verts_godot[k][[0, 2]] - l),
                               np.linalg.norm(verts_godot[k][[0, 2]] - r)))
            if d_edge > max_edge:
                continue
            if abs(float(verts_godot[k][1]) - float(center[i][1])) > dy_max:
                continue
            n = np.array([-(cxz[min(i + 1, len(cxz) - 1)][1] - cxz[max(i - 1, 0)][1]),
                          cxz[min(i + 1, len(cxz) - 1)][0] - cxz[max(i - 1, 0)][0]])
            nrm = float(np.linalg.norm(n)) or 1.0
            lat = float(np.dot(verts_godot[k][[0, 2]] - cxz[i], n / nrm))
            raw.append({"s": float(i * step_m), "station": i, "side": "left" if lat < 0 else "right",
                        "d_edge": d_edge, "label": label,
                        "pos": [float(v) for v in verts_godot[k]]})

    for chunk in stage.track_chunks:
        for b in chunk["batches"]:
            mat = stage.materials[b["mat_id"]]["name"] if b["mat_id"] < len(stage.materials) else ""
            for cat, pats in OBSTACLE_PATTERNS.items():
                if _match_any(mat, pats):
                    _collect(_batch_world_verts(b, None, None), f"{cat}:{mat}")
                    break
    for mesh in stage.hierarchy_meshes:
        mat4 = np.asarray(mesh["matrix"], dtype=np.float64).reshape(4, 4)
        pos = np.asarray(mesh["pos_extra"], dtype=np.float64)
        for model in mesh["models"]:
            for b in model["batches"]:
                mat = stage.materials[b["mat_id"]]["name"] if b["mat_id"] < len(stage.materials) else ""
                name = mesh.get("name", "")
                for cat, pats in OBSTACLE_PATTERNS.items():
                    if _match_any(mat, pats) or _match_any(name, pats):
                        _collect(_batch_world_verts(b, mat4, pos), f"{cat}:{mat or name}")
                        break

    events: List[Dict[str, Any]] = []
    by_cat: Dict[str, List[Dict[str, Any]]] = {}
    for r in raw:
        by_cat.setdefault(r["label"].split(":")[0], []).append(r)
    hid = 0
    for cat, items in by_cat.items():
        eps = 18.0 if cat in ("gate", "junction") else 12.0
        items.sort(key=lambda r: r["s"])
        cluster: List[Dict[str, Any]] = []
        def _flush(cl):
            nonlocal hid
            if not cl:
                return
            s_vals = [c["s"] for c in cl]
            sides = [c["side"] for c in cl]
            side = max(set(sides), key=sides.count)
            hid += 1
            events.append({
                "id": f"RU1_HAZ_{hid:03d}" if False else f"HAZ_{hid:03d}",
                "type": cat, "s": round(float(np.median(s_vals)), 2),
                "s_min": round(float(min(s_vals)), 2), "s_max": round(float(max(s_vals)), 2),
                "side": side, "d_edge": round(float(min(c["d_edge"] for c in cl)), 2),
                "count": len(cl), "label": cl[0]["label"],
            })
        for r in items:
            if cluster and r["s"] - cluster[-1]["s"] > eps:
                _flush(cluster)
                cluster = []
            cluster.append(r)
        _flush(cluster)
    events.sort(key=lambda e: e["s"])
    # Re-etiqueta estable por posición.
    for k, e in enumerate(events, 1):
        e["id"] = f"HAZ_{k:03d}"
    return events


def link_obstacles(events: List[Dict[str, Any]], curves: List[Dict[str, Any]],
                   cfg: V3Config) -> None:
    """Vincula obstáculos a curvas (inside/outside, dont_cut). In situ."""
    for ob in events:
        ob["relative_side"] = None
        ob["linked_curve"] = None
        for c in curves:
            # Ampliar ventana de absorción antes de la curva (35m normal, 50m en frenadas fuertes)
            look_before = 50.0 if c.get("severity_effective", 3) >= 5 else 30.0
            if c["s_start"] - look_before <= ob["s"] <= c["s_end"] + 12.0:
                ob["linked_curve"] = c["id"]
                same = (ob["side"] == c["direction"])
                ob["relative_side"] = "inside" if same else "outside"
                if same and ob["d_edge"] <= cfg.dont_cut_edge_m and ob["type"] in ("rock", "post", "ditch"):
                    ob["dont_cut"] = True
                    ob["priority"] = 85
                break


def compute_speed_profiles(geo: Dict[str, Any], cfg: V3Config) -> Dict[str, np.ndarray]:
    """3 perfiles cuasi-estacionarios (forward/backward) + t(s) nominal."""
    secs = geo["sections"]
    n = len(secs)
    ko = np.array([x["kappa_opt"] for x in secs])
    mu = np.array([x["grip_mu"] for x in secs])
    grade = np.array([x["grade_pct"] for x in secs])
    out: Dict[str, np.ndarray] = {}
    t_nom = None
    for tag, gf, vm in zip(("conservative", "nominal", "fast"),
                           cfg.grip_factors, cfg.vmax):
        with np.errstate(divide="ignore"):
            v_curve = np.sqrt(gf * mu * G / np.maximum(np.abs(ko), 1e-6))
        v_curve = np.minimum(v_curve, vm)
        v = np.full(n, vm)
        v[0] = min(cfg.v_start_ms, v_curve[0])
        for i in range(1, n):
            slope = math.atan(grade[i - 1] / 100.0)
            a = cfg.acc_ms2 - G * math.sin(slope)
            v[i] = min(v_curve[i], math.sqrt(max(v[i - 1] ** 2 + 2 * max(a, 0.5) * STEP_M, 0.0)))
        for i in range(n - 2, -1, -1):
            slope = math.atan(grade[i] / 100.0)
            a = cfg.brk_ms2 + G * math.sin(slope)
            v[i] = min(v[i], math.sqrt(max(v[i + 1] ** 2 + 2 * max(a, 0.5) * STEP_M, 0.0)))
        out[tag] = v
        if tag == "nominal":
            t_nom = np.concatenate([[0.0], np.cumsum(2.0 * STEP_M / np.maximum(v[:-1] + v[1:], 1e-6))])
    out["t"] = t_nom
    return out


def detect_vertical(geo: Dict[str, Any], speeds: Dict[str, np.ndarray],
                    cfg: V3Config) -> List[Dict[str, Any]]:
    """Detecta un único evento por rasante/salto usando picos locales (NMS) de Gamma."""
    secs = geo["sections"]
    kv = np.array([x["kappa_vertical"] for x in secs])
    grade = np.array([x["grade_pct"] for x in secs])
    v = speeds["fast"]

    # Solo partes convexas (kv < 0) producen descarga vertical
    convex_kv = np.where(kv < 0.0, -kv, 0.0)
    cos_grade = np.cos(np.arctan(grade / 100.0))
    gamma_arr = (v ** 2 * convex_kv) / np.maximum(G * cos_grade, 1e-6)

    min_dist_samples = max(1, int(round(cfg.crest_min_dist_m / STEP_M)))
    peaks, _ = find_peaks(gamma_arr, height=cfg.crest_gamma, distance=min_dist_samples)

    evts: List[Dict[str, Any]] = []
    win_steps = max(2, int(round(12.0 / STEP_M)))
    for idx in peaks:
        i = int(idx)
        # Verificar caída real de pendiente (slope_in - slope_out), igual que en v1
        s_in = float(np.max(grade[max(0, i - win_steps):i + 1]))
        s_out = float(np.min(grade[i:min(len(grade), i + win_steps + 1)]))
        delta_grade = s_in - s_out
        if delta_grade < cfg.crest_min_delta_grade_pct:
            continue

        gamma = float(gamma_arr[i])
        if gamma >= cfg.jump_gamma and (delta_grade >= 8.0 or s_out <= -8.0):
            evts.append({"type": "jump", "s": float(secs[i]["s_m"]), "station": i,
                         "gamma": round(gamma, 3), "priority": 90})
        else:
            evts.append({"type": "crest", "s": float(secs[i]["s_m"]), "station": i,
                         "gamma": round(gamma, 3), "priority": 70})
    return evts


# --- Parte C: severidad efectiva, planificador t(s), multi-palabra y exportación ---

ZERO_FIELDS = {"kind": 0, "direction": 0, "distance": 0, "length": 0, "turn": 0,
               "surface": 0, "hazard": 0, "caution": 0, "junction": 0,
               "no_cut": 0, "ending": 0, "side": 0}

HAZARD_BY_TYPE = {"jump": 1, "crest": 2, "rocks": 4, "post": 5, "ditch": 7, "gate": 6}
PRIORITY = {"jump": 90, "gate": 85, "dont_cut": 85, "junction": 80,
            "rocks": 75, "crest": 70, "ditch": 65, "post": 60}


def _distance_class(gap_m: float, both_curves: bool = False) -> int:
    if gap_m >= 180.0:
        return 9
    if gap_m >= 135.0:
        return 8
    if gap_m >= 110.0:
        return 7
    if gap_m >= 85.0:
        return 6
    if gap_m >= 60.0:
        return 5
    if gap_m >= 40.0:
        return 4
    if gap_m >= 22.0:
        return 3
    if both_curves:
        return 2  # Entre dos curvas pegadas (<22m), usar siempre "into" ("a"), nunca "and" ("y")
    if gap_m >= 10.0:
        return 2
    return 1


def group_consecutive_curves(curves: List[Dict[str, Any]], gap_m: float = 40.0) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """Agrupa curvas consecutivas del mismo sentido con hueco < gap_m en una
    sola llamada (densidad). Conserva la más severa como referencia; el resto
    queda auditado como grouped_into. Retorna (kept, absorbed)."""
    ordered = sorted(curves, key=lambda e: e["s_start"])
    kept: List[Dict[str, Any]] = []
    absorbed: List[Dict[str, Any]] = []
    for c in ordered:
        if (kept and kept[-1]["direction"] == c["direction"]
                and c["s_start"] - kept[-1]["s_end"] < gap_m):
            p = kept[-1]
            p["s_end"] = c["s_end"]
            p["node_end"] = c["node_end"]
            p["length_m"] = round(p["s_end"] - p["s_start"], 2)
            p["angle_deg"] = round(p.get("angle_deg", 0.0) + c.get("angle_deg", 0.0), 2)
            if c.get("severity_effective", 0) > p.get("severity_effective", 0):
                for k in ("severity_geometric", "severity_effective", "radius_geom",
                          "radius_apex_c", "radius_avg_core", "radius_first_half", "radius_second_half",
                          "node_apex", "s_apex", "grade_p85_down_pct", "camber_apex_eff_deg",
                          "decel_demand_ms", "speed_scenarios_ms", "kind_str"):
                    if k in c:
                        p[k] = c[k]
            for m in c.get("modifiers", []):
                if m not in p["modifiers"]:
                    p["modifiers"].append(m)
            if p["length_m"] >= 135.0 and "verylong" not in p["modifiers"]:
                p["modifiers"].append("verylong")
            elif p["length_m"] >= 80.0 and "long" not in p["modifiers"]:
                p["modifiers"].append("long")
            p["review_reasons"] = p.get("review_reasons", []) + [f"absorbe {c['id']}"]
            p["merged_ids"] = p.get("merged_ids", [p["id"]]) + [c["id"]]
            c["status"] = "grouped_into"
            c["grouped_into"] = p["id"]
            absorbed.append(c)
        else:
            c["merged_ids"] = [c["id"]]
            kept.append(c)
    for p in kept:
        p["priority"] = min(95, 35 + 6 * int(p.get("severity_effective", 3)))
    return kept, absorbed


def apply_effective_severity(curves: List[Dict[str, Any]], geo: Dict[str, Any],
                             speeds: Dict[str, np.ndarray], cfg: V3Config) -> None:
    """Suma +1 por bajada p85, contraperalte y demanda de frenada. In situ."""
    secs = geo["sections"]
    grade = np.array([x["grade_pct"] for x in secs])
    s_arr = np.array([x["s_m"] for x in secs])
    vnom = speeds["nominal"]
    for c in curves:
        reasons = c["review_reasons"]
        i0 = max(0, int(np.searchsorted(s_arr, c["s_start"] - cfg.downhill_window_m)))
        i1 = int(np.searchsorted(s_arr, c["s_end"], side="right"))
        p85 = float(np.percentile(grade[i0:max(i1, i0 + 1)], 85)) if i1 > i0 else 0.0
        c["grade_p85_down_pct"] = round(p85, 2)
        if p85 <= cfg.downhill_p85_pct:
            c["severity_effective"] += 1
            reasons.append(f"downhill_p85 {p85:.1f}%<={cfg.downhill_p85_pct}%")
            if "steep_drop_exit" not in c["modifiers"]:
                c["modifiers"].append("steep_drop_exit")
        ai = int(c["node_apex"])
        phi = 0.0
        if 0 <= ai < len(secs):
            kc_a = float(secs[ai]["kappa_center"])
            phi = -np.sign(kc_a) * float(secs[ai]["camber_deg"]) if kc_a != 0 else 0.0
        c["camber_apex_eff_deg"] = round(phi, 2)
        if phi <= cfg.bad_camber_deg:
            c["severity_effective"] += 1
            reasons.append(f"bad_camber {phi:.1f}<={cfg.bad_camber_deg}")
        j0 = max(0, int(np.searchsorted(s_arr, c["s_start"] - cfg.decel_window_m)))
        dem = float(vnom[j0] - vnom[c["node_start"]:c["node_end"] + 1].min(initial=vnom[j0]))
        c["decel_demand_ms"] = round(dem, 2)
        if dem >= cfg.decel_demand_ms:
            c["severity_effective"] += 1
            reasons.append(f"decel_demand {dem:.1f}>={cfg.decel_demand_ms}")
        # Un hairpin exige cambio de rumbo >= 100° (convención v2: kind 8
        # solo si angle >= 100; si no, openhairpin). Una square de 90°
        # nunca es hairpin aunque su ápice sea cerrado.
        if c.get("angle_deg", 0.0) < 100.0 and c["severity_effective"] == 8:
            c["severity_effective"] = 7
            reasons.append("capped_square: ang<100 -> openhairpin")
        c["priority"] = min(95, 35 + 6 * int(c["severity_effective"]))


def group_standalone_hazards(events: List[Dict[str, Any]], gap_m: float = 25.0) -> List[Dict[str, Any]]:
    """Agrupa peligros sueltos del mismo tipo/lado a < gap_m en una sola llamada.

    Los eventos individuales se conservan en candidates (trazabilidad); la
    llamada agrupada evita saturar el canal de voz. No se descarta nada.
    """
    standalone = [e for e in events if e.get("linked_curve") is None and e.get("status") != "absorbed"]
    others = [e for e in events if e not in standalone]
    standalone.sort(key=lambda e: e["s"])
    grouped: List[Dict[str, Any]] = []
    for e in standalone:
        if e["type"] in ("junction", "gate", "jump", "crest"):
            grouped.append(e)
            continue
        if grouped and grouped[-1]["type"] == e["type"] and grouped[-1].get("side") == e.get("side") \
                and e["s"] - grouped[-1].get("s_end", grouped[-1]["s"]) < gap_m:
            g = grouped[-1]
            g["s_end"] = max(g.get("s_end", g["s"]), e["s"])
            g["s"] = min(g["s"], e["s"])
            g["priority"] = max(g.get("priority", 0), e.get("priority", 0))
            if e.get("d_edge") is not None and (g.get("d_edge", 99.0) is None or e["d_edge"] < g["d_edge"]):
                g["d_edge"] = e["d_edge"]
            g["merged_ids"] = g.get("merged_ids", [g["id"]]) + [e["id"]]
            g["count"] = g.get("count", 1) + e.get("count", 1)
            e["status"] = "grouped"
            e["grouped_into"] = g["id"]
        else:
            e["merged_ids"] = [e["id"]]
            grouped.append(e)
    return others + grouped


def _standalone_fields(ob: Dict[str, Any]) -> Dict[str, int]:
    """Palabra para peligro suelto: hazard por tipo; no_cut+caution si roza
    la trazada (d_edge <= 1.2 m, umbral dont_cut). Sin side: no hay inside/outside."""
    f = dict(ZERO_FIELDS)
    t = ob["type"]
    if t == "gate":
        f.update({"surface": 2, "hazard": 6, "turn": 3, "caution": 1})
    elif t in ("rock", "rocks"):
        f.update({"hazard": 4})
    elif t == "post":
        f.update({"hazard": 5})
    elif t == "ditch":
        f.update({"hazard": 7})
    elif t == "junction":
        f.update({"junction": 1, "caution": 1})
    if t in ("rock", "rocks", "post", "ditch") and float(ob.get("d_edge", 99.0)) <= 1.2:
        f.update({"no_cut": 1, "caution": 1})
    return f


def build_main_sequence(curves: List[Dict[str, Any]], junctions: List[Dict[str, Any]],
                        verticals: List[Dict[str, Any]], obstacles: List[Dict[str, Any]],
                        cfg: V3Config) -> List[Dict[str, Any]]:
    """Secuencia principal: curvas + junctions + verticales + peligros sueltos."""
    seq: List[Dict[str, Any]] = []
    for c in curves:
        c["kind"] = "curve"
        seq.append(c)
    for j in junctions:
        if j.get("status") in ("absorbed", "dropped_low_priority"):
            continue
        j["kind"] = "junction"
        j.setdefault("priority", PRIORITY["junction"])
        seq.append(j)
    for v in verticals:
        v["kind"] = "hazard"
        v.setdefault("priority", PRIORITY.get(v["type"], 70))
        if v.get("status") in ("absorbed", "dropped_low_priority"):
            continue  # su aviso viaja en la palabra 1 de la curva o se omitió en recta
        seq.append(v)
    for ob in obstacles:
        if ob.get("linked_curve") is None and ob.get("status", "pending") != "absorbed":
            ob.setdefault("fields", _standalone_fields(ob))
            ob["kind"] = "hazard"
            ob.setdefault("priority", PRIORITY.get(ob["type"], 60))
            seq.append(ob)
    seq.sort(key=lambda e: (e.get("s_start", e.get("s", 0.0)), -e.get("priority", 0)))
    return seq


def _curve_base_fields(curve: Dict[str, Any]) -> Dict[str, int]:
    f = dict(ZERO_FIELDS)
    f["kind"] = int(curve["severity_effective"])
    f["direction"] = 1 if curve["direction"] == "left" else 2
    if curve.get("length_m", 0.0) >= 135.0:
        f["length"] = 2
    elif curve.get("length_m", 0.0) >= 80.0:
        f["length"] = 1
    if "tightens" in curve.get("modifiers", []):
        f["turn"] = 1
    elif "opens" in curve.get("modifiers", []):
        f["turn"] = 2
    return f


def _hazard_fields(ob: Dict[str, Any]) -> Dict[str, int]:
    f = dict(ZERO_FIELDS)
    t = ob["type"]
    if t == "gate":
        f.update({"surface": 2, "hazard": 6, "turn": 3, "caution": 1})
    elif t in ("rock", "rocks"):
        f.update({"hazard": 4, "side": 1 if ob.get("relative_side") == "inside" else 2})
        if ob.get("dont_cut"):
            f.update({"no_cut": 1, "caution": 1})
    elif t == "post":
        f.update({"hazard": 5, "side": 1 if ob.get("relative_side") == "inside" else 2})
    elif t == "ditch":
        f.update({"hazard": 7, "side": 1 if ob.get("relative_side") == "inside" else 2})
    elif t == "junction":
        f.update({"junction": 1, "caution": 1})
    return f


def plan_and_emit(seq: List[Dict[str, Any]], route_cum: np.ndarray,
                  t_of_s: np.ndarray, s_grid: np.ndarray,
                  cfg: V3Config) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """Planifica en t(s), degrada por niveles y emite llamadas (multi-palabra).

    Retorna (runtime_calls, dropped) con trazabilidad total.
    """
    # Distancias "to_current" sobre la secuencia emitida.
    for i, e in enumerate(seq):
        s0 = e.get("s_start", e.get("s", 0.0))
        if i == 0:
            e["gap_prev_m"] = s0
        else:
            p = seq[i - 1]
            e["gap_prev_m"] = max(0.0, s0 - p.get("s_end", p.get("s", s0)))
        gap = e["gap_prev_m"]
        # link coherente con lo anunciado: la palabra solo puede decir
        # and/into mediante las clases 1/2 (into: 10<=gap<22, and: gap<10).
        dc = _distance_class(gap)
        e["link"] = "into" if dc == 2 else ("and" if dc == 1 else None)
    runtime: List[Dict[str, Any]] = []
    dropped: List[Dict[str, Any]] = []
    prev_end_t = -1e9
    prev_node = -1
    call_idx = 0
    last_node = -1

    def _t(sv: float) -> float:
        return float(np.interp(sv, s_grid, t_of_s))

    def _node_ceil(sv: float) -> int:
        return int(min(int(np.searchsorted(route_cum, sv - 1e-9, side="left")), len(route_cum) - 1))

    for e in seq:
        words = _compose_words(e)
        if not words:
            e["status"] = "dropped"
            dropped.append(e)
            continue
        # Duración total del bloque (palabras encadenadas).
        durs = [speech_duration(decode_cmr2_slots(w["word"]), _V3SPEECH) for w in words]
        dur = sum(durs) + 0.15 * (len(words) - 1)
        s_evt = e.get("s_start", e.get("s", 0.0))
        sev = int(e.get("severity_effective", e.get("severity_geometric", 3)))
        v_app = e.get("speed_ms", 20.0)
        dem = e.get("decel_demand_ms", 0.0)
        t_lead = cfg.t_lead_base_s + cfg.t_lead_per_sev_s * sev + max(0.0, dem) / 6.0
        t_trig = max(0.0, _t(s_evt) - (t_lead + dur))
        s_trig = float(np.interp(t_trig, t_of_s, s_grid))
        gap_m = s_evt - s_trig
        if gap_m < cfg.lead_min_m:
            s_trig = max(0.0, s_evt - cfg.lead_min_m)
        elif gap_m > cfg.lead_max_m:
            s_trig = max(0.0, s_evt - cfg.lead_max_m)
        node = _node_ceil(s_trig)
        if node <= prev_node:
            node = prev_node + 1
        # Conflicto temporal con el bloque anterior.
        t_node = _t(route_cum[min(node, len(route_cum) - 1)])
        if t_node < prev_end_t + cfg.t_gap_s and runtime:
            # 1) anticipar el anterior hasta 1.8 s + into.
            prev = runtime[-1]
            shift = min(cfg.shift_early_max_s, (prev_end_t + cfg.t_gap_s) - t_node)
            if shift > 0 and prev["t_trigger"] - shift >= 0:
                prev["t_trigger"] -= shift
                prev["review"] = (prev.get("review", "") + " anticipado %.1fs+into" % shift).strip()
                t_node = _t(route_cum[min(node, len(route_cum) - 1)])
            if t_node < prev_end_t + cfg.t_gap_s:
                if not _degrade(e, words, cfg):
                    if int(e.get("priority", 0)) >= 70:
                        e["review_reasons"] = e.get("review_reasons", []) + ["forced_chain_critical"]
                    else:
                        e["status"] = "dropped"
                        dropped.append(e)
                        continue
                durs = [speech_duration(decode_cmr2_slots(w["word"]), _V3SPEECH) for w in words]
                dur = sum(durs) + 0.15 * (len(words) - 1)
        latest_t = _t(s_evt) - (1.5 + dur)
        if t_node > latest_t and e.get("deg_level", 0) < 3:
            e["deg_level"] = e.get("deg_level", 0) + 1
            _apply_deg_level(e, words)
        for w_i, w in enumerate(words):
            w["call_index"] = call_idx
            # Nodos estrictamente crecientes en toda la secuencia (contrato v1).
            w_node = min(node + w_i, len(route_cum) - 1)
            if w_node <= last_node:
                w_node = min(last_node + 1, len(route_cum) - 1)
            w["advisory_gate_node"] = w_node
            last_node = w_node
            w["route_distance_m"] = float(route_cum[w["advisory_gate_node"]])
            w["t_trigger"] = t_node if w_i == 0 else t_node
            call_idx += 1
        e["status"] = "emitted"
        e["emitted_call_ids"] = [w["call_index"] for w in words]
        runtime.extend(words)
        prev_end_t = t_node + dur
        prev_node = node
    # 1) Repack de distancias desde la adyacencia EMITIDA:
    ev_by_id: Dict[str, Dict[str, Any]] = {str(e.get("id", "")): e for e in seq}
    last_end: Optional[float] = None
    prev_is_curve = False
    for w in runtime:
        s0 = w.get("s_start")
        f = dict(w.get("fields", {}))
        cur_is_curve = 1 <= f.get("kind", 0) <= 8
        if last_end is None or s0 is None:
            cls = 0
        else:
            cls = _distance_class(max(0.0, s0 - last_end), both_curves=(prev_is_curve and cur_is_curve))
        f["distance"] = cls
        w["fields"] = f
        last_end = w.get("s_end", s0)
        prev_is_curve = cur_is_curve

    # 2) Elevación de Caution (Caution Hoisting) en cadenas enlazadas ("and" / "into"):
    # Si varias palabras van unidas con distance in (1, 2), forman una sola frase.
    # El nivel máximo de caution sube a la primera palabra de la cadena y se borra en el resto.
    idx = 0
    while idx < len(runtime):
        chain_end = idx
        while chain_end + 1 < len(runtime) and runtime[chain_end + 1]["fields"].get("distance") in (1, 2):
            chain_end += 1
        if chain_end > idx:
            max_caut = max(runtime[k]["fields"].get("caution", 0) for k in range(idx, chain_end + 1))
            # Si hay más de 1 peligro severo en la cadena o una curva muy cerrada (kind >= 5), sube a caution=2
            has_tight = any(runtime[k]["fields"].get("kind", 0) >= 5 for k in range(idx, chain_end + 1))
            if max_caut >= 1 and has_tight and sum(1 for k in range(idx, chain_end + 1) if runtime[k]["fields"].get("caution", 0) > 0) >= 2:
                max_caut = 2
            runtime[idx]["fields"]["caution"] = max_caut
            for k in range(idx + 1, chain_end + 1):
                runtime[k]["fields"]["caution"] = 0
        idx = chain_end + 1

    # 3) Cooldown de Caution y Deduplicación de Hazards repetidos (ej. "rocks" en 3 curvas seguidas):
    last_caution_s = -1e9
    last_caution_t = -1e9
    last_caution_lvl = 0
    last_hazard_s: Dict[int, float] = {}
    last_curve_kind = 0

    for w in runtime:
        f = w["fields"]
        s0 = float(w.get("s_start") or 0.0)
        t0 = float(w.get("t_trigger") or 0.0)

        # 3a. Suprimir caution repetido dentro de la ventana de cooldown (salvo que escale de 1 a 2)
        caut = f.get("caution", 0)
        if caut > 0:
            if (s0 - last_caution_s < cfg.caution_cooldown_m or t0 - last_caution_t < cfg.caution_cooldown_s) and caut <= last_caution_lvl:
                f["caution"] = 0
            else:
                last_caution_s = s0
                last_caution_t = t0
                last_caution_lvl = caut

        # 3b. Suprimir el mismo hazard estático (rocks=4, post=5, ditch=7) si se acaba de cantar hace < 65m
        hz = f.get("hazard", 0)
        kind = f.get("kind", 0)
        if hz in (4, 5, 7):
            prev_hz_s = last_hazard_s.get(hz, -1e9)
            # Si está dentro del cooldown y la curva actual no es más cerrada que la anterior, omitir hazard redundante
            if (s0 - prev_hz_s < cfg.hazard_repeat_cooldown_m) and (1 <= kind <= 6 and kind <= last_curve_kind):
                f["hazard"] = 0
                f["side"] = 0
                f["no_cut"] = 0
                f["surface"] = 0
            else:
                last_hazard_s[hz] = s0
        if 1 <= kind <= 8:
            last_curve_kind = kind

        # Re-empaquetar la palabra final limpia y actualizar metadatos
        w["word"] = pack_cmr2_word(**f)
        cls = f["distance"]
        w["link"] = "into" if cls == 2 else ("and" if cls == 1 else None)
        ev = ev_by_id.get(str(w.get("event_id", "")))
        if ev is not None and (not ev.get("emitted_call_ids") or ev["emitted_call_ids"][0] == w["call_index"]):
            ev["distance"] = cls
            ev["link"] = w["link"]
    return runtime, dropped


def _compose_words(e: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Compone una palabra CMR2 limpia por evento, evitando desdoblar hazards con 'and'."""
    if e.get("kind") == "curve":
        f = _curve_base_fields(e)
        if e.get("is_junction_turn"):
            f["junction"] = 1
        linked = list(e.get("_hazards", []))
        if linked:
            # Elegir únicamente el peligro de mayor prioridad para no saturar la curva
            top = max(linked, key=lambda h: (1 if h.get("no_cut") else 0, h.get("priority", 0)))
            if top.get("hz"):
                f["hazard"] = top["hz"]
                f["surface"] = 1 if top["hz"] in (1, 2) else (2 if top["hz"] == 6 else 0)
            if top.get("side") and f["hazard"] in (4, 5, 7):
                f["side"] = top["side"]
            if top.get("no_cut"):
                f["no_cut"] = 1
                f["caution"] = max(f.get("caution", 0), 1)
            if top.get("turn") == 3 and f["turn"] == 0:
                f["turn"] = 3
            e["linked_hazard_ids"] = [top["id"]]
            # Los no elegidos quedan auditados como absorbed en el post-pase
            # (comparten las llamadas de la curva que los absorbe).
        elif e.get("crest_here"):
            f["hazard"] = 2
            f["surface"] = 1
        return [{"word": pack_cmr2_word(**{**f, "distance": e.get("distance", 0)}),
                 "fields": dict(f), "event_id": e.get("id"),
                 "s_start": e.get("s_start"), "s_end": e.get("s_end")}]
    # Peligros / junctions standalone: palabra propia.
    f = dict(e.get("fields", {}))
    return [{"word": pack_cmr2_word(**{**f, "distance": e.get("distance", 0)}),
             "fields": dict(f), "event_id": e.get("id"),
             "s_start": e.get("s_start", e.get("s")), "s_end": e.get("s_end", e.get("s"))}]


def _apply_deg_level(e: Dict[str, Any], words: List[Dict[str, Any]]) -> None:
    lvl = e.get("deg_level", 1)
    for w in words:
        f = w["fields"]
        if lvl >= 1:
            f["length"] = 0
            if f.get("turn") == 2:
                f["turn"] = 0
        if lvl >= 2:
            f["length"] = 0
            keep_side = f.get("no_cut") == 1 or f.get("hazard") in (4,)
            if not keep_side:
                f["side"] = 0
        if lvl >= 3 and f.get("turn") == 1:
            f["turn"] = 0
            if 1 <= e.get("severity_effective", 0) <= 7:
                e["severity_effective"] += 1
                e["kind"] = e["severity_effective"]
        w["word"] = pack_cmr2_word(**{**f, "distance": e.get("distance", 0)})


def _degrade(e: Dict[str, Any], words: List[Dict[str, Any]], cfg: V3Config) -> bool:
    """Degrada por niveles; True si conserva la llamada."""
    for lvl in (1, 2, 3):
        e["deg_level"] = lvl
        _apply_deg_level(e, words)
        e["review_reasons"] = e.get("review_reasons", []) + [f"degraded_L{lvl}"]
        return True
    return False


class _SpeechCfg:
    base_sec = 0.35
    slot_sec = 0.50
    slot_durations = None


_V3SPEECH = _SpeechCfg()


def _json_default(o):
    """Serializa escalares numpy (int64 de índices) para json."""
    if isinstance(o, (np.integer,)):
        return int(o)
    if isinstance(o, (np.floating,)):
        return float(o)
    if isinstance(o, (np.bool_,)):
        return bool(o)
    if isinstance(o, np.ndarray):
        return o.tolist()
    raise TypeError(f"No serializable: {type(o)}")


def export_documents(runtime: List[Dict[str, Any]], candidates: List[Dict[str, Any]],
                     authoring: List[Dict[str, Any]], country: str, stage: str,
                     out_dir: Path) -> Dict[str, Any]:
    """Escribe runtime + authoring + candidates (mismos nombres que v1/v2)."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    run_doc = {"stage": f"{country}_{stage}", "generator": "pacenote_analyzer_v3",
               "calls": [f"0x{w['word'] & 0xFFFFFFFF:08x}" for w in runtime],
               "curves": []}
    for w in runtime:
        run_doc["curves"].append({
            "call_word_hex": f"0x{w['word'] & 0xFFFFFFFF:08x}",
            "call_index": int(w["call_index"]),
            "curve_id": w.get("curve_id", "EVT_%03d" % w["call_index"]),
            "advisory_gate_node": int(w["advisory_gate_node"]),
            "route_distance_m": round(float(w["route_distance_m"]), 2),
            "s_start": w.get("s_start"), "s_end": w.get("s_end"),
            "kind_str": w.get("kind_str"), "direction": w.get("direction"),
            "link": w.get("link"),
        })
    (out_dir / f"{country}_{stage}_pacenotes.json").write_text(
        json.dumps(run_doc, ensure_ascii=False, indent=2, default=_json_default) + "\n", encoding="utf-8")
    (out_dir / f"{country}_{stage}_pacenotes_authoring.json").write_text(
        json.dumps({"stage": f"{country}_{stage}", "generator": "pacenote_analyzer_v3",
                    "events": authoring}, ensure_ascii=False, indent=2, default=_json_default) + "\n", encoding="utf-8")
    (out_dir / f"{country}_{stage}_pacenotes_candidates.json").write_text(
        json.dumps({"stage": f"{country}_{stage}", "generator": "pacenote_analyzer_v3",
                    "events": candidates}, ensure_ascii=False, indent=2, default=_json_default) + "\n", encoding="utf-8")
    return run_doc


def analyze_and_build_pacenotes(route_points, bmf_stage, output_dir,
                                country_name="russia", stage_name="stage1",
                                cfg: Optional[V3Config] = None,
                                geo_json: Optional[Path] = None) -> Dict[str, Any]:
    """Pipeline completo v3 con la firma compatible v1/v2."""
    cfg = cfg or V3Config()
    route = np.asarray(route_points, dtype=np.float64)
    # 1. Geometría (reutiliza JSON si se aporta, o reconstruye).
    if geo_json and Path(geo_json).exists():
        geo = json.loads(Path(geo_json).read_text(encoding="utf-8"))
        mesh = extract_road_mesh(bmf_stage)
        center = np.array([s["center"] for s in geo["sections"]])
        left = np.array([s["left_edge"] for s in geo["sections"]])
        right = np.array([s["right_edge"] for s in geo["sections"]])
    else:
        mesh = extract_road_mesh(bmf_stage)
        cs = CrossSections(mesh["road_triangles"], mesh["road_materials"],
                           mesh["road_categories"], mesh["road_uvs"])
        doc = cs.build(route)
        sol = CorridorSolver(mesh["barrier_segments"]).solve(doc)
        cl = build_centerline(sol["sections"])
        mats = [s.get("surface_center", "") for s in sol["sections"]]
        left = np.array([s["solved_left_edge"] for s in sol["sections"]])
        right = np.array([s["solved_right_edge"] for s in sol["sections"]])
        an = analyze_geometry(cl["center"], cl["opt_line"], left, right, mats)
        geo = build_road_geometry(f"{country_name}-{stage_name}", sol, cl, an, route)
    # 2. Curvas + severidad efectiva.
    curves = detect_curves(geo, cfg)
    for k, c in enumerate(curves, 1):
        c["id"] = f"EVT_{k:03d}"
    speeds = compute_speed_profiles(geo, cfg)
    apply_effective_severity(curves, geo, speeds, cfg)
    # Densidad: agrupa curvas consecutivas del mismo sentido (hueco < 40 m)
    # en una sola llamada antes de enlazar obstáculos.
    detected_curves = curves
    curves, _grouped = group_consecutive_curves(curves, gap_m=55.0)
    for c in curves:
        c["priority"] = min(95, 35 + 6 * int(c["severity_effective"]))
        c["kind_str"] = SEVERITY_NAMES.get(int(c["severity_effective"]), "three")
        c["speed_ms"] = float(np.interp(c["s_start"], np.arange(len(speeds["nominal"])) * STEP_M,
                                        speeds["nominal"]))
        dem = c.get("decel_demand_ms", 0.0)
        c["speed_scenarios_ms"] = {
            "conservative": round(float(np.interp(c["s_apex"], np.arange(len(speeds["conservative"])) * STEP_M, speeds["conservative"])), 1),
            "nominal": round(float(np.interp(c["s_apex"], np.arange(len(speeds["nominal"])) * STEP_M, speeds["nominal"])), 1),
            "fast": round(float(np.interp(c["s_apex"], np.arange(len(speeds["fast"])) * STEP_M, speeds["fast"])), 1)}
    # 3. Obstáculos + junctions + verticales.
    obstacles = extract_obstacles(bmf_stage, np.array([s["center"] for s in geo["sections"]]), left, right,
                                  step_m=STEP_M, cfg=cfg)
    link_obstacles(obstacles, curves, cfg)
    junctions = []
    jk = 0
    secs = geo["sections"]
    i = 0
    while i < len(secs):
        if secs[i].get("is_junction"):
            j0 = i
            j = j0
            while j + 1 < len(secs) and secs[j + 1].get("is_junction"):
                j += 1
            jk += 1
            junctions.append({"id": f"JCT_{jk:03d}", "type": "junction",
                              "s_start": float(secs[j0]["s_m"]), "s_end": float(secs[j]["s_m"]),
                              "s": float((secs[j0]["s_m"] + secs[j]["s_m"]) / 2),
                              "fields": {"junction": 1, "caution": 1},
                              "modifiers": ["junction"], "review_reasons": ["corridor_junction"],
                              "linked_hazard_ids": [], "status": "pending"})
            i = j + 1
        else:
            i += 1
    # Filtrar junctions del corredor: si el coche sigue recto (fuera de una curva de giro >= 55°),
    # un ensanchamiento lateral del camino secundario no debe cantarse como "Turn/Junction".
    valid_junctions = []
    for j in junctions:
        host_c = next((c for c in curves if c["s_start"] - 25.0 <= j["s"] <= c["s_end"] + 25.0), None)
        if host_c is not None and host_c.get("angle_deg", 0.0) >= 55.0:
            host_c["is_junction_turn"] = True
            j["status"] = "absorbed"
            j["linked_curve"] = host_c["id"]
        else:
            j["status"] = "dropped_low_priority"
            j["priority"] = 30
            j["review_reasons"] = ["cruce pasante sin desvío de ruta: no se canta 'Turn'"]
    junctions = valid_junctions
    verticals = []
    for v_i, v in enumerate(detect_vertical(geo, speeds, cfg), 1):
        verticals.append({"id": f"VRT_{v_i:03d}", **v,
                          "fields": {"surface": 1, "hazard": 1 if v["type"] == "jump" else 2,
                                     "caution": 1 if v["type"] == "jump" else 0},
                          "modifiers": [], "review_reasons": [f"gamma={v['gamma']}"],
                          "linked_hazard_ids": [], "status": "pending"})
    # Absorber obstáculos linked de baja cardinalidad en sus curvas.
    # Los troncos (mobiliario continuo del bosque, no postes discretos) solo
    # se absorben si implican dont_cut real; si no, quedan auditados como
    # roadside_furniture sin contaminar la palabra con inside/outside.
    for c in curves:
        c["_hazards"] = []
    for ob in obstacles:
        if ob.get("linked_curve"):
            is_trunk = _is_trunk(str(ob.get("label", "")))
            if is_trunk and not ob.get("dont_cut"):
                ob["status"] = "roadside_furniture"
                ob["review_reasons"] = ["tronco sin dont_cut: no se canta inside/outside"]
                continue
            if ob["type"] == "post" and float(ob.get("d_edge", 99.0)) > cfg.post_max_edge_m:
                ob["status"] = "dropped_low_priority"
                ob["review_reasons"] = [f"poste lejos del borde ({ob.get('d_edge')}m)"]
                continue
            host = next((c for c in curves if c["id"] == ob["linked_curve"]), None)
            if host is None:
                ob["status"] = "orphaned_link"
                ob["review_reasons"] = [f"curva {ob['linked_curve']} no existe"]
                continue
            hz = {"rock": 4, "post": 5, "ditch": 7, "gate": 6, "junction": 0}.get(ob["type"], 0)
            side = 1 if ob.get("relative_side") == "inside" else 2
            host["_hazards"].append({"id": ob["id"], "hz": hz, "side": side,
                                     "no_cut": bool(ob.get("dont_cut")),
                                     "turn": 3 if ob["type"] == "gate" else 0,
                                     "priority": ob.get("priority", 60),
                                     "label": ob.get("label", "")})
            ob["status"] = "linked"
    # Absorber crestas en curvas cercanas (ventana [-35m, +15m]); descartar crestas sueltas en recta
    for v in verticals:
        for c in curves:
            if c["s_start"] - 35.0 <= v["s"] <= c["s_end"] + 15.0:
                if v["type"] == "jump":
                    c["jump_here"] = True
                else:
                    c["crest_here"] = True
                v["status"] = "absorbed"
                v["linked_curve"] = c["id"]
                break
        if v.get("status") != "absorbed" and v["type"] == "crest":
            # Una cresta simple en recta sin salto ("Over Crest" sin curva) no se canta suelta
            v["status"] = "dropped_low_priority"
            v["priority"] = 30
            v["review_reasons"] = ["crest en recta sin salto: omitido del canal de voz"]
    standalone = group_standalone_hazards(
        [o for o in obstacles if o.get("linked_curve") is None])
    # En recta (standalone), SOLO se permiten portones ('gate'), cruces ('junction')
    # o peligros pegados a la calzada (d_edge <= dont_cut: roca/poste/zanja que
    # invade la trazada aunque no haya curva enlazada). El resto no se canta suelto.
    for ob in standalone:
        if _is_trunk(str(ob.get("label", ""))):
            ob["status"] = "roadside_furniture"
            ob["review_reasons"] = ["alineacion continua de troncos: no se canta suelto"]
        elif ob["type"] in ("rock", "post", "ditch") and float(ob.get("d_edge", 99.0)) > cfg.dont_cut_edge_m:
            ob["status"] = "dropped_low_priority"
            ob["review_reasons"] = ["peligro lateral en recta sin curva: no se canta suelto"]
    seq = build_main_sequence(curves, junctions, verticals,
                              [o for o in standalone if o.get("status") not in ("dropped_low_priority", "roadside_furniture")], cfg)
    n_dropped_low = sum(1 for o in standalone if o.get("status") == "dropped_low_priority")
    # 4. Distancias + palabras + plan temporal.
    cum = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(route, axis=0), axis=1))])
    s_grid = np.arange(len(speeds["nominal"])) * STEP_M
    t_of_s = speeds["t"]
    for e in seq:
        e.setdefault("deg_level", 0)
        e.setdefault("review_reasons", [])
    # distance class v2 sobre gap previo (toda la secuencia emitida).
    def _is_curve(ev: Dict[str, Any]) -> bool:
        return "severity_effective" in ev
    for i, e in enumerate(seq):
        gap = e.get("gap_prev_m", 0.0) if i else 0.0
        bc = bool(i) and _is_curve(seq[i - 1]) and _is_curve(e)
        e["distance"] = 0 if i == 0 else _distance_class(gap, both_curves=bc)
    runtime_calls, dropped = plan_and_emit(seq, cum, t_of_s, s_grid, cfg)
    # Enriquecer palabras con metadatos del evento para el runtime.
    by_ev: Dict[str, Dict[str, Any]] = {e.get("id", ""): e for e in seq}
    for w in runtime_calls:
        e = by_ev.get(w.get("event_id", ""), {})
        w["curve_id"] = e.get("id", "EVT_%03d" % w["call_index"])
        for k in ("s_start", "s_end"):
            if w.get(k) is None:
                w[k] = e.get(k, e.get("s", 0.0))
        w["kind_str"] = e.get("kind_str", e.get("type", "hazard"))
        w["direction"] = e.get("direction")
        w["link"] = e.get("link")
    # Trazabilidad de peligros absorbidos/emitidos vía multi-palabra.
    idx_by_event: Dict[str, List[int]] = {}
    for w in runtime_calls:
        idx_by_event.setdefault(str(w.get("event_id", "")), []).append(w["call_index"])
    for ob in list(obstacles) + [v for v in verticals if v.get("linked_curve")] + [j for j in junctions if j.get("linked_curve")]:
        if ob.get("status") in ("roadside_furniture", "dropped_low_priority", "grouped"):
            continue  # auditado y descartado del canal de voz: no tocar
        if not ob.get("linked_curve"):
            continue
        hits = idx_by_event.get(ob["id"], [])
        if hits:
            ob["status"] = "emitted"
            ob["emitted_call_ids"] = hits
        else:
            parent = ob["linked_curve"]
            ob["status"] = "absorbed"
            ob["emitted_call_ids"] = list(idx_by_event.get(parent, []))
            ob["review_reasons"] = ob.get("review_reasons", []) + [f"absorbido en {parent}"]
    for c in detected_curves:
        if c.get("status") == "grouped_into":
            c["emitted_call_ids"] = list(idx_by_event.get(c.get("grouped_into", ""), []))
            c.setdefault("review_reasons", []).append(f"cubierta por {c.get('grouped_into')}")
    # 5. Candidatos con trazabilidad total (incluye absorbidas por agrupado).
    candidates: List[Dict[str, Any]] = []
    for c in detected_curves:
        station_apex = c["node_apex"]
        candidates.append({
            "id": c["id"], "type": "curve", "s_start": c["s_start"], "s_apex": c["s_apex"],
            "s_end": c["s_end"], "guide_node_start": station_apex, "guide_node_end": station_apex,
            "link": c.get("link"),
            "direction": c["direction"], "radius_center_min_m": c["radius_apex_c"],
            "radius_opt_min_m": c["radius_second_half"], "angle_deg": c["angle_deg"],
            "width_min_m": 0.0, "grade_p85_down_pct": c.get("grade_p85_down_pct", 0.0),
            "camber_apex_deg": c.get("camber_apex_eff_deg", 0.0),
            "severity_geometric": c["severity_geometric"], "severity_effective": c["severity_effective"],
            "modifiers": c["modifiers"], "linked_hazard_ids": c.get("linked_hazard_ids", []),
            "speed_scenarios_ms": c.get("speed_scenarios_ms", {}),
            "priority": c.get("priority", 0), "confidence": "high",
            "status": c.get("status", "pending"),
            "emitted_call_ids": c.get("emitted_call_ids", []),
            "review_reasons": c.get("review_reasons", [])})
    for ob in obstacles:
        candidates.append({
            "id": ob["id"], "type": ob["type"], "s_start": ob["s"], "s_apex": ob["s"], "s_end": ob["s"],
            "guide_node_start": ob.get("station", 0), "guide_node_end": ob.get("station", 0),
            "direction": None, "radius_center_min_m": 0.0, "radius_opt_min_m": 0.0,
            "angle_deg": 0.0, "width_min_m": 0.0, "grade_p85_down_pct": 0.0, "camber_apex_deg": 0.0,
            "severity_geometric": 0, "severity_effective": 0, "modifiers": [],
            "linked_hazard_ids": [], "speed_scenarios_ms": {},
            "priority": ob.get("priority", 60), "confidence": "high",
            "status": ob.get("status", "pending"),
            "emitted_call_ids": ob.get("emitted_call_ids", []),
            "review_reasons": [f"side={ob.get('side')} d_edge={ob.get('d_edge')}"] + ob.get("review_reasons", []),
            "label": ob.get("label", ""),
            "side": ob.get("side"),
            "d_edge": ob.get("d_edge"),
            "relative_side": ob.get("relative_side"), "dont_cut": bool(ob.get("dont_cut", False))})
    for v in verticals:
        candidates.append({
            "id": v["id"], "type": v["type"], "s_start": v["s"], "s_apex": v["s"], "s_end": v["s"],
            "guide_node_start": v.get("station", 0), "guide_node_end": v.get("station", 0),
            "direction": None, "radius_center_min_m": 0.0, "radius_opt_min_m": 0.0,
            "angle_deg": 0.0, "width_min_m": 0.0, "grade_p85_down_pct": 0.0, "camber_apex_deg": 0.0,
            "severity_geometric": 0, "severity_effective": 0, "modifiers": [],
            "linked_hazard_ids": [], "speed_scenarios_ms": {},
            "priority": v.get("priority", 70), "confidence": "high",
            "status": v.get("status", "pending"),
            "emitted_call_ids": v.get("emitted_call_ids", []),
            "review_reasons": v.get("review_reasons", [])})
    for j in junctions:
        candidates.append({
            "id": j["id"], "type": "junction", "s_start": j["s_start"], "s_apex": j["s"],
            "s_end": j["s_end"], "guide_node_start": 0, "guide_node_end": 0,
            "direction": None, "radius_center_min_m": 0.0, "radius_opt_min_m": 0.0,
            "angle_deg": 0.0, "width_min_m": 0.0, "grade_p85_down_pct": 0.0, "camber_apex_deg": 0.0,
            "severity_geometric": 0, "severity_effective": 0, "modifiers": j.get("modifiers", []),
            "linked_hazard_ids": [], "speed_scenarios_ms": {},
            "priority": j.get("priority", 80), "confidence": "high",
            "status": j.get("status", "pending"),
            "emitted_call_ids": j.get("emitted_call_ids", []),
            "review_reasons": j.get("review_reasons", [])})
    authoring = [dict(c) for c in candidates if c.get("status") == "emitted"]
    run_doc = export_documents(runtime_calls, candidates, authoring,
                               country_name, stage_name, Path(output_dir))
    n_curves = sum(1 for w in runtime_calls if w.get("fields", {}).get("kind", 0) in (1, 2, 3, 4, 5, 6, 7, 8))
    print(f"[PacenoteAnalyzer v3] {len(curves)} curvas + {len(runtime_calls) - n_curves} multi-palabra/peligros = "
          f"{len(runtime_calls)} llamadas ({sum(1 for e in seq if e.get('link') == 'into')} into, "
          f"{len(dropped)} descartadas) -> {output_dir}")
    return run_doc


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Analizador de pacenotes CMR2 v3")
    parser.add_argument("--route-json", type=Path, required=True)
    parser.add_argument("--bmf", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--country", type=str, default="russia")
    parser.add_argument("--stage", type=str, default="stage1")
    parser.add_argument("--geo-json", type=Path, default=None)
    args = parser.parse_args()

    with open(args.route_json, "r", encoding="utf-8") as fh:
        rdata = json.load(fh)
    stage_bmf = bmf_parser.parse_bmf(args.bmf)
    analyze_and_build_pacenotes(
        rdata["points"], stage_bmf, args.output_dir,
        country_name=args.country, stage_name=args.stage,
        geo_json=args.geo_json,
    )


