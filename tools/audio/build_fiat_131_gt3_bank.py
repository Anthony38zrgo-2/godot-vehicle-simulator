#!/usr/bin/env python3
"""
Build the dedicated GT3 engine sound bank for the Fiat Abarth 131 Rally Group 4:
  game/sounds/banks/gt3-bank/fiat-131-abarth/

Uses ONLY the `engine/` samples from:
  D:\\RallyManiacAssets\\engine-samples\\engine_samples\\banks\\33406 - Spoon S2000(J)\\engine
(2.0L L4 DOHC 16V Naturally Aspirated FR competition engine, 8 layers 1000..8000 rpm),
mastered through the 6-step clean_gt3_bank DSP pipeline, while keeping all auxiliary
audios (whine, backfire, shifts, impacts, surfaces, limiter) shared from `commons`.
"""

from __future__ import annotations

import csv
import hashlib
import json
import math
from pathlib import Path
import sys

import numpy as np

REPO = Path(__file__).resolve().parents[2]
if str(REPO) not in sys.path:
    sys.path.insert(0, str(REPO))

from tools.audio import commons_audit as audit
from tools.audio import clean_gt3_bank as clean

SRC_ROOT = Path(r"D:\RallyManiacAssets\engine-samples\engine_samples")
SRC_BANK_DIR = SRC_ROOT / "banks" / "33406 - Spoon S2000(J)" / "engine"
OUT_BANK_DIR = REPO / "game" / "sounds" / "banks" / "gt3-bank" / "fiat-131-abarth"
SOUND_ID = 33406
CEILING_DB = -3.0


def load_engine_layer_rows() -> list[dict]:
    with open(SRC_ROOT / "LAYERS_INDEX.csv", encoding="utf-8-sig") as f:
        rows = [
            r
            for r in csv.DictReader(f)
            if r["sound_id"] == str(SOUND_ID) and r["bank_group"] == "engine"
        ]
    rows.sort(key=lambda r: int(r["layer_index"]))
    assert len(rows) == 8, f"Expected 8 engine layers for sound_id={SOUND_ID}, got {len(rows)}"
    return rows


def build_fiat131_recipe(base_rpm: int, sr_in: int) -> clean.FilterRecipe:
    factor = clean.upsample_factor_for(sr_in)
    nyq_in = sr_in / 2.0
    if base_rpm <= 1100:
        hpf_hz = 16.0
    else:
        crank_hz = base_rpm / 60.0
        hpf_hz = float(np.clip(0.65 * crank_hz, 16.0, 55.0))

    # Tame low-mid 220 Hz mud and bring out 850-950 Hz twin-cam 16V mechanical induction presence
    bells = [
        (220.0, -2.5, 0.9),
        (900.0, +1.5, 0.75),
    ]
    return clean.FilterRecipe(
        hpf_hz=hpf_hz,
        lpf_start_hz=0.86 * nyq_in,
        lpf_end_hz=0.98 * nyq_in,
        bells=bells,
        lowshelf=None,
        highshelf=None,
        tilt_db_per_oct=0.0,
        tilt_pivot_hz=450.0,
        upsample_factor=factor,
    )


