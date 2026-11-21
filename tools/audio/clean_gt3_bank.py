"""Offline 6-step DSP cleaning, mastering & manifest calibration for ``gt3-bank``.

Usage:
    python -m tools.audio.clean_gt3_bank                  # -> tmp/gt3_clean_v1 (preview)
    python -m tools.audio.clean_gt3_bank --in-place       # backup -> tmp/gt3_backup_pre_clean, update bank + manifests

Pipeline (all filtering/resampling operates on closed periodic loops so seams never drift):
  1. Extract loop core, repair broken loop seams (phase-aligned correlation-compensated crossfade),
     and emit [preroll Y[-fade:] + Y] + manifest key matched to SeamlessVehicleLoop & VehicleSoundRouting.
  2. Exact DC removal + RPM-scaled zero-phase Butterworth HPF (16..55 Hz) + soft flat-top declipping.
  3. Periodic FFT linear-phase upsampling for sample rates < 22,050 Hz (exact integer factor 2x/3x/4x).
  4. Per-car / per-role corrective zero-phase EQ (Godot EQ10-aware) + layer spectral tilt smoothing.
  5. Circular slow envelope de-wobble (only where 50 ms wobble > 2.2 dB) + -3.0 dBFS true-peak norm + TPDF dither.
  6. Psychoacoustic gain recalibration (post-EQ10 K/B-weighted hybrid ramp) + full manifest.json updates.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import zlib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

import numpy as np

from tools.audio import commons_audit as audit

ROOT = Path(__file__).resolve().parents[2]
BANK = ROOT / "game" / "sounds" / "banks" / "gt3-bank"
DEFAULT_OUT = ROOT / "tmp" / "gt3_clean_v1"
BACKUP_DIR = ROOT / "tmp" / "gt3_backup_pre_clean"


@dataclass
class FilterRecipe:
    """Zero-phase corrective EQ & filtering specification for one sample."""

    hpf_hz: float
    lpf_start_hz: float
    lpf_end_hz: float
    bells: list[tuple[float, float, float]] = field(default_factory=list)  # (fc_hz, gain_db, q)
    lowshelf: tuple[float, float] | None = None  # (fc_hz, gain_db)
    highshelf: tuple[float, float] | None = None  # (fc_hz, gain_db)
    tilt_db_per_oct: float = 0.0
    tilt_pivot_hz: float = 500.0
    upsample_factor: int = 1


def upsample_factor_for(sr: int) -> int:
    if sr < 8000:
        return 4
    if sr < 12000:
        return 3
    if sr < 22050:
        return 2
    return 1


def _peaking_mag(freqs: np.ndarray, fs: float, fc: float, gain_db: float, q: float) -> np.ndarray:
    if abs(gain_db) < 0.05 or fc >= fs * 0.48 or fc <= 1.0:
        return np.ones_like(freqs)
    b, a = audit.biquad_peaking(fc, int(round(fs)), gain_db, q)
    z1 = np.exp(-1j * (2.0 * math.pi * freqs / fs))
    z2 = z1 * z1
    h = (b[0] + b[1] * z1 + b[2] * z2) / (a[0] + a[1] * z1 + a[2] * z2)
    return np.abs(h)


def _lowshelf_mag(freqs: np.ndarray, fs: float, fc: float, gain_db: float) -> np.ndarray:
    if abs(gain_db) < 0.05 or fc >= fs * 0.45 or fc <= 1.0:
        return np.ones_like(freqs)
    b, a = audit.biquad_lowshelf(fc, int(round(fs)), gain_db, slope=0.9)
    z1 = np.exp(-1j * (2.0 * math.pi * freqs / fs))
    z2 = z1 * z1
    h = (b[0] + b[1] * z1 + b[2] * z2) / (a[0] + a[1] * z1 + a[2] * z2)
    return np.abs(h)


def _highshelf_mag(freqs: np.ndarray, fc: float, gain_db: float) -> np.ndarray:
    if abs(gain_db) < 0.05 or fc <= 1.0:
        return np.ones_like(freqs)
    t = 0.5 + 0.5 * np.tanh(np.log2(np.maximum(freqs, 1.0) / fc) * 2.2)
    return 10.0 ** ((gain_db * t) / 20.0)


def _cosine_lpf_mag(freqs: np.ndarray, start_hz: float, end_hz: float) -> np.ndarray:
    h = np.ones_like(freqs)
    if end_hz <= start_hz:
        return np.where(freqs <= start_hz, 1.0, 0.0)
    trans = (freqs > start_hz) & (freqs < end_hz)
    phase = (freqs[trans] - start_hz) / (end_hz - start_hz)
    h[trans] = 0.5 * (1.0 + np.cos(math.pi * phase))
    h[freqs >= end_hz] = 0.0
    return h


def eq10_godot_gain(freqs: np.ndarray) -> np.ndarray:
    """Approximates Godot VehicleSoundRouting AudioEffectEQ10(presence) curve."""
    centers = np.array([31.25, 62.5, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0])
    gains = np.array([0.0, 0.0, 0.0, 0.0, 2.0, 3.0, 4.0, 3.0, 0.0, 0.0])
    db_vals = np.interp(np.log2(np.maximum(freqs, 1.0)), np.log2(centers), gains, left=0.0, right=0.0)
    return 10.0 ** (db_vals / 20.0)


def b_weight_gain(freqs: np.ndarray) -> np.ndarray:
    f = np.maximum(freqs, 1.0)
    num = (12194.0 ** 2) * (f ** 3)
    den = (f ** 2 + 20.6 ** 2) * np.sqrt(f ** 2 + 158.5 ** 2) * (f ** 2 + 12194.0 ** 2)
    return (num / den) * 1.019765


def periodic_fft_filter(y: np.ndarray, fs: int, mag_fn: Callable[[np.ndarray], np.ndarray]) -> np.ndarray:
    n = y.size
    if n < 8:
        return y
    spec = np.fft.rfft(y)
    freqs = np.fft.rfftfreq(n, 1.0 / fs)
    mag = mag_fn(freqs)
    mag[0] = 0.0  # guarantee zero DC
    return np.fft.irfft(spec * mag, n)


def resample_periodic_fft(y: np.ndarray, factor: int) -> np.ndarray:
    if factor <= 1 or y.size < 8:
        return y
    n = y.size
    m = n * factor
    spec = np.fft.rfft(y)
    out_spec = np.zeros(m // 2 + 1, dtype=complex)
    out_spec[:spec.size] = spec
    if n % 2 == 0:
        out_spec[n // 2] *= 0.5
    return np.fft.irfft(out_spec, m) * float(factor)


def declip_plateaus(y: np.ndarray, max_cubic_run: int = 14) -> tuple[np.ndarray, bool]:
    """Smoothly reconstruct flat-top clipped runs while preserving healthy peaks."""
    n = y.size
    if n < 16:
        return y, False
    out = y.copy()
    ax = np.abs(out)
    max_abs = float(np.max(ax))
    if max_abs < 0.85:
        return y, False

    near = ax >= max_abs * 0.992
    flat_diff = np.abs(np.diff(out, append=out[0])) <= (2.5 / 32768.0)
    mask = near & flat_diff
    # Expand each true run by 1 sample to cover the last glued sample in each diff pair.
    flagged = mask | np.roll(mask, 1)
    # Only consider plateaus of >= 3 consecutive samples near ceiling.
    runs: list[tuple[int, int]] = []
    i = 0
    while i < n:
        if flagged[i]:
            j = i
            while j < n and flagged[j]:
                j += 1
            if (j - i) >= 3:
                runs.append((i, j))
            i = j
        else:
            i += 1
    if not runs:
        return y, False

    for s, e in runs:
        run_len = e - s
        idx_before = [(s - 2) % n, (s - 1) % n]
        idx_after = [e % n, (e + 1) % n]
        y_m2, y_m1 = out[idx_before[0]], out[idx_before[1]]
        y_p0, y_p1 = out[idx_after[0]], out[idx_after[1]]
        sign = 1.0 if out[s] >= 0 else -1.0

        if run_len <= max_cubic_run:
            # Periodic cubic Hermite fit across [s-1, e]
            L = float(run_len + 1)
            m0 = (out[s] - y_m2) * 0.5 * L
            m1 = (y_p1 - out[e - 1]) * 0.5 * L
            #Clamp slopes so overshoot stays realistic
            m0 = float(np.clip(m0, -0.5 * max_abs * L, 0.5 * max_abs * L))
            m1 = float(np.clip(m1, -0.5 * max_abs * L, 0.5 * max_abs * L))
            t = (np.arange(run_len, dtype=np.float64) + 1.0) / L
            t2 = t * t
            t3 = t2 * t
            h00 = 2.0 * t3 - 3.0 * t2 + 1.0
            h10 = t3 - 2.0 * t2 + t
            h01 = -2.0 * t3 + 3.0 * t2
            h11 = t3 - t2
            recon = h00 * y_m1 + h10 * m0 + h01 * y_p0 + h11 * m1
            cap = 1.32 * max_abs
            if sign > 0:
                recon = np.clip(recon, y_m1 - 0.1 * max_abs, cap)
            else:
                recon = np.clip(recon, -cap, y_m1 + 0.1 * max_abs)
            out[s:e] = recon
        else:
            # Long clipped plateau: gently taper shoulders to soften harsh square corners
            t = np.linspace(0.0, math.pi, run_len)
            arch = 0.04 * max_abs * np.sin(t)
            out[s:e] = out[s:e] + sign * arch
    return out, True


def _trim_bad_edges(core: np.ndarray, fs: int) -> tuple[np.ndarray, bool]:
    """Trim leading/trailing ADPCM dead digital silence blocks (>=3 samples) or edge flat-top clipping."""
    max_trim = min(core.size // 10, int(0.004 * fs))
    if max_trim < 3:
        return core, False
    start = 0
    end = core.size
    ax = np.abs(core)
    mx = float(np.max(ax)) or 1.0

    # Trim leading dead digital silence only when >= 3 near-zero samples appear at the start
    zero_lead = 0
    while zero_lead < max_trim and ax[zero_lead] < 1e-5:
        zero_lead += 1
    if zero_lead >= 3:
        start = zero_lead

    # Trim trailing dead digital silence (>= 3 near-zero samples) or clipped ceiling run
    if mx > 0.85:
        while (core.size - end) < max_trim and ax[end - 1] >= mx * 0.998 and abs(core[end - 1] - core[end - 2]) < 3.0 / 32768.0:
            end -= 1
    zero_tail = 0
    while (core.size - end + zero_tail) < max_trim and ax[end - 1 - zero_tail] < 1e-5:
        zero_tail += 1
    if zero_tail >= 3:
        end -= zero_tail

    trimmed = (start > 0) or (end < core.size)
    if end - start < 64:
        return core, False
    return core[start:end].copy(), trimmed


def seam_continuity_stats(y: np.ndarray) -> tuple[float, float]:
    """Return (step_ratio_vs_p99, slope_ratio_vs_p99) across wrap y[-1] -> y[0]."""
    yz = y - float(np.mean(y))
    steps = np.abs(np.diff(yz))
    typ = float(np.percentile(steps, 99.0)) or 1e-9
    step_err = abs(float(yz[0] - yz[-1])) / typ
    d0 = float(yz[1] - yz[0])
    d1 = float(yz[-1] - yz[-2])
    d_wrap = float(yz[0] - yz[-1])
    slope_err = max(abs(d_wrap - d1), abs(d0 - d_wrap)) / typ
    return step_err, slope_err


def repair_loop_seam_phase_aligned(core: np.ndarray, fs: int) -> tuple[np.ndarray, bool, str]:
    """Ensure periodic continuity across wrap without pitch/level glitches."""
    x, edge_trimmed = _trim_bad_edges(core, fs)
    step_r, slope_r = seam_continuity_stats(x)
    if step_r <= 0.95 and slope_r <= 1.85:
        note = "trimmed_clean" if edge_trimmed else "clean_raw"
        return x, edge_trimmed, note

    # Only when a genuine boundary discontinuity remains: search up to 350ms (<= half loop) for peak phase match
    n = x.size
    w = min(max(int(0.024 * fs), 32), n // 6)
    max_search = min(int(0.350 * fs), max(8, n // 2 - w))
    xz = x - float(np.mean(x))
    head = xz[:w]
    head_norm = math.sqrt(float(np.dot(head, head))) + 1e-12

    tail_region = xz[n - w - max_search:n]
    windows = np.lib.stride_tricks.sliding_window_view(tail_region, w)
    dots = windows @ head
    norms = np.sqrt(np.sum(windows * windows, axis=1)) * head_norm + 1e-12
    corrs = dots / norms

    best_trim = 0
    best_corr = float(corrs[-1])
    if max_search > 1:
        idx_best = int(np.argmax(corrs))
        best_trim = (corrs.size - 1) - idx_best
        best_corr = float(corrs[idx_best])

    end_idx = n - best_trim
    if end_idx - w < 2 * w:
        return x, edge_trimmed, "too_short_raw"

    tail_seg = x[end_idx - w:end_idx].copy()
    head_seg = x[:w].copy()
    r_comp = float(np.clip(best_corr, 0.0, 0.999))
    t = np.linspace(0.0, 1.0, w, endpoint=False)
    alpha = np.sin(t * (math.pi / 2.0))
    beta = np.cos(t * (math.pi / 2.0))
    gain_comp = 1.0 / np.sqrt(alpha * alpha + beta * beta + 2.0 * alpha * beta * r_comp)
    blend = (beta * tail_seg + alpha * head_seg) * gain_comp

    out = x[:end_idx - w].copy()
    out[:w] = blend
    return out, True, f"phase_xfade(trim={best_trim},corr={best_corr:+.3f},step={step_r:.2f}x)"


def circular_wobble_db(y: np.ndarray, fs: int, win_s: float = 0.05) -> float:
    win = max(4, min(y.size // 4, int(win_s * fs)))
    if win < 4 or y.size < 4 * win:
        return 0.0
    pad = np.concatenate([y, y[:win - 1]])
    sq = pad * pad
    cs = np.concatenate([[0.0], np.cumsum(sq)])
    rms_arr = np.sqrt(np.maximum((cs[win:win + y.size] - cs[:y.size]) / float(win), 1e-18))
    step = max(1, win // 8)
    dbs = 20.0 * np.log10(np.maximum(rms_arr[::step], 1e-9))
    return float(np.percentile(dbs, 95) - np.percentile(dbs, 5))


def circular_dewobble(y: np.ndarray, fs: int, threshold_db: float = 2.2) -> tuple[np.ndarray, float | None]:
    """Attenuate slow cyclic amplitude wobble smoothly & periodically without squashing transients."""
    wob = circular_wobble_db(y, fs)
    if wob <= threshold_db or y.size < 64:
        return y, None
    n = y.size
    # Symmetric ~90 ms circular RMS via FFT convolution: spans 2.5-4 firing cycles while tracking 50 ms surge
    win = min(n // 3, max(16, int(0.090 * fs)))
    if win % 2 == 0:
        win += 1
    ker = np.hanning(win + 2)[1:-1]
    ker /= np.sum(ker)
    ker_pad = np.zeros(n)
    half = win // 2
    for idx in range(win):
        ker_pad[(idx - half) % n] = ker[idx]
    env_sq = np.fft.irfft(np.fft.rfft(y * y) * np.fft.rfft(ker_pad), n)
    env_rms = np.sqrt(np.maximum(env_sq, 1e-14))
    env_db = 20.0 * np.log10(env_rms)
    med_db = float(np.median(env_db))
    dev = env_db - med_db
    # Soft deadband +/- 0.35 dB, then apply 0.80 correction capped at +/-4.5 dB
    excess = np.where(np.abs(dev) > 0.35, dev - np.sign(dev) * 0.35, 0.0)
    gain_db = np.clip(-0.80 * excess, -4.5, 4.5)
    # Re-center mean gain_db to 0 so overall RMS barely moves
    gain_db -= float(np.mean(gain_db))
    out = y * (10.0 ** (gain_db / 20.0))
    return out, circular_wobble_db(out, fs)


def build_recipe(car: str, role: str, rel: str, base_rpm: int, sr_in: int, tilt_db: float) -> FilterRecipe:
    """Per-car, per-role corrective EQ profile accounting for Godot's fixed EQ10."""
    factor = upsample_factor_for(sr_in)
    nyq_in = sr_in / 2.0

    # RPM-scaled HPF: preserve 23-27 Hz fundamental at idle, clean sub-crank rumble above idle
    if base_rpm <= 1100:
        hpf_hz = 16.0
    else:
        crank_hz = base_rpm / 60.0
        hpf_hz = float(np.clip(0.65 * crank_hz, 16.0, 55.0))

    lpf_start = 0.86 * nyq_in
    lpf_end = 0.98 * nyq_in
    bells: list[tuple[float, float, float]] = []
    lowshelf = None
    highshelf = None

    if role == "engine":
        if car == "civic-sir-ii":
            # Severe broadband >4kHz noise floor + 13-15kHz Nyquist shelf
            lpf_start, lpf_end = 7400.0, 10800.0
            bells.append((6200.0, -3.5 if base_rpm <= 3000 or base_rpm >= 7500 else -2.5, 0.75))
            bells.append((250.0, -1.5, 0.9))
            highshelf = (3800.0, -2.5)
        elif car == "civic-type-r":
            # Worst fizz/resonance 6-9kHz near 10kHz Nyquist (up to 72% >4kHz at 8120 rpm)
            lpf_start, lpf_end = (5600.0, 8200.0) if base_rpm >= 7000 else (6400.0, 9200.0)
            bells.append((5800.0, -4.5 if base_rpm >= 7000 or base_rpm <= 3000 else -3.0, 0.75))
            if base_rpm >= 7500:
                bells.append((6200.0, -3.0, 1.2))
            elif base_rpm >= 7000:
                bells.append((6800.0, -2.5, 1.4))
            bells.append((240.0, -1.5, 0.9))
        elif car == "motor-sport-elise":
            # 80.6% <400Hz mud, dull upper mids
            bells.append((220.0, -3.0, 0.9))
            bells.append((900.0, +2.0, 0.75))
        elif car == "trueno-gt-apex":
            # Heavy 160-400Hz (41.9%)
            bells.append((250.0, -2.5, 0.9))
            bells.append((850.0, +1.0, 0.75))
        elif car == "mx-5":
            # 7.8-11.1 kHz SR: tame nasal 1.8k-3.4k boosted by Godot EQ10 (+4 dB @ 2k)
            bells.append((1800.0, -3.0, 0.85))
            bells.append((3400.0, -2.0, 0.9))
            bells.append((240.0, -1.5, 0.9))
        elif car == "mx-5-18-rs":
            # Strongest EQ10 boost (+1.99 dB avg -> 55.7% 1-5kHz)
            bells.append((1850.0, -2.5, 0.85))
            bells.append((3200.0, -2.0, 0.9))
            bells.append((230.0, -1.5, 0.9))
        elif car == "mini-cooper":
            if base_rpm >= 3500:
                bells.append((1900.0, -2.0, 0.85))
            else:
                bells.append((140.0, -1.5, 0.8))
        elif car == "peugeot-206-s16":
            if 3800 <= base_rpm <= 4300:
                bells.append((220.0, -2.5, 0.85))
                bells.append((1900.0, -1.5, 0.85))
            elif base_rpm >= 3500:
                bells.append((260.0, -1.5, 0.85))
                bells.append((1900.0, -1.5, 0.85))
        elif car == "vitz-rs":
            bells.append((240.0, -2.0, 0.9))
            if nyq_in > 9000:
                bells.append((4200.0, -1.5, 0.9))
        elif car == "new-beetle-20":
            bells.append((240.0, -2.0, 0.9))
            bells.append((1800.0, -1.0, 0.85))
        elif car == "stratos-rally-car":
            bells.append((220.0, -1.5, 0.85))
        elif car == "fiat-131-abarth":
            bells.append((220.0, -2.5, 0.9))
            bells.append((900.0, +1.5, 0.75))

    elif role == "exhaust":
        if car == "mini-cooper":
            lowshelf = (110.0, -2.5)
            bells.append((350.0, +2.0, 0.7))
        elif car in ("civic-sir-ii", "civic-type-r", "peugeot-206-s16", "new-beetle-20", "trueno-gt-apex", "vitz-rs"):
            bells.append((230.0, -2.0, 0.85))
            if base_rpm >= 2500:
                lowshelf = (95.0, -1.5)
        elif car == "motor-sport-elise":
            bells.append((220.0, -2.5, 0.9))
            bells.append((700.0, +1.5, 0.8))
        elif car == "mx-5":
            bells.append((250.0, -1.5, 0.85))
        elif car == "mx-5-18-rs":
            if base_rpm >= 5500:
                bells.append((1800.0, -2.0, 0.85))
            else:
                bells.append((180.0, -1.5, 0.85))
        elif car == "stratos-rally-car":
            lowshelf = (95.0, -1.5)
            bells.append((220.0, -1.0, 0.85))
        elif car == "fiat-131-abarth":
            bells.append((220.0, -2.5, 0.9))
            bells.append((900.0, +1.5, 0.75))

    return FilterRecipe(
        hpf_hz=hpf_hz,
        lpf_start_hz=lpf_start,
        lpf_end_hz=lpf_end,
        bells=bells,
        lowshelf=lowshelf,
        highshelf=highshelf,
        tilt_db_per_oct=tilt_db,
        tilt_pivot_hz=450.0 if role == "engine" else 220.0,
        upsample_factor=factor,
    )


