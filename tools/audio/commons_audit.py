"""Objective DSP audit primitives for the shared WAV banks (numpy + stdlib only).

No scipy/soundfile in this environment, so everything is implemented here:
RIFF parsing that mirrors ``SeamlessVehicleLoop.load_pcm`` preconditions,
ITU-R BS.1770-4 gated loudness, 4x oversampled true peak, octave band split,
loop-wrap discontinuity metrics and click/clipping detectors.

All amplitudes are float64 in [-1, 1). Decibel helpers are re 1.0 (dBFS).
"""
from __future__ import annotations

import hashlib
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

SILENCE_FLOOR = 1e-9
TRUE_PEAK_FACTOR = 4

# Octave-ish analysis bands used by the report (Hz).
BANDS = (
    ("sub_20_40", 20.0, 40.0),
    ("low_40_80", 40.0, 80.0),
    ("lowmid_80_200", 80.0, 200.0),
    ("mid_200_500", 200.0, 500.0),
    ("himid_500_2k", 500.0, 2000.0),
    ("presence_2k_6k", 2000.0, 6000.0),
    ("air_6k_12k", 6000.0, 12000.0),
    ("top_12k_20k", 12000.0, 20000.0),
)


def db(linear: float) -> float:
    """Amplitude ratio -> dBFS (clamped to a finite floor)."""
    return 20.0 * math.log10(max(float(linear), SILENCE_FLOOR))


def pow_db(linear: float) -> float:
    """Power ratio -> dB."""
    return 10.0 * math.log10(max(float(linear), SILENCE_FLOOR * SILENCE_FLOOR))


# --------------------------------------------------------------------------- #
# RIFF reading (same preconditions the game's PCM loader enforces)
# --------------------------------------------------------------------------- #


@dataclass
class Wav:
    path: Path
    rate: int
    channels: int
    bits: int
    format_tag: int
    data: np.ndarray  # shape (frames, channels), float64 in [-1, 1]
    runtime_ok: bool
    runtime_reason: str
    sha256: str

    @property
    def frames(self) -> int:
        return int(self.data.shape[0])

    @property
    def duration(self) -> float:
        return self.frames / float(self.rate) if self.rate else 0.0

    def mono(self) -> np.ndarray:
        if self.channels == 1:
            return self.data[:, 0]
        return self.data.mean(axis=1)


def _decode(raw: bytes, bits: int, tag: int) -> np.ndarray:
    if tag == 3 and bits == 32:
        return np.frombuffer(raw, dtype="<f4").astype(np.float64)
    if tag == 3 and bits == 64:
        return np.frombuffer(raw, dtype="<f8").astype(np.float64)
    if bits == 16:
        return np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    if bits == 24:
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        v = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
        v = np.where(v & 0x800000, v - 0x1000000, v)
        return v.astype(np.float64) / float(1 << 23)
    if bits == 32:
        return np.frombuffer(raw, dtype="<i4").astype(np.float64) / float(1 << 31)
    if bits == 8:
        u = np.frombuffer(raw, dtype=np.uint8).astype(np.float64) - 128.0
        return u / 128.0
    raise ValueError(f"unsupported bits={bits} tag={tag}")


