#!/usr/bin/env python3
"""
Build the dedicated GT3 flat-6 engine + exhaust sound bank for the 1972-1973 Porsche 911 2.4 S:
  game/sounds/banks/gt3-bank/porsche-911-24s/

Uses BOTH:
  - `engine/` (6 layers, 900..6000 rpm)
  - `exhaust_turbo0/` layer 0 (900 rpm idle) + `exhaust_normal0-3_turbo1_turbo3/` (7 layers, 1400..6928 rpm)
from:
  D:\\RallyManiacAssets\\engine-samples\\engine_samples\\banks\\22803 - 911(996) GT3 (+1)
mastered through the 6-step clean_gt3_bank DSP pipeline, while keeping all auxiliary
audios (whine, backfire, shifts, impacts, surfaces, limiter) shared from `res://sounds/banks/commons/`.
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
OUT_BANK_DIR = REPO / "game" / "sounds" / "banks" / "gt3-bank" / "porsche-911-24s"
SOUND_ID = 22803
CEILING_DB = -3.0


def load_rows_for_role(role: str) -> list[dict]:
    with open(SRC_ROOT / "LAYERS_INDEX.csv", encoding="utf-8-sig") as f:
        all_rows = [r for r in csv.DictReader(f) if r["sound_id"] == str(SOUND_ID)]

    if role == "engine":
        rows = [r for r in all_rows if r["bank_group"] == "engine"]
        rows.sort(key=lambda r: int(r["base_rpm"]))
        assert len(rows) == 6, f"Expected 6 engine layers for {SOUND_ID}, got {len(rows)}"
        return rows

    # Exhaust: 900 rpm idle from exhaust_turbo0 + 1400..6928 rpm from exhaust_normal0-3_turbo1_turbo3
    idle_rows = [r for r in all_rows if r["bank_group"] == "exhaust_turbo0" and int(r["base_rpm"]) == 900]
    drive_rows = [r for r in all_rows if r["bank_group"] == "exhaust_normal0-3_turbo1_turbo3"]
    rows = idle_rows + drive_rows
    rows.sort(key=lambda r: int(r["base_rpm"]))
    assert len(rows) == 8, f"Expected 8 combined exhaust layers for {SOUND_ID}, got {len(rows)}"
    return rows


def build_porsche_recipe(role: str, base_rpm: int, sr_in: int) -> clean.FilterRecipe:
    factor = clean.upsample_factor_for(sr_in)
    nyq_in = sr_in / 2.0
    if base_rpm <= 1100:
        hpf_hz = 16.0
    else:
        crank_hz = base_rpm / 60.0
        hpf_hz = float(np.clip(0.65 * crank_hz, 16.0, 55.0))

    if role == "engine":
        # Preserve air-cooled flat-6 mechanical fan & MFI bite while taming harsh nasal peak
        bells = [
            (240.0, -2.0, 0.9),
            (1850.0, -1.8, 0.85),
            (3200.0, -1.2, 0.9),
        ]
        lowshelf = None
        pivot = 450.0
    else:
        # Crisp flat-6 exhaust bark with clean low end
        bells = [
            (220.0, -1.8, 0.85),
            (950.0, +1.2, 0.75),
        ]
        lowshelf = (95.0, -1.5) if base_rpm >= 2500 else None
        pivot = 220.0

    return clean.FilterRecipe(
        hpf_hz=hpf_hz,
        lpf_start_hz=0.86 * nyq_in,
        lpf_end_hz=0.98 * nyq_in,
        bells=bells,
        lowshelf=lowshelf,
        highshelf=None,
        tilt_db_per_oct=0.0,
        tilt_pivot_hz=pivot,
        upsample_factor=factor,
    )


def main() -> None:
    samples_meta: list[dict] = []
    role_targets = {
        "engine": (-28.0, -18.5, 0.80),
        "exhaust": (-26.5, -18.0, 0.85),
    }
    role_defs: dict[str, list[dict]] = {"engine": [], "exhaust": []}

    for role, (lo_db, hi_db, exp_p) in role_targets.items():
        rows = load_rows_for_role(role)
        role_dir = OUT_BANK_DIR / role
        role_dir.mkdir(parents=True, exist_ok=True)
        processed_info: list[tuple[int, str, float]] = []

        print(f"Processing {role} ({len(rows)} layers)...")
        for idx, r in enumerate(rows):
            base_rpm = int(r["base_rpm"])
            src_wav_path = SRC_ROOT / r["wav_path"]
            rel_file = f"{role}/{role}_layer{idx:02d}_{base_rpm:05d}rpm.wav"
            dst_wav_path = OUT_BANK_DIR / rel_file

            wav = audit.read_wav(src_wav_path)
            sr_in = wav.rate
            ls = max(0, min(wav.frames - 2, int(r["loop_start_sample"])))
            le = max(ls + 2, min(wav.frames, int(r["loop_end_sample"])))
            core = wav.mono()[ls:le]

            y, _, seam_note = clean.repair_loop_seam_phase_aligned(core, sr_in)
            y, _ = clean.declip_plateaus(y)
            recipe = build_porsche_recipe(role, base_rpm, sr_in)
            y = clean.apply_filter_recipe(y, sr_in, recipe)
            if recipe.upsample_factor > 1:
                y = clean.resample_periodic_fft(y, recipe.upsample_factor)
            sr_out = sr_in * recipe.upsample_factor
            y, _ = clean.circular_dewobble(y, sr_out, threshold_db=2.2)

            fade = int(512.0 * sr_out / 44100.0)
            if y.size < 4 * fade:
                reps = math.ceil((4 * fade) / max(y.size, 1))
                y = np.tile(y, reps)

            tp_pre = audit.db(audit.true_peak(y))
            scale = 10.0 ** (((CEILING_DB - 0.08) - tp_pre) / 20.0)
            y *= scale
            y_i16 = clean.tpdf_quantize_loop(y, f"porsche-911-24s/{rel_file}")
            y_q = y_i16.astype(np.float64) / 32768.0
            tp_q = audit.db(audit.true_peak(y_q))
            if tp_q > CEILING_DB + 0.02:
                nudge = 10.0 ** ((CEILING_DB - 0.05 - tp_q) / 20.0)
                y_i16 = clean.tpdf_quantize_loop(y * nudge, f"porsche-911-24s/{rel_file}_nudge")
                y_q = y_i16.astype(np.float64) / 32768.0
                tp_q = audit.db(audit.true_peak(y_q))

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

        rpms = [item[0] for item in processed_info]
        rpm_min, rpm_max = float(min(rpms)), float(max(rpms))
        span_rpm = max(rpm_max - rpm_min, 1.0)
        for i, (base_rpm, rel_file, hybrid_eq) in enumerate(processed_info):
            lower = 0 if i == 0 else processed_info[i - 1][0]
            upper = 12000 if i == len(processed_info) - 1 else processed_info[i + 1][0]
            mode = "idle" if i == 0 else "continuous"
            t_norm = min(1.0, max(0.0, (float(base_rpm) - rpm_min) / span_rpm))
            target_db = lo_db + (hi_db - lo_db) * (t_norm ** exp_p)
            gain = float(np.clip(10.0 ** ((target_db - hybrid_eq) / 20.0), 0.02, 0.85))
            role_defs[role].append(
                {
                    "path": f"res://sounds/banks/gt3-bank/porsche-911-24s/{rel_file}",
                    "reference": base_rpm,
                    "lower": lower,
                    "upper": upper,
                    "mode": mode,
                    "gain": gain,
                }
            )

    manifest = {
        "schema_version": 1,
        "vehicle_id": "porsche_911_24s",
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
        "engine_position": [0.0, 0.42, 1.38],
        "exhaust_position": [-0.35, 0.22, 1.98],
        "source": (
            "Gran Turismo 3: A-Spec USA v1.10 (banks/22803 - 911(996) GT3 (+1): "
            "engine 6 layers 900-6000 rpm + exhaust 900 rpm idle + exhaust_normal0-3_turbo1_turbo3 1400-6928 rpm)"
        ),
        "sound_id": SOUND_ID,
        "samples": samples_meta,
        "engine": role_defs["engine"],
        "exhaust": role_defs["exhaust"],
    }

    manifest_path = OUT_BANK_DIR / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"PORSCHE_911_24S_GT3_BANK_BUILT_OK: {manifest_path}")


if __name__ == "__main__":
    main()