def compute_layer_spectral_tilts(bank: Path, manifest: dict) -> dict[str, float]:
    """Identify active RPM layers whose post-base-EQ centroid deviates strongly from the car's RPM trend."""
    smap = {s["file"]: s for s in manifest["samples"]}
    tilts: dict[str, float] = {}
    marker = f"gt3-bank/{bank.name}/"
    for role in ("engine", "exhaust"):
        defs = manifest.get(role, [])
        items: list[tuple[int, str, float]] = []
        for d in defs:
            p_str = str(d["path"])
            rel = p_str.split(marker, 1)[1] if marker in p_str else Path(p_str).name
            sm = smap.get(rel)
            if not sm:
                continue
            wav = audit.read_wav(bank / rel)
            x = wav.mono()
            ls = max(0, min(x.size - 2, int(float(sm["loop"]["start_s"]) * wav.rate)))
            le = max(ls + 2, min(x.size, int(float(sm["loop"]["end_s"]) * wav.rate)))
            core = x[ls:le]
            y, _, _ = repair_loop_seam_phase_aligned(core, wav.rate)
            y, _ = declip_plateaus(y)
            base_rec = build_recipe(bank.name, role, rel, int(sm["base_rpm"]), wav.rate, 0.0)
            y_eq = apply_filter_recipe(y, wav.rate, base_rec)
            freqs, pwr = audit.average_spectrum(y_eq - float(np.mean(y_eq)), wav.rate)
            cent = float(np.sum(freqs * pwr) / (np.sum(pwr) + 1e-30))
            items.append((int(d["reference"]), rel, cent))
        items.sort(key=lambda it: it[0])
        if len(items) < 3:
            continue
        lx = np.log2(np.maximum([it[0] for it in items], 200.0))
        ly = np.log2(np.maximum([it[2] for it in items], 30.0))
        # Robust weighted linear trend constrained to non-negative slope (centroids don't legitimately invert)
        w = np.ones_like(lx)
        slope, intercept = 0.0, float(np.median(ly))
        for _ in range(4):
            wsum = float(np.sum(w))
            mx = float(np.sum(w * lx) / wsum)
            my = float(np.sum(w * ly) / wsum)
            denom = float(np.sum(w * (lx - mx) ** 2))
            raw_slope = float(np.sum(w * (lx - mx) * (ly - my)) / denom) if denom > 1e-9 else 0.0
            slope = max(0.0, raw_slope)
            intercept = my - slope * mx
            res = np.abs(ly - (slope * lx + intercept))
            w = 1.0 / np.maximum(res, 0.25)
        trend = slope * lx + intercept
        for i, (_, rel, _) in enumerate(items):
            if i == 0 and role == "engine":
                continue  # Idle engine chatter naturally sits brighter than low-load cruise
            err_oct = float(ly[i] - trend[i])
            if err_oct < -0.55:
                tilts[rel] = float(np.clip(-1.6 * err_oct, 0.0, 2.0))
            elif err_oct > 0.65:
                tilts[rel] = float(np.clip(-1.4 * err_oct, -1.8, 0.0))
    return tilts