def read_wav(path: Path) -> Wav:
    raw = path.read_bytes()
    if len(raw) < 44 or raw[0:4] != b"RIFF" or raw[8:12] != b"WAVE":
        raise ValueError(f"not a RIFF/WAVE file: {path}")

    fmt_raw = None
    data_raw = None
    offset = 12
    while offset + 8 <= len(raw):
        chunk_id = raw[offset:offset + 4]
        size = int.from_bytes(raw[offset + 4:offset + 8], "little")
        start = offset + 8
        if start + size > len(raw):
            raise ValueError(f"truncated chunk in {path}")
        if chunk_id == b"fmt ":
            fmt_raw = raw[start:start + size]
        elif chunk_id == b"data":
            data_raw = raw[start:start + size]
        offset = start + size + (size & 1)

    if fmt_raw is None or data_raw is None or len(fmt_raw) < 16:
        raise ValueError(f"missing fmt/data chunk in {path}")

    tag = int.from_bytes(fmt_raw[0:2], "little")
    channels = int.from_bytes(fmt_raw[2:4], "little")
    rate = int.from_bytes(fmt_raw[4:8], "little")
    bits = int.from_bytes(fmt_raw[14:16], "little")
    if tag == 0xFFFE and len(fmt_raw) >= 26:  # WAVE_FORMAT_EXTENSIBLE
        tag = int.from_bytes(fmt_raw[24:26], "little")

    samples = _decode(data_raw, bits, tag)
    if channels > 0:
        samples = samples[: (len(samples) // channels) * channels]
        samples = samples.reshape(-1, channels)

    # Mirrors SeamlessVehicleLoop.load_pcm: fmt tag 1, 16 bit, 1-2 channels.
    reasons = []
    if tag != 1:
        reasons.append(f"fmt_tag={tag}")
    if bits != 16:
        reasons.append(f"bits={bits}")
    if channels < 1 or channels > 2:
        reasons.append(f"channels={channels}")
    if rate <= 0:
        reasons.append(f"rate={rate}")

    return Wav(
        path=path,
        rate=rate,
        channels=channels,
        bits=bits,
        format_tag=tag,
        data=samples,
        runtime_ok=not reasons,
        runtime_reason="ok" if not reasons else "+".join(reasons),
        sha256=hashlib.sha256(raw).hexdigest(),
    )


# --------------------------------------------------------------------------- #
# Filters
# --------------------------------------------------------------------------- #


def biquad_highpass(fc: float, fs: int, q: float = 0.7071067811865476) -> tuple[np.ndarray, np.ndarray]:
    w0 = 2.0 * math.pi * fc / fs
    cos_w0 = math.cos(w0)
    alpha = math.sin(w0) / (2.0 * q)
    b0 = (1.0 + cos_w0) / 2.0
    b1 = -(1.0 + cos_w0)
    b2 = (1.0 + cos_w0) / 2.0
    a0 = 1.0 + alpha
    a1 = -2.0 * cos_w0
    a2 = 1.0 - alpha
    return (np.array([b0, b1, b2]) / a0, np.array([1.0, a1 / a0, a2 / a0]))


def biquad_lowpass(fc: float, fs: int, q: float = 0.7071067811865476) -> tuple[np.ndarray, np.ndarray]:
    w0 = 2.0 * math.pi * fc / fs
    cos_w0 = math.cos(w0)
    alpha = math.sin(w0) / (2.0 * q)
    b0 = (1.0 - cos_w0) / 2.0
    b1 = 1.0 - cos_w0
    b2 = (1.0 - cos_w0) / 2.0
    a0 = 1.0 + alpha
    a1 = -2.0 * cos_w0
    a2 = 1.0 - alpha
    return (np.array([b0, b1, b2]) / a0, np.array([1.0, a1 / a0, a2 / a0]))


def biquad_peaking(fc: float, fs: int, gain_db: float, q: float = 1.0) -> tuple[np.ndarray, np.ndarray]:
    A = 10.0 ** (gain_db / 40.0)
    w0 = 2.0 * math.pi * fc / fs
    cos_w0 = math.cos(w0)
    alpha = math.sin(w0) / (2.0 * q)
    b0 = 1.0 + alpha * A
    b1 = -2.0 * cos_w0
    b2 = 1.0 - alpha * A
    a0 = 1.0 + alpha / A
    a1 = -2.0 * cos_w0
    a2 = 1.0 - alpha / A
    return (np.array([b0, b1, b2]) / a0, np.array([1.0, a1 / a0, a2 / a0]))


def biquad_lowshelf(fc: float, fs: int, gain_db: float, slope: float = 1.0) -> tuple[np.ndarray, np.ndarray]:
    A = 10.0 ** (gain_db / 40.0)
    w0 = 2.0 * math.pi * fc / fs
    cos_w0, sin_w0 = math.cos(w0), math.sin(w0)
    alpha = sin_w0 / 2.0 * math.sqrt((A + 1.0 / A) * (1.0 / slope - 1.0) + 2.0)
    two_sqrt_a_alpha = 2.0 * math.sqrt(A) * alpha
    b0 = A * ((A + 1.0) - (A - 1.0) * cos_w0 + two_sqrt_a_alpha)
    b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cos_w0)
    b2 = A * ((A + 1.0) - (A - 1.0) * cos_w0 - two_sqrt_a_alpha)
    a0 = (A + 1.0) + (A - 1.0) * cos_w0 + two_sqrt_a_alpha
    a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cos_w0)
    a2 = (A + 1.0) + (A - 1.0) * cos_w0 - two_sqrt_a_alpha
    return (np.array([b0, b1, b2]) / a0, np.array([1.0, a1 / a0, a2 / a0]))


