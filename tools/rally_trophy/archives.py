"""Self-contained BZF reader; based on the local verified stage exporter reader."""
from __future__ import annotations

import hashlib
import struct
import zlib
from pathlib import Path

from .common import within, write_json

KEY = bytes.fromhex(
    "8bc2698046421825805daa026d491194a801e758cb8da6303e831b094cce18bb"
    "7cae6a301e000ac924c098fd33cc0444faea8f33c30df2e847d4dca8c754a2c7"
    "581732c87f644ac6fdc1e713ecb7ff1e0bd5729a57f83fdcdbc9f385c8866862"
    "c806ab9090f73ee4b46b8089c09369eb84c97ad4afd4f4d5a06849e878edd053"
    "7481bcd07a404feaf1c34baad6e6aa730ccf8e2bf42c7b9b3ebbc419ff104364"
    "03934dcf64c8e5a25bd330bd573b2a7e4cee96e54e853bf65eca4d5f84772a5b"
    "1e4147d6771569d29ba218096a1750d4ec2e7b4be4699caea89bcd042fabeb01"
    "6c95902ddab141435938e9d73804863c939723a5df5f068ac3392a4e2933f01e"
)
PREFIX = b"(c) 2001 by JoWooD Productions Software AG\x00"


def read_bzf(path):
    raw = Path(path).read_bytes()
    if len(raw) < 12 or raw[:4] != b"bbzf":
        raise ValueError(f"Invalid BZF: {path}")
    count = struct.unpack_from("<I", raw, 8)[0]
    if count > 100000 or 12 + count * 53 > len(raw):
        raise ValueError("Invalid BZF entry table")
    header = bytes(v ^ KEY[i % 256] for i, v in enumerate(raw[12:12 + count * 53]))
    files, seen = {}, set()
    for i in range(count):
        entry = header[i * 53:(i + 1) * 53]
        flags = entry[0]
        offset, size, packed = struct.unpack_from("<III", entry, 1)
        name = entry[13:53].split(b"\0")[0].decode("latin1").replace("\\", "/")
        within(Path.cwd(), name)
        if not name or name.casefold() in seen or offset + packed > len(raw) or size > 512 * 1024 * 1024:
            raise ValueError(f"Unsafe/duplicate BZF entry: {name}")
        seen.add(name.casefold())
        data = bytes(v ^ KEY[j % 256] for j, v in enumerate(raw[offset:offset + packed]))
        if flags & 1:
            data = zlib.decompress(data)
        if len(data) not in {size, size + len(PREFIX)}:
            raise ValueError(f"BZF size mismatch: {name}: {len(data)} != {size}")
        if data.startswith(PREFIX):
            data = data[len(PREFIX):]
        files[name] = data
    return files


def get(files, name):
    return next((value for key, value in files.items() if key.casefold() == name.casefold()), None)


def extract(path, destination):
    files = read_bzf(path)
    index = {}
    for name, data in files.items():
        output = within(destination, name)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(data)
        index[name] = {"sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
    write_json(Path(destination) / "extraction.json", index)
    return files


def find_data(source):
    source = Path(source).resolve()
    for candidate in [source, source / "Data", source / "Program Files/JoWooD/Rally Trophy/Data"]:
        if (candidate / "Cars/car_1.bzf").is_file():
            return candidate
    raise FileNotFoundError(f"Rally Trophy Data/Cars not found below {source}")