def apply_filter_recipe(y: np.ndarray, fs_in: int, recipe: FilterRecipe) -> np.ndarray:
    def mag_fn(freqs: np.ndarray) -> np.ndarray:
        f_nz = np.maximum(freqs, 1.0)
        # 2nd-order zero-phase Butterworth HPF magnitude
        h = (f_nz / recipe.hpf_hz) ** 2 / np.sqrt(1.0 + (f_nz / recipe.hpf_hz) ** 4)
        # Anti-image / cleanup cosine LPF near input Nyquist
        h *= _cosine_lpf_mag(freqs, recipe.lpf_start_hz, recipe.lpf_end_hz)
        if recipe.lowshelf is not None:
            h *= _lowshelf_mag(freqs, float(fs_in), recipe.lowshelf[0], recipe.lowshelf[1])
        if recipe.highshelf is not None:
            h *= _highshelf_mag(freqs, recipe.highshelf[0], recipe.highshelf[1])
        for fc, gdb, q in recipe.bells:
            h *= _peaking_mag(freqs, float(fs_in), fc, gdb, q)
        if abs(recipe.tilt_db_per_oct) >= 0.1:
            octs = np.clip(np.log2(f_nz / recipe.tilt_pivot_hz), -2.0, 2.0)
            t_db = np.clip(recipe.tilt_db_per_oct * octs, -3.5, 4.0)
            h *= 10.0 ** (t_db / 20.0)
        return h

    return periodic_fft_filter(y, fs_in, mag_fn)