def biquad_response(sections: list[tuple[np.ndarray, np.ndarray]], freqs: np.ndarray, fs: int) -> np.ndarray:
    w = 2.0 * math.pi * freqs / fs
    z1 = np.exp(-1j * w)
    z2 = z1 * z1
    h = np.ones_like(z1)
    for b, a in sections:
        h *= (b[0] + b[1] * z1 + b[2] * z2) / (a[0] + a[1] * z1 + a[2] * z2)
    return h


def fft_filter(x: np.ndarray, sections: list[tuple[np.ndarray, np.ndarray]], fs: int,
               pad_s: float = 0.05) -> np.ndarray:
    """Zero-phase-ish filtering via FFT with linear padding (no wrap-around)."""
    if not sections or x.size == 0:
        return x
    pad = max(64, int(pad_s * fs))
    n = x.size + 2 * pad
    nfft = 1 << int(math.ceil(math.log2(max(n, 2))))
    xp = np.zeros(nfft)
    xp[pad:pad + x.size] = x
    freqs = np.fft.rfftfreq(nfft, 1.0 / fs)
    h = biquad_response(sections, freqs, fs)
    y = np.fft.irfft(np.fft.rfft(xp) * h, nfft)
    return y[pad:pad + x.size]


# --------------------------------------------------------------------------- #
# Loudness (ITU-R BS.1770-4)
# --------------------------------------------------------------------------- #


def _k_weighting(fs: int) -> list[tuple[np.ndarray, np.ndarray]]:
    # Stage 1: high shelf (head effect).
    g, q, fc = 3.999843853973347, 0.7071752369554196, 1681.974450955533
    k = math.tan(math.pi * fc / fs)
    vh = 10.0 ** (g / 20.0)
    vb = vh ** 0.4996667741545416
    a0 = 1.0 + k / q + k * k
    shelf_b = np.array([
        (vh + vb * k / q + k * k) / a0,
        2.0 * (k * k - vh) / a0,
        (vh - vb * k / q + k * k) / a0,
    ])
    shelf_a = np.array([1.0, 2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0])

    # Stage 2: high pass (RLB).
    q2, fc2 = 0.5003270373238773, 38.13547087602444
    k2 = math.tan(math.pi * fc2 / fs)
    den = 1.0 + k2 / q2 + k2 * k2
    hp_b = np.array([1.0, -2.0, 1.0])
    hp_a = np.array([1.0, 2.0 * (k2 * k2 - 1.0) / den, (1.0 - k2 / q2 + k2 * k2) / den])
    return [(shelf_b, shelf_a), (hp_b, hp_a)]


def lufs_integrated(x: np.ndarray, fs: int, block_s: float = 0.4, hop_s: float = 0.1) -> float:
    """Gated integrated loudness for mono input. Returns -inf for silence.

    Content shorter than one 400 ms block is measured as a single ungated block
    so short one-shots still report a meaningful loudness.
    """
    if x.size == 0:
        return float("-inf")
    weighted = fft_filter(x, _k_weighting(fs), fs, pad_s=0.2)
    block = max(1, int(block_s * fs))
    hop = max(1, int(hop_s * fs))
    if weighted.size < block:
        ms = float(np.mean(weighted * weighted))
        if ms <= SILENCE_FLOOR:
            return float("-inf")
        return -0.691 + 10.0 * math.log10(ms)
    view = np.lib.stride_tricks.sliding_window_view(weighted, block)[::hop]
    ms = np.mean(view * view, axis=1)
    lj = -0.691 + 10.0 * np.log10(np.maximum(ms, SILENCE_FLOOR))

    gated = ms[lj > -70.0]
    if gated.size == 0:
        return float("-inf")
    rel = -0.691 + 10.0 * math.log10(float(np.mean(gated))) - 10.0
    gated2 = ms[(lj > -70.0) & (lj > rel)]
    if gated2.size == 0:
        return float("-inf")
    return -0.691 + 10.0 * math.log10(float(np.mean(gated2)))


