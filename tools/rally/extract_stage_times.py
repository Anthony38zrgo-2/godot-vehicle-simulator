"""Export original Rally Trophy stage timing tables without modifying archives.
Usage: python tools/rally/extract_stage_times.py --game-data <Rally Trophy/Data>
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zlib

KEY = bytes.fromhex("8bc2698046421825805daa026d491194a801e758cb8da6303e831b094cce18bb7cae6a301e000ac924c098fd33cc0444faea8f33c30df2e847d4dca8c754a2c7581732c87f644ac6fdc1e713ecb7ff1e0bd5729a57f83fdcdbc9f385c8866862c806ab9090f73ee4b46b8089c09369eb84c97ad4afd4f4d5a06849e878edd0537481bcd07a404feaf1c34baad6e6aa730ccf8e2bf42c7b9b3ebbc419ff10436403934dcf64c8e5a25bd330bd573b2a7e4cee96e54e853bf65eca4d5f84772a5b1e4147d6771569d29ba218096a1750d4ec2e7b4be4699caea89bcd042fabeb016c95902ddab141435938e9d73804863c939723a5df5f068ac3392a4e2933f01e")
PREFIX = b"(c) 2001 by JoWooD Productions Software AG\x00"

def decode_archive(path):
    raw = path.read_bytes()
    if raw[:4] != b"bbzf":
        raise ValueError(f"Invalid BZF: {path}")
    count = struct.unpack_from("<I", raw, 8)[0]
    header = bytes(v ^ KEY[i % len(KEY)] for i, v in enumerate(raw[12:12 + count * 53]))
    for i in range(count):
        entry = header[i * 53:(i + 1) * 53]
        flags = entry[0]
        offset, size, packed = struct.unpack_from("<III", entry, 1)
        name = entry[13:53].split(b"\x00")[0].decode("latin1")
        if not re.fullmatch(r"stagetimes\d+\.ini", name, re.I):
            continue
        data = bytes(v ^ KEY[j % len(KEY)] for j, v in enumerate(raw[offset:offset + packed]))
        if flags & 1:
            data = zlib.decompress(data)
        yield name, data.removeprefix(PREFIX)

def extract(game_data, output):
    output.mkdir(parents=True, exist_ok=True)
    available = unavailable = 0
    for archive in sorted((game_data / "Tracks").glob("track*/data.bzf")):
        for name, data in decode_archive(archive):
            text = data.decode("latin1").replace("\r", "")
            fields = {k: [float(x.strip()) for x in v.split(",")] for k, v in re.findall(r"^\s*(\w+)\s*=\s*\{([^}]+)\}", text, re.M)}
            valid = all(len(fields.get(f"CPUSplit{i}", [])) == 3 for i in range(10))
            index = int(re.search(r"\d+", name)[0])
            document = {"source_game": "Rally Trophy", "source_archive": archive.relative_to(game_data).as_posix(), "source_archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(), "source_file": name, "source_ini_sha256": hashlib.sha256(data).hexdigest(), "raw_ini": text, "track": archive.parent.name, "stage_index": index, "difficulty_order": ["novice", "intermediate", "expert"], "values_seconds": fields, "has_cpu_reference": valid, "fallback_status": "available_uncalibrated" if valid else "unavailable_original_has_no_cpu_splits", "usage": "Original game parameters, not a verified executable formula. Route mapping and physics calibration are design inputs."}
            (output / f"{archive.parent.name}_stage{index}.json").write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            available += valid
            unavailable += not valid
    return available, unavailable

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--game-data", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[2] / "game/data/competition/rally_trophy")
    args = parser.parse_args()
    print("CPU references available/unavailable:", extract(args.game_data, args.output))