def tpdf_quantize_loop(y: np.ndarray, rel_key: str) -> np.ndarray:
    seed = zlib.crc32(rel_key.encode("utf-8")) & 0xFFFFFFFF
    rng = np.random.default_rng(seed)
    lsb = 1.0 / 32768.0
    dithered = np.clip(y, -1.0, 1.0) + (rng.random(y.size) - rng.random(y.size)) * lsb
    return np.clip(np.round(dithered * 32768.0), -32768, 32767).astype("<i2")


def write_i16_wav(path: Path, pcm: np.ndarray, fs: int) -> None:
    data = pcm.tobytes()
    header = bytearray()
    header += b"RIFF"
    header += (36 + len(data)).to_bytes(4, "little")
    header += b"WAVEfmt "
    header += (16).to_bytes(4, "little")
    header += (1).to_bytes(2, "little")
    header += (1).to_bytes(2, "little")
    header += int(fs).to_bytes(4, "little")
    header += (int(fs) * 2).to_bytes(4, "little")
    header += (2).to_bytes(2, "little")
    header += (16).to_bytes(2, "little")
    header += b"data"
    header += len(data).to_bytes(4, "little")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(bytes(header) + data)


def measure_post_eq10_loudness(y: np.ndarray, fs: int) -> tuple[float, float, float]:
    """Return (lufs_eq10, dbb_eq10, hybrid_0.5_0.5) at unity gain."""
    if y.size < 8:
        return -70.0, -70.0, -70.0
    freqs = np.fft.rfftfreq(y.size, 1.0 / fs)
    eq_lin = eq10_godot_gain(freqs)
    y_eq = np.fft.irfft(np.fft.rfft(y) * eq_lin, y.size)
    lufs_eq = audit.lufs_event(y_eq, fs)
    # B-weighted power using Parseval over periodic Hann window
    win = np.hanning(y.size)
    spec = np.fft.rfft(y * win)
    pwr = (np.abs(spec) ** 2) / (y.size * float(np.sum(win * win)) + 1e-30) * 2.0
    pwr[0] *= 0.5
    if y.size % 2 == 0:
        pwr[-1] *= 0.5
    dbb_eq = audit.db(math.sqrt(max(float(np.sum(pwr * (eq_lin ** 2) * (b_weight_gain(freqs) ** 2))), 1e-24)))
    return lufs_eq, dbb_eq, 0.5 * lufs_eq + 0.5 * dbb_eq


