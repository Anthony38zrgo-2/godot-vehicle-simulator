"""Native sample extraction and explicitly labelled acoustic approximations."""
from __future__ import annotations

import hashlib
import io
import wave
from pathlib import Path

import numpy as np

from .archives import get
from .common import write_json
from .config_parser import vector


def pcm(blob):
    with wave.open(io.BytesIO(blob), "rb") as stream:
        rate, channels, width, count = stream.getframerate(), stream.getnchannels(), stream.getsampwidth(), stream.getnframes()
        raw = stream.readframes(count)
    if width != 2 or channels not in (1, 2):
        raise ValueError("Expected mono/stereo PCM16 native WAV")
    return np.frombuffer(raw, dtype="<i2").astype(np.float64).reshape(-1, channels) / 32768.0, rate, channels


def encode(data, rate):
    if data.ndim == 1:
        data = data[:, None]
    output = io.BytesIO()
    with wave.open(output, "wb") as stream:
        stream.setnchannels(data.shape[1])
        stream.setsampwidth(2)
        stream.setframerate(rate)
        stream.writeframes((np.clip(data, -0.98, 0.98) * 32767).astype("<i2").tobytes())
    return output.getvalue()


def build_bank(files, sounds, engine, recipe, destination, provenance):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    samples, names = [], {}

    def store(name, blob, origin, source_name=None):
        # Unique bus keys across banks; original bytes still match the archive.
        actual = recipe["id"] + "__" + name
        (destination / actual).write_bytes(blob)
        data, rate, channels = pcm(blob)
        rms = float(np.sqrt(np.mean(data * data)))
        sample = {"file": actual, "sha256": hashlib.sha256(blob).hexdigest(), "origin": origin,
                  "source_file": source_name or name, "rate_hz": rate, "channels": channels,
                  "seconds": len(data) / rate, "rms": rms, "gain": min(0.12 / max(rms, 0.001), 3.0),
                  "space": {"eq": {"enabled": False}}}
        samples.append(sample)
        return sample

    # Keep all originals, including unused samples; record actual channels/rate.
    for name, blob in files.items():
        if name.lower().endswith(".wav"):
            names[name.casefold()] = store(name, blob, "native_byte_identical")

    def native(name):
        if not isinstance(name, str) or name.casefold() not in names:
            raise ValueError(f"Missing native sound {name!r}; supply it explicitly in recipe sound_aliases")
        return names[name.casefold()]

    for name, alias in recipe.get("sound_aliases", {}).items():
        # Aliases refer only to explicit local archive files, never silently to another car.
        names[name.casefold()] = native(alias)

    base = "res://sounds/banks/" + recipe["id"] + "/"
    idle_rpm = float(engine.get("IdleRpm", 1100))
    definitions = {}
    for role, prefix in [("engine", "Engine"), ("exhaust", "Exhaust")]:
        idle = native(sounds[prefix + "SoundIdle"])
        driven = []
        for i in range(1, 10):
            key = prefix + "Sound" + str(i)
            if key not in sounds:
                break
            source = native(sounds[key])
            interval = vector(sounds, key + "Range")
            driven.append((source, interval))
        if not driven:
            raise ValueError(f"No {role} sample ranges in Sounds.ini")
        centers = [float(interval[1]) for _, interval in driven]

        def definition(sample, ref, lower, upper, mode):
            return {"path": base + sample["file"], "reference": ref, "lower": lower, "upper": upper,
                    "mode": mode, "gain": sample["gain"]}

        load = [definition(idle, idle_rpm, 0, max(idle_rpm * 1.8, centers[0]), "idle")]
        coast = []
        for i, (sample, interval) in enumerate(driven):
            ref = centers[i]
            # The old mixer uses triangular overlaps; convert game fade ranges to
            # overlapping intervals that remain audible at both range boundaries.
            lower = max(0, centers[i - 1] - 200) if i else 0
            upper = centers[i + 1] + 1000 if i + 1 < len(centers) else max(ref * 2.5, 15000)
            load.append(definition(sample, ref, lower, upper, "drive"))
            source_name = sample["source_file"]
            data, rate, _ = pcm(get(files, source_name))
            frequency = np.fft.rfftfreq(len(data), 1 / rate)
            filtered = np.fft.irfft(np.fft.rfft(data, axis=0) / (1 + (frequency[:, None] / 1700) ** 4), n=len(data), axis=0)
            derived = store(f"{role}_coast_{i + 1}.wav", encode(filtered, rate), "derived_lowpass_coast", source_name)
            coast.append(definition(derived, ref, lower, upper, "coast"))
        definitions[role], definitions["coast_" + role] = load, coast

    rate = 22050
    t = np.arange(rate * 2) / rate
    whine = []
    for label, frequency in [("low", 360), ("high", 720)]:
        data = sum(0.1 / (i * i) * np.sin(2 * np.pi * frequency * i * t) for i in range(1, 5))
        sample = store(f"whine_{label}.wav", encode(data, rate), "synthesized_generic_gearbox")
        whine.append(base + sample["file"])
    backfire = []
    loudest = next((sounds[k] for k in ["ExhaustSound3", "ExhaustSound2", "ExhaustSound1"] if k in sounds))
    source = native(loudest)
    data, rate, _ = pcm(get(files, source["source_file"]))
    count = int(rate * 0.16)
    for i in range(3):
        start = min(i * int(rate * 0.07), max(len(data) - count, 0))
        grain = np.resize(data[start:start + count], (count, data.shape[1]))
        envelope = np.exp(-np.arange(count) / (rate * 0.032)) * np.minimum(np.arange(count) / (rate * 0.0015), 1)
        sample = store(f"lift_{i + 1}.wav", encode(grain * envelope[:, None] * 1.5, rate), "derived_lift_approximation", source["source_file"])
        backfire.append(base + sample["file"])
    manifest = {"schema_version": 1, "vehicle_id": recipe["id"], "source": provenance, "samples": samples,
                **definitions, "whine": whine, "backfire": backfire,
                "engine_position": _position(sounds, "EngineLoc", [0, 0.5, 1]),
                "exhaust_position": _position(sounds, "ExhaustLoc", [0, 0.1, -1.5]),
                "calibration": "RPM centres from Sounds.ini; overlap adapted to shared mixer. Native recordings unchanged. Coast/lift derived; gearbox synthesized."}
    write_json(destination / "manifest.json", manifest)
    return manifest


def _position(config, key, default):
    v = vector(config, key, default)
    return [v[0], v[1], -v[2]]
