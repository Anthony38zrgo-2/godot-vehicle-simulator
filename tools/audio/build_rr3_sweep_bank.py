#!/usr/bin/env python3
"""Build non-destructive Method A sweep-granular manifests for all 11 vehicles using rr3-bank.

This tool NEVER modifies any .wav file under game/sounds/banks/rr3-bank.
It analyzes the continuous accel/decel sweeps and idle loops, extracts accurate
RPM(t) lookup tables, local RMS envelopes, cycle lengths, and seamless loop windows,
and emits per-vehicle schema_version=4 manifests under:
  game/sounds/banks/rr3-bank/vehicles/<vehicle_id>.json
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import wave
from pathlib import Path
from typing import Any

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
RR3_ROOT = REPO_ROOT / "game" / "sounds" / "banks" / "rr3-bank"
VEHICLES_DATA_ROOT = REPO_ROOT / "game" / "data" / "vehicles"
OUT_DIR = RR3_ROOT / "vehicles"


# Approved 11-car assignment table (zero duplicate sweep+idle combos, uses all 8 sub-banks
# plus v6_01_v2, all 4 racecar_idle variants, and i4_05_idle2).
VEHICLE_CONFIGS: list[dict[str, Any]] = [
    {
        "vehicle_id": "rt-lancia-stratos",
        "powertrain_path": VEHICLES_DATA_ROOT / "rt" / "rt-lancia-stratos" / "powertrain.json",
        "legacy_manifest": REPO_ROOT / "game" / "sounds" / "banks" / "gt3-bank" / "stratos-rally-car" / "manifest.json",
        "subbank": "v6_01_v2",
        "cylinders": 6,
        "accel_wav": "v6_01/v6_01_v2_accel.wav",
        "decel_wav": "v6_01/v6_01_v2_decel.wav",
        "idle_wav": "v6_01/v6_01_racecar_idle.wav",
        "sweep_rpm_scale": 1.00,
        "pitch_character": 1.00,
        "eq": {
            "hpf_hz": 45.0,
            "lpf_hz": 11500.0,
            "engine_bands_db": [0.0, 0.5, 0.5, 1.0, 1.5, 2.5, 2.5, 1.5, 0.0, -1.0],
            "exhaust_bands_db": [1.5, 2.0, 1.0, 0.5, 0.5, 1.5, 2.0, 0.5, -1.5, -3.0],
        },
        "character_note": "Ferrari Dino 2.4L V6 DOHC 24v; uses v6_01_v2 + v6_01_racecar_idle with 1.5-4kHz bite",
    },
    {
        "vehicle_id": "lancia_fulvia_1600_hf",
        "manifest_name": "lancia-fulvia",
        "powertrain_path": VEHICLES_DATA_ROOT / "lancia-fulvia" / "powertrain.json",
        "legacy_manifest": REPO_ROOT / "game" / "sounds" / "banks" / "gt3-bank" / "trueno-gt-apex" / "manifest.json",
        "subbank": "v6_01",
        "cylinders": 6,
        "accel_wav": "v6_01/v6_01_accel.wav",
        "decel_wav": "v6_01/v6_01_decel.wav",
        "idle_wav": "v6_01/v6_01_idle.wav",
        "sweep_rpm_scale": 1.03,
        "pitch_character": 1.00,
        "eq": {
            "hpf_hz": 65.0,
            "lpf_hz": 6200.0,
            "engine_bands_db": [-1.5, 0.0, 1.5, 3.0, 3.0, 1.5, -0.5, -2.5, -4.5, -6.0],
            "exhaust_bands_db": [0.0, 1.5, 2.5, 2.5, 1.5, -0.5, -2.5, -4.5, -6.5, -8.0],
        },
        "character_note": "Lancia Fulvia 1.6 HF narrow-angle V4 11deg20; asymmetric half-order pulse from v6_01 + 350-900Hz Solex emphasis",
    },
    {
        "vehicle_id": "rt-alfa-giulia-gta",
        "powertrain_path": VEHICLES_DATA_ROOT / "rt" / "rt-alfa-giulia-gta" / "powertrain.json",
        "legacy_manifest": REPO_ROOT / "game" / "sounds" / "banks" / "gt3-bank" / "civic-type-r" / "manifest.json",
        "subbank": "i4_04",
        "cylinders": 4,
        "accel_wav": "i4_04/i4_04_accel.wav",
        "decel_wav": "i4_04/i4_04_decel.wav",
        "idle_wav": "i4_04/i4_04_idle.wav",
        "sweep_rpm_scale": 1.05,
        "pitch_character": 1.00,
        "eq": {
            "hpf_hz": 55.0,
            "lpf_hz": 10500.0,
            "engine_bands_db": [-0.5, 0.0, 0.5, 1.0, 2.5, 3.0, 2.0, 0.5, -0.5, -1.5],
            "exhaust_bands_db": [1.0, 1.5, 1.0, 0.5, 1.5, 2.0, 1.0, -1.0, -2.5, -4.0],
        },
        "character_note": "Alfa Romeo Giulia Sprint GTA 1.6L Twin Cam DOHC; brightest i4_04 with Weber 800-2000Hz metallic ring",
    },
    {
        "vehicle_id": "rt-lotus-cortina",
        "powertrain_path": VEHICLES_DATA_ROOT / "rt" / "rt-lotus-cortina" / "powertrain.json",
        "legacy_manifest": REPO_ROOT / "game" / "sounds" / "banks" / "gt3-bank" / "motor-sport-elise" / "manifest.json",
        "subbank": "i4_01",
        "cylinders": 4,
        "accel_wav": "i4_01/i4_01_accel.wav",
        "decel_wav": "i4_01/i4_01_decel.wav",
        "idle_wav": "i4_01/i4_01_racecar_idle.wav",
        "sweep_rpm_scale": 1.04,
        "pitch_character": 0.96,
        "eq": {
            "hpf_hz": 50.0,
            "lpf_hz": 9200.0,
            "engine_bands_db": [0.0, 0.5, 1.0, 1.0, 1.5, 2.0, 1.0, 0.0, -1.5, -3.0],
            "exhaust_bands_db": [1.5, 2.0, 1.5, 0.5, 1.0, 1.0, -0.5, -2.0, -3.5, -5.0],
        },
        "character_note": "Ford Lotus Cortina Mk1 1.6L Twin Cam; i4_01 + racecar_idle pitched 0.96x for authentic British race twin-cam",
    },
    {
        "vehicle_id": "rt-alpine-a110",
        "powertrain_path": VEHICLES_DATA_ROOT / "rt" / "rt-alpine-a110" / "powertrain.json",
        "legacy_manifest": REPO_ROOT / "game" / "sounds" / "banks" / "gt3-bank" / "vitz-rs" / "manifest.json",
        "subbank": "i4_02",
        "cylinders": 4,
        "accel_wav": "i4_02/i4_02_accel.wav",
        "decel_wav": "i4_02/i4_02_decel.wav",
        "idle_wav": "i4_02/i4_02_racecar_idle.wav",
        "sweep_rpm_scale": 0.95,
        "pitch_character": 1.03,
        "eq": {
            "hpf_hz": 55.0,
            "lpf_hz": 10000.0,
            "engine_bands_db": [-0.5, 0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 1.5, 0.0, -1.5],
            "exhaust_bands_db": [1.0, 1.5, 1.0, 0.0, 1.0, 2.0, 2.5, 1.0, -1.0, -3.0],
        },
        "character_note": "Renault Alpine A110 1600S; rear-mounted i4_02 + racecar_idle + crispy high-harmonic overrun",
    },
    {
        "vehicle_id": "ford_escort_rs2000",
        "manifest_name": "ford-escort-rs2000",
        "powertrain_path": VEHICLES_DATA_ROOT / "ford-escort-rs2000" / "powertrain.json",
        "legacy_manifest": REPO_ROOT / "game" / "sounds" / "banks" / "EscortRS1600" / "manifest.json",
        "subbank": "i4_06",
        "cylinders": 4,
        "accel_wav": "i4_06/i4_06_accel.wav",
        "decel_wav": "i4_06/i4_06_decel.wav",
        "idle_wav": "i4_06/i4_06_idle.wav",
        "sweep_rpm_scale": 0.96,
        "pitch_character": 1.00,
        "whine_override": [
            "res://sounds/banks/EscortRS1600/whinelo.wav",
            "res://sounds/banks/EscortRS1600/whinehi.wav",
        ],
        "engine_position_override": [0.0, 0.55, -0.8],
        "exhaust_position_override": [0.0, 0.20, 1.50],
        "eq": {
            "hpf_hz": 45.0,
            "lpf_hz": 8800.0,
            "engine_bands_db": [0.5, 1.0, 1.5, 2.0, 2.0, 1.0, 0.5, -0.5, -2.0, -3.5],
            "exhaust_bands_db": [2.0, 2.5, 1.5, 1.0, 0.5, 0.5, -0.5, -2.0, -3.5, -5.0],
        },
        "character_note": "Ford Escort RS2000 2.0L Pinto; muscular i4_06 250-1500Hz mid punch + crisp 16.5s overrun",
    },
    {
        "vehicle_id": "rt-opel-kadett",
        "powertrain_path": VEHICLES_DATA_ROOT / "rt" / "rt-opel-kadett" / "powertrain.json",
        "legacy_manifest": REPO_ROOT / "game" / "sounds" / "banks" / "gt3-bank" / "mx-5-18-rs" / "manifest.json",
        "subbank": "4cyl_01",
        "cylinders": 4,
        "accel_wav": "4cyl_01/4cyl_01_accel.wav",
        "decel_wav": "4cyl_01/4cyl_01_decel.wav",
        "idle_wav": "4cyl_01/4cyl_01_racecar_idle.wav",
        "sweep_rpm_scale": 1.02,
        "pitch_character": 1.02,
        "eq": {
            "hpf_hz": 50.0,
            "lpf_hz": 8500.0,
            "engine_bands_db": [0.5, 1.5, 2.0, 2.0, 1.0, 0.5, 0.0, -1.0, -2.5, -4.0],
            "exhaust_bands_db": [2.0, 2.5, 2.0, 1.0, 0.0, -0.5, -1.0, -2.5, -4.0, -6.0],
        },
        "character_note": "Opel Kadett B Rallye 1900 CIH; 4cyl_01 + 4cyl_01_racecar_idle with mid-bass rally thump",
    },
    {
        "vehicle_id": "rt-saab-96-v4",
        "powertrain_path": VEHICLES_DATA_ROOT / "rt" / "rt-saab-96-v4" / "powertrain.json",
        "legacy_manifest": REPO_ROOT / "game" / "sounds" / "banks" / "gt3-bank" / "peugeot-206-s16" / "manifest.json",
        "subbank": "i4_03",
        "cylinders": 4,
        "accel_wav": "i4_03/i4_03_accel.wav",
        "decel_wav": "i4_03/i4_03_decel.wav",
        "idle_wav": "i4_03/i4_03_idle.wav",
        "sweep_rpm_scale": 0.98,
        "pitch_character": 0.95,
        "eq": {
            "hpf_hz": 38.0,
            "lpf_hz": 5200.0,
            "engine_bands_db": [2.0, 3.5, 3.0, 1.0, -0.5, -1.5, -3.0, -4.5, -6.0, -8.0],
            "exhaust_bands_db": [3.5, 4.0, 2.5, 0.5, -1.5, -3.0, -4.5, -6.0, -8.0, -10.0],
        },
        "character_note": "Saab 96 V4 Ford Cologne 1.7L; i4_03 heaviest cam lope (CV=0.580) + 95% sub-250Hz overrun rumble",
    },
    {
        "vehicle_id": "rt-fiat-abarth-1000",
        "powertrain_path": VEHICLES_DATA_ROOT / "rt" / "rt-fiat-abarth-1000" / "powertrain.json",
        "legacy_manifest": REPO_ROOT / "game" / "sounds" / "banks" / "gt3-bank" / "civic-sir-ii" / "manifest.json",
        "subbank": "i4_05",
        "cylinders": 4,
        "accel_wav": "i4_05/i4_05_accel.wav",
        "decel_wav": "i4_05/i4_05_decel.wav",
        "idle_wav": "i4_05/i4_05_idle2.wav",
        "sweep_rpm_scale": 0.94,
        "pitch_character": 1.10,
        "eq": {
            "hpf_hz": 115.0,
            "lpf_hz": 11000.0,
            "engine_bands_db": [-6.0, -3.5, 0.0, 1.5, 2.5, 3.0, 2.0, 1.0, -0.5, -2.0],
            "exhaust_bands_db": [-5.0, -2.0, 0.5, 1.5, 2.5, 2.5, 1.0, -0.5, -2.5, -4.5],
        },
        "character_note": "Fiat Abarth 1000 TC; small 982cc high-rev block pitched +10% with 115Hz HPF and i4_05_idle2",
    },
    {
        "vehicle_id": "rt-mini-cooper-s",
        "powertrain_path": VEHICLES_DATA_ROOT / "rt" / "rt-mini-cooper-s" / "powertrain.json",
        "legacy_manifest": REPO_ROOT / "game" / "sounds" / "banks" / "gt3-bank" / "mini-cooper" / "manifest.json",
        "subbank": "i4_05",
        "cylinders": 4,
        "accel_wav": "i4_05/i4_05_accel.wav",
        "decel_wav": "i4_05/i4_05_decel.wav",
        "idle_wav": "i4_05/i4_05_idle.wav",
        "sweep_rpm_scale": 0.92,
        "pitch_character": 0.92,
        "eq": {
            "hpf_hz": 55.0,
            "lpf_hz": 4400.0,
            "engine_bands_db": [0.5, 1.5, 2.5, 3.5, 1.5, -1.0, -3.0, -5.0, -7.0, -9.0],
            "exhaust_bands_db": [2.0, 2.5, 2.5, 2.0, 0.0, -2.5, -4.5, -6.5, -8.5, -10.0],
        },
        "character_note": "Morris Mini Cooper S 1275 A-Series; i4_05 pitched 0.92x + i4_05_idle + 450-850Hz pushrod nasal growl",
    },
    {
        "vehicle_id": "rt-volvo-amazon",
        "powertrain_path": VEHICLES_DATA_ROOT / "rt" / "rt-volvo-amazon" / "powertrain.json",
        "legacy_manifest": REPO_ROOT / "game" / "sounds" / "banks" / "gt3-bank" / "new-beetle-20" / "manifest.json",
        "subbank": "4cyl_01",
        "cylinders": 4,
        "accel_wav": "4cyl_01/4cyl_01_accel.wav",
        "decel_wav": "4cyl_01/4cyl_01_decel.wav",
        "idle_wav": "4cyl_01/4cyl_01_idle.wav",
        "sweep_rpm_scale": 0.94,
        "pitch_character": 0.91,
        "eq": {
            "hpf_hz": 38.0,
            "lpf_hz": 2600.0,
            "engine_bands_db": [2.5, 3.5, 2.0, 0.5, -1.0, -2.5, -5.0, -8.0, -10.0, -12.0],
            "exhaust_bands_db": [4.0, 3.5, 1.5, 0.0, -2.0, -4.0, -7.0, -10.0, -12.0, -14.0],
        },
        "character_note": "Volvo 122 S Amazon B18/B20 OHV; 4cyl_01 pitched 0.91x + slow heavy idle + warm 2.6kHz LPF",
    },
]


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def load_wav_mono_f64(path: Path) -> tuple[int, np.ndarray]:
    with wave.open(str(path), "rb") as w:
        sr = w.getframerate()
        ch = w.getnchannels()
        sw = w.getsampwidth()
        nf = w.getnframes()
        raw = w.readframes(nf)
    if ch != 1 or sw != 2:
        raise ValueError(f"Expected mono PCM16 for {path}, got ch={ch} sw={sw}")
    x = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    return sr, x


def score_comb(mag_log: np.ndarray, freqs: np.ndarray, rpm_grid: np.ndarray, is_v6: bool) -> np.ndarray:
    df = freqs[1] - freqs[0]
    m = mag_log.copy()
    # Mask sub-28 Hz microphone wind rumble while preserving down to ~1700 RPM crank (28 Hz)
    m[freqs < 28.0] = 0.0

    def peak_at(order_mult: float) -> np.ndarray:
        f = rpm_grid * (order_mult / 60.0)
        idx = np.clip(np.round(f / df).astype(int), 1, len(m) - 2)
        return np.where(
            (f >= 28.0) & (f <= 2400.0),
            np.maximum(m[idx], np.maximum(m[idx - 1], m[idx + 1])),
            0.0,
        )

    if is_v6:
        return (
            0.55 * peak_at(1.0)
            + 1.40 * peak_at(1.5)
            + 0.25 * peak_at(2.0)
            + 1.55 * peak_at(3.0)
            + 0.90 * peak_at(4.5)
            + 0.80 * peak_at(6.0)
            + 0.40 * peak_at(7.5)
            + 0.45 * peak_at(9.0)
            - 0.90 * peak_at(0.75)
            - 0.50 * peak_at(2.25)
        )
    p1 = peak_at(1.0)
    p2 = peak_at(2.0)
    p3 = peak_at(3.0)
    p4 = peak_at(4.0)
    p6 = peak_at(6.0)
    p8 = peak_at(8.0)
    return (
        0.65 * p1
        + 1.85 * p2
        + 0.35 * p3
        + 0.95 * p4
        + 0.55 * p6
        + 0.35 * p8
        - 0.70 * np.maximum(0.0, p4 - p2)
        - 0.45 * peak_at(0.5)
    )


def dp_monotone(obs: np.ndarray, rpm_grid: np.ndarray, max_step_down: float, max_step_up: float) -> np.ndarray:
    t_len = obs.shape[0]
    log_rpm = np.log(rpm_grid)
    diff = log_rpm[:, None] - log_rpm[None, :]
    in_band = (diff >= max_step_down) & (diff <= max_step_up)
    trans = np.where(in_band, -((diff / 0.018) ** 2) * 2.5, -1e6)
    dp = np.zeros_like(obs)
    bp = np.zeros((t_len, len(rpm_grid)), dtype=np.int32)
    dp[0] = obs[0]
    for t in range(1, t_len):
        cand = dp[t - 1][None, :] + trans
        best_prev = np.argmax(cand, axis=1)
        dp[t] = obs[t] + cand[np.arange(len(rpm_grid)), best_prev]
        bp[t] = best_prev
    path = np.zeros(t_len, dtype=np.int32)
    path[-1] = int(np.argmax(dp[-1]))
    for t in range(t_len - 1, 0, -1):
        path[t - 1] = int(bp[t, path[t]])
    return rpm_grid[path]


def smooth_segment_frames(
    times_s: np.ndarray,
    rpms: np.ndarray,
    frms: np.ndarray,
    increasing: bool,
) -> list[dict[str, float]]:
    """Convert raw tracked frames into a smooth strictly monotonic curve."""
    # Smooth slightly with 3-tap boxcar inside valid segment to suppress single-bin quantization steps
    kernel = np.array([0.25, 0.5, 0.25])
    if len(rpms) >= 5:
        padded = np.pad(rpms, 1, mode="edge")
        sm = np.convolve(padded, kernel, mode="valid")
    else:
        sm = rpms.copy()

    # Enforce strict monotonicity by running cumulative envelope + linear re-anchor
    if increasing:
        mono = np.maximum.accumulate(sm)
    else:
        mono = np.minimum.accumulate(sm)

    # Keep only interior active region (trim tiny 0.04s edge fades if RMS < 30% of median)
    med_rms = float(np.median(frms))
    valid = np.where(frms >= med_rms * 0.28)[0]
    if len(valid) >= 4:
        i0, i1 = int(valid[0]), int(valid[-1]) + 1
    else:
        i0, i1 = 0, len(times_s)

    pts = []
    for k in range(i0, i1):
        pts.append({
            "time_s": float(times_s[k]),
            "rpm": float(mono[k]),
            "rms": float(frms[k]),
        })
    return pts


def build_uniform_rpm_table(
    segments: list[list[dict[str, float]]],
    increasing: bool,
    step_rpm: float = 50.0,
) -> tuple[float, float, list[dict[str, float]]]:
    """Sample analyzed monotonic segment(s) onto a uniform RPM grid."""
    all_pts = [p for seg in segments for p in seg]
    rpm_min = min(p["rpm"] for p in all_pts)
    rpm_max = max(p["rpm"] for p in all_pts)
    # Trim extreme 30 RPM edges to keep lookahead safely inside active audio
    g_lo = math.ceil((rpm_min + 25.0) / step_rpm) * step_rpm
    g_hi = math.floor((rpm_max - 25.0) / step_rpm) * step_rpm
    if g_hi <= g_lo:
        g_lo, g_hi = rpm_min, rpm_max

    grid = np.arange(g_lo, g_hi + 0.5 * step_rpm, step_rpm)

    # Sort each segment ascending in RPM for clean np.interp
    seg_arrays = []
    for seg_id, seg in enumerate(segments):
        s_sorted = sorted(seg, key=lambda p: p["rpm"])
        r_arr = np.array([p["rpm"] for p in s_sorted], dtype=np.float64)
        t_arr = np.array([p["time_s"] for p in s_sorted], dtype=np.float64)
        e_arr = np.array([p["rms"] for p in s_sorted], dtype=np.float64)
        # De-duplicate identical r_arr values if plateaued
        _, uniq_idx = np.unique(r_arr, return_index=True)
        seg_arrays.append((seg_id, r_arr[uniq_idx], t_arr[uniq_idx], e_arr[uniq_idx]))

    rows: list[dict[str, float]] = []
    for r in grid:
        # Pick covering segment; if inside a tiny inter-segment gap, clamp to closest segment endpoint
        chosen = None
        best_dist = 1e18
        for seg_id, r_arr, t_arr, e_arr in seg_arrays:
            if r_arr[0] <= r <= r_arr[-1]:
                t_val = float(np.interp(r, r_arr, t_arr))
                e_val = float(np.interp(r, r_arr, e_arr))
                r_ref = float(r)
                chosen = (seg_id, t_val, e_val, r_ref)
                break
            d = min(abs(r - r_arr[0]), abs(r - r_arr[-1]))
            if d < best_dist:
                best_dist = d
                if r < r_arr[0]:
                    chosen = (seg_id, float(t_arr[0]), float(e_arr[0]), float(r_arr[0]))
                else:
                    chosen = (seg_id, float(t_arr[-1]), float(e_arr[-1]), float(r_arr[-1]))
        assert chosen is not None
        seg_id, t_val, e_val, r_ref = chosen
        rows.append({
            "rpm": round(float(r), 1),
            "ref_rpm": round(r_ref, 1),
            "time_s": round(t_val, 4),
            "rms": round(e_val, 5),
            "seg": int(seg_id),
        })
    return round(float(g_lo), 1), round(float(g_hi), 1), rows


def analyze_sweep_pair(subbank: str, acc_path: Path, dec_path: Path) -> dict[str, Any]:
    is_v6 = subbank.startswith("v6")
    rpm_grid = np.geomspace(1450.0 if is_v6 else 1350.0, 12200.0 if is_v6 else 8700.0, 260)

    def frame_features(x: np.ndarray, sr: int) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        win_n, hop = 4096, int(0.04 * sr)
        hann = np.hanning(win_n)
        freqs = np.fft.rfftfreq(win_n, 1.0 / sr)
        centers = np.arange(win_n // 2, len(x) - win_n // 2, hop)
        obs = np.zeros((len(centers), len(rpm_grid)), dtype=np.float64)
        frms = np.zeros(len(centers), dtype=np.float64)
        for ti, c in enumerate(centers):
            seg = x[c - win_n // 2 : c + win_n // 2] * hann
            frms[ti] = math.sqrt(float(np.mean(seg * seg)) * 2.6667)  # Hann RMS compensation
            mag = np.abs(np.fft.rfft(seg))
            ref = float(np.percentile(mag[(freqs >= 35.0) & (freqs <= 2500.0)], 96)) + 1e-9
            obs[ti] = score_comb(np.log1p((mag / ref) * 10.0), freqs, rpm_grid, is_v6)
        return centers / sr, obs, frms

    # 1. Accel
    sr_a, xa = load_wav_mono_f64(acc_path)
    ta, obsa, fa = frame_features(xa, sr_a)
    obsa[0, rpm_grid > 3000.0] -= 500.0
    obsa[-1, rpm_grid < (7400.0 if is_v6 else 6200.0)] -= 500.0
    ra = dp_monotone(obsa, rpm_grid, max_step_down=-0.004, max_step_up=0.045)
    acc_seg = smooth_segment_frames(ta, ra, fa, increasing=True)
    acc_min, acc_max, acc_rows = build_uniform_rpm_table([acc_seg], increasing=True, step_rpm=50.0)

    # 2. Decel (segment V6 around mid-file splice dip so zero grains span dead/splice area)
    top_rpm = float(ra[-1])
    sr_d, xd = load_wav_mono_f64(dec_path)
    td, obsd, fd = frame_features(xd, sr_d)

    if not is_v6:
        obsd[0, (rpm_grid < top_rpm * 0.85) | (rpm_grid > top_rpm * 1.06)] -= 1000.0
        rd = dp_monotone(obsd, rpm_grid, max_step_down=-0.022, max_step_up=0.003)
        # Trim flat bottom plateau if tail settles near noise floor
        dec_seg = smooth_segment_frames(td, rd, fd, increasing=False)
        dec_segs = [dec_seg]
    else:
        lo_i, hi_i = int(0.25 * len(td)), int(0.75 * len(td))
        dip_i = lo_i + int(np.argmin(fd[lo_i:hi_i]))
        # Stay >= 0.25s clear of the quiet splice dip
        s1_end = dip_i
        while s1_end > 12 and fd[s1_end - 1] < 0.085:
            s1_end -= 1
        s1_end = max(12, s1_end - 4)
        s2_start = dip_i
        while s2_start < len(td) - 12 and fd[s2_start] < 0.085:
            s2_start += 1
        s2_start = min(len(td) - 12, s2_start + 4)

        o1 = obsd[:s1_end].copy()
        o1[0, (rpm_grid < top_rpm * 0.85) | (rpm_grid > top_rpm * 1.06)] -= 1000.0
        r1 = dp_monotone(o1, rpm_grid, max_step_down=-0.035, max_step_up=0.004)
        seg1 = smooth_segment_frames(td[:s1_end], r1, fd[:s1_end], increasing=False)

        # Also check if Segment 2 has a late small splice bump near the very end (trim if RMS/pitch rises)
        o2 = obsd[s2_start:].copy()
        o2[0, (rpm_grid < 3000.0) | (rpm_grid > 5200.0)] -= 500.0
        r2 = dp_monotone(o2, rpm_grid, max_step_down=-0.035, max_step_up=0.004)
        # Trim last 0.8s on v6 decel seg2 to stay strictly inside clean sweep before end splice
        keep2 = max(12, len(r2) - int(0.8 / 0.04))
        seg2 = smooth_segment_frames(td[s2_start : s2_start + keep2], r2[:keep2], fd[s2_start : s2_start + keep2], increasing=False)
        dec_segs = [seg1, seg2]

    dec_min, dec_max, dec_rows = build_uniform_rpm_table(dec_segs, increasing=False, step_rpm=50.0)

    def summarize_seg_bounds(segs: list[list[dict[str, float]]]) -> list[dict[str, float]]:
        return [
            {
                "seg": i,
                "start_s": round(s[0]["time_s"], 4),
                "end_s": round(s[-1]["time_s"], 4),
                "rpm_start": round(s[0]["rpm"], 1),
                "rpm_end": round(s[-1]["rpm"], 1),
            }
            for i, s in enumerate(segs)
        ]

    return {
        "accel": {
            "sample_rate": sr_a,
            "duration_s": round(len(xa) / sr_a, 4),
            "target_rms": round(float(np.median(fa)), 5),
            "rpm_min": acc_min,
            "rpm_max": acc_max,
            "segments": summarize_seg_bounds([acc_seg]),
            "points": acc_rows,
        },
        "decel": {
            "sample_rate": sr_d,
            "duration_s": round(len(xd) / sr_d, 4),
            "target_rms": round(float(np.median(fd)), 5),
            "rpm_min": dec_min,
            "rpm_max": dec_max,
            "segments": summarize_seg_bounds(dec_segs),
            "points": dec_rows,
        },
    }


def analyze_idle(idle_path: Path, is_v6: bool) -> dict[str, Any]:
    sr, x = load_wav_mono_f64(idle_path)
    dur = len(x) / sr
    # High-res FFT for idle RPM estimation
    win_n = 16384
    hann = np.hanning(win_n)
    freqs = np.fft.rfftfreq(win_n, 1.0 / sr)
    segs = [x[i : i + win_n] * hann for i in range(0, len(x) - win_n + 1, win_n // 2)]
    mag = np.mean([np.abs(np.fft.rfft(s)) for s in segs], axis=0)
    m = mag / (np.max(mag[(freqs >= 18.0) & (freqs <= 240.0)]) + 1e-9)
    logm = np.log1p(m * 10.0)

    # Search idle RPM in [620, 1080] (firing harmonic comb; includes 8x/10x for strong even-order I4 matching)
    rpm_grid = np.linspace(620.0, 1080.0, 461)
    best_rpm = 850.0
    best_score = -1e9
    df = freqs[1] - freqs[0]
    for r in rpm_grid:
        if is_v6:
            orders = [(1.5, 0.7), (3.0, 1.4), (4.5, 0.7), (6.0, 1.2), (9.0, 0.7)]
            penalties = [(0.75, 0.9), (2.25, 0.6)]
        else:
            orders = [(1.0, 0.4), (2.0, 1.4), (4.0, 1.35), (6.0, 1.25), (8.0, 1.0), (10.0, 0.6)]
            penalties = [(0.5, 0.6), (1.33, 0.4), (1.5, 0.4)]
        sc = 0.0
        for o, wt in orders:
            idx = int(round((r * o / 60.0) / df))
            if 1 <= idx < len(logm) - 1:
                sc += wt * max(logm[idx - 1], logm[idx], logm[idx + 1])
        for o, wt in penalties:
            idx = int(round((r * o / 60.0) / df))
            if 1 <= idx < len(logm) - 1:
                sc -= wt * max(logm[idx - 1], logm[idx], logm[idx + 1])
        if sc > best_score:
            best_score = sc
            best_rpm = float(r)

    # Find seamless loop bounds via multi-start normalized correlation (~70ms ~ 2-3 firing cycles)
    w_len = int(0.07 * sr)
    best_start = int(0.25 * sr)
    best_end = len(x) - int(0.25 * sr)
    best_corr = -1e9
    step_s = int(0.025 * sr)
    for s_cand in range(int(0.15 * sr), int(0.85 * sr), step_s):
        s0 = s_cand
        while s0 < s_cand + int(0.04 * sr) and not (x[s0 - 1] <= 0.0 < x[s0]):
            s0 += 1
        ref_win = x[s0 : s0 + w_len]
        ref_norm = math.sqrt(float(np.sum(ref_win * ref_win))) + 1e-9
        search_lo = max(s0 + int(2.2 * sr), len(x) - int(1.1 * sr))
        search_hi = len(x) - w_len - int(0.08 * sr)
        for idx in range(search_lo, search_hi, 4):
            if not (x[idx - 1] <= 0.0 < x[idx]):
                continue
            cand = x[idx : idx + w_len]
            corr = float(np.dot(ref_win, cand)) / (ref_norm * (math.sqrt(float(np.sum(cand * cand))) + 1e-9))
            if corr > best_corr:
                best_corr = corr
                best_start = s0
                best_end = idx

    rms = math.sqrt(float(np.mean(x * x)))
    firing_hz = best_rpm * ((3.0 if is_v6 else 2.0) / 60.0)
    return {
        "sample_rate": sr,
        "duration_s": round(dur, 4),
        "measured_rpm": round(best_rpm, 1),
        "cycle_freq_hz": round(firing_hz, 2),
        "rms": round(rms, 5),
        "loop": {
            "start_s": round(best_start / sr, 5),
            "end_s": round(best_end / sr, 5),
            "correlation": round(best_corr, 4),
        },
    }


def load_legacy_extras(cfg: dict[str, Any]) -> dict[str, Any]:
    with cfg["legacy_manifest"].open("r", encoding="utf-8") as f:
        lm = json.load(f)
    backfire = lm.get("backfire", [
        "res://sounds/banks/commons/backfire_ext_1.wav",
        "res://sounds/banks/commons/backfire_ext_2.wav",
        "res://sounds/banks/commons/backfire_ext_3.wav",
        "res://sounds/banks/commons/backfire_ext_4.wav",
    ])
    whine = cfg.get("whine_override") or lm.get("whine", [
        "res://sounds/banks/EscortRS1600/whinelo.wav",
        "res://sounds/banks/EscortRS1600/whinehi.wav",
    ])
    ep = cfg.get("engine_position_override") or lm.get("engine_position", [0.0, 0.5, -0.9])
    xp = cfg.get("exhaust_position_override") or lm.get("exhaust_position", [0.0, 0.15, 1.0])
    return {
        "whine": whine,
        "backfire": backfire,
        "engine_position": ep,
        "exhaust_position": xp,
    }


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sweep_cache: dict[str, dict[str, Any]] = {}
    idle_cache: dict[str, dict[str, Any]] = {}

    for cfg in VEHICLE_CONFIGS:
        with cfg["powertrain_path"].open("r", encoding="utf-8") as f:
            pt_raw = json.load(f)
        pt = pt_raw.get("powertrain", pt_raw)
        idle_rpm = float(pt.get("idle_rpm", 900.0))
        max_rpm = float(pt.get("max_rpm", 7200.0))

        sub_key = f"{cfg['subbank']}|{cfg['accel_wav']}|{cfg['decel_wav']}"
        if sub_key not in sweep_cache:
            acc_p = RR3_ROOT / cfg["accel_wav"]
            dec_p = RR3_ROOT / cfg["decel_wav"]
            sweep_cache[sub_key] = analyze_sweep_pair(cfg["subbank"], acc_p, dec_p)
            sweep_cache[sub_key]["accel"]["sha256"] = sha256_file(acc_p)
            sweep_cache[sub_key]["decel"]["sha256"] = sha256_file(dec_p)

        if cfg["idle_wav"] not in idle_cache:
            idle_p = RR3_ROOT / cfg["idle_wav"]
            info = analyze_idle(idle_p, cfg["cylinders"] == 6)
            info["sha256"] = sha256_file(idle_p)
            idle_cache[cfg["idle_wav"]] = info

        sw = sweep_cache[sub_key]
        idl = idle_cache[cfg["idle_wav"]]
        extras = load_legacy_extras(cfg)

        manifest_stem = cfg.get("manifest_name", cfg["vehicle_id"])
        out_path = OUT_DIR / f"{manifest_stem}.json"

        idle_dict = {
            "path": f"res://sounds/banks/rr3-bank/{cfg['idle_wav']}",
            **idl,
        }
        accel_dict = {
            "path": f"res://sounds/banks/rr3-bank/{cfg['accel_wav']}",
            **sw["accel"],
        }
        decel_dict = {
            "path": f"res://sounds/banks/rr3-bank/{cfg['decel_wav']}",
            **sw["decel"],
        }

        manifest = {
            "schema_version": 4,
            "format": "rr3_sweep_granular_bank",
            "vehicle_id": cfg["vehicle_id"],
            "subbank": cfg["subbank"],
            "cylinders": cfg["cylinders"],
            "firing_order_multiplier": 3.0 if cfg["cylinders"] == 6 else 2.0,
            "character_note": cfg["character_note"],
            "rpm_profile": {
                "idle_rpm": idle_rpm,
                "max_rpm": max_rpm,
                "sweep_rpm_scale": cfg["sweep_rpm_scale"],
                "pitch_character": cfg["pitch_character"],
                "idle_crossfade_start_rpm": round(idle_rpm * 1.15, 1),
                "idle_crossfade_end_rpm": round(idle_rpm * 1.95, 1),
                "timbre_load_offset_rpm": 220.0,
            },
            "eq_profile": cfg["eq"],
            "engine_position": extras["engine_position"],
            "exhaust_position": extras["exhaust_position"],
            "whine": extras["whine"],
            "backfire": extras["backfire"],
            "idle": idle_dict,
            "accel": accel_dict,
            "decel": decel_dict,
        }

        with out_path.open("w", encoding="utf-8", newline="\n") as f:
            json.dump(manifest, f, indent=2)
            f.write("\n")

        print(
            f"{manifest_stem:22s} | sub={cfg['subbank']:8s} | idle={cfg['idle_wav'].split('/')[-1]:22s}"
            f" ({idl['measured_rpm']:5.0f}rpm r={idl['loop']['correlation']:.2f}) | pt=[{idle_rpm:4.0f},{max_rpm:4.0f}]"
            f" | acc=[{sw['accel']['rpm_min']:5.0f}..{sw['accel']['rpm_max']:5.0f}] ({len(sw['accel']['points'])}pts)"
            f" | dec=[{sw['decel']['rpm_min']:5.0f}..{sw['decel']['rpm_max']:5.0f}] ({len(sw['decel']['points'])}pts)"
        )


if __name__ == "__main__":
    main()