def process_car(
    car_dir: Path,
    out_car_dir: Path,
    ceiling_db: float,
    in_place: bool,
) -> dict:
    car = car_dir.name
    bkp_car_dir = BACKUP_DIR / car
    bkp_mf = bkp_car_dir / "manifest.json"
    mf_path = car_dir / "manifest.json"
    if in_place and not bkp_mf.exists():
        bkp_mf.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(mf_path, bkp_mf)
    raw_car_dir = bkp_car_dir if bkp_mf.exists() else car_dir
    manifest = json.loads((raw_car_dir / "manifest.json").read_text(encoding="utf-8"))

    marker = f"gt3-bank/{car}/"
    active_role_by_rel: dict[str, str] = {}
    for role in ("engine", "exhaust"):
        for d in manifest.get(role, []):
            p_str = str(d["path"])
            rel = p_str.split(marker, 1)[1] if marker in p_str else Path(p_str).name
            active_role_by_rel[rel] = role

    tilts = compute_layer_spectral_tilts(raw_car_dir, manifest)

    # Track aliases (bit-identical originals within same car & role)
    sha_to_canonical: dict[tuple[str, str], dict] = {}
    sample_reports: list[dict] = []
    processed_loop_info: dict[str, tuple[np.ndarray, int, float]] = {}

    for sm in manifest["samples"]:
        rel = str(sm["file"]).replace("\\", "/")
        role = active_role_by_rel.get(rel, "unused")
        orig_sha = str(sm["sha256"])
        alias_key = (orig_sha, role)
        bkp_path = bkp_car_dir / rel
        if in_place and not bkp_path.exists():
            bkp_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(car_dir / rel, bkp_path)
        src_path = bkp_path if bkp_path.exists() else (car_dir / rel)
        dst_path = out_car_dir / rel

        if alias_key in sha_to_canonical:
            canon = sha_to_canonical[alias_key]
            dst_path.parent.mkdir(parents=True, exist_ok=True)
            if canon["path"] != dst_path:
                shutil.copy2(canon["path"], dst_path)
            sm["key"] = Path(rel).stem
            sm["sha256"] = canon["sha256"]
            sm["rate_hz"] = canon["rate_hz"]
            sm["loop"] = dict(canon["loop"])
            if role != "unused":
                processed_loop_info[rel] = canon["loop_info"]
            sample_reports.append({**canon["report"], "file": rel, "alias_of": canon["rel"]})
            continue

        wav = audit.read_wav(src_path)
        sr_in = wav.rate
        base_rpm = int(sm["base_rpm"])
        core = wav.mono()[
            max(0, min(wav.frames - 2, int(float(sm["loop"]["start_s"]) * sr_in))):
            max(2, min(wav.frames, int(float(sm["loop"]["end_s"]) * sr_in)))
        ]
        tp_before = audit.db(audit.true_peak(core))
        step_before, slope_before = seam_continuity_stats(core)
        wob_before = circular_wobble_db(core, sr_in)
        dc_before = audit.db(abs(float(np.mean(core))))

        # Step 1a: Phase-aligned seam repair
        y, repaired, seam_note = repair_loop_seam_phase_aligned(core, sr_in)

        # Step 2a: Declip plateaus before filtering
        y, declipped = declip_plateaus(y)

        # Step 2b + Step 4: Zero-phase periodic FFT DC removal, RPM HPF, LPF & car EQ
        tilt = tilts.get(rel, 0.0) if role != "unused" else 0.0
        recipe = build_recipe(car, role, rel, base_rpm, sr_in, tilt)
        y = apply_filter_recipe(y, sr_in, recipe)

        # Step 3: Exact periodic FFT upsampling for low sample rates
        if recipe.upsample_factor > 1:
            y = resample_periodic_fft(y, recipe.upsample_factor)
        sr_out = sr_in * recipe.upsample_factor

        # Step 5a: Circular de-wobble (gentle slow envelope leveling)
        y, wob_after = circular_dewobble(y, sr_out, threshold_db=2.2)

        # Ensure loop length >= 4 * fade so SeamlessVehicleLoop uses full 512*sr/44100 window
        fade = int(512.0 * sr_out / 44100.0)
        if y.size < 4 * fade:
            reps = math.ceil((4 * fade) / max(y.size, 1))
            y = np.tile(y, reps)

        # Step 5b: Scale closed loop safely below -3.0 dBFS true peak (with TPDF headroom)
        tp_pre = audit.db(audit.true_peak(y))
        target_pre_db = ceiling_db - 0.08
        scale = 10.0 ** ((target_pre_db - tp_pre) / 20.0)
        y *= scale

        # Quantize closed loop once to PCM16 with deterministic TPDF dither
        y_i16 = tpdf_quantize_loop(y, f"{car}/{rel}")
        # Verify final quantized True Peak <= ceiling + 0.02 dBFS
        y_q = y_i16.astype(np.float64) / 32768.0
        tp_q = audit.db(audit.true_peak(y_q))
        if tp_q > ceiling_db + 0.02:
            nudge = 10.0 ** ((ceiling_db - 0.05 - tp_q) / 20.0)
            y_i16 = tpdf_quantize_loop(y * nudge, f"{car}/{rel}_nudge")
            y_q = y_i16.astype(np.float64) / 32768.0
            tp_q = audit.db(audit.true_peak(y_q))

        # Step 1b: Pack [preroll Y[-fade:] + Y] so SeamlessVehicleLoop lands identically with or without loop arg
        packed_i16 = np.concatenate([y_i16[-fade:], y_i16])
        write_i16_wav(dst_path, packed_i16, sr_out)

        new_sha = hashlib.sha256(dst_path.read_bytes()).hexdigest()
        loop_end_frames = fade + y_i16.size
        # +0.25 frame guarantees int(end_s * rate) == loop_end_frames even under FP rounding
        new_loop = {"start_s": 0.0, "end_s": float(loop_end_frames + 0.25) / float(sr_out)}

        sm["key"] = Path(rel).stem
        sm["sha256"] = new_sha
        sm["rate_hz"] = int(sr_out)
        sm["loop"] = new_loop

        lufs_eq, dbb_eq, hybrid_eq = measure_post_eq10_loudness(y_q, sr_out)
        if role != "unused":
            processed_loop_info[rel] = (y_q, sr_out, hybrid_eq)

        step_after, slope_after = seam_continuity_stats(y_q)
        dc_after = audit.db(abs(float(np.mean(y_q))))
        wob_final = circular_wobble_db(y_q, sr_out)

        rep = {
            "car": car,
            "file": rel,
            "role": role,
            "rpm": base_rpm,
            "sr_in": sr_in,
            "sr_out": sr_out,
            "tp_before": round(tp_before, 2),
            "tp_after": round(tp_q, 2),
            "dc_before": round(dc_before, 1),
            "dc_after": round(dc_after, 1),
            "wob_before": round(wob_before, 2),
            "wob_after": round(wob_final, 2),
            "step_before": round(step_before, 2),
            "step_after": round(step_after, 2),
            "declipped": declipped,
            "seam": seam_note,
            "tilt": round(tilt, 2),
            "hybrid_eq_unity": round(hybrid_eq, 2),
        }
        sample_reports.append(rep)
        sha_to_canonical[alias_key] = {
            "path": dst_path,
            "rel": rel,
            "sha256": new_sha,
            "rate_hz": int(sr_out),
            "loop": new_loop,
            "loop_info": (y_q, sr_out, hybrid_eq),
            "report": rep,
        }

    # Step 6: Calibrate monotonic perceptual gains on engine and exhaust
    gain_reports: list[dict] = []
    targets = {
        "engine": (-28.0, -18.5, 0.80),
        "exhaust": (-26.5, -18.0, 0.85),
    }
    for role, (lo_db, hi_db, exp_p) in targets.items():
        defs = manifest.get(role, [])
        if not defs:
            continue
        rpms = [float(d["reference"]) for d in defs]
        rpm_min, rpm_max = min(rpms), max(rpms)
        span_rpm = max(rpm_max - rpm_min, 1.0)
        for d in defs:
            p_str = str(d["path"])
            rel = p_str.split(marker, 1)[1] if marker in p_str else Path(p_str).name
            _, sr_out, hybrid_eq = processed_loop_info[rel]
            t_norm = min(1.0, max(0.0, (float(d["reference"]) - rpm_min) / span_rpm))
            target_db = lo_db + (hi_db - lo_db) * (t_norm ** exp_p)
            old_gain = float(d["gain"])
            new_gain = float(np.clip(10.0 ** ((target_db - hybrid_eq) / 20.0), 0.02, 0.85))
            d["gain"] = new_gain
            gain_reports.append({
                "role": role,
                "rpm": int(d["reference"]),
                "old_gain": round(old_gain, 4),
                "new_gain": round(new_gain, 4),
                "target_hybrid": round(target_db, 2),
                "achieved_hybrid": round(hybrid_eq + audit.db(new_gain), 2),
                "eff_tp_dbfs": round(ceiling_db + audit.db(new_gain), 2),
            })

    (out_car_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    return {"car": car, "samples": sample_reports, "gains": gain_reports}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bank", type=Path, default=BANK)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--ceiling", type=float, default=-3.0, help="true-peak ceiling in dBFS")
    parser.add_argument("--in-place", action="store_true", help="overwrite gt3-bank WAVs and manifests in-place (writes backup first)")
    args = parser.parse_args(argv)

    car_dirs = sorted(p for p in args.bank.iterdir() if p.is_dir() and (p / "manifest.json").exists())
    if not car_dirs:
        print(f"No car manifests found in {args.bank}")
        return 1

    all_reports: list[dict] = []
    for car_dir in car_dirs:
        out_car = car_dir if args.in_place else (args.out / car_dir.name)
        out_car.mkdir(parents=True, exist_ok=True)
        res = process_car(car_dir, out_car, args.ceiling, args.in_place)
        all_reports.append(res)
        sreps = res["samples"]
        act = [r for r in sreps if r["role"] != "unused"]
        print(
            f"[{res['car']:18s}] n={len(sreps):2d} (act={len(act):2d}) | "
            f"TP: {max(r['tp_before'] for r in sreps):+5.2f} -> {max(r['tp_after'] for r in sreps):+5.2f} | "
            f"DC max: {max(r['dc_before'] for r in sreps):5.1f} -> {max(r['dc_after'] for r in sreps):5.1f} | "
            f"Wob max: {max(r['wob_before'] for r in act):4.2f} -> {max(r['wob_after'] for r in act):4.2f} | "
            f"Step max: {max(r['step_before'] for r in act):5.2f}x -> {max(r['step_after'] for r in act):4.2f}x"
        )

    rep_root = args.out if not args.in_place else (ROOT / "tmp")
    rep_root.mkdir(parents=True, exist_ok=True)
    rep_path = rep_root / "gt3_clean_report.json"
    rep_path.write_text(json.dumps(all_reports, indent=2), encoding="utf-8")
    print(f"\nReport written to {rep_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