# --------------------------------------------------------------------------- #
# Peaks and levels
# --------------------------------------------------------------------------- #


def true_peak(x: np.ndarray, factor: int = TRUE_PEAK_FACTOR) -> float:
    if x.size < 2:
        return float(np.max(np.abs(x))) if x.size else 0.0
    n = x.size
    m = n * factor
    xr = np.fft.rfft(x)
    y = np.zeros(m // 2 + 1, dtype=complex)
    y[:xr.size] = xr
    out = np.fft.irfft(y, m) * factor
    return float(np.max(np.abs(out)))


def lufs_event(x: np.ndarray, fs: int) -> float:
    """Ungated K-weighted loudness over the whole file (robust for any length)."""
    if x.size == 0:
        return float("-inf")
    weighted = fft_filter(x, _k_weighting(fs), fs, pad_s=0.05)
    ms = float(np.mean(weighted * weighted))
    if ms <= SILENCE_FLOOR:
        return float("-inf")
    return -0.691 + 10.0 * math.log10(ms)


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x * x))) if x.size else 0.0


def short_term_max(x: np.ndarray, fs: int, win_s: float = 0.05) -> float:
    win = max(1, int(win_s * fs))
    if x.size < win:
        return rms(x)
    view = np.lib.stride_tricks.sliding_window_view(x, win)
    return float(np.max(np.sqrt(np.mean(view * view, axis=1))))


# --------------------------------------------------------------------------- #
# Spectrum
# --------------------------------------------------------------------------- #


