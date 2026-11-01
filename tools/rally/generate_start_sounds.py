"""Deterministic original countdown sounds, 48 kHz mono 16-bit PCM. No samples used."""
import math
from pathlib import Path
import random
import struct
import wave

RATE = 48000
OUT = Path(__file__).resolve().parents[2] / "game/sounds/rally_start"

def write(name, duration, sample):
    count = int(duration * RATE)
    values = []
    for i in range(count):
        t = i / RATE
        envelope = min(1.0, t / 0.003) * min(1.0, (duration - t) / 0.025)
        value = sample(t) * envelope
        assert abs(value) < 1.0
        values.append(struct.pack("<h", round(value * 32767)))
    with wave.open(str(OUT / name), "wb") as wav:
        wav.setparams((1, 2, RATE, count, "NONE", "not compressed"))
        wav.writeframes(b"".join(values))

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    noise = random.Random(1974)
    write("ready_click.wav", 0.11, lambda t: (0.55 * math.sin(2 * math.pi * 1100 * t) + 0.1 * noise.uniform(-1, 1)) * math.exp(-t * 38))
    write("go_horn.wav", 0.65, lambda t: (0.32 * math.sin(2 * math.pi * 440 * t) + 0.24 * math.sin(2 * math.pi * 554.365 * t) + 0.12 * math.sin(2 * math.pi * 880 * t)) * (0.95 + 0.05 * math.sin(2 * math.pi * 23 * t)))
    print(OUT)
