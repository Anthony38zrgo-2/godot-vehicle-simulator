"""Remaster the CMR2 Spanish voice bank from a preserved original directory."""
import argparse
import hashlib
import json
from pathlib import Path
import wave

import numpy as np
from scipy.signal import sosfilt

ROOT = Path(__file__).resolve().parents[2]
BANK = ROOT / "game/sounds/banks/pacenotes/cmr2/es"


def peak_filter(rate, frequency, gain_db, q):
    a = 10 ** (gain_db / 40)
    omega = 2 * np.pi * frequency / rate
    alpha = np.sin(omega) / (2 * q)
    c = np.cos(omega)
    return np.array([1 + alpha * a, -2*c, 1 - alpha*a,
                     1 + alpha/a, -2*c, 1 - alpha/a]) / (1 + alpha/a)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--originals", required=True, type=Path)
    args = parser.parse_args()
    manifest_path = BANK / "provenance.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    samples = manifest["samples"]
    if len(samples) != 59:
        raise ValueError("Expected 59 samples")
    sos = np.stack([peak_filter(11025, 1900, -4.0, 0.8), peak_filter(11025, 3200, -1.5, 1.0)])
    for item in samples:
        original = args.originals / item["file"]
        raw_hash = hashlib.sha256(original.read_bytes()).hexdigest()
        expected = item.get("original_sha256", item["sha256"])
        if raw_hash != expected:
            raise ValueError(f"Original hash mismatch: {original}")
    for item in samples:
        original = args.originals / item["file"]
        with wave.open(str(original), "rb") as wav:
            params = wav.getparams()
            if (params.nchannels, params.sampwidth, params.framerate, params.comptype) != (1, 2, 11025, "NONE"):
                raise ValueError(f"Unexpected format: {original}")
            x = np.frombuffer(wav.readframes(params.nframes), dtype="<i2").astype(np.float64) / 32768.0
        y = sosfilt(sos, x)
        rms = np.sqrt(np.mean(y * y)) if y.size else 0.0
        peak = np.max(np.abs(y)) if y.size else 0.0
        gain = min(10 ** (-16 / 20) / max(rms, 1e-12), 10 ** (-1 / 20) / max(peak, 1e-12), 4.0)
        pcm = np.clip(np.rint(y * gain * 32768), -32768, 32767).astype('<i2')
        with wave.open(str(BANK / item["file"]), "wb") as wav:
            wav.setparams(params)
            wav.writeframes(pcm.tobytes())
        item["original_sha256"] = item.get("original_sha256", item["sha256"])
        item["sha256"] = hashlib.sha256((BANK / item["file"]).read_bytes()).hexdigest()
        item["remaster_gain_db"] = round(float(20 * np.log10(gain)), 3)
    manifest["processing"] = {"source": "original_sha256", "eq": [{"hz": 1900, "gain_db": -4.0, "q": 0.8}, {"hz": 3200, "gain_db": -1.5, "q": 1.0}], "rms_target_dbfs": -16, "peak_ceiling_dbfs": -1, "max_gain_db": 12.0412, "method": "causal biquad EQ, per-file RMS gain bounded by peak; no resampling or compression", "tool": "tools/rally/remaster_cmr2_copilot.py"}
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Remastered {len(samples)} files; source: {args.originals}")


if __name__ == "__main__":
    main()
