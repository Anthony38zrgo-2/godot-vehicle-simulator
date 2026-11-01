"""Render an isolated, reproducible surface audition (no spatialization/engine).
Each of gravel, grass, dirt, tarmac: 2 s rolling, 2 s rolling+slip, 0.5 s silence.
Run: python -m tools.audio.preview_surfaces
"""
from pathlib import Path
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
BANK = ROOT / "game/sounds/banks/surfaces"
RATE = 22050

def loop(path, duration):
    with wave.open(str(path), "rb") as w:
        assert w.getnchannels() == 1 and w.getframerate() == RATE and w.getsampwidth() == 2
        data = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(float) / 32768
    return np.resize(data, round(duration * RATE))

def main():
    mapping = json.loads((BANK / "manifest.json").read_text())["runtime_map"]
    sections = []
    for name in ["gravel", "grass", "dirt", "tarmac"]:
        roles = mapping[name]
        for slipping in [False, True]:
            data = loop(BANK / roles["roll"], 2) * (0.06 if slipping else 0.20)
            if slipping:
                data += loop(BANK / roles["skid"], 2) * 0.18
            fade = round(0.08 * RATE)
            data[:fade] *= np.linspace(0, 1, fade)
            data[-fade:] *= np.linspace(1, 0, fade)
            sections.append(data)
        sections.append(np.zeros(round(0.5 * RATE)))
    data = np.concatenate(sections)
    assert np.max(np.abs(data)) < 1, "preview clips"
    output = ROOT / "game/logs/rally/cmr4_surface_audition.wav"
    output.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(output), "wb") as w:
        w.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        w.writeframes(np.round(data * 32767).astype("<i2").tobytes())
    print(output)
    print("Order: gravel 0s, grass 4.5s, dirt 9s, tarmac 13.5s; each: rolling then slip.")
if __name__ == "__main__":
    main()
