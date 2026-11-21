#!/usr/bin/env python3
"""
Build the dedicated GT3 engine + exhaust sound bank for the VW Golf Mk1 GTI Gr.2:
  game/sounds/banks/gt3-bank/vw-golf-mk1/

Uses BOTH `engine/` (8 layers, 800..7000 rpm) and `exhaust_normal0_turbo0/`
(8 layers, 800..7000 rpm) from:
  D:\\RallyManiacAssets\\engine-samples\\engine_samples\\banks\\33801 - Mazda MX-5 Miata LS (+2)
mastered through the 6-step clean_gt3_bank DSP pipeline, while keeping all
auxiliary audios (whine, backfire, shifts, impacts, surfaces, limiter) shared
from `res://sounds/banks/commons/`.
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
OUT_BANK_DIR = REPO / "game" / "sounds" / "banks" / "gt3-bank" / "vw-golf-mk1"
SOUND_ID = 33801
CEILING_DB = -3.0


def load_layer_rows(bank_group: str) -> list[dict]:
    with open(SRC_ROOT / "LAYERS_INDEX.csv", encoding="utf-8-sig") as f:
        rows = [
            r
            for r in csv.DictReader(f)
            if r["sound_id"] == str(SOUND_ID) and r["bank_group"] == bank_group
        ]
    rows.sort(key=lambda r: int(r["layer_index"]))
    assert len(rows) == 8, f"Expected 8 layers for sound_id={SOUND_ID} group={bank_group}, got {len(rows)}"
    return rows


def build_golf_recipe(role: str, base_rpm: int, sr_in: int) -> clean.FilterRecipe:
    factor = clean.upsample_factor_for(sr_in)
    nyq_in = sr_in / 2.0
    if base_rpm <= 1100:
        hpf_hz = 16.0
    else:
        crank_hz = base_rpm / 60.0
        hpf_hz = float(np.clip(0.65 * crank_hz, 16.0, 55.0))

    if role == "engine":
        # Tame nasal 1.8-3.2 kHz boosted by Godot EQ10 and clean 240 Hz mud
        bells = [
            (240.0, -2.0, 0.9),
            (1850.0, -2.0, 0.85),
            (3200.0, -1.5, 0.9),
        ]
        lowshelf = None
        pivot = 450.0
    else:
        # Warm, punchy 8V rally exhaust; keep low-end clean without boom
        bells = [
            (230.0, -1.8, 0.85),
            (950.0, +1.0, 0.75),
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
        "engine": ("engine", -28.0, -18.5, 0.80),
        "exhaust": ("exhaust_normal0_turbo0", -26.5, -18.0, 0.85),
    }
    role_defs: dict[str, list[dict]] = {"engine": [], "exhaust": []}

    for role, (bank_group, lo_db, hi_db, exp_p) in role_targets.items():
        rows = load_layer_rows(bank_group)
        role_dir = OUT_BANK_DIR / role
        role_dir.mkdir(parents=True, exist_ok=True)
        processed_info: list[tuple[int, str, float]] = []

        print(f"Processing {role} from {bank_group}...")
        for r in rows:
            idx = int(r["layer_index"])
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
            recipe = build_golf_recipe(role, base_rpm, sr_in)
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
            y_i16 = clean.tpdf_quantize_loop(y, f"vw-golf-mk1/{rel_file}")
            y_q = y_i16.astype(np.float64) / 32768.0
            tp_q = audit.db(audit.true_peak(y_q))
            if tp_q > CEILING_DB + 0.02:
                nudge = 10.0 ** ((CEILING_DB - 0.05 - tp_q) / 20.0)
                y_i16 = clean.tpdf_quantize_loop(y * nudge, f"vw-golf-mk1/{rel_file}_nudge")
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
                    "path": f"res://sounds/banks/gt3-bank/vw-golf-mk1/{rel_file}",
                    "reference": base_rpm,
                    "lower": lower,
                    "upper": upper,
                    "mode": mode,
                    "gain": gain,
                }
            )

    manifest = {
        "schema_version": 1,
        "vehicle_id": "vw_golf_mk1_gti",
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
        "engine_position": [0.0, 0.48, -0.95],
        "exhaust_position": [-0.38, 0.20, 1.75],
        "source": "Gran Turismo 3: A-Spec USA v1.10 (banks/33801 - Mazda MX-5 Miata LS (+2): engine + exhaust_normal0_turbo0)",
        "sound_id": SOUND_ID,
        "samples": samples_meta,
        "engine": role_defs["engine"],
        "exhaust": role_defs["exhaust"],
    }

    manifest_path = OUT_BANK_DIR / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"VW_GOLF_MK1_GT3_BANK_BUILT_OK: {manifest_path}")


if __name__ == "__main__":
    main()