def main() -> None:
    rows = load_engine_layer_rows()
    eng_out_dir = OUT_BANK_DIR / "engine"
    eng_out_dir.mkdir(parents=True, exist_ok=True)

    samples_meta: list[dict] = []
    processed_info: list[tuple[int, str, float]] = []

    for r in rows:
        idx = int(r["layer_index"])
        base_rpm = int(r["base_rpm"])
        src_wav_path = SRC_ROOT / r["wav_path"]
        rel_file = f"engine/engine_layer{idx:02d}_{base_rpm:05d}rpm.wav"
        dst_wav_path = OUT_BANK_DIR / rel_file

        wav = audit.read_wav(src_wav_path)
        sr_in = wav.rate
        ls = max(0, min(wav.frames - 2, int(r["loop_start_sample"])))
        le = max(ls + 2, min(wav.frames, int(r["loop_end_sample"])))
        core = wav.mono()[ls:le]

        # Step 1a: Phase-aligned seam repair
        y, _, seam_note = clean.repair_loop_seam_phase_aligned(core, sr_in)
        # Step 2a: Declip plateaus
        y, _ = clean.declip_plateaus(y)
        # Step 2b + 4: Zero-phase periodic FFT filter & EQ
        recipe = build_fiat131_recipe(base_rpm, sr_in)
        y = clean.apply_filter_recipe(y, sr_in, recipe)
        # Step 3: Periodic FFT upsampling
        if recipe.upsample_factor > 1:
            y = clean.resample_periodic_fft(y, recipe.upsample_factor)
        sr_out = sr_in * recipe.upsample_factor
        # Step 5a: Circular de-wobble
        y, _ = clean.circular_dewobble(y, sr_out, threshold_db=2.2)

        fade = int(512.0 * sr_out / 44100.0)
        if y.size < 4 * fade:
            reps = math.ceil((4 * fade) / max(y.size, 1))
            y = np.tile(y, reps)

        # Step 5b: -3.0 dBFS true-peak normalization + deterministic TPDF dither
        tp_pre = audit.db(audit.true_peak(y))
        scale = 10.0 ** (((CEILING_DB - 0.08) - tp_pre) / 20.0)
        y *= scale
        y_i16 = clean.tpdf_quantize_loop(y, f"fiat-131-abarth/{rel_file}")
        y_q = y_i16.astype(np.float64) / 32768.0
        tp_q = audit.db(audit.true_peak(y_q))
        if tp_q > CEILING_DB + 0.02:
            nudge = 10.0 ** ((CEILING_DB - 0.05 - tp_q) / 20.0)
            y_i16 = clean.tpdf_quantize_loop(y * nudge, f"fiat-131-abarth/{rel_file}_nudge")
            y_q = y_i16.astype(np.float64) / 32768.0
            tp_q = audit.db(audit.true_peak(y_q))

        # Step 1b: Pack [preroll y_i16[-fade:] + y_i16]
        packed_i16 = np.concatenate([y_i16[-fade:], y_i16])
        clean.write_i16_wav(dst_wav_path, packed_i16, sr_out)

        sha = hashlib.sha256(dst_wav_path.read_bytes()).hexdigest()
        loop_end_frames = fade + y_i16.size
        loop_meta = {"start_s": 0.0, "end_s": float(loop_end_frames + 0.25) / float(sr_out)}
        _, _, hybrid_eq = clean.measure_post_eq10_loudness(y_q, sr_out)

        samples_meta.append(
            {
                "file": rel_file,
                "sha256": sha,
                "rate_hz": int(sr_out),
                "base_rpm": base_rpm,
                "loop": loop_meta,
                "key": Path(rel_file).stem,
            }
        )
        processed_info.append((base_rpm, rel_file, hybrid_eq))
        print(
            f"  Layer {idx:02d} ({base_rpm:4d} rpm): sr={sr_in}->{sr_out} Hz | "
            f"TP={tp_q:+.2f} dBFS | hybrid={hybrid_eq:+.2f} dB | seam={seam_note}"
        )

    # Step 6: Build engine & exhaust definitions from the 8 engine layers with calibrated gains
    rpms = [item[0] for item in processed_info]
    rpm_min, rpm_max = float(min(rpms)), float(max(rpms))
    span_rpm = max(rpm_max - rpm_min, 1.0)

    role_targets = {
        "engine": (-28.0, -18.5, 0.80),
        "exhaust": (-26.5, -18.0, 0.85),
    }
    role_defs: dict[str, list[dict]] = {"engine": [], "exhaust": []}

    for role, (lo_db, hi_db, exp_p) in role_targets.items():
        for i, (base_rpm, rel_file, hybrid_eq) in enumerate(processed_info):
            lower = 0 if i == 0 else processed_info[i - 1][0]
            upper = 12000 if i == len(processed_info) - 1 else processed_info[i + 1][0]
            mode = "idle" if i == 0 else "continuous"
            t_norm = min(1.0, max(0.0, (float(base_rpm) - rpm_min) / span_rpm))
            target_db = lo_db + (hi_db - lo_db) * (t_norm ** exp_p)
            gain = float(np.clip(10.0 ** ((target_db - hybrid_eq) / 20.0), 0.02, 0.85))
            role_defs[role].append(
                {
                    "path": f"res://sounds/banks/gt3-bank/fiat-131-abarth/{rel_file}",
                    "reference": base_rpm,
                    "lower": lower,
                    "upper": upper,
                    "mode": mode,
                    "gain": gain,
                }
            )

    manifest = {
        "schema_version": 1,
        "vehicle_id": "fiat_131_abarth",
        "whine": [
            "res://sounds/banks/commons/whinelo.wav",
            "res://sounds/banks/commons/whinehi.wav",
        ],
        "backfire": [
            "res://sounds/banks/commons/backfire_ext_1.wav",
            "res://sounds/banks/commons/backfire_ext_2.wav",
            "res://sounds/banks/commons/backfire_ext_3.wav",
            "res://sounds/banks/commons/backfire_ext_4.wav",
        ],
        "engine_position": [0.0, 0.52, -0.92],
        "exhaust_position": [0.0, 0.22, 1.95],
        "source": "Gran Turismo 3: A-Spec USA v1.10 (banks/33406 - Spoon S2000(J)/engine)",
        "sound_id": SOUND_ID,
        "samples": samples_meta,
        "engine": role_defs["engine"],
        "exhaust": role_defs["exhaust"],
    }

    manifest_path = OUT_BANK_DIR / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"FIAT_131_GT3_BANK_BUILT_OK: {manifest_path}")


if __name__ == "__main__":
    main()