def average_spectrum(x: np.ndarray, fs: int, nfft: int = 8192) -> tuple[np.ndarray, np.ndarray]:
    """Welch-style averaged periodogram -> (freqs, power_per_bin)."""
    if x.size < 64:
        nfft = max(64, 1 << int(math.ceil(math.log2(max(x.size, 2)))))
    nfft = min(nfft, 1 << int(math.ceil(math.log2(max(x.size, 2)))))
    win = np.hanning(nfft)
    hop = max(1, nfft // 2)
    if x.size < nfft:
        seg = np.zeros(nfft)
        seg[:x.size] = x
        segs = seg[None, :]
    else:
        segs = np.lib.stride_tricks.sliding_window_view(x, nfft)[::hop]
    scale = 1.0 / (np.sum(win * win) * fs)
    acc = np.zeros(nfft // 2 + 1)
    for seg in segs:
        spec = np.fft.rfft(seg * win)
        acc += (spec.real ** 2 + spec.imag ** 2)
    acc *= scale / max(len(segs), 1)
    freqs = np.fft.rfftfreq(nfft, 1.0 / fs)
    return freqs, acc


def band_powers(freqs: np.ndarray, power: np.ndarray) -> dict[str, float]:
    total = float(np.sum(power)) or 1e-30
    out = {}
    for name, lo, hi in BANDS:
        sel = (freqs >= lo) & (freqs < hi)
        out[name] = pow_db(float(np.sum(power[sel])) / total)
    return out


def spectral_features(freqs: np.ndarray, power: np.ndarray) -> dict[str, float]:
    total = float(np.sum(power)) or 1e-30
    p = power / total
    centroid = float(np.sum(freqs * p))
    cumulative = np.cumsum(p)
    rolloff = float(freqs[int(np.searchsorted(cumulative, 0.95))]) if cumulative.size else 0.0
    positive = power[power > 0]
    flatness = float(np.exp(np.mean(np.log(positive))) / np.mean(positive)) if positive.size else 0.0
    # Spectral slope (dB per octave) over 100 Hz .. 10 kHz using log-log fit.
    sel = (freqs >= 100.0) & (freqs <= 10000.0) & (power > 0)
    slope = 0.0
    if np.count_nonzero(sel) > 8:
        lf = np.log2(freqs[sel])
        lp = 10.0 * np.log10(power[sel])
        slope = float(np.polyfit(lf, lp, 1)[0])
    return {
        "centroid_hz": centroid,
        "rolloff95_hz": rolloff,
        "flatness": flatness,
        "slope_db_per_oct": slope,
    }


def hum_prominence(freqs: np.ndarray, power: np.ndarray, fs: int) -> dict[str, float]:
    """Narrow-band prominence of mains hum and its odd harmonics."""
    out = {}
    for mains in (50.0, 60.0):
        if mains * 2 > fs / 2:
            continue
        tones = []
        for h in (1, 2, 3):
            f0 = mains * h
            band = (freqs > f0 * 0.985) & (freqs < f0 * 1.015)
            if not np.any(band):
                continue
            tone = float(np.max(power[band]))
            guard = (freqs > f0 * 0.80) & (freqs < f0 * 1.20) & ~band
            floor = float(np.median(power[guard])) if np.any(guard) else 1e-30
            tones.append(pow_db(tone / max(floor, 1e-30)))
        out[f"{int(mains)}hz_prominence_db"] = max(tones) if tones else 0.0
    out["hum_prominence_db"] = max(out.get("50hz_prominence_db", 0.0),
                                   out.get("60hz_prominence_db", 0.0))
    return out


def sub_30_ratio(freqs: np.ndarray, power: np.ndarray) -> float:
    total = float(np.sum(power)) or 1e-30
    sel = freqs < 30.0
    return float(np.sum(power[sel])) / total


# --------------------------------------------------------------------------- #
# Envelope / onset / seam
# --------------------------------------------------------------------------- #


def envelope(x: np.ndarray, fs: int, win_s: float = 0.002) -> np.ndarray:
    win = max(1, int(win_s * fs))
    if x.size < win:
        return np.array([rms(x)])
    view = np.lib.stride_tricks.sliding_window_view(x, win)
    return np.sqrt(np.mean(view * view, axis=1))


def frame_statistics(x: np.ndarray, fs: int, win_s: float = 0.02) -> dict[str, float]:
    win = max(1, int(win_s * fs))
    if x.size < win:
        return {"frame_win_s": win / fs, "floor_dbfs": -120.0}
    view = np.lib.stride_tricks.sliding_window_view(x, win)
    fr = np.sqrt(np.mean(view * view, axis=1))
    audible = fr[fr > 1e-6]
    floor = float(np.percentile(audible, 5)) if audible.size else 0.0
    return {"frame_win_s": win / fs, "floor_dbfs": db(floor)}


def onset_and_silence(x: np.ndarray, fs: int) -> dict[str, float]:
    env = envelope(x, fs)
    if env.size == 0:
        return {}
    peak = float(np.max(env)) or SILENCE_FLOOR
    thr = peak * 10.0 ** (-50.0 / 20.0)
    above = np.nonzero(env > thr)[0]
    onset_s = (above[0] * 0.002) if above.size else 0.0
    end_s = ((above[-1] + 1) * 0.002) if above.size else 0.0
    lead = float(onset_s)
    tail = max(0.0, float(x.size) / fs - end_s)
    first_audible = int(np.argmax(np.abs(x) > 1e-6)) if np.any(np.abs(x) > 1e-6) else 0
    return {
        "onset_s": onset_s,
        "lead_silence_s": lead,
        "tail_silence_s": tail,
        "digital_lead_s": first_audible / fs,
        "active_s": max(0.0, end_s - onset_s),
        "start_db": db(abs(float(x[0]))),
        "end_db": db(abs(float(x[-1]))),
        "peak_time_s": float(np.argmax(np.abs(x))) / fs,
    }


def attack_metrics(x: np.ndarray, fs: int) -> dict[str, float]:
    env = envelope(x, fs)
    peak = float(np.max(env)) or SILENCE_FLOOR
    hi = np.nonzero(env >= peak * 0.9)[0]
    lo = np.nonzero(env >= peak * 0.1)[0]
    if hi.size == 0 or lo.size == 0:
        return {"rise_s": 0.0}
    return {"rise_s": max(0.0, (hi[0] - lo[0]) * 0.002)}


def seam_metrics(x: np.ndarray, fs: int) -> dict[str, float]:
    """Discontinuity across the buffer wrap (x[-1] -> x[0])."""
    if x.size < 8:
        return {}
    steps = np.abs(np.diff(x))
    typical = float(np.percentile(steps, 99.0)) or SILENCE_FLOOR
    d0 = float(x[0] - x[-1])
    d_first = float(x[1] - x[0])
    d_last = float(x[-1] - x[-2])
    win = max(1, int(0.01 * fs))
    head_rms = rms(x[:win])
    tail_rms = rms(x[-win:])
    return {
        "seam_step": d0,
        "seam_ratio": abs(d0) / typical,
        "seam_slope_mismatch": abs(d_first - d_last),
        "seam_head_tail_rms_db": db(head_rms) - db(tail_rms),
        "seam_dc_mismatch": float(np.mean(x[:win]) - np.mean(x[-win:])),
    }


def quiet_regions(x: np.ndarray, fs: int, onset_s: float, tail_s: float) -> dict[str, float | None]:
    """RMS of the pre-attack and post-decay regions, when they actually exist."""
    out: dict[str, float | None] = {"head_floor_dbfs": None, "tail_floor_dbfs": None,
                                    "head_region_s": 0.0, "tail_region_s": 0.0}
    head_n = int(onset_s * fs)
    if head_n >= int(0.02 * fs):
        out["head_floor_dbfs"] = db(rms(x[:head_n]))
        out["head_region_s"] = head_n / fs
    tail_n = int(tail_s * fs)
    if tail_n >= int(0.02 * fs):
        out["tail_floor_dbfs"] = db(rms(x[-tail_n:]))
        out["tail_region_s"] = tail_n / fs
    return out


def clipping_metrics(x: np.ndarray) -> dict[str, float]:
    ax = np.abs(x)
    peak = float(np.max(ax)) if ax.size else 0.0
    if peak <= 0:
        return {"peak": 0.0, "flat_top_runs": 0.0, "near_peak_samples": 0.0}
    near = ax >= peak * 0.9995
    # Flat-top runs: >= 3 consecutive near-identical magnitudes at the ceiling.
    flat = near[1:] & near[:-1] & (np.abs(np.diff(ax)) <= 1.0 / 32768.0)
    flags = np.concatenate(([False], flat, [False]))
    edges = np.diff(flags.astype(np.int8))
    starts = np.flatnonzero(edges == 1)
    ends = np.flatnonzero(edges == -1)
    flat_runs = int(np.count_nonzero((ends - starts) >= 2))
    return {
        "peak": peak,
        "flat_top_runs": flat_runs,
        "near_peak_samples": int(np.count_nonzero(near)),
    }


# --------------------------------------------------------------------------- #
# Full file analysis
# --------------------------------------------------------------------------- #


def analyse(path: Path) -> dict:
    wav = read_wav(path)
    x = wav.mono()
    fs = wav.rate
    peak = float(np.max(np.abs(x))) if x.size else 0.0
    tp = true_peak(x)
    loudness = lufs_integrated(x, fs)
    st_max = short_term_max(x, fs)
    freqs, power = average_spectrum(x, fs)

    result = {
        "file": path.name,
        "sha256": wav.sha256,
        "sample_rate": fs,
        "channels": wav.channels,
        "bits": wav.bits,
        "frames": wav.frames,
        "duration_s": round(wav.duration, 6),
        "runtime_loadable": wav.runtime_ok,
        "runtime_reason": wav.runtime_reason,
        "dc_offset": float(np.mean(x)) if x.size else 0.0,
        "dc_offset_dbfs": db(abs(float(np.mean(x)))) if x.size else -120.0,
        "peak": peak,
        "peak_dbfs": db(peak),
        "true_peak": tp,
        "true_peak_dbfs": db(tp),
        "true_peak_over_db": db(tp) - db(peak),
        "true_peak_headroom_db": -db(tp),
        "rms_dbfs": db(rms(x)),
        "crest_db": db(peak) - db(rms(x)) if rms(x) > 0 else 0.0,
        "lufs": loudness,
        "event_lufs": lufs_event(x, fs),
        "short_term_max_lufs_approx_dbfs": db(st_max),
        "lra_est_db": db(st_max) - (loudness + 0.691) if loudness > -70 else 0.0,
        "sub_30_ratio": sub_30_ratio(freqs, power),
        "band_db": band_powers(freqs, power),
    }
    result.update(spectral_features(freqs, power))
    result.update(hum_prominence(freqs, power, fs))
    result.update(frame_statistics(x, fs))
    level = onset_and_silence(x, fs)
    result.update(level)
    result.update(quiet_regions(x, fs, float(level.get("lead_silence_s", 0.0)),
                                float(level.get("tail_silence_s", 0.0))))
    result.update(attack_metrics(x, fs))
    result.update(clipping_metrics(x))
    result["seam"] = seam_metrics(x, fs)
    peak_db = db(peak)
    result["tail_step_rel_db"] = db(abs(float(x[-1]))) - peak_db if x.size else -120.0
    result["head_step_rel_db"] = db(abs(float(x[0]))) - peak_db if x.size else -120.0
    result["noise_floor_dbfs"] = min(
        [v for v in (result["head_floor_dbfs"], result["tail_floor_dbfs"]) if v is not None],
        default=result["floor_dbfs"],
    )
    result["snr_db"] = db(peak) - result["noise_floor_dbfs"]
    return result


# --------------------------------------------------------------------------- #
# Repair primitives (used by clean_commons_bank)
# --------------------------------------------------------------------------- #


def remove_dc(x: np.ndarray, fs: int, cutoff_hz: float = 8.0) -> np.ndarray:
    """DC + sub-sonic removal: 2nd-order HPF (keeps kick/boom body)."""
    if x.size == 0:
        return x
    return fft_filter(x - float(np.mean(x)), [biquad_highpass(cutoff_hz, fs)], fs)


def repair_loop_seam(x: np.ndarray, fs: int, crossfade_ms: float = 20.0) -> tuple[np.ndarray, bool]:
    """Equal-power wrap crossfade; trims the tail by the fade length.

    The tail is blended into the head, so after trimming x[0] continues from the
    blended ending: the wrap stays continuous when the whole file loops.
    """
    fade = int(fs * crossfade_ms / 1000.0)
    if x.size <= 4 * fade + 16:
        return x, False
    steps = np.abs(np.diff(x))
    typical = float(np.percentile(steps, 99.0)) or SILENCE_FLOOR
    if abs(float(x[0] - x[-1])) <= typical:
        return x, False
    head = x[:fade].copy()
    tail = x[-fade:].copy()
    t = np.linspace(0.0, 1.0, fade, endpoint=False)
    blend = tail * np.cos(t * math.pi / 2.0) + head * np.sin(t * math.pi / 2.0)
    out = x[:-fade].copy()
    out[:fade] = blend
    return out, True


def fade_edges(x: np.ndarray, fs: int, fade_in_ms: float, fade_out_ms: float) -> np.ndarray:
    out = x.copy()
    n_in = min(int(fs * fade_in_ms / 1000.0), out.size)
    n_out = min(int(fs * fade_out_ms / 1000.0), out.size)
    if n_in > 1:
        out[:n_in] *= 0.5 - 0.5 * np.cos(np.linspace(0.0, math.pi, n_in))
    if n_out > 1:
        out[-n_out:] *= 0.5 + 0.5 * np.cos(np.linspace(0.0, math.pi, n_out))
    return out


def gate_head_noise(x: np.ndarray, fs: int, onset_s: float, threshold_db: float = -78.0) -> np.ndarray:
    """Silence the pre-attack hiss without touching the transient."""
    out = x.copy()
    start = int(min(max(onset_s - 0.003, 0.0), out.size / fs) * fs)
    if start <= 0:
        return out
    head = out[:start]
    out[:start] = np.where(np.abs(head) < 10.0 ** (threshold_db / 20.0), 0.0, head)
    return out


def soft_limit_true_peak(x: np.ndarray, ceiling_db: float) -> np.ndarray:
    """Attenuate so the true peak sits at the ceiling (crest preserved)."""
    tp = true_peak(x)
    if tp <= 0:
        return x
    gain = 10.0 ** ((ceiling_db - db(tp)) / 20.0)
    return x * min(gain, 1.0)


def normalise_true_peak(x: np.ndarray, ceiling_db: float) -> np.ndarray:
    tp = true_peak(x)
    if tp <= 0:
        return x
    return x * (10.0 ** ((ceiling_db - db(tp)) / 20.0))


def limit_true_peak(x: np.ndarray, fs: int, ceiling_db: float, lookahead_ms: float = 2.0,
                    max_reduction_db: float = 3.0) -> tuple[np.ndarray, float, float]:
    """Lookahead peak limiter that only touches the transient excess.

    The gain curve is the moving max of the required gain (so |y| <= ceiling at
    every sample) smoothed with a Hann kernel and re-clamped to that requirement.
    Returns (signal, max gain reduction dB, residual whole-file trim dB).
    """
    if x.size < 8:
        return x, 0.0, 0.0
    ceiling = 10.0 ** (ceiling_db / 20.0)
    look = max(1, int(lookahead_ms / 1000.0 * fs))
    ax = np.abs(x)
    padded = np.pad(ax, (look, look), mode="constant")
    env = np.lib.stride_tricks.sliding_window_view(padded, 2 * look + 1).max(axis=1)
    floor = 10.0 ** (-max_reduction_db / 20.0)
    need = np.clip(np.minimum(1.0, ceiling / np.maximum(env, 1e-9)), floor, 1.0)

    # Convolve on an edge-padded copy so the curve does not collapse at the ends.
    kernel = np.hanning(2 * look + 1)
    kernel /= kernel.sum()
    padded_need = np.pad(need, (look, look), mode="edge")
    smooth = np.convolve(padded_need, kernel, mode="valid")[: need.size]
    gain = np.minimum(need, smooth)

    y = x * gain
    reduction = -db(float(np.min(gain))) if float(np.min(gain)) < 1.0 else 0.0
    trim = 0.0
    tp = true_peak(y)
    if tp > ceiling:
        trim = ceiling / tp
        y = y * trim
        trim = db(trim)
    return y, reduction, trim


def dither_tpdf(x: np.ndarray, bits: int = 16, seed: int = 0) -> np.ndarray:
    rng = np.random.default_rng(seed)
    lsb = 1.0 / float(1 << (bits - 1))
    return x + (rng.random(x.size) - rng.random(x.size)) * lsb


def to_pcm16(x: np.ndarray, dither: bool = True, seed: int = 0) -> np.ndarray:
    y = dither_tpdf(np.clip(x, -1.0, 1.0), 16, seed) if dither else np.clip(x, -1.0, 1.0)
    return np.clip(np.round(y * 32768.0), -32768, 32767).astype("<i2")


def write_wav_pcm16(path: Path, x: np.ndarray, fs: int, channels: int = 1) -> None:
    if channels == 1:
        pcm = to_pcm16(x)
    else:
        pcm = to_pcm16(x)  # caller passes already-interleaved data via channels=1
    data = pcm.tobytes()
    header = bytearray()
    header += b"RIFF"
    header += (36 + len(data)).to_bytes(4, "little")
    header += b"WAVEfmt "
    header += (16).to_bytes(4, "little")
    header += (1).to_bytes(2, "little")
    header += channels.to_bytes(2, "little")
    header += fs.to_bytes(4, "little")
    header += (fs * channels * 2).to_bytes(4, "little")
    header += (channels * 2).to_bytes(2, "little")
    header += (16).to_bytes(2, "little")
    header += b"data"
    header += len(data).to_bytes(4, "little")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(bytes(header) + data)
