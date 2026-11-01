"""Extract untouched Escort RS1600 PCM WAVs and record reproducible provenance.
Run: python -m tools.audio.cmr4_escort [CMR4 installation directory]
RPM references are local calibration estimates, not measured recording RPM.
"""
from pathlib import Path
import hashlib
import io
import json
import sys
import wave
import numpy as np
from tools.audio.cmr4_surfaces import parse_archive, decrypt, KEY_OFFSET, KEY_LENGTH

ROOT = Path(__file__).resolve().parents[2]
BANK = ROOT / "game/sounds/banks/EscortRS1600"
REFERENCES = [1800, 3000, 4200, 5500, 6800]

def main():
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\ASETS\CMR4\Colin McRae Rally 04")
    executable = (source / "cmr4.exe").read_bytes()
    key = executable[KEY_OFFSET:KEY_OFFSET + KEY_LENGTH]
    BANK.mkdir(parents=True, exist_ok=True)
    samples = []
    archives = []
    levels_path = ROOT / "game/data/rally/audio_sample_levels.json"
    levels = json.loads(levels_path.read_text(encoding="utf-8"))
    for archive_name in ("escort.big", "escortx.big"):
        archive = source / "Data/Sounds/Car" / archive_name
        data = archive.read_bytes()
        archives.append({"file": str(archive), "sha256": hashlib.sha256(data).hexdigest()})
        _, _, entries = parse_archive(data)
        for entry in entries:
            raw = decrypt(data[entry.absolute_offset:entry.absolute_offset + entry.size], key)
            with wave.open(io.BytesIO(raw)) as wav:
                assert wav.getnchannels() == 1 and wav.getsampwidth() == 2 and wav.getcomptype() == "NONE"
                rate = wav.getframerate()
                frames = wav.getnframes()
                pcm = np.frombuffer(wav.readframes(frames), dtype="<i2").astype(float) / 32768
            reference = 1050 if "_stat" in entry.name else REFERENCES[int(entry.name[-6:-4]) - 1] if entry.name.startswith(("e_", "x_")) else None
            role = ("engine" if entry.name.startswith("e_") else "exhaust") if archive_name == "escort.big" else "event"
            if "whine" in entry.name:
                role = "gearbox_whine"
            rms = float(np.sqrt(np.mean(pcm ** 2)))
            rms_db = float(20 * np.log10(max(rms, 1e-9)))
            sample = {"file": entry.name, "role": role, "source_archive": archive_name,
                      "source_sha256": hashlib.sha256(raw).hexdigest(), "mix_rate_hz": rate,
                      "channels": 1, "bits": 16, "duration_s": frames / rate,
                      "reference_rpm": reference, "reference_origin": "local estimated calibration" if reference else None}
            if role in ("engine", "exhaust"):
                levels["samples"][entry.name] = {"source_rms_db": rms_db, "gain": 10 ** ((-12 - rms_db) / 20)}
            (BANK / entry.name).write_bytes(raw)
            samples.append(sample)
    manifest = {"contract_version": 1, "bank_id": "EscortRS1600", "source_game": "Colin McRae Rally 04",
                "archives": archives, "samples": samples,
                "policy": "Unmodified native PCM. e/x interpreted as engine/exhaust; stat as idle, thr as loaded and idle01-05 as coast. Local RPM references 1050/1800/3000/4200/5500/6800 are estimates, not decoded original FL/NMAP curves. loadoff events replace lift pops; not asserted to be combustion backfires. Ignition and stall retained as inventory. Shared limiter, impacts and surfaces remain in their own banks."}
    for name in ("escort.cfg", "escort.fl"):
        raw = (source / "Data/Sounds/Car" / name).read_bytes()
        (BANK / name).write_bytes(raw)
    (BANK / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    levels_path.write_text(json.dumps(levels, indent=2) + "\n", encoding="utf-8")
    print(f"Extracted {len(samples)} verified native WAV files to {BANK}")

if __name__ == "__main__":
    main()
