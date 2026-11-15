"""Generate schema_version 1 manifest.json files for all gp4-sfx engine banks."""

from __future__ import annotations

import hashlib
import json
import math
import re
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GP4_ROOT = ROOT / "game" / "sounds" / "banks" / "gp4-sfx"
VEHICLES_ROOT = ROOT / "game" / "data" / "vehicles"

TARGET_RMS = 0.12
RPM_RE = re.compile(r"^\d+_rpm(\d+)\.wav$")

CAR_CONFIGS = {
    "Alfa Romeo Giulia GTA": {
        "vehicle_id": "rt-alfa-giulia-gta",
        "powertrain": "rt/rt-alfa-giulia-gta",
        "engine_position": [0.0, 0.5, -1.0],
        "exhaust_position": [0.0, 0.1, 1.0],
    },
    "Alpine A110 1600": {
        "vehicle_id": "rt-alpine-a110",
        "powertrain": "rt/rt-alpine-a110",
        "engine_position": [0.0, 0.5, 0.5],
        "exhaust_position": [0.0, 0.2, 1.0],
    },
    "Fiat-Abarth 1000 TC": {
        "vehicle_id": "rt-fiat-abarth-1000",
        "powertrain": "rt/rt-fiat-abarth-1000",
        "engine_position": [0.0, 0.4, 0.8],
        "exhaust_position": [0.0, 0.1, 1.0],
    },
    "Ford Escort Mk1 RS2000": {
        "vehicle_id": "ford_escort_rs2000",
        "powertrain": "ford-escort-rs2000",
        "engine_position": [0.0, 0.55, -0.8],
        "exhaust_position": [0.0, 0.2, 1.5],
    },
    "Ford Lotus Cortina Mk1": {
        "vehicle_id": "rt-lotus-cortina",
        "powertrain": "rt/rt-lotus-cortina",
        "engine_position": [0.0, 0.5, -0.8],
        "exhaust_position": [0.0, 0.1, 1.0],
    },
    "Lancia Fulvia 1.6 HF": {
        "vehicle_id": "lancia_fulvia_1600_hf",
        "powertrain": "lancia-fulvia",
        "engine_position": [0.0, 0.55, -0.8],
        "exhaust_position": [0.0, 0.2, 1.5],
    },
    "Lancia Stratos HF": {
        "vehicle_id": "rt-lancia-stratos",
        "powertrain": "rt/rt-lancia-stratos",
        "engine_position": [0.0, 0.5, 0.5],
        "exhaust_position": [0.0, 0.1, 1.0],
    },
    "Mini Cooper S 1275 Mk1": {
        "vehicle_id": "rt-mini-cooper-s",
        "powertrain": "rt/rt-mini-cooper-s",
        "engine_position": [0.0, 0.5, 0.5],
        "exhaust_position": [0.0, 0.1, 0.9],
    },
    "Opel Kadett B Rallye": {
        "vehicle_id": "rt-opel-kadett",
        "powertrain": "rt/rt-opel-kadett",
        "engine_position": [0.0, 0.5, -1.0],
        "exhaust_position": [0.0, 0.2, 1.0],
    },
    "Saab 96 V4": {
        "vehicle_id": "rt-saab-96-v4",
        "powertrain": "rt/rt-saab-96-v4",
        "engine_position": [0.0, 0.5, -1.0],
        "exhaust_position": [0.0, 0.0, 1.0],
    },
    "Volvo Amazon 122S": {
        "vehicle_id": "rt-volvo-amazon",
        "powertrain": "rt/rt-volvo-amazon",
        "engine_position": [0.0, 0.5, -1.0],
        "exhaust_position": [0.0, 0.1, 1.0],
    },
}

COMMONS_WHINE = [
    "res://sounds/banks/commons/whinelo.wav",
    "res://sounds/banks/commons/whinehi.wav",
]

COMMONS_BACKFIRE = [
    "res://sounds/banks/commons/backfire_ext_1.wav",
    "res://sounds/banks/commons/backfire_ext_2.wav",
    "res://sounds/banks/commons/backfire_ext_3.wav",
    "res://sounds/banks/commons/backfire_ext_4.wav",
]


def inspect_wav(path: Path) -> tuple[int, int, float, str]:
    data = path.read_bytes()
    sha = hashlib.sha256(data).hexdigest()
    with wave.open(str(path), "rb") as w:
        rate = w.getframerate()
        channels = w.getnchannels()
        frames = w.readframes(w.getnframes())
    samples = struct.unpack("<" + "h" * (len(frames) // 2), frames)
    rms = math.sqrt(sum(s * s for s in samples) / max(len(samples), 1)) / 32768.0
    return rate, channels, rms, sha


def build_manifest(folder_name: str, cfg: dict) -> dict:
    folder = GP4_ROOT / folder_name
    pt_path = VEHICLES_ROOT / cfg["powertrain"] / "powertrain.json"
    max_rpm = float(json.loads(pt_path.read_text(encoding="utf-8"))["powertrain"]["max_rpm"])

    wav_entries: list[tuple[int, Path]] = []
    for p in sorted(folder.glob("*.wav")):
        m = RPM_RE.match(p.name)
        if m:
            wav_entries.append((int(m.group(1)), p))
    wav_entries.sort(key=lambda item: item[0])

    samples = []
    engine = []
    for idx, (rpm, wav_path) in enumerate(wav_entries):
        rate, channels, rms, sha = inspect_wav(wav_path)
        gain = TARGET_RMS / max(rms, 1e-6)
        res_path = f"res://sounds/banks/gp4-sfx/{folder_name}/{wav_path.name}"
        samples.append(
            {
                "file": wav_path.name,
                "sha256": sha,
                "rate_hz": rate,
                "channels": channels,
                "base_rpm": rpm,
                "rms": rms,
                "gain": gain,
            }
        )
        lower = 0 if idx == 0 else wav_entries[idx - 1][0]
        upper = int(max_rpm + 3500) if idx == len(wav_entries) - 1 else wav_entries[idx + 1][0]
        engine.append(
            {
                "path": res_path,
                "reference": rpm,
                "lower": lower,
                "upper": upper,
                "mode": "idle" if idx == 0 else "continuous",
                "gain": gain,
            }
        )

    return {
        "schema_version": 1,
        "vehicle_id": cfg["vehicle_id"],
        "source": "Gran Turismo 4 (gp4-sfx engine-only)",
        "whine": COMMONS_WHINE,
        "backfire": COMMONS_BACKFIRE,
        "engine_position": cfg["engine_position"],
        "exhaust_position": cfg["exhaust_position"],
        "samples": samples,
        "engine": engine,
        "exhaust": [],
    }


def main() -> None:
    for folder_name, cfg in CAR_CONFIGS.items():
        manifest = build_manifest(folder_name, cfg)
        out_path = GP4_ROOT / folder_name / "manifest.json"
        out_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        print(f"Wrote {out_path} ({len(manifest['engine'])} engine layers)")


if __name__ == "__main__":
    main()
