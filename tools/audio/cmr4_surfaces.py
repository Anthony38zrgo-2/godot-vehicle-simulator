"""Reproducible extraction and preparation of Colin McRae Rally 04 surface sounds.

Subcommands
  extract  Read cmr4.exe and Data/Sounds/Surfaces/surfaces.big, locate and verify the
           512-byte XOR key by decrypting every entry and validating RIFF headers, then
           write the decrypted WAV files verbatim with their original names.
  prepare  Build the runtime WAVs for the surfaces bank: DC removal, RMS-based level
           with a sample-peak ceiling, and a baked equal-power loop crossfade.
           Writes game/sounds/banks/surfaces/manifest.json with every hash.
  verify   Re-check raw and prepared hashes, WAV formats, runtime mapping and the
           absence of retired surface references in code and data.

The CMR4 executable is only read; it is never copied into the repository.
Usage (from the repository root):
  python -m tools.audio.cmr4_surfaces extract --cmr4-root "D:\\ASETS\\CMR4\\Colin McRae Rally 04"
  python -m tools.audio.cmr4_surfaces prepare
  python -m tools.audio.cmr4_surfaces verify
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import struct
import sys
import wave
from dataclasses import dataclass
from pathlib import Path

import numpy as np

TOOL_REVISION = 1
KEY_OFFSET = 1483808
KEY_LENGTH = 512
ENTRY_TABLE_OFFSET = 0x24
ENTRY_SIZE = 0x18
SAMPLE_RATE = 22050
PEAK_CEILING_DBFS = -1.0
PEAK_CEILING = 10.0 ** (PEAK_CEILING_DBFS / 20.0)
LOOP_CROSSFADE_S = 0.120
ARCHIVE_RELATIVE = Path("Data/Sounds/Surfaces/surfaces.big")
CONFIG_RELATIVE = Path("Data/Sounds/Config/surfaces.cfg")
EXECUTABLE_NAME = "cmr4.exe"
DEFAULT_CMR4_ROOT = Path(r"D:\ASETS\CMR4\Colin McRae Rally 04")

REPO_ROOT = Path(__file__).resolve().parents[2]
RAW_DIR = REPO_ROOT / "game" / "sounds" / "bank_sources" / "cmr4" / "surfaces"
RAW_MANIFEST = RAW_DIR / "source_manifest.json"
CFG_ROLES_PATH = RAW_DIR / "surfaces_cfg_roles.json"
BANK_DIR = REPO_ROOT / "game" / "sounds" / "banks" / "surfaces"
MANIFEST_PATH = BANK_DIR / "manifest.json"
COMMONS_MANIFEST = REPO_ROOT / "game" / "sounds" / "banks" / "commons" / "bank_manifest.json"

FAMILY_SURFACE = {
    "grv": "gravel",
    "grs": "grass",
    "drt": "dirt",
    "tar": "tarmac",
    "mud": "mud",
    "sno": "snow",
    "ice": "ice",
    "mul": "special",
}
EVENT_NAMES = {"catgrid", "bridge", "splash"}
ROLE_LETTERS = {"p": "peel", "s": "skid", "l": "lock"}
CFG_KEY_ROLES = {
    "INTERIOR_ROLL_FILENAME": "interior_roll",
    "EXTERIOR_ROLL_FILENAME": "exterior_roll",
    "INTERIOR_PEEL_FILENAME": "interior_peel",
    "EXTERIOR_PEEL_FILENAME": "exterior_peel",
    "INTERIOR_SKID_FILENAME": "interior_skid",
    "EXTERIOR_SKID_FILENAME": "exterior_skid",
    "INTERIOR_LOCK_FILENAME": "interior_lock",
    "EXTERIOR_LOCK_FILENAME": "exterior_lock",
}

# Runtime mapping used by the rally mix. Only these files are referenced at runtime; every
# other prepared sample is inventory. Selection basis is recorded per entry in the manifest.
RUNTIME_MAP = {
    "gravel": {"roll": "cmr4/gravel/grv_er11.wav", "skid": "cmr4/gravel/grv_es1.wav"},
    "grass": {"roll": "cmr4/grass/grs_er11.wav", "skid": "cmr4/grass/grs_es1.wav"},
    "dirt": {"roll": "cmr4/dirt/drt_er11.wav", "skid": "cmr4/dirt/drt_es1.wav"},
    "tarmac": {
        "roll": "cmr4/tarmac/tar_er21.wav",
        "skid": "cmr4/tarmac/tar_s2.wav",
        "peel": "cmr4/tarmac/tar_p2.wav",
        "lock": "cmr4/tarmac/tar_l2.wav",
    },
    "sand": {"roll": "legacy/surf_sand.wav"},
    "rumble": {"roll": "legacy/surf_rumble.wav"},
}
RUNTIME_FILES = {path for roles in RUNTIME_MAP.values() for path in roles.values()}
# Commons surface files that leave commons (migrated to the surfaces bank or retired).
RETIRED_COMMONS_FILES = ["surf_grass.wav", "surf_gravel.wav", "surf_sand.wav", "surf_rumble.wav", "tyre_scrub.wav"]
RETIRED_REFERENCE_TOKENS = ["surf_grass", "surf_gravel", "surf_sand", "surf_rumble", "tyre_scrub"]


class CmrError(RuntimeError):
    pass


@dataclass(frozen=True)
class ArchiveEntry:
    index: int
    name: str
    size: int
    relative_offset: int
    absolute_offset: int


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_archive(data: bytes) -> tuple[int, int, list[ArchiveEntry]]:
    if data[:4] != b"BIGF":
        raise CmrError("archive signature is not BIGF")
    count, data_start = struct.unpack_from("<II", data, 4)
    entries: list[ArchiveEntry] = []
    for index in range(count):
        base = ENTRY_TABLE_OFFSET + index * ENTRY_SIZE
        name = data[base:base + 16].split(b"\x00", 1)[0].decode("ascii")
        size, relative = struct.unpack_from("<II", data, base + 16)
        absolute = data_start + relative
        if absolute + size > len(data):
            raise CmrError(f"entry {name} exceeds archive bounds")
        entries.append(ArchiveEntry(index, name, size, relative, absolute))
    return count, data_start, entries


def decrypt(encrypted: bytes, key: bytes) -> bytes:
    cipher = np.frombuffer(encrypted, dtype=np.uint8)
    repeated = np.resize(np.frombuffer(key, dtype=np.uint8), cipher.size)
    return (cipher ^ repeated).tobytes()


def inspect_wav(data: bytes) -> dict:
    """Validate a RIFF/WAVE file as PCM16 mono at SAMPLE_RATE and return its header facts."""
    if len(data) < 12 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise CmrError("missing RIFF/WAVE header")
    riff_size = struct.unpack_from("<I", data, 4)[0]
    if riff_size + 8 != len(data):
        raise CmrError("RIFF size does not match the file length")
    fmt = None
    data_size = None
    position = 12
    while position + 8 <= len(data):
        chunk_id = data[position:position + 4]
        size = struct.unpack_from("<I", data, position + 4)[0]
        start = position + 8
        if start + size > len(data):
            raise CmrError("chunk exceeds file length")
        if chunk_id == b"fmt ":
            fmt = struct.unpack_from("<HHIIHH", data, start)
        elif chunk_id == b"data":
            data_size = size
        position = start + size + (size & 1)
    if fmt is None or data_size is None:
        raise CmrError("fmt or data chunk missing")
    audio_format, channels, rate, _byte_rate, block_align, bits = fmt
    if audio_format != 1 or channels != 1 or rate != SAMPLE_RATE or bits != 16 or block_align != 2:
        raise CmrError(f"unexpected format fmt={fmt}")
    frames = data_size // 2
    return {"sample_rate": rate, "channels": channels, "bits": bits, "frames": frames, "duration_s": frames / rate}


def key_is_valid(key: bytes, archive: bytes, entries: list[ArchiveEntry]) -> bool:
    for entry in entries:
        encrypted = archive[entry.absolute_offset:entry.absolute_offset + entry.size]
        try:
            inspect_wav(decrypt(encrypted, key))
        except CmrError:
            return False
    return True


def locate_key(executable: bytes, archive: bytes, entries: list[ArchiveEntry]) -> tuple[bytes, str]:
    """Use the recorded offset first, then search by the RIFF prefix; both need a full verification."""
    if KEY_OFFSET + KEY_LENGTH <= len(executable):
        candidate = executable[KEY_OFFSET:KEY_OFFSET + KEY_LENGTH]
        if key_is_valid(candidate, archive, entries):
            return candidate, f"offset:{KEY_OFFSET}"
    first = entries[0]
    head = archive[first.absolute_offset:first.absolute_offset + 4]
    prefix = bytes(cipher ^ plain for cipher, plain in zip(head, b"RIFF"))
    position = executable.find(prefix)
    while position != -1:
        candidate = executable[position:position + KEY_LENGTH]
        if len(candidate) == KEY_LENGTH and key_is_valid(candidate, archive, entries):
            return candidate, f"search:{position}"
        position = executable.find(prefix, position + 1)
    raise CmrError("no 512-byte key verified every RIFF entry")


def parse_config_roles(config: bytes) -> list[dict]:
    """Return surface blocks in file order: SURFACE_INDEX (float32 at name+7) and FILENAME roles.

    The config is a binary record stream (CONF header); the layout was established by inspecting
    the file, not from a published format. Each SURFACE_INDEX value is a float32 at its name end + 7.
    """
    surface_hits = [(match.start(), struct.unpack_from("<f", config, match.end() + 7)[0])
                    for match in re.finditer(b"SURFACE_INDEX", config)]
    token_pattern = re.compile(rb"[a-z]{3}_[a-z]{1,2}\d{1,2}")
    events: list[tuple[int, str, object]] = []
    for position, value in surface_hits:
        events.append((position, "SURFACE", value))
    for key in CFG_KEY_ROLES:
        for match in re.finditer(key.encode("ascii"), config):
            events.append((match.start(), key, None))
    for match in token_pattern.finditer(config):
        events.append((match.start(), "TOKEN", match.group().decode("ascii")))
    events.sort(key=lambda event: event[0])
    blocks: list[dict] = []
    current: dict | None = None
    last_key: str | None = None
    for _position, kind, value in events:
        if kind == "SURFACE":
            current = {"block": len(blocks), "surface_index": float(value), "roles": {}}
            blocks.append(current)
            last_key = None
        elif kind == "TOKEN":
            if current is not None and last_key is not None:
                role = CFG_KEY_ROLES[last_key]
                files = current["roles"].setdefault(role, [])
                if value not in files:
                    files.append(value)
        else:
            last_key = kind
    return [
        {"block": block["block"], "surface_index": block["surface_index"],
         "roles": {role: block["roles"][role] for role in sorted(block["roles"])}}
        for block in blocks
    ]


def classify(name: str) -> dict:
    stem = Path(name).stem
    lowered = stem.lower()
    if lowered in EVENT_NAMES:
        return {"family": None, "folder": "special", "surface": "event", "domain": "event",
                "role": "event", "role_class": "event", "set": None, "variant": None}
    match = re.fullmatch(r"([a-z]{3})_([a-z]{1,2})(\d)(\d?)", lowered)
    if not match:
        raise CmrError(f"unrecognised sample name: {name}")
    family, letters, set_digit, variant = match.groups()
    if family not in FAMILY_SURFACE:
        raise CmrError(f"unknown family: {family}")
    surface = FAMILY_SURFACE[family]
    folder = "special" if surface == "special" else surface
    if letters in ("er", "ir"):
        domain = "exterior" if letters[0] == "e" else "interior"
        role, role_class = "roll", "roll"
    elif letters in ("es", "is"):
        domain = "exterior" if letters[0] == "e" else "interior"
        role, role_class = "slip", "slip"
    elif letters in ROLE_LETTERS:
        domain = "shared"
        role, role_class = ROLE_LETTERS[letters], "slip"
    else:
        raise CmrError(f"unknown role letters in {name}: {letters}")
    return {"family": family, "folder": folder, "surface": surface, "domain": domain, "role": role,
            "role_class": role_class, "set": int(set_digit), "variant": int(variant) if variant else None}


def read_pcm16(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as handle:
        frames = handle.readframes(handle.getnframes())
    return np.frombuffer(frames, dtype="<i2").astype(np.float64) / 32768.0


def write_pcm16(path: Path, samples: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.clip(np.round(samples * 32768.0), -32768, 32767).astype("<i2").tobytes()
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(pcm)


def dbfs(value: float) -> float:
    return 20.0 * math.log10(max(value, 1e-12))


def level_metrics(samples: np.ndarray) -> dict:
    return {
        "rms_dbfs": dbfs(float(np.sqrt(np.mean(samples * samples)))),
        "peak": float(np.max(np.abs(samples))),
    }


def spectral_centroid_hz(samples: np.ndarray) -> float:
    window = 2048
    hop = 512
    if samples.size < window:
        return 0.0
    frames = np.lib.stride_tricks.sliding_window_view(samples, window)[::hop]
    spectrum = np.abs(np.fft.rfft(frames * np.hanning(window), axis=1))
    freqs = np.fft.rfftfreq(window, 1.0 / SAMPLE_RATE)
    energy = spectrum.sum(axis=1)
    centroid = (spectrum * freqs).sum(axis=1) / np.maximum(energy, 1e-12)
    return float(np.mean(centroid))


def modulation_db(samples: np.ndarray) -> float:
    window = int(0.05 * SAMPLE_RATE)
    if samples.size < window:
        return 0.0
    frames = np.lib.stride_tricks.sliding_window_view(samples, window)[::window // 2]
    levels = 20.0 * np.log10(np.maximum(np.sqrt(np.mean(frames * frames, axis=1)), 1e-6))
    return float(np.std(levels))


def loop_crossfade(body: np.ndarray, tail: np.ndarray) -> np.ndarray:
    """Equal-power head/tail blend: out[0] = tail[0] and out[L-1] = body[L-1], so the wrap
    from out[-1] = body[-1] to out[0] = tail[0] follows the recorded sample order."""
    length = tail.size
    if length < 2:
        return body
    position = np.linspace(0.0, 1.0, length)
    head_weight = np.sin(0.5 * math.pi * position)
    tail_weight = np.cos(0.5 * math.pi * position)
    blended = body.copy()
    blended[:length] = body[:length] * head_weight + tail[:length] * tail_weight
    return blended


def wrap_metric(samples: np.ndarray) -> float:
    steps = np.abs(np.diff(samples))
    wrap_step = abs(samples[0] - samples[-1])
    typical = float(np.percentile(steps, 99)) if steps.size else 0.0
    return float(wrap_step / max(typical, 1e-9))


def cmd_extract(arguments: argparse.Namespace) -> int:
    root = Path(arguments.cmr4_root)
    executable_path = root / EXECUTABLE_NAME
    archive_path = root / ARCHIVE_RELATIVE
    config_path = root / CONFIG_RELATIVE
    for path in (executable_path, archive_path, config_path):
        if not path.is_file():
            raise CmrError(f"missing source file: {path}")
    executable = executable_path.read_bytes()
    archive = archive_path.read_bytes()
    config = config_path.read_bytes()
    count, data_start, entries = parse_archive(archive)
    if count != len(entries) or count != 59:
        raise CmrError(f"expected 59 entries, found {len(entries)}")
    key, locator = locate_key(executable, archive, entries)
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    records = []
    for entry in entries:
        encrypted = archive[entry.absolute_offset:entry.absolute_offset + entry.size]
        plain = decrypt(encrypted, key)
        facts = inspect_wav(plain)
        target = RAW_DIR / entry.name
        target.write_bytes(plain)
        records.append({
            "name": entry.name,
            "archive_index": entry.index,
            "archive_relative_offset": entry.relative_offset,
            "archive_absolute_offset": entry.absolute_offset,
            "archive_size": entry.size,
            "frames": facts["frames"],
            "duration_s": round(facts["duration_s"], 6),
            "sample_rate": facts["sample_rate"],
            "channels": facts["channels"],
            "bits": facts["bits"],
            "sha256": sha256_bytes(plain),
        })
    roles = parse_config_roles(config)
    CFG_ROLES_PATH.write_text(json.dumps({"source_sha256": sha256_bytes(config), "blocks": roles}, indent=2) + "\n", encoding="utf-8")
    source = {
        "tool_revision": TOOL_REVISION,
        "executable_name": EXECUTABLE_NAME,
        "executable_sha256": sha256_file(executable_path),
        "archive_relative_path": ARCHIVE_RELATIVE.as_posix(),
        "archive_sha256": sha256_bytes(archive),
        "archive_signature": "BIGF",
        "archive_data_start": data_start,
        "archive_entry_count": count,
        "config_relative_path": CONFIG_RELATIVE.as_posix(),
        "config_sha256": sha256_bytes(config),
        "config_surface_blocks": len(roles),
        "key_length": KEY_LENGTH,
        "key_locator": locator,
        "key_sha256": sha256_bytes(key),
        "cipher": "xor-repeating-512 over the file start (verified by RIFF/WAVE decode of all entries)",
        "entries": records,
    }
    RAW_MANIFEST.write_text(json.dumps(source, indent=2) + "\n", encoding="utf-8")
    print(f"extracted {len(records)} WAV files to {RAW_DIR}")
    print(f"key locator: {locator}")
    return 0


def load_raw_manifest() -> dict:
    if not RAW_MANIFEST.is_file():
        raise CmrError("run extract first: raw source manifest is missing")
    return json.loads(RAW_MANIFEST.read_text(encoding="utf-8"))


def cfg_blocks_for(name: str, roles: list[dict]) -> dict:
    stem = Path(name).stem.lower()
    used = []
    for block in roles:
        for role, files in block["roles"].items():
            if any(Path(file).stem == stem for file in files):
                used.append((block["surface_index"], role))
    indices = sorted({int(index) for index, _role in used})
    keys = sorted({role for _index, role in used})
    return {"surface_indices": indices, "roles": keys}


def cmd_prepare(_arguments: argparse.Namespace) -> int:
    source = load_raw_manifest()
    roles = json.loads(CFG_ROLES_PATH.read_text(encoding="utf-8"))["blocks"]
    raw_entries = source["entries"]
    analysed = []
    for entry in raw_entries:
        raw_path = RAW_DIR / entry["name"]
        if sha256_file(raw_path) != entry["sha256"]:
            raise CmrError(f"raw sample changed since extraction: {entry['name']}")
        samples = read_pcm16(raw_path)
        dc_mean = float(np.mean(samples))
        centred = samples - dc_mean
        levels = level_metrics(centred)
        analysed.append({
            "entry": entry,
            "meta": classify(entry["name"]),
            "centred": centred,
            "dc_mean_lsb": dc_mean * 32768.0,
            "source_levels": levels,
            "centroid_hz": spectral_centroid_hz(centred),
            "modulation_db": modulation_db(centred),
        })
    targets = {}
    for role_class in ("roll", "slip"):
        values = [item["source_levels"]["rms_dbfs"] for item in analysed
                  if item["meta"]["role_class"] == role_class and item["meta"]["domain"] in ("exterior", "shared")]
        targets[role_class] = float(np.median(values))
    loop_length = int(round(LOOP_CROSSFADE_S * SAMPLE_RATE))
    prepared_records = []
    for item in analysed:
        entry = item["entry"]
        meta = item["meta"]
        centred = item["centred"]
        is_event = meta["role_class"] == "event"
        if not is_event and centred.size < 4 * loop_length:
            raise CmrError(f"sample too short for loop crossfade: {entry['name']}")
        # One-shot events take the exterior roll level law; loops take their class target.
        target = targets["roll" if is_event else meta["role_class"]]
        gain = 10.0 ** ((target - item["source_levels"]["rms_dbfs"]) / 20.0)
        peak_limited = PEAK_CEILING / max(float(np.max(np.abs(centred))), 1e-9)
        limited_by_peak = gain > peak_limited
        gain = min(gain, peak_limited)
        scaled = centred * gain
        if is_event:
            blended = scaled
            body_length = scaled.size
            loop_record = {"mode": "none", "runtime_fade": False}
        else:
            body_length = scaled.size - loop_length
            blended = loop_crossfade(scaled[:body_length].copy(), scaled[body_length:])
            loop_record = {"mode": "baked_equal_power", "crossfade_ms": LOOP_CROSSFADE_S * 1000.0,
                           "crossfade_frames": loop_length, "body_frames": body_length,
                           "runtime_fade": False}
        peak_after_blend = float(np.max(np.abs(blended)))
        limiter = min(1.0, PEAK_CEILING / max(peak_after_blend, 1e-12))
        blended *= limiter
        folder = BANK_DIR / "cmr4" / meta["folder"] / entry["name"]
        write_pcm16(folder, blended)
        prepared_levels = level_metrics(blended)
        prepared_records.append({
            "file": folder.relative_to(BANK_DIR).as_posix(),
            "original_name": entry["name"],
            "family": meta["family"],
            "surface": meta["surface"],
            "domain": meta["domain"],
            "role": meta["role"],
            "role_class": meta["role_class"],
            "set": meta["set"],
            "variant": meta["variant"],
            "status": "active" if folder.relative_to(BANK_DIR).as_posix() in RUNTIME_FILES else "inventory",
            "raw": {"path": f"game/sounds/bank_sources/cmr4/surfaces/{entry['name']}", "sha256": entry["sha256"],
                    "frames": entry["frames"], "duration_s": entry["duration_s"],
                    "sample_rate": entry["sample_rate"], "channels": entry["channels"], "bits": entry["bits"]},
            "prepared": {"sha256": sha256_file(folder), "sample_rate": SAMPLE_RATE, "channels": 1, "bits": 16,
                         "frames": blended.size, "duration_s": round(blended.size / SAMPLE_RATE, 6),
                         "rms_dbfs": round(prepared_levels["rms_dbfs"], 3), "peak_dbfs": round(dbfs(prepared_levels["peak"]), 3)},
            "processing": {
                "dc_mean_removed_lsb": round(item["dc_mean_lsb"], 4),
                "source_rms_dbfs": round(item["source_levels"]["rms_dbfs"], 3),
                "source_peak_dbfs": round(dbfs(item["source_levels"]["peak"]), 3),
                "target_rms_dbfs": round(target, 3),
                "gain_db": round(20.0 * math.log10(gain), 3),
                "gain_limited_by_peak": bool(limited_by_peak),
                "limiter_scale_db": round(20.0 * math.log10(limiter), 4),
                "loop": loop_record,
                "wrap_step_ratio": round(wrap_metric(blended), 4) if not is_event else None,
            },
            "analysis": {"spectral_centroid_hz": round(item["centroid_hz"], 1), "modulation_db": round(item["modulation_db"], 3)},
            "cfg": cfg_blocks_for(entry["name"], roles),
            # Read by VehicleSoundRouting: a baked loop must not receive the runtime 512-frame fade.
            **({"loop": loop_record} if not is_event else {}),
        })
    legacy = []
    commons_records = {}
    if COMMONS_MANIFEST.is_file():
        for record in json.loads(COMMONS_MANIFEST.read_text(encoding="utf-8")).get("files", []):
            commons_records[record["file"]] = record
    for legacy_path in sorted((BANK_DIR / "legacy").glob("*.wav")) if (BANK_DIR / "legacy").is_dir() else []:
        provenance = commons_records.get(legacy_path.name, {})
        legacy.append({
            "file": legacy_path.relative_to(BANK_DIR).as_posix(),
            "status": "legacy_fallback",
            "sha256": sha256_file(legacy_path),
            "provenance": provenance.get("provenance", "moved from commons; see git history"),
            "previous_commons_sha256": provenance.get("sha256"),
        })
    manifest = {
        "bank_name": "surfaces",
        "schema_version": 1,
        "generator": f"tools/audio/cmr4_surfaces.py revision {TOOL_REVISION}",
        "source": {
            "game": "Colin McRae Rally 04",
            "executable_sha256": source["executable_sha256"],
            "archive": source["archive_relative_path"],
            "archive_sha256": source["archive_sha256"],
            "config": source["config_relative_path"],
            "config_sha256": source["config_sha256"],
            "key_locator": source["key_locator"],
            "key_sha256": source["key_sha256"],
            "raw_manifest": "game/sounds/bank_sources/cmr4/surfaces/source_manifest.json",
            "raw_manifest_sha256": sha256_file(RAW_MANIFEST),
            "config_roles": "game/sounds/bank_sources/cmr4/surfaces/surfaces_cfg_roles.json",
            "config_roles_sha256": sha256_file(CFG_ROLES_PATH),
        },
        "format": {"sample_rate": SAMPLE_RATE, "channels": 1, "bits": 16, "source": "PCM16 mono 22050 Hz (verified)"},
        "preparation": {
            "dc_removed": True,
            "level_law": "gain = min(target_rms / source_rms, ceiling / source_peak); target = median RMS of exterior/shared samples per role class",
            "target_rms_dbfs": {key: round(value, 3) for key, value in targets.items()},
            "peak_ceiling_dbfs": PEAK_CEILING_DBFS,
            "loop": {"mode": "baked_equal_power", "crossfade_ms": LOOP_CROSSFADE_S * 1000.0,
                     "runtime_fade": False, "law": "out[i] = body[i]*sin(pi/2*i/(L-1)) + tail[i]*cos(pi/2*i/(L-1))"},
            "length_change": "each loop loses the crossfade length (120 ms); pitch and sample rate are unchanged",
        },
        "runtime_map": RUNTIME_MAP,
        "runtime_map_basis": {
            "gravel": "grv_er11: first exterior roll of gravel set 1; the scenario's Gravel group is the stage road and terrain",
            "grass": "grs_er11: first exterior roll of grass set 1 (grs_er21 is the alternate)",
            "dirt": "drt_er11: first exterior roll of dirt set 1 (drt_er12/13 are alternates)",
            "tarmac": "tar set 2 (tar_er21 roll with tar_s2/tar_p2/tar_l2, the cfg pairing of blocks 25/29/35): lowest modulation of the peel and lock candidates (0.73/0.88 dB), and it avoids the 0.48 s peel of set 1; tarmac is not identified by the scenario today",
            "sand": "legacy surf_sand: no CMR4 sand family exists",
            "rumble": "legacy surf_rumble: no CMR4 rumble/curb family exists; not identified by the scenario",
        },
        "samples": sorted(prepared_records, key=lambda record: record["file"]),
        "legacy": legacy,
        "retired_from_commons": RETIRED_COMMONS_FILES,
    }
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    update_sample_levels(manifest)
    print(f"prepared {len(prepared_records)} samples; manifest {MANIFEST_PATH}")
    return 0


def update_sample_levels(manifest: dict) -> None:
    """Record the surfaces level law in game/data/rally/audio_sample_levels.json (other keys untouched)."""
    levels_path = REPO_ROOT / "game" / "data" / "rally" / "audio_sample_levels.json"
    document = json.loads(levels_path.read_text(encoding="utf-8")) if levels_path.is_file() else {}
    document["surfaces"] = {
        "bank": "sounds/banks/surfaces/manifest.json",
        "baked": True,
        "target_rms_dbfs": manifest["preparation"]["target_rms_dbfs"],
        "peak_ceiling_dbfs": PEAK_CEILING_DBFS,
        "law": manifest["preparation"]["level_law"],
        "samples": {
            record["file"]: {
                "source_rms_dbfs": record["processing"]["source_rms_dbfs"],
                "gain_db": record["processing"]["gain_db"],
                "prepared_rms_dbfs": record["prepared"]["rms_dbfs"],
                "prepared_peak_dbfs": record["prepared"]["peak_dbfs"],
            }
            for record in manifest["samples"]
        },
    }
    levels_path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")


def cmd_verify(_arguments: argparse.Namespace) -> int:
    failures: list[str] = []
    source = load_raw_manifest()
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    if len(source["entries"]) != 59:
        failures.append("raw manifest does not list 59 entries")
    for entry in source["entries"]:
        raw_path = RAW_DIR / entry["name"]
        if not raw_path.is_file() or sha256_file(raw_path) != entry["sha256"]:
            failures.append(f"raw hash mismatch: {entry['name']}")
            continue
        try:
            inspect_wav(raw_path.read_bytes())
        except CmrError as error:
            failures.append(f"raw WAV invalid {entry['name']}: {error}")
    prepared_by_name = {record["original_name"]: record for record in manifest["samples"]}
    for name in (entry["name"] for entry in source["entries"]):
        if name not in prepared_by_name:
            failures.append(f"missing prepared sample: {name}")
    for record in manifest["samples"]:
        path = BANK_DIR / record["file"]
        if not path.is_file():
            failures.append(f"prepared file missing: {record['file']}")
            continue
        if sha256_file(path) != record["prepared"]["sha256"]:
            failures.append(f"prepared hash mismatch: {record['file']}")
        try:
            facts = inspect_wav(path.read_bytes())
        except CmrError as error:
            failures.append(f"prepared WAV invalid {record['file']}: {error}")
            continue
        if facts["sample_rate"] != SAMPLE_RATE or facts["channels"] != 1 or facts["bits"] != 16:
            failures.append(f"prepared format mismatch: {record['file']}")
    for surface, roles in manifest["runtime_map"].items():
        for role, relative in roles.items():
            if not (BANK_DIR / relative).is_file():
                failures.append(f"runtime map missing file: {surface}.{role} -> {relative}")
    for legacy in manifest["legacy"]:
        if sha256_file(BANK_DIR / legacy["file"]) != legacy["sha256"]:
            failures.append(f"legacy hash mismatch: {legacy['file']}")
    if COMMONS_MANIFEST.is_file():
        commons = json.loads(COMMONS_MANIFEST.read_text(encoding="utf-8"))
        remaining = {record["file"] for record in commons.get("files", [])}
        for retired in RETIRED_COMMONS_FILES:
            if retired in remaining:
                failures.append(f"retired surface still listed in commons manifest: {retired}")
            if (REPO_ROOT / "game" / "sounds" / "banks" / "commons" / retired).exists():
                failures.append(f"retired surface still present in commons: {retired}")
    # Code and data only: documentation and the surfaces manifest may name retired files as history.
    for path in (REPO_ROOT / "game").rglob("*"):
        if not path.is_file() or path.suffix not in {".gd", ".tscn", ".json", ".ps1", ".py"}:
            continue
        if "docs" in path.parts or path == MANIFEST_PATH or path == RAW_MANIFEST:
            continue
        if path == COMMONS_MANIFEST:
            continue  # its absence of retired entries is checked above
        text = path.read_text(encoding="utf-8", errors="ignore")
        for token in RETIRED_REFERENCE_TOKENS:
            if token in text:
                failures.append(f"retired reference '{token}' in {path.relative_to(REPO_ROOT).as_posix()}")
    if failures:
        for failure in failures:
            print("FAIL " + failure)
        return 1
    print(f"verified {len(source['entries'])} raw samples, {len(manifest['samples'])} prepared samples, {len(manifest['legacy'])} legacy samples")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    subcommands = parser.add_subparsers(dest="command", required=True)
    extract_parser = subcommands.add_parser("extract", help="decrypt surfaces.big into bank_sources")
    extract_parser.add_argument("--cmr4-root", default=str(DEFAULT_CMR4_ROOT))
    extract_parser.set_defaults(handler=cmd_extract)
    prepare_parser = subcommands.add_parser("prepare", help="build the runtime surfaces bank")
    prepare_parser.set_defaults(handler=cmd_prepare)
    verify_parser = subcommands.add_parser("verify", help="check hashes, formats and runtime references")
    verify_parser.set_defaults(handler=cmd_verify)
    arguments = parser.parse_args(argv)
    try:
        return arguments.handler(arguments)
    except CmrError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
